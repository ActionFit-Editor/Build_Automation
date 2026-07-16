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
abort("workflow-level permissions must remain read-only") unless delivery_workflow.fetch("permissions") == read_only_permissions

jobs = delivery_workflow.fetch("jobs")
abort("delivery workflow must isolate delivery from Artifact cleanup") unless jobs.keys == ["deliver", "cleanup"]
job = jobs.fetch("deliver")
abort("self-hosted delivery job permissions must remain read-only") unless job.fetch("permissions") == read_only_permissions
expected_runner = { "group" => "slack-delivery", "labels" => "slack-delivery" }
abort("delivery job must use the dedicated runner group and label") unless job.fetch("runs-on") == expected_runner
abort("delivery timeout must remain bounded") unless job.fetch("timeout-minutes") == 15
abort("delivery job must expose only the verified Slack receipt") unless job.fetch("outputs") == { "apk_delivered" => "${{ steps.complete.outputs.apk_delivered }}" }

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
  step.key?("uses") && step["uses"] != "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093"
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
  "inspect" => ["Inspect BuildCommit request metadata", true],
  "start" => ["Deliver build start notification", true],
  "complete" => ["Deliver build completion notification", false]
}.each do |mode, step_name|
  step_name, advisory = step_name
  step = steps.find { |candidate| candidate["name"] == step_name }
  abort("missing delivery mode: #{mode}") unless step
  abort("#{mode} must call only the fixed host executable") unless step.fetch("run").include?("#{host_executable} #{mode}")
  if advisory
    abort("#{mode} delivery must remain advisory") unless step.fetch("continue-on-error") == true
  else
    abort("required Development APK completion must fail this delivery workflow") if step["continue-on-error"] == true
    abort("completion step must expose its delivery receipt") unless step["id"] == "complete"
  end
end

download = steps.find { |step| step["name"] == "Download Development APK from source run" }
abort("Development APK download is missing") unless download
abort("credential-bearing delivery runner actions must be pinned to a full commit SHA") unless download.fetch("uses") == "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093"
expected_artifact = "Android-BuildCommit-Development-APK-${{ github.event.workflow_run.id }}-${{ github.event.workflow_run.run_attempt }}"
abort("delivery must download only the exact source run attempt artifact") unless download.dig("with", "name") == expected_artifact
abort("artifact download must target the source workflow run") unless download.dig("with", "run-id") == "${{ github.event.workflow_run.id }}"
abort("artifact download must use the workflow token") unless download.dig("with", "github-token") == "${{ github.token }}"
abort("APK download must be limited to successful Development Android builds") unless download.fetch("if").include?("development_android == 'true'") && download.fetch("if").include?("conclusion == 'success'")
abort("a persisted Slack receipt must skip the APK download") unless download.fetch("if").include?("apk_already_delivered != 'true'")
abort("required Development APK download must fail this delivery workflow") if download["continue-on-error"] == true

health_check = steps.find { |step| step["name"] == "Assert required Slack delivery outcome" }
abort("completed delivery health assertion is missing") unless health_check
abort("delivery health assertion must always inspect completed events") unless health_check.fetch("if").include?("always()") && health_check.fetch("if").include?("github.event.action == 'completed'")
abort("delivery health assertion must fail the delivery workflow") if health_check["continue-on-error"] == true
health_contract = health_check.to_s
%w[fetch_request inspect complete download apk_already_delivered apk_delivered].each do |signal|
  abort("delivery health assertion does not inspect #{signal}") unless health_contract.include?(signal)
end

cleanup = jobs.fetch("cleanup")
abort("Artifact cleanup must wait for the isolated delivery job") unless cleanup.fetch("needs") == "deliver"
abort("Artifact cleanup must use an ephemeral GitHub-hosted runner") unless cleanup.fetch("runs-on") == "ubuntu-latest"
abort("Artifact cleanup must receive only Actions write permission") unless cleanup.fetch("permissions") == { "actions" => "write" }
cleanup_condition = cleanup.fetch("if")
abort("Artifact cleanup must require a successful delivery job") unless cleanup_condition.include?("needs.deliver.result == 'success'")
abort("Artifact cleanup must require the verified Slack receipt") unless cleanup_condition.include?("needs.deliver.outputs.apk_delivered == 'true'")
abort("Artifact cleanup timeout must remain bounded") unless cleanup.fetch("timeout-minutes").to_i <= 5

