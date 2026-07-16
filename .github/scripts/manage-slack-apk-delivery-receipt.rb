#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "time"

SCHEMA_VERSION = 1
EXIT_INVALID = 2
EXIT_MISSING = 3
EXIT_PENDING = 4
EXIT_DELIVERED = 5
MAX_RECEIPT_BYTES = 64 * 1024
DIRECTORY_MODE = 0o700
FILE_MODE = 0o600
REPOSITORY_PATTERN = /\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/.freeze
SHA_PATTERN = /\A[0-9a-f]{40,64}\z/.freeze
FILE_ID_PATTERN = /\AF[A-Z0-9]+\z/.freeze

class ReceiptError < StandardError; end

class SlackApkDeliveryReceiptStore
  def initialize
    @secret_root = required_absolute_path("CI_SECRET_ROOT")
    @repository = required_value("GITHUB_REPOSITORY").downcase
    @run_id = canonical_positive_integer("GITHUB_RUN_ID")
    @run_attempt = Integer(canonical_positive_integer("GITHUB_RUN_ATTEMPT"), 10)
    @source_sha = required_value("GITHUB_SHA").downcase

    unless @repository.match?(REPOSITORY_PATTERN) && @repository.split("/").none? { |part| part == "." || part == ".." }
      raise ReceiptError, "GITHUB_REPOSITORY is invalid"
    end
    raise ReceiptError, "GITHUB_SHA must be a 40-64 character hexadecimal commit ID" unless @source_sha.match?(SHA_PATTERN)

    identity_digest = Digest::SHA256.hexdigest("#{@repository}\0#{@run_id}")
    @state_root = File.join(@secret_root, "state")
    @receipt_root = File.join(@state_root, "slack-apk-delivery")
    @receipt_path = File.join(@receipt_root, "#{identity_digest}.json")
    @lock_path = File.join(@receipt_root, ".#{identity_digest}.lock")
  rescue ArgumentError
    raise ReceiptError, "GITHUB_RUN_ID and GITHUB_RUN_ATTEMPT must be positive integers"
  end

  attr_reader :receipt_path

  def prepare!
    validate_secret_root!
    ensure_private_directory!(@state_root)
    ensure_private_directory!(@receipt_root)
  end

  def with_lock
    prepare!
    flags = File::RDWR | File::NOFOLLOW
    lock = begin
      File.open(@lock_path, flags | File::CREAT | File::EXCL, FILE_MODE)
    rescue Errno::EEXIST
      File.open(@lock_path, flags)
    end

    begin
      validate_open_file!(lock, @lock_path, FILE_MODE)
      raise ReceiptError, "could not lock receipt state" unless lock.flock(File::LOCK_EX)

      validate_private_directory!(@receipt_root)
      yield
    ensure
      lock.close
    end
  rescue Errno::ELOOP
    raise ReceiptError, "receipt lock must not be a symbolic link"
  rescue SystemCallError => error
    raise ReceiptError, "receipt lock failed: #{error.message}"
  end

  def lookup
    with_lock do
      receipt = read_receipt
      exit_with("Slack APK delivery receipt is missing: #{@receipt_path}", EXIT_MISSING) unless receipt

      case receipt.fetch("state")
      when "delivered"
        puts receipt.fetch("file_id")
      when "pending"
        if receipt.fetch("completion_attempted")
          file_id = receipt.fetch("file_id")
          exit_with(
            "Slack APK delivery is pending after a completion attempt: #{@receipt_path} (file_id=#{file_id}); reconcile manually",
            EXIT_PENDING
          )
        end
        exit_with(
          "Slack APK delivery is pending before completion: #{@receipt_path}; discard is required before retry",
          EXIT_PENDING
        )
      end
    end
  end

  def begin_delivery
    with_lock do
      receipt = read_receipt
      if receipt.nil?
        now = timestamp
        atomic_write(
          "schema_version" => SCHEMA_VERSION,
          "repository" => @repository,
          "run_id" => @run_id,
          "run_attempt" => @run_attempt,
          "source_sha" => @source_sha,
          "state" => "pending",
          "completion_attempted" => false,
          "created_at" => now,
          "updated_at" => now
        )
        puts "pending"
        next
      end

      if receipt.fetch("state") == "delivered"
        puts receipt.fetch("file_id")
        exit_with("Slack APK was already delivered for this workflow run", EXIT_DELIVERED)
      end
      if receipt.fetch("completion_attempted")
        exit_with(
          "Slack APK delivery has an unresolved completion attempt (file_id=#{receipt.fetch("file_id")})",
          EXIT_PENDING
        )
      end
      if receipt.fetch("run_attempt") != @run_attempt
        exit_with(
          "an unarmed pending receipt from run attempt #{receipt.fetch("run_attempt")} must be discarded before attempt #{@run_attempt}",
          EXIT_PENDING
        )
      end

      puts "pending"
    end
  end

  def arm(file_id)
    validate_file_id!(file_id)
    with_lock do
      receipt = required_receipt
      if receipt.fetch("state") == "delivered"
        puts receipt.fetch("file_id")
        exit_with("Slack APK was already delivered for this workflow run", EXIT_DELIVERED)
      end
      if receipt.fetch("completion_attempted")
        exit_with(
          "Slack APK delivery already has an unresolved completion attempt (file_id=#{receipt.fetch("file_id")})",
          EXIT_PENDING
        )
      end
      if receipt.fetch("run_attempt") != @run_attempt
        exit_with(
          "an unarmed pending receipt from run attempt #{receipt.fetch("run_attempt")} must be discarded before arming attempt #{@run_attempt}",
          EXIT_PENDING
        )
      end

      now = timestamp
      armed = receipt.merge(
        "completion_attempted" => true,
        "file_id" => file_id,
        "completion_attempted_at" => now,
        "updated_at" => now
      )
      atomic_write(armed)
      puts file_id
    end
  end

  def complete(file_id)
    validate_file_id!(file_id)
    with_lock do
      receipt = required_receipt
      if receipt.fetch("state") == "delivered"
        unless receipt.fetch("file_id") == file_id
          raise ReceiptError, "delivered receipt file ID does not match #{file_id}"
        end

        puts file_id
        next
      end
      raise ReceiptError, "pending receipt is not armed for Slack completion" unless receipt.fetch("completion_attempted")
      unless receipt.fetch("file_id") == file_id
        raise ReceiptError, "armed receipt file ID does not match #{file_id}"
      end

      now = timestamp
      delivered = receipt.merge(
        "state" => "delivered",
        "delivered_at" => now,
        "updated_at" => now
      )
      atomic_write(delivered)
      puts file_id
    end
  end

  def discard
    with_lock do
      receipt = read_receipt
      if receipt.nil?
        puts "missing"
        next
      end
      if receipt.fetch("state") == "delivered"
        puts receipt.fetch("file_id")
        exit_with("delivered Slack APK receipt must not be discarded", EXIT_DELIVERED)
      end
      if receipt.fetch("completion_attempted")
        exit_with(
          "armed Slack APK receipt must not be discarded (file_id=#{receipt.fetch("file_id")}); reconcile manually",
          EXIT_PENDING
        )
      end

      File.unlink(@receipt_path)
      sync_directory
      puts "discarded"
    end
  end

  private

  def required_value(name)
    value = ENV.fetch(name, "").strip
    raise ReceiptError, "#{name} is required" if value.empty?

    value
  end

  def required_absolute_path(name)
    value = required_value(name)
    raise ReceiptError, "#{name} must be an absolute path" unless value.start_with?(File::SEPARATOR)

    File.expand_path(value)
  end

  def canonical_positive_integer(name)
    value = required_value(name)
    raise ReceiptError, "#{name} must be a positive integer" unless value.match?(/\A[1-9][0-9]*\z/)

    Integer(value, 10).to_s
  end

  def validate_file_id!(file_id)
    raise ReceiptError, "Slack file ID is invalid" unless file_id && file_id.match?(FILE_ID_PATTERN)
  end

  def validate_secret_root!
    current = File::SEPARATOR
    @secret_root.split(File::SEPARATOR).reject(&:empty?).each do |component|
      current = File.join(current, component)
      stat = File.lstat(current)
      next unless stat.symlink?

      # macOS commonly exposes root-owned compatibility links such as /var.
      # User-owned links, and a linked CI_SECRET_ROOT itself, are not trusted.
      if current == @secret_root || stat.uid != 0
        raise ReceiptError, "CI_SECRET_ROOT path must not contain user-controlled symbolic links: #{current}"
      end
    end

    stat = File.lstat(@secret_root)
    raise ReceiptError, "CI_SECRET_ROOT must be a directory" unless stat.directory?
    raise ReceiptError, "CI_SECRET_ROOT must be owned by uid #{Process.uid}" unless stat.uid == Process.uid
    if (stat.mode & 0o022) != 0
      raise ReceiptError, "CI_SECRET_ROOT must not be writable by group or other users"
    end
  rescue Errno::ENOENT
    raise ReceiptError, "CI_SECRET_ROOT does not exist: #{@secret_root}"
  end

  def ensure_private_directory!(path)
    begin
      Dir.mkdir(path, DIRECTORY_MODE)
      File.chmod(DIRECTORY_MODE, path)
      sync_parent_directory(path)
    rescue Errno::EEXIST
      # Validated below. Never follow an existing link or accept weak ownership.
    end
    validate_private_directory!(path)
  rescue SystemCallError => error
    raise ReceiptError, "could not prepare receipt directory #{path}: #{error.message}"
  end

  def validate_private_directory!(path)
    stat = File.lstat(path)
    raise ReceiptError, "receipt state path must not be a symbolic link: #{path}" if stat.symlink?
    raise ReceiptError, "receipt state path is not a directory: #{path}" unless stat.directory?
    raise ReceiptError, "receipt state directory has an unexpected owner: #{path}" unless stat.uid == Process.uid
    unless (stat.mode & 0o777) == DIRECTORY_MODE
      raise ReceiptError, format("receipt state directory must have mode 0700: %s (found %04o)", path, stat.mode & 0o777)
    end
  end

  def required_receipt
    read_receipt || exit_with("Slack APK delivery receipt is missing: #{@receipt_path}", EXIT_MISSING)
  end

  def read_receipt
    stat = begin
      File.lstat(@receipt_path)
    rescue Errno::ENOENT
      return nil
    end
    validate_file_stat!(stat, @receipt_path, FILE_MODE)
    raise ReceiptError, "receipt exceeds #{MAX_RECEIPT_BYTES} bytes" if stat.size > MAX_RECEIPT_BYTES

    flags = File::RDONLY | File::NOFOLLOW
    content = File.open(@receipt_path, flags) do |file|
      validate_open_file!(file, @receipt_path, FILE_MODE, stat)
      file.read(MAX_RECEIPT_BYTES + 1)
    end
    raise ReceiptError, "receipt exceeds #{MAX_RECEIPT_BYTES} bytes" if content.bytesize > MAX_RECEIPT_BYTES

    receipt = JSON.parse(content)
    validate_receipt!(receipt)
    receipt
  rescue Errno::ELOOP
    raise ReceiptError, "receipt must not be a symbolic link: #{@receipt_path}"
  rescue JSON::ParserError => error
    raise ReceiptError, "receipt is not valid JSON: #{error.message}"
  end

  def validate_receipt!(receipt)
    raise ReceiptError, "receipt root must be a JSON object" unless receipt.is_a?(Hash)

    base_keys = %w[
      schema_version repository run_id run_attempt source_sha state
      completion_attempted created_at updated_at
    ]
    state = receipt["state"]
    expected_keys = case state
                    when "pending"
                      receipt["completion_attempted"] == true ? base_keys + %w[file_id completion_attempted_at] : base_keys
                    when "delivered"
                      base_keys + %w[file_id completion_attempted_at delivered_at]
                    else
                      raise ReceiptError, "receipt state is invalid"
                    end
    unless receipt.keys.sort == expected_keys.sort
      raise ReceiptError, "receipt schema contains missing or unexpected fields"
    end

    raise ReceiptError, "receipt schema version is unsupported" unless receipt["schema_version"] == SCHEMA_VERSION
    raise ReceiptError, "receipt repository does not match this workflow" unless receipt["repository"] == @repository
    raise ReceiptError, "receipt run ID does not match this workflow" unless receipt["run_id"] == @run_id
    unless receipt["run_attempt"].is_a?(Integer) && receipt["run_attempt"].positive? && receipt["run_attempt"] <= @run_attempt
      raise ReceiptError, "receipt run attempt is invalid for this workflow attempt"
    end
    raise ReceiptError, "receipt source SHA does not match this workflow" unless receipt["source_sha"] == @source_sha
    unless receipt["completion_attempted"] == true || receipt["completion_attempted"] == false
      raise ReceiptError, "receipt completion_attempted must be boolean"
    end
    if state == "delivered" && receipt["completion_attempted"] != true
      raise ReceiptError, "delivered receipt must record a completion attempt"
    end

    %w[created_at updated_at completion_attempted_at delivered_at].each do |field|
      next unless receipt.key?(field)

      validate_timestamp!(receipt[field], field)
    end
    validate_file_id!(receipt["file_id"]) if receipt.key?("file_id")
    validate_timestamp_order!(receipt)
  end

  def validate_timestamp!(value, field)
    raise ReceiptError, "receipt #{field} is invalid" unless value.is_a?(String)

    parsed = Time.iso8601(value)
    raise ReceiptError, "receipt #{field} must be UTC" unless parsed.utc_offset.zero? && value.end_with?("Z")
  rescue ArgumentError
    raise ReceiptError, "receipt #{field} is invalid"
  end

  def validate_timestamp_order!(receipt)
    created = Time.iso8601(receipt.fetch("created_at"))
    updated = Time.iso8601(receipt.fetch("updated_at"))
    raise ReceiptError, "receipt updated_at predates created_at" if updated < created

    if receipt.key?("completion_attempted_at")
      attempted = Time.iso8601(receipt.fetch("completion_attempted_at"))
      raise ReceiptError, "receipt completion_attempted_at predates created_at" if attempted < created
      raise ReceiptError, "receipt completion_attempted_at follows updated_at" if attempted > updated
    end
    return unless receipt.key?("delivered_at")

    delivered = Time.iso8601(receipt.fetch("delivered_at"))
    attempted = Time.iso8601(receipt.fetch("completion_attempted_at"))
    raise ReceiptError, "receipt delivered_at predates completion_attempted_at" if delivered < attempted
    raise ReceiptError, "receipt delivered_at follows updated_at" if delivered > updated
  end

  def validate_open_file!(file, path, expected_mode, prior_stat = nil)
    stat = file.stat
    validate_file_stat!(stat, path, expected_mode)
    if prior_stat && (stat.dev != prior_stat.dev || stat.ino != prior_stat.ino)
      raise ReceiptError, "receipt changed while it was being opened: #{path}"
    end
  end

  def validate_file_stat!(stat, path, expected_mode)
    raise ReceiptError, "state file is not regular: #{path}" unless stat.file?
    raise ReceiptError, "state file has an unexpected owner: #{path}" unless stat.uid == Process.uid
    unless (stat.mode & 0o777) == expected_mode
      raise ReceiptError, format("state file must have mode %04o: %s (found %04o)", expected_mode, path, stat.mode & 0o777)
    end
    raise ReceiptError, "state file must not have hard links: #{path}" unless stat.nlink == 1
  end

  def atomic_write(receipt)
    validate_receipt!(receipt)
    payload = JSON.generate(receipt) + "\n"
    raise ReceiptError, "receipt exceeds #{MAX_RECEIPT_BYTES} bytes" if payload.bytesize > MAX_RECEIPT_BYTES

    temp_path = File.join(@receipt_root, ".receipt-#{Process.pid}-#{SecureRandom.hex(12)}.tmp")
    flags = File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW
    begin
      File.open(temp_path, flags, FILE_MODE) do |file|
        file.write(payload)
        file.flush
        file.fsync
        validate_open_file!(file, temp_path, FILE_MODE)
      end
      if File.exist?(@receipt_path) || File.symlink?(@receipt_path)
        destination = File.lstat(@receipt_path)
        raise ReceiptError, "receipt destination must not be a symbolic link" if destination.symlink?
        validate_file_stat!(destination, @receipt_path, FILE_MODE)
      end
      File.rename(temp_path, @receipt_path)
      sync_directory
      validate_file_stat!(File.lstat(@receipt_path), @receipt_path, FILE_MODE)
    ensure
      File.unlink(temp_path) if File.exist?(temp_path) || File.symlink?(temp_path)
    end
  rescue SystemCallError => error
    raise ReceiptError, "could not persist Slack APK delivery receipt: #{error.message}"
  end

  def sync_parent_directory(path)
    sync_directory_path(File.dirname(path))
  end

  def sync_directory
    sync_directory_path(@receipt_root)
  end

  def sync_directory_path(path)
    File.open(path, File::RDONLY) { |directory| directory.fsync }
  rescue SystemCallError => error
    unsupported = [Errno::EINVAL::Errno]
    unsupported << Errno::ENOTSUP::Errno if defined?(Errno::ENOTSUP)
    unsupported << Errno::EOPNOTSUPP::Errno if defined?(Errno::EOPNOTSUPP)
    raise unless unsupported.include?(error.errno)

    # Some macOS SMB mounts do not expose directory fsync. File fsync and the
    # same-directory atomic rename remain enforced in that environment.
  end

  def timestamp
    Time.now.utc.iso8601(6)
  end

  def exit_with(message, code)
    warn message
    exit code
  end
