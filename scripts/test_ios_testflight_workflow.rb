#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

ROOT = File.expand_path("..", __dir__)
BUILD_SCRIPT = File.join(ROOT, "scripts", "build_ios_testflight.sh")
UPLOAD_SCRIPT = File.join(ROOT, "scripts", "upload_ios_testflight.sh")
PREFLIGHT_SCRIPT = File.join(ROOT, "scripts", "release_contract_preflight.sh")

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

preflight_source = File.read(PREFLIGHT_SCRIPT)
assert(!preflight_source.include?("YINGJIAN_OWNER_TESTFLIGHT_AUTHORIZED"),
       "preflight still contains the removed owner acceptance bypass")
assert(preflight_source.scan("check_mvp_acceptance.rb").length == 1,
       "default MVP acceptance checker was removed or duplicated")

puts "iOS TestFlight workflow tests passed."
