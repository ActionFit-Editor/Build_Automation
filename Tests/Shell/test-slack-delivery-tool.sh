#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
delivery_tool="$package_root/RunnerSetup/deliver-buildcommit-slack"
grep -F 'exit(3) unless File.exist?(path) || File.symlink?(path)' "$delivery_tool" >/dev/null
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

request_path="$fixture_root/build_request.json"
cat > "$request_path" <<'JSON'
{
  "schemaVersion": 12,
  "triggerSource": "BuildCommit",
  "unityProjectPath": "",
  "autoConfigureBuildSymbols": false,
  "developmentBuild": true,
  "platform": 1,
  "buildKind": 0,
  "uploadTarget": 0,
  "distributionProfile": 0,
  "buildVersion": "5.5.5",
  "bundleNo": "555",
  "buildFileName": "",
  "androidPackageName": "com.actionfit.fixture",
  "iosBundleId": "",
  "androidKeystoreFileName": "",
  "androidKeystoreBase64": "",
  "androidKeystorePassword": "",
  "androidAliasPassword": "",
  "androidKeyaliasName": "",
  "slackMentions": ["U12345678"],
  "sourceBranch": "dev_jewoo",
  "sourceCommit": "0123456789abcdef0123456789abcdef01234567",
  "createdAtUtc": "2026-07-16T00:00:00Z"
}
JSON

cat > "$fixture_root/fake-notify" <<'FAKE_NOTIFY'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
  "${BUILD_JOB_STATUS:-}" \
  "${BUILD_PROJECT_NAME:-}" \
  "${BUILD_PLATFORM:-}" \
  "${BUILD_DEVELOPMENT_BUILD:-}" \
  "${BUILD_VERSION:-}" \
  "${BUILD_BUNDLE_NO:-}" \
  "${BUILD_DISTRIBUTION_PROFILE:-}" \
  "${SLACK_BUILD_MENTIONS:-}" \
  "${BUILD_SHORT_SHA:-}" >> "$FAKE_NOTIFY_LOG"
exit "${FAKE_NOTIFY_STATUS:-0}"
FAKE_NOTIFY

cat > "$fixture_root/fake-upload" <<'FAKE_UPLOAD'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s|%s|%s|%s|%s\n' \
  "${SLACK_FILE_PATH:-}" \
  "${BUILD_PROJECT_NAME:-}" \
  "${BUILD_PLATFORM:-}" \
  "${BUILD_VERSION:-}" \
  "${BUILD_BUNDLE_NO:-}" \
  "${SLACK_BUILD_MENTIONS:-}" >> "$FAKE_UPLOAD_LOG"
status="${FAKE_UPLOAD_STATUS:-0}"
if [ -n "${SLACK_UPLOAD_PHASE_PATH:-}" ]; then
  phase="${FAKE_UPLOAD_PHASE:-}"
  if [ -z "$phase" ]; then
    if [ "$status" -eq 0 ]; then
      phase=completed
    else
      phase=preflight-complete
    fi
  fi
  printf '%s\n' "$phase" > "$SLACK_UPLOAD_PHASE_PATH"