end

def usage
  warn <<~USAGE
    Usage: manage-slack-apk-delivery-receipt.rb <operation> [SLACK_FILE_ID]
      lookup            exit 0 and print file_id only when delivered; 3 if missing; 4 if pending
      begin             create or resume an unarmed pending receipt
      arm FILE_ID       persist completion-attempt metadata immediately before the Slack completion API call
      complete FILE_ID  mark an armed receipt delivered; repeated completion with the same ID is idempotent
      discard           remove only a pending receipt that has not been armed

    Exit codes: 0 success, 2 invalid/security/schema error, 3 missing,
                4 unresolved pending, 5 operation blocked by delivered state.
  USAGE
end

begin
  operation = ARGV.shift
  if operation.nil? || ARGV.length > (operation == "arm" || operation == "complete" ? 1 : 0)
    usage
    exit EXIT_INVALID
  end

  store = SlackApkDeliveryReceiptStore.new
  case operation
  when "lookup"
    raise ReceiptError, "lookup does not accept a Slack file ID" unless ARGV.empty?
    store.lookup
  when "begin"
    raise ReceiptError, "begin does not accept a Slack file ID" unless ARGV.empty?
    store.begin_delivery
  when "arm"
    raise ReceiptError, "arm requires exactly one Slack file ID" unless ARGV.length == 1
    store.arm(ARGV.fetch(0))
  when "complete"
    raise ReceiptError, "complete requires exactly one Slack file ID" unless ARGV.length == 1
    store.complete(ARGV.fetch(0))
  when "discard"
    raise ReceiptError, "discard does not accept a Slack file ID" unless ARGV.empty?
    store.discard
  else
    usage
    exit EXIT_INVALID
  end
rescue ReceiptError => error
  warn "Slack APK delivery receipt error: #{error.message}"
  exit EXIT_INVALID
rescue SystemCallError => error
  warn "Slack APK delivery receipt I/O error: #{error.message}"
  exit EXIT_INVALID
end
