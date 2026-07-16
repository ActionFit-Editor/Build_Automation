#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
slack_uploader="$package_root/.github/scripts/upload-slack-file.sh"
testflight_checker="$package_root/.github/scripts/check-testflight-build-number.rb"
slack_notifier="$package_root/.github/scripts/notify-slack-build-result.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

mkdir -p "$fixture_root/bin"
cat > "$fixture_root/bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "---" >> "$FAKE_CURL_LOG"
printf '%s\n' "$@" >> "$FAKE_CURL_LOG"
previous_argument=""
for argument in "$@"; do
  if [ "$previous_argument" = "--config" ] && [ "$argument" = "-" ]; then
    cat >> "${FAKE_CURL_CONFIG_LOG:-/dev/null}"
    break
  fi
  previous_argument="$argument"
done
last_argument="${!#}"
case "$last_argument" in
  */files.getUploadURLExternal)
    printf '{"ok":true,"upload_url":"http://127.0.0.1:12345/upload","file_id":"%s"}\n' "${FAKE_SLACK_FILE_ID:-F123}"
    ;;
  http://127.0.0.1:12345/upload)
    printf 'uploaded\n'
    ;;
  */files.completeUploadExternal)
    printf '{"ok":true}\n'
    ;;
  https://hooks.slack.com/services/*)
    ;;
  https://api.appstoreconnect.apple.com/v1/apps)
    case "${FAKE_ASC_MODE:-available}" in
      api_error)
        printf '{"errors":[{"status":"403","code":"FORBIDDEN","title":"Access denied","detail":"Fixture API denial"}]}\n'
        exit 22
        ;;
      app_missing)
        printf '{"data":[]}\n'
        ;;
      duplicate_apps)
        printf '{"data":[{"type":"apps","id":"APP_ONE","attributes":{"bundleId":"com.actionfit.fixture"}},{"type":"apps","id":"APP_TWO","attributes":{"bundleId":"com.actionfit.fixture"}}]}\n'
        ;;
      invalid_json)
        printf 'not-json\n'
        ;;
      invalid_collection)
        printf '[]\n'
        ;;
      *)
        printf '{"data":[{"type":"apps","id":"APP_FIXTURE","attributes":{"bundleId":"com.actionfit.fixture"}}]}\n'
        ;;
    esac
    ;;
  https://api.appstoreconnect.apple.com/v1/builds)
    case "${FAKE_ASC_MODE:-available}" in
      collision)
        printf '{"data":[{"type":"builds","id":"BUILD_FIXTURE","attributes":{"version":"1"}}]}\n'
        ;;
      *)
        printf '{"data":[]}\n'
        ;;
    esac
    ;;
  https://api.appstoreconnect.apple.com/v1/apps/APP_FIXTURE/buildUploads)
    case "${FAKE_ASC_MODE:-available}" in
      active_upload)
        printf '{"data":[{"type":"buildUploads","id":"UPLOAD_FIXTURE","attributes":{"state":{"state":"PROCESSING"}}}]}\n'
        ;;
      *)
        printf '{"data":[]}\n'
        ;;
    esac
    ;;
  *)
    exit 64
    ;;
esac
FAKE_CURL
chmod +x "$fixture_root/bin/curl"

apk_path="$fixture_root/development.apk"
printf 'development-apk\n' > "$apk_path"
slack_github_output="$fixture_root/slack-github-output"
slack_upload_phase="$fixture_root/slack-upload-phase"
: > "$slack_github_output"
: > "$slack_upload_phase"
slack_output="$(
  PATH="$fixture_root/bin:$PATH" \
  FAKE_CURL_LOG="$fixture_root/curl.log" \
  GITHUB_OUTPUT="$slack_github_output" \
  SLACK_UPLOAD_PHASE_PATH="$slack_upload_phase" \
  SLACK_BUILD_BOT_TOKEN="xoxb-fixture-token" \
  SLACK_BUILD_CHANNEL_ID="C12345678" \
  SLACK_FILE_PATH="$apk_path" \
  BUILD_PROJECT_NAME="FixtureProject" \
  BUILD_VERSION="5.5.5" \
  BUILD_BUNDLE_NO="555" \
  BUILD_SHORT_SHA="0123456789" \
  BUILD_RUN_URL="https://example.invalid/run" \
  SLACK_BUILD_MENTIONS="U12345678 <!channel> <@U99999999>" \
    bash "$slack_uploader"
)"
if printf '%s\n' "$slack_output" | grep -v '^::add-mask::' | grep -F 'xoxb-fixture-token' >/dev/null; then
  echo "Slack uploader must not print the bot token outside masking commands" >&2
  exit 1
