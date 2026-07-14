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
abort("expected only the mobile-build job") unless jobs.keys == ["mobile-build"]

mobile_build = jobs.fetch("mobile-build")
runs_on = mobile_build.fetch("runs-on")
expected_labels = ["self-hosted", "macOS", "unity-mobile", "${{ vars.UNITY_RUNNER_AFFINITY_LABEL }}"]
abort("unexpected affinity runner labels: #{runs_on.inspect}") unless runs_on == expected_labels

steps = mobile_build.fetch("steps")
checkout = steps.find { |step| step["uses"] == "actions/checkout@v4" }
abort("checkout clean:false is required") unless checkout && checkout.fetch("with").fetch("clean") == false

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
