#!/usr/bin/env bash
set -euo pipefail

profile="${1:-${DISTRIBUTION_PROFILE:-Actionfit}}"
platform="${2:-${REQUEST_PLATFORM:-Both}}"
upload_target="${3:-${UPLOAD_TARGET:-None}}"
secret_root="${CI_SECRET_ROOT:-$HOME/ci-secrets/build-automation}"
export CI_SECRET_ROOT="$secret_root"
repository_root="${GITHUB_WORKSPACE:-}"
if [ -z "$repository_root" ]; then
  repository_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
fi
request_path="${BUILD_REQUEST_PATH:-$repository_root/.build/build_request.json}"
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
profile_android_env="$secret_root/profiles/$profile_slug/android-signing.env"
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

source_optional_env_file() {
  local path="$1"
  if [ ! -r "$path" ]; then
    return
  fi

  set -a
  # shellcheck disable=SC1090
  . "$path"
  set +a
}

mask_value() {
  local value="$1"
  if [ -n "$value" ] && [ "${GITHUB_ACTIONS:-}" = "true" ]; then
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

validate_base64_value() {
  local label="$1"
  local value="$2"
  ruby -rbase64 -e 'Base64.strict_decode64(ARGV.fetch(0))' "$value" >/dev/null || {
    echo "::error::$label is not valid base64"
    exit 1
  }
}

validate_p12_distribution_identity() {
  local label="$1"
  local path="$2"
  local password="$3"
  local team_id="$4"

  if ! command -v security >/dev/null 2>&1; then
    echo "::error::macOS security command is required to validate $label"
    exit 1
  fi

  (
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    keychain_path="$tmp_dir/p12-validation.keychain-db"
    keychain_password="actionfit-p12-validation"
    trap 'security delete-keychain "$keychain_path" >/dev/null 2>&1 || true; rm -rf "$tmp_dir"' EXIT

    security create-keychain -p "$keychain_password" "$keychain_path" >/dev/null
    security unlock-keychain -p "$keychain_password" "$keychain_path" >/dev/null

    if ! security import "$path" \
      -k "$keychain_path" \
      -P "$password" \
      -T /usr/bin/codesign \
      -T /usr/bin/security \
      -T /usr/bin/xcodebuild >/dev/null 2>&1; then
      echo "::error::$label could not be imported. Check IOS_DISTRIBUTION_CERTIFICATE_PASSWORD and the .p12 file."
      exit 1
    fi

    identity_line="$(security find-identity -v -p codesigning "$keychain_path" | grep -F "Apple Distribution:" | grep -F "($team_id)" | head -1 || true)"
    if [ -z "$identity_line" ]; then
      echo "::error::$label must contain an Apple Distribution identity with private key for team $team_id"
      echo "::error::Export the certificate and private key together from Keychain Access, then replace the .p12 in the local runner secret bundle."
      echo "Apple Distribution identities found in $label:"
      security find-identity -v -p codesigning "$keychain_path" | grep -F "Apple Distribution:" || true
      exit 1
    fi
  )
}

read_request_value() {
  local field="$1"
  if [ ! -r "$request_path" ]; then
    return
  fi

  ruby -rjson -e 'request = JSON.parse(File.read(ARGV.fetch(0))); value = request[ARGV.fetch(1)]; print(value.nil? ? "" : value.to_s.strip)' "$request_path" "$field" 2>/dev/null || true
}

source_env_file "profile env" "$profile_env"
request_ios_bundle_id="${IOS_BUNDLE_ID_FROM_REQUEST:-$(read_request_value "iosBundleId")}"

if [ "$uses_android" -eq 1 ]; then
  source_optional_env_file "$android_env"
  source_optional_env_file "$profile_android_env"
  request_keystore_base64="$(read_request_value "androidKeystoreBase64")"
  request_keystore_pass="$(read_request_value "androidKeystorePassword")"
  request_keyalias_pass="$(read_request_value "androidAliasPassword")"
  if [ -n "$request_keystore_base64" ]; then
    validate_base64_value "BuildCommit request androidKeystoreBase64" "$request_keystore_base64"
  else
    require_readable_file "ANDROID_KEYSTORE_PATH" "${ANDROID_KEYSTORE_PATH:-}"
  fi
  if [ -z "${ANDROID_KEYSTORE_PASS:-}" ] && [ -z "$request_keystore_pass" ]; then
    echo "::error::ANDROID_KEYSTORE_PASS is empty and BuildCommit request androidKeystorePassword is empty"
    exit 1
  fi
  if [ -z "${ANDROID_KEYALIAS_PASS:-}" ] && [ -z "$request_keyalias_pass" ]; then
    echo "::error::ANDROID_KEYALIAS_PASS is empty and BuildCommit request androidAliasPassword is empty"
    exit 1
  fi
  mask_value "${ANDROID_KEYSTORE_PASS:-}"
  mask_value "${ANDROID_KEYALIAS_PASS:-}"
  mask_value "$request_keystore_pass"
  mask_value "$request_keyalias_pass"
  if [ -z "$request_keystore_base64" ] && [ -n "${ANDROID_KEYSTORE_PATH:-}" ]; then
    append_github_env "ANDROID_KEYSTORE_PATH" "${ANDROID_KEYSTORE_PATH:-}"
    append_github_output "android_keystore_path" "${ANDROID_KEYSTORE_PATH:-}"
  else
    append_github_output "android_keystore_path" ""
  fi
  if [ -z "$request_keystore_pass" ] && [ -n "${ANDROID_KEYSTORE_PASS:-}" ]; then
    append_github_env "ANDROID_KEYSTORE_PASS" "${ANDROID_KEYSTORE_PASS:-}"
  fi
  if [ -z "$request_keyalias_pass" ] && [ -n "${ANDROID_KEYALIAS_PASS:-}" ]; then
    append_github_env "ANDROID_KEYALIAS_PASS" "${ANDROID_KEYALIAS_PASS:-}"
  fi
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
  require_readable_file "IOS_DISTRIBUTION_CERTIFICATE_P12_PATH" "${IOS_DISTRIBUTION_CERTIFICATE_P12_PATH:-}"
  require_nonempty "IOS_DISTRIBUTION_CERTIFICATE_PASSWORD" "${IOS_DISTRIBUTION_CERTIFICATE_PASSWORD:-}"
  require_nonempty "iosBundleId" "$request_ios_bundle_id"

  ios_profile_dir="${IOS_APP_STORE_PROVISIONING_PROFILE_DIR:-$secret_root/profiles/$profile_slug/ios/profiles}"
  ios_profile_auto_generate="${IOS_PROVISIONING_PROFILE_AUTO_GENERATE:-true}"
  if [ -z "${IOS_APP_STORE_PROVISIONING_PROFILE_PATH:-}" ]; then
    IOS_APP_STORE_PROVISIONING_PROFILE_PATH="$ios_profile_dir/$request_ios_bundle_id.mobileprovision"
  fi

  case "$ios_profile_auto_generate" in
    true|false) ;;
    *)
      echo "::error::IOS_PROVISIONING_PROFILE_AUTO_GENERATE must be true or false: $ios_profile_auto_generate"
      exit 1
      ;;
  esac

  if [ "$ios_profile_auto_generate" = "false" ]; then
    require_readable_file "IOS_APP_STORE_PROVISIONING_PROFILE_PATH" "${IOS_APP_STORE_PROVISIONING_PROFILE_PATH:-}"
  fi

  if ! grep -q "BEGIN PRIVATE KEY" "${APP_STORE_CONNECT_API_KEY_P8_PATH:-}"; then
    echo "::error::APP_STORE_CONNECT_API_KEY_P8_PATH does not look like an App Store Connect private key: ${APP_STORE_CONNECT_API_KEY_P8_PATH:-}"
    exit 1
  fi

  validate_p12_distribution_identity \
    "IOS_DISTRIBUTION_CERTIFICATE_P12_PATH" \
    "${IOS_DISTRIBUTION_CERTIFICATE_P12_PATH:-}" \
    "${IOS_DISTRIBUTION_CERTIFICATE_PASSWORD:-}" \
    "${IOS_DEVELOPMENT_TEAM_ID:-}"

  mask_value "${IOS_KEYCHAIN_PASSWORD:-}"
  mask_value "${IOS_DISTRIBUTION_CERTIFICATE_PASSWORD:-}"
  append_github_env "APP_STORE_CONNECT_API_KEY_ID" "${APP_STORE_CONNECT_API_KEY_ID:-}"
  append_github_env "APP_STORE_CONNECT_ISSUER_ID" "${APP_STORE_CONNECT_ISSUER_ID:-}"
  append_github_env "APP_STORE_CONNECT_API_KEY_P8_PATH" "${APP_STORE_CONNECT_API_KEY_P8_PATH:-}"
  append_github_env "IOS_DISTRIBUTION_CERTIFICATE_P12_PATH" "${IOS_DISTRIBUTION_CERTIFICATE_P12_PATH:-}"
  append_github_env "IOS_DISTRIBUTION_CERTIFICATE_PASSWORD" "${IOS_DISTRIBUTION_CERTIFICATE_PASSWORD:-}"
  append_github_env "IOS_APP_STORE_PROVISIONING_PROFILE_PATH" "${IOS_APP_STORE_PROVISIONING_PROFILE_PATH:-}"
  append_github_env "IOS_APP_STORE_PROVISIONING_PROFILE_DIR" "$ios_profile_dir"
  append_github_env "IOS_PROVISIONING_PROFILE_AUTO_GENERATE" "$ios_profile_auto_generate"
  if [ -n "${IOS_KEYCHAIN_PASSWORD:-}" ]; then
    append_github_env "IOS_KEYCHAIN_PASSWORD" "${IOS_KEYCHAIN_PASSWORD:-}"
  fi
  append_github_output "app_store_connect_api_key_p8_path" "${APP_STORE_CONNECT_API_KEY_P8_PATH:-}"
  append_github_output "ios_distribution_certificate_p12_path" "${IOS_DISTRIBUTION_CERTIFICATE_P12_PATH:-}"
  append_github_output "ios_app_store_provisioning_profile_path" "${IOS_APP_STORE_PROVISIONING_PROFILE_PATH:-}"
  append_github_output "ios_app_store_provisioning_profile_dir" "$ios_profile_dir"
fi

echo "Local runner secrets validated: root=$secret_root, profile=$profile_slug, platform=$platform, upload=$upload_target"
