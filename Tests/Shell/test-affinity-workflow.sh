#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
workflow="$package_root/WorkflowTemplates/buildcommit-auto-build.yml"
android_action="$package_root/.github/actions/build-android/action.yml"
ios_action="$package_root/.github/actions/build-ios/action.yml"

ruby -ryaml - "$workflow" "$android_action" "$ios_action" <<'RUBY'
workflow_path, android_action_path, ios_action_path = ARGV
workflow = YAML.load_file(workflow_path)
jobs = workflow.fetch("jobs")
abort("expected allocate then mobile-build jobs") unless jobs.keys == ["allocate", "mobile-build"]

allocate = jobs.fetch("allocate")
abort("allocator job must not receive repository token permissions") unless allocate.fetch("permissions") == {}
expected_allocator_target = {
  "group" => "mobile-build-allocator",
  "labels" => "runner-allocator"
}
abort("allocator must use the dedicated runner group") unless allocate.fetch("runs-on") == expected_allocator_target
abort("allocator timeout must remain bounded") unless allocate.fetch("timeout-minutes") == 5
allocator_outputs = allocate.fetch("outputs")
abort("allocator affinity output is missing") unless allocator_outputs.fetch("affinity_label") == "${{ steps.allocator.outputs.project_label }}"

allocator_steps = allocate.fetch("steps")
abort("allocator job must not checkout BuildRequest or repository objects") if allocator_steps.any? { |step| step["uses"] == "actions/checkout@v4" }
abort("allocator job must not run repository-provided actions") if allocator_steps.any? { |step| step.key?("uses") }
allocator = allocator_steps.find { |step| step["id"] == "allocator" }
abort("runner allocator step is missing") unless allocator
abort("runner allocator must use bash") unless allocator["shell"] == "bash"
abort("runner allocator must use the host-local executable") unless allocator.dig("env", "ALLOCATOR_EXECUTABLE") == "/Users/lydia/workspace/runner-allocator/bin/allocate-project-runner"
allocator_script = allocator.fetch("run")
abort("allocator repository input is missing") unless allocator_script.include?('--repository "$GITHUB_REPOSITORY"')
abort("allocator output file is missing") unless allocator_script.include?('--github-output "$GITHUB_OUTPUT"')
abort("allocator project override is missing") unless allocator_script.include?('--project-label "$CONFIGURED_AFFINITY_LABEL"')
abort("allocator must not reference the hosted runner token") if allocator.to_s.include?("UNITY_RUNNER_ALLOCATOR_TOKEN")
abort("workflow must not reference the hosted runner token") if workflow.to_s.include?("UNITY_RUNNER_ALLOCATOR_TOKEN")

mobile_build = jobs.fetch("mobile-build")
abort("mobile-build must wait for allocator") unless mobile_build.fetch("needs") == "allocate"
abort("mobile-build timeout must bound both builds and Store uploads") unless mobile_build.fetch("timeout-minutes") == 180
runs_on = mobile_build.fetch("runs-on")
expected_labels = ["self-hosted", "macOS", "unity-mobile", "${{ needs.allocate.outputs.affinity_label }}"]
abort("unexpected affinity runner labels: #{runs_on.inspect}") unless runs_on == expected_labels

workflow_environment = workflow.fetch("env")
abort("Store upload timeout is missing") unless workflow_environment.fetch("STORE_UPLOAD_TIMEOUT_SECONDS") == 3600
abort("TestFlight retries must be limited to two attempts") unless workflow_environment.fetch("TESTFLIGHT_UPLOAD_ATTEMPTS") == 2
abort("TestFlight attempt timeout is missing") unless workflow_environment.fetch("TESTFLIGHT_UPLOAD_ATTEMPT_TIMEOUT_SECONDS") == 900
abort("TestFlight retry delay is missing") unless workflow_environment.fetch("TESTFLIGHT_UPLOAD_RETRY_DELAY_SECONDS") == 10

