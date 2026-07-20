#!/usr/bin/env bash
set -euo pipefail

secret_root="${CI_SECRET_ROOT:-$HOME/ci-secrets/build-automation}"
token_file="${SLACK_BOT_TOKEN_FILE:-$secret_root/shared/slack-bot-token}"
channel_file="${SLACK_CHANNEL_ID_FILE:-$secret_root/shared/slack-channel-id}"
bot_token="${SLACK_BUILD_BOT_TOKEN:-}"
channel_id="${SLACK_BUILD_CHANNEL_ID:-}"
file_path="${SLACK_FILE_PATH:-${1:-}}"
api_base_url="${SLACK_API_BASE_URL:-https://slack.com/api}"
upload_phase_path="${SLACK_UPLOAD_PHASE_PATH:-}"
api_timeout_seconds="${SLACK_API_TIMEOUT_SECONDS:-60}"
file_upload_timeout_seconds="${SLACK_FILE_UPLOAD_TIMEOUT_SECONDS:-1800}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
receipt_manager="${SLACK_DELIVERY_RECEIPT_MANAGER:-$script_dir/manage-slack-apk-delivery-receipt.rb}"
receipt_started=false
receipt_armed=false

read_first_value() {
  local path="$1"
  if [ ! -r "$path" ]; then
    return 0
  fi

  sed -n \
    -e '/^[[:space:]]*#/d' \
    -e '/^[[:space:]]*$/d' \
    -e 's/^[[:space:]]*//' \
    -e 's/[[:space:]]*$//' \
    -e 'p' \
    -e 'q' \
    "$path"
}

write_upload_phase() {
  local phase="$1"
  if [ -z "$upload_phase_path" ]; then
    return 0
  fi
  if [ -L "$upload_phase_path" ]; then
    echo "::warning::Slack upload phase path must not be a symbolic link."
    return 2
  fi
  printf '%s\n' "$phase" > "$upload_phase_path"
  chmod 600 "$upload_phase_path"
}

write_slack_file_output() {
  local slack_file_id="$1"
  if [ -z "${GITHUB_OUTPUT:-}" ]; then
    return 0
  fi
  if ! printf 'slack_file_id=%s\n' "$slack_file_id" >> "$GITHUB_OUTPUT"; then
    echo "::warning::Slack delivery succeeded, but its advisory GitHub output could not be written."
  fi
}

handle_exit() {
  local status=$?
  trap - EXIT
  if [ "$status" -ne 0 ] && [ "$receipt_started" = true ] && [ "$receipt_armed" = false ]; then
    if ruby "$receipt_manager" discard >/dev/null; then
      echo "Discarded retry-safe Slack delivery state after a pre-completion failure."
    else
      echo "::warning::Retry-safe Slack delivery state could not be discarded; the next attempt will reconcile it."
    fi
  fi
  exit "$status"
}

trap handle_exit EXIT

if [ -z "$bot_token" ]; then
  bot_token="$(read_first_value "$token_file")"
fi
if [ -z "$channel_id" ]; then
  channel_id="$(read_first_value "$channel_file")"
fi