fi
grep -F 'files.getUploadURLExternal' "$fixture_root/curl.log" >/dev/null
grep -F 'files.completeUploadExternal' "$fixture_root/curl.log" >/dev/null
grep -Fx 'slack_file_id=F123' "$slack_github_output" >/dev/null
grep -Fx 'completed' "$slack_upload_phase" >/dev/null
grep -F '[DEVELOPMENT BUILD] [OK] FixtureProject Android BuildCommit SUCCESS - v5.5.5(555)' "$fixture_root/curl.log" >/dev/null
grep -F '"channel_id":"C12345678"' "$fixture_root/curl.log" >/dev/null
grep -F '<@U12345678>' "$fixture_root/curl.log" >/dev/null
if grep -E '<!channel>|<@U99999999>' "$fixture_root/curl.log" >/dev/null; then
  echo "Slack uploader must discard values outside the raw member ID allowlist" >&2
  exit 1
fi

invalid_receipt_output="$fixture_root/invalid-receipt-output"
: > "$invalid_receipt_output"
set +e
PATH="$fixture_root/bin:$PATH" \
FAKE_CURL_LOG="$fixture_root/invalid-receipt-curl.log" \
FAKE_SLACK_FILE_ID='invalid/file-id' \
GITHUB_OUTPUT="$invalid_receipt_output" \
SLACK_BUILD_BOT_TOKEN="xoxb-fixture-token" \
SLACK_BUILD_CHANNEL_ID="C12345678" \
SLACK_FILE_PATH="$apk_path" \
  bash "$slack_uploader" >/dev/null
invalid_receipt_status=$?
set -e
if [ "$invalid_receipt_status" -ne 2 ]; then
  echo "Slack uploader must reject an invalid file ID receipt" >&2
  exit 1
fi
if [ -s "$invalid_receipt_output" ]; then
  echo "Slack uploader must not emit an invalid file ID receipt" >&2
  exit 1
fi

PATH="$fixture_root/bin:$PATH" \
FAKE_CURL_LOG="$fixture_root/hostile-upload.log" \
SLACK_BUILD_BOT_TOKEN="xoxb-fixture-token" \
SLACK_BUILD_CHANNEL_ID="C12345678" \
SLACK_FILE_PATH="$apk_path" \
BUILD_PROJECT_NAME="FixtureProject" \
BUILD_VERSION='5.5.5<!channel>&' \
BUILD_BUNDLE_NO='555<@U99999999>' \
  bash "$slack_uploader" >/dev/null
grep -F 'v5.5.5&lt;!channel&gt;&amp;(555&lt;@U99999999&gt;)' "$fixture_root/hostile-upload.log" >/dev/null
if grep -E '<!channel>|<@U99999999>' "$fixture_root/hostile-upload.log" >/dev/null; then
  echo "Slack uploader must escape markup in version metadata" >&2
  exit 1
fi

PATH="$fixture_root/bin:$PATH" \
FAKE_CURL_LOG="$fixture_root/curl.log" \
SLACK_BUILD_WEBHOOK_URL="https://hooks.slack.com/services/fixture" \
BUILD_JOB_STATUS=success \
BUILD_PLATFORM=iOS \
BUILD_PROJECT_NAME="FixtureProject" \
BUILD_VERSION="5.5.5" \
BUILD_BUNDLE_NO="1" \
BUILD_DEVELOPMENT_BUILD=true \
SLACK_BUILD_MENTIONS="W87654321 <!channel>" \
  bash "$slack_notifier" >/dev/null
