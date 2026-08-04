#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
checker = File.join(repo_root, "scripts/check_portrait_capture_manifest.rb")
plan_builder = File.join(repo_root, "scripts/build_portrait_review_plan.rb")
package_builder = File.join(repo_root, "scripts/build_blind_review_package.rb")

def assert(condition, message)
  raise message unless condition
end

def run(*command)
  Open3.capture3(*command)
end

def write_manifest(path, capture_directory, overrides = {})
  outputs = {
    "baselineOriginal" => ["baseline-original.jpg", "original", "source"],
    "offExport" => ["yingjian-off-export.jpg", "off", "export"],
    "defaultExport" => ["yingjian-default-export.jpg", "default", "export"],
    "highSafeExport" => ["yingjian-high-safe-export.jpg", "high_safe", "export"],
    "defaultPreview" => ["candidate-default-preview.png", "default", "preview"],
  }.to_h do |name, (file, variant, render_kind)|
    file_path = File.join(capture_directory, file)
    [
      name,
      {
        "file" => file,
        "sha256" => Digest::SHA256.file(file_path).hexdigest,
        "variant" => variant,
        "renderKind" => render_kind,
      },
    ]
  end
  manifest = {
    "schema" => 1,
    "candidateKind" => "vision-landmarks-geometry-roi",
    "effectVersion" => "ios-geometry-retouch-spike-v1",
    "productionEligible" => false,
    "executionEnvironment" => "physical-device",
    "device" => "iPhone14,8",
    "os" => "iOS 26.5",
    "appVersion" => "0.1.0",
    "appBuild" => "1",
    "capturedAtUtc" => "2026-08-05T00:00:00Z",
    "rawSourceSha256" => "a" * 64,
    "sourceWidth" => 96,
    "sourceHeight" => 64,
    "faceCount" => 0,
    "defaultStrength" => 0.35,
    "highSafeStrength" => 0.55,
    "outputs" => outputs,
  }.merge(overrides)
  File.write(path, JSON.pretty_generate(manifest))
end