steps = mobile_build.fetch("steps")
checkout = steps.find { |step| step["uses"] == "actions/checkout@v4" }
abort("checkout clean:false is required") unless checkout && checkout.fetch("with").fetch("clean") == false

marker = steps.find { |step| step["name"] == "Refresh affinity workspace retention marker" }
abort("affinity retention marker step is missing") unless marker
abort("affinity marker must run before reset and checkout") unless steps.first.equal?(marker)
abort("marker affinity output is not wired") unless marker.dig("env", "AFFINITY_LABEL") == "${{ needs.allocate.outputs.affinity_label }}"
abort("marker runner output is not wired") unless marker.dig("env", "ALLOCATED_RUNNER_NAME") == "${{ needs.allocate.outputs.runner_name }}"
marker_script = marker.fetch("run")
abort("marker runner verification is missing") unless marker_script.include?("actual_runner == allocated_runner")
abort("affinity marker path is missing") unless marker_script.include?(".unity-mobile-affinity.json")
abort("affinity marker schema is missing") unless marker_script.include?('"schema_version" => 1')

sequence = steps.find { |step| step["id"] == "sequence" }
abort("PrepareBuildSequence entry point is missing") unless sequence.fetch("run").include?("CIBuildEntry.PrepareBuildSequence")

%w[android_first ios_first android_second ios_second].each do |step_id|
  abort("missing build phase: #{step_id}") unless steps.any? { |step| step["id"] == step_id }
end

step_by_id = lambda do |step_id|
  steps.find { |step| step["id"] == step_id } || abort("missing workflow step: #{step_id}")
end
step_index = lambda do |step_id|
  steps.index { |step| step["id"] == step_id } || abort("missing workflow step index: #{step_id}")
end

%w[android_first ios_first].each do |step_id|
  step = step_by_id.call(step_id)
  expected_defer = "${{ steps.sequence.outputs.second != '' }}"
  abort("#{step_id} must defer only when a second platform exists") unless step.dig("with", "defer-store-upload") == expected_defer
end
%w[android_second ios_second].each do |step_id|
  step = step_by_id.call(step_id)
  abort("#{step_id} must upload synchronously") unless step.dig("with", "defer-store-upload") == "false"
end

finalize_upload = step_by_id.call("first_store_upload")
abort("deferred Store upload finalizer must always run for Both") unless finalize_upload.fetch("if") == "always() && steps.sequence.outputs.second != ''"
abort("deferred Store upload finalizer must expose its outcome") unless finalize_upload.fetch("continue-on-error") == true
abort("deferred Store upload finalizer must wait through the worker") unless finalize_upload.fetch("run").include?('store-upload-worker.rb" wait "$task"')
last_second_index = [step_index.call("android_second"), step_index.call("ios_second")].max
abort("first Store upload must overlap the second build") unless step_index.call("first_store_upload") > last_second_index

cancel_upload = step_by_id.call("store_upload_cleanup")
abort("deferred Store upload cancellation must always run for Both") unless cancel_upload.fetch("if") == "always() && steps.sequence.outputs.second != ''"
abort("deferred Store upload cancellation must not hide final reporting") unless cancel_upload.fetch("continue-on-error") == true
abort("Android deferred upload cancellation is missing") unless cancel_upload.fetch("run").include?("cancel android")
abort("iOS deferred upload cancellation is missing") unless cancel_upload.fetch("run").include?("cancel ios")
abort("Store upload cancellation must follow finalization") unless step_index.call("store_upload_cleanup") > step_index.call("first_store_upload")

failure_step = steps.find { |step| step["name"] == "Fail when a requested platform failed" }
abort("final build failure aggregation is missing") unless failure_step
abort("deferred Store upload failure is not aggregated") unless failure_step.dig("env", "FIRST_STORE_UPLOAD_OUTCOME") == "${{ steps.first_store_upload.outcome }}"
abort("deferred Store cleanup failure is not aggregated") unless failure_step.dig("env", "STORE_UPLOAD_CLEANUP_OUTCOME") == "${{ steps.store_upload_cleanup.outcome }}"

