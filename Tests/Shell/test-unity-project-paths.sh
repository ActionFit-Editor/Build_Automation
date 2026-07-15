#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
resolver="$package_root/.github/scripts/resolve-unity-project.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

create_unity_project() {
  local root="$1"
  mkdir -p "$root/Assets" "$root/Packages" "$root/ProjectSettings"
  printf '{"dependencies":{}}\n' > "$root/Packages/manifest.json"
  printf '{"dependencies":{}}\n' > "$root/Packages/packages-lock.json"
  printf 'm_EditorVersion: 6000.2.8f1\n' > "$root/ProjectSettings/ProjectVersion.txt"
}

run_resolver() {
  local repository="$1"
  local output="$2"
  : > "$output"
  GITHUB_WORKSPACE="$repository" \
  GITHUB_OUTPUT="$output" \
  GITHUB_ENV="$fixture_root/github-env" \
  RUNNER_TEMP="$fixture_root/runner-temp" \
  bash "$resolver" >/dev/null
}

root_repository="$fixture_root/root-project"
mkdir -p "$root_repository/.build"
root_repository="$(cd "$root_repository" && pwd -P)"
create_unity_project "$root_repository"
printf '{"schemaVersion":12,"unityProjectPath":"."}\n' > "$root_repository/.build/build_request.json"
run_resolver "$root_repository" "$fixture_root/root-output"
grep -Fx 'unity_project_path=.' "$fixture_root/root-output" >/dev/null
grep -Fx "unity_project_dir=$root_repository" "$fixture_root/root-output" >/dev/null

nested_repository="$fixture_root/nested-project"
mkdir -p "$nested_repository/.build"
nested_repository="$(cd "$nested_repository" && pwd -P)"
create_unity_project "$nested_repository/KnitFactory"
printf '{"schemaVersion":12,"unityProjectPath":"KnitFactory"}\n' > "$nested_repository/.build/build_request.json"
run_resolver "$nested_repository" "$fixture_root/nested-output"
grep -Fx 'unity_project_path=KnitFactory' "$fixture_root/nested-output" >/dev/null
grep -Fx "unity_project_dir=$nested_repository/KnitFactory" "$fixture_root/nested-output" >/dev/null
grep -Fx "unity_build_dir=$nested_repository/KnitFactory/Builds" "$fixture_root/nested-output" >/dev/null
grep -Fx "ios_export_options_path=$fixture_root/runner-temp/BuildCommit-ExportOptions.plist" "$fixture_root/nested-output" >/dev/null

create_unity_project "$nested_repository/Games/Foo"
printf '{"schemaVersion":12,"unityProjectPath":"Games/Foo"}\n' > "$nested_repository/.build/build_request.json"
run_resolver "$nested_repository" "$fixture_root/slash-key-output"
slash_key="$(sed -n 's/^unity_project_key=//p' "$fixture_root/slash-key-output")"

create_unity_project "$nested_repository/Games-Foo"
printf '{"schemaVersion":12,"unityProjectPath":"Games-Foo"}\n' > "$nested_repository/.build/build_request.json"
run_resolver "$nested_repository" "$fixture_root/dash-key-output"
dash_key="$(sed -n 's/^unity_project_key=//p' "$fixture_root/dash-key-output")"
if [ "$slash_key" = "$dash_key" ] || [ "${#slash_key}" -gt 65 ] || [ "${#dash_key}" -gt 65 ]; then
  echo "Expected bounded, collision-resistant Unity project cache keys" >&2
  exit 1
fi

printf '{"schemaVersion":11,"unityProjectPath":"KnitFactory"}\n' > "$nested_repository/.build/build_request.json"
if run_resolver "$nested_repository" "$fixture_root/legacy-output" 2>/dev/null; then
  echo "Expected legacy BuildRequest schema to fail" >&2
  exit 1
fi

printf '{"schemaVersion":12,"unityProjectPath":"../outside"}\n' > "$nested_repository/.build/build_request.json"
if run_resolver "$nested_repository" "$fixture_root/unsafe-output" 2>/dev/null; then
  echo "Expected traversal unityProjectPath to fail" >&2
  exit 1
fi

outside_project="$fixture_root/outside-project"
create_unity_project "$outside_project"
ln -s "$outside_project" "$nested_repository/LinkedProject"
printf '{"schemaVersion":12,"unityProjectPath":"LinkedProject"}\n' > "$nested_repository/.build/build_request.json"
if run_resolver "$nested_repository" "$fixture_root/symlink-output" 2>/dev/null; then
  echo "Expected symlink escape unityProjectPath to fail" >&2
  exit 1
fi

echo "Unity project path tests passed"