cleanup_steps = cleanup.fetch("steps")
abort("Artifact cleanup must not checkout repository code") if cleanup_steps.any? { |step| step["uses"] == "actions/checkout@v4" }
delete_artifact = cleanup_steps.find { |step| step["name"] == "Delete delivered Development APK artifact" }
abort("delivered Development APK deletion is missing") unless delete_artifact
abort("Artifact deletion failure must fail this delivery workflow") if delete_artifact["continue-on-error"] == true
abort("Artifact deletion must use the workflow token") unless delete_artifact.dig("env", "GH_TOKEN") == "${{ github.token }}"
abort("Artifact deletion must bind the exact source run attempt name") unless delete_artifact.dig("env", "ARTIFACT_NAME") == expected_artifact
delete_script = delete_artifact.fetch("run")
abort("Artifact deletion must enumerate only the source run artifacts") unless delete_script.include?("actions/runs/${SOURCE_RUN_ID}/artifacts")
abort("Artifact lookup must use the exact expected name") unless delete_script.include?("ARTIFACT_NAME")
abort("Artifact deletion must target the resolved artifact ID") unless delete_script.include?("actions/artifacts/") && delete_script.match?(/(?:--method|-X)\s+DELETE/)
abort("Artifact cleanup reruns must accept an already absent Artifact") unless delete_script.include?('artifact_id" = missing')

forbidden_secret_access = /(?:SLACK_(?:BUILD_)?(?:WEBHOOK_URL|BOT_TOKEN|CHANNEL_ID)|slack-(?:webhook-url|bot-token|channel-id)|hooks\.slack\.com)/i
abort("delivery workflow must not contain Slack credentials") if delivery_workflow.to_s.match?(forbidden_secret_access)
RUBY

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
mkdir -p "$fixture_root/bin"
ruby -ryaml -e '
  workflow = YAML.load_file(ARGV.fetch(0))
  cleanup = workflow.fetch("jobs").fetch("cleanup")
  step = cleanup.fetch("steps").find { |candidate| candidate["name"] == "Delete delivered Development APK artifact" }
  print step.fetch("run")
' "$delivery_workflow" > "$fixture_root/delete-artifact.sh"

cat > "$fixture_root/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
method=""
previous=""
for argument in "$@"; do
  if [ "$previous" = "--method" ]; then
    method="$argument"
  fi
  previous="$argument"
done
endpoint="${!#}"
case "$endpoint" in
  repos/ActionFitGames/FixtureProject/actions/runs/12345/artifacts)
    test "$method" = GET
    if [ "${FAKE_ARTIFACT_STATE:-present}" = missing ]; then
      printf '{"total_count":0,"artifacts":[]}\n'
    else
      printf '{"total_count":1,"artifacts":[{"id":987,"name":"%s","expired":false,"workflow_run":{"id":12345}}]}\n' "$ARTIFACT_NAME"
    fi
    ;;
  repos/ActionFitGames/FixtureProject/actions/artifacts/987)
    test "$method" = DELETE
    ;;
  *)
    echo "unexpected gh endpoint: $endpoint" >&2
    exit 64
    ;;
esac
FAKE_GH
chmod +x "$fixture_root/bin/gh"

PATH="$fixture_root/bin:$PATH" \
FAKE_GH_LOG="$fixture_root/gh.log" \
GH_TOKEN=fixture-token \
SOURCE_REPOSITORY=ActionFitGames/FixtureProject \
SOURCE_RUN_ID=12345 \
SOURCE_RUN_ATTEMPT=2 \
ARTIFACT_NAME=Android-BuildCommit-Development-APK-12345-2 \
  bash "$fixture_root/delete-artifact.sh" >/dev/null
grep -F 'repos/ActionFitGames/FixtureProject/actions/runs/12345/artifacts' "$fixture_root/gh.log" >/dev/null
grep -F 'repos/ActionFitGames/FixtureProject/actions/artifacts/987' "$fixture_root/gh.log" >/dev/null

: > "$fixture_root/gh.log"
PATH="$fixture_root/bin:$PATH" \
FAKE_GH_LOG="$fixture_root/gh.log" \
FAKE_ARTIFACT_STATE=missing \
GH_TOKEN=fixture-token \
SOURCE_REPOSITORY=ActionFitGames/FixtureProject \
SOURCE_RUN_ID=12345 \
SOURCE_RUN_ATTEMPT=2 \
ARTIFACT_NAME=Android-BuildCommit-Development-APK-12345-2 \
  bash "$fixture_root/delete-artifact.sh" >/dev/null
grep -F 'repos/ActionFitGames/FixtureProject/actions/runs/12345/artifacts' "$fixture_root/gh.log" >/dev/null
if grep -F 'actions/artifacts/987' "$fixture_root/gh.log" >/dev/null; then
  echo "Already absent Artifact cleanup must not issue DELETE" >&2
  exit 1
fi

repository_root="$(cd "$package_root/../.." && pwd -P)"
if [ -e "$repository_root/.git" ]; then
  cmp "$delivery_workflow" "$repository_root/.github/workflows/buildcommit-slack-delivery.yml"
fi

echo "Slack delivery workflow tests passed"
