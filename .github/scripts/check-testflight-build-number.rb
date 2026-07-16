#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "open3"
require "openssl"
require "uri"

API_BASE_URL = "https://api.appstoreconnect.apple.com"

class AppStoreConnectLookupError < StandardError; end

def required_environment(name)
  value = ENV.fetch(name, "").strip
  raise AppStoreConnectLookupError, "#{name} is required" if value.empty?

  value
end

def required_json_string(payload, name)
  value = payload[name]
  unless value.is_a?(String) && !value.strip.empty?
    raise AppStoreConnectLookupError, "App Store Connect API key JSON is missing #{name}"
  end

  value
end

def base64url(value)
  Base64.urlsafe_encode64(value).delete("=")
end

def fixed_width_integer(integer, byte_length)
  hex = integer.to_s(16)
  expected_length = byte_length * 2
  raise AppStoreConnectLookupError, "App Store Connect JWT signature is invalid" if hex.length > expected_length

  [hex.rjust(expected_length, "0")].pack("H*")
end

def create_api_token(api_key_path)
  unless File.file?(api_key_path) && File.readable?(api_key_path)
    raise AppStoreConnectLookupError, "APP_STORE_CONNECT_API_KEY_JSON_PATH is not readable"
  end

  payload = JSON.parse(File.read(api_key_path))
  unless payload.is_a?(Hash)
    raise AppStoreConnectLookupError, "App Store Connect API key JSON must contain an object"
  end
  key_id = required_json_string(payload, "key_id").strip
  issuer_id = required_json_string(payload, "issuer_id").strip
  private_key = OpenSSL::PKey::EC.new(required_json_string(payload, "key"))
  now = Time.now.to_i
  header = base64url(JSON.generate(alg: "ES256", kid: key_id, typ: "JWT"))
  claims = base64url(
    JSON.generate(
      iss: issuer_id,
      iat: now - 5,
      exp: now + 595,
      aud: "appstoreconnect-v1"
    )
  )
  signing_input = "#{header}.#{claims}"
  digest = OpenSSL::Digest::SHA256.digest(signing_input)
  signature = OpenSSL::ASN1.decode(private_key.dsa_sign_asn1(digest)).value.map(&:value)
  unless signature.length == 2
    raise AppStoreConnectLookupError, "App Store Connect JWT signature is invalid"
  end

  raw_signature = fixed_width_integer(signature[0], 32) + fixed_width_integer(signature[1], 32)
  "#{signing_input}.#{base64url(raw_signature)}"
rescue JSON::ParserError, OpenSSL::OpenSSLError, SystemCallError
  raise AppStoreConnectLookupError, "App Store Connect API key JSON could not be loaded"
end

def api_error_summary(output, diagnostic)
  begin
    parsed = JSON.parse(output)
    errors = parsed.is_a?(Hash) ? parsed["errors"] : nil
    messages = errors.is_a?(Array) ? errors.first(3).map do |error|
      next unless error.is_a?(Hash)

      [error["code"], error["title"], error["detail"]]
        .select { |value| value.is_a?(String) && !value.strip.empty? }
        .join(" - ")
    end.compact : []
    return ": #{messages.join("; ")[0, 1000]}" unless messages.empty?
  rescue JSON::ParserError
    # Fall through to the bounded plain-text diagnostic.
  end

  sanitized = [output, diagnostic].join(" ").gsub(/[\r\n\t]+/, " ").strip
  sanitized.empty? ? "" : ": #{sanitized[0, 1000]}"
end