grep -F '[DEVELOPMENT BUILD] [OK] FixtureProject iOS BuildCommit SUCCESS - v5.5.5(1)' "$fixture_root/curl.log" >/dev/null
grep -F '<@W87654321>' "$fixture_root/curl.log" >/dev/null
if grep -F '<!channel>' "$fixture_root/curl.log" >/dev/null; then
  echo "Slack notifier must discard values outside the raw member ID allowlist" >&2
  exit 1
fi

PATH="$fixture_root/bin:$PATH" \
FAKE_CURL_LOG="$fixture_root/apk-delivery-failure.log" \
SLACK_BUILD_WEBHOOK_URL="https://hooks.slack.com/services/fixture" \
BUILD_JOB_STATUS=apk_delivery_failure \
BUILD_PLATFORM=Android \
BUILD_PROJECT_NAME="FixtureProject" \
BUILD_VERSION="5.5.5" \
BUILD_BUNDLE_NO="555" \
BUILD_DEVELOPMENT_BUILD=true \
  bash "$slack_notifier" >/dev/null
grep -F '[DEVELOPMENT BUILD] [WARNING] FixtureProject Android BuildCommit BUILD SUCCESS / APK DELIVERY FAILED - v5.5.5(555)' "$fixture_root/apk-delivery-failure.log" >/dev/null


PATH="$fixture_root/bin:$PATH" \
FAKE_CURL_LOG="$fixture_root/hostile-notify.log" \
SLACK_BUILD_WEBHOOK_URL="https://hooks.slack.com/services/fixture" \
BUILD_JOB_STATUS=success \
BUILD_PLATFORM=Android \
BUILD_PROJECT_NAME="FixtureProject" \
BUILD_VERSION='5.5.5<!channel>&' \
BUILD_BUNDLE_NO='555<@U99999999>' \
  bash "$slack_notifier" >/dev/null
grep -F 'v5.5.5&lt;!channel&gt;&amp;(555&lt;@U99999999&gt;)' "$fixture_root/hostile-notify.log" >/dev/null
if grep -E '<!channel>|<@U99999999>' "$fixture_root/hostile-notify.log" >/dev/null; then
  echo "Slack notifier must escape markup in version metadata" >&2
  exit 1
fi

set +e
missing_config_output="$(
  HOME="$fixture_root/no-config-home" \
  SLACK_FILE_PATH="$apk_path" \
    bash "$slack_uploader" 2>&1
)"
missing_config_status=$?
set -e
if [ "$missing_config_status" -ne 2 ] || ! printf '%s\n' "$missing_config_output" | grep -F 'GitHub Artifact fallback' >/dev/null; then
  echo "Missing Slack Bot configuration must produce a nonfatal fallback signal" >&2
  exit 1
fi

/usr/bin/ruby -ropenssl -e '
  private_key = OpenSSL::PKey::EC.generate("prime256v1")
  File.write(ARGV.fetch(0), private_key.to_pem)
  File.chmod(0600, ARGV.fetch(0))
' "$fixture_root/app-store-key-sec1.pem"
/usr/bin/openssl pkcs8 -topk8 -nocrypt \
  -in "$fixture_root/app-store-key-sec1.pem" \
  -out "$fixture_root/app-store-key.p8"
/usr/bin/ruby -rjson -e '
  File.write(
    ARGV.fetch(0),
    JSON.generate(
      key_id: "KEY_FIXTURE",
      issuer_id: "ISSUER_FIXTURE",
      key: File.read(ARGV.fetch(1)),
      duration: 1200,
      in_house: false
    )
  )
  File.chmod(0600, ARGV.fetch(0))
' "$fixture_root/app-store-key.json" "$fixture_root/app-store-key.p8"

