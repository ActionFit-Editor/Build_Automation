#!/usr/bin/env bash
set -euo pipefail

if [ "${MOBILE_BASELINE_FAKE_JAVA:-false}" = "true" ]; then
  permission_element=""
  if [ "${MOBILE_BASELINE_TEST_PERMISSION:-false}" = "true" ]; then
    permission_element='<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />'
  fi
  printf '%s\n' \
    '<?xml version="1.0" encoding="utf-8"?>' \
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">' \
    "<uses-sdk android:minSdkVersion=\"28\" android:targetSdkVersion=\"${MOBILE_BASELINE_TEST_TARGET:-36}\" />" \
    "$permission_element" \
    '</manifest>'
  exit 0
fi

if [ "${MOBILE_BASELINE_FAKE_XCODE:-false}" = "true" ]; then
  case "${1:-}" in
    -version)
      printf 'Xcode %s\nBuild version TEST\n' "${MOBILE_BASELINE_TEST_XCODE_VERSION:-26.0}"
      ;;
    -showsdks)
      printf 'iOS SDKs:\n\tiOS %s -sdk iphoneos%s\n' \
        "${MOBILE_BASELINE_TEST_IOS_SDK_VERSION:-26.0}" \
        "${MOBILE_BASELINE_TEST_IOS_SDK_VERSION:-26.0}"
      ;;
    *)
      exit 2
      ;;
  esac
  exit 0
fi

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
baseline_script="$package_root/.github/scripts/verify-mobile-build-baseline.sh"
test_script="$package_root/Tests/Shell/test-mobile-build-baseline.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

fail_test() {
  echo "$1" >&2
  exit 1
}

expect_pass() {
  local label="$1"
  shift
  "$@" >/dev/null || fail_test "Expected success: $label"
}

expect_failure() {
  local label="$1"
  local expected_message="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)"; then
    fail_test "Expected failure: $label"
  fi
  printf '%s\n' "$output" | grep -Fq "$expected_message" ||
    fail_test "Missing failure diagnostic for $label"
}

create_android_fixture() {
  local root="$1"
  local target_sdk="$2"
  local predictive_back="$3"
  local min_sdk="$4"
  local agp_version="$5"
  local include_suppression="$6"
  local include_permission="$7"

  mkdir -p "$root/ProjectSettings" "$root/Assets/Plugins/Android"
  printf '  androidPredictiveBackSupport: %s\n  AndroidMinSdkVersion: %s\n  AndroidTargetSdkVersion: %s\n' \
    "$predictive_back" "$min_sdk" "$target_sdk" > "$root/ProjectSettings/ProjectSettings.asset"
  printf "plugins {\n    id 'com.android.application' version '%s' apply false\n    id 'com.android.library' version '%s' apply false\n}\n" \
    "$agp_version" "$agp_version" > "$root/Assets/Plugins/Android/baseProjectTemplate.gradle"
  printf 'android.useAndroidX=true\n' > "$root/Assets/Plugins/Android/gradleTemplate.properties"
  if [ "$include_suppression" = "true" ]; then
    printf 'android.suppressUnsupportedCompileSdk=34\n' >> "$root/Assets/Plugins/Android/gradleTemplate.properties"
  fi
  printf '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n' > "$root/Assets/Plugins/Android/AndroidManifest.xml"
  if [ "$include_permission" = "true" ]; then
    printf '  <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />\n' >> "$root/Assets/Plugins/Android/AndroidManifest.xml"
  fi
  printf '</manifest>\n' >> "$root/Assets/Plugins/Android/AndroidManifest.xml"
}

android_fixture="$fixture_root/android"
create_android_fixture "$android_fixture" 36 1 28 8.10.0 false false
expect_pass "valid Android project baseline" \
  bash "$baseline_script" android-settings "$android_fixture"

create_android_fixture "$android_fixture" 35 1 28 8.10.0 false false
expect_failure "Android target API" "AndroidTargetSdkVersion must be 36 (found 35)" \
  bash "$baseline_script" android-settings "$android_fixture"

create_android_fixture "$android_fixture" 36 0 28 8.10.0 false false
expect_failure "Predictive Back" "androidPredictiveBackSupport must be 1 (found 0)" \
  bash "$baseline_script" android-settings "$android_fixture"

create_android_fixture "$android_fixture" 36 1 28 8.7.2 false false
expect_failure "Android Gradle Plugin" "Android application plugin must use AGP 8.10.0" \
  bash "$baseline_script" android-settings "$android_fixture"