fi
if [ "$status" -eq 0 ] && [ "${FAKE_UPLOAD_SUPPRESS_RECEIPT:-false}" != true ] && [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'slack_file_id=FDELIVERED123\n' >> "$GITHUB_OUTPUT"
fi
exit "$status"
FAKE_UPLOAD
chmod +x "$fixture_root/fake-notify" "$fixture_root/fake-upload"

notify_log="$fixture_root/notify.log"
upload_log="$fixture_root/upload.log"
delivery_root="$fixture_root/delivery-root"
mkdir -p "$delivery_root/receipts"
chmod 700 "$delivery_root" "$delivery_root/receipts"
common_env=(
  env
  SLACK_DELIVERY_ROOT="$delivery_root"
  BUILD_REQUEST_PATH="$request_path"
  SOURCE_REPOSITORY="ActionFitGames/FixtureProject"
  SOURCE_SHA="0123456789abcdef0123456789abcdef01234567"
  SOURCE_RUN_URL="https://github.com/ActionFitGames/FixtureProject/actions/runs/12345"
  SOURCE_RUN_ID="12345"
  SOURCE_RUN_ATTEMPT="2"
  SOURCE_EVENT="push"
  SOURCE_RUN_STARTED_AT="2026-07-16T00:00:00Z"
  SLACK_NOTIFY_SCRIPT="$fixture_root/fake-notify"
  SLACK_UPLOAD_SCRIPT="$fixture_root/fake-upload"
  FAKE_NOTIFY_LOG="$notify_log"
  FAKE_UPLOAD_LOG="$upload_log"
)

inspect_output="$fixture_root/inspect-output"
: > "$inspect_output"
"${common_env[@]}" GITHUB_OUTPUT="$inspect_output" bash "$delivery_tool" inspect >/dev/null
grep -Fx 'request_state=build' "$inspect_output" >/dev/null
grep -Fx 'should_build=true' "$inspect_output" >/dev/null
grep -Fx 'development_android=true' "$inspect_output" >/dev/null
grep -Fx 'apk_already_delivered=false' "$inspect_output" >/dev/null
test ! -e "$notify_log"
test ! -e "$upload_log"

start_output="$fixture_root/start-output"
: > "$start_output"
"${common_env[@]}" GITHUB_OUTPUT="$start_output" bash "$delivery_tool" start >/dev/null
grep -E '^started_at_epoch=[0-9]+$' "$start_output" >/dev/null
grep -Fx 'start|FixtureProject|Android|true|5.5.5|555|Actionfit|U12345678|0123456789abcdef0123456789abcdef01234567' "$notify_log" >/dev/null
test ! -e "$upload_log"

rm -f "$notify_log" "$upload_log"
apk_root="$fixture_root/apk"
mkdir -p "$apk_root"
apk_path="$apk_root/FixtureProject-development.apk"
printf 'development-apk\n' > "$apk_path"
complete_output="$fixture_root/complete-output"
: > "$complete_output"
"${common_env[@]}" \
  SOURCE_CONCLUSION=success \
  SLACK_APK_ROOT="$apk_root" \
  GITHUB_OUTPUT="$complete_output" \
  bash "$delivery_tool" complete >/dev/null
grep -Fx "$apk_path|FixtureProject|Android|5.5.5|555|U12345678" "$upload_log" >/dev/null
grep -Fx 'slack_file_id=FDELIVERED123' "$complete_output" >/dev/null
grep -Fx 'apk_delivered=false' "$complete_output" >/dev/null
grep -Fx 'apk_delivered=true' "$complete_output" >/dev/null
if [ -e "$notify_log" ]; then
  echo "Successful Development APK delivery must not send a duplicate webhook notification" >&2
  exit 1
fi

receipt_path="$(find "$delivery_root/receipts" -maxdepth 1 -type f -name '*.json' -print -quit)"
test -n "$receipt_path"
ruby -rjson -e '
  path = ARGV.fetch(0)
  payload = JSON.parse(File.binread(path))
  abort("receipt mode must be 0600") unless (File.stat(path).mode & 0o777) == 0o600
  abort("receipt schema mismatch") unless payload["schema_version"] == 1
  abort("receipt state mismatch") unless payload["state"] == "delivered"
  abort("receipt repository mismatch") unless payload["source_repository"] == "ActionFitGames/FixtureProject"
  abort("receipt run mismatch") unless payload["source_run_id"] == "12345"
  abort("receipt attempt mismatch") unless payload["source_run_attempt"] == "2"
  abort("receipt SHA mismatch") unless payload["source_sha"] == "0123456789abcdef0123456789abcdef01234567"
  abort("receipt file ID mismatch") unless payload["slack_file_id"] == "FDELIVERED123"
' "$receipt_path"

rm -f "$notify_log" "$upload_log"
rerun_inspect_output="$fixture_root/rerun-inspect-output"
: > "$rerun_inspect_output"
"${common_env[@]}" GITHUB_OUTPUT="$rerun_inspect_output" bash "$delivery_tool" inspect >/dev/null
grep -Fx 'apk_already_delivered=true' "$rerun_inspect_output" >/dev/null
grep -Fx 'slack_file_id=FDELIVERED123' "$rerun_inspect_output" >/dev/null

rm -rf "$apk_root"
rerun_complete_output="$fixture_root/rerun-complete-output"
: > "$rerun_complete_output"
"${common_env[@]}" \
  SOURCE_CONCLUSION=success \
  SLACK_APK_ROOT="$apk_root" \
  GITHUB_OUTPUT="$rerun_complete_output" \
  FAKE_UPLOAD_STATUS=2 \
  bash "$delivery_tool" complete >/dev/null
grep -Fx 'slack_file_id=FDELIVERED123' "$rerun_complete_output" >/dev/null
grep -Fx 'apk_delivered=true' "$rerun_complete_output" >/dev/null
test ! -e "$notify_log"
test ! -e "$upload_log"

mkdir -p "$apk_root"
printf 'development-apk\n' > "$apk_path"

rm -f "$notify_log" "$upload_log"
failed_complete_output="$fixture_root/failed-complete-output"
: > "$failed_complete_output"
set +e
"${common_env[@]}" \
  SOURCE_CONCLUSION=success \
  SOURCE_RUN_ATTEMPT=3 \
  SLACK_APK_ROOT="$apk_root" \
  GITHUB_OUTPUT="$failed_complete_output" \
  FAKE_UPLOAD_STATUS=2 \
  bash "$delivery_tool" complete >/dev/null
failed_complete_status=$?
set -e
if [ "$failed_complete_status" -eq 0 ]; then
  echo "Development APK Slack upload failure must fail the delivery command" >&2
  exit 1
fi
grep -Fx "$apk_path|FixtureProject|Android|5.5.5|555|U12345678" "$upload_log" >/dev/null
grep -Fx 'apk_delivery_failure|FixtureProject|Android|true|5.5.5|555|Actionfit|U12345678|0123456789abcdef0123456789abcdef01234567' "$notify_log" >/dev/null
grep -Fx 'apk_delivered=false' "$failed_complete_output" >/dev/null
if grep -Fx 'apk_delivered=true' "$failed_complete_output" >/dev/null; then
  echo "Failed Development APK delivery must not emit a success receipt" >&2
  exit 1
fi
retry_safe_receipt_path="$(
  ruby -rdigest -e '
    identity = ["v1", "ActionFitGames/FixtureProject", "12345", "3"].join("\0")
    puts File.join(ARGV.fetch(0), "#{Digest::SHA256.hexdigest(identity)}.json")
  ' "$delivery_root/receipts"
)"
if [ -e "$retry_safe_receipt_path" ] || [ -L "$retry_safe_receipt_path" ]; then
  echo "A failure before Slack completion must release its retry-safe pending receipt" >&2
  exit 1
