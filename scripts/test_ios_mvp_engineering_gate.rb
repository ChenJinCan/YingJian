#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "fileutils"
require "tmpdir"

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
  "portrait engineering diagnostic tools",
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

integration_runner = File.join(repo_root, "scripts/test_ios_mvp_integration.sh")
Dir.mktmpdir("ios-mvp-runner-test-") do |directory|
  bin_directory = File.join(directory, "bin")
  FileUtils.mkdir_p(bin_directory)
  log_path = File.join(directory, "flutter.log")
  File.write(
    File.join(bin_directory, "xcrun"),
    <<~SH,
      #!/bin/sh
      if [ "$1" = "simctl" ] && [ "$2" = "list" ]; then
        echo "    iPhone fixture (fixture-ios-simulator) (Booted)"
      fi
      exit 0
    SH
  )
  File.write(
    File.join(bin_directory, "flutter"),
    <<~SH,
      #!/bin/sh
      printf '%s\t%s\n' "${XDG_CONFIG_HOME:-}" "$*" >> "$YINGJIAN_FLUTTER_LOG"
      exit 0
    SH
  )
  FileUtils.chmod(0o755, [
    File.join(bin_directory, "xcrun"),
    File.join(bin_directory, "flutter"),
  ])
  environment = {
    "PATH" => "#{bin_directory}:#{ENV.fetch("PATH")}",
    "YINGJIAN_FLUTTER_LOG" => log_path,
  }
  stdout, stderr, status = Open3.capture3(
    environment,
    integration_runner,
    "fixture-ios-simulator",
  )
  assert(status.success?, "isolated iOS integration runner failed: #{stdout}#{stderr}")
  invocations = File.readlines(log_path, chomp: true).map { |line| line.split("\t", 2) }
  config_roots = invocations.map(&:first).uniq
  assert(config_roots.length == 1 && !config_roots.first.empty?,
         "iOS integration runner did not isolate Flutter configuration")
  assert(invocations.any? { |(_, command)| command.include?("config --no-enable-android --enable-ios") },
         "iOS integration runner did not disable Android discovery")
  assert(invocations.any? { |(_, command)| command.include?("config --no-enable-swift-package-manager") },
         "iOS integration runner did not preserve the CocoaPods project configuration")
  assert(!Dir.exist?(config_roots.first), "temporary Flutter configuration was not removed")
end

puts "iOS-only integration runner isolation tests passed."
