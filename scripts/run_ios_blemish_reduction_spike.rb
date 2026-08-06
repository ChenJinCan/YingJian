#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

def fail_spike(message)
  warn "iOS blemish-reduction spike failed: #{message}"
  exit 1
end

repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
manifest_path = File.expand_path(ARGV[0] || File.join(quality_root, "portrait-corpus-manifest.local.yaml"))
output_root = File.expand_path(ARGV[1] || File.join(quality_root, "ios-blemish-reduction-spike"))
fail_spike("paths must stay inside .quality") unless
  manifest_path.start_with?("#{quality_root}/") && output_root.start_with?("#{quality_root}/")
manifest = YAML.safe_load(File.read(manifest_path), permitted_classes: [], aliases: false)
candidate_ids = %w[
  blemish-consented-001
  portrait-001
  portrait-007
  portrait-010
  portrait-013
  portrait-014
  portrait-015
  portrait-017
  portrait-025
  portrait-026
  portrait-027
  portrait-028
  portrait-031
  portrait-035
]
assets_by_id = manifest.fetch("assets", []).to_h { |asset| [asset.fetch("id"), asset] }
assets = candidate_ids.map { |id| assets_by_id.fetch(id) }
corpus_root = File.join(repo_root, manifest.fetch("corpus_root", ".quality/corpus"))
portrait_source = File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift")
probe_source = File.join(repo_root, "scripts/support/run_ios_blemish_reduction_spike.swift")
opencv_probe = File.join(repo_root, "scripts/support/run_opencv_portrait_spike.py")
opencv_pythonpath = ENV["YINGJIAN_OPENCV_PYTHONPATH"]
if opencv_pythonpath && !Dir.exist?(opencv_pythonpath)
  fail_spike("YINGJIAN_OPENCV_PYTHONPATH does not exist")
end
FileUtils.mkdir_p(output_root)

Dir.mktmpdir("yingjian-blemish-spike-") do |directory|
  executable = File.join(directory, "blemish-spike")
  _stdout, stderr, status = Open3.capture3(
    "/usr/bin/xcrun", "swiftc", "-parse-as-library",
    portrait_source, probe_source, "-o", executable
  )
  fail_spike("Swift probe compilation failed: #{stderr.lines.first&.strip}") unless status.success?
  results = assets.map do |asset|
    source_path = File.join(corpus_root, asset.fetch("file"))
    actual_sha = Digest::SHA256.file(source_path).hexdigest
    fail_spike("#{asset.fetch("id")} source hash changed") unless actual_sha == asset.fetch("sha256")
    stdout, stderr, status = Open3.capture3(
      executable, source_path, File.join(output_root, asset.fetch("id"))
    )
    fail_spike("#{asset.fetch("id")} probe failed: #{stderr.lines.first&.strip}") unless status.success?
    result = JSON.parse(stdout)
    result["id"] = asset.fetch("id")
    result["tags"] = asset.fetch("tags")
    result["source_sha256"] = actual_sha
    result.fetch("outputs").each do |name, path|
      result["#{name}_sha256"] = Digest::SHA256.file(path).hexdigest
    end
    result.fetch("face_crops").each do |name, path|
      result["#{name}_face_sha256"] = Digest::SHA256.file(path).hexdigest
    end
    asset_output = File.join(output_root, asset.fetch("id"))
    metadata_path = File.join(asset_output, "result.json")
    File.write(metadata_path, JSON.pretty_generate(result) + "\n")
    if opencv_pythonpath
      opencv_output = File.join(asset_output, "opencv-inpaint.jpg")
      opencv_stdout, opencv_stderr, opencv_status = Open3.capture3(
        { "PYTHONPATH" => opencv_pythonpath, "PYTHONDONTWRITEBYTECODE" => "1" },
        "python3", opencv_probe, "blemish", result.fetch("outputs").fetch("off"),
        metadata_path, opencv_output
      )
      fail_spike("#{asset.fetch("id")} OpenCV probe failed: #{opencv_stderr.lines.first&.strip}") unless
        opencv_status.success?
      result["opencv"] = JSON.parse(opencv_stdout)
      result["opencv_sha256"] = Digest::SHA256.file(opencv_output).hexdigest
      File.write(metadata_path, JSON.pretty_generate(result) + "\n")
    end
    result
  end
  report = {
    "schema" => 1,
    "task" => "ios_conservative_blemish_reduction_spike",
    "candidate_identity" => {
      "apple_system" => "no-safe-semantic-candidate-no-op",
      "yingjian_self_built" => results.dig(0, "effect_version"),
      "open_source" => opencv_pythonpath ? "opencv-inpaint-#{results.dig(0, "opencv", "opencv_version")}" : "not_run",
    },
    "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
    "portrait_source_sha256" => Digest::SHA256.file(portrait_source).hexdigest,
    "probe_source_sha256" => Digest::SHA256.file(probe_source).hexdigest,
    "engineering_only" => true,
    "quality_passed" => false,
    "assets" => results,
  }
  report_path = File.join(output_root, "engineering-report.json")
  File.write(report_path, JSON.pretty_generate(report) + "\n")
  puts "iOS blemish spike generated #{results.length} fixed-image triplets: #{report_path}"
end
