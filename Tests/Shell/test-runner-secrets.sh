#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
validator="$package_root/.github/scripts/validate-local-runner-secrets.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

home_root="$fixture_root/home"
secret_root="$home_root/ci-secrets/build-automation"
mkdir -p "$secret_root/shared" "$secret_root/profiles/actionfit/android"
keystore_path="$secret_root/profiles/actionfit/android/upload.keystore"
printf 'test-keystore\n' > "$keystore_path"

cat > "$secret_root/profiles/actionfit/profile.env" <<'EOF'
ANDROID_KEYSTORE_PATH="${CI_SECRET_ROOT}/profiles/actionfit/android/upload.keystore"
EOF
cat > "$secret_root/shared/android-signing.env" <<'EOF'
ANDROID_KEYSTORE_PASS="runner-keystore-pass"
ANDROID_KEYALIAS_PASS="runner-alias-pass"
EOF

request_path="$fixture_root/build_request.json"
cat > "$request_path" <<'EOF'
{
  "schemaVersion": 11,
  "androidKeystoreBase64": "cmVxdWVzdC1rZXlzdG9yZQ==",
  "androidKeystorePassword": "request-keystore-pass",
  "androidAliasPassword": "request-alias-pass"
}
EOF

github_env="$fixture_root/github-env"
github_output="$fixture_root/github-output"
: > "$github_env"
: > "$github_output"
validator_output="$(
  HOME="$home_root" \
  BUILD_REQUEST_PATH="$request_path" \
  GITHUB_ENV="$github_env" \
  GITHUB_OUTPUT="$github_output" \
  bash "$validator" Actionfit Android None
)"
if printf '%s' "$validator_output" | grep -E '(runner-|request-)' >/dev/null; then
  echo "Local validation must not print credential values" >&2
  exit 1
fi

if grep -E '(ANDROID_KEYSTORE_PATH|ANDROID_KEYSTORE_PASS|ANDROID_KEYALIAS_PASS|runner-|request-)' "$github_env" >/dev/null; then
  echo "Request signing values must take precedence without entering GITHUB_ENV" >&2
  exit 1
fi

rm -f "$keystore_path" "$secret_root/shared/android-signing.env"
HOME="$home_root" BUILD_REQUEST_PATH="$request_path" \
  bash "$validator" Actionfit Android None >/dev/null

printf 'test-keystore\n' > "$keystore_path"
cat > "$secret_root/shared/android-signing.env" <<'EOF'
ANDROID_KEYSTORE_PASS="runner-keystore-pass"
ANDROID_KEYALIAS_PASS="runner-alias-pass"
EOF
cat > "$request_path" <<'EOF'
{
  "schemaVersion": 11,
  "androidKeystoreBase64": "",
  "androidKeystorePassword": "",
  "androidAliasPassword": ""
}
EOF
: > "$github_env"
: > "$github_output"
fallback_output="$(
  HOME="$home_root" \
  BUILD_REQUEST_PATH="$request_path" \
  GITHUB_ENV="$github_env" \
  GITHUB_OUTPUT="$github_output" \
  bash "$validator" Actionfit Android None
)"
if printf '%s' "$fallback_output" | grep -F 'runner-' >/dev/null; then
  echo "Runner fallback validation must not print credential values" >&2
  exit 1
fi
grep -Fx "$keystore_path" "$github_env" >/dev/null
grep -Fx 'runner-keystore-pass' "$github_env" >/dev/null
grep -Fx 'runner-alias-pass' "$github_env" >/dev/null

rm -f "$keystore_path"
if HOME="$home_root" BUILD_REQUEST_PATH="$request_path" bash "$validator" Actionfit Android None >/dev/null 2>&1; then
  echo "Expected validation to fail when request and runner keystore values are both missing" >&2
  exit 1
fi

echo "BuildRequest signing and runner fallback tests passed"
