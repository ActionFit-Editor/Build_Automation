#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "::error::Mobile build baseline check failed: $1" >&2
  exit 1
}

require_readable_file() {
  local path="$1"
  local label="$2"
  [ -f "$path" ] && [ -r "$path" ] || fail "$label is not readable"
}

read_unity_setting() {
  local settings_path="$1"
  local setting_name="$2"
  sed -n "s/^[[:space:]]*${setting_name}:[[:space:]]*//p" "$settings_path" | tr -d '\r'
}

require_unity_setting() {
  local settings_path="$1"
  local setting_name="$2"
  local expected_value="$3"
  local actual_value
  actual_value="$(read_unity_setting "$settings_path" "$setting_name")"
  [ "$actual_value" = "$expected_value" ] ||
    fail "$setting_name must be $expected_value (found ${actual_value:-missing})"
}

verify_android_settings() {
  local unity_project_dir="$1"
  local project_settings="$unity_project_dir/ProjectSettings/ProjectSettings.asset"
  local base_project_template="$unity_project_dir/Assets/Plugins/Android/baseProjectTemplate.gradle"
  local gradle_properties="$unity_project_dir/Assets/Plugins/Android/gradleTemplate.properties"
  local android_manifest="$unity_project_dir/Assets/Plugins/Android/AndroidManifest.xml"

  require_readable_file "$project_settings" "ProjectSettings.asset"
  require_readable_file "$base_project_template" "active Android base project template"
  require_readable_file "$gradle_properties" "active Android Gradle properties template"
  require_readable_file "$android_manifest" "active Android manifest"

  require_unity_setting "$project_settings" "AndroidTargetSdkVersion" "36"
  require_unity_setting "$project_settings" "androidPredictiveBackSupport" "1"
  require_unity_setting "$project_settings" "AndroidMinSdkVersion" "28"

  grep -Eq "^[[:space:]]*id ['\"]com\\.android\\.application['\"] version ['\"]8\\.10\\.0['\"] apply false[[:space:]]*$" "$base_project_template" ||
    fail "Android application plugin must use AGP 8.10.0"
  grep -Eq "^[[:space:]]*id ['\"]com\\.android\\.library['\"] version ['\"]8\\.10\\.0['\"] apply false[[:space:]]*$" "$base_project_template" ||
    fail "Android library plugin must use AGP 8.10.0"

  if grep -Eq '^[[:space:]]*android\.suppressUnsupportedCompileSdk[[:space:]]*=' "$gradle_properties"; then
    fail "android.suppressUnsupportedCompileSdk must not be present in the active template"
  fi

  if grep -Fq 'android.permission.WRITE_EXTERNAL_STORAGE' "$android_manifest"; then
    fail "WRITE_EXTERNAL_STORAGE must not be present in the active Android manifest"
  fi

  echo "Android project baseline passed: target API 36, Predictive Back enabled, AGP 8.10.0."
}

