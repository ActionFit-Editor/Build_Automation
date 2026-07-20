#!/usr/bin/env bash
set -euo pipefail

secret_root="${CI_SECRET_ROOT:-$HOME/ci-secrets/build-automation}"
webhook_file="${SLACK_WEBHOOK_URL_FILE:-$secret_root/shared/slack-webhook-url}"
webhook_url="${SLACK_BUILD_WEBHOOK_URL:-${SLACK_WEBHOOK_URL:-}}"
mentions="${SLACK_BUILD_MENTIONS:-${SLACK_MENTIONS:-}}"
api_timeout_seconds="${SLACK_API_TIMEOUT_SECONDS:-60}"

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

if [ -z "$webhook_url" ]; then
  webhook_url="$(read_first_value "$webhook_file")"
fi

if ! [[ "$api_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "::warning::Slack notification timeout must be a positive integer; skipping build notification."
  exit 0
fi

if [ -z "$webhook_url" ]; then
  echo "Slack webhook URL is not configured; skipping build notification."
  exit 0
fi

if [[ "$webhook_url" != https://hooks.slack.com/services/* ]]; then
  echo "::warning::Slack webhook URL is not a Slack Incoming Webhook URL; skipping build notification."
  exit 0
fi

echo "::add-mask::$webhook_url"

status="${BUILD_JOB_STATUS:-${1:-unknown}}"
status_normalized="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
platform="${BUILD_PLATFORM:-Build}"
repository="${GITHUB_REPOSITORY:-}"
project_name="${BUILD_PROJECT_NAME:-${repository##*/}}"
if [ -z "$project_name" ]; then
  project_name="UnknownProject"
fi
version="${BUILD_VERSION:-}"
bundle_no="${BUILD_BUNDLE_NO:-}"
ios_effective_bundle_no="${BUILD_IOS_EFFECTIVE_BUNDLE_NO:-}"
distribution_profile="${BUILD_DISTRIBUTION_PROFILE:-}"
development_build="$(printf '%s' "${BUILD_DEVELOPMENT_BUILD:-false}" | tr '[:upper:]' '[:lower:]')"
run_url="${BUILD_RUN_URL:-${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}}"
short_sha="${BUILD_SHORT_SHA:-${GITHUB_SHA:-}}"
started_at_epoch="${BUILD_STARTED_AT_EPOCH:-}"
completed_at_epoch="${BUILD_COMPLETED_AT_EPOCH:-}"

if [ -n "$short_sha" ]; then
  short_sha="${short_sha:0:7}"
fi

if [ -z "$completed_at_epoch" ]; then
  completed_at_epoch="$(date +%s)"
fi

format_duration() {
  local total_seconds="$1"
  if ! [[ "$total_seconds" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  if [ "$hours" -gt 0 ]; then
    printf '%dh %02dm %02ds\n' "$hours" "$minutes" "$seconds"
  elif [ "$minutes" -gt 0 ]; then
    printf '%dm %02ds\n' "$minutes" "$seconds"
  else
    printf '%ds\n' "$seconds"
  fi
}

version_label=""
version_prefix="v"
case "$version" in
  v*|V*)
    version_prefix=""
    ;;
esac

if [ -n "$version" ] && [ -n "$bundle_no" ]; then
  version_label="${version_prefix}${version}(${bundle_no})"
elif [ -n "$version" ]; then
  version_label="${version_prefix}${version}"
elif [ -n "$bundle_no" ]; then
  version_label="bundle ${bundle_no}"
else
  version_label="version unknown"
fi

case "$status_normalized" in
  start|started)
    status_label="STARTED"
    status_symbol="Start"
    ;;
  success)
    status_label="SUCCESS"
    status_symbol="OK"
    ;;
  failure)
    status_label="FAILED"
    status_symbol="FAIL"
    ;;
  apk_delivery_failure)
    status_label="BUILD SUCCESS / APK DELIVERY FAILED"
    status_symbol="WARNING"
    ;;
  cancelled)
    status_label="CANCELLED"
    status_symbol="CANCELLED"
    ;;
  *)
    status_label="$(printf '%s' "$status" | tr '[:lower:]' '[:upper:]')"
    status_symbol="INFO"
    ;;
esac

