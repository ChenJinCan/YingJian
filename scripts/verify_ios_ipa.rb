#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "tmpdir"
require "time"

def fail_verification(message)
  warn "iOS IPA verification failed: #{message}"
  exit 1
end

def capture!(*command)
  output, error, status = Open3.capture3(*command)
  fail_verification("#{File.basename(command.first)} failed: #{error.strip}") unless status.success?

  output
end

def parse_plist(path, label)
  JSON.parse(capture!("/usr/bin/plutil", "-convert", "json", "-o", "-", path))
rescue JSON::ParserError => error
  fail_verification("#{label} could not be decoded: #{error.message}")
end

def parse_plist_data(data, directory, label)
  path = File.join(directory, "#{label.gsub(/[^A-Za-z0-9]/, '_')}.plist")
  File.binwrite(path, data)
  parse_plist(path, label)
end

def extract_plist_value(path, key, format, label, optional: false)
  output, error, status = Open3.capture3(
    "/usr/bin/plutil", "-extract", key, format, "-o", "-", path
  )
  return nil if optional && !status.success?
  fail_verification("#{label} #{key} could not be extracted: #{error.strip}") unless status.success?

  return output.strip unless format == "json"

  JSON.parse(output)
rescue JSON::ParserError => error
  fail_verification("#{label} #{key} could not be decoded: #{error.message}")
end

def parse_provisioning_profile(data, directory, label)
  path = File.join(directory, "#{label.gsub(/[^A-Za-z0-9]/, '_')}.plist")
  File.binwrite(path, data)
  capture!("/usr/bin/plutil", "-lint", path)
  all_devices = extract_plist_value(
    path, "ProvisionsAllDevices", "raw", label, optional: true
  )
  profile = {
    "Entitlements" => extract_plist_value(path, "Entitlements", "json", label),
    "TeamIdentifier" => extract_plist_value(path, "TeamIdentifier", "json", label),
    "ExpirationDate" => extract_plist_value(path, "ExpirationDate", "raw", label),
  }
  provisioned_devices = extract_plist_value(
    path, "ProvisionedDevices", "json", label, optional: true
  )
  profile["ProvisionedDevices"] = provisioned_devices unless provisioned_devices.nil?
  profile["ProvisionsAllDevices"] = true if all_devices == "true"
  profile
end

def require_nonempty(value, label)
  fail_verification("#{label} is required") if value.to_s.strip.empty?

  value.to_s.strip
end

def version_parts(value, label)
  parts = value.to_s.split(".")
  fail_verification("#{label} must contain only numeric components") unless
    !parts.empty? && parts.all? { |part| part.match?(/\A\d+\z/) }

  parts.map(&:to_i)
end

def version_at_least?(actual, minimum)
  length = [actual.length, minimum.length].max
  actual = actual + Array.new(length - actual.length, 0)
  minimum = minimum + Array.new(length - minimum.length, 0)
  (actual <=> minimum) >= 0
end

def write_report(path, report)
  destination = Pathname.new(path).expand_path
  FileUtils.mkdir_p(destination.dirname)
  Tempfile.create([".#{destination.basename}", ".tmp"], destination.dirname.to_s) do |file|
    file.chmod(0o600)
    file.write(JSON.pretty_generate(report))
    file.write("\n")
    file.flush
    file.fsync
    File.rename(file.path, destination)
  end
end