fi

corrupt_receipt_path="$(
  ruby -rdigest -e '
    identity = ["v1", "ActionFitGames/FixtureProject", "12345", "5"].join("\0")
    puts File.join(ARGV.fetch(0), "#{Digest::SHA256.hexdigest(identity)}.json")
  ' "$delivery_root/receipts"
)"
printf '{invalid-json\n' > "$corrupt_receipt_path"
chmod 600 "$corrupt_receipt_path"
rm -f "$notify_log" "$upload_log"
corrupt_output="$fixture_root/corrupt-output"
: > "$corrupt_output"
set +e
"${common_env[@]}" \
  SOURCE_RUN_ATTEMPT=5 \
  GITHUB_OUTPUT="$corrupt_output" \
  bash "$delivery_tool" inspect >/dev/null 2>&1
corrupt_status=$?
set -e
if [ "$corrupt_status" -eq 0 ]; then
  echo "A corrupt Slack delivery receipt must fail closed" >&2
  exit 1
fi
test ! -e "$notify_log"
test ! -e "$upload_log"
rm -f "$corrupt_receipt_path"

rm -f "$notify_log" "$upload_log"
missing_child_receipt_output="$fixture_root/missing-child-receipt-output"
printf 'slack_file_id=FSTALEPARENT999\n' > "$missing_child_receipt_output"
set +e
"${common_env[@]}" \
  SOURCE_CONCLUSION=success \
  SOURCE_RUN_ATTEMPT=6 \
  SLACK_APK_ROOT="$apk_root" \
  GITHUB_OUTPUT="$missing_child_receipt_output" \
  FAKE_UPLOAD_SUPPRESS_RECEIPT=true \
  bash "$delivery_tool" complete >/dev/null 2>&1
