#!/usr/bin/env bash
set -euo pipefail

github_host="${ACTIONFIT_GITHUB_HOST:-github.com}"
unity_project_dir="${UNITY_PROJECT_DIR:-${GITHUB_WORKSPACE:-$PWD}}"
manifest_path="${UNITY_MANIFEST_PATH:-$unity_project_dir/Packages/manifest.json}"
owners="${ACTIONFIT_PRIVATE_PACKAGE_OWNERS:-ActionFit-Editor ActionFitGames}"
secret_root="${CI_SECRET_ROOT:-$HOME/ci-secrets/build-automation}"
token_file="${ACTIONFIT_GITHUB_PACKAGE_READ_TOKEN_FILE:-$secret_root/shared/github-package-read-token}"
token="${ACTIONFIT_GITHUB_PACKAGE_READ_TOKEN:-${GITHUB_PACKAGE_READ_TOKEN:-}}"

add_global_config_value() {
  local key="$1"
  local value="$2"

  if git config --global --get-all "$key" 2>/dev/null | grep -Fx -- "$value" >/dev/null; then
    return
  fi

  git config --global --add "$key" "$value"
}

read_token_file() {
  local path="$1"
  if [ ! -r "$path" ]; then
    return 0
  fi

  sed -n \
    -e '/^[[:space:]]*#/d' \
    -e '/^[[:space:]]*$/d' \
    -e 's/^[[:space:]]*//' \
    -e 's/[[:space:]]*$//' \
    -e 'p' \
    -e 'q' \
    "$path"
}

configure_token_helper() {
  local helper_token_file="$1"
  local helper_dir="$secret_root/.git-helpers"
  local helper_path="$helper_dir/github-package-credential-helper.sh"

  mkdir -p "$helper_dir"
  chmod 700 "$helper_dir"

  cat > "$helper_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

token_file="$helper_token_file"
token=""
if [ -r "\$token_file" ]; then
  token="\$(sed -n -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*\$//' -e 'p' -e 'q' "\$token_file")"
fi

if [ -z "\$token" ]; then
  exit 0
fi

while IFS= read -r line; do
  [ -z "\$line" ] && break
done

printf 'username=x-access-token\n'
printf 'password=%s\n' "\$token"
EOF

  chmod 700 "$helper_path"
  git config --local --unset-all "http.https://$github_host/.extraheader" 2>/dev/null || true
  git config --global --unset-all "http.https://$github_host/.extraheader" 2>/dev/null || true
  git config --global --replace-all "credential.helper" ""
  git config --global --replace-all "credential.https://$github_host.helper" "!$helper_path"

  export GIT_CONFIG_COUNT=2
  export GIT_CONFIG_KEY_0="credential.helper"
  export GIT_CONFIG_VALUE_0=""
  export GIT_CONFIG_KEY_1="credential.https://$github_host.helper"
  export GIT_CONFIG_VALUE_1="!$helper_path"

  if [ -n "${GITHUB_ENV:-}" ]; then
    {
      echo "GIT_CONFIG_COUNT=$GIT_CONFIG_COUNT"
      echo "GIT_CONFIG_KEY_0=$GIT_CONFIG_KEY_0"
      echo "GIT_CONFIG_VALUE_0=$GIT_CONFIG_VALUE_0"
      echo "GIT_CONFIG_KEY_1=$GIT_CONFIG_KEY_1"
      echo "GIT_CONFIG_VALUE_1=$GIT_CONFIG_VALUE_1"
    } >> "$GITHUB_ENV"
  fi
}

ensure_github_credential() {
  if command -v gh >/dev/null 2>&1 && gh auth status --hostname "$github_host" >/dev/null 2>&1; then
    gh auth setup-git --hostname "$github_host" >/dev/null
    echo "GitHub credential helper prepared from gh auth for $github_host"
    return 0
  fi

  if [ -z "$token" ]; then
    token="$(read_token_file "$token_file")"
  fi

  if [ -n "$token" ]; then
    echo "::add-mask::$token"
    local helper_token_file="$token_file"
    if [ ! -r "$helper_token_file" ]; then
      helper_token_file="${RUNNER_TEMP:-/tmp}/actionfit-github-package-read-token"
      printf '%s\n' "$token" > "$helper_token_file"
      chmod 600 "$helper_token_file"
    fi

    configure_token_helper "$helper_token_file"
    echo "GitHub credential helper prepared from local package read token"
    return 0
  fi

  return 1
}

collect_actionfit_github_repositories() {
  if [ ! -r "$manifest_path" ]; then
    echo "::warning::Unity manifest is not readable: $manifest_path" >&2
    return 0
  fi

  ruby - "$manifest_path" "$owners" "$github_host" <<'RUBY'
require "json"

manifest_path = ARGV.fetch(0)
owners = ARGV.fetch(1).split(/\s+/).reject(&:empty?)
github_host = ARGV.fetch(2)
dependencies = JSON.parse(File.read(manifest_path)).fetch("dependencies", {})
repositories = []

dependencies.each_value do |value|
  next unless value.is_a?(String)

  raw = value.strip
  owner = nil
  repo = nil

  patterns = [
    %r{\A(?:git\+)?https://#{Regexp.escape(github_host)}/([^/]+)/([^?#]+?)(?:[?#].*)?\z},
    %r{\Assh://git@#{Regexp.escape(github_host)}/([^/]+)/([^?#]+?)(?:[?#].*)?\z},
    %r{\Agit@#{Regexp.escape(github_host)}:([^/]+)/([^?#]+?)(?:[?#].*)?\z}
  ]

  patterns.each do |pattern|
    match = raw.match(pattern)
    next unless match

    owner = match[1]
    repo = match[2].sub(/\.git\z/, "")
    break
  end

  next if owner.nil? || repo.nil?
  next unless owners.include?(owner)

  repositories << "https://#{github_host}/#{owner}/#{repo}.git"
end

puts repositories.uniq
RUBY
}

add_global_config_value "url.https://$github_host/.insteadOf" "git@$github_host:"
add_global_config_value "url.https://$github_host/.insteadOf" "ssh://git@$github_host/"
export GIT_TERMINAL_PROMPT=0

repositories_file="${RUNNER_TEMP:-/tmp}/actionfit-private-package-repositories.$$"
trap 'rm -f "$repositories_file"' EXIT
collect_actionfit_github_repositories > "$repositories_file"
repository_count="$(wc -l < "$repositories_file" | tr -d ' ')"

if ! ensure_github_credential; then
  if [ "$repository_count" -eq 0 ]; then
    echo "No gh auth or package read token found, and no ActionFit private GitHub package dependency was found."
    exit 0
  fi

  echo "::error::GitHub private package credential is not configured for $github_host."
  echo "::error::Run gh auth setup-git for the runner user, or put a read token at $token_file."
  exit 1
fi

if [ "$repository_count" -eq 0 ]; then
  echo "No ActionFit GitHub package dependency found in $manifest_path."
  exit 0
fi

while IFS= read -r repository; do
  [ -z "$repository" ] && continue
  echo "Checking private package access: $repository"
  if ! git ls-remote "$repository" HEAD >/dev/null; then
    echo "::error::Cannot access private package repository: $repository"
    exit 1
  fi
done < "$repositories_file"

echo "ActionFit private package access is ready."
