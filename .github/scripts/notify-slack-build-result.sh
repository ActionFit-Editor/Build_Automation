#!/usr/bin/env bash
set -euo pipefail

secret_root="${CI_SECRET_ROOT:-$HOME/workspace/build-automation}"
webhook_file="${SLACK_WEBHOOK_URL_FILE:-$secret_root/shared/slack-webhook-url}"
webhook_url="${SLACK_BUILD_WEBHOOK_URL:-${SLACK_WEBHOOK_URL:-}}"
mentions="${SLACK_BUILD_MENTIONS:-${SLACK_MENTIONS:-}}"

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
platform="${BUILD_PLATFORM:-Build}"
repository="${GITHUB_REPOSITORY:-}"
project_name="${BUILD_PROJECT_NAME:-${repository##*/}}"
if [ -z "$project_name" ]; then
  project_name="UnknownProject"
fi
version="${BUILD_VERSION:-}"
bundle_no="${BUILD_BUNDLE_NO:-}"
distribution_profile="${BUILD_DISTRIBUTION_PROFILE:-}"
run_url="${BUILD_RUN_URL:-${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}}"
short_sha="${BUILD_SHORT_SHA:-${GITHUB_SHA:-}}"

if [ -n "$short_sha" ]; then
  short_sha="${short_sha:0:7}"
fi

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

case "$status" in
  success)
    status_label="SUCCESS"
    status_symbol="OK"
    ;;
  failure)
    status_label="FAILED"
    status_symbol="FAIL"
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

payload="$(
  PROJECT_NAME="$project_name" \
  PLATFORM="$platform" \
  STATUS_LABEL="$status_label" \
  STATUS_SYMBOL="$status_symbol" \
  VERSION_LABEL="$version_label" \
  DISTRIBUTION_PROFILE="$distribution_profile" \
  SHORT_SHA="$short_sha" \
  RUN_URL="$run_url" \
  SLACK_MENTIONS="$mentions" \
  ruby -rjson <<'RUBY'
project_name = ENV.fetch("PROJECT_NAME", "")
platform = ENV.fetch("PLATFORM", "")
status_label = ENV.fetch("STATUS_LABEL", "")
status_symbol = ENV.fetch("STATUS_SYMBOL", "")
version_label = ENV.fetch("VERSION_LABEL", "")
distribution_profile = ENV.fetch("DISTRIBUTION_PROFILE", "")
short_sha = ENV.fetch("SHORT_SHA", "")
run_url = ENV.fetch("RUN_URL", "")
raw_mentions = ENV.fetch("SLACK_MENTIONS", "")

mentions = raw_mentions
  .split(/[,\s]+/)
  .map(&:strip)
  .reject(&:empty?)
  .map do |token|
    if token.match?(/\A<(@|!)[^>]+>\z/)
      token
    elsif token.match?(/\A[UW][A-Z0-9]+\z/)
      "<@#{token}>"
    else
      token
    end
  end
  .uniq
  .join(" ")

lines = [
  "[#{status_symbol}] #{project_name} #{platform} BuildCommit #{status_label} - #{version_label}"
]

lines.unshift(mentions) unless mentions.empty?
lines << "Profile: #{distribution_profile}" unless distribution_profile.empty?
lines << "Commit: #{short_sha}" unless short_sha.empty?
lines << "Run: #{run_url}" unless run_url.empty?

puts JSON.generate({ text: lines.join("\n") })
RUBY
)"

if ! curl --fail --silent --show-error \
  -X POST \
  -H "Content-type: application/json" \
  --data "$payload" \
  "$webhook_url" >/dev/null; then
  echo "::warning::Slack build notification failed."
  exit 0
fi

echo "Slack build notification sent: $project_name $platform $status_label $version_label"