if ! [[ "$api_timeout_seconds" =~ ^[1-9][0-9]*$ ]] || ! [[ "$file_upload_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "::warning::Slack upload timeouts must be positive integers."
  exit 2
fi

if [ -z "$bot_token" ] || [ -z "$channel_id" ]; then
  echo "::warning::Slack Bot token or channel ID is not configured; direct APK delivery failed."
  exit 2
fi
if [[ ! "$channel_id" =~ ^[CGD][A-Z0-9]+$ ]]; then
  echo "::warning::Slack channel ID is invalid; direct APK delivery failed."
  exit 2
fi
if [ -z "$file_path" ] || [ ! -r "$file_path" ]; then
  echo "::warning::Development APK is not readable; direct APK delivery failed."
  exit 2
fi
if [ ! -r "$receipt_manager" ]; then
  echo "::warning::Slack delivery receipt manager is missing; refusing a non-idempotent APK upload."
  exit 2
fi

receipt_file_id=""
receipt_status=0
receipt_file_id="$(ruby "$receipt_manager" lookup)" || receipt_status=$?
case "$receipt_status" in
  0)
    if ! write_upload_phase receipt-delivered; then
      echo "::warning::Slack delivery is confirmed, but its advisory phase marker could not be written."
    fi
    write_slack_file_output "$receipt_file_id"
    echo "Development APK was already attached to Slack for this workflow run."
    exit 0
    ;;
  3)
    ruby "$receipt_manager" begin >/dev/null
    receipt_started=true
    ;;
  4)
    if ruby "$receipt_manager" discard >/dev/null; then
      ruby "$receipt_manager" begin >/dev/null
      receipt_started=true
    else
      write_upload_phase receipt-pending
      echo "::warning::A previous Slack completion attempt is unresolved; refusing a possible duplicate APK upload."
      exit 4
    fi
    ;;
  *)
    write_upload_phase receipt-invalid
    echo "::warning::Slack delivery receipt validation failed; refusing a non-idempotent APK upload."
    exit 2
    ;;
esac
write_upload_phase preflight-complete

echo "::add-mask::$bot_token"
file_name="$(basename "$file_path")"
file_length="$(wc -c < "$file_path" | tr -d '[:space:]')"
upload_response="$(
  curl --fail --silent --show-error \
    --connect-timeout 15 \
    --max-time "$api_timeout_seconds" \
    -X POST \
    -H "Authorization: Bearer $bot_token" \
    --data-urlencode "filename=$file_name" \
    --data-urlencode "length=$file_length" \
    "$api_base_url/files.getUploadURLExternal"
)" || {
  echo "::warning::Slack upload URL request failed; direct APK delivery failed."
  exit 2
}

upload_values="$(
  UPLOAD_RESPONSE="$upload_response" ruby -rjson -e '
    response = JSON.parse(ENV.fetch("UPLOAD_RESPONSE"))
    abort(response.fetch("error", "Slack upload URL request failed")) unless response["ok"]
    upload_url = response.fetch("upload_url")
    file_id = response.fetch("file_id")
    abort("Invalid Slack upload URL") unless upload_url.start_with?("https://") || upload_url.start_with?("http://127.0.0.1:") || upload_url.start_with?("http://localhost:")
    puts upload_url
    puts file_id
  ' 2>/dev/null
)" || {
  echo "::warning::Slack upload URL response was invalid; direct APK delivery failed."
  exit 2
}
upload_url="$(printf '%s\n' "$upload_values" | sed -n '1p')"
file_id="$(printf '%s\n' "$upload_values" | sed -n '2p')"
if [[ ! "$file_id" =~ ^F[A-Z0-9]+$ ]]; then
  echo "::warning::Slack upload URL response contained an invalid file ID."
  exit 2
fi
write_upload_phase upload-url-allocated
echo "::add-mask::$upload_url"

if ! curl --fail --silent --show-error \
  --connect-timeout 30 \
  --max-time "$file_upload_timeout_seconds" \
  -F "filename=@$file_path" \
  "$upload_url" >/dev/null; then
  echo "::warning::Slack file transfer failed; direct APK delivery failed."
  exit 2
fi
write_upload_phase file-transferred

initial_comment="$(
  BUILD_PROJECT_NAME="${BUILD_PROJECT_NAME:-UnknownProject}" \
  BUILD_PLATFORM="${BUILD_PLATFORM:-Android}" \
  BUILD_VERSION="${BUILD_VERSION:-}" \
  BUILD_BUNDLE_NO="${BUILD_BUNDLE_NO:-}" \
  BUILD_IOS_EFFECTIVE_BUNDLE_NO="${BUILD_IOS_EFFECTIVE_BUNDLE_NO:-}" \
  BUILD_SHORT_SHA="${BUILD_SHORT_SHA:-${GITHUB_SHA:-}}" \
  BUILD_RUN_URL="${BUILD_RUN_URL:-}" \
  SLACK_BUILD_MENTIONS="${SLACK_BUILD_MENTIONS:-}" \
  ruby <<'RUBY'