duration_label=""
if [ "$status_symbol" != "Start" ] \
  && [[ "$started_at_epoch" =~ ^[0-9]+$ ]] \
  && [[ "$completed_at_epoch" =~ ^[0-9]+$ ]] \
  && [ "$completed_at_epoch" -ge "$started_at_epoch" ]; then
  duration_label="$(format_duration "$((completed_at_epoch - started_at_epoch))")"
fi

payload="$(
  PROJECT_NAME="$project_name" \
  PLATFORM="$platform" \
  STATUS_LABEL="$status_label" \
  STATUS_SYMBOL="$status_symbol" \
  STATUS_NORMALIZED="$status_normalized" \
  VERSION_LABEL="$version_label" \
  BUILD_VERSION="$version" \
  IOS_EFFECTIVE_BUNDLE_NO="$ios_effective_bundle_no" \
  DURATION_LABEL="$duration_label" \
  DISTRIBUTION_PROFILE="$distribution_profile" \
  DEVELOPMENT_BUILD="$development_build" \
  SHORT_SHA="$short_sha" \
  RUN_URL="$run_url" \
  SLACK_MENTIONS="$mentions" \
  ruby -rjson <<'RUBY'
project_name = ENV.fetch("PROJECT_NAME", "")
platform = ENV.fetch("PLATFORM", "")
status_label = ENV.fetch("STATUS_LABEL", "")
status_symbol = ENV.fetch("STATUS_SYMBOL", "")
status_normalized = ENV.fetch("STATUS_NORMALIZED", "")
version_label = ENV.fetch("VERSION_LABEL", "")
build_version = ENV.fetch("BUILD_VERSION", "").strip
ios_effective_bundle_no = ENV.fetch("IOS_EFFECTIVE_BUNDLE_NO", "").strip
duration_label = ENV.fetch("DURATION_LABEL", "")
distribution_profile = ENV.fetch("DISTRIBUTION_PROFILE", "")
development_build = ENV.fetch("DEVELOPMENT_BUILD", "false") == "true"
short_sha = ENV.fetch("SHORT_SHA", "")
run_url = ENV.fetch("RUN_URL", "")
raw_mentions = ENV.fetch("SLACK_MENTIONS", "")
escape_mrkdwn = lambda do |value|
  value.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
end

version_label = escape_mrkdwn.call(version_label)

mentions = raw_mentions
  .split(/[,\s]+/)
  .map(&:strip)
  .reject(&:empty?)
  .select { |token| token.match?(/\A[UW][A-Z0-9]+\z/) }
  .map { |token| "<@#{token}>" }
  .uniq
  .join(" ")

development_label = development_build ? "[DEVELOPMENT BUILD] " : ""
lines = ["#{development_label}[#{status_symbol}] #{project_name} #{platform} BuildCommit #{status_label} - #{version_label}"]

lines.unshift(mentions) unless mentions.empty?
if development_build && %w[success apk_delivery_failure].include?(status_normalized) && ios_effective_bundle_no.match?(/\A[1-9][0-9]*\z/)
  escaped_build_version = escape_mrkdwn.call(build_version)
  ios_version_label = escaped_build_version.empty? ? "build #{ios_effective_bundle_no}" : "v#{escaped_build_version.sub(/\A[vV]/, "")}(#{ios_effective_bundle_no})"
  lines << "iOS TestFlight: #{ios_version_label}"
end
lines << "Time: #{duration_label}" unless duration_label.empty?
lines << "Profile: #{distribution_profile}" unless distribution_profile.empty?
lines << "Commit: #{short_sha}" unless short_sha.empty?
lines << "Run: #{run_url}" unless run_url.empty?

puts JSON.generate({ text: lines.join("\n") })
RUBY
)"

if ! curl --fail --silent --show-error \
  --connect-timeout 15 \
  --max-time "$api_timeout_seconds" \
  -X POST \
  -H "Content-type: application/json" \
  --data "$payload" \
  "$webhook_url" >/dev/null; then
  echo "::warning::Slack build notification failed."
  exit 0
fi

if [ -n "$duration_label" ]; then
  echo "Slack build notification sent: $project_name $platform $status_label $version_label, $duration_label"
else
  echo "Slack build notification sent: $project_name $platform $status_label $version_label"
fi
