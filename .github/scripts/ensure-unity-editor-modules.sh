#!/usr/bin/env bash
set -euo pipefail

unity_project_dir="${UNITY_PROJECT_DIR:-${GITHUB_WORKSPACE:-$PWD}}"
project_version_file="${UNITY_PROJECT_VERSION_FILE:-$unity_project_dir/ProjectSettings/ProjectVersion.txt}"
editor_root="${UNITY_HUB_EDITOR_ROOT:-/Applications/Unity/Hub/Editor}"
unity_hub="${UNITY_HUB_EXECUTABLE:-/Applications/Unity Hub.app/Contents/MacOS/Unity Hub}"
installer_root="${ACTIONFIT_UNITY_INSTALLER_ROOT:-$HOME/.cache/actionfit-unity-installer}"
auto_install="${ACTIONFIT_UNITY_AUTO_INSTALL:-true}"
architecture="${UNITY_EDITOR_ARCHITECTURE:-arm64}"
lock_timeout_seconds="${ACTIONFIT_UNITY_INSTALL_LOCK_TIMEOUT_SECONDS:-14400}"
stale_lock_seconds="${ACTIONFIT_UNITY_INSTALL_STALE_LOCK_SECONDS:-7200}"
wait_interval_seconds="${ACTIONFIT_UNITY_INSTALL_WAIT_INTERVAL_SECONDS:-20}"

requested_platform="${1:-${ACTIONFIT_UNITY_REQUIRED_PLATFORM:-}}"

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

if [ ! -r "$project_version_file" ]; then
  echo "::error::Unity ProjectVersion file is not readable: $project_version_file"
  exit 1
fi

unity_version="$(sed -n 's/^m_EditorVersion:[[:space:]]*//p' "$project_version_file" | head -n 1 | tr -d '\r')"
unity_version_with_revision="$(sed -n 's/^m_EditorVersionWithRevision:[[:space:]]*//p' "$project_version_file" | head -n 1 | tr -d '\r')"
changeset="$(printf '%s\n' "$unity_version_with_revision" | sed -n 's/^.*(\([^)]*\)).*$/\1/p' | head -n 1 | tr -d '\r')"

if [ -z "$unity_version" ]; then
  echo "::error::m_EditorVersion was not found in $project_version_file"
  exit 1
fi

unity_dir="$editor_root/$unity_version"
unity_executable="$unity_dir/Unity.app/Contents/MacOS/Unity"

declare -a required_modules=()
install_child_modules=false

case "$requested_platform" in
  Android|AOS|android|aos)
    required_modules=("android")
    install_child_modules=true
    ;;
  iOS|IOS|ios)
    required_modules=("ios")
    ;;
  Both|both)
    required_modules=("android" "ios")
    install_child_modules=true
    ;;
  ""|None|none)
    required_modules=()
    ;;
  *)
    echo "::error::Unsupported Unity module platform: $requested_platform"
    exit 1
    ;;
esac

module_label() {
  case "$1" in
    android) printf 'Android Build Support';;
    ios) printf 'iOS Build Support';;
    *) printf '%s' "$1";;
  esac
}

module_installed() {
  local module="$1"
  case "$module" in
    android)
      [ -d "$unity_dir/PlaybackEngines/AndroidPlayer" ] &&
        [ -d "$unity_dir/PlaybackEngines/AndroidPlayer/SDK" ] &&
        [ -d "$unity_dir/PlaybackEngines/AndroidPlayer/NDK" ] &&
        [ -d "$unity_dir/PlaybackEngines/AndroidPlayer/OpenJDK" ]
      ;;
    ios)
      [ -d "$unity_dir/PlaybackEngines/iOSSupport" ]
      ;;
    *)
      return 1
      ;;
  esac
}

collect_missing() {
  missing_editor=false
  missing_items=()
  missing_modules=()

  if [ ! -x "$unity_executable" ]; then
    missing_editor=true
    missing_items+=("Unity Editor $unity_version")
  fi

  local module
  for module in "${required_modules[@]}"; do
    if ! module_installed "$module"; then
      missing_modules+=("$module")
      missing_items+=("$(module_label "$module")")
    fi
  done
}

join_by_comma() {
  local first=true
  local value
  for value in "$@"; do
    if [ "$first" = true ]; then
      first=false
    else
      printf ', '
    fi
    printf '%s' "$value"
  done
}

collect_missing

if [ "${#missing_items[@]}" -eq 0 ]; then
  echo "Unity editor and requested modules are already installed for $unity_version."
  append_github_output "installed" "false"
  append_github_output "waited" "false"
  exit 0
fi

if [ "$auto_install" != "true" ]; then
  echo "::error::Missing Unity environment: $(join_by_comma "${missing_items[@]}"). Automatic install is disabled."
  exit 1