resolve_android_toolchain() {
  local unity_executable="${UNITY_EXECUTABLE:-}"
  local unity_editor_dir=""
  local android_player=""

  if [ -n "$unity_executable" ]; then
    [ -x "$unity_executable" ] || fail "Unity executable is not available for Android AAB validation"
    unity_editor_dir="$(cd "$(dirname "$unity_executable")/../../.." && pwd -P)"
    android_player="$unity_editor_dir/PlaybackEngines/AndroidPlayer"
  fi

  RESOLVED_JAVA_BIN="${MOBILE_BASELINE_JAVA_BIN:-}"
  if [ -z "$RESOLVED_JAVA_BIN" ] && [ -x "$android_player/OpenJDK/bin/java" ]; then
    RESOLVED_JAVA_BIN="$android_player/OpenJDK/bin/java"
  fi
  if [ -z "$RESOLVED_JAVA_BIN" ] && [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    RESOLVED_JAVA_BIN="$JAVA_HOME/bin/java"
  fi
  if [ -z "$RESOLVED_JAVA_BIN" ]; then
    RESOLVED_JAVA_BIN="$(command -v java || true)"
  fi
  [ -n "$RESOLVED_JAVA_BIN" ] && [ -x "$RESOLVED_JAVA_BIN" ] ||
    fail "Java is not available for Android AAB validation"

  RESOLVED_BUNDLETOOL_JAR="${MOBILE_BASELINE_BUNDLETOOL_JAR:-}"
  if [ -z "$RESOLVED_BUNDLETOOL_JAR" ] && [ -d "$android_player" ]; then
    RESOLVED_BUNDLETOOL_JAR="$(find "$android_player" -type f -name 'bundletool*.jar' -print -quit 2>/dev/null || true)"
  fi
  [ -n "$RESOLVED_BUNDLETOOL_JAR" ] && [ -r "$RESOLVED_BUNDLETOOL_JAR" ] ||
    fail "Unity bundletool is not available for Android AAB validation"
}

verify_android_aab() {
  local aab_path="$1"
  require_readable_file "$aab_path" "staged Android AAB"
  resolve_android_toolchain

  MOBILE_BASELINE_TEMPORARY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/actionfit-mobile-baseline.XXXXXX")"
  trap 'if [ -n "${MOBILE_BASELINE_TEMPORARY_ROOT:-}" ]; then rm -rf "$MOBILE_BASELINE_TEMPORARY_ROOT"; fi' EXIT
  local manifest_path="$MOBILE_BASELINE_TEMPORARY_ROOT/base-manifest.xml"

  if ! "$RESOLVED_JAVA_BIN" -jar "$RESOLVED_BUNDLETOOL_JAR" dump manifest \
    --bundle="$aab_path" \
    --module=base > "$manifest_path" 2>/dev/null; then
    fail "bundletool could not inspect the staged Android AAB"
  fi

  python3 - "$manifest_path" <<'PY'
import sys
import xml.etree.ElementTree as ET

ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"
TARGET_SDK_ATTRIBUTE = f"{{{ANDROID_NAMESPACE}}}targetSdkVersion"
NAME_ATTRIBUTE = f"{{{ANDROID_NAMESPACE}}}name"
FORBIDDEN_PERMISSION = "android.permission.WRITE_EXTERNAL_STORAGE"

try:
    root = ET.parse(sys.argv[1]).getroot()
except (ET.ParseError, OSError):
    print("::error::Mobile build baseline check failed: bundletool returned an invalid base manifest", file=sys.stderr)
    raise SystemExit(1)

uses_sdk = root.find("uses-sdk")
target_sdk = uses_sdk.get(TARGET_SDK_ATTRIBUTE, "") if uses_sdk is not None else ""
if target_sdk != "36":
    observed = target_sdk or "missing"
    print(
        f"::error::Mobile build baseline check failed: staged Android AAB targetSdkVersion must be 36 (found {observed})",
        file=sys.stderr,
    )
    raise SystemExit(1)

for element in root.findall("uses-permission"):
    if element.get(NAME_ATTRIBUTE) == FORBIDDEN_PERMISSION:
        print(
            "::error::Mobile build baseline check failed: staged Android AAB contains WRITE_EXTERNAL_STORAGE",
            file=sys.stderr,
        )
        raise SystemExit(1)

print("Android AAB baseline passed: target API 36 and no legacy external-storage permission.")
PY
}

verify_ios_toolchain() {
  local xcodebuild_bin="${MOBILE_BASELINE_XCODEBUILD_BIN:-xcodebuild}"
  local xcode_version_output
  local sdk_output

  xcode_version_output="$("$xcodebuild_bin" -version 2>/dev/null)" ||
    fail "Xcode version could not be resolved"
  sdk_output="$("$xcodebuild_bin" -showsdks 2>/dev/null)" ||
    fail "installed Apple SDK versions could not be resolved"

  local xcode_version
  local xcode_major
  xcode_version="$(printf '%s\n' "$xcode_version_output" | sed -n 's/^Xcode[[:space:]]\{1,\}\([0-9][0-9.]*\).*$/\1/p' | head -n 1)"
  xcode_major="${xcode_version%%.*}"
  case "$xcode_major" in
    ''|*[!0-9]*) fail "Xcode version could not be resolved" ;;
  esac
  [ "$xcode_major" -ge 26 ] ||
    fail "Xcode 26 or newer is required (found $xcode_version)"

  local sdk_version
  local sdk_major
  local highest_sdk_version=""
  local highest_sdk_major=0
  while IFS= read -r sdk_version; do
    [ -n "$sdk_version" ] || continue
    sdk_major="${sdk_version%%.*}"
    case "$sdk_major" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ "$sdk_major" -gt "$highest_sdk_major" ]; then
      highest_sdk_major="$sdk_major"
      highest_sdk_version="$sdk_version"
    fi
  done < <(printf '%s\n' "$sdk_output" | sed -n 's/.*-sdk[[:space:]]\{1,\}iphoneos\([0-9][0-9.]*\).*/\1/p')

  [ "$highest_sdk_major" -ge 26 ] ||
    fail "iPhoneOS SDK 26 or newer is required (found ${highest_sdk_version:-missing})"

  echo "iOS toolchain baseline passed: Xcode $xcode_version, iPhoneOS SDK $highest_sdk_version."
}

case "${1:-}" in
  android-settings)
    [ "$#" -eq 2 ] || fail "android-settings requires a Unity project directory"
    verify_android_settings "$2"
    ;;
  android-aab)
    [ "$#" -eq 2 ] || fail "android-aab requires a staged AAB path"
    verify_android_aab "$2"
    ;;
  ios-toolchain)
    [ "$#" -eq 1 ] || fail "ios-toolchain does not accept extra arguments"
    verify_ios_toolchain
    ;;
  *)
    fail "expected android-settings, android-aab, or ios-toolchain"
    ;;
esac