def request_collection(token, path, filters)
  command = [
    "curl",
    "--disable",
    "--config", "-",
    "--silent",
    "--show-error",
    "--fail-with-body",
    "--connect-timeout", "10",
    "--max-time", "60",
    "--retry", "2",
    "--retry-delay", "1",
    "--retry-connrefused",
    "--get"
  ]
  filters.each do |name, value|
    command.concat(["--data-urlencode", "#{name}=#{value}"])
  end
  command << "#{API_BASE_URL}#{path}"

  curl_config = <<~CONFIG
    header = "Authorization: Bearer #{token}"
    header = "Accept: application/json"
  CONFIG
  output, diagnostic, status = Open3.capture3(*command, stdin_data: curl_config)
  unless status.success?
    raise AppStoreConnectLookupError,
          "App Store Connect API request failed for #{path}#{api_error_summary(output, diagnostic)}"
  end

  response = JSON.parse(output)
  unless response.is_a?(Hash) && response["data"].is_a?(Array)
    raise AppStoreConnectLookupError, "App Store Connect API returned an invalid collection for #{path}"
  end

  response["data"]
rescue JSON::ParserError => error
  raise AppStoreConnectLookupError, "App Store Connect API returned invalid JSON for #{path}: #{error.message}"
rescue SystemCallError => error
  raise AppStoreConnectLookupError, "App Store Connect API request could not start for #{path}: #{error.message}"
end

begin
  api_key_path = required_environment("APP_STORE_CONNECT_API_KEY_JSON_PATH")
  bundle_id = required_environment("IOS_BUNDLE_ID")
  build_version = required_environment("TESTFLIGHT_BUILD_VERSION")
  build_number = required_environment("TESTFLIGHT_BUILD_NUMBER")
  token = create_api_token(api_key_path)

  apps = request_collection(
    token,
    "/v1/apps",
    {
      "filter[bundleId]" => bundle_id,
      "fields[apps]" => "bundleId",
      "limit" => "2"
    }
  )
  app = apps[0]
  app_attributes = app.is_a?(Hash) ? app["attributes"] : nil
  unless apps.length == 1 &&
         app.is_a?(Hash) &&
         app["type"] == "apps" &&
         app_attributes.is_a?(Hash) &&
         app_attributes["bundleId"] == bundle_id &&
         !app["id"].to_s.empty?
    raise AppStoreConnectLookupError,
          "Expected exactly one App Store Connect app for bundle ID #{bundle_id}; found #{apps.length}"
  end
  app_id = app["id"].to_s
  encoded_app_id = URI.encode_www_form_component(app_id)

  # Apple identifies a build by bundle ID, marketing version, and build string across platforms.
  builds = request_collection(
    token,
    "/v1/builds",
    {
      "filter[app]" => app_id,
      "filter[preReleaseVersion.version]" => build_version,
      "filter[version]" => build_number,
      "fields[builds]" => "version,processingState",
      "limit" => "1"
    }
  )

  if builds.any?
    warn("::error::TestFlight already contains build #{build_version}(#{build_number}). Development Build uses fixed build number 1 once; change the marketing version before retrying.")
    exit(3)
  end

  active_uploads = request_collection(
    token,
    "/v1/apps/#{encoded_app_id}/buildUploads",
    {
      "filter[cfBundleShortVersionString]" => build_version,
      "filter[cfBundleVersion]" => build_number,
      "filter[state]" => "AWAITING_UPLOAD,PROCESSING,COMPLETE",
      "fields[buildUploads]" => "cfBundleShortVersionString,cfBundleVersion,state,platform,uploadedDate",
      "limit" => "1"
    }
  )
  if active_uploads.any?
    warn("::error::TestFlight already contains an active upload for build #{build_version}(#{build_number}). Development Build uses fixed build number 1 once; change the marketing version before retrying.")
    exit(3)
  end

  puts("TestFlight build number is available: #{build_version}(#{build_number})")
rescue AppStoreConnectLookupError => error
  warn("::error::Could not verify whether TestFlight build #{ENV.fetch("TESTFLIGHT_BUILD_VERSION", "").strip}(#{ENV.fetch("TESTFLIGHT_BUILD_NUMBER", "").strip}) already exists: #{error.message}")
  exit(1)
end
