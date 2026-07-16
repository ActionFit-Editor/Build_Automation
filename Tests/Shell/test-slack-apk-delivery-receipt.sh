#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
receipt_manager="$package_root/.github/scripts/manage-slack-apk-delivery-receipt.rb"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

secret_root="$fixture_root/build-automation"
mkdir -m 700 "$secret_root"

export CI_SECRET_ROOT="$secret_root"
export GITHUB_REPOSITORY="ActionFitGames/Receipt-Fixture"
export GITHUB_RUN_ID="123456789"
export GITHUB_RUN_ATTEMPT="1"
export GITHUB_SHA="0123456789abcdef0123456789abcdef01234567"

run_expect_status() {
  local expected_status="$1"
  shift
  set +e
  "$@" > "$fixture_root/stdout" 2> "$fixture_root/stderr"
  local actual_status=$?
  set -e
  if [ "$actual_status" -ne "$expected_status" ]; then
    echo "Expected status $expected_status, got $actual_status: $*" >&2
    cat "$fixture_root/stdout" >&2
    cat "$fixture_root/stderr" >&2
    exit 1
  fi
}

run_expect_status 3 ruby "$receipt_manager" lookup
grep -F 'receipt is missing' "$fixture_root/stderr" >/dev/null

for index in 1 2 3 4 5 6; do
  ruby "$receipt_manager" begin > "$fixture_root/begin-$index.out" &
done
wait
for index in 1 2 3 4 5 6; do
  grep -Fx 'pending' "$fixture_root/begin-$index.out" >/dev/null
done
receipt_path="$(find "$secret_root/state/slack-apk-delivery" -type f -name '*.json' -print)"
if [ -z "$receipt_path" ]; then
  echo "begin must create a receipt" >&2
  exit 1
fi
if [ "$(find "$secret_root/state/slack-apk-delivery" -type f -name '*.json' | wc -l | tr -d '[:space:]')" -ne 1 ]; then
  echo "concurrent begin operations must share one receipt" >&2
  exit 1
fi

RECEIPT_PATH="$receipt_path" ruby -rjson -e '
  path = ENV.fetch("RECEIPT_PATH")
  receipt = JSON.parse(File.read(path))
  abort "wrong mode" unless File.stat(path).mode & 0777 == 0600
  abort "wrong directory mode" unless File.stat(File.dirname(path)).mode & 0777 == 0700
  abort "wrong state" unless receipt.fetch("state") == "pending"
  abort "wrong attempt" unless receipt.fetch("run_attempt") == 1
  abort "unexpected completion state" unless receipt.fetch("completion_attempted") == false
  forbidden = receipt.keys.grep(/token|upload_url|apk|file_path/i)
  abort "forbidden receipt fields: #{forbidden.join(",")}" unless forbidden.empty?
'

run_expect_status 4 ruby "$receipt_manager" lookup
grep -F 'pending before completion' "$fixture_root/stderr" >/dev/null
ruby "$receipt_manager" begin >/dev/null
ruby "$receipt_manager" discard > "$fixture_root/stdout"
grep -Fx 'discarded' "$fixture_root/stdout" >/dev/null
test ! -e "$receipt_path"

ruby "$receipt_manager" begin >/dev/null
ruby "$receipt_manager" arm FABC123 > "$fixture_root/stdout"
grep -Fx 'FABC123' "$fixture_root/stdout" >/dev/null

run_expect_status 4 ruby "$receipt_manager" lookup
grep -F 'file_id=FABC123' "$fixture_root/stderr" >/dev/null
run_expect_status 4 ruby "$receipt_manager" discard
test -f "$receipt_path"
run_expect_status 4 ruby "$receipt_manager" arm FABC123
run_expect_status 2 ruby "$receipt_manager" complete FDIFFERENT

ruby "$receipt_manager" complete FABC123 > "$fixture_root/stdout"
grep -Fx 'FABC123' "$fixture_root/stdout" >/dev/null
ruby "$receipt_manager" lookup > "$fixture_root/stdout"
grep -Fx 'FABC123' "$fixture_root/stdout" >/dev/null
ruby "$receipt_manager" complete FABC123 > "$fixture_root/stdout"
grep -Fx 'FABC123' "$fixture_root/stdout" >/dev/null
run_expect_status 5 ruby "$receipt_manager" discard

GITHUB_RUN_ATTEMPT=2 ruby "$receipt_manager" lookup > "$fixture_root/stdout"
grep -Fx 'FABC123' "$fixture_root/stdout" >/dev/null
run_expect_status 2 env GITHUB_SHA=ffffffffffffffffffffffffffffffffffffffff ruby "$receipt_manager" lookup

export GITHUB_RUN_ID="987654321"
ruby "$receipt_manager" begin >/dev/null
second_receipt="$(find "$secret_root/state/slack-apk-delivery" -type f -name '*.json' ! -path "$receipt_path" -print)"
GITHUB_RUN_ATTEMPT=2 run_expect_status 4 ruby "$receipt_manager" begin
GITHUB_RUN_ATTEMPT=2 ruby "$receipt_manager" discard >/dev/null
GITHUB_RUN_ATTEMPT=2 ruby "$receipt_manager" begin >/dev/null
RECEIPT_PATH="$second_receipt" ruby -rjson -e '
  receipt = JSON.parse(File.read(ENV.fetch("RECEIPT_PATH")))
  abort "new attempt was not recorded" unless receipt.fetch("run_attempt") == 2
'

chmod 644 "$second_receipt"
run_expect_status 2 env GITHUB_RUN_ATTEMPT=2 ruby "$receipt_manager" lookup
chmod 600 "$second_receipt"

RECEIPT_PATH="$second_receipt" ruby -rjson -e '
  path = ENV.fetch("RECEIPT_PATH")
  receipt = JSON.parse(File.read(path))
  receipt["upload_url"] = "https://example.invalid/secret"
  File.write(path, JSON.generate(receipt) + "\n")
  File.chmod(0600, path)
'
run_expect_status 2 env GITHUB_RUN_ATTEMPT=2 ruby "$receipt_manager" lookup

rm -f "$second_receipt"
ln -s "$fixture_root/nonexistent" "$second_receipt"
run_expect_status 2 env GITHUB_RUN_ATTEMPT=2 ruby "$receipt_manager" lookup

symlink_root="$fixture_root/symlink-root"
ln -s "$secret_root" "$symlink_root"
run_expect_status 2 env CI_SECRET_ROOT="$symlink_root" GITHUB_RUN_ID=111 ruby "$receipt_manager" begin

echo "Slack APK delivery receipt tests passed"
