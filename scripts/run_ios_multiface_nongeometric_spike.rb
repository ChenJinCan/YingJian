#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

def fail_spike(message)
  warn "iOS multi-face non-geometric spike failed: #{message}"
  exit 1
end

repo_root = File.expand_path("..", __dir__)
manifest_path = File.expand_path(ARGV[0] || File.join(repo_root, ".quality/portrait-corpus-manifest.local.yaml"))
output_root = File.expand_path(ARGV[1] || File.join(repo_root, ".quality/ios-multiface-nongeometric-spike"))
quality_root = File.join(repo_root, ".quality")
fail_spike("manifest must stay inside .quality") unless manifest_path.start_with?("#{quality_root}/")
fail_spike("output must stay inside .quality") unless output_root.start_with?("#{quality_root}/")
fail_spike("manifest is missing") unless File.file?(manifest_path)

manifest = YAML.safe_load(File.read(manifest_path), permitted_classes: [], aliases: false)
assets = manifest.fetch("assets", []).select { |asset| asset.fetch("tags", []).include?("portrait_multi") }
fail_spike("manifest must contain portrait_multi assets") if assets.empty?
corpus_root_value = manifest.fetch("corpus_root", ".quality/corpus")
corpus_root = if corpus_root_value.start_with?("/")
  corpus_root_value
else
  File.join(repo_root, corpus_root_value)
end
portrait_source = File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift")
probe_source = File.join(repo_root, "scripts/support/run_ios_multiface_nongeometric_spike.swift")
FileUtils.mkdir_p(output_root)

Dir.mktmpdir("yingjian-multiface-spike-") do |directory|
  executable = File.join(directory, "multiface-spike")
  _stdout, stderr, status = Open3.capture3(
    "/usr/bin/xcrun", "swiftc", "-parse-as-library",
    portrait_source, probe_source, "-o", executable
  )
  fail_spike("Swift probe compilation failed: #{stderr.lines.first&.strip}") unless status.success?

  results = assets.map do |asset|
    source_path = File.join(corpus_root, asset.fetch("file"))
    fail_spike("#{asset.fetch("id")} source is missing") unless File.file?(source_path)
    actual_sha = Digest::SHA256.file(source_path).hexdigest
    fail_spike("#{asset.fetch("id")} source hash changed") unless actual_sha == asset.fetch("sha256")
    asset_output = File.join(output_root, asset.fetch("id"))
    stdout, stderr, status = Open3.capture3(executable, source_path, asset_output)
    fail_spike("#{asset.fetch("id")} probe failed: #{stderr.lines.first&.strip}") unless status.success?
    result = JSON.parse(stdout)
    result["id"] = asset.fetch("id")
    result["source_sha256"] = actual_sha
    %w[baseline].each do |field|
      result["#{field}_sha256"] = Digest::SHA256.file(result.fetch(field)).hexdigest
    end
    result.fetch("candidates").each do |name, path|
      result["#{name}_sha256"] = Digest::SHA256.file(path).hexdigest
    end
    File.write(File.join(asset_output, "result.json"), JSON.pretty_generate(result) + "\n")
    result
  end

  report = {
    "schema" => 1,
    "task" => "ios_multiface_nongeometric_spike",
    "candidate_identity" => {
      "apple_system" => "vision-landmarks-plus-cinoisereduction-v1",
      "yingjian_self_built" => "ios-metal-warp-retouch-candidate-v8",
      "open_source" => "opencv-bilateral-pending-isolated-build",
      "production_texture_smoothing" => "ios-texture-smoothing-v2",
      "production_skin_tone_lighting" => "ios-skin-tone-lighting-v2",
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
  puts "iOS multi-face spike generated #{results.length} fixed-image candidate sets: #{report_path}"
end
