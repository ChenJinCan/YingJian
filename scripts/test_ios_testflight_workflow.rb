#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

ROOT = File.expand_path("..", __dir__)
BUILD_SCRIPT = File.join(ROOT, "scripts", "build_ios_testflight.sh")
UPLOAD_SCRIPT = File.join(ROOT, "scripts", "upload_ios_testflight.sh")

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
assert(!stdout.include?("upload-package"), "local build plan unexpectedly uploads to Apple")

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
assert(status.success?, "upload dry-run failed: #{stdout}#{stderr}")
assert(stdout.include?("TESTFLIGHT-UPLOAD"), "upload plan did not label its Apple mutation")
assert(stdout.include?("release_contract_preflight.sh ios 1.2.4 112 upload"),
       "upload plan omitted the fresh release contract preflight")
assert(stdout.include?("verify_ios_ipa.rb"), "upload plan did not re-verify the exact IPA")
assert(stdout.include?("altool --validate-app"), "upload plan omitted Apple validation")
assert(stdout.include?("altool --upload-package") && stdout.include?("--wait"),
       "upload plan does not wait on the uploaded delivery")
assert(stdout.include?("provider valid only"),
       "upload plan did not state its terminal boundary")

puts "iOS TestFlight workflow tests passed."