PATH="$fixture_root/bin:$PATH" \
FAKE_CURL_LOG="$fixture_root/asc-curl.log" \
FAKE_CURL_CONFIG_LOG="$fixture_root/asc-curl-config.log" \
APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/app-store-key.json" \
IOS_BUNDLE_ID="com.actionfit.fixture" \
TESTFLIGHT_BUILD_VERSION="5.5.5" \
TESTFLIGHT_BUILD_NUMBER="1" \
  /usr/bin/ruby "$testflight_checker" >/dev/null

grep -F 'https://api.appstoreconnect.apple.com/v1/apps' "$fixture_root/asc-curl.log" >/dev/null
grep -F 'filter[bundleId]=com.actionfit.fixture' "$fixture_root/asc-curl.log" >/dev/null
grep -F 'https://api.appstoreconnect.apple.com/v1/builds' "$fixture_root/asc-curl.log" >/dev/null
grep -F 'filter[app]=APP_FIXTURE' "$fixture_root/asc-curl.log" >/dev/null
grep -F 'filter[preReleaseVersion.version]=5.5.5' "$fixture_root/asc-curl.log" >/dev/null
grep -F 'filter[version]=1' "$fixture_root/asc-curl.log" >/dev/null
grep -F 'https://api.appstoreconnect.apple.com/v1/apps/APP_FIXTURE/buildUploads' "$fixture_root/asc-curl.log" >/dev/null
grep -F 'filter[cfBundleShortVersionString]=5.5.5' "$fixture_root/asc-curl.log" >/dev/null
grep -F 'filter[cfBundleVersion]=1' "$fixture_root/asc-curl.log" >/dev/null
grep -F 'filter[state]=AWAITING_UPLOAD,PROCESSING,COMPLETE' "$fixture_root/asc-curl.log" >/dev/null
if grep -F 'Authorization: Bearer' "$fixture_root/asc-curl.log" >/dev/null; then
  echo "App Store Connect JWT must not be passed in curl process arguments" >&2
  exit 1
fi

/usr/bin/ruby -rbase64 -rjson -ropenssl -e '
  def decode(value)
    Base64.urlsafe_decode64(value + ("=" * ((4 - value.length % 4) % 4)))
  end

  config = File.read(ARGV.fetch(0))
  token = config[/Authorization: Bearer ([A-Za-z0-9_.-]+)/, 1]
  abort("App Store Connect bearer token missing from curl config") if token.nil?
  parts = token.split(".")
  abort("JWT must have three parts") unless parts.length == 3
  header = JSON.parse(decode(parts[0]))
  claims = JSON.parse(decode(parts[1]))
  signature = decode(parts[2])
  abort("unexpected JWT header") unless header == {"alg" => "ES256", "kid" => "KEY_FIXTURE", "typ" => "JWT"}
  abort("unexpected JWT issuer") unless claims["iss"] == "ISSUER_FIXTURE"
  abort("unexpected JWT audience") unless claims["aud"] == "appstoreconnect-v1"
  abort("JWT lifetime is invalid") unless claims["exp"] - claims["iat"] == 600
  abort("ES256 signature must be 64-byte R||S") unless signature.bytesize == 64

  private_key = OpenSSL::PKey::EC.new(JSON.parse(File.read(ARGV.fetch(1))).fetch("key"))
  r = OpenSSL::BN.new(signature.byteslice(0, 32), 2)
  s = OpenSSL::BN.new(signature.byteslice(32, 32), 2)
  der = OpenSSL::ASN1::Sequence([
    OpenSSL::ASN1::Integer(r),
    OpenSSL::ASN1::Integer(s)
  ]).to_der
  signing_input = parts.first(2).join(".")
  digest = OpenSSL::Digest::SHA256.digest(signing_input)
  abort("ES256 JWT signature verification failed") unless private_key.dsa_verify_asn1(digest, der)
' "$fixture_root/asc-curl-config.log" "$fixture_root/app-store-key.json"

