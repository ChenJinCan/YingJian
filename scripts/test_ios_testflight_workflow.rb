#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"

ROOT = File.expand_path("..", __dir__)
BUILD_SCRIPT = File.join(ROOT, "scripts", "build_ios_testflight.sh")
UPLOAD_SCRIPT = File.join(ROOT, "scripts", "upload_ios_testflight.sh")
PREFLIGHT_SCRIPT = File.join(ROOT, "scripts", "release_contract_preflight.sh")
FASTFILE = File.join(ROOT, "fastlane", "Fastfile")
RELEASE_POLICY = File.join(ROOT, "release", "release-policy.yaml")

def assert(condition, message)
  raise message unless condition
end

def run(*command)
  Open3.capture3(*command)
end

stdout, stderr, status = run(BUILD_SCRIPT, "--dry-run", "1.2.4", "112")
assert(status.success?, "build dry-run failed: #{stdout}#{stderr}")
assert(stdout.include?("LOCAL-ONLY"), "build plan did not label its side effects")
assert(stdout.include?("release_contract_preflight.sh ios 1.2.4 112 build"),
       "build plan omitted the release contract preflight")
assert(stdout.include?("flutter build ipa --release --build-name 1.2.4 --build-number 112"),
       "build plan omitted the exact Flutter candidate identity")
assert(stdout.include?("verify_ios_ipa.rb"), "build plan omitted final IPA verification")
assert(stdout.include?("Android discovery is disabled"), "build plan omitted the iOS-only Flutter boundary")
assert(stdout.include?("Swift Package Manager migration is disabled"),
       "build plan omitted the existing CocoaPods project boundary")
assert(!stdout.include?("upload-package"), "local build plan unexpectedly uploads to Apple")

build_source = File.read(BUILD_SCRIPT)
assert(build_source.include?("--no-enable-swift-package-manager"),
       "build wrapper may mutate the CocoaPods project into a partial SPM migration")

_stdout, stderr, status = run(BUILD_SCRIPT, "--dry-run", "1.2", "112")
assert(!status.success? && stderr.include?("x.y.z"), "build wrapper accepted an invalid version")
_stdout, stderr, status = run(BUILD_SCRIPT, "--dry-run", "1.2.04", "112")
assert(!status.success? && stderr.include?("leading zeroes"),
       "build wrapper accepted a non-canonical version")
_stdout, stderr, status = run(BUILD_SCRIPT, "--dry-run", "1.2.4", "0")
assert(!status.success? && stderr.include?("positive integer"), "build wrapper accepted an invalid build")

stdout, stderr, status = run(
  UPLOAD_SCRIPT,
  "--dry-run",
  "/tmp/Yingjian.ipa",
  "/tmp/Yingjian-artifact.json",
  "1.2.4",
  "112"
)
assert(status.exitstatus == 78, "legacy upload did not fail closed: #{stdout}#{stderr}")
assert(stderr.include?("TESTFLIGHT-UPLOAD BLOCKED"),
       "legacy upload did not explain that it is disabled")
assert(stderr.include?("Fastlane/Spaceship"),
       "legacy upload did not name the required replacement path")

upload_source = File.read(UPLOAD_SCRIPT)
assert(!upload_source.match?(/^\s*xcrun\s+altool\b/),
       "legacy wrapper still contains an executable altool path")
assert(!upload_source.include?("--upload-package"),
       "legacy wrapper still contains an upload command")
assert(!upload_source.include?("--wait"),
       "legacy wrapper still contains a processing wait")

assert(File.file?(FASTFILE), "repository-owned Fastlane lane is missing")
release_policy = YAML.safe_load(File.read(RELEASE_POLICY))
ios_policy = release_policy.fetch("platforms").fetch("ios")
assert(ios_policy.fetch("release_ready") == true,
       "iOS release policy unexpectedly blocks the verified TestFlight lane")
assert(ios_policy.fetch("upload_adapter") == "fastlane_spaceship",
       "iOS release policy does not require the verified Fastlane/Spaceship adapter")
assert(ios_policy.fetch("upload_lane") == "ios beta",
       "iOS release policy does not select the verified beta lane")

fastfile_source = File.read(FASTFILE)
assert(fastfile_source.include?("platform :ios"), "Fastfile does not define the iOS platform")
assert(fastfile_source.include?("lane :beta"), "Fastfile does not define the beta lane")
assert(fastfile_source.scan("build_ios_testflight.sh").length == 1,
       "Fastlane lane must invoke the guarded build wrapper exactly once")
