#!/usr/bin/env bash
set -euo pipefail

unity_project_dir="${UNITY_PROJECT_DIR:-${GITHUB_WORKSPACE:-$PWD}}"
project_version_file="${UNITY_PROJECT_VERSION_FILE:-$unity_project_dir/ProjectSettings/ProjectVersion.txt}"
editor_root="${UNITY_HUB_EDITOR_ROOT:-/Applications/Unity/Hub/Editor}"

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

if [ ! -r "$project_version_file" ]; then
  echo "::error::Unity ProjectVersion file is not readable: $project_version_file"
  exit 1
fi

unity_version="$(sed -n 's/^m_EditorVersion:[[:space:]]*//p' "$project_version_file" | head -n 1 | tr -d '\r')"
unity_version_with_revision="$(sed -n 's/^m_EditorVersionWithRevision:[[:space:]]*//p' "$project_version_file" | head -n 1 | tr -d '\r')"

if [ -z "$unity_version" ]; then
  echo "::error::m_EditorVersion was not found in $project_version_file"
  exit 1
fi

unity_executable="$editor_root/$unity_version/Unity.app/Contents/MacOS/Unity"
if [ ! -x "$unity_executable" ]; then
  echo "::error::Unity executable not found for project editor version $unity_version: $unity_executable"
  if [ -d "$editor_root" ]; then
    echo "Installed Unity editors under $editor_root:"
    find "$editor_root" -maxdepth 1 -mindepth 1 -type d -print | sort || true
  else
    echo "Unity editor root does not exist: $editor_root"
  fi
  exit 1
fi

append_github_env "UNITY_VERSION" "$unity_version"
append_github_env "UNITY_VERSION_WITH_REVISION" "$unity_version_with_revision"
append_github_env "UNITY_EXECUTABLE" "$unity_executable"

append_github_output "unity_version" "$unity_version"
append_github_output "unity_version_with_revision" "$unity_version_with_revision"
append_github_output "unity_executable" "$unity_executable"

echo "Resolved Unity editor version: $unity_version"
if [ -n "$unity_version_with_revision" ]; then
  echo "Resolved Unity editor revision: $unity_version_with_revision"
fi
echo "Resolved Unity executable: $unity_executable"