missing_child_receipt_status=$?
set -e
if [ "$missing_child_receipt_status" -eq 0 ]; then
  echo "The delivery tool must not reuse a stale parent step output as a Slack receipt" >&2
  exit 1
fi
if grep -Fx 'apk_delivered=true' "$missing_child_receipt_output" >/dev/null; then
  echo "A missing child upload receipt must not emit apk_delivered=true" >&2
  exit 1
fi
grep -Fx "$apk_path|FixtureProject|Android|5.5.5|555|U12345678" "$upload_log" >/dev/null
grep -Fx 'apk_delivery_failure|FixtureProject|Android|true|5.5.5|555|Actionfit|U12345678|0123456789abcdef0123456789abcdef01234567' "$notify_log" >/dev/null

pending_receipt_path="$(
  ruby -rdigest -e '
    identity = ["v1", "ActionFitGames/FixtureProject", "12345", "6"].join("\0")
    puts File.join(ARGV.fetch(0), "#{Digest::SHA256.hexdigest(identity)}.json")
  ' "$delivery_root/receipts"
)"
ruby -rjson -e '
  payload = JSON.parse(File.binread(ARGV.fetch(0)))
  abort("ambiguous upload must preserve a pending receipt") unless payload["state"] == "pending"
  abort("pending receipt must not claim a Slack file") unless payload["slack_file_id"] == ""
' "$pending_receipt_path"
rm -f "$notify_log" "$upload_log"
pending_inspect_output="$fixture_root/pending-inspect-output"
: > "$pending_inspect_output"
set +e
"${common_env[@]}" \
  SOURCE_RUN_ATTEMPT=6 \
  GITHUB_OUTPUT="$pending_inspect_output" \
  bash "$delivery_tool" inspect >/dev/null 2>&1
pending_inspect_status=$?
set -e
if [ "$pending_inspect_status" -eq 0 ]; then
  echo "A pending Slack attempt must block automatic duplicate delivery" >&2
  exit 1
fi
test ! -e "$notify_log"
test ! -e "$upload_log"

rm -f "$notify_log" "$upload_log"
invalid_output="$fixture_root/invalid-output"
: > "$invalid_output"
"${common_env[@]}" \
  SOURCE_EVENT=pull_request \
  GITHUB_OUTPUT="$invalid_output" \
  bash "$delivery_tool" inspect >/dev/null
grep -Fx 'request_state=invalid' "$invalid_output" >/dev/null
grep -Fx 'should_build=false' "$invalid_output" >/dev/null
grep -Fx 'development_android=false' "$invalid_output" >/dev/null
test ! -e "$notify_log"
test ! -e "$upload_log"

current_request_path="$fixture_root/current-build-request.json"
ruby -rjson -e '
  request = JSON.parse(File.binread(ARGV.fetch(0)))
  request["platform"] = 0
  request["distributionProfile"] = 1
  request["slackMentions"] = [
    "U12345678",
    "<!channel>",
    "<@U99999999>",
    "W87654321",
    "https://example.invalid/not-a-member"
  ]
  File.open(ARGV.fetch(1), "wb", 0o600) { |file| file.write(JSON.generate(request)) }
' "$request_path" "$current_request_path"

current_output="$fixture_root/current-output"
: > "$current_output"
"${common_env[@]}" \
  BUILD_REQUEST_PATH="$current_request_path" \
  GITHUB_OUTPUT="$current_output" \
  bash "$delivery_tool" inspect >/dev/null