abort("Android composite action is not wired") unless steps.any? { |step| step["uses"] == "./.github/actions/build-android" }
abort("iOS composite action is not wired") unless steps.any? { |step| step["uses"] == "./.github/actions/build-ios" }
abort("final Library-preserving cleanup is missing") unless steps.any? { |step| step["name"] == "Final cleanup while preserving Unity Library" }

android_action = YAML.load_file(android_action_path)
ios_action = YAML.load_file(ios_action_path)
abort("Android action must be composite") unless android_action.dig("runs", "using") == "composite"
abort("iOS action must be composite") unless ios_action.dig("runs", "using") == "composite"

[
  ["Android", android_action],
  ["iOS", ios_action]
].each do |platform, action|
  abort("#{platform} defer input is missing") unless action.dig("inputs", "defer-store-upload", "default") == "false"
  expected_output = "${{ steps.upload_mode.outputs.deferred }}"
  abort("#{platform} deferred output is missing") unless action.dig("outputs", "store-upload-deferred", "value") == expected_output
  upload_mode = action.dig("runs", "steps").find { |step| step["id"] == "upload_mode" }
  abort("#{platform} upload mode resolver is missing") unless upload_mode
  abort("#{platform} upload mode must validate the defer input") unless upload_mode.fetch("run").include?("defer-store-upload must be true or false")
end

android_steps = android_action.dig("runs", "steps")
android_sync_upload = android_steps.find { |step| step["uses"] == "r0adkll/upload-google-play@v1" }
abort("synchronous Google Play upload is missing") unless android_sync_upload
abort("synchronous Google Play upload must be disabled in deferred mode") unless android_sync_upload.fetch("if").include?("steps.upload_mode.outputs.deferred != 'true'")
android_deferred_upload = android_steps.find { |step| step["name"] == "Start Google Play upload in background" }
abort("deferred Google Play upload is missing") unless android_deferred_upload
abort("deferred Google Play upload mode guard is missing") unless android_deferred_upload.fetch("if") == "steps.upload_mode.outputs.deferred == 'true'"
abort("deferred Google Play upload must use the worker") unless android_deferred_upload.fetch("run").include?("store-upload-worker.rb")
abort("deferred Google Play upload wrapper is missing") unless android_deferred_upload.fetch("run").include?("upload-google-play.sh")

ios_steps = ios_action.dig("runs", "steps")
ios_sync_upload = ios_steps.find { |step| step["name"] == "Upload to TestFlight" }
abort("synchronous TestFlight upload is missing") unless ios_sync_upload
abort("synchronous TestFlight upload must be disabled in deferred mode") unless ios_sync_upload.fetch("if").include?("steps.upload_mode.outputs.deferred != 'true'")
abort("synchronous TestFlight upload must use the bounded retry wrapper") unless ios_sync_upload.fetch("run").include?("upload-testflight.rb")
ios_deferred_upload = ios_steps.find { |step| step["name"] == "Start TestFlight upload in background" }
abort("deferred TestFlight upload is missing") unless ios_deferred_upload
abort("deferred TestFlight upload mode guard is missing") unless ios_deferred_upload.fetch("if") == "steps.upload_mode.outputs.deferred == 'true'"
abort("deferred TestFlight upload must use the worker") unless ios_deferred_upload.fetch("run").include?("store-upload-worker.rb")
abort("deferred TestFlight retry wrapper is missing") unless ios_deferred_upload.fetch("run").include?("upload-testflight.rb")
RUBY

if grep -Fq 'File.write(path, JSON.pretty_generate(request))' "$workflow"; then
  echo "Workflow must not overwrite the original BuildRequest" >&2
  exit 1
fi

if grep -Fq 'uses: actions/cache@' "$workflow"; then
  echo "Workflow must not save the remote Unity Library cache" >&2
  exit 1
fi

echo "Affinity workflow tests passed"
