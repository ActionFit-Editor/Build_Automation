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
runs_on = mobile_build.fetch("runs-on")
expected_labels = ["self-hosted", "macOS", "unity-mobile", "${{ needs.allocate.outputs.affinity_label }}"]
abort("unexpected affinity runner labels: #{runs_on.inspect}") unless runs_on == expected_labels

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

abort("Android composite action is not wired") unless steps.any? { |step| step["uses"] == "./.github/actions/build-android" }
abort("iOS composite action is not wired") unless steps.any? { |step| step["uses"] == "./.github/actions/build-ios" }
abort("final Library-preserving cleanup is missing") unless steps.any? { |step| step["name"] == "Final cleanup while preserving Unity Library" }

android_action = YAML.load_file(android_action_path)
ios_action = YAML.load_file(ios_action_path)
abort("Android action must be composite") unless android_action.dig("runs", "using") == "composite"
abort("iOS action must be composite") unless ios_action.dig("runs", "using") == "composite"
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