set +e
collision_output="$(
  PATH="$fixture_root/bin:$PATH" \
  FAKE_CURL_LOG="$fixture_root/asc-collision-curl.log" \
  FAKE_CURL_CONFIG_LOG="$fixture_root/asc-collision-config.log" \
  FAKE_ASC_MODE=collision \
  APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/app-store-key.json" \
  IOS_BUNDLE_ID="com.actionfit.fixture" \
  TESTFLIGHT_BUILD_VERSION="5.5.5" \
  TESTFLIGHT_BUILD_NUMBER="1" \
    /usr/bin/ruby "$testflight_checker" 2>&1
)"
collision_status=$?
set -e
if [ "$collision_status" -ne 3 ] || ! printf '%s\n' "$collision_output" | grep -F 'already contains build 5.5.5(1)' >/dev/null; then
  echo "TestFlight build-number collision must fail clearly" >&2
  exit 1
fi

set +e
active_upload_output="$(
  PATH="$fixture_root/bin:$PATH" \
  FAKE_CURL_LOG="$fixture_root/asc-active-curl.log" \
  FAKE_CURL_CONFIG_LOG="$fixture_root/asc-active-config.log" \
  FAKE_ASC_MODE=active_upload \
  APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/app-store-key.json" \
  IOS_BUNDLE_ID="com.actionfit.fixture" \
  TESTFLIGHT_BUILD_VERSION="5.5.5" \
  TESTFLIGHT_BUILD_NUMBER="1" \
    /usr/bin/ruby "$testflight_checker" 2>&1
)"
active_upload_status=$?
set -e
if [ "$active_upload_status" -ne 3 ] || ! printf '%s\n' "$active_upload_output" | grep -F 'active upload for build 5.5.5(1)' >/dev/null; then
  echo "Active TestFlight upload collision must fail clearly" >&2
  exit 1
fi

set +e
api_error_output="$(
  PATH="$fixture_root/bin:$PATH" \
  FAKE_CURL_LOG="$fixture_root/asc-error-curl.log" \
  FAKE_CURL_CONFIG_LOG="$fixture_root/asc-error-config.log" \
  FAKE_ASC_MODE=api_error \
  APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/app-store-key.json" \
  IOS_BUNDLE_ID="com.actionfit.fixture" \
  TESTFLIGHT_BUILD_VERSION="5.5.5" \
  TESTFLIGHT_BUILD_NUMBER="1" \
    /usr/bin/ruby "$testflight_checker" 2>&1
)"
api_error_status=$?
set -e
if [ "$api_error_status" -ne 1 ] || ! printf '%s\n' "$api_error_output" | grep -F 'FORBIDDEN - Access denied - Fixture API denial' >/dev/null; then
  echo "App Store Connect API failures must retain the actionable server error" >&2
  exit 1
fi

set +e
app_missing_output="$(
  PATH="$fixture_root/bin:$PATH" \
  FAKE_CURL_LOG="$fixture_root/asc-missing-curl.log" \
  FAKE_CURL_CONFIG_LOG="$fixture_root/asc-missing-config.log" \
  FAKE_ASC_MODE=app_missing \
  APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/app-store-key.json" \
  IOS_BUNDLE_ID="com.actionfit.fixture" \
  TESTFLIGHT_BUILD_VERSION="5.5.5" \
  TESTFLIGHT_BUILD_NUMBER="1" \
    /usr/bin/ruby "$testflight_checker" 2>&1
)"
app_missing_status=$?
set -e
if [ "$app_missing_status" -ne 1 ] || ! printf '%s\n' "$app_missing_output" | grep -F 'found 0' >/dev/null; then
  echo "Missing App Store Connect app must fail clearly" >&2
  exit 1
fi

