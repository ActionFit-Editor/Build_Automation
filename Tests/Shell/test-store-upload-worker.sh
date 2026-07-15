#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
worker="$package_root/.github/scripts/store-upload-worker.rb"
testflight_uploader="$package_root/.github/scripts/upload-testflight.rb"
google_play_uploader="$package_root/.github/scripts/upload-google-play.sh"
fixture_root="$(mktemp -d)"
worker_state_root="$fixture_root/store-upload-state"

cleanup() {
  set +e
  for task in success failure timeout cancel; do
    STORE_UPLOAD_STATE_ROOT="$worker_state_root" \
      ruby "$worker" cancel "$task" >/dev/null 2>&1
  done
  rm -rf "$fixture_root"
}
trap cleanup EXIT INT TERM

assert_state() {
  state_path="$1"
  expected_state="$2"
  expected_exit_code="$3"
  ruby -rjson -e '
    state = JSON.parse(File.read(ARGV.fetch(0)))
    expected_state = ARGV.fetch(1)
    expected_exit_code = Integer(ARGV.fetch(2), 10)
    abort("unexpected worker state: #{state.inspect}") unless state["state"] == expected_state
    abort("unexpected worker exit code: #{state.inspect}") unless state["exit_code"] == expected_exit_code
    abort("worker terminal timestamp is missing: #{state.inspect}") if state["completed_at"].to_s.empty?
  ' "$state_path" "$expected_state" "$expected_exit_code"
}

export STORE_UPLOAD_STATE_ROOT="$worker_state_root"
export STORE_UPLOAD_POLL_SECONDS=0.05

ruby "$worker" start success 10 -- /bin/sh -c 'printf "worker-success-output\n"'
ruby "$worker" wait success
assert_state "$worker_state_root/success/state.json" succeeded 0
grep -F 'worker-success-output' "$worker_state_root/success/upload.log" >/dev/null

ruby "$worker" start failure 10 -- /bin/sh -c 'printf "worker-failure-output\n"; exit 17'
set +e
failure_output="$(ruby "$worker" wait failure 2>&1)"
failure_status=$?
set -e
if [ "$failure_status" -ne 17 ]; then
  printf '%s\n' "$failure_output" >&2
  echo "Expected failed upload worker to preserve exit code 17, got $failure_status" >&2
  exit 1
fi
assert_state "$worker_state_root/failure/state.json" failed 17

ruby "$worker" start timeout 1 -- /bin/sh -c 'sleep 30'
set +e
timeout_output="$(ruby "$worker" wait timeout 2>&1)"
timeout_status=$?
set -e
if [ "$timeout_status" -ne 124 ]; then
  printf '%s\n' "$timeout_output" >&2
  echo "Expected timed out upload worker to exit 124, got $timeout_status" >&2
  exit 1
fi
assert_state "$worker_state_root/timeout/state.json" timed_out 124

ruby "$worker" start cancel 30 -- /bin/sh -c 'sleep 30'
ruby "$worker" cancel cancel
set +e
cancel_output="$(ruby "$worker" wait cancel 2>&1)"
cancel_status=$?
set -e
if [ "$cancel_status" -ne 130 ]; then
  printf '%s\n' "$cancel_output" >&2
  echo "Expected cancelled upload worker to exit 130, got $cancel_status" >&2
  exit 1
fi
assert_state "$worker_state_root/cancel/state.json" cancelled 130
ruby "$worker" cancel cancel

fake_testflight_fastlane="$fixture_root/fake-testflight-fastlane"
cat > "$fake_testflight_fastlane" <<'FAKE_TESTFLIGHT'
#!/bin/sh
set -eu

count=0
if [ -r "$FAKE_FASTLANE_COUNT_FILE" ]; then
  count="$(sed -n '1p' "$FAKE_FASTLANE_COUNT_FILE")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$FAKE_FASTLANE_COUNT_FILE"
printf '%s\n' "${TMPDIR:-}" >> "$FAKE_FASTLANE_TMPDIR_FILE"
: > "$FAKE_FASTLANE_ARGS_PREFIX.$count"
for argument in "$@"; do
  printf '%s\n' "$argument" >> "$FAKE_FASTLANE_ARGS_PREFIX.$count"
done

if [ "${FAKE_FASTLANE_MODE:-retry}" = hang ]; then
  sleep 30
  exit 0
fi

if [ "$count" -eq 1 ]; then
  exit 75
fi
FAKE_TESTFLIGHT
chmod +x "$fake_testflight_fastlane"

app_store_key="$fixture_root/app-store-key.json"
ipa_path="$fixture_root/TestBuild.ipa"
printf '{}\n' > "$app_store_key"
printf 'test-ipa\n' > "$ipa_path"

FASTLANE_CMD="$fake_testflight_fastlane" \
FAKE_FASTLANE_COUNT_FILE="$fixture_root/testflight-count" \
FAKE_FASTLANE_TMPDIR_FILE="$fixture_root/testflight-tmpdirs" \
FAKE_FASTLANE_ARGS_PREFIX="$fixture_root/testflight-args" \
APP_STORE_CONNECT_API_KEY_JSON_PATH="$app_store_key" \
IOS_IPA_PATH="$ipa_path" \
IOS_BUNDLE_ID="com.actionfit.test" \
TESTFLIGHT_UPLOAD_ATTEMPTS=2 \
TESTFLIGHT_UPLOAD_ATTEMPT_TIMEOUT_SECONDS=5 \
TESTFLIGHT_UPLOAD_RETRY_DELAY_SECONDS=0 \
RUNNER_TEMP="$fixture_root" \
  ruby "$testflight_uploader"

