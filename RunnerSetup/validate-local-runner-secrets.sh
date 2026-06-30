#!/usr/bin/env bash
set -euo pipefail

profile="${1:-${DISTRIBUTION_PROFILE:-Actionfit}}"
platform="${2:-${REQUEST_PLATFORM:-Both}}"
upload_target="${3:-${UPLOAD_TARGET:-None}}"
secret_root="${CI_SECRET_ROOT:-$HOME/ci-secrets/cat-merge-cafe}"

profile_slug="$(printf '%s' "$profile" | tr '[:upper:]' '[:lower:]')"
case "$profile_slug" in
  actionfit|stormborn) ;;
  *)
    echo "::error::Unsupported distribution profile: $profile"
    exit 1
    ;;
esac

uses_android=0
uses_ios=0
uses_google_play=0
uses_testflight=0

case "$platform" in
  Android|1) uses_android=1 ;;
  iOS|Ios|2) uses_ios=1 ;;
  Both|3) uses_android=1; uses_ios=1 ;;
  *)
    echo "::error::Unsupported platform: $platform"
    exit 1
    ;;
esac

case "$upload_target" in
  GooglePlayInternal|1) uses_google_play=1 ;;
  TestFlight|2) uses_testflight=1 ;;
  GooglePlayInternalAndTestFlight|3) uses_google_play=1; uses_testflight=1 ;;
  None|0|"") ;;
  *)
    echo "::error::Unsupported upload target: $upload_target"
    exit 1
    ;;
esac

profile_env="$secret_root/profiles/$profile_slug/profile.env"
android_env="$secret_root/shared/android-signing.env"
ios_keychain_env="$secret_root/shared/ios-keychain.env"

require_readable_file() {
  local label="$1"
  local path="$2"
  if [ -z "$path" ]; then
    echo "::error::$label is empty"
    exit 1
  fi
  if [ ! -r "$path" ]; then
    echo "::error::$label is not readable: $path"
    exit 1
  fi
}

require_nonempty() {
  local label="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "::error::$label is empty"
    exit 1
  fi
}

source_env_file() {
  local label="$1"
  local path="$2"
  require_readable_file "$label" "$path"
  set -a
  # shellcheck disable=SC1090
  . "$path"
  set +a
}

mask_value() {
  local value="$1"
  if [ -n "$value" ]; then
    echo "::add-mask::$value"
  fi
}

append_github_env() {
  local name="$1"
  local value="$2"
  if [ -n "${GITHUB_ENV:-}" ]; then
    {
      printf '%s<<__ACTIONFIT_EOF__\n' "$name"
      printf '%s\n' "$value"
      printf '__ACTIONFIT_EOF__\n'
    } >> "$GITHUB_ENV"
  fi
}

append_github_output() {
  local name="$1"
  local value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      printf '%s<<__ACTIONFIT_EOF__\n' "$name"
      printf '%s\n' "$value"
      printf '__ACTIONFIT_EOF__\n'
    } >> "$GITHUB_OUTPUT"
  fi
}

validate_json_file() {
  local label="$1"
  local path="$2"
  ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$path" >/dev/null || {
    echo "::error::$label is not valid JSON: $path"
    exit 1
  }
}

source_env_file "profile env" "$profile_env"

if [ "$uses_android" -eq 1 ]; then
  source_env_file "shared Android signing env" "$android_env"
  require_readable_file "ANDROID_KEYSTORE_PATH" "${ANDROID_KEYSTORE_PATH:-}"
  require_nonempty "ANDROID_KEYSTORE_PASS" "${ANDROID_KEYSTORE_PASS:-}"
  require_nonempty "ANDROID_KEYALIAS_PASS" "${ANDROID_KEYALIAS_PASS:-}"
  mask_value "${ANDROID_KEYSTORE_PASS:-}"
  mask_value "${ANDROID_KEYALIAS_PASS:-}"
  append_github_env "ANDROID_KEYSTORE_PATH" "${ANDROID_KEYSTORE_PATH:-}"
  append_github_env "ANDROID_KEYSTORE_PASS" "${ANDROID_KEYSTORE_PASS:-}"
  append_github_env "ANDROID_KEYALIAS_PASS" "${ANDROID_KEYALIAS_PASS:-}"
  append_github_output "android_keystore_path" "${ANDROID_KEYSTORE_PATH:-}"
fi

if [ "$uses_google_play" -eq 1 ]; then
  require_readable_file "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" "${GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH:-}"
  validate_json_file "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" "${GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH:-}"
  append_github_env "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH" "${GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH:-}"
  append_github_output "google_play_service_account_json_path" "${GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH:-}"
fi

if [ "$uses_ios" -eq 1 ]; then
  if [ -r "$ios_keychain_env" ]; then
    source_env_file "shared iOS keychain env" "$ios_keychain_env"
  fi

  require_nonempty "IOS_DEVELOPMENT_TEAM_ID" "${IOS_DEVELOPMENT_TEAM_ID:-}"
  append_github_env "IOS_DEVELOPMENT_TEAM_ID" "${IOS_DEVELOPMENT_TEAM_ID:-}"
  append_github_output "ios_development_team_id" "${IOS_DEVELOPMENT_TEAM_ID:-}"

  if [ -n "${IOS_KEYCHAIN_PATH:-}" ]; then
    append_github_env "IOS_KEYCHAIN_PATH" "${IOS_KEYCHAIN_PATH:-}"
  fi
fi

if [ "$uses_testflight" -eq 1 ]; then
  require_nonempty "APP_STORE_CONNECT_API_KEY_ID" "${APP_STORE_CONNECT_API_KEY_ID:-}"
  require_nonempty "APP_STORE_CONNECT_ISSUER_ID" "${APP_STORE_CONNECT_ISSUER_ID:-}"
  require_readable_file "APP_STORE_CONNECT_API_KEY_P8_PATH" "${APP_STORE_CONNECT_API_KEY_P8_PATH:-}"
  require_nonempty "IOS_KEYCHAIN_PASSWORD" "${IOS_KEYCHAIN_PASSWORD:-}"

  if ! grep -q "BEGIN PRIVATE KEY" "${APP_STORE_CONNECT_API_KEY_P8_PATH:-}"; then
    echo "::error::APP_STORE_CONNECT_API_KEY_P8_PATH does not look like an App Store Connect private key: ${APP_STORE_CONNECT_API_KEY_P8_PATH:-}"
    exit 1
  fi

  mask_value "${IOS_KEYCHAIN_PASSWORD:-}"
  append_github_env "APP_STORE_CONNECT_API_KEY_ID" "${APP_STORE_CONNECT_API_KEY_ID:-}"
  append_github_env "APP_STORE_CONNECT_ISSUER_ID" "${APP_STORE_CONNECT_ISSUER_ID:-}"
  append_github_env "APP_STORE_CONNECT_API_KEY_P8_PATH" "${APP_STORE_CONNECT_API_KEY_P8_PATH:-}"
  append_github_env "IOS_KEYCHAIN_PASSWORD" "${IOS_KEYCHAIN_PASSWORD:-}"
  append_github_output "app_store_connect_api_key_p8_path" "${APP_STORE_CONNECT_API_KEY_P8_PATH:-}"
fi

echo "Local runner secrets validated: root=$secret_root, profile=$profile_slug, platform=$platform, upload=$upload_target"
