#!/usr/bin/env bash
set -euo pipefail

unity_project_dir="${UNITY_PROJECT_DIR:-${GITHUB_WORKSPACE:-$PWD}}"
build_root="${BUILD_CLEANUP_ROOT:-$unity_project_dir/Builds}"
retention_days="${BUILD_CLEANUP_RETENTION_DAYS:-5}"
repository_name="${GITHUB_REPOSITORY:-}"
repository_name="${repository_name##*/}"
project_name="${BUILD_CLEANUP_PROJECT_NAME:-$repository_name}"
build_version="${BUILD_CLEANUP_BUILD_VERSION:-${BUILD_VERSION:-}}"
bundle_no="${BUILD_CLEANUP_BUNDLE_NO:-${BUILD_BUNDLE_NO:-}}"
dry_run="${BUILD_CLEANUP_DRY_RUN:-false}"

if ! [[ "$retention_days" =~ ^[0-9]+$ ]] || [ "$retention_days" -lt 1 ]; then
  echo "::error::BUILD_CLEANUP_RETENTION_DAYS must be a positive integer: $retention_days"
  exit 1
fi

if [ ! -d "$build_root" ]; then
  echo "Build cleanup skipped; build root does not exist: $build_root"
  exit 0
fi

threshold_epoch="$(date -v-"${retention_days}"d +%s 2>/dev/null || date -d "${retention_days} days ago" +%s)"

read_build_request_field() {
  local field="$1"
  local request_path="${BUILD_CLEANUP_REQUEST_PATH:-${GITHUB_WORKSPACE:-$PWD}/.build/build_request.json}"
  if [ ! -r "$request_path" ]; then
    return 0
  fi

  ruby -rjson -e '
    path = ARGV.fetch(0)
    field = ARGV.fetch(1)
    value = JSON.parse(File.read(path))[field]
    print value.to_s
  ' "$request_path" "$field" 2>/dev/null || true
}

build_file_name="${BUILD_CLEANUP_BUILD_FILE_NAME:-$(read_build_request_field buildFileName)}"

prefixes=()
add_prefix() {
  local value="$1"
  if [ -z "$value" ]; then
    return 0
  fi

  local existing
  if [ "${#prefixes[@]}" -gt 0 ]; then
    for existing in "${prefixes[@]}"; do
      if [ "$existing" = "$value" ]; then
        return 0
      fi
    done
  fi

  prefixes+=("$value")
}

add_prefix "$project_name"
add_prefix "$build_file_name"

if [ "${#prefixes[@]}" -eq 0 ]; then
  echo "::warning::Build cleanup skipped; project name/build file name could not be resolved."
  exit 0
fi

version_core="$build_version"
case "$version_core" in
  v*|V*)
    version_core="${version_core#?}"
    ;;
esac

current_names=()
add_current_name() {
  local value="$1"
  if [ -n "$value" ]; then
    current_names+=("$value")
  fi
}

for prefix in "${prefixes[@]}"; do
  if [ -n "$version_core" ] && [ -n "$bundle_no" ]; then
    add_current_name "${prefix}_v${version_core}(${bundle_no})"
  fi
  if [ -n "$version_core" ]; then
    add_current_name "${prefix}_v${version_core}"
  fi
  if [ -n "$build_version" ] && [ -n "$bundle_no" ]; then
    add_current_name "${prefix}_${build_version}(${bundle_no})"
  fi
  if [ -n "$build_version" ]; then
    add_current_name "${prefix}_${build_version}"
  fi
done

age_epoch() {
  local path="$1"
  local birth_epoch
  local modified_epoch

  birth_epoch="$(stat -f '%B' "$path" 2>/dev/null || echo -1)"
  modified_epoch="$(stat -f '%m' "$path" 2>/dev/null || echo 0)"

  if [[ "$birth_epoch" =~ ^[0-9]+$ ]] && [ "$birth_epoch" -gt 0 ]; then
    printf '%s\n' "$birth_epoch"
  else
    printf '%s\n' "$modified_epoch"
  fi
}

is_same_project_artifact() {
  local name="$1"
  local prefix
  for prefix in "${prefixes[@]}"; do
    case "$name" in
      "${prefix}"_v*|"${prefix}"_V*)
        return 0
        ;;
    esac
  done

  return 1
}

is_current_artifact() {
  local name="$1"
  local current_name
  if [ "${#current_names[@]}" -gt 0 ]; then
    for current_name in "${current_names[@]}"; do
      if [ "$name" = "$current_name" ]; then
        return 0
      fi
    done
  fi

  return 1
}

deleted_count=0
freed_bytes=0

echo "Build cleanup root: $build_root"
echo "Build cleanup retention: ${retention_days} days"
echo "Build cleanup prefixes: ${prefixes[*]}"

while IFS= read -r -d '' path; do
  name="$(basename "$path")"

  if ! is_same_project_artifact "$name"; then
    continue
  fi

  if is_current_artifact "$name"; then
    echo "Keeping current build artifact: $path"
    continue
  fi

  artifact_epoch="$(age_epoch "$path")"
  if ! [[ "$artifact_epoch" =~ ^[0-9]+$ ]] || [ "$artifact_epoch" -gt "$threshold_epoch" ]; then
    continue
  fi

  size_bytes="$(du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}' || echo 0)"
  echo "Deleting old build artifact: $path"
  if [ "$dry_run" = "true" ]; then
    echo "Dry run enabled; not deleting: $path"
  else
    rm -rf "$path"
  fi

  deleted_count=$((deleted_count + 1))
  freed_bytes=$((freed_bytes + size_bytes))
done < <(find "$build_root" -mindepth 1 -maxdepth 1 \( -type d -o -type f \) -print0)

freed_mib=$((freed_bytes / 1024 / 1024))
if [ "$dry_run" = "true" ]; then
  echo "Build cleanup dry run completed. Matched ${deleted_count} old artifact(s), ${freed_mib} MiB."
else
  echo "Build cleanup completed. Deleted ${deleted_count} old artifact(s), approximately ${freed_mib} MiB."
fi
