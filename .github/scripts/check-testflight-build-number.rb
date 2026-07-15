#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

fastlane = ENV.fetch("FASTLANE_CMD", "").strip
api_key_path = ENV.fetch("APP_STORE_CONNECT_API_KEY_JSON_PATH", "").strip
bundle_id = ENV.fetch("IOS_BUNDLE_ID", "").strip
build_version = ENV.fetch("TESTFLIGHT_BUILD_VERSION", "").strip
build_number = ENV.fetch("TESTFLIGHT_BUILD_NUMBER", "").strip

abort("FASTLANE_CMD is required") if fastlane.empty?
abort("APP_STORE_CONNECT_API_KEY_JSON_PATH is required") unless File.file?(api_key_path)
abort("IOS_BUNDLE_ID is required") if bundle_id.empty?
abort("TESTFLIGHT_BUILD_VERSION is required") if build_version.empty?
abort("TESTFLIGHT_BUILD_NUMBER is required") if build_number.empty?

environment = {
  "FASTLANE_DISABLE_COLORS" => "1",
  "FASTLANE_SKIP_UPDATE_CHECK" => "1"
}
command = [
  fastlane,
  "pilot",
  "builds",
  "--api_key_path", api_key_path,
  "--app_identifier", bundle_id,
  "--app_platform", "ios"
]
output, status = Open3.capture2e(environment, *command)
unless status.success?
  warn("::error::Could not verify whether TestFlight build #{build_version}(#{build_number}) already exists.")
  exit(status.exitstatus || 1)
end

plain_output = output.gsub(/\e\[[0-9;]*m/, "")
collision = plain_output.each_line.any? do |line|
  columns = line.split("|").map(&:strip).reject(&:empty?)
  columns.each_cons(2).any? { |version, number| version == build_version && number == build_number }
end

if collision
  warn("::error::TestFlight already contains build #{build_version}(#{build_number}). Development Build uses fixed build number 1 once; change the marketing version or remove the conflicting build before retrying.")
  exit 3
end

puts("TestFlight build number is available: #{build_version}(#{build_number})")
