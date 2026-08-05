#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

repo_root = File.expand_path("..", __dir__)
runner = File.join(repo_root, "scripts/run_ios_mvp_engineering_gate.sh")

def assert(condition, message)
  raise message unless condition
end

stdout, stderr, status = Open3.capture3(runner, "--list")
assert(status.success?, "gate list failed: #{stdout}#{stderr}")

expected = [
  "source hygiene",
  "Flutter static and unit tests",
  "iOS native tests",
  "iOS runtime journey",
  "image corpus contracts",
  "portrait engineering corpus",
  "portrait review structure",
  "iOS device evidence contract",
  "release contract",
]
expected.each do |landmark|
  assert(stdout.include?(landmark), "gate list is missing #{landmark.inspect}")
end

assert(!stdout.match?(/android|adb/i), "deferred platform work entered the iOS gate list")

_stdout, stderr, status = Open3.capture3(runner)
assert(!status.success? && stderr.include?("IOS_SIMULATOR_ID"),
       "runner accepted a missing iOS simulator identity")

puts "iOS MVP engineering gate runner tests passed."
