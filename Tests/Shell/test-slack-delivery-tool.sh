#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
delivery_tool="$package_root/RunnerSetup/deliver-buildcommit-slack"
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
exit "${FAKE_UPLOAD_STATUS:-0}"
FAKE_UPLOAD
chmod +x "$fixture_root/fake-notify" "$fixture_root/fake-upload"

notify_log="$fixture_root/notify.log"
upload_log="$fixture_root/upload.log"
common_env=(
  env
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
"${common_env[@]}" \
  SOURCE_CONCLUSION=success \
  SLACK_APK_ROOT="$apk_root" \
  bash "$delivery_tool" complete >/dev/null
grep -Fx "$apk_path|FixtureProject|Android|5.5.5|555|U12345678" "$upload_log" >/dev/null
if [ -e "$notify_log" ]; then
  echo "Successful Development APK delivery must not send a duplicate webhook notification" >&2
  exit 1
fi

rm -f "$notify_log" "$upload_log"
"${common_env[@]}" \
  SOURCE_CONCLUSION=success \
  SLACK_APK_ROOT="$apk_root" \
  FAKE_UPLOAD_STATUS=2 \
  bash "$delivery_tool" complete >/dev/null
grep -Fx "$apk_path|FixtureProject|Android|5.5.5|555|U12345678" "$upload_log" >/dev/null
grep -Fx 'success|FixtureProject|Android|true|5.5.5|555|Actionfit|U12345678|0123456789abcdef0123456789abcdef01234567' "$notify_log" >/dev/null

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
"${common_env[@]}" \
  SOURCE_CONCLUSION=success \
  SLACK_APK_ROOT="$apk_root" \
  bash "$delivery_tool" complete >/dev/null
test ! -e "$upload_log"
grep -Fx 'success|FixtureProject|Android|true|5.5.5|555|Actionfit|U12345678|0123456789abcdef0123456789abcdef01234567' "$notify_log" >/dev/null

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
ruby -e '
  expected = {
    ARGV.fetch(0) => 0o700,
    ARGV.fetch(1) => 0o700,
    ARGV.fetch(2) => 0o600,
    ARGV.fetch(3) => 0o600,
    ARGV.fetch(4) => 0o600
  }
  expected.each do |path, mode|
    actual = File.stat(path).mode & 0o777
    abort("unexpected mode #{actual.to_s(8)} for #{path}") unless actual == mode
  end
' \
  "$install_root/secrets" \
  "$install_root/secrets/shared" \
  "$install_root/secrets/shared/slack-webhook-url" \
  "$install_root/secrets/shared/slack-bot-token" \
  "$install_root/secrets/shared/slack-channel-id"

printf 'xoxb-preserved-fixture\n' > "$install_root/secrets/shared/slack-bot-token"
SLACK_DELIVERY_ROOT="$install_root" bash "$install_script" >/dev/null
grep -Fx 'xoxb-preserved-fixture' "$install_root/secrets/shared/slack-bot-token" >/dev/null
test "$(wc -l < "$install_root/secrets/shared/slack-bot-token" | tr -d '[:space:]')" -eq 1

echo "Slack delivery host tool tests passed"
