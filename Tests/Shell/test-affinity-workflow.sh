#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
workflow="$package_root/WorkflowTemplates/buildcommit-auto-build.yml"
android_action="$package_root/.github/actions/build-android/action.yml"
ios_action="$package_root/.github/actions/build-ios/action.yml"
slack_notifier="$package_root/.github/scripts/notify-slack-build-result.sh"

ruby -ryaml - "$workflow" "$android_action" "$ios_action" "$slack_notifier" <<'RUBY'
workflow_path, android_action_path, ios_action_path, slack_notifier_path = ARGV
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

forbidden_slack_access = /(?:SLACK_(?:BUILD_)?(?:WEBHOOK_URL|BOT_TOKEN|CHANNEL_ID)|slack-(?:webhook-url|bot-token|channel-id)|notify-slack-build-result\.sh|upload-slack-file\.sh|hooks\.slack\.com)/i
abort("allocator must not access Slack credentials or helpers") if allocate.to_s.match?(forbidden_slack_access)

mobile_build = jobs.fetch("mobile-build")
abort("mobile-build must wait for allocator") unless mobile_build.fetch("needs") == "allocate"
abort("mobile-build timeout must leave advisory Slack delivery headroom") unless mobile_build.fetch("timeout-minutes") == 220
runs_on = mobile_build.fetch("runs-on")
expected_labels = ["self-hosted", "macOS", "unity-mobile", "${{ needs.allocate.outputs.affinity_label }}"]
abort("unexpected affinity runner labels: #{runs_on.inspect}") unless runs_on == expected_labels
abort("workflow must not use GitHub Secrets for runner-local credentials") if workflow.to_s.include?("${{ secrets.")
abort("workflow must not embed a Slack Bot token") if workflow.to_s.match?(/xox[baprs]-[A-Za-z0-9-]+/i)
abort("workflow must not embed a Slack webhook URL") if workflow.to_s.match?(%r{https://hooks\.slack\.com/services/}i)

slack_notifier = File.read(slack_notifier_path)
abort("Slack notifier must use the shared Bot token") unless slack_notifier.include?("shared/slack-bot-token")
abort("Slack notifier must use the shared channel ID") unless slack_notifier.include?("shared/slack-channel-id")
abort("Slack notifier must post through chat.postMessage") unless slack_notifier.include?("chat.postMessage")
abort("Slack notifier must not use the legacy Incoming Webhook") if slack_notifier.match?(/slack-webhook-url|hooks\.slack\.com|SLACK_(?:BUILD_)?WEBHOOK_URL/i)

workflow_environment = workflow.fetch("env")
abort("Store upload timeout is missing") unless workflow_environment.fetch("STORE_UPLOAD_TIMEOUT_SECONDS") == 3600
abort("TestFlight retries must be limited to two attempts") unless workflow_environment.fetch("TESTFLIGHT_UPLOAD_ATTEMPTS") == 2
abort("TestFlight attempt timeout is missing") unless workflow_environment.fetch("TESTFLIGHT_UPLOAD_ATTEMPT_TIMEOUT_SECONDS") == 900
abort("TestFlight retry delay is missing") unless workflow_environment.fetch("TESTFLIGHT_UPLOAD_RETRY_DELAY_SECONDS") == 10
abort("Slack metadata request timeout is missing") unless workflow_environment.fetch("SLACK_API_TIMEOUT_SECONDS") == 60
abort("Slack APK transfer timeout is missing") unless workflow_environment.fetch("SLACK_FILE_UPLOAD_TIMEOUT_SECONDS") == 1800

steps = mobile_build.fetch("steps")
log_reset = steps.find { |step| step["name"] == "Reset current BuildCommit logs" }
abort("current-run log reset is missing") unless log_reset
abort("log reset must run only for an approved build") unless log_reset.fetch("if") == "steps.detect.outputs.should_build == 'true'"
abort("log reset must reject an unexpected path") unless log_reset.fetch("run").include?("Refusing to reset an unexpected Unity log path")
checkout = steps.find { |step| step["uses"] == "actions/checkout@v4" }
abort("checkout clean:false is required") unless checkout && checkout.fetch("with").fetch("clean") == false

secret_root = steps.find { |step| step["name"] == "Resolve shared runner secret root" }
abort("shared runner secret-root resolver is missing") unless secret_root
abort("secret-root resolver must expose its result") unless secret_root.fetch("id") == "secret_root"
abort("secret-root resolver must run only for an approved build") unless secret_root.fetch("if") == "steps.detect.outputs.should_build == 'true'"
abort("secret-root resolver must use the synchronized local helper") unless secret_root.fetch("run") == 'bash "$REPOSITORY_ROOT/.github/scripts/resolve-local-secret-root.sh"'

start_notification = steps.find { |step| step["name"] == "Notify Slack build start" }
abort("BuildCommit start notification is missing") unless start_notification
abort("start notification failure must not change the build result") unless start_notification.fetch("continue-on-error") == true
abort("start notification must use the synchronized local helper") unless start_notification.fetch("run") == 'bash "$REPOSITORY_ROOT/.github/scripts/notify-slack-build-result.sh"'
abort("start notification status metadata is missing") unless start_notification.dig("env", "BUILD_JOB_STATUS") == "start"
abort("start notification platform metadata is missing") unless start_notification.dig("env", "BUILD_PLATFORM") == "${{ steps.detect.outputs.platform }}"
abort("start notification project metadata is missing") unless start_notification.dig("env", "BUILD_PROJECT_NAME") == "${{ steps.paths.outputs.unity_project_name }}"
abort("start notification version metadata is missing") unless start_notification.dig("env", "BUILD_VERSION") == "${{ steps.detect.outputs.build_version }}"
abort("start notification mentions metadata is missing") unless start_notification.dig("env", "SLACK_BUILD_MENTIONS") == "${{ steps.detect.outputs.slack_mentions }}"

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

{
  "android_first" => ["android_upload_target", "android_bundle_no", "android_development_build"],
  "android_second" => ["android_upload_target", "android_bundle_no", "android_development_build"],
  "ios_first" => ["ios_upload_target", "ios_bundle_no", "ios_development_build"],
  "ios_second" => ["ios_upload_target", "ios_bundle_no", "ios_development_build"]
}.each do |step_id, outputs|
  step = steps.find { |candidate| candidate["id"] == step_id }
  platform = step_id.start_with?("android") ? "android" : "ios"
  abort("#{step_id} must use the effective working-request upload target") unless step.dig("with", "upload-target") == "${{ steps.sequence.outputs.#{outputs[0]} }}"
  abort("#{step_id} must use the effective working-request bundle number") unless step.dig("with", "bundle-no") == "${{ steps.sequence.outputs.#{outputs[1]} }}"
  abort("#{step_id} must use the effective Development Build flag") unless step.dig("with", "development-build") == "${{ steps.sequence.outputs.#{outputs[2]} }}"
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

deferred_aab = steps.find { |step| step["name"] == "Upload deferred Android AAB artifact" }
abort("deferred Android recovery Artifact is missing") unless deferred_aab
abort("successful deferred Android uploads must not retain a duplicate AAB") unless deferred_aab.fetch("if").include?("steps.first_store_upload.outcome != 'success'")
abort("deferred Android recovery must require a staged binary") unless deferred_aab.fetch("if").include?("steps.android_first.outputs.store-binary-path != ''")
abort("deferred Android recovery upload failure must be visible") if deferred_aab["continue-on-error"] == true
abort("deferred Android recovery must fail when its staged binary is missing") unless deferred_aab.dig("with", "if-no-files-found") == "error"
abort("deferred Android recovery Artifact must expire after three days") unless deferred_aab.dig("with", "retention-days") == 3
deferred_aab_paths = deferred_aab.dig("with", "path")
abort("deferred Android recovery must use only fresh composite outputs") unless deferred_aab_paths.include?("steps.android_first.outputs.store-binary-path")
abort("deferred Android recovery must not scan the affinity build directory") if deferred_aab_paths.include?("UNITY_BUILD_DIR")
deferred_android_logs = steps.find { |step| step["name"] == "Upload deferred Android logs" }
abort("deferred Android failure logs are missing") unless deferred_android_logs
abort("successful deferred Android uploads must not retain logs") unless deferred_android_logs.fetch("if").include?("steps.first_store_upload.outcome != 'success'")
abort("deferred Android logs must expire after seven days") unless deferred_android_logs.dig("with", "retention-days") == 7
deferred_ios = steps.find { |step| step["name"] == "Upload deferred iOS app artifact" }
abort("deferred iOS recovery Artifact is missing") unless deferred_ios
abort("successful deferred iOS uploads must not retain a duplicate IPA") unless deferred_ios.fetch("if").include?("steps.first_store_upload.outcome != 'success'")
abort("deferred iOS recovery must require a staged binary") unless deferred_ios.fetch("if").include?("steps.ios_first.outputs.store-binary-path != ''")
abort("deferred iOS recovery upload failure must be visible") if deferred_ios["continue-on-error"] == true
abort("deferred iOS recovery must fail when its staged binary is missing") unless deferred_ios.dig("with", "if-no-files-found") == "error"
abort("deferred iOS recovery Artifact must expire after three days") unless deferred_ios.dig("with", "retention-days") == 3
abort("deferred iOS recovery must use the fresh composite output") unless deferred_ios.dig("with", "path") == "${{ steps.ios_first.outputs.store-binary-path }}"
deferred_diagnostics = steps.find { |step| step["name"] == "Upload deferred store upload diagnostics" }
abort("deferred Store diagnostics are missing") unless deferred_diagnostics
abort("successful deferred Store uploads must not retain diagnostics") unless deferred_diagnostics.fetch("if").include?("steps.first_store_upload.outcome != 'success'")
abort("deferred Store diagnostics must expire after seven days") unless deferred_diagnostics.dig("with", "retention-days") == 7
deferred_cleanup = steps.find { |step| step["name"] == "Cleanup old artifacts after deferred upload" }
expected_deferred_cleanup_number = "${{ steps.android_first.outputs.store-upload-deferred == 'true' && steps.sequence.outputs.android_bundle_no || steps.ios_first.outputs.effective-bundle-no }}"
abort("deferred iOS cleanup must use the effective bundle number") unless deferred_cleanup.dig("env", "BUILD_CLEANUP_BUNDLE_NO") == expected_deferred_cleanup_number

direct_apk_delivery = step_by_id.call("direct_apk_delivery")
abort("direct Development APK delivery step has an unexpected name") unless direct_apk_delivery.fetch("name") == "Attach Development APK directly to Slack"
abort("direct Development APK delivery must not change the source build result") unless direct_apk_delivery.fetch("continue-on-error") == true
direct_delivery_condition = direct_apk_delivery.fetch("if")
abort("direct APK delivery must evaluate after final result aggregation") unless direct_delivery_condition.include?("always()")
abort("direct APK delivery must require successful final cleanup") unless direct_delivery_condition.include?("steps.final_cleanup.outcome == 'success'")
abort("direct APK delivery must require a successful aggregated build result") unless direct_delivery_condition.include?("steps.build_result.outcome == 'success'")
abort("direct APK delivery must require Development Android") unless direct_delivery_condition.include?("steps.sequence.outputs.android_development_build == 'true'")
abort("direct APK delivery must require successful build-sequence preparation") unless direct_delivery_condition.include?("steps.sequence.outcome == 'success'")
%w[android_first ios_first android_second ios_second first_store_upload store_upload_cleanup].each do |step_id|
  abort("direct APK delivery must reject #{step_id} failure") unless direct_delivery_condition.include?("steps.#{step_id}.outcome != 'failure'")
end
expected_direct_apk_path = "${{ steps.android_first.outputs.development-apk-path || steps.android_second.outputs.development-apk-path }}"
abort("direct APK delivery must use only the fresh Android action output") unless direct_apk_delivery.dig("env", "SLACK_FILE_PATH") == expected_direct_apk_path
abort("direct APK delivery phase metadata is missing") unless direct_apk_delivery.dig("env", "SLACK_UPLOAD_PHASE_PATH") == "${{ runner.temp }}/buildcommit-slack-upload-${{ github.run_id }}-${{ github.run_attempt }}.phase"
abort("direct APK delivery platform metadata is missing") unless direct_apk_delivery.dig("env", "BUILD_PLATFORM") == "${{ steps.detect.outputs.platform }}"
abort("direct APK delivery project metadata is missing") unless direct_apk_delivery.dig("env", "BUILD_PROJECT_NAME") == "${{ steps.paths.outputs.unity_project_name }}"
abort("direct APK delivery version metadata is missing") unless direct_apk_delivery.dig("env", "BUILD_VERSION") == "${{ steps.detect.outputs.build_version }}"
abort("direct APK delivery bundle metadata is missing") unless direct_apk_delivery.dig("env", "BUILD_BUNDLE_NO") == "${{ steps.sequence.outputs.android_bundle_no }}"
abort("direct APK delivery iOS version metadata is missing") unless direct_apk_delivery.dig("env", "BUILD_IOS_EFFECTIVE_BUNDLE_NO") == "${{ steps.ios_first.outputs.effective-bundle-no || steps.ios_second.outputs.effective-bundle-no }}"
abort("direct APK delivery mentions metadata is missing") unless direct_apk_delivery.dig("env", "SLACK_BUILD_MENTIONS") == "${{ steps.detect.outputs.slack_mentions }}"
abort("direct APK delivery commit metadata is missing") unless direct_apk_delivery.dig("env", "BUILD_SHORT_SHA") == "${{ github.sha }}"
abort("direct APK delivery run URL metadata is missing") unless direct_apk_delivery.dig("env", "BUILD_RUN_URL") == "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
abort("direct APK delivery must use the synchronized local helper") unless direct_apk_delivery.fetch("run") == 'bash "$REPOSITORY_ROOT/.github/scripts/upload-slack-file.sh"'
abort("direct APK delivery must follow both possible second-platform builds") unless step_index.call("direct_apk_delivery") > last_second_index
abort("direct APK delivery must follow deferred Store finalization") unless step_index.call("direct_apk_delivery") > step_index.call("first_store_upload")
abort("direct APK delivery must follow deferred Store cleanup") unless step_index.call("direct_apk_delivery") > step_index.call("store_upload_cleanup")

final_notification = steps.find { |step| step["name"] == "Notify Slack final result" }
abort("final Slack notification is missing") unless final_notification
abort("final Slack notification must always report approved builds") unless final_notification.fetch("if") == "always() && steps.detect.outputs.should_build == 'true'"
abort("final Slack notification failure must not change the build result") unless final_notification.fetch("continue-on-error") == true
abort("final Slack notification must consume the direct delivery outcome") unless final_notification.dig("env", "DIRECT_APK_DELIVERY_OUTCOME") == "${{ steps.direct_apk_delivery.outcome }}"
abort("final Slack notification must consume durable delivery phase metadata") unless final_notification.dig("env", "DIRECT_APK_DELIVERY_PHASE_PATH") == "${{ runner.temp }}/buildcommit-slack-upload-${{ github.run_id }}-${{ github.run_attempt }}.phase"
abort("final Slack notification must consume the effective iOS build number") unless final_notification.dig("env", "BUILD_IOS_EFFECTIVE_BUNDLE_NO") == "${{ steps.ios_first.outputs.effective-bundle-no || steps.ios_second.outputs.effective-bundle-no }}"
final_notification_script = final_notification.fetch("run")
abort("iOS-only Slack metadata must use the effective TestFlight build number") unless final_notification_script.include?('BUILD_IOS_EFFECTIVE_BUNDLE_NO:-$REQUEST_BUNDLE_NO')
abort("successful direct APK delivery must suppress the duplicate success message") unless final_notification_script.include?("skipping a duplicate result message") && final_notification_script.include?("exit 0")
abort("failed direct APK delivery must produce an explicit warning status") unless final_notification_script.include?("build_status=apk_delivery_failure")
abort("ambiguous Slack completion must suppress a contradictory failure message") unless final_notification_script.include?("completion-ambiguous") && final_notification_script.include?("durable pending receipt blocks duplicate APK delivery")
abort("confirmed durable delivery must suppress a contradictory failure message") unless final_notification_script.include?("receipt-delivered") && final_notification_script.include?("delivery receipt confirms success")
abort("final Slack notification must use the synchronized local helper") unless final_notification_script.include?('bash "$REPOSITORY_ROOT/.github/scripts/notify-slack-build-result.sh"')

failure_step = step_by_id.call("build_result")
abort("final build failure aggregation is missing") unless failure_step
abort("deferred Store upload failure is not aggregated") unless failure_step.dig("env", "FIRST_STORE_UPLOAD_OUTCOME") == "${{ steps.first_store_upload.outcome }}"
abort("deferred Store cleanup failure is not aggregated") unless failure_step.dig("env", "STORE_UPLOAD_CLEANUP_OUTCOME") == "${{ steps.store_upload_cleanup.outcome }}"

final_cleanup = steps.find { |step| step["name"] == "Final cleanup while preserving Unity Library" }
abort("final cleanup must expose a stable step id") unless final_cleanup.fetch("id") == "final_cleanup"
abort("final cleanup must finish before result aggregation") unless steps.index(final_cleanup) < steps.index(failure_step)
abort("result aggregation must finish before direct APK delivery") unless steps.index(failure_step) < step_index.call("direct_apk_delivery")
abort("direct APK delivery must run before final notification") unless step_index.call("direct_apk_delivery") < steps.index(final_notification)
phase_cleanup = steps.find { |step| step["name"] == "Remove Slack delivery phase marker" }
abort("Slack phase cleanup is missing") unless phase_cleanup
abort("Slack phase cleanup must be advisory") unless phase_cleanup["continue-on-error"] == true
abort("Slack phase cleanup must run after final notification") unless steps.index(final_notification) < steps.index(phase_cleanup)

abort("Android composite action is not wired") unless steps.any? { |step| step["uses"] == "./.github/actions/build-android" }
abort("iOS composite action is not wired") unless steps.any? { |step| step["uses"] == "./.github/actions/build-ios" }
abort("final Library-preserving cleanup is missing") unless final_cleanup

android_action = YAML.load_file(android_action_path)
ios_action = YAML.load_file(ios_action_path)
abort("Android action must be composite") unless android_action.dig("runs", "using") == "composite"
abort("iOS action must be composite") unless ios_action.dig("runs", "using") == "composite"

[
  ["Android", android_action],
  ["iOS", ios_action]
].each do |platform, action|
  abort("#{platform} composite must not expose the legacy slack-mentions input") if action.fetch("inputs").key?("slack-mentions")
  abort("#{platform} composite must not access Slack") if action.to_s.match?(forbidden_slack_access)
end

[
  ["Android", android_action],
  ["iOS", ios_action]
].each do |platform, action|
  abort("#{platform} defer input is missing") unless action.dig("inputs", "defer-store-upload", "default") == "false"
  abort("#{platform} Development Build input is missing") unless action.dig("inputs", "development-build", "default") == "false"
  expected_output = "${{ steps.upload_mode.outputs.deferred }}"
  abort("#{platform} deferred output is missing") unless action.dig("outputs", "store-upload-deferred", "value") == expected_output
  abort("#{platform} fresh Store binary output is missing") unless action.dig("outputs", "store-binary-path", "value")
  upload_mode = action.dig("runs", "steps").find { |step| step["id"] == "upload_mode" }
  abort("#{platform} upload mode resolver is missing") unless upload_mode
  abort("#{platform} upload mode must validate the defer input") unless upload_mode.fetch("run").include?("defer-store-upload must be true or false")
  abort("#{platform} upload mode must validate the Development Build input") unless upload_mode.fetch("run").include?("development-build must be true or false")
end

android_steps = android_action.dig("runs", "steps")
android_sync_upload = android_steps.find { |step| step["uses"] == "r0adkll/upload-google-play@v1" }
abort("synchronous Google Play upload is missing") unless android_sync_upload
abort("synchronous Google Play upload must expose its exact outcome") unless android_sync_upload.fetch("id") == "google_play_upload"
abort("synchronous Google Play upload must be disabled in deferred mode") unless android_sync_upload.fetch("if").include?("steps.upload_mode.outputs.deferred != 'true'")
android_deferred_upload = android_steps.find { |step| step["name"] == "Start Google Play upload in background" }
abort("deferred Google Play upload is missing") unless android_deferred_upload
abort("deferred Google Play upload mode guard is missing") unless android_deferred_upload.fetch("if") == "steps.upload_mode.outputs.deferred == 'true'"
abort("deferred Google Play upload must use the worker") unless android_deferred_upload.fetch("run").include?("store-upload-worker.rb")
abort("deferred Google Play upload wrapper is missing") unless android_deferred_upload.fetch("run").include?("upload-google-play.sh")
development_apk = android_steps.find { |step| step["id"] == "apk" }
abort("fresh Development APK locator is missing") unless development_apk
abort("Development APK locator must use the build marker") unless development_apk.fetch("run").include?("steps.build_timer.outputs.marker_path")
expected_development_apk_output = "${{ steps.apk.outputs.path }}"
abort("Android action must expose the fresh Development APK path") unless android_action.dig("outputs", "development-apk-path", "value") == expected_development_apk_output
abort("Development APK must not be relayed through GitHub Artifact") if android_steps.any? { |step| step["name"] == "Upload Development APK artifact" }
abort("legacy Development APK Artifact name must be removed") if android_action.to_s.include?("Android-BuildCommit-Development-APK")
aab_locator = android_steps.find { |step| step["id"] == "aab" }
abort("fresh AAB staging is missing") unless aab_locator
abort("non-Development AAB staging must support non-Store recovery") unless aab_locator.fetch("if") == "inputs.development-build != 'true'"
aab_locator_script = aab_locator.fetch("run")
abort("AAB staging must use the current build marker") unless aab_locator_script.include?("steps.build_timer.outputs.marker_path")
expected_mapping_entry = "BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map"
abort("Retrace mapping must be extracted from the staged AAB") unless aab_locator_script.include?(expected_mapping_entry) && aab_locator_script.include?('/usr/bin/unzip -p "$upload_path" "$mapping_entry"')
abort("Retrace mapping must not depend on the build marker timestamp") if aab_locator_script.match?(/mapping_path=.*-newer.*marker_path/)
abort("empty extracted Retrace mapping must fail the Android phase") unless aab_locator_script.include?('[ ! -s "$mapping_upload_path" ]') && aab_locator_script.include?("The Retrace mapping extracted from the staged Android AAB is empty")
abort("minified Android releases must fail when the AAB mapping is missing") unless aab_locator_script.include?("AndroidMinifyRelease") && aab_locator_script.include?("Android release minification is enabled")
android_aab_artifact = android_steps.find { |step| step["name"] == "Upload Android AAB artifact" }
abort("Android recovery AAB Artifact is missing") unless android_aab_artifact
abort("successful Google Play uploads must not retain a duplicate AAB") unless android_aab_artifact.fetch("if").include?("steps.google_play_upload.outcome != 'success'")
abort("Android recovery must require the fresh staged AAB") unless android_aab_artifact.fetch("if").include?("steps.aab.outputs.path != ''")
android_aab_paths = android_aab_artifact.dig("with", "path")
abort("Android recovery must use the fresh AAB output") unless android_aab_paths.include?("steps.aab.outputs.path")
abort("Android recovery must not scan the affinity build directory") if android_aab_paths.include?("UNITY_BUILD_DIR")
abort("Android recovery upload failure must be visible") if android_aab_artifact["continue-on-error"] == true
abort("Android recovery must fail when its staged binary is missing") unless android_aab_artifact.dig("with", "if-no-files-found") == "error"
abort("Android recovery AAB Artifact must expire after three days") unless android_aab_artifact.dig("with", "retention-days") == 3
android_logs = android_steps.find { |step| step["name"] == "Upload Android logs" }
abort("Android failure logs are missing") unless android_logs
abort("Android logs must be failure-only") unless android_logs.fetch("if").include?("failure()")
abort("Android logs must expire after seven days") unless android_logs.dig("with", "retention-days") == 7

ios_steps = ios_action.dig("runs", "steps")
ios_sync_upload = ios_steps.find { |step| step["name"] == "Upload to TestFlight" }
abort("synchronous TestFlight upload is missing") unless ios_sync_upload
abort("synchronous TestFlight upload must expose its exact outcome") unless ios_sync_upload.fetch("id") == "testflight_upload"
abort("synchronous TestFlight upload must be disabled in deferred mode") unless ios_sync_upload.fetch("if").include?("steps.upload_mode.outputs.deferred != 'true'")
abort("synchronous TestFlight upload must use the bounded retry wrapper") unless ios_sync_upload.fetch("run").include?("upload-testflight.rb")
ios_deferred_upload = ios_steps.find { |step| step["name"] == "Start TestFlight upload in background" }
abort("deferred TestFlight upload is missing") unless ios_deferred_upload
abort("deferred TestFlight upload mode guard is missing") unless ios_deferred_upload.fetch("if") == "steps.upload_mode.outputs.deferred == 'true'"
abort("deferred TestFlight upload must use the worker") unless ios_deferred_upload.fetch("run").include?("store-upload-worker.rb")
abort("deferred TestFlight retry wrapper is missing") unless ios_deferred_upload.fetch("run").include?("upload-testflight.rb")
testflight_resolver = ios_steps.find { |step| step["name"] == "Resolve Development TestFlight build number" }
abort("Development TestFlight build-number resolver is missing") unless testflight_resolver
abort("TestFlight build-number resolver must expose its selected number") unless testflight_resolver.fetch("id") == "testflight_build_number"
abort("TestFlight build-number resolver must use the package-owned checker") unless testflight_resolver.fetch("run").include?("check-testflight-build-number.rb")
abort("TestFlight build-number resolver must start from the iOS working-request number") unless testflight_resolver.dig("env", "TESTFLIGHT_BUILD_NUMBER") == "${{ inputs.bundle-no }}"
apply_testflight_number = ios_steps.find { |step| step["name"] == "Apply Development TestFlight build number" }
abort("Resolved TestFlight build-number application is missing") unless apply_testflight_number
abort("Resolved TestFlight build number must update only the supplied working request") unless apply_testflight_number.dig("env", "BUILD_REQUEST_PATH") == "${{ inputs.request-path }}"
abort("Resolved TestFlight build number must be written structurally") unless apply_testflight_number.fetch("run").include?('request["bundleNo"] = resolved')
resolver_index = ios_steps.index(testflight_resolver)
apply_index = ios_steps.index(apply_testflight_number)
unity_build_index = ios_steps.index { |step| step["name"] == "Build iOS Xcode project from BuildCommit request" }
abort("TestFlight build number must resolve before the Unity iOS build") unless resolver_index < apply_index && apply_index < unity_build_index
expected_effective_bundle = "${{ steps.testflight_build_number.outputs.build_number || inputs.bundle-no }}"
abort("iOS action must expose the effective bundle number") unless ios_action.dig("outputs", "effective-bundle-no", "value") == expected_effective_bundle
ios_cleanup = ios_steps.find { |step| step["name"] == "Cleanup old iOS build artifacts" }
abort("iOS cleanup must use the effective bundle number") unless ios_cleanup.dig("env", "BUILD_CLEANUP_BUNDLE_NO") == expected_effective_bundle
ios_app_artifact = ios_steps.find { |step| step["name"] == "Upload iOS app artifact" }
abort("iOS recovery app Artifact is missing") unless ios_app_artifact
abort("successful TestFlight uploads must not retain a duplicate IPA") unless ios_app_artifact.fetch("if").include?("steps.testflight_upload.outcome != 'success'")
abort("iOS recovery must require the fresh exported IPA") unless ios_app_artifact.fetch("if").include?("steps.ipa.outputs.path != ''")
abort("iOS recovery must use only the fresh IPA output") unless ios_app_artifact.dig("with", "path") == "${{ steps.ipa.outputs.path }}"
abort("iOS recovery upload failure must be visible") if ios_app_artifact["continue-on-error"] == true
abort("iOS recovery must fail when its staged binary is missing") unless ios_app_artifact.dig("with", "if-no-files-found") == "error"
abort("iOS recovery app Artifact must expire after three days") unless ios_app_artifact.dig("with", "retention-days") == 3
abort("iOS recovery app Artifact must not duplicate diagnostic logs") if ios_app_artifact.dig("with", "path").include?("UNITY_LOG_DIR")
ios_diagnostics = ios_steps.find { |step| step["name"] == "Upload iOS diagnostic artifact" }
abort("iOS failure diagnostics are missing") unless ios_diagnostics
abort("iOS diagnostics must be failure-only") unless ios_diagnostics.fetch("if") == "failure()"
abort("iOS diagnostics must expire after seven days") unless ios_diagnostics.dig("with", "retention-days") == 7
abort("iOS diagnostics must not duplicate the IPA") if ios_diagnostics.dig("with", "path").include?("IOS_EXPORT_PATH")
RUBY

if grep -Fq 'File.write(path, JSON.pretty_generate(request))' "$workflow"; then
  echo "Workflow must not overwrite the original BuildRequest" >&2
  exit 1
fi

if grep -Fq 'uses: actions/cache@' "$workflow"; then
  echo "Workflow must not save the remote Unity Library cache" >&2
  exit 1
fi

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
locator_script="$fixture_root/locate-aab.sh"
ruby -ryaml - "$android_action" "$locator_script" <<'RUBY'
action_path, output_path = ARGV
action = YAML.load_file(action_path)
locator = action.dig("runs", "steps").find { |step| step["id"] == "aab" }
abort("fresh AAB staging is missing") unless locator
script = locator.fetch("run").sub(
  'marker_path="${{ steps.build_timer.outputs.marker_path }}"',
  'marker_path="${BUILD_MARKER_PATH:?}"'
)
File.write(output_path, script)
RUBY

run_mapping_fixture() {
  local case_root="$1"
  local log_path="$2"
  GITHUB_OUTPUT="$case_root/github-output.txt" \
  BUILD_MARKER_PATH="$case_root/build.marker" \
  UNITY_BUILD_DIR="$case_root/build" \
  ANDROID_UPLOAD_DIR="$case_root/upload" \
  UNITY_LIBRARY_DIR="$case_root/library" \
  UNITY_PROJECT_DIR="$case_root/project" \
  REQUEST_UPLOAD_TARGET=GooglePlayInternal \
    bash "$locator_script" > "$log_path" 2>&1
}

valid_root="$fixture_root/valid"
mkdir -p \
  "$valid_root/build" \
  "$valid_root/payload/BUNDLE-METADATA/com.android.tools.build.obfuscation" \
  "$valid_root/project/ProjectSettings"
printf 'AndroidMinifyRelease: 1\n' > "$valid_root/project/ProjectSettings/ProjectSettings.asset"
printf 'cached-retrace-mapping\n' > "$valid_root/payload/BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map"
touch -t 202001010000 "$valid_root/build.marker"
(cd "$valid_root/payload" && /usr/bin/zip -q -r "$valid_root/build/app.aab" .)
run_mapping_fixture "$valid_root" "$valid_root/run.log"
cmp \
  "$valid_root/payload/BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map" \
  "$valid_root/upload/mapping.txt"
grep -Fxq "mapping_path=$valid_root/upload/mapping.txt" "$valid_root/github-output.txt"

missing_root="$fixture_root/missing"
mkdir -p "$missing_root/build" "$missing_root/payload" "$missing_root/project/ProjectSettings"
printf 'AndroidMinifyRelease: 1\n' > "$missing_root/project/ProjectSettings/ProjectSettings.asset"
printf 'no mapping\n' > "$missing_root/payload/placeholder.txt"
touch -t 202001010000 "$missing_root/build.marker"
(cd "$missing_root/payload" && /usr/bin/zip -q -r "$missing_root/build/app.aab" .)
if run_mapping_fixture "$missing_root" "$missing_root/run.log"; then
  echo "Minified Android release must fail when the AAB mapping is missing" >&2
  exit 1
fi
grep -Fq "Android release minification is enabled" "$missing_root/run.log"

unminified_root="$fixture_root/unminified"
mkdir -p "$unminified_root/build" "$unminified_root/payload" "$unminified_root/project/ProjectSettings"
printf 'AndroidMinifyRelease: 0\n' > "$unminified_root/project/ProjectSettings/ProjectSettings.asset"
printf 'no mapping required\n' > "$unminified_root/payload/placeholder.txt"
touch -t 202001010000 "$unminified_root/build.marker"
(cd "$unminified_root/payload" && /usr/bin/zip -q -r "$unminified_root/build/app.aab" .)
run_mapping_fixture "$unminified_root" "$unminified_root/run.log"
grep -Fxq "mapping_path=" "$unminified_root/github-output.txt"

corrupt_root="$fixture_root/corrupt"
mkdir -p "$corrupt_root/build" "$corrupt_root/project/ProjectSettings"
printf 'AndroidMinifyRelease: 1\n' > "$corrupt_root/project/ProjectSettings/ProjectSettings.asset"
printf 'not an app bundle\n' > "$corrupt_root/build/app.aab"
touch -t 202001010000 "$corrupt_root/build.marker"
if run_mapping_fixture "$corrupt_root" "$corrupt_root/run.log"; then
  echo "Corrupt staged Android AAB must fail before upload" >&2
  exit 1
fi
grep -Fq "Unable to inspect the staged Android AAB" "$corrupt_root/run.log"

echo "Affinity workflow tests passed"
