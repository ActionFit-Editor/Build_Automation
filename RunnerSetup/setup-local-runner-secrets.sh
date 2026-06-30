#!/usr/bin/env bash
set -euo pipefail

secret_root="${1:-${CI_SECRET_ROOT:-$HOME/ci-secrets/cat-merge-cafe}}"

mkdir -p \
  "$secret_root/shared" \
  "$secret_root/profiles/actionfit/android" \
  "$secret_root/profiles/actionfit/ios" \
  "$secret_root/profiles/stormborn/android" \
  "$secret_root/profiles/stormborn/ios"

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
  "# Shared Android signing passwords." \
  "# This repo currently uses the same keystore password and alias password across profiles." \
  "ANDROID_KEYSTORE_PASS=\"\"" \
  "ANDROID_KEYALIAS_PASS=\"\""

write_if_missing "$secret_root/shared/ios-keychain.env" \
  "# Password for the keychain used by the GitHub Actions runner service." \
  "# Leave IOS_KEYCHAIN_PATH blank to use \$HOME/Library/Keychains/login.keychain-db." \
  "IOS_KEYCHAIN_PASSWORD=\"\"" \
  "IOS_KEYCHAIN_PATH=\"\""

write_if_missing "$secret_root/profiles/actionfit/profile.env" \
  "ANDROID_KEYSTORE_PATH=\"$secret_root/profiles/actionfit/android/upload.keystore\"" \
  "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH=\"$secret_root/profiles/actionfit/android/google-play-service-account.json\"" \
  "IOS_DEVELOPMENT_TEAM_ID=\"49W7A8489P\"" \
  "APP_STORE_CONNECT_API_KEY_ID=\"\"" \
  "APP_STORE_CONNECT_ISSUER_ID=\"\"" \
  "APP_STORE_CONNECT_API_KEY_P8_PATH=\"$secret_root/profiles/actionfit/ios/AuthKey_Actionfit.p8\""

write_if_missing "$secret_root/profiles/stormborn/profile.env" \
  "ANDROID_KEYSTORE_PATH=\"$secret_root/profiles/stormborn/android/upload.keystore\"" \
  "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH=\"$secret_root/profiles/stormborn/android/google-play-service-account.json\"" \
  "IOS_DEVELOPMENT_TEAM_ID=\"\"" \
  "APP_STORE_CONNECT_API_KEY_ID=\"\"" \
  "APP_STORE_CONNECT_ISSUER_ID=\"\"" \
  "APP_STORE_CONNECT_API_KEY_P8_PATH=\"$secret_root/profiles/stormborn/ios/AuthKey_Stormborn.p8\""

find "$secret_root" -type d -exec chmod 700 {} \;
find "$secret_root" -type f -name "*.env" -exec chmod 600 {} \;

cat <<EOF

Local runner secret folders are ready:
  $secret_root

Next:
  1. Copy keystore, Google Play JSON, and App Store Connect .p8 files into the profile folders.
  2. Fill these env files:
     - $secret_root/shared/android-signing.env
     - $secret_root/shared/ios-keychain.env
     - $secret_root/profiles/actionfit/profile.env
     - $secret_root/profiles/stormborn/profile.env
  3. Validate:
     CI_SECRET_ROOT="$secret_root" bash Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh Actionfit Both GooglePlayInternalAndTestFlight
EOF
