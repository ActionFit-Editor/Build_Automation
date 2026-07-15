#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
build_workflow="$package_root/WorkflowTemplates/buildcommit-auto-build.yml"
delivery_workflow="$package_root/WorkflowTemplates/buildcommit-slack-delivery.yml"

ruby -ryaml - "$build_workflow" "$delivery_workflow" <<'RUBY'
build_workflow_path, delivery_workflow_path = ARGV
build_workflow = YAML.load_file(build_workflow_path)
delivery_workflow = YAML.load_file(delivery_workflow_path)

abort("unexpected source workflow name") unless build_workflow.fetch("name") == "BuildCommit Auto Build"
abort("unexpected Slack delivery workflow name") unless delivery_workflow.fetch("name") == "BuildCommit Slack Delivery"

trigger = delivery_workflow["on"] || delivery_workflow[true]
workflow_run = trigger.fetch("workflow_run")
abort("delivery must follow only the BuildCommit workflow") unless workflow_run.fetch("workflows") == ["BuildCommit Auto Build"]
abort("delivery must handle start and completion events") unless workflow_run.fetch("types") == ["in_progress", "completed"]

read_only_permissions = { "actions" => "read", "contents" => "read" }
abort("delivery workflow permissions must remain read-only") unless delivery_workflow.fetch("permissions") == read_only_permissions

jobs = delivery_workflow.fetch("jobs")
abort("delivery workflow must contain one isolated job") unless jobs.keys == ["deliver"]
job = jobs.fetch("deliver")
abort("delivery job permissions must remain read-only") unless job.fetch("permissions") == read_only_permissions
expected_runner = { "group" => "slack-delivery", "labels" => "slack-delivery" }
abort("delivery job must use the dedicated runner group and label") unless job.fetch("runs-on") == expected_runner
abort("delivery timeout must remain bounded") unless job.fetch("timeout-minutes") == 15

trust_guard = job.fetch("if")
abort("delivery must reject workflow runs from another repository") unless trust_guard.include?("head_repository.full_name == github.repository")
abort("delivery must bind the exact source workflow path") unless trust_guard.include?("workflow_run.path == '.github/workflows/buildcommit-auto-build.yml'")
abort("delivery must accept trusted push requests") unless trust_guard.include?("workflow_run.event == 'push'")
abort("delivery must accept trusted manual requests") unless trust_guard.include?("workflow_run.event == 'workflow_dispatch'")

concurrency_group = delivery_workflow.dig("concurrency", "group")
abort("delivery concurrency must be unique per source run attempt") unless concurrency_group == "buildcommit-slack-delivery-${{ github.event.workflow_run.id }}-${{ github.event.workflow_run.run_attempt }}"
abort("a rerun must not cancel an active delivery") unless delivery_workflow.dig("concurrency", "cancel-in-progress") == false

environment = job.fetch("env")
abort("runner context is unavailable in job-level env") if environment.to_s.include?("runner.temp")
{
  "SOURCE_REPOSITORY" => "${{ github.event.workflow_run.head_repository.full_name }}",
  "SOURCE_SHA" => "${{ github.event.workflow_run.head_sha }}",
  "SOURCE_RUN_URL" => "${{ github.event.workflow_run.html_url }}",
  "SOURCE_RUN_ID" => "${{ github.event.workflow_run.id }}",
  "SOURCE_RUN_ATTEMPT" => "${{ github.event.workflow_run.run_attempt }}",
  "SOURCE_EVENT" => "${{ github.event.workflow_run.event }}",
  "SOURCE_RUN_STARTED_AT" => "${{ github.event.workflow_run.run_started_at }}"
}.each do |name, value|
  abort("missing host delivery environment: #{name}") unless environment[name] == value
end

steps = job.fetch("steps")
abort("delivery runner must not checkout repository code") if steps.any? { |step| step["uses"] == "actions/checkout@v4" }
unexpected_action = steps.find do |step|
  step.key?("uses") && step["uses"] != "actions/download-artifact@v4"
end
abort("delivery must not execute an unexpected action: #{unexpected_action.inspect}") if unexpected_action

initialize_paths = steps.find { |step| step["name"] == "Initialize Slack delivery paths" }
abort("Slack delivery path initialization is missing") unless initialize_paths
initialize_script = initialize_paths.fetch("run")
abort("delivery paths must use RUNNER_TEMP") unless initialize_script.include?('delivery_work_root="$RUNNER_TEMP/buildcommit-slack-delivery-')
abort("delivery paths must be passed through GITHUB_ENV") unless initialize_script.include?('>> "$GITHUB_ENV"')
abort("run identifier validation is missing") unless initialize_script.include?("run identifiers must be numeric")

fetch_request = steps.find { |step| step["id"] == "fetch_request" }
abort("BuildRequest metadata fetch is missing") unless fetch_request
abort("BuildRequest must be fetched from the immutable source SHA") unless fetch_request.fetch("run").include?("contents/.build/build_request.json?ref=${SOURCE_SHA}")
abort("source SHA validation is missing") unless fetch_request.fetch("run").include?("40 hexadecimal characters")

host_executable = "/Users/lydia/workspace/slack-delivery/bin/deliver-buildcommit-slack"
{
  "inspect" => "Inspect BuildCommit request metadata",
  "start" => "Deliver build start notification",
  "complete" => "Deliver build completion notification"
}.each do |mode, step_name|
  step = steps.find { |candidate| candidate["name"] == step_name }
  abort("missing delivery mode: #{mode}") unless step
  abort("#{mode} must call only the fixed host executable") unless step.fetch("run").include?("#{host_executable} #{mode}")
  abort("#{mode} delivery failure must not change the source build result") unless step.fetch("continue-on-error") == true
end

download = steps.find { |step| step["name"] == "Download Development APK from source run" }
abort("Development APK download is missing") unless download
expected_artifact = "Android-BuildCommit-Development-APK-${{ github.event.workflow_run.id }}-${{ github.event.workflow_run.run_attempt }}"
abort("delivery must download only the exact source run attempt artifact") unless download.dig("with", "name") == expected_artifact
abort("artifact download must target the source workflow run") unless download.dig("with", "run-id") == "${{ github.event.workflow_run.id }}"
abort("artifact download must use the workflow token") unless download.dig("with", "github-token") == "${{ github.token }}"
abort("APK download must be limited to successful Development Android builds") unless download.fetch("if").include?("development_android == 'true'") && download.fetch("if").include?("conclusion == 'success'")

forbidden_secret_access = /(?:SLACK_(?:BUILD_)?(?:WEBHOOK_URL|BOT_TOKEN|CHANNEL_ID)|slack-(?:webhook-url|bot-token|channel-id)|hooks\.slack\.com)/i
abort("delivery workflow must not contain Slack credentials") if delivery_workflow.to_s.match?(forbidden_secret_access)
RUBY

echo "Slack delivery workflow tests passed"