set +e
duplicate_apps_output="$(
  PATH="$fixture_root/bin:$PATH" \
  FAKE_CURL_LOG="$fixture_root/asc-duplicate-apps-curl.log" \
  FAKE_CURL_CONFIG_LOG="$fixture_root/asc-duplicate-apps-config.log" \
  FAKE_ASC_MODE=duplicate_apps \
  APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/app-store-key.json" \
  IOS_BUNDLE_ID="com.actionfit.fixture" \
  TESTFLIGHT_BUILD_VERSION="5.5.5" \
  TESTFLIGHT_BUILD_NUMBER="1" \
    /usr/bin/ruby "$testflight_checker" 2>&1
)"
duplicate_apps_status=$?
set -e
if [ "$duplicate_apps_status" -ne 1 ] || ! printf '%s\n' "$duplicate_apps_output" | grep -F 'found 2' >/dev/null; then
  echo "Ambiguous App Store Connect app lookup must fail clearly" >&2
  exit 1
fi

set +e
invalid_json_output="$(
  PATH="$fixture_root/bin:$PATH" \
  FAKE_CURL_LOG="$fixture_root/asc-invalid-json-curl.log" \
  FAKE_CURL_CONFIG_LOG="$fixture_root/asc-invalid-json-config.log" \
  FAKE_ASC_MODE=invalid_json \
  APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/app-store-key.json" \
  IOS_BUNDLE_ID="com.actionfit.fixture" \
  TESTFLIGHT_BUILD_VERSION="5.5.5" \
  TESTFLIGHT_BUILD_NUMBER="1" \
    /usr/bin/ruby "$testflight_checker" 2>&1
)"
invalid_json_status=$?
set -e
if [ "$invalid_json_status" -ne 1 ] || ! printf '%s\n' "$invalid_json_output" | grep -F 'returned invalid JSON for /v1/apps' >/dev/null; then
  echo "Invalid App Store Connect JSON must fail clearly" >&2
  exit 1
fi

set +e
invalid_collection_output="$(
  PATH="$fixture_root/bin:$PATH" \
  FAKE_CURL_LOG="$fixture_root/asc-invalid-collection-curl.log" \
  FAKE_CURL_CONFIG_LOG="$fixture_root/asc-invalid-collection-config.log" \
  FAKE_ASC_MODE=invalid_collection \
  APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/app-store-key.json" \
  IOS_BUNDLE_ID="com.actionfit.fixture" \
  TESTFLIGHT_BUILD_VERSION="5.5.5" \
  TESTFLIGHT_BUILD_NUMBER="1" \
    /usr/bin/ruby "$testflight_checker" 2>&1
)"
invalid_collection_status=$?
set -e
if [ "$invalid_collection_status" -ne 1 ] || ! printf '%s\n' "$invalid_collection_output" | grep -F 'returned an invalid collection for /v1/apps' >/dev/null; then
  echo "Invalid App Store Connect collection must fail clearly" >&2
  exit 1
fi

secret_marker="PRIVATE_KEY_MATERIAL_MUST_NOT_APPEAR"
printf '{"key":"%s"' "$secret_marker" > "$fixture_root/malformed-app-store-key.json"
set +e
malformed_key_output="$(
  APP_STORE_CONNECT_API_KEY_JSON_PATH="$fixture_root/malformed-app-store-key.json" \
  IOS_BUNDLE_ID="com.actionfit.fixture" \
  TESTFLIGHT_BUILD_VERSION="5.5.5" \
  TESTFLIGHT_BUILD_NUMBER="1" \
    /usr/bin/ruby "$testflight_checker" 2>&1
)"
malformed_key_status=$?
set -e
if [ "$malformed_key_status" -ne 1 ] || ! printf '%s\n' "$malformed_key_output" | grep -F 'API key JSON could not be loaded' >/dev/null; then
  echo "Malformed App Store Connect API key JSON must fail clearly" >&2
  exit 1
fi
if printf '%s\n' "$malformed_key_output" | grep -F "$secret_marker" >/dev/null; then
  echo "Malformed App Store Connect API key JSON must not leak key material" >&2
  exit 1
fi

echo "Development distribution tests passed"
