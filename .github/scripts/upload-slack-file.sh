#!/usr/bin/env bash
set -euo pipefail

secret_root="${CI_SECRET_ROOT:-$HOME/ci-secrets/build-automation}"
token_file="${SLACK_BOT_TOKEN_FILE:-$secret_root/shared/slack-bot-token}"
channel_file="${SLACK_CHANNEL_ID_FILE:-$secret_root/shared/slack-channel-id}"
bot_token="${SLACK_BUILD_BOT_TOKEN:-}"
channel_id="${SLACK_BUILD_CHANNEL_ID:-}"
file_path="${SLACK_FILE_PATH:-${1:-}}"
api_base_url="${SLACK_API_BASE_URL:-https://slack.com/api}"

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

if [ -z "$bot_token" ]; then
  bot_token="$(read_first_value "$token_file")"
fi
if [ -z "$channel_id" ]; then
  channel_id="$(read_first_value "$channel_file")"
fi

if [ -z "$bot_token" ] || [ -z "$channel_id" ]; then
  echo "::warning::Slack Bot token or channel ID is not configured; use the GitHub Artifact fallback."
  exit 2
fi
if [[ ! "$channel_id" =~ ^[CGD][A-Z0-9]+$ ]]; then
  echo "::warning::Slack channel ID is invalid; use the GitHub Artifact fallback."
  exit 2
fi
if [ -z "$file_path" ] || [ ! -r "$file_path" ]; then
  echo "::warning::Development APK is not readable; use the GitHub Artifact fallback."
  exit 2
fi

echo "::add-mask::$bot_token"
file_name="$(basename "$file_path")"
file_length="$(wc -c < "$file_path" | tr -d '[:space:]')"
upload_response="$(
  curl --fail --silent --show-error \
    -X POST \
    -H "Authorization: Bearer $bot_token" \
    --data-urlencode "filename=$file_name" \
    --data-urlencode "length=$file_length" \
    "$api_base_url/files.getUploadURLExternal"
)" || {
  echo "::warning::Slack upload URL request failed; use the GitHub Artifact fallback."
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
  echo "::warning::Slack upload URL response was invalid; use the GitHub Artifact fallback."
  exit 2
}
upload_url="$(printf '%s\n' "$upload_values" | sed -n '1p')"
file_id="$(printf '%s\n' "$upload_values" | sed -n '2p')"
echo "::add-mask::$upload_url"

if ! curl --fail --silent --show-error \
  -F "filename=@$file_path" \
  "$upload_url" >/dev/null; then
  echo "::warning::Slack file transfer failed; use the GitHub Artifact fallback."
  exit 2
fi

initial_comment="$(
  BUILD_PROJECT_NAME="${BUILD_PROJECT_NAME:-UnknownProject}" \
  BUILD_VERSION="${BUILD_VERSION:-}" \
  BUILD_BUNDLE_NO="${BUILD_BUNDLE_NO:-}" \
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
version_label = version.empty? ? "version unknown" : "v#{version.sub(/\A[vV]/, "")}"
version_label += "(#{bundle})" unless bundle.empty?
lines = ["[DEVELOPMENT BUILD] [OK] #{ENV.fetch("BUILD_PROJECT_NAME")} Android BuildCommit SUCCESS - #{version_label}"]
lines.unshift(mentions.join(" ")) unless mentions.empty?
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
complete_response="$(
  curl --fail --silent --show-error \
    -X POST \
    -H "Authorization: Bearer $bot_token" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$complete_payload" \
    "$api_base_url/files.completeUploadExternal"
)" || {
  echo "::warning::Slack file completion failed; use the GitHub Artifact fallback."
  exit 2
}

if ! COMPLETE_RESPONSE="$complete_response" ruby -rjson -e 'response = JSON.parse(ENV.fetch("COMPLETE_RESPONSE")); exit(response["ok"] ? 0 : 1)' 2>/dev/null; then
  echo "::warning::Slack rejected the file attachment; use the GitHub Artifact fallback."
  exit 2
fi

echo "Development APK attached to Slack: $file_name"