FileUtils.mkdir_p(quality_root)
Dir.mktmpdir("portrait-review-plan-test-", quality_root) do |directory|
  capture_directory = File.join(directory, "review-inputs", "portrait-001")
  FileUtils.mkdir_p(capture_directory)
  fixture_source = File.join(directory, "fixture-images.swift")
  File.write(
    fixture_source,
    <<~SWIFT,
      import CoreImage
      import Foundation

      let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
      let context = CIContext(options: [.cacheIntermediates: false])
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
      let extent = CGRect(x: 0, y: 0, width: 96, height: 64)
      let original = CIImage(color: CIColor(red: 0.25, green: 0.35, blue: 0.45)).cropped(to: extent)
      let competitor = CIImage(color: CIColor(red: 0.28, green: 0.36, blue: 0.44)).cropped(to: extent)
      let jpegOptions = [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
      ]
      try context.writeJPEGRepresentation(
        of: original,
        to: directory.appendingPathComponent("baseline-original.jpg"),
        colorSpace: colorSpace,
        options: jpegOptions
      )
      try context.writePNGRepresentation(
        of: original,
        to: directory.appendingPathComponent("candidate-default-preview.png"),
        format: .RGBA8,
        colorSpace: colorSpace,
        options: [:]
      )
      try context.writeJPEGRepresentation(
        of: competitor,
        to: directory.appendingPathComponent("competitor-fixed-path-export.jpg"),
        colorSpace: colorSpace,
        options: jpegOptions
      )
    SWIFT
  )
  fixture_binary = File.join(directory, "fixture-images")
  _stdout, stderr, status = run("/usr/bin/xcrun", "swiftc", fixture_source, "-o", fixture_binary)
  assert(status.success?, "fixture image helper failed to compile: #{stderr}")
  _stdout, stderr, status = run(fixture_binary, capture_directory)
  assert(status.success?, "fixture images failed to render: #{stderr}")
  baseline = File.join(capture_directory, "baseline-original.jpg")
  %w[yingjian-off-export.jpg yingjian-default-export.jpg yingjian-high-safe-export.jpg].each do |name|
    FileUtils.cp(baseline, File.join(capture_directory, name))
  end

  manifest_path = File.join(capture_directory, "capture-manifest.json")
  write_manifest(manifest_path, capture_directory)
  stdout, stderr, status = run("ruby", checker, manifest_path)
  assert(status.success?, "valid physical capture failed: #{stdout}#{stderr}")
  summary = JSON.parse(stdout)
  assert(summary["status"] == "valid", "checker did not return a valid summary")
  assert(summary["execution_environment"] == "physical-device", "checker lost device identity")

  competitor_path = File.join(capture_directory, "competitor-fixed-path-export.jpg")
  intake = {
    "schema" => 1,
    "review_id" => "portrait-round-1",
    "minimum_reviewers" => 5,
    "items" => [
      {
        "asset_id" => "portrait-001",
        "tags" => %w[portrait_single improvable glasses],
        "capture_manifest" => manifest_path,
        "source" => {
          "version" => "raw-source-v1",
          "device" => "source-device-record",
          "os" => "source-os-record",
        },
        "competitor" => {
          "file" => competitor_path,
          "sha256" => Digest::SHA256.file(competitor_path).hexdigest,
          "version" => "fixture-1.2.3",
          "device" => "iPhone14,8",
          "os" => "iOS 26.5",
          "parameters" => { "preset" => "natural", "strength" => 50 },
          "operation_path" => "portrait > natural > strength 50 > export",
        },
      },
    ],
  }
  intake_path = File.join(directory, "portrait-review-intake.yaml")
  File.write(intake_path, YAML.dump(intake))
  plan_path = File.join(directory, "review-plan.yaml")
  stdout, stderr, status = run("ruby", plan_builder, intake_path, plan_path)
  assert(status.success?, "valid review plan failed: #{stdout}#{stderr}")
  plan = YAML.safe_load(File.read(plan_path), permitted_classes: [], aliases: false)
  candidates = plan.fetch("items").first.fetch("candidates")
  assert(candidates.length == 6, "generated review plan does not contain six slots")
  assert(candidates.all? { |candidate| !Pathname.new(candidate["file"]).absolute? },
         "generated review plan leaked absolute file paths")
  defaults = candidates.select do |candidate|
    candidate.dig("provenance", "variant") == "default"
  end
  assert(defaults.map { |candidate| candidate.dig("provenance", "parameters") }.uniq.length == 1,
         "default preview/export parameters diverged")
  subject = candidates.find { |candidate| candidate["id"] == "yingjian-default-export" }
  assert(subject.dig("provenance", "parameters", "capture_manifest_sha256") == Digest::SHA256.file(manifest_path).hexdigest,
         "capture manifest identity was not preserved")

  review_output = File.join(directory, "review-package")
  stdout, stderr, status = run(
    "ruby", package_builder, plan_path, review_output, "--seed", "portrait-round-1-seed"
  )
  assert(status.success?, "generated plan failed the existing package builder: #{stdout}#{stderr}")

  _stdout, stderr, status = run("ruby", plan_builder, intake_path, plan_path)
  assert(!status.success? && stderr.include?("output already exists"),
         "plan builder overwrote an existing plan")

  simulator_manifest = JSON.parse(File.read(manifest_path))
  simulator_manifest["executionEnvironment"] = "simulator-cpu-only"
  File.write(manifest_path, JSON.pretty_generate(simulator_manifest))
  _stdout, stderr, status = run("ruby", checker, manifest_path)
  assert(!status.success? && stderr.include?("physical-device"),
         "simulator capture entered the physical review intake")
  _stdout, stderr, status = run("ruby", checker, manifest_path, "--allow-simulator")
  assert(status.success?, "explicit simulator diagnostics were rejected: #{stderr}")

  write_manifest(manifest_path, capture_directory, "productionEligible" => true)
  _stdout, stderr, status = run("ruby", checker, manifest_path)
  assert(!status.success? && stderr.include?("productionEligible"),
         "production-eligible claim was accepted from the debug capture")

  write_manifest(manifest_path, capture_directory)
  default_export = File.join(capture_directory, "yingjian-default-export.jpg")
  FileUtils.cp(competitor_path, default_export)
  write_manifest(manifest_path, capture_directory)
  _stdout, stderr, status = run("ruby", checker, manifest_path)
  assert(!status.success? && stderr.include?("faceCount is zero"),
         "no-face capture with a changed default export was accepted")
  FileUtils.cp(baseline, default_export)
  write_manifest(manifest_path, capture_directory)

  preview = File.join(capture_directory, "candidate-default-preview.png")
  displaced_preview = File.join(directory, "displaced-preview.png")
  FileUtils.cp(preview, displaced_preview)
  File.delete(preview)
  File.symlink(displaced_preview, preview)
  write_manifest(manifest_path, capture_directory)
  _stdout, stderr, status = run("ruby", checker, manifest_path)
  assert(!status.success? && stderr.include?("outside the capture directory"),
         "capture output symlinked to another quality directory was accepted")
  File.delete(preview)
  FileUtils.cp(displaced_preview, preview)
  write_manifest(manifest_path, capture_directory)

  mismatched_intake = Marshal.load(Marshal.dump(intake))
  mismatched_intake["items"].first["competitor"]["device"] = "different-device"
  mismatched_path = File.join(directory, "mismatched-intake.yaml")
  File.write(mismatched_path, YAML.dump(mismatched_intake))
  _stdout, stderr, status = run(
    "ruby", plan_builder, mismatched_path, File.join(directory, "mismatched-plan.yaml")
  )
  assert(!status.success? && stderr.include?("same device and OS"),
         "cross-device competitor output was accepted")

  placeholder_intake = Marshal.load(Marshal.dump(intake))
  placeholder_intake["items"].first["competitor"]["version"] = "replace_with_version"
  placeholder_path = File.join(directory, "placeholder-intake.yaml")
  File.write(placeholder_path, YAML.dump(placeholder_intake))
  _stdout, stderr, status = run(
    "ruby", plan_builder, placeholder_path, File.join(directory, "placeholder-plan.yaml")
  )
  assert(!status.success? && stderr.include?("concrete string"),
         "placeholder competitor evidence was accepted")

  wrong_hash_intake = Marshal.load(Marshal.dump(intake))
  wrong_hash_intake["items"].first["competitor"]["sha256"] = "0" * 64
  wrong_hash_path = File.join(directory, "wrong-hash-intake.yaml")
  File.write(wrong_hash_path, YAML.dump(wrong_hash_intake))
  _stdout, stderr, status = run(
    "ruby", plan_builder, wrong_hash_path, File.join(directory, "wrong-hash-plan.yaml")
  )
  assert(!status.success? && stderr.include?("does not match"),
         "competitor hash drift was accepted")

  second_capture = File.join(directory, "review-inputs", "portrait-002")
  FileUtils.cp_r(capture_directory, second_capture)
  second_manifest_path = File.join(second_capture, "capture-manifest.json")
  second_competitor = File.join(second_capture, "competitor-fixed-path-export.jpg")
  File.open(second_competitor, "ab") { |file| file.write("round-two") }
  %w[
    baseline-original.jpg yingjian-off-export.jpg
    yingjian-default-export.jpg yingjian-high-safe-export.jpg
  ].each do |name|
    File.open(File.join(second_capture, name), "ab") { |file| file.write("round-two") }
  end
  write_manifest(
    second_manifest_path,
    second_capture,
    "rawSourceSha256" => "b" * 64,
    "appBuild" => "2",
  )
  mismatched_round = Marshal.load(Marshal.dump(intake))
  second_item = Marshal.load(Marshal.dump(intake["items"].first))
  second_item["asset_id"] = "portrait-002"
  second_item["capture_manifest"] = second_manifest_path
  second_item["competitor"]["file"] = second_competitor
  second_item["competitor"]["sha256"] = Digest::SHA256.file(second_competitor).hexdigest
  mismatched_round["items"] << second_item
  mismatched_round_path = File.join(directory, "mismatched-round-intake.yaml")
  File.write(mismatched_round_path, YAML.dump(mismatched_round))
  _stdout, stderr, status = run(
    "ruby", plan_builder, mismatched_round_path, File.join(directory, "mismatched-round-plan.yaml")
  )
  assert(!status.success? && stderr.include?("frozen Yingjian and competitor round configuration"),
         "mixed candidate builds entered one frozen review round")

  outside_directory = Dir.mktmpdir("portrait-review-outside-")
  begin
    outside_competitor = File.join(outside_directory, "competitor.jpg")
    FileUtils.cp(competitor_path, outside_competitor)
    symlink = File.join(capture_directory, "outside-competitor.jpg")
    File.symlink(outside_competitor, symlink)
    escaped_intake = Marshal.load(Marshal.dump(intake))
    escaped_intake["items"].first["competitor"]["file"] = symlink
    escaped_path = File.join(directory, "escaped-intake.yaml")
    File.write(escaped_path, YAML.dump(escaped_intake))
    _stdout, stderr, status = run(
      "ruby", plan_builder, escaped_path, File.join(directory, "escaped-plan.yaml")
    )
    assert(!status.success? && stderr.include?("ignored .quality"),
           "symlinked competitor escaped the private quality root")
  ensure
    FileUtils.remove_entry(outside_directory)
  end
end

puts "Portrait review intake tests passed"