test "$(sed -n '1p' "$fixture_root/testflight-count")" = 2
ruby -e '
  actual = File.readlines(ARGV.fetch(0)).map(&:chomp)
  expected = [
    "pilot",
    "upload",
    "--api_key_path", ARGV.fetch(1),
    "--app_identifier", "com.actionfit.test",
    "--ipa", ARGV.fetch(2),
    "--skip_waiting_for_build_processing"
  ]
  abort("unexpected TestFlight arguments: #{actual.inspect}") unless actual == expected
' "$fixture_root/testflight-args.2" "$app_store_key" "$ipa_path"
ruby -e '
  paths = File.readlines(ARGV.fetch(0)).map { |line| line.strip.sub(%r{/\z}, "") }
  abort("each TestFlight retry must use a fresh TMPDIR: #{paths.inspect}") unless paths.length == 2 && paths.uniq.length == 2
  abort("TestFlight attempt TMPDIR was not removed: #{paths.inspect}") if paths.any? { |path| File.exist?(path) }
' "$fixture_root/testflight-tmpdirs"

set +e
FASTLANE_CMD="$fake_testflight_fastlane" \
FAKE_FASTLANE_MODE=hang \
FAKE_FASTLANE_COUNT_FILE="$fixture_root/testflight-timeout-count" \
FAKE_FASTLANE_TMPDIR_FILE="$fixture_root/testflight-timeout-tmpdirs" \
FAKE_FASTLANE_ARGS_PREFIX="$fixture_root/testflight-timeout-args" \
APP_STORE_CONNECT_API_KEY_JSON_PATH="$app_store_key" \
IOS_IPA_PATH="$ipa_path" \
IOS_BUNDLE_ID="com.actionfit.test" \
TESTFLIGHT_UPLOAD_ATTEMPTS=1 \
TESTFLIGHT_UPLOAD_ATTEMPT_TIMEOUT_SECONDS=1 \
TESTFLIGHT_UPLOAD_RETRY_DELAY_SECONDS=0 \
RUNNER_TEMP="$fixture_root" \
  ruby "$testflight_uploader" >/dev/null 2>&1
testflight_timeout_status=$?
set -e
if [ "$testflight_timeout_status" -ne 124 ]; then
  echo "Expected a stalled TestFlight upload attempt to exit 124, got $testflight_timeout_status" >&2
  exit 1
fi
test "$(sed -n '1p' "$fixture_root/testflight-timeout-count")" = 1

fake_google_fastlane="$fixture_root/fake-google-fastlane"
cat > "$fake_google_fastlane" <<'FAKE_GOOGLE'
#!/bin/sh
set -eu

: > "$FAKE_GOOGLE_ARGS_FILE"
for argument in "$@"; do
  printf '%s\n' "$argument" >> "$FAKE_GOOGLE_ARGS_FILE"
done
printf '%s\n%s\n' "${FASTLANE_DISABLE_COLORS:-}" "${FASTLANE_SKIP_UPDATE_CHECK:-}" > "$FAKE_GOOGLE_ENV_FILE"
FAKE_GOOGLE
chmod +x "$fake_google_fastlane"

service_account_json="$fixture_root/google-service-account.json"
aab_path="$fixture_root/TestBuild.aab"
mapping_path="$fixture_root/mapping.txt"
debug_symbols_path="$fixture_root/native-symbols.zip"
printf '{}\n' > "$service_account_json"
printf 'test-aab\n' > "$aab_path"
printf 'test-mapping\n' > "$mapping_path"
printf 'test-symbols\n' > "$debug_symbols_path"

ACTIONFIT_FASTLANE_CMD="$fake_google_fastlane" \
FAKE_GOOGLE_ARGS_FILE="$fixture_root/google-args" \
FAKE_GOOGLE_ENV_FILE="$fixture_root/google-env" \
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="$service_account_json" \
ANDROID_PACKAGE_NAME="com.actionfit.test" \
ANDROID_AAB_PATH="$aab_path" \
ANDROID_MAPPING_PATH="$mapping_path" \
ANDROID_DEBUG_SYMBOLS_PATH="$debug_symbols_path" \
  /bin/bash "$google_play_uploader"

ruby -e '
  actual = File.readlines(ARGV.fetch(0)).map(&:chomp)
  expected = [
    "supply",
    "--json_key", ARGV.fetch(1),
    "--package_name", "com.actionfit.test",
    "--aab", ARGV.fetch(2),
    "--track", "internal",
    "--release_status", "completed",
    "--skip_upload_apk", "true",
    "--skip_upload_metadata", "true",
    "--skip_upload_changelogs", "true",
    "--skip_upload_images", "true",
    "--skip_upload_screenshots", "true",
    "--changes_not_sent_for_review", "false",
    "--rescue_changes_not_sent_for_review", "false",
    "--timeout", "3600",
    "--mapping_paths", "#{ARGV.fetch(3)},#{ARGV.fetch(4)}"
  ]
  abort("unexpected Google Play arguments: #{actual.inspect}") unless actual == expected
' "$fixture_root/google-args" "$service_account_json" "$aab_path" "$mapping_path" "$debug_symbols_path"
test "$(sed -n '1p' "$fixture_root/google-env")" = 1
test "$(sed -n '2p' "$fixture_root/google-env")" = 1

echo "Deferred Store upload worker and uploader tests passed"
