#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "support/cross_platform_render_comparison"

def fail_contract(message)
  warn "Cross-platform render comparison failed: #{message}"
  exit 1
end

repo_root = File.expand_path("..", __dir__)
ios_argument = ARGV.shift
android_argument = ARGV.shift
output_argument = ARGV.shift
if ios_argument.nil? || android_argument.nil? || output_argument.nil? || !ARGV.empty?
  fail_contract("usage: run_cross_platform_render_comparison.rb IOS_DIRECTORY ANDROID_DIRECTORY OUTPUT_DIRECTORY")
end

begin
  ios_root = CrossPlatformRenderComparison.validated_quality_directory(
    ios_argument,
    repo_root: repo_root,
  )
  android_root = CrossPlatformRenderComparison.validated_quality_directory(
    android_argument,
    repo_root: repo_root,
  )
  output_root = CrossPlatformRenderComparison.validated_output_root(
    output_argument,
    repo_root: repo_root,
  )
rescue CrossPlatformRenderComparison::ContractError => error
  fail_contract(error.message)
end
fail_contract("output directory already exists") if File.exist?(output_root)

def read_report(root, platform)
  path = File.join(root, "engineering-report.json")
  raise CrossPlatformRenderComparison::ContractError, "#{platform} report is missing" unless File.file?(path)
  report = JSON.parse(File.read(path))
  unless report["schema"] == 1 && report["engineering_only"] == true
    raise CrossPlatformRenderComparison::ContractError, "#{platform} report contract is invalid"
  end
  [path, report]
rescue JSON::ParserError
  raise CrossPlatformRenderComparison::ContractError, "#{platform} report is not JSON"
end

begin
  ios_report_path, ios_report = read_report(ios_root, "ios")
  android_report_path, android_report = read_report(android_root, "android")
  ios_assets = CrossPlatformRenderComparison.index_assets!(ios_report, platform: "ios")
  android_assets = CrossPlatformRenderComparison.index_assets!(android_report, platform: "android")
rescue CrossPlatformRenderComparison::ContractError => error
  fail_contract(error.message)
end
unless ios_report["manifest_sha256"] == android_report["manifest_sha256"]
  fail_contract("platform reports do not bind the same corpus manifest")
end
unless ios_assets.keys == android_assets.keys
  fail_contract("platform reports do not contain the same ordered assets")
end

comparator_source = File.join(
  repo_root,
  "scripts/support/compare_cross_platform_renders.swift",
)
fail_contract("render comparator source is missing") unless File.file?(comparator_source)
sample_max_edge = 512
quality_root = File.join(repo_root, ".quality")
begin
  CrossPlatformRenderComparison.validate_output_ancestry!(output_root, repo_root: repo_root)
rescue CrossPlatformRenderComparison::ContractError => error
  fail_contract(error.message)
end

