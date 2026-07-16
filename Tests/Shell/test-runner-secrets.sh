#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
validator="$package_root/.github/scripts/validate-local-runner-secrets.sh"
resolver="$package_root/.github/scripts/resolve-local-secret-root.sh"
setup_script="$package_root/RunnerSetup/setup-local-runner-secrets.sh"
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
  "schemaVersion": 12,
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
  GITHUB_ACTIONS=false \
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

github_actions_output="$(
  HOME="$home_root" \
  BUILD_REQUEST_PATH="$request_path" \
  GITHUB_ACTIONS=true \
  GITHUB_ENV="$github_env" \
  GITHUB_OUTPUT="$github_output" \
  bash "$validator" Actionfit Android None
)"
mask_count="$(printf '%s\n' "$github_actions_output" | grep -c '^::add-mask::' || true)"
if [ "$mask_count" -ne 4 ]; then
  echo "GitHub Actions validation must emit exactly four fixture credential masks" >&2
  exit 1
fi
for credential in \
  runner-keystore-pass \
  runner-alias-pass \
  request-keystore-pass \
  request-alias-pass; do
  if ! printf '%s\n' "$github_actions_output" | grep -Fx "::add-mask::$credential" >/dev/null; then
    echo "GitHub Actions validation is missing an expected fixture credential mask" >&2
    exit 1
  fi
done
if printf '%s\n' "$github_actions_output" \
  | grep -v '^::add-mask::' \
  | grep -E '(runner-|request-)' >/dev/null; then
  echo "GitHub Actions validation must not print fixture credentials outside add-mask commands" >&2
  exit 1
fi

rm -f "$keystore_path" "$secret_root/shared/android-signing.env"
HOME="$home_root" BUILD_REQUEST_PATH="$request_path" GITHUB_ACTIONS=false \
  bash "$validator" Actionfit Android None >/dev/null

printf 'test-keystore\n' > "$keystore_path"
cat > "$secret_root/shared/android-signing.env" <<'EOF'
ANDROID_KEYSTORE_PASS="runner-keystore-pass"
ANDROID_KEYALIAS_PASS="runner-alias-pass"
EOF
cat > "$request_path" <<'EOF'
{
  "schemaVersion": 12,
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
  GITHUB_ACTIONS=false \
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

cat > "$request_path" <<'EOF'
{
  "schemaVersion": 12,
  "developmentBuild": true,
  "androidKeystoreBase64": "",
  "androidKeystorePassword": "",
  "androidAliasPassword": ""
}
EOF
: > "$github_env"
: > "$github_output"
development_validation_output="$(
  HOME="$home_root" \
  BUILD_REQUEST_PATH="$request_path" \
  GITHUB_ACTIONS=true \
  GITHUB_ENV="$github_env" \
  GITHUB_OUTPUT="$github_output" \
    bash "$validator" Actionfit Android None
)"
if printf '%s\n' "$development_validation_output" | grep -Ei 'slack|webhook' >/dev/null; then
  echo "Development Android validation must not inspect Slack configuration" >&2
  exit 1
fi
if grep -Ei 'slack|webhook' "$github_env" "$github_output" >/dev/null; then
  echo "Development Android validation must not export Slack configuration" >&2
  exit 1
fi
if grep -Eiq 'slack|webhook' "$validator"; then
  echo "Runner secret validation must not contain Slack credential access" >&2
  exit 1
fi

rm -f "$keystore_path"
if HOME="$home_root" BUILD_REQUEST_PATH="$request_path" GITHUB_ACTIONS=false \
  bash "$validator" Actionfit Android None >/dev/null 2>&1; then
  echo "Expected validation to fail when request and runner keystore values are both missing" >&2
  exit 1
fi

resolver_home="$fixture_root/resolver-home"
resolver_root="$resolver_home/workspace/build-automation"
mkdir -p "$resolver_root/shared"
resolver_root_physical="$(cd "$resolver_root" && pwd -P)"
resolver_env="$fixture_root/resolver-env"
resolver_output="$fixture_root/resolver-output"
: > "$resolver_env"
: > "$resolver_output"
HOME="$resolver_home" GITHUB_ENV="$resolver_env" GITHUB_OUTPUT="$resolver_output" \
  bash "$resolver" >/dev/null
grep -Fx "$resolver_root_physical" "$resolver_env" >/dev/null
grep -Fx "path=$resolver_root_physical" "$resolver_output" >/dev/null

if CI_SECRET_ROOT="$fixture_root/missing-root" HOME="$resolver_home" \
  bash "$resolver" >/dev/null 2>&1; then
  echo "An invalid explicit CI_SECRET_ROOT must not silently fall back" >&2
  exit 1
fi

generated_root="$fixture_root/generated-build-automation"
bash "$setup_script" "$generated_root" >/dev/null
for slack_file in slack-webhook-url slack-bot-token slack-channel-id; do
  path="$generated_root/shared/$slack_file"
  test -f "$path"
  test "$(stat -f '%Lp' "$path")" = 600
done
test "$(stat -f '%Lp' "$generated_root/shared")" = 700
test -d "$generated_root/state/slack-apk-delivery"
test "$(stat -f '%Lp' "$generated_root/state")" = 700
test "$(stat -f '%Lp' "$generated_root/state/slack-apk-delivery")" = 700

echo "BuildRequest signing and runner fallback tests passed"
