#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
VERIFIER = File.join(ROOT, "scripts", "verify_ios_ipa.rb")
SHA = "0123456789abcdef0123456789abcdef01234567"
TEAM = "V86Q54AQQU"
BUNDLE = "com.babycompany.yingjian"
DEVICE_UDID = "00008110-001075E03CE1401E"

def assert(condition, message)
  raise message unless condition
end
def plist(dict)
  body = dict.map do |key, value|
    encoded = case value
              when String then "<string>#{value}</string>"
              when Array then "<array>#{value.map { |v| "<string>#{v}</string>" }.join}</array>"
              when true then "<true/>"
              when false then "<false/>"
              when Hash then "<dict>#{value.map { |k, v| "<key>#{k}</key>#{v == true ? '<true/>' : v == false ? '<false/>' : "<string>#{v}</string>"}" }.join}</dict>"
              else raise "unsupported fixture value"
              end
    "<key>#{key}</key>#{encoded}"
  end.join
  %(<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>#{body}</dict></plist>)
end

def run_verifier(environment, ipa, firebase_config, bundle: BUNDLE)
  Open3.capture3(environment, "ruby", VERIFIER, ipa, "--bundle-id", bundle,
                 "--version", "1.2.4", "--build", "112", "--team-id", TEAM,
                 "--firebase-config", firebase_config,
                 "--source-commit", SHA,
                 "--test-tool-directory", environment.fetch("YINGJIAN_TEST_TOOL_DIRECTORY"))
end

Dir.mktmpdir("yingjian-ipa-verifier-") do |directory|
  app = File.join(directory, "Payload", "Runner.app")
  assets = File.join(app, "Frameworks", "App.framework", "flutter_assets")
  FileUtils.mkdir_p(assets)
  File.write(File.join(app, "Info.plist"), plist(
    "CFBundleIdentifier" => BUNDLE, "CFBundleShortVersionString" => "1.2.4",
    "CFBundleVersion" => "112", "CFBundleExecutable" => "Runner",
    "DTPlatformName" => "iphoneos", "CFBundleSupportedPlatforms" => ["iPhoneOS"],
    "MinimumOSVersion" => "15.0", "UIDeviceFamily" => ["1", "2"],
    "NSPhotoLibraryUsageDescription" => "选择照片", "NSPhotoLibraryAddUsageDescription" => "保存照片"
  ).sub("<string>1</string><string>2</string>", "<integer>1</integer><integer>2</integer>"))
  File.write(File.join(app, "GoogleService-Info.plist"), plist(
    "BUNDLE_ID" => BUNDLE, "GOOGLE_APP_ID" => "1:fixture:ios:fixture",
    "PROJECT_ID" => "yingjian-fixture", "API_KEY" => "fixture-key",
    "GCM_SENDER_ID" => "123456789", "STORAGE_BUCKET" => "yingjian-fixture.appspot.com"
  ))
  %w[Runner Assets.car Frameworks/App.framework/App Frameworks/App.framework/flutter_assets/AssetManifest.bin Frameworks/App.framework/flutter_assets/NOTICES.Z Frameworks/App.framework/flutter_assets/assets/legal/privacy_en.md Frameworks/App.framework/flutter_assets/assets/legal/privacy_zh.md Frameworks/App.framework/flutter_assets/assets/legal/terms_en.md Frameworks/App.framework/flutter_assets/assets/legal/terms_zh.md Frameworks/App.framework/flutter_assets/assets/build/source-commit.txt].each do |relative|
    path = File.join(app, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "fixture")
  end
  File.write(File.join(app, "Frameworks/App.framework/flutter_assets/assets/build/source-commit.txt"), "#{SHA}\n")
  File.write(File.join(app, "embedded.mobileprovision"), "fixture")

  bin = File.join(directory, "bin")
  FileUtils.mkdir_p(bin)
  entitlements = plist(
    "application-identifier" => "#{TEAM}.#{BUNDLE}",
    "com.apple.developer.team-identifier" => TEAM, "get-task-allow" => false
  )
  profile = plist(
    "TeamIdentifier" => [TEAM], "ExpirationDate" => "2099-01-01T00:00:00Z",
    "Entitlements" => {
      "application-identifier" => "#{TEAM}.#{BUNDLE}",
      "com.apple.developer.team-identifier" => TEAM,
      "get-task-allow" => false, "beta-reports-active" => true
    }
  )
  profile = profile.sub(
    "</dict></plist>",
    "<key>CreationDate</key><date>2026-08-06T00:00:00Z</date>" \
      "<key>DeveloperCertificates</key><array><data>AQID</data></array>" \
      "</dict></plist>"
  )
  File.write(File.join(bin, "security"), "#!/bin/sh\ncat '#{File.join(directory, 'profile.plist')}'\n")
  File.write(File.join(directory, "profile.plist"), profile)
  File.write(File.join(bin, "codesign"), "#!/bin/sh\nif [ \"$1\" = \"-d\" ]; then cat '#{File.join(directory, 'entitlements.plist')}'; fi\nexit 0\n")
  File.write(File.join(directory, "entitlements.plist"), entitlements)
  FileUtils.chmod(0o755, [File.join(bin, "security"), File.join(bin, "codesign")])
  environment = {
    "YINGJIAN_ALLOW_TEST_TOOLS" => "1",
    "YINGJIAN_TEST_TOOL_DIRECTORY" => bin,
  }
  firebase_config = File.join(directory, "frozen-firebase.plist")
  FileUtils.cp(File.join(app, "GoogleService-Info.plist"), firebase_config)

  ipa = File.join(directory, "Yingjian.ipa")
  _out, err, status = Open3.capture3("zip", "-qry", ipa, "Payload", chdir: directory)
  assert(status.success?, "fixture IPA creation failed: #{err}")
  report = File.join(directory, "artifact.json")
  sha = Digest::SHA256.file(ipa).hexdigest
  out, err, status = Open3.capture3(environment, "ruby", VERIFIER, ipa,
                                    "--bundle-id", BUNDLE, "--version", "1.2.4", "--build", "112",
                                    "--team-id", TEAM, "--source-commit", SHA,
                                    "--firebase-config", firebase_config,
                                    "--expected-sha256", sha, "--output", report,
                                    "--test-tool-directory", bin)
  assert(status.success?, "valid IPA rejected: #{out}#{err}")
  data = JSON.parse(File.read(report))
  assert(data["distribution_profile_verified"] == true, "distribution profile not recorded")
  assert(data["firebase_configuration_verified"] == true, "Firebase verification not recorded")

  profile_mode_profile = profile
    .sub("<key>get-task-allow</key><false/>", "<key>get-task-allow</key><true/>")
    .sub(
      "<key>CreationDate</key>",
      "<key>ProvisionedDevices</key><array><string>#{DEVICE_UDID}</string></array>" \
        "<key>CreationDate</key>"
    )
  profile_mode_entitlements = entitlements.sub(
    "<key>get-task-allow</key><false/>",
    "<key>get-task-allow</key><true/>"
  )
  File.write(File.join(directory, "profile.plist"), profile_mode_profile)
  File.write(File.join(directory, "entitlements.plist"), profile_mode_entitlements)
  profile_report = File.join(directory, "profile-artifact.json")
  out, err, status = Open3.capture3(
    environment,
    "ruby", VERIFIER, ipa, "--bundle-id", BUNDLE, "--version", "1.2.4",
    "--build", "112", "--team-id", TEAM, "--source-commit", SHA,
    "--firebase-config", firebase_config, "--output", profile_report,
    "--device-evidence-mode", "profile", "--expected-device-udid", DEVICE_UDID,
    "--test-tool-directory", bin
  )
  assert(status.success?, "valid Profile IPA rejected: #{out}#{err}")
  profile_data = JSON.parse(File.read(profile_report))
  assert(profile_data["development_profile_verified"] == true,
         "development profile verification not recorded")
  assert(profile_data["distribution_profile_verified"] == false,
         "Profile evidence was mislabeled as distribution-signed")
  File.write(File.join(directory, "profile.plist"), profile)
  File.write(File.join(directory, "entitlements.plist"), entitlements)

  _out, err, status = Open3.capture3(
    "ruby", VERIFIER, ipa, "--bundle-id", BUNDLE, "--version", "1.2.4",
    "--build", "112", "--team-id", TEAM, "--source-commit", SHA,
    "--firebase-config", firebase_config, "--test-tool-directory", bin
  )
  assert(!status.success? && err.include?("test tool overrides are disabled"),
         "production verification accepted injected signing tools")

  _out, err, status = run_verifier(environment, ipa, firebase_config, bundle: "com.example.wrong")
  assert(!status.success? && err.include?("bundle identifier"), "wrong bundle accepted")
  File.write(File.join(directory, "profile.plist"), profile.sub(TEAM, "WRONGTEAM1"))
  _out, err, status = run_verifier(environment, ipa, firebase_config)
  assert(!status.success? && err.include?("profile team"), "wrong profile team accepted")
  File.write(File.join(directory, "profile.plist"), profile)
  File.write(File.join(directory, "entitlements.plist"), entitlements.sub("<false/>", "<true/>"))
  _out, err, status = run_verifier(environment, ipa, firebase_config)
  assert(!status.success? && err.include?("disable get-task-allow"), "debug entitlement accepted")

  File.write(firebase_config, File.read(firebase_config).sub("yingjian-fixture", "wrong-project"))
  File.write(File.join(directory, "entitlements.plist"), entitlements)
  _out, err, status = run_verifier(environment, ipa, firebase_config)
  assert(!status.success? && err.include?("PROJECT_ID does not match"), "wrong Firebase project accepted")

  FileUtils.cp(File.join(app, "GoogleService-Info.plist"), firebase_config)
  source_identity = File.join(app, "Frameworks/App.framework/flutter_assets/assets/build/source-commit.txt")
  File.write(source_identity, "#{'b' * 40}\n")
  wrong_source_ipa = File.join(directory, "WrongSource.ipa")
  _out, err, status = Open3.capture3("zip", "-qry", wrong_source_ipa, "Payload", chdir: directory)
  assert(status.success?, "wrong-source fixture creation failed: #{err}")
  _out, err, status = run_verifier(environment, wrong_source_ipa, firebase_config)
  assert(!status.success? && err.include?("embedded source commit"),
         "IPA was accepted for a source commit it did not embed")
  File.write(source_identity, "#{SHA}\n")

  FileUtils.rm(File.join(app, "Frameworks/App.framework/flutter_assets/assets/legal/privacy_en.md"))
  missing_legal_ipa = File.join(directory, "MissingLegal.ipa")
  _out, err, status = Open3.capture3("zip", "-qry", missing_legal_ipa, "Payload", chdir: directory)
  assert(status.success?, "missing-legal fixture creation failed: #{err}")
  _out, err, status = run_verifier(environment, missing_legal_ipa, firebase_config)
  assert(!status.success? && err.include?("assets/legal/privacy_en.md"), "IPA without legal assets accepted")
end

puts "iOS IPA verifier tests passed."
