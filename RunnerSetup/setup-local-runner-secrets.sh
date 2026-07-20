#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
secret_root="${1:-${CI_SECRET_ROOT:-$HOME/ci-secrets/build-automation}}"

mkdir -p \
  "$secret_root/shared" \
  "$secret_root/state/slack-apk-delivery" \
  "$secret_root/profiles/actionfit/android" \
  "$secret_root/profiles/actionfit/ios" \
  "$secret_root/profiles/actionfit/ios/profiles" \
  "$secret_root/profiles/stormborn/android" \
  "$secret_root/profiles/stormborn/ios" \
  "$secret_root/profiles/stormborn/ios/profiles"

write_if_missing() {
  local path="$1"
  shift
  if [ -f "$path" ]; then
    echo "exists: $path"
    return
  fi

  printf '%s\n' "$@" > "$path"
  echo "created: $path"
}

write_if_missing "$secret_root/shared/android-signing.env" \
  "# Shared Android signing passwords for this project." \
  "# Profile files can override these values when a company/account uses different passwords." \
  "ANDROID_KEYSTORE_PASS=\"\"" \
  "ANDROID_KEYALIAS_PASS=\"\""

write_if_missing "$secret_root/profiles/actionfit/android-signing.env" \
  "# Optional Android signing password override for Actionfit." \
  "# Leave these commented to use shared/android-signing.env." \
  "# ANDROID_KEYSTORE_PASS=\"\"" \
  "# ANDROID_KEYALIAS_PASS=\"\""

write_if_missing "$secret_root/profiles/stormborn/android-signing.env" \
  "# Optional Android signing password override for Stormborn." \
  "# Leave these commented to use shared/android-signing.env." \
  "# ANDROID_KEYSTORE_PASS=\"\"" \
  "# ANDROID_KEYALIAS_PASS=\"\""

write_if_missing "$secret_root/shared/ios-keychain.env" \
  "# Optional password for the temporary keychain created by the iOS workflow." \
  "# Leave IOS_KEYCHAIN_PASSWORD blank to let the workflow generate a per-run password." \
  "# Leave IOS_KEYCHAIN_PATH blank to let the workflow create a per-run temporary keychain." \
  "IOS_KEYCHAIN_PASSWORD=\"\"" \
  "IOS_KEYCHAIN_PATH=\"\""

write_if_missing "$secret_root/shared/github-package-read-token" \
  "# Optional GitHub read token for private UPM package repositories." \
  "# Prefer gh auth setup-git on the runner user. If that is unavailable, put one fine-grained token on the first non-comment line." \
  "# Required access: read-only Contents access to private ActionFit package repositories."

write_if_missing "$secret_root/shared/slack-webhook-url" \
  "# Legacy only: older Build Automation versions may use this Incoming Webhook URL." \
  "# Current versions use slack-bot-token and slack-channel-id for every Slack post."

write_if_missing "$secret_root/shared/slack-bot-token" \
  "# Slack Bot token for BuildCommit notifications and Development APK uploads." \
  "# Required scopes: chat:write and files:write. The bot must be a member of the target channel." \
  "# Put one xoxb-... token on the first non-comment line."

write_if_missing "$secret_root/shared/slack-channel-id" \
  "# Shared Slack destination channel ID for every BuildCommit notification and APK upload." \
  "# Put one C..., G..., or D... channel ID on the first non-comment line."

write_if_missing "$secret_root/profiles/actionfit/profile.env" \
  'ANDROID_KEYSTORE_PATH="${CI_SECRET_ROOT}/profiles/actionfit/android/upload.keystore"' \
  'GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="${CI_SECRET_ROOT}/profiles/actionfit/android/google-play-service-account.json"' \
  "IOS_DEVELOPMENT_TEAM_ID=\"49W7A8489P\"" \
  "APP_STORE_CONNECT_API_KEY_ID=\"\"" \
  "APP_STORE_CONNECT_ISSUER_ID=\"\"" \
  'APP_STORE_CONNECT_API_KEY_P8_PATH="${CI_SECRET_ROOT}/profiles/actionfit/ios/AuthKey_Actionfit.p8"' \
  'IOS_DISTRIBUTION_CERTIFICATE_P12_PATH="${CI_SECRET_ROOT}/profiles/actionfit/ios/AppleDistribution_Actionfit.p12"' \
  "IOS_DISTRIBUTION_CERTIFICATE_PASSWORD=\"\"" \
  'IOS_APP_STORE_PROVISIONING_PROFILE_DIR="${CI_SECRET_ROOT}/profiles/actionfit/ios/profiles"' \
  "IOS_PROVISIONING_PROFILE_AUTO_GENERATE=\"true\""

write_if_missing "$secret_root/profiles/stormborn/profile.env" \
  'ANDROID_KEYSTORE_PATH="${CI_SECRET_ROOT}/profiles/stormborn/android/upload.keystore"' \
  'GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="${CI_SECRET_ROOT}/profiles/stormborn/android/google-play-service-account.json"' \
  "IOS_DEVELOPMENT_TEAM_ID=\"\"" \
  "APP_STORE_CONNECT_API_KEY_ID=\"\"" \
  "APP_STORE_CONNECT_ISSUER_ID=\"\"" \
  'APP_STORE_CONNECT_API_KEY_P8_PATH="${CI_SECRET_ROOT}/profiles/stormborn/ios/AuthKey_Stormborn.p8"' \
  'IOS_DISTRIBUTION_CERTIFICATE_P12_PATH="${CI_SECRET_ROOT}/profiles/stormborn/ios/AppleDistribution_Stormborn.p12"' \
  "IOS_DISTRIBUTION_CERTIFICATE_PASSWORD=\"\"" \
  'IOS_APP_STORE_PROVISIONING_PROFILE_DIR="${CI_SECRET_ROOT}/profiles/stormborn/ios/profiles"' \
  "IOS_PROVISIONING_PROFILE_AUTO_GENERATE=\"true\""

find "$secret_root" -type d -exec chmod 700 {} \;
find "$secret_root" -type f -exec chmod 600 {} \;

cat <<EOF

Local runner secret folders are ready:
  $secret_root

Next:
  1. Copy keystore, Google Play JSON, App Store Connect .p8, and Apple Distribution .p12 files into the profile folders.
     App Store .mobileprovision files are selected by bundle id from ios/profiles/<bundle-id>.mobileprovision, or generated by fastlane sigh when IOS_PROVISIONING_PROFILE_AUTO_GENERATE=true.
  2. Fill these env files:
     - $secret_root/shared/android-signing.env
     - $secret_root/shared/ios-keychain.env
     - $secret_root/shared/github-package-read-token (optional, only when gh auth is unavailable)
     - $secret_root/shared/slack-webhook-url (legacy, for older package versions only)
     - $secret_root/shared/slack-bot-token (for all BuildCommit Slack posts)
     - $secret_root/shared/slack-channel-id (shared destination for all BuildCommit Slack posts)
     - $secret_root/profiles/actionfit/profile.env
     - $secret_root/profiles/actionfit/android-signing.env (optional override)
     - $secret_root/profiles/stormborn/profile.env
     - $secret_root/profiles/stormborn/android-signing.env (optional override)
  3. Validate:
     CI_SECRET_ROOT="$secret_root" bash "$script_dir/validate-local-runner-secrets.sh" Actionfit Both GooglePlayInternalAndTestFlight
EOF