options = {}
OptionParser.new do |parser|
  parser.banner = "usage: scripts/verify_ios_ipa.rb IPA --bundle-id ID --version VERSION --build BUILD --source-commit SHA --team-id ID --firebase-config PATH [options]"
  parser.on("--bundle-id ID") { |value| options[:bundle_id] = value }
  parser.on("--version VERSION") { |value| options[:version] = value }
  parser.on("--build BUILD") { |value| options[:build] = value }
  parser.on("--source-commit SHA") { |value| options[:source_commit] = value }
  parser.on("--team-id ID") { |value| options[:team_id] = value }
  parser.on("--firebase-config PATH") { |value| options[:firebase_config] = value }
  parser.on("--device-evidence-mode MODE", %w[profile release]) { |value| options[:device_evidence_mode] = value }
  parser.on("--expected-device-udid UDID") { |value| options[:expected_device_udid] = value }
  parser.on("--test-tool-directory DIRECTORY") { |value| options[:test_tool_directory] = value }
  parser.on("--expected-sha256 SHA256") { |value| options[:expected_sha256] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
end.parse!

ipa_argument = ARGV.shift
fail_verification("exactly one IPA path is required") unless ipa_argument && ARGV.empty?
ipa_path = Pathname.new(ipa_argument).expand_path
fail_verification("IPA does not exist: #{ipa_path}") unless ipa_path.file?

expected_bundle_id = require_nonempty(options[:bundle_id], "bundle-id")
expected_version = require_nonempty(options[:version], "version")
expected_build = require_nonempty(options[:build], "build")
source_commit = require_nonempty(options[:source_commit], "source-commit")
expected_team_id = require_nonempty(options[:team_id], "team-id")
expected_firebase_path = Pathname.new(require_nonempty(options[:firebase_config], "firebase-config")).expand_path
fail_verification("frozen Firebase config is missing") unless expected_firebase_path.file?
fail_verification("source-commit must be a full 40-character Git SHA") unless
  source_commit.match?(/\A[0-9a-f]{40}\z/)
fail_verification("build must be a positive integer") unless expected_build.match?(/\A[1-9]\d*\z/)
test_tool_directory = options[:test_tool_directory]
if test_tool_directory
  fail_verification("test tool overrides are disabled") unless ENV["YINGJIAN_ALLOW_TEST_TOOLS"] == "1"
  test_tool_directory = Pathname.new(test_tool_directory).expand_path
  fail_verification("test tool directory is invalid") unless test_tool_directory.directory?
end
security_tool = test_tool_directory ? test_tool_directory.join("security").to_s : "/usr/bin/security"
codesign_tool = test_tool_directory ? test_tool_directory.join("codesign").to_s : "/usr/bin/codesign"

sha256 = Digest::SHA256.file(ipa_path).hexdigest
expected_sha256 = options[:expected_sha256].to_s.strip.downcase
unless expected_sha256.empty?
  fail_verification("expected SHA-256 must contain 64 lowercase hexadecimal characters") unless
    expected_sha256.match?(/\A[0-9a-f]{64}\z/)
  fail_verification("IPA SHA-256 #{sha256} does not match expected SHA-256 #{expected_sha256}") unless
    sha256 == expected_sha256
end

raw_entries = capture!("/usr/bin/unzip", "-Z1", ipa_path.to_s)
entries = raw_entries.lines(chomp: true)
fail_verification("IPA is empty") if entries.empty?
fail_verification("IPA contains duplicate archive entries") unless entries.uniq.length == entries.length
entries.each do |entry|
  components = entry.split("/")
  if entry.empty? || entry.start_with?("/", "\\") || entry.include?("\\") ||
     components.include?("..") || entry.include?("\0")
    fail_verification("IPA contains an unsafe archive path")
  end
end

info_entries = entries.grep(%r{\APayload/[^/]+\.app/Info\.plist\z})
fail_verification("IPA must contain exactly one top-level iOS app") unless info_entries.length == 1
info_entry = info_entries.first
app_entry = info_entry.delete_suffix("/Info.plist")
unless entries.include?("#{app_entry}/embedded.mobileprovision")
  fail_verification("IPA is missing #{app_entry}/embedded.mobileprovision")
end
unless entries.include?("#{app_entry}/GoogleService-Info.plist")
  fail_verification("IPA is missing the configured Firebase plist")
end

Dir.mktmpdir("yingjian-ipa-verify-") do |directory|
  capture!("/usr/bin/unzip", "-qq", ipa_path.to_s, "-d", directory)
  app_path = File.join(directory, app_entry)
  info_path = File.join(directory, info_entry)
  fail_verification("extracted app is not a directory") unless File.directory?(app_path)
  fail_verification("extracted Info.plist is missing") unless File.file?(info_path)

  info = parse_plist(info_path, "Info.plist")

  bundle_id = info["CFBundleIdentifier"].to_s
  version = info["CFBundleShortVersionString"].to_s
  build = info["CFBundleVersion"].to_s
  fail_verification("bundle identifier #{bundle_id.inspect} does not match #{expected_bundle_id.inspect}") unless
    bundle_id == expected_bundle_id
  fail_verification("marketing version #{version.inspect} does not match #{expected_version.inspect}") unless
    version == expected_version
  fail_verification("build #{build.inspect} does not match #{expected_build.inspect}") unless build == expected_build
  executable = info["CFBundleExecutable"].to_s
  fail_verification("CFBundleExecutable must be nonempty") if executable.empty?
  fail_verification("IPA is missing the app executable") unless File.file?(File.join(app_path, executable))
  fail_verification("IPA is not an iphoneos device build") unless info["DTPlatformName"] == "iphoneos"
  supported_platforms = info["CFBundleSupportedPlatforms"]
  fail_verification("CFBundleSupportedPlatforms must include iPhoneOS") unless
    supported_platforms.is_a?(Array) && supported_platforms.include?("iPhoneOS")

  minimum_ios = info["MinimumOSVersion"].to_s
  minimum_parts = version_parts(minimum_ios, "MinimumOSVersion")
  fail_verification("MinimumOSVersion #{minimum_ios} is lower than the frozen iOS 15.0 baseline") unless
    version_at_least?(minimum_parts, [15, 0])
  families = info["UIDeviceFamily"]
  fail_verification("UIDeviceFamily must include iPhone") unless families.is_a?(Array) && families.include?(1)
  %w[NSPhotoLibraryUsageDescription NSPhotoLibraryAddUsageDescription].each do |key|
    fail_verification("Info.plist #{key} must be nonempty") if info[key].to_s.strip.empty?
  end
  required_resources = %w[
    Assets.car
    Frameworks/App.framework/App
    Frameworks/App.framework/flutter_assets/AssetManifest.bin
    Frameworks/App.framework/flutter_assets/NOTICES.Z
    Frameworks/App.framework/flutter_assets/assets/legal/privacy_en.md
    Frameworks/App.framework/flutter_assets/assets/legal/privacy_zh.md
    Frameworks/App.framework/flutter_assets/assets/legal/terms_en.md
    Frameworks/App.framework/flutter_assets/assets/legal/terms_zh.md
  ]
  required_resources.each do |relative|
    fail_verification("IPA is missing required resource #{relative}") unless File.file?(File.join(app_path, relative))
  end
  embedded_source_path = File.join(app_path, "Frameworks/App.framework/flutter_assets/assets/build/source-commit.txt")
  fail_verification("IPA is missing embedded source commit identity") unless File.file?(embedded_source_path)
  fail_verification("embedded source commit does not match the frozen source") unless
    File.read(embedded_source_path).strip == source_commit
  fail_verification("Release IPA contains debug kernel_blob.bin") if
    File.exist?(File.join(app_path, "Frameworks/App.framework/flutter_assets/kernel_blob.bin"))

  firebase = parse_plist(File.join(app_path, "GoogleService-Info.plist"), "GoogleService-Info.plist")
  expected_firebase = parse_plist(expected_firebase_path.to_s, "frozen Firebase config")
  fail_verification("Firebase BUNDLE_ID does not match the app") unless firebase["BUNDLE_ID"] == expected_bundle_id
  %w[BUNDLE_ID GOOGLE_APP_ID PROJECT_ID API_KEY GCM_SENDER_ID STORAGE_BUCKET].each do |key|
    fail_verification("Firebase #{key} must be nonempty") if firebase[key].to_s.strip.empty?
    fail_verification("Firebase #{key} does not match the frozen config") unless firebase[key] == expected_firebase[key]
  end

  profile_path = File.join(app_path, "embedded.mobileprovision")
  profile = parse_provisioning_profile(
    capture!(security_tool, "cms", "-D", "-i", profile_path),
    directory,
    "provisioning profile"
  )
  profile_entitlements = profile["Entitlements"]
  fail_verification("provisioning profile entitlements are missing") unless profile_entitlements.is_a?(Hash)
  fail_verification("provisioning profile team does not match") unless Array(profile["TeamIdentifier"]).include?(expected_team_id)
  fail_verification("provisioning application identifier does not match") unless
    profile_entitlements["application-identifier"] == "#{expected_team_id}.#{expected_bundle_id}"
  fail_verification("provisioning team entitlement does not match") unless
    profile_entitlements["com.apple.developer.team-identifier"] == expected_team_id
  device_evidence_mode = options[:device_evidence_mode]
  if device_evidence_mode == "profile"
    fail_verification("Profile device evidence must enable get-task-allow") unless profile_entitlements["get-task-allow"] == true
    provisioned_devices = profile["ProvisionedDevices"]
    fail_verification("Profile device evidence must use a device provisioning profile") unless
      provisioned_devices.is_a?(Array) && !provisioned_devices.empty?
    expected_udid = options[:expected_device_udid].to_s.strip
    fail_verification("Profile device evidence must bind the tested device UDID") if
      expected_udid.empty? || !provisioned_devices.include?(expected_udid)
  elsif device_evidence_mode == "release"
    fail_verification("Release device evidence must disable get-task-allow") unless profile_entitlements["get-task-allow"] == false
    distributable = (profile["ProvisionedDevices"].is_a?(Array) && !profile["ProvisionedDevices"].empty?) ||
      profile_entitlements["beta-reports-active"] == true
    fail_verification("Release device evidence profile is not installable or distributable") unless distributable
  else
    fail_verification("App Store profile must disable get-task-allow") unless profile_entitlements["get-task-allow"] == false
    fail_verification("App Store profile must enable beta reports") unless profile_entitlements["beta-reports-active"] == true
    fail_verification("development provisioning profile is not allowed") if profile.key?("ProvisionedDevices")
  end
  fail_verification("enterprise provisioning profile is not allowed") if profile["ProvisionsAllDevices"] == true
  expiration = profile["ExpirationDate"]
  expiration = Time.parse(expiration) if expiration.is_a?(String)
  fail_verification("provisioning profile expiration is invalid") unless expiration.respond_to?(:>)
  fail_verification("provisioning profile is expired") unless expiration > Time.now

  _output, error, status = Open3.capture3(
    codesign_tool,
    "--verify",
    "--deep",
    "--strict",
    app_path
  )
  fail_verification("codesign verification failed: #{error.strip}") unless status.success?
  signed_output, signed_error, signed_status = Open3.capture3(codesign_tool, "-d", "--entitlements", ":-", app_path)
  fail_verification("signed entitlements could not be read") unless signed_status.success?
  signed_data = signed_output.empty? ? signed_error : signed_output
  signed = parse_plist_data(signed_data, directory, "signed entitlements")
  fail_verification("signed application identifier does not match") unless
    signed["application-identifier"] == "#{expected_team_id}.#{expected_bundle_id}"
  fail_verification("signed team entitlement does not match") unless
    signed["com.apple.developer.team-identifier"] == expected_team_id
  if device_evidence_mode
    expected_get_task_allow = device_evidence_mode == "profile"
    fail_verification("signed app get-task-allow does not match the build mode") unless
      signed["get-task-allow"] == expected_get_task_allow
  else
    fail_verification("signed app must disable get-task-allow") unless signed["get-task-allow"] == false
  end

  report = {
    "schema_version" => 1,
    "platform" => "ios",
    "artifact_name" => ipa_path.basename.to_s,
    "bundle_id" => bundle_id,
    "version" => version,
    "build" => build,
    "minimum_ios" => minimum_ios,
    "source_commit" => source_commit,
    "sha256" => sha256,
    "signature_verified" => true,
    "team_id" => expected_team_id,
    "distribution_profile_verified" => device_evidence_mode != "profile",
    "development_profile_verified" => device_evidence_mode == "profile",
    "provisioning_profile_present" => true,
    "firebase_configuration_verified" => true,
    "device_evidence_eligible" => !device_evidence_mode.nil?,
    "build_mode" => device_evidence_mode,
    "embedded_source_commit_verified" => true,
    "verified_at" => Time.now.utc.iso8601
  }
  write_report(options[:output], report) if options[:output]
  puts "Verified iOS IPA #{bundle_id} #{version} (#{build}), SHA-256 #{sha256}."
end
