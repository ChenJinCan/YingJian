#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "test_support/device_evidence_fixture"

repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
evidence_root = File.join(quality_root, "device-evidence")
checker = File.join(repo_root, "scripts/check_device_evidence.rb")
source_commit = "a" * 40

def assert(condition, message)
  raise message unless condition
end

def run(*command)
  Open3.capture3(*command)
end

def relative_to_repo(path, repo_root)
  Pathname.new(path).relative_path_from(Pathname.new(repo_root)).to_s
end

def samples(value, count)
  Array.new(count, value)
end

FileUtils.mkdir_p(evidence_root)
Dir.mktmpdir("device-evidence-test-", evidence_root) do |directory|
  slots = [["ios", "low"], ["ios", "mid"], ["ios", "high"]]
  coverage = {
    ["ios", "low"] => %w[12mp portrait_single six_photo_group],
    ["ios", "mid"] => %w[12mp 24mp display_p3 heic six_photo_group],
    ["ios", "high"] => %w[48mp portrait_multi six_photo_batch],
  }
  platform_build_files = {
    "ios" => DeviceEvidenceFixture.create_profile_ipa(
      repo_root: repo_root, directory: directory, source_commit: source_commit,
      device_udids: 3.times.map { |index| "fixture-udid-#{index}" }
    ),
  }
  runs = slots.map.with_index do |(platform, tier), index|
    run_id = "#{platform}-#{tier}-fixture"
    run_directory = File.join(directory, run_id)
    FileUtils.mkdir_p(run_directory)
    outcomes = %w[
      source_hash_unchanged final_artifacts_valid three_batch_rounds_completed
      no_system_kill background_restore low_memory_restore cancellation_recover
      offline_journey diagnostics_disabled cloud_image_tasks_zero accessibility_task_completed
    ].to_h { |name| [name, true] }
    if platform == "ios"
      %w[system_share_success system_share_cancel system_share_failure].each do |name|
        outcomes[name] = true
      end
    end
    measurements = {
      "first_preview_ms" => samples(500, 5),
      "six_photo_recommendations_ms" => samples(1_000, 5),
      "slider_response_ms" => samples(30, 20),
      "continuous_preview_fps" => samples(60, 20),
      "export_12mp_ms" => samples(1_000, 3),
      "batch_six_12mp_ms" => samples(5_000, 3),
      "ui_main_thread_stalls_ms" => samples(10, 20),
      "peak_additional_memory_mb" => 100,
      "thermal_states" => %w[nominal fair],
      "thermal_mitigation_activated" => false,
    }
    measurements["export_24mp_ms"] = samples(2_000, 3) if tier == "mid"
    measurements["export_48mp_ms"] = samples(4_000, 3) if tier == "high"
    methodology = {
      "timing_tool" => "fixture monotonic trace parser",
      "memory_tool" => "fixture resident-memory sampler",
      "frame_tool" => "fixture frame-timing callback",
      "thermal_tool" => "fixture platform thermal monitor",
      "lifecycle_protocol" => "fixture background low-memory cancel protocol",
    }

    build_file = platform_build_files.fetch(platform)
    device_identifier = "fixture-core-device-#{index}"
    model = ["iPhone 11", "iPhone 14 Plus", "iPhone 15 Pro"].fetch(index)
    product_type = ["iPhone12,1", "iPhone14,8", "iPhone16,1"].fetch(index)
    device_capture_file = File.join(run_directory, "devicectl-device.json")
    metrics_file = File.join(run_directory, "metrics.json")
    probe_file = File.join(run_directory, "final-artifacts.json")
    File.write(
      device_capture_file,
      JSON.pretty_generate(DeviceEvidenceFixture.device_capture_record(
        repo_root: repo_root, identifier: device_identifier,
        udid: "fixture-udid-#{index}", model: model, product_type: product_type
      )),
    )
    File.write(
      metrics_file,
      JSON.pretty_generate(
        "schema" => 1,
        "run_id" => run_id,
        "methodology" => methodology,
        "measurements" => measurements,
        "outcomes" => outcomes,
      ),
    )
    File.write(
      probe_file,
      JSON.pretty_generate(
        "schema" => 1,
        "run_id" => run_id,
        "source_commit" => source_commit,
        "probed_output_count" => 6,
        "checks" => %w[
          orientation dimensions crop srgb jpeg_quality_95 capture_time
          sensitive_metadata_removed source_hash_unchanged
        ].to_h { |name| [name, true] },
      ),
    )
    artifacts = [
      ["build_artifact", build_file],
      ["device_capture", device_capture_file],
      ["metrics_log", metrics_file],
      ["final_artifact_probe", probe_file],
    ].map do |kind, path|
      {
        "kind" => kind,
        "file" => relative_to_repo(path, repo_root),
        "sha256" => Digest::SHA256.file(path).hexdigest,
      }
    end
    {
      "run_id" => run_id,
      "platform" => platform,
      "tier" => tier,
      "device" => {
        "device_id" => Digest::SHA256.hexdigest(device_identifier),
        "model" => model,
        "hardware_class" => product_type,
        "os_version" => "iOS 26.5.2",
        "tier_basis" => "frozen fixture tier #{tier}",
        "physical_memory_mb" => 4_096,
        "physical" => true,
      },
      "build" => {
        "mode" => "profile",
        "source_commit" => source_commit,
        "bundle_id" => "com.babycompany.yingjian",
        "version" => "0.1.0",
        "build_number" => "1",
        "artifact_sha256" => Digest::SHA256.file(build_file).hexdigest,
      },
      "coverage" => coverage.fetch([platform, tier]),
      "methodology" => methodology,
      "measurements" => measurements,
      "outcomes" => outcomes,
      "artifacts" => artifacts,
    }
  end
  manifest = {
    "schema" => 1,
    "status" => "ready",
    "source_commit" => source_commit,
    "runs" => runs,
  }
  manifest_path = File.join(directory, "device-evidence.yaml")
  File.write(manifest_path, YAML.dump(manifest))

  stdout, stderr, status = run(
    "ruby", checker, manifest_path, "--source-commit", source_commit
  )
  assert(status.success?, "valid iOS three-tier evidence failed: #{stdout}#{stderr}")
  assert(stdout.include?("3/3 iOS physical runs"), "complete evidence summary is missing")
  assert(stdout.include?("slider_p95_ms"), "computed percentile summary is missing")

  no_device_capture = Marshal.load(Marshal.dump(manifest))
  no_device_capture["runs"].each do |run|
    run["artifacts"].reject! { |artifact| artifact["kind"] == "device_capture" }
  end
  no_device_capture_path = File.join(directory, "no-device-capture.yaml")
  File.write(no_device_capture_path, YAML.dump(no_device_capture))
  _stdout, stderr, status = run("ruby", checker, no_device_capture_path)
  assert(!status.success? && stderr.include?("device_capture"),
         "self-asserted physical devices passed without devicectl capture")

  build_file = platform_build_files.fetch("ios")
  valid_build_bytes = File.binread(build_file)
  File.binwrite(build_file, "not-an-ios-build")
  fake_build = Marshal.load(Marshal.dump(manifest))
  fake_sha = Digest::SHA256.file(build_file).hexdigest
  fake_build["runs"].each do |run|
    run["build"]["artifact_sha256"] = fake_sha
    run["artifacts"].find { |artifact| artifact["kind"] == "build_artifact" }["sha256"] = fake_sha
  end
  fake_build_path = File.join(directory, "fake-build.yaml")
  File.write(fake_build_path, YAML.dump(fake_build))
  _stdout, stderr, status = run("ruby", checker, fake_build_path)
  assert(!status.success? && stderr.include?("verified signed iOS device build"),
         "a hashed text file passed as the physical-device build artifact")
  File.binwrite(build_file, valid_build_bytes)

  wrong_installed_build = Marshal.load(Marshal.dump(manifest))
  wrong_capture_artifact = wrong_installed_build["runs"].first["artifacts"].find do |artifact|
    artifact["kind"] == "device_capture"
  end
  wrong_capture_path = File.join(repo_root, wrong_capture_artifact["file"])
  valid_capture_bytes = File.binread(wrong_capture_path)
  wrong_capture = JSON.parse(valid_capture_bytes)
  wrong_capture["installed_apps"]["result"]["apps"].first["bundleVersion"] = "999"
  File.write(wrong_capture_path, JSON.pretty_generate(wrong_capture))
  wrong_capture_artifact["sha256"] = Digest::SHA256.file(wrong_capture_path).hexdigest
  wrong_installed_path = File.join(directory, "wrong-installed-build.yaml")
  File.write(wrong_installed_path, YAML.dump(wrong_installed_build))
  _stdout, stderr, status = run("ruby", checker, wrong_installed_path)
  assert(!status.success? && stderr.include?("frozen app version/build is installed"),
         "signed IPA was not bound to the build installed on the tested iPhone")
  File.binwrite(wrong_capture_path, valid_capture_bytes)

  duplicate_udid = Marshal.load(Marshal.dump(manifest))
  second_capture_artifact = duplicate_udid["runs"][1]["artifacts"].find do |artifact|
    artifact["kind"] == "device_capture"
  end
  second_capture_path = File.join(repo_root, second_capture_artifact["file"])
  valid_second_capture = File.binread(second_capture_path)
  second_capture = JSON.parse(valid_second_capture)
  second_capture["device_list"]["result"]["devices"].first["hardwareProperties"]["udid"] = "fixture-udid-0"
  File.write(second_capture_path, JSON.pretty_generate(second_capture))
  second_capture_artifact["sha256"] = Digest::SHA256.file(second_capture_path).hexdigest
  duplicate_udid_path = File.join(directory, "duplicate-udid.yaml")
  File.write(duplicate_udid_path, YAML.dump(duplicate_udid))
  _stdout, stderr, status = run("ruby", checker, duplicate_udid_path)
  assert(!status.success? && stderr.include?("duplicate captured physical iPhone UDID"),
         "one physical iPhone was accepted as multiple device tiers")
  File.binwrite(second_capture_path, valid_second_capture)

  incomplete = Marshal.load(Marshal.dump(manifest))
  incomplete["status"] = "blocked_missing_runs"
  incomplete["runs"] = [incomplete["runs"].first]
  incomplete_path = File.join(directory, "incomplete.yaml")
  File.write(incomplete_path, YAML.dump(incomplete))
  _stdout, stderr, status = run("ruby", checker, incomplete_path)
  assert(!status.success? && stderr.include?("device run count"),
         "incomplete device matrix passed the complete gate")
  stdout, stderr, status = run("ruby", checker, incomplete_path, "--allow-incomplete")
  assert(status.success? && stdout.include?("1/3 iOS runs"),
         "valid partial device evidence failed schema mode: #{stderr}")

  android = Marshal.load(Marshal.dump(manifest))
  android["runs"].first["platform"] = "android"
  android_path = File.join(directory, "android.yaml")
  File.write(android_path, YAML.dump(android))
  _stdout, stderr, status = run("ruby", checker, android_path, "--allow-incomplete")
  assert(!status.success? && stderr.include?("iOS low/mid/high slot"),
         "deferred Android evidence entered the iOS MVP gate")

  slow = Marshal.load(Marshal.dump(manifest))
  high = slow["runs"].find { |entry| entry["platform"] == "ios" && entry["tier"] == "high" }
  high["measurements"]["slider_response_ms"][-2, 2] = [81, 81]
  slow_path = File.join(directory, "slow.yaml")
  File.write(slow_path, YAML.dump(slow))
  _stdout, stderr, status = run("ruby", checker, slow_path)
  assert(!status.success? && stderr.include?("metrics_log does not exactly bind") &&
           stderr.include?("slider response p95"),
         "changed or over-budget raw metrics were accepted")

  simulated = Marshal.load(Marshal.dump(manifest))
  simulated["runs"].first["device"]["physical"] = false
  simulated_path = File.join(directory, "simulated.yaml")
  File.write(simulated_path, YAML.dump(simulated))
  _stdout, stderr, status = run("ruby", checker, simulated_path)
  assert(!status.success? && stderr.include?("physical must equal true"),
         "simulator evidence entered the physical matrix")

  non_iphone = Marshal.load(Marshal.dump(manifest))
  non_iphone["runs"].first["device"]["model"] = "Pixel 9"
  non_iphone_path = File.join(directory, "non-iphone.yaml")
  File.write(non_iphone_path, YAML.dump(non_iphone))
  _stdout, stderr, status = run("ruby", checker, non_iphone_path)
  assert(!status.success? && stderr.include?("physical iPhone model"),
         "non-iPhone device entered the iOS physical matrix")

  wrong_tier = Marshal.load(Marshal.dump(manifest))
  low_run = wrong_tier["runs"].find { |entry| entry["tier"] == "low" }
  low_capture_artifact = low_run["artifacts"].find { |artifact| artifact["kind"] == "device_capture" }
  low_capture_path = File.join(repo_root, low_capture_artifact["file"])
  valid_low_capture = File.binread(low_capture_path)
  low_capture = JSON.parse(valid_low_capture)
  low_capture["device_list"]["result"]["devices"].first["hardwareProperties"]["marketingName"] = "iPhone 15 Pro"
  low_capture["device_list"]["result"]["devices"].first["hardwareProperties"]["productType"] = "iPhone16,1"
  low_run["device"]["model"] = "iPhone 15 Pro"
  low_run["device"]["hardware_class"] = "iPhone16,1"
  File.write(low_capture_path, JSON.pretty_generate(low_capture))
  low_capture_artifact["sha256"] = Digest::SHA256.file(low_capture_path).hexdigest
  wrong_tier_path = File.join(directory, "wrong-tier.yaml")
  File.write(wrong_tier_path, YAML.dump(wrong_tier))
  _stdout, stderr, status = run("ruby", checker, wrong_tier_path)
  assert(!status.success? && stderr.include?("frozen low hardware tier"),
         "a flagship iPhone was accepted as the frozen low tier")
  File.binwrite(low_capture_path, valid_low_capture)

  duplicate_device = Marshal.load(Marshal.dump(manifest))
  duplicate_device["runs"][1]["device"]["device_id"] =
    duplicate_device["runs"][0]["device"]["device_id"]
  duplicate_device_path = File.join(directory, "duplicate-device.yaml")
  File.write(duplicate_device_path, YAML.dump(duplicate_device))
  _stdout, stderr, status = run("ruby", checker, duplicate_device_path)
  assert(!status.success? && stderr.include?("duplicate physical device identity"),
         "one physical device was counted as two frozen tiers")

  mixed_build = Marshal.load(Marshal.dump(manifest))
  ios_mid = mixed_build["runs"].find do |entry|
    entry["platform"] == "ios" && entry["tier"] == "mid"
  end
  ios_mid["build"]["build_number"] = "2"
  mixed_build_path = File.join(directory, "mixed-build.yaml")
  File.write(mixed_build_path, YAML.dump(mixed_build))
  _stdout, stderr, status = run("ruby", checker, mixed_build_path)
  assert(!status.success? && stderr.include?("frozen ios build"),
         "one platform mixed multiple candidate builds")

  bad_hash = Marshal.load(Marshal.dump(manifest))
  bad_hash["runs"].first["artifacts"].first["sha256"] = "0" * 64
  bad_hash_path = File.join(directory, "bad-hash.yaml")
  File.write(bad_hash_path, YAML.dump(bad_hash))
  _stdout, stderr, status = run("ruby", checker, bad_hash_path)
  assert(!status.success? && stderr.include?("does not match the file"),
         "tampered evidence artifact hash was accepted")

  outside = Dir.mktmpdir("device-evidence-outside-")
  begin
    outside_file = File.join(outside, "metrics.json")
    File.write(outside_file, "outside")
    symlink = File.join(directory, "ios-low-fixture", "escaped-metrics.json")
    File.symlink(outside_file, symlink)
    escaped = Marshal.load(Marshal.dump(manifest))
    metrics_artifact = escaped["runs"].first["artifacts"].find do |artifact|
      artifact["kind"] == "metrics_log"
    end
    metrics_artifact["file"] = relative_to_repo(symlink, repo_root)
    metrics_artifact["sha256"] = Digest::SHA256.file(outside_file).hexdigest
    escaped_path = File.join(directory, "escaped.yaml")
    File.write(escaped_path, YAML.dump(escaped))
    _stdout, stderr, status = run("ruby", checker, escaped_path)
    assert(!status.success? && stderr.include?("resolves outside"),
           "evidence symlink escaped the private device directory")
  ensure
    FileUtils.remove_entry(outside)
  end

  _stdout, stderr, status = run(
    "ruby", checker, manifest_path, "--source-commit", "b" * 40
  )
  assert(!status.success? && stderr.include?("does not match --source-commit"),
         "device evidence was accepted for a different source commit")
end

puts "Device evidence checker tests passed"