assert(fastfile_source.scan(/\bupload_to_testflight\s*\(/).length == 1,
       "Fastlane lane must contain exactly one TestFlight upload action")
assert(fastfile_source.include?('source_commit == frozen_source_commit'),
       "Fastlane lane does not bind its source option to RELEASE_SOURCE_COMMIT")
assert(fastfile_source.include?('release_contract_preflight.sh'),
       "Fastlane lane does not rerun the release preflight")
assert(fastfile_source.include?('"upload"'),
       "Fastlane lane does not use the upload-stage preflight")
assert(fastfile_source.include?('verify_ios_ipa.rb'),
       "Fastlane lane does not re-verify the final IPA")
assert(fastfile_source.include?('"--expected-sha256"'),
       "Fastlane lane does not bind re-verification to the recorded SHA-256")
assert(fastfile_source.include?("File::EXCL"),
       "Fastlane lane does not create exclusive upload state")
assert(fastfile_source.include?("file.fsync"),
       "Fastlane lane does not durably record upload state")
assert(fastfile_source.include?('"upload-attempt.json"'),
       "Fastlane lane does not record a duplicate-upload guard")
assert(fastfile_source.include?('"upload-receipt.json"'),
       "Fastlane lane does not record successful upload state")
assert(fastfile_source.include?("upload_directory.children.empty?"),
       "Fastlane lane may ignore legacy upload state for the same candidate")
assert(fastfile_source.include?('Pathname.new(Dir.home).join('),
       "Fastlane lane does not use a machine-scoped upload ledger")
assert(fastfile_source.include?("skip_submission: true"),
       "Fastlane lane may submit or distribute a build")
assert(fastfile_source.include?("skip_waiting_for_build_processing: true"),
       "Fastlane lane may wait for provider processing")
assert(fastfile_source.include?("distribute_external: false"),
       "Fastlane lane may distribute to external testers")
assert(fastfile_source.include?("notify_external_testers: false"),
       "Fastlane lane may notify external testers")

forbidden_fastlane_actions = %w[
  deliver
  upload_to_app_store
  submit_for_review
  automatic_release
  changelog:
  groups:
  screenshots_path
  metadata_path
]
forbidden_fastlane_actions.each do |forbidden|
  assert(!fastfile_source.include?(forbidden),
         "Fastlane lane contains forbidden mutation or distribution option #{forbidden}")
end
assert(!fastfile_source.include?("check_altool_delivery"),
       "Fastlane lane references the retired altool workflow")

ordered_tokens = [
  'key_id = required_environment_value!("ASC_KEY_ID")',
  'build_script = REPOSITORY_ROOT.join("scripts", "build_ios_testflight.sh")',
  "actual_sha256 = Digest::SHA256.file(ipa_path).hexdigest",
  'preflight_script = REPOSITORY_ROOT.join("scripts", "release_contract_preflight.sh")',
  'verify_script = REPOSITORY_ROOT.join("scripts", "verify_ios_ipa.rb")',
  "write_private_json_exclusive!(attempt_path, attempt)",
  "upload_to_testflight(",
  "write_private_json_exclusive!(receipt_path, receipt)",
  "File.unlink(attempt_path)"
]
ordered_positions = ordered_tokens.map do |token|
  position = fastfile_source.index(token)
  assert(!position.nil?, "Fastlane lane is missing ordered release step #{token}")
  position
end
ordered_positions.each_cons(2) do |before, after|
  assert(before < after, "Fastlane release steps are in an unsafe order")
end
lane_source = fastfile_source[fastfile_source.index("lane :beta")..]
assert(!lane_source.match?(/^\s*(rescue|ensure)\b/),
       "Fastlane lane may retry upload or remove its attempt marker after failure")

build_source = File.read(BUILD_SCRIPT)
assert(build_source.include?('mkdir "$build_lock"'),
       "build wrapper does not acquire an exclusive iOS build lock")
assert(build_source.include?('mkdir "$candidate_directory"'),
       "build wrapper does not atomically reserve candidate evidence")
assert(!build_source.include?('mkdir -p "$candidate_directory"'),
       "build wrapper still uses a racy candidate directory reservation")

preflight_source = File.read(PREFLIGHT_SCRIPT)
assert(!preflight_source.include?("YINGJIAN_OWNER_TESTFLIGHT_AUTHORIZED"),
       "preflight still contains the removed owner acceptance bypass")
assert(!preflight_source.include?("check_mvp_acceptance.rb"),
       "pre-upload workflow still blocks on post-upload MVP acceptance")
%w[validate-config validate-env validate-candidate validate-source].each do |gate|
  assert(preflight_source.scan(gate).length == 1,
         "pre-upload workflow removed or duplicated release gate #{gate}")
end
assert(File.file?(File.join(ROOT, "scripts", "check_mvp_acceptance.rb")),
       "post-upload MVP acceptance checker was removed")

puts "iOS TestFlight workflow tests passed."
