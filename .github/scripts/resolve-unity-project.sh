#!/usr/bin/env bash
set -euo pipefail

repository_root="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}"
repository_root="$(cd "$repository_root" && pwd -P)"
request_path="${BUILD_REQUEST_PATH:-$repository_root/.build/build_request.json}"
if [[ "$request_path" != /* ]]; then
  request_path="$repository_root/$request_path"
fi

if [ ! -r "$request_path" ]; then
  echo "::error::BuildRequest is not readable: $request_path"
  exit 1
fi

resolved="$({
  ruby -rjson -rdigest -rpathname - "$repository_root" "$request_path" <<'RUBY'
repository_root = File.realpath(ARGV.fetch(0))
request_path = File.expand_path(ARGV.fetch(1), repository_root)
request = JSON.parse(File.read(request_path))
schema_version = request.fetch("schemaVersion", 0).to_i
abort("Unsupported BuildRequest schemaVersion: #{schema_version} (expected 11)") unless schema_version == 11

raw_path = ENV.fetch("UNITY_PROJECT_PATH", request.fetch("unityProjectPath", ".").to_s).strip
raw_path = "." if raw_path.empty?
abort("unityProjectPath contains control characters") if raw_path.match?(/[[:cntrl:]]/)

raw_path = raw_path.tr("\\", "/")
pathname = Pathname.new(raw_path)
abort("unityProjectPath must be relative: #{raw_path}") if pathname.absolute?
abort("unityProjectPath must not contain '..': #{raw_path}") if raw_path.split("/").include?("..")

normalized_path = pathname.cleanpath.to_s.tr("\\", "/")
normalized_path = "." if normalized_path.empty?
project_candidate = File.expand_path(normalized_path, repository_root)
abort("Unity project directory does not exist: #{project_candidate}") unless File.directory?(project_candidate)

project_root = File.realpath(project_candidate)
unless project_root == repository_root || project_root.start_with?(repository_root + File::SEPARATOR)
  abort("Unity project escapes the Git repository: #{project_root}")
end

required_paths = {
  "Assets" => File.join(project_root, "Assets"),
  "Packages/manifest.json" => File.join(project_root, "Packages", "manifest.json"),
  "ProjectSettings/ProjectVersion.txt" => File.join(project_root, "ProjectSettings", "ProjectVersion.txt")
}
required_paths.each do |label, path|
  abort("Unity project file is missing: #{label} (#{path})") unless File.exist?(path)
end

manifest_path = required_paths.fetch("Packages/manifest.json")
packages_lock_path = File.join(project_root, "Packages", "packages-lock.json")
project_version_path = required_paths.fetch("ProjectSettings/ProjectVersion.txt")
cache_digest = Digest::SHA256.new
[manifest_path, packages_lock_path, project_version_path].each do |path|
  cache_digest << path.delete_prefix(repository_root) << "\0"
  cache_digest << File.binread(path) if File.file?(path)
  cache_digest << "\0"
end

project_key_prefix = normalized_path == "." ? "root" : normalized_path
project_key_prefix = project_key_prefix.gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/\A[-.]+|[-.]+\z/, "")
project_key_prefix = "project" if project_key_prefix.empty?
project_key_prefix = project_key_prefix[0, 48].gsub(/[-.]+\z/, "")
project_key_hash = Digest::SHA256.hexdigest(normalized_path)[0, 16]
project_key = "#{project_key_prefix}-#{project_key_hash}"
project_name = File.basename(project_root)
build_root = File.join(project_root, "Builds")
log_root = File.join(project_root, "Logs")
runner_temp = ENV.fetch("RUNNER_TEMP", File.join(repository_root, ".build", "tmp"))

values = {
  "REPOSITORY_ROOT" => repository_root,
  "BUILD_REQUEST_PATH" => request_path,
  "UNITY_PROJECT_PATH" => normalized_path,
  "UNITY_PROJECT_DIR" => project_root,
  "UNITY_PROJECT_NAME" => project_name,
  "UNITY_PROJECT_KEY" => project_key,
  "UNITY_CACHE_INPUT_HASH" => cache_digest.hexdigest,
  "UNITY_PROJECT_VERSION_FILE" => project_version_path,
  "UNITY_MANIFEST_PATH" => manifest_path,
  "UNITY_PACKAGES_LOCK_PATH" => packages_lock_path,
  "UNITY_LIBRARY_DIR" => File.join(project_root, "Library"),
  "UNITY_BUILD_DIR" => build_root,
  "UNITY_LOG_DIR" => log_root,
  "BUILD_CLEANUP_ROOT" => build_root,
  "BUILD_CLEANUP_REQUEST_PATH" => request_path,
  "ANDROID_UPLOAD_DIR" => File.join(repository_root, ".build", "google-play-upload"),
  "IOS_XCODE_BUILD_PATH" => File.join(build_root, "iOS"),
  "IOS_ARCHIVE_PATH" => File.join(build_root, "iOSArchive", "BuildCommit.xcarchive"),
  "IOS_EXPORT_PATH" => File.join(build_root, "iOSExport"),
  "IOS_EXPORT_OPTIONS_PATH" => File.join(runner_temp, "BuildCommit-ExportOptions.plist")
}

values.each { |key, value| puts("#{key}\t#{value}") }
RUBY
} 2>&1)" || {
  echo "::error::$resolved"
  exit 1
}

append_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  if [ -n "$file" ]; then
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

REPOSITORY_ROOT=""
UNITY_PROJECT_PATH=""
UNITY_PROJECT_DIR=""

while IFS=$'\t' read -r key value; do
  [ -z "$key" ] && continue
  append_value "${GITHUB_ENV:-}" "$key" "$value"
  append_value "${GITHUB_OUTPUT:-}" "$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')" "$value"
  export "$key=$value"
done <<< "$resolved"

echo "Resolved Git repository root: $REPOSITORY_ROOT"
echo "Resolved Unity project path: $UNITY_PROJECT_PATH"
echo "Resolved Unity project directory: $UNITY_PROJECT_DIR"