mentions = ENV.fetch("SLACK_BUILD_MENTIONS", "")
  .split(/[,\s]+/)
  .map(&:strip)
  .reject(&:empty?)
  .select { |value| value.match?(/\A[UW][A-Z0-9]+\z/) }
  .map { |value| "<@#{value}>" }
  .uniq
escape_mrkdwn = lambda do |value|
  value.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
end
version = escape_mrkdwn.call(ENV.fetch("BUILD_VERSION", ""))
bundle = escape_mrkdwn.call(ENV.fetch("BUILD_BUNDLE_NO", ""))
ios_bundle = ENV.fetch("BUILD_IOS_EFFECTIVE_BUNDLE_NO", "").strip
project = escape_mrkdwn.call(ENV.fetch("BUILD_PROJECT_NAME", "UnknownProject"))
platform = escape_mrkdwn.call(ENV.fetch("BUILD_PLATFORM", "Android"))
version_label = version.empty? ? "version unknown" : "v#{version.sub(/\A[vV]/, "")}"
version_label += "(#{bundle})" unless bundle.empty?
lines = ["[DEVELOPMENT BUILD] [OK] #{project} #{platform} BuildCommit SUCCESS - #{version_label}"]
lines.unshift(mentions.join(" ")) unless mentions.empty?
if ios_bundle.match?(/\A[1-9][0-9]*\z/)
  ios_version_label = version.empty? ? "build #{ios_bundle}" : "v#{version.sub(/\A[vV]/, "")}(#{ios_bundle})"
  lines << "iOS TestFlight: #{ios_version_label}"
end
sha = ENV.fetch("BUILD_SHORT_SHA", "")[0, 7]
lines << "Commit: #{sha}" unless sha.empty?
run_url = ENV.fetch("BUILD_RUN_URL", "")
lines << "Run: #{run_url}" unless run_url.empty?
puts lines.join("\n")
RUBY
)"

complete_payload="$(
  FILE_ID="$file_id" FILE_TITLE="$file_name" CHANNEL_ID="$channel_id" INITIAL_COMMENT="$initial_comment" \
  ruby -rjson -e '
    puts JSON.generate({
      files: [{ id: ENV.fetch("FILE_ID"), title: ENV.fetch("FILE_TITLE") }],
      channel_id: ENV.fetch("CHANNEL_ID"),
      initial_comment: ENV.fetch("INITIAL_COMMENT")
    })
  '
)"
receipt_armed=true
if ! ruby "$receipt_manager" arm "$file_id" >/dev/null; then
  write_upload_phase receipt-pending
  echo "::warning::Slack delivery receipt could not be armed; refusing an untracked completion request."
  exit 2
fi
write_upload_phase completion-attempted
complete_response="$(
  curl --fail --silent --show-error \
    --connect-timeout 15 \
    --max-time "$api_timeout_seconds" \
    -X POST \
    -H "Authorization: Bearer $bot_token" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$complete_payload" \
    "$api_base_url/files.completeUploadExternal"
)" || {
  write_upload_phase completion-ambiguous
  echo "::warning::Slack file completion failed; direct APK delivery failed."
  exit 2
}

if ! COMPLETE_RESPONSE="$complete_response" ruby -rjson -e 'response = JSON.parse(ENV.fetch("COMPLETE_RESPONSE")); exit(response["ok"] ? 0 : 1)' 2>/dev/null; then
  write_upload_phase completion-ambiguous
  echo "::warning::Slack rejected the file attachment; direct APK delivery failed."
  exit 2
fi
if ! ruby "$receipt_manager" complete "$file_id" >/dev/null; then
  write_upload_phase completion-ambiguous
  echo "::warning::Slack accepted the APK, but its durable delivery receipt could not be completed."
  exit 2
fi
receipt_started=false
if ! write_upload_phase completed; then
  echo "::warning::Slack delivery is confirmed, but its advisory phase marker could not be written."
fi

write_slack_file_output "$file_id"
echo "Development APK attached to Slack: $file_name"