fi

if [ ! -x "$unity_hub" ]; then
  echo "::error::Unity Hub executable not found: $unity_hub"
  exit 1
fi

mkdir -p "$installer_root/locks" "$installer_root/logs"

safe_version="$(printf '%s' "$unity_version" | tr -c '[:alnum:]._-+' '_')"
lock_dir="$installer_root/locks/unity-$safe_version.lock"
log_path="$installer_root/logs/unity-$safe_version-install.log"
waited=false
lock_acquired=false
heartbeat_pid=""

release_lock() {
  if [ -n "${heartbeat_pid:-}" ]; then
    kill "$heartbeat_pid" >/dev/null 2>&1 || true
  fi

  if [ "$lock_acquired" = true ]; then
    rm -rf "$lock_dir"
  fi
}

trap release_lock EXIT

lock_started_at="$(date +%s)"
while ! mkdir "$lock_dir" 2>/dev/null; do
  waited=true
  now="$(date +%s)"

  owner_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  heartbeat="$(cat "$lock_dir/heartbeat" 2>/dev/null || true)"
  lock_age=$((now - $(stat -f %m "$lock_dir" 2>/dev/null || printf '%s' "$now")))
  heartbeat_age=0

  if [[ "$heartbeat" =~ ^[0-9]+$ ]]; then
    heartbeat_age=$((now - heartbeat))
  else
    heartbeat_age="$lock_age"
  fi

  if { [ -z "$owner_pid" ] || ! kill -0 "$owner_pid" >/dev/null 2>&1; } && [ "$heartbeat_age" -ge "$stale_lock_seconds" ]; then
    echo "::warning::Removing stale Unity installer lock: $lock_dir"
    rm -rf "$lock_dir"
    continue
  fi

  if [ "$((now - lock_started_at))" -ge "$lock_timeout_seconds" ]; then
    echo "::error::Timed out waiting for Unity installer lock: $lock_dir"
    exit 1
  fi

  echo "Waiting for Unity installer lock: $lock_dir"
  sleep "$wait_interval_seconds"
done

lock_acquired=true
{
  echo "$$" > "$lock_dir/pid"
  date +%s > "$lock_dir/heartbeat"
  printf '%s\n' "${GITHUB_RUN_ID:-}" > "$lock_dir/run_id"
  printf '%s\n' "${GITHUB_REPOSITORY:-}" > "$lock_dir/repository"
  printf '%s\n' "${requested_platform:-}" > "$lock_dir/platform"
  printf '%s\n' "$(join_by_comma "${missing_items[@]}")" > "$lock_dir/missing"
} 2>/dev/null || true

(
  while true; do
    date +%s > "$lock_dir/heartbeat" 2>/dev/null || true
    sleep 15
  done
) &
heartbeat_pid="$!"

collect_missing
if [ "${#missing_items[@]}" -eq 0 ]; then
  echo "Unity environment was installed by another job while waiting."
  append_github_output "installed" "false"
  append_github_output "waited" "$waited"
  exit 0
fi

run_hub() {
  echo "+ Unity Hub -- --headless $*" | tee -a "$log_path"
  "$unity_hub" -- --headless "$@" 2>&1 | tee -a "$log_path"
}

install_status=0

{
  echo "==== $(date '+%Y-%m-%d %H:%M:%S %Z') ===="
  echo "Unity version: $unity_version"
  echo "Unity revision: $unity_version_with_revision"
  echo "Requested platform: $requested_platform"
  echo "Missing: $(join_by_comma "${missing_items[@]}")"
} >> "$log_path"

run_hub install-path --set "$editor_root" || install_status=$?

if [ "$install_status" -eq 0 ] && [ "$missing_editor" = true ]; then
  install_args=(install --version "$unity_version")
  if [ -n "$changeset" ]; then
    install_args+=(--changeset "$changeset")
  fi
  if [ -n "$architecture" ]; then
    install_args+=(--architecture "$architecture")
  fi

  run_hub "${install_args[@]}" || install_status=$?
fi

if [ "$install_status" -eq 0 ] && [ "${#missing_modules[@]}" -gt 0 ]; then
  module_args=(install-modules --version "$unity_version" --module "${missing_modules[@]}")
  if [ "$install_child_modules" = true ]; then
    module_args+=(--childModules)
  fi

  run_hub "${module_args[@]}" || install_status=$?
fi

collect_missing

if [ "$install_status" -ne 0 ] || [ "${#missing_items[@]}" -ne 0 ]; then
  echo "::error::Unity environment install failed. Missing after install: $(join_by_comma "${missing_items[@]}"). See $log_path"
  exit 1
fi

append_github_output "installed" "true"
append_github_output "waited" "$waited"

echo "Unity environment is ready for $unity_version."