report_assets = []
Dir.mktmpdir(".cross-platform-render-", quality_root) do |temporary_root|
  comparator = File.join(temporary_root, "render-comparator")
  compile_stdout, compile_stderr, compile_status = Open3.capture3(
    "/usr/bin/xcrun",
    "swiftc",
    "-parse-as-library",
    comparator_source,
    "-o",
    comparator,
  )
  unless compile_status.success?
    detail = compile_stderr.lines.first&.strip || compile_stdout.lines.first&.strip
    fail_contract("render comparator compilation failed: #{detail}")
  end

  ios_assets.each do |asset_id, ios_asset|
    android_asset = android_assets.fetch(asset_id)
    ios_path = File.join(ios_root, "#{asset_id}.jpg")
    android_path = File.join(android_root, "#{asset_id}.jpg")
    fail_contract("#{asset_id} iOS output is missing") unless File.file?(ios_path)
    fail_contract("#{asset_id} Android output is missing") unless File.file?(android_path)
    unless Digest::SHA256.file(ios_path).hexdigest == ios_asset["output_sha256"]
      fail_contract("#{asset_id} iOS output hash changed")
    end
    unless Digest::SHA256.file(android_path).hexdigest == android_asset["output_sha256"]
      fail_contract("#{asset_id} Android output hash changed")
    end
    ios_source_hash = ios_asset["source_sha256"]
    android_source_hash = android_asset["source_sha256_before"]
    unless ios_source_hash == android_source_hash &&
           android_source_hash == android_asset["source_sha256_after"]
      fail_contract("#{asset_id} platform reports do not bind the same source")
    end
    unless ios_asset["tags"] == android_asset["tags"]
      fail_contract("#{asset_id} platform tags differ")
    end
    ios_dimensions = [ios_asset.dig("output", "width"), ios_asset.dig("output", "height")]
    android_dimensions = [android_asset["width"], android_asset["height"]]
    fail_contract("#{asset_id} platform dimensions differ") unless ios_dimensions == android_dimensions

    metric_stdout, metric_stderr, metric_status = Open3.capture3(
      comparator,
      ios_path,
      android_path,
      sample_max_edge.to_s,
    )
    unless metric_status.success?
      detail = metric_stderr.lines.first&.strip || metric_stdout.lines.first&.strip
      fail_contract("#{asset_id} comparison failed: #{detail}")
    end
    begin
      metric = JSON.parse(metric_stdout)
      CrossPlatformRenderComparison.validate_metric!(metric, asset_id: asset_id)
    rescue JSON::ParserError
      fail_contract("#{asset_id} comparison result is not JSON")
    rescue CrossPlatformRenderComparison::ContractError => error
      fail_contract(error.message)
    end
    metric["maximum_absolute_rgb_bias"] = metric.fetch("mean_rgb_bias").map(&:abs).max
    report_assets << {
      "id" => asset_id,
      "tags" => ios_asset.fetch("tags"),
      "source_sha256" => ios_source_hash,
      "ios_output_sha256" => ios_asset.fetch("output_sha256"),
      "android_output_sha256" => android_asset.fetch("output_sha256"),
      "metric" => metric,
    }
  end

  summary_fields = CrossPlatformRenderComparison::NORMALIZED_METRICS + [
    "maximum_absolute_rgb_bias",
  ]
  summarize_assets = lambda do |assets|
    summary_fields.to_h do |field|
      values = assets.map { |asset| asset.fetch("metric").fetch(field) }
      [field, CrossPlatformRenderComparison.summarize(values)]
    end
  end
  tags = report_assets.flat_map { |asset| asset.fetch("tags") }.uniq.sort
  tag_summaries = tags.to_h do |tag|
    tagged = report_assets.select { |asset| asset.fetch("tags").include?(tag) }
    [tag, { "asset_count" => tagged.length, "metrics" => summarize_assets.call(tagged) }]
  end
  psnr_values = report_assets.each_with_object([]) do |asset, values|
    value = asset.dig("metric", "psnr_db")
    values << value unless value.nil?
  end
  report = {
    "schema" => 1,
    "engineering_only" => true,
    "observation_only" => true,
    "thresholds_frozen" => false,
    "sample_max_edge" => sample_max_edge,
    "manifest_sha256" => ios_report.fetch("manifest_sha256"),
    "ios_report_sha256" => Digest::SHA256.file(ios_report_path).hexdigest,
    "android_report_sha256" => Digest::SHA256.file(android_report_path).hexdigest,
    "comparator_source_sha256" => Digest::SHA256.file(comparator_source).hexdigest,
    "runner_source_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
    "asset_count" => report_assets.length,
    "metrics" => summarize_assets.call(report_assets).merge(
      "psnr_db" => CrossPlatformRenderComparison.summarize(psnr_values),
    ),
    "tag_summaries" => tag_summaries,
    "assets" => report_assets,
  }
  staged_output_root = File.join(temporary_root, "output")
  FileUtils.mkdir_p(staged_output_root)
  File.write(
    File.join(staged_output_root, "observation-report.json"),
    JSON.pretty_generate(report) + "\n",
  )
  FileUtils.mkdir_p(File.dirname(output_root))
  FileUtils.mv(staged_output_root, output_root)
end

puts "Cross-platform render observation passed: #{report_assets.length} assets"
