#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require "time"

class StoreUploadWorker
  TERMINAL_STATES = %w[succeeded failed timed_out cancelled].freeze
  TASK_PATTERN = /\A[a-z][a-z0-9-]{0,31}\z/
  MAX_LOG_BYTES = 2 * 1024 * 1024

  def initialize(environment = ENV)
    @environment = environment
  end

  def run(arguments)
    command = arguments.shift
    case command
    when "start"
      start(arguments)
    when "wait"
      wait(arguments)
    when "cancel"
      cancel(arguments)
    when "status"
      status(arguments)
    when "__supervise"
      supervise(arguments)
    else
      raise ArgumentError, "Usage: store-upload-worker.rb <start|wait|cancel|status> ..."
    end
  rescue ArgumentError, KeyError, JSON::ParserError => error
    warn "::error::Store upload worker: #{error.message}"
    1
  end

  private

  def start(arguments)
    task = fetch_task(arguments)
    timeout_seconds = positive_integer(arguments.shift, "timeout seconds")
    separator = arguments.shift
    raise ArgumentError, "start requires -- before the uploader command" unless separator == "--"
    raise ArgumentError, "start requires an uploader command" if arguments.empty?

    directory = task_directory(task)
    if File.exist?(directory)
      raise ArgumentError, "upload task already exists: #{task}"
    end

    FileUtils.mkdir_p(directory, mode: 0o700)
    File.chmod(0o700, directory)
    File.open(log_path(directory), File::WRONLY | File::CREAT | File::TRUNC, 0o600) {}

    started_at_epoch = Time.now.to_i
    supervisor_pid = Process.spawn(
      RbConfig.ruby,
      File.expand_path(__FILE__),
      "__supervise",
      directory,
      timeout_seconds.to_s,
      started_at_epoch.to_s,
      "--",
      *arguments,
      pgroup: true,
      in: File::NULL,
      out: File::NULL,
      err: File::NULL,
      close_others: true
    )
    Process.detach(supervisor_pid)
    atomic_write(pid_path(directory), "#{supervisor_pid}\n")

    deadline = monotonic_time + 10
    until File.exist?(state_path(directory))
      unless process_alive?(supervisor_pid)
        raise ArgumentError, "upload supervisor exited before initialization: #{task}"
      end
      raise ArgumentError, "timed out starting upload supervisor: #{task}" if monotonic_time >= deadline

      sleep 0.05
    end

    puts "Store upload started: task=#{task}, supervisor_pid=#{supervisor_pid}, timeout=#{timeout_seconds}s"
    0
  end

  def wait(arguments)
    task = fetch_task(arguments)
    raise ArgumentError, "unexpected wait arguments: #{arguments.join(' ')}" unless arguments.empty?

    directory = task_directory(task)
    raise ArgumentError, "upload task does not exist: #{task}" unless File.directory?(directory)

    poll_seconds = positive_number(@environment.fetch("STORE_UPLOAD_POLL_SECONDS", "5"), "poll seconds")
    last_notice_at = 0.0

    loop do
      state = read_state(directory)
      if state && TERMINAL_STATES.include?(state.fetch("state"))
        print_log(task, directory)
        return terminal_exit_code(task, state)
      end

      supervisor_pid = read_pid(directory)
      if supervisor_pid && !process_alive?(supervisor_pid)
        sleep 0.25
        state = read_state(directory)
        unless state && TERMINAL_STATES.include?(state.fetch("state"))
          print_log(task, directory)
          warn "::error::Store upload supervisor exited without a terminal state: #{task}"
          return 1
        end
        next
      end

      if monotonic_time - last_notice_at >= 30
        current_state = state ? state.fetch("state") : "starting"
        puts "Waiting for store upload: task=#{task}, state=#{current_state}"
        last_notice_at = monotonic_time
      end
      sleep poll_seconds
    end
  end

  def cancel(arguments)
    task = fetch_task(arguments)
    raise ArgumentError, "unexpected cancel arguments: #{arguments.join(' ')}" unless arguments.empty?

    directory = task_directory(task)
    return 0 unless File.directory?(directory)

    state = read_state(directory)
    return 0 if state && TERMINAL_STATES.include?(state.fetch("state"))

    supervisor_pid = read_pid(directory)
    unless supervisor_pid && process_alive?(supervisor_pid)
      write_forced_cancel_state(directory, state, "supervisor was not running")
      return 0
    end

    unless supervisor_process_matches?(supervisor_pid, directory)
      warn "::error::Refusing to terminate an unrelated process for upload task #{task}: #{supervisor_pid}"
      return 1
    end

    Process.kill("TERM", supervisor_pid)
    deadline = monotonic_time + 15
    while process_alive?(supervisor_pid) && monotonic_time < deadline
      sleep 0.25
    end

    if process_alive?(supervisor_pid)
      child_pid = state && integer_or_nil(state["process_pid"])
      terminate_process_group(child_pid, "KILL") if child_pid
      Process.kill("KILL", supervisor_pid)
    end

    sleep 0.1
    final_state = read_state(directory)
    unless final_state && TERMINAL_STATES.include?(final_state.fetch("state"))
      write_forced_cancel_state(directory, final_state || state, "cancelled by workflow cleanup")
    end

    puts "Store upload cancelled or already stopped: task=#{task}"
    0
  rescue Errno::ESRCH
    write_forced_cancel_state(directory, state, "supervisor exited during cancellation") if directory
    0
  end

  def status(arguments)
    task = fetch_task(arguments)
    raise ArgumentError, "unexpected status arguments: #{arguments.join(' ')}" unless arguments.empty?

    directory = task_directory(task)
    state = read_state(directory)
    raise ArgumentError, "upload task state does not exist: #{task}" unless state

    puts JSON.pretty_generate(state)
    0
  end

  def supervise(arguments)
    directory = File.expand_path(arguments.shift.to_s)
    timeout_seconds = positive_integer(arguments.shift, "timeout seconds")
    started_at_epoch = positive_integer(arguments.shift, "start epoch")
    separator = arguments.shift
    raise ArgumentError, "supervisor requires -- before the uploader command" unless separator == "--"
    raise ArgumentError, "supervisor requires an uploader command" if arguments.empty?

    FileUtils.mkdir_p(directory, mode: 0o700)
    cancelled_signal = nil
    child_pid = nil
    Signal.trap("TERM") { cancelled_signal = "TERM" }
    Signal.trap("INT") { cancelled_signal = "INT" }

    initial_state = state_payload(
      "running",
      started_at_epoch,
      timeout_seconds,
      supervisor_pid: Process.pid,
      process_pid: nil
    )
    atomic_write_json(state_path(directory), initial_state)

    File.open(log_path(directory), "ab", 0o600) do |log|
      log.sync = true
      log.puts("[store-upload-worker] uploader started at #{Time.at(started_at_epoch).utc.iso8601}")

      begin
        child_pid = Process.spawn(
          *arguments,
          pgroup: true,
          in: File::NULL,
          out: log,
          err: log,
          close_others: true
        )
        atomic_write_json(
          state_path(directory),
          initial_state.merge("process_pid" => child_pid, "updated_at" => Time.now.utc.iso8601)
        )

        result = supervise_child(child_pid, started_at_epoch, timeout_seconds, -> { cancelled_signal })
        log.puts("[store-upload-worker] uploader finished: state=#{result.fetch('state')}, exit_code=#{result.fetch('exit_code')}")
        atomic_write_json(
          state_path(directory),
          state_payload(
            result.fetch("state"),
            started_at_epoch,
            timeout_seconds,
            supervisor_pid: Process.pid,
            process_pid: child_pid,
            exit_code: result.fetch("exit_code"),
            detail: result["detail"]
          )
        )
      rescue SystemCallError => error
        terminate_and_reap(child_pid) if child_pid
        log.puts("[store-upload-worker] failed to start uploader: #{error.class}: #{error.message}")
        atomic_write_json(
          state_path(directory),
          state_payload(
            "failed",
            started_at_epoch,
            timeout_seconds,
            supervisor_pid: Process.pid,
            process_pid: child_pid,
            exit_code: 127,
            detail: error.message
          )
        )
      rescue StandardError => error
        terminate_and_reap(child_pid) if child_pid
        log.puts("[store-upload-worker] supervisor failure: #{error.class}: #{error.message}")
        atomic_write_json(
          state_path(directory),
          state_payload(
            "failed",
            started_at_epoch,
            timeout_seconds,
            supervisor_pid: Process.pid,
            process_pid: child_pid,
            exit_code: 1,
            detail: error.message
          )
        )
      end
    end

    0
  end

  def supervise_child(child_pid, started_at_epoch, timeout_seconds, cancelled_signal)
    deadline = started_at_epoch + timeout_seconds

    loop do
      if cancelled_signal.call
        terminate_and_reap(child_pid)
        return { "state" => "cancelled", "exit_code" => 130, "detail" => "received #{cancelled_signal.call}" }
      end

      if Time.now.to_i >= deadline
        terminate_and_reap(child_pid)
        return { "state" => "timed_out", "exit_code" => 124, "detail" => "exceeded #{timeout_seconds}s" }
      end

      waited_pid, process_status = Process.waitpid2(child_pid, Process::WNOHANG)
      if waited_pid
        exit_code = process_status.exitstatus || 128 + process_status.termsig.to_i
        return {
          "state" => exit_code.zero? ? "succeeded" : "failed",
          "exit_code" => exit_code
        }
      end

      sleep 0.25
    end
  rescue Errno::ECHILD
    { "state" => "failed", "exit_code" => 1, "detail" => "uploader process was not waitable" }
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

  def terminal_exit_code(task, state)
    state_name = state.fetch("state")
    exit_code = integer_or_nil(state["exit_code"])
    case state_name
    when "succeeded"
      puts "Store upload succeeded: task=#{task}"
      0
    when "failed"
      code = exit_code && exit_code.between?(1, 255) ? exit_code : 1
      warn "::error::Store upload failed: task=#{task}, exit_code=#{code}"
      code
    when "timed_out"
      warn "::error::Store upload timed out: task=#{task}"
      124
    when "cancelled"
      warn "::error::Store upload was cancelled: task=#{task}"
      130
    else
      1
    end
  end

  def state_payload(state, started_at_epoch, timeout_seconds, supervisor_pid:, process_pid:, exit_code: nil, detail: nil)
    payload = {
      "schema_version" => 1,
      "state" => state,
      "started_at" => Time.at(started_at_epoch).utc.iso8601,
      "started_at_epoch" => started_at_epoch,
      "updated_at" => Time.now.utc.iso8601,
      "timeout_seconds" => timeout_seconds,
      "supervisor_pid" => supervisor_pid,
      "process_pid" => process_pid
    }
    if TERMINAL_STATES.include?(state)
      payload["completed_at"] = Time.now.utc.iso8601
      payload["exit_code"] = exit_code
    end
    payload["detail"] = detail if detail && !detail.empty?
    payload
  end

  def write_forced_cancel_state(directory, previous_state, detail)
    previous_state ||= {}
    started_at_epoch = integer_or_nil(previous_state["started_at_epoch"]) || Time.now.to_i
    timeout_seconds = integer_or_nil(previous_state["timeout_seconds"]) || 1
    atomic_write_json(
      state_path(directory),
      state_payload(
        "cancelled",
        started_at_epoch,
        timeout_seconds,
        supervisor_pid: integer_or_nil(previous_state["supervisor_pid"]),
        process_pid: integer_or_nil(previous_state["process_pid"]),
        exit_code: 130,
        detail: detail
      )
    )
  end

  def print_log(task, directory)
    path = log_path(directory)
    return unless File.file?(path)

    data = File.binread(path)
    truncated = data.bytesize > MAX_LOG_BYTES
    data = data.byteslice(data.bytesize - MAX_LOG_BYTES, MAX_LOG_BYTES) if truncated
    puts "::group::#{task} store upload log#{truncated ? ' (tail)' : ''}"
    $stdout.write(data)
    puts unless data.end_with?("\n")
    puts "::endgroup::"
  end

  def state_root
    configured = @environment["STORE_UPLOAD_STATE_ROOT"].to_s.strip
    return File.expand_path(configured) unless configured.empty?

    runner_temp = @environment.fetch("RUNNER_TEMP")
    run_id = @environment.fetch("GITHUB_RUN_ID")
    run_attempt = @environment.fetch("GITHUB_RUN_ATTEMPT")
    raise ArgumentError, "GITHUB_RUN_ID must be numeric" unless run_id.match?(/\A[0-9]+\z/)
    raise ArgumentError, "GITHUB_RUN_ATTEMPT must be numeric" unless run_attempt.match?(/\A[0-9]+\z/)

    File.join(File.expand_path(runner_temp), "buildcommit-store-upload-#{run_id}-#{run_attempt}")
  end

  def task_directory(task)
    File.join(state_root, task)
  end

  def fetch_task(arguments)
    task = arguments.shift.to_s
    raise ArgumentError, "invalid upload task name: #{task.inspect}" unless task.match?(TASK_PATTERN)

    task
  end

  def read_state(directory)
    path = state_path(directory)
    return nil unless File.file?(path)

    JSON.parse(File.read(path))
  end

  def read_pid(directory)
    state = read_state(directory)
    state_pid = state && integer_or_nil(state["supervisor_pid"])
    return state_pid if state_pid

    return nil unless File.file?(pid_path(directory))

    integer_or_nil(File.read(pid_path(directory)).strip)
  end

  def supervisor_process_matches?(pid, directory)
    output = IO.popen(["/bin/ps", "-p", pid.to_s, "-o", "command="], &:read)
    output.include?(File.basename(__FILE__)) && output.include?("__supervise") && output.include?(directory)
  rescue SystemCallError
    false
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def atomic_write_json(path, payload)
    atomic_write(path, "#{JSON.pretty_generate(payload)}\n")
  end

  def atomic_write(path, content)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    temporary_path = "#{path}.tmp-#{Process.pid}-#{rand(1_000_000)}"
    File.open(temporary_path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
      file.write(content)
      file.flush
      file.fsync
    end
    File.rename(temporary_path, path)
  ensure
    FileUtils.rm_f(temporary_path) if defined?(temporary_path) && temporary_path
  end

  def positive_integer(value, label)
    parsed = Integer(value, 10)
    raise ArgumentError, "#{label} must be positive" unless parsed.positive?

    parsed
  rescue TypeError, ArgumentError
    raise ArgumentError, "#{label} must be a positive integer: #{value.inspect}"
  end

  def positive_number(value, label)
    parsed = Float(value)
    raise ArgumentError, "#{label} must be positive" unless parsed.positive?

    parsed
  rescue TypeError, ArgumentError
    raise ArgumentError, "#{label} must be a positive number: #{value.inspect}"
  end

  def integer_or_nil(value)
    return value if value.is_a?(Integer)

    Integer(value, 10)
  rescue TypeError, ArgumentError
    nil
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def state_path(directory)
    File.join(directory, "state.json")
  end

  def pid_path(directory)
    File.join(directory, "supervisor.pid")
  end

  def log_path(directory)
    File.join(directory, "upload.log")
  end
end

exit(StoreUploadWorker.new.run(ARGV))