grep -Fx 'request_state=build' "$current_output" >/dev/null
grep -Fx 'should_build=true' "$current_output" >/dev/null
grep -Fx 'development_android=true' "$current_output" >/dev/null

rm -f "$notify_log" "$upload_log"
"${common_env[@]}" \
  BUILD_REQUEST_PATH="$current_request_path" \
  bash "$delivery_tool" start >/dev/null
grep -Fx 'start|FixtureProject|Current|true|5.5.5|555|Stormborn|U12345678 W87654321|0123456789abcdef0123456789abcdef01234567' "$notify_log" >/dev/null
if grep -E '<!channel>|<@U99999999>|https://example.invalid' "$notify_log" >/dev/null; then
  echo "Slack delivery must discard values outside the raw member ID allowlist" >&2
  exit 1
fi

rm -f "$notify_log" "$upload_log"
printf 'second-development-apk\n' > "$apk_root/second.apk"
set +e
"${common_env[@]}" \
  SOURCE_CONCLUSION=success \
  SOURCE_RUN_ATTEMPT=4 \
  SLACK_APK_ROOT="$apk_root" \
  bash "$delivery_tool" complete >/dev/null
invalid_apk_status=$?
set -e
if [ "$invalid_apk_status" -eq 0 ]; then
  echo "Invalid Development APK artifact must fail the delivery command" >&2
  exit 1
fi
test ! -e "$upload_log"
grep -Fx 'apk_delivery_failure|FixtureProject|Android|true|5.5.5|555|Actionfit|U12345678|0123456789abcdef0123456789abcdef01234567' "$notify_log" >/dev/null

set +e
"${common_env[@]}" bash "$delivery_tool" inspect unexpected-argument >/dev/null 2>&1
invalid_cli_status=$?
set -e
if [ "$invalid_cli_status" -ne 64 ]; then
  echo "Invalid Slack delivery CLI usage must exit 64" >&2
  exit 1
fi

install_script="$package_root/RunnerSetup/install-slack-delivery-tool.sh"
install_root="$fixture_root/installed-slack-delivery"
SLACK_DELIVERY_ROOT="$install_root" bash "$install_script" >/dev/null
test -x "$install_root/bin/deliver-buildcommit-slack"
test -x "$install_root/bin/notify-slack-build-result.sh"
test -x "$install_root/bin/upload-slack-file.sh"
test -d "$install_root/receipts"
ruby -e '
  expected = {
    ARGV.fetch(0) => 0o700,
    ARGV.fetch(1) => 0o700,
    ARGV.fetch(2) => 0o700,
    ARGV.fetch(3) => 0o600,
    ARGV.fetch(4) => 0o600,
    ARGV.fetch(5) => 0o600
  }
  expected.each do |path, mode|
    actual = File.stat(path).mode & 0o777
    abort("unexpected mode #{actual.to_s(8)} for #{path}") unless actual == mode
  end
' \
  "$install_root/secrets" \
  "$install_root/secrets/shared" \
  "$install_root/receipts" \
  "$install_root/secrets/shared/slack-webhook-url" \
  "$install_root/secrets/shared/slack-bot-token" \
  "$install_root/secrets/shared/slack-channel-id"

printf 'xoxb-preserved-fixture\n' > "$install_root/secrets/shared/slack-bot-token"
printf '{"preserved":true}\n' > "$install_root/receipts/preserved-fixture.json"
chmod 600 "$install_root/receipts/preserved-fixture.json"
SLACK_DELIVERY_ROOT="$install_root" bash "$install_script" >/dev/null
grep -Fx 'xoxb-preserved-fixture' "$install_root/secrets/shared/slack-bot-token" >/dev/null
grep -Fx '{"preserved":true}' "$install_root/receipts/preserved-fixture.json" >/dev/null
test "$(wc -l < "$install_root/secrets/shared/slack-bot-token" | tr -d '[:space:]')" -eq 1

echo "Slack delivery host tool tests passed"
