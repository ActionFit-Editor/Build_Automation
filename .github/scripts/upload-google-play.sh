#!/usr/bin/env bash
set -euo pipefail

service_account_json="${GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH:-}"
package_name="${ANDROID_PACKAGE_NAME:-}"
aab_path="${ANDROID_AAB_PATH:-}"
mapping_path="${ANDROID_MAPPING_PATH:-}"
debug_symbols_path="${ANDROID_DEBUG_SYMBOLS_PATH:-}"

test -r "$service_account_json" || {
  echo "::error::Google Play service account JSON is not readable: $service_account_json"
  exit 1
}
test -r "$aab_path" || {
  echo "::error::Android AAB is not readable: $aab_path"
  exit 1
}
if [ -z "$package_name" ]; then
  echo "::error::Android package name is required"
  exit 1
fi

if [ -n "${ACTIONFIT_FASTLANE_CMD:-}" ]; then
  fastlane_cmd="$ACTIONFIT_FASTLANE_CMD"
elif command -v fastlane >/dev/null 2>&1; then
  fastlane_cmd="$(command -v fastlane)"
elif [ -x /opt/homebrew/bin/fastlane ]; then
  fastlane_cmd=/opt/homebrew/bin/fastlane
elif [ -x /usr/local/bin/fastlane ]; then
  fastlane_cmd=/usr/local/bin/fastlane
else
  echo "::error::fastlane is required for deferred Google Play uploads"
  exit 1
fi

mapping_paths=()
for path in "$mapping_path" "$debug_symbols_path"; do
  if [ -z "$path" ]; then
    continue
  fi
  test -r "$path" || {
    echo "::error::Google Play deobfuscation file is not readable: $path"
    exit 1
  }
  case "$path" in
    *,*)
      echo "::error::Google Play deobfuscation paths must not contain commas: $path"
      exit 1
      ;;
  esac
  mapping_paths+=("$path")
done

supply_args=(
  supply
  --json_key "$service_account_json"
  --package_name "$package_name"
  --aab "$aab_path"
  --track internal
  --release_status completed
  --skip_upload_apk true
  --skip_upload_metadata true
  --skip_upload_changelogs true
  --skip_upload_images true
  --skip_upload_screenshots true
  --changes_not_sent_for_review false
  --rescue_changes_not_sent_for_review false
  --timeout 3600
)

if [ "${#mapping_paths[@]}" -eq 1 ]; then
  supply_args+=(--mapping "${mapping_paths[0]}")
elif [ "${#mapping_paths[@]}" -gt 1 ]; then
  mapping_csv="$(IFS=,; echo "${mapping_paths[*]}")"
  supply_args+=(--mapping_paths "$mapping_csv")
fi

export FASTLANE_DISABLE_COLORS=1
export FASTLANE_SKIP_UPDATE_CHECK=1
exec "$fastlane_cmd" "${supply_args[@]}"
