#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

class TestFlightUploader
  def initialize(environment = ENV)
    @environment = environment
    @cancel_signal = nil
  end

  def run
    fastlane = resolve_fastlane
    api_key_path = readable_file("APP_STORE_CONNECT_API_KEY_JSON_PATH")
    ipa_path = readable_file("IOS_IPA_PATH")
    bundle_id = required_value("IOS_BUNDLE_ID")
    attempts = positive_integer(@environment.fetch("TESTFLIGHT_UPLOAD_ATTEMPTS", "2"), "TESTFLIGHT_UPLOAD_ATTEMPTS")
    timeout_seconds = positive_integer(
      @environment.fetch("TESTFLIGHT_UPLOAD_ATTEMPT_TIMEOUT_SECONDS", "900"),
      "TESTFLIGHT_UPLOAD_ATTEMPT_TIMEOUT_SECONDS"
    )
    retry_delay_seconds = nonnegative_integer(
      @environment.fetch("TESTFLIGHT_UPLOAD_RETRY_DELAY_SECONDS", "10"),
      "TESTFLIGHT_UPLOAD_RETRY_DELAY_SECONDS"
    )

    Signal.trap("TERM") { @cancel_signal = "TERM" }
    Signal.trap("INT") { @cancel_signal = "INT" }

    command = [
      fastlane,
      "pilot",
      "upload",
      "--api_key_path", api_key_path,
      "--app_identifier", bundle_id,
      "--ipa", ipa_path,
      "--skip_waiting_for_build_processing"
    ]

    attempts.times do |index|
      attempt = index + 1
      puts "TestFlight upload attempt #{attempt}/#{attempts}, hard timeout #{timeout_seconds}s"
      exit_code = run_attempt(command, attempt, timeout_seconds)
      return 0 if exit_code.zero?
      return 130 if @cancel_signal

      if attempt < attempts
        warn "::warning::TestFlight upload attempt #{attempt} failed with exit code #{exit_code}; starting a fresh upload session after #{retry_delay_seconds}s."
        return 130 unless interruptible_sleep(retry_delay_seconds)
      else
        warn "::error::TestFlight upload failed after #{attempts} attempt(s); last exit code #{exit_code}."
        return exit_code
      end
    end

    1
  rescue ArgumentError, KeyError => error
    warn "::error::TestFlight uploader: #{error.message}"
    1
  end

  private

  def run_attempt(command, attempt, timeout_seconds)
    temporary_root = @environment["RUNNER_TEMP"].to_s.strip
    temporary_root = Dir.tmpdir if temporary_root.empty?
    attempt_directory = Dir.mktmpdir("testflight-upload-#{attempt}-", temporary_root)
    child_pid = nil

    child_environment = {
      "TMPDIR" => "#{attempt_directory}/",
      "FASTLANE_DISABLE_COLORS" => "1",
      "FASTLANE_SKIP_UPDATE_CHECK" => "1"
    }
    child_pid = Process.spawn(child_environment, *command, pgroup: true)
    deadline = monotonic_time + timeout_seconds

    loop do
      if @cancel_signal
        terminate_and_reap(child_pid)
        warn "::warning::TestFlight upload attempt #{attempt} cancelled by #{@cancel_signal}."
        return 130
      end

      waited_pid, process_status = Process.waitpid2(child_pid, Process::WNOHANG)
      if waited_pid
        return process_status.exitstatus || 128 + process_status.termsig.to_i
      end

      if monotonic_time >= deadline
        warn "::warning::TestFlight upload attempt #{attempt} exceeded #{timeout_seconds}s; terminating pilot/altool before retry."
        terminate_and_reap(child_pid)
        return 124
      end

      sleep 0.25
    end
  rescue SystemCallError => error
    warn "::error::Failed to launch TestFlight uploader: #{error.class}: #{error.message}"
    127
  ensure
    terminate_and_reap(child_pid) if child_pid && process_alive?(child_pid)
    FileUtils.rm_rf(attempt_directory) if defined?(attempt_directory) && attempt_directory
  end

  def terminate_and_reap(child_pid)
    return unless child_pid

    terminate_process_group(child_pid, "TERM")
    deadline = monotonic_time + 5
    loop do
      waited_pid, = Process.waitpid2(child_pid, Process::WNOHANG)
      return if waited_pid
      break if monotonic_time >= deadline

      sleep 0.1
    end

    terminate_process_group(child_pid, "KILL")
    Process.waitpid(child_pid)
  rescue Errno::ECHILD, Errno::ESRCH
    nil
  end

  def terminate_process_group(pid, signal)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def interruptible_sleep(seconds)
    deadline = monotonic_time + seconds
    while monotonic_time < deadline
      return false if @cancel_signal

      sleep [0.25, deadline - monotonic_time].min
    end
    true
  end

  def resolve_fastlane
    configured = @environment["FASTLANE_CMD"].to_s.strip
    return configured if !configured.empty? && File.executable?(configured)

    %w[/opt/homebrew/bin/fastlane /usr/local/bin/fastlane].each do |path|
      return path if File.executable?(path)
    end

    path = search_path("fastlane")
    return path if path

    raise ArgumentError, "fastlane is required on the self-hosted macOS runner"
  end

  def search_path(executable)
    @environment.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
      candidate = File.join(directory, executable)
      return candidate if File.executable?(candidate) && !File.directory?(candidate)
    end
    nil
  end

  def readable_file(name)
    path = required_value(name)
    raise ArgumentError, "#{name} is not readable: #{path}" unless File.file?(path) && File.readable?(path)

    path
  end

  def required_value(name)
    value = @environment[name].to_s.strip
    raise ArgumentError, "#{name} is required" if value.empty?

    value
  end

  def positive_integer(value, name)
    parsed = Integer(value, 10)
    raise ArgumentError, "#{name} must be positive: #{value.inspect}" unless parsed.positive?

    parsed
  rescue TypeError, ArgumentError
    raise ArgumentError, "#{name} must be a positive integer: #{value.inspect}"
  end

  def nonnegative_integer(value, name)
    parsed = Integer(value, 10)
    raise ArgumentError, "#{name} must not be negative: #{value.inspect}" if parsed.negative?

    parsed
  rescue TypeError, ArgumentError
    raise ArgumentError, "#{name} must be a nonnegative integer: #{value.inspect}"
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

exit(TestFlightUploader.new.run)
