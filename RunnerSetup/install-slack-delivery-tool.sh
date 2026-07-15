#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
package_root="$(cd "$script_dir/.." && pwd -P)"
install_root="${SLACK_DELIVERY_ROOT:-/Users/lydia/workspace/slack-delivery}"
bin_dir="$install_root/bin"
secret_dir="$install_root/secrets/shared"

umask 077
mkdir -p "$bin_dir" "$secret_dir"
chmod 700 "$install_root" "$bin_dir" "$install_root/secrets" "$secret_dir"

install_executable() {
  local source_path="$1"
  local destination_path="$2"
  if [ ! -f "$source_path" ]; then
    echo "Required Slack delivery source is missing: $source_path" >&2
    exit 1
  fi
  /usr/bin/install -m 700 "$source_path" "$destination_path"
  echo "installed: $destination_path"
}

create_secret_placeholder() {
  local path="$1"
  shift
  if [ ! -e "$path" ]; then
    printf '%s\n' "$@" > "$path"
    echo "created: $path"
  else
    echo "exists: $path"
  fi
  chmod 600 "$path"
}

install_executable "$script_dir/deliver-buildcommit-slack" "$bin_dir/deliver-buildcommit-slack"
install_executable "$package_root/.github/scripts/notify-slack-build-result.sh" "$bin_dir/notify-slack-build-result.sh"
install_executable "$package_root/.github/scripts/upload-slack-file.sh" "$bin_dir/upload-slack-file.sh"

create_secret_placeholder "$secret_dir/slack-webhook-url" \
  "# Slack Incoming Webhook URL for BuildCommit start/result notifications." \
  "# Put one https://hooks.slack.com/services/... URL on the first non-comment line."

create_secret_placeholder "$secret_dir/slack-bot-token" \
  "# Slack Bot token for Development APK attachments." \
  "# Required scope: files:write. Put one xoxb-... token on the first non-comment line."

create_secret_placeholder "$secret_dir/slack-channel-id" \
  "# Shared Slack destination for BuildCommit notifications and APK attachments." \
  "# Put one C..., G..., or D... channel ID on the first non-comment line."

find "$install_root/secrets" -type d -exec chmod 700 {} \;
find "$install_root/secrets" -type f -exec chmod 600 {} \;

cat <<EOF

Slack delivery runner files are ready:
  tools:   $bin_dir
  secrets: $secret_dir

Fill the first non-comment line of each secret file, then run a trusted Slack delivery workflow on this runner.
EOF