create_android_fixture "$android_fixture" 36 1 28 8.10.0 true false
expect_failure "unsupported compile SDK suppression" "android.suppressUnsupportedCompileSdk must not be present" \
  bash "$baseline_script" android-settings "$android_fixture"

create_android_fixture "$android_fixture" 36 1 28 8.10.0 false true
expect_failure "active Android legacy permission" "WRITE_EXTERNAL_STORAGE must not be present" \
  bash "$baseline_script" android-settings "$android_fixture"

aab_path="$fixture_root/release.aab"
bundletool_path="$fixture_root/bundletool.jar"
: > "$aab_path"
: > "$bundletool_path"

expect_pass "valid final Android AAB baseline" \
  env MOBILE_BASELINE_FAKE_JAVA=true \
    MOBILE_BASELINE_TEST_TARGET=36 \
    MOBILE_BASELINE_JAVA_BIN="$test_script" \
    MOBILE_BASELINE_BUNDLETOOL_JAR="$bundletool_path" \
    bash "$baseline_script" android-aab "$aab_path"

fake_unity_root="$fixture_root/6000.3.9f1"
fake_unity_executable="$fake_unity_root/Unity.app/Contents/MacOS/Unity"
mkdir -p \
  "$(dirname "$fake_unity_executable")" \
  "$fake_unity_root/PlaybackEngines/AndroidPlayer/OpenJDK/bin" \
  "$fake_unity_root/PlaybackEngines/AndroidPlayer/Tools"
ln -s "$test_script" "$fake_unity_executable"
ln -s "$test_script" "$fake_unity_root/PlaybackEngines/AndroidPlayer/OpenJDK/bin/java"
: > "$fake_unity_root/PlaybackEngines/AndroidPlayer/Tools/bundletool-test.jar"
expect_pass "Unity Hub Android toolchain discovery" \
  env MOBILE_BASELINE_FAKE_JAVA=true \
    MOBILE_BASELINE_TEST_TARGET=36 \
    UNITY_EXECUTABLE="$fake_unity_executable" \
    bash "$baseline_script" android-aab "$aab_path"

expect_failure "final Android AAB target API" "targetSdkVersion must be 36 (found 35)" \
  env MOBILE_BASELINE_FAKE_JAVA=true \
    MOBILE_BASELINE_TEST_TARGET=35 \
    MOBILE_BASELINE_JAVA_BIN="$test_script" \
    MOBILE_BASELINE_BUNDLETOOL_JAR="$bundletool_path" \
    bash "$baseline_script" android-aab "$aab_path"

expect_failure "final Android AAB legacy permission" "staged Android AAB contains WRITE_EXTERNAL_STORAGE" \
  env MOBILE_BASELINE_FAKE_JAVA=true \
    MOBILE_BASELINE_TEST_TARGET=36 \
    MOBILE_BASELINE_TEST_PERMISSION=true \
    MOBILE_BASELINE_JAVA_BIN="$test_script" \
    MOBILE_BASELINE_BUNDLETOOL_JAR="$bundletool_path" \
    bash "$baseline_script" android-aab "$aab_path"

expect_pass "Xcode 26 and iPhoneOS SDK 26" \
  env MOBILE_BASELINE_FAKE_XCODE=true \
    MOBILE_BASELINE_TEST_XCODE_VERSION=26.0 \
    MOBILE_BASELINE_TEST_IOS_SDK_VERSION=26.0 \
    MOBILE_BASELINE_XCODEBUILD_BIN="$test_script" \
    bash "$baseline_script" ios-toolchain

expect_failure "Xcode 25" "Xcode 26 or newer is required (found 25.4)" \
  env MOBILE_BASELINE_FAKE_XCODE=true \
    MOBILE_BASELINE_TEST_XCODE_VERSION=25.4 \
    MOBILE_BASELINE_TEST_IOS_SDK_VERSION=26.0 \
    MOBILE_BASELINE_XCODEBUILD_BIN="$test_script" \
    bash "$baseline_script" ios-toolchain

expect_failure "iPhoneOS SDK 25" "iPhoneOS SDK 26 or newer is required (found 25.2)" \
  env MOBILE_BASELINE_FAKE_XCODE=true \
    MOBILE_BASELINE_TEST_XCODE_VERSION=26.1 \
    MOBILE_BASELINE_TEST_IOS_SDK_VERSION=25.2 \
    MOBILE_BASELINE_XCODEBUILD_BIN="$test_script" \
    bash "$baseline_script" ios-toolchain

echo "Mobile build baseline tests passed"
