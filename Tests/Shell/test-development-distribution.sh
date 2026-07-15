#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
slack_uploader="$package_root/.github/scripts/upload-slack-file.sh"
testflight_checker="$package_root/.github/scripts/check-testflight-build-number.rb"
slack_notifier="$package_root/.github/scripts/notify-slack-build-result.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

mkdir -p "$fixture_root/bin"
cat > "$fixture_root/bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "---" >> "$FAKE_CURL_LOG"
printf '%s\n' "$@" >> "$FAKE_CURL_LOG"
last_argument="${!#}"
case "$last_argument" in
  */files.getUploadURLExternal)
    printf '{"ok":true,"upload_url":"http://127.0.0.1:12345/upload","file_id":"F123"}\n'
    ;;
  http://127.0.0.1:12345/upload)
    printf 'uploaded\n'
    ;;
  */files.completeUploadExternal)
    printf '{"ok":true}\n'
    ;;
  https://hooks.slack.com/services/*)
    ;;
  *)
    exit 64
    ;;
esac
FAKE_CURL
chmod +x "$fixture_root/bin/curl"

apk_path="$fixture_root/development.apk"
printf 'development-apk\n' > "$apk_path"
slack_output="$(
  PATH="$fixture_root/bin:$PATH" \
  FAKE_CURL_LOG="$fixture_root/curl.log" \
  SLACK_BUILD_BOT_TOKEN="xoxb-fixture-token" \
  SLACK_BUILD_CHANNEL_ID="C12345678" \
  SLACK_FILE_PATH="$apk_path" \
  BUILD_PROJECT_NAME="FixtureProject" \
  BUILD_VERSION="5.5.5" \
  BUILD_BUNDLE_NO="555" \
  BUILD_SHORT_SHA="0123456789" \
  BUILD_RUN_URL="https://example.invalid/run" \
  SLACK_BUILD_MENTIONS="U12345678" \
    bash "$slack_uploader"
)"
if printf '%s\n' "$slack_output" | grep -v '^::add-mask::' | grep -F 'xoxb-fixture-token' >/dev/null; then
  echo "Slack uploader must not print the bot token outside masking commands" >&2
  exit 1
fi
grep -F 'files.getUploadURLExternal' "$fixture_root/curl.log" >/dev/null
grep -F 'files.completeUploadExternal' "$fixture_root/curl.log" >/dev/null
grep -F '[DEVELOPMENT BUILD] FixtureProject Android v5.5.5(555)' "$fixture_root/curl.log" >/dev/null
grep -F '"channel_id":"C12345678"' "$fixture_root/curl.log" >/dev/null

PATH="$fixture_root/bin:$PATH" \
FAKE_CURL_LOG="$fixture_root/curl.log" \
SLACK_BUILD_WEBHOOK_URL="https://hooks.slack.com/services/fixture" \
BUILD_JOB_STATUS=success \
BUILD_PLATFORM=iOS \
BUILD_PROJECT_NAME="FixtureProject" \
BUILD_VERSION="5.5.5" \
BUILD_BUNDLE_NO="1" \
BUILD_DEVELOPMENT_BUILD=true \
  bash "$slack_notifier" >/dev/null
grep -F '[DEVELOPMENT BUILD] [OK] FixtureProject iOS BuildCommit SUCCESS - v5.5.5(1)' "$fixture_root/curl.log" >/dev/null

set +e
missing_config_output="$(
  HOME="$fixture_root/no-config-home" \
  SLACK_FILE_PATH="$apk_path" \
    bash "$slack_uploader" 2>&1
)"
missing_config_status=$?
set -e
if [ "$missing_config_status" -ne 2 ] || ! printf '%s\n' "$missing_config_output" | grep -F 'GitHub Artifact fallback' >/dev/null; then
  echo "Missing Slack Bot configuration must produce a nonfatal fallback signal" >&2
  exit 1
fi

cat > "$fixture_root/fake-fastlane" <<'FAKE_FASTLANE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$FAKE_FASTLANE_ARGS"
case "${FAKE_FASTLANE_MODE:-available}" in
  collision)
    printf '| Version | Build | State |\n| 5.5.5 | 1 | processing |\n'
    ;;
  available)
    printf '| Version | Build | State |\n| 5.5.5 | 555 | ready |\n'
    ;;
esac
FAKE_FASTLANE
chmod +x "$fixture_root/fake-fastlane"
printf '{}\n' > "$fixture_root/app-store-key.json"

FASTLANE_CMD="$fixture_root/fake-fastlane" \
FAKE_FASTLANE_ARGS="$fixture_root/fastlane-args" \
APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/app-store-key.json" \
IOS_BUNDLE_ID="com.actionfit.fixture" \
TESTFLIGHT_BUILD_VERSION="5.5.5" \
TESTFLIGHT_BUILD_NUMBER="1" \
  ruby "$testflight_checker" >/dev/null
ruby -e '
  actual = File.readlines(ARGV.fetch(0)).map(&:chomp)
  expected = [
    "pilot", "builds",
    "--api_key_path", ARGV.fetch(1),
    "--app_identifier", "com.actionfit.fixture",
    "--app_platform", "ios"
  ]
  abort("unexpected TestFlight lookup arguments: #{actual.inspect}") unless actual == expected
' "$fixture_root/fastlane-args" "$fixture_root/app-store-key.json"

set +e
collision_output="$(
  FASTLANE_CMD="$fixture_root/fake-fastlane" \
  FAKE_FASTLANE_MODE=collision \
  FAKE_FASTLANE_ARGS="$fixture_root/fastlane-collision-args" \
  APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/app-store-key.json" \
  IOS_BUNDLE_ID="com.actionfit.fixture" \
  TESTFLIGHT_BUILD_VERSION="5.5.5" \
  TESTFLIGHT_BUILD_NUMBER="1" \
    ruby "$testflight_checker" 2>&1
)"
collision_status=$?
set -e
if [ "$collision_status" -ne 3 ] || ! printf '%s\n' "$collision_output" | grep -F 'already contains build 5.5.5(1)' >/dev/null; then
  echo "TestFlight build-number collision must fail clearly" >&2
  exit 1
fi

echo "Development distribution tests passed"
