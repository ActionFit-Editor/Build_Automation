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
  "schemaVersion": 10,
  "androidKeystoreBase64": "bGVnYWN5LXNlY3JldA==",
  "androidKeystorePassword": "legacy-keystore-pass",
  "androidAliasPassword": "legacy-alias-pass"
}
EOF

github_env="$fixture_root/github-env"
github_output="$fixture_root/github-output"
: > "$github_env"
: > "$github_output"
HOME="$home_root" \
BUILD_REQUEST_PATH="$request_path" \
GITHUB_ENV="$github_env" \
GITHUB_OUTPUT="$github_output" \
bash "$validator" Actionfit Android None >/dev/null

grep -F "ANDROID_KEYSTORE_PATH<<__ACTIONFIT_EOF__" "$github_env" >/dev/null
grep -Fx "$keystore_path" "$github_env" >/dev/null
grep -Fx 'runner-keystore-pass' "$github_env" >/dev/null
grep -Fx 'runner-alias-pass' "$github_env" >/dev/null
if grep -F 'legacy-' "$github_env" >/dev/null; then
  echo "Legacy request credentials must not enter GITHUB_ENV" >&2
  exit 1
fi

rm -f "$keystore_path"
if HOME="$home_root" BUILD_REQUEST_PATH="$request_path" \
  bash "$validator" Actionfit Android None >/dev/null 2>&1; then
  echo "Expected missing runner-local keystore to fail even with legacy request data" >&2
  exit 1
fi

echo "Runner secret tests passed"
