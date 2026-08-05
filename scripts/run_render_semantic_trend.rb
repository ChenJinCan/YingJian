#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "support/cross_platform_render_comparison"
require_relative "support/file_render_recipe_profile"
require_relative "support/render_semantic_trend"

def fail_contract(message)
  warn "Render semantic trend failed: #{message}"
  exit 1
end

repo_root = File.expand_path("..", __dir__)
platform = ARGV.shift
parameter = ARGV.shift
directory_arguments = 3.times.map { ARGV.shift }
output_argument = ARGV.shift
unless %w[ios android].include?(platform) &&
       FileRenderRecipeProfile::PROFILE_VALUES.key?(parameter) &&
       directory_arguments.none?(&:nil?) && output_argument && ARGV.empty?
  fail_contract(
    "usage: run_render_semantic_trend.rb PLATFORM PARAMETER NEGATIVE_DIR NEUTRAL_DIR POSITIVE_DIR OUTPUT_DIR",
  )
end

begin
  directories = directory_arguments.map do |argument|
    CrossPlatformRenderComparison.validated_quality_directory(argument, repo_root: repo_root)
  end
  output_root = CrossPlatformRenderComparison.validated_output_root(
    output_argument,
    repo_root: repo_root,
  )
  CrossPlatformRenderComparison.validate_output_ancestry!(output_root, repo_root: repo_root)
rescue CrossPlatformRenderComparison::ContractError => error
  fail_contract(error.message)
end
fail_contract("output directory already exists") if File.exist?(output_root)

profile_ids = ["#{parameter}-negative", "neutral", "#{parameter}-positive"]
reports = directories.zip(profile_ids).map do |directory, expected_profile|
  report_path = File.join(directory, "engineering-report.json")
  fail_contract("#{expected_profile} engineering report is missing") unless File.file?(report_path)
  begin
    report = JSON.parse(File.read(report_path))
  rescue JSON::ParserError
    fail_contract("#{expected_profile} engineering report is not JSON")
  end
  unless report["schema"] == 1 && report["engineering_only"] == true &&
         report["recipe_profile"] == expected_profile && report["asset_count"] == 48
    fail_contract("#{expected_profile} engineering report identity is invalid")
  end
  expected_recipe = FileRenderRecipeProfile.fetch(expected_profile)
  expected_recipe_hash = Digest::SHA256.hexdigest(JSON.generate(expected_recipe))
  unless report["recipe"] == expected_recipe && report["recipe_sha256"] == expected_recipe_hash
    fail_contract("#{expected_profile} recipe identity differs from the frozen catalog")
  end
  [report_path, report]
end
unless reports.map { |_, report| report["manifest_sha256"] }.uniq.length == 1
  fail_contract("trend reports do not bind the same corpus manifest")
end

indexed_reports = reports.zip(profile_ids).map do |(_, report), profile_id|
  begin
    CrossPlatformRenderComparison.index_assets!(report, platform: "#{platform}-#{profile_id}")
  rescue CrossPlatformRenderComparison::ContractError => error
    fail_contract(error.message)
  end
end
asset_ids = indexed_reports.first.keys
unless indexed_reports.all? { |indexed| indexed.keys == asset_ids }
  fail_contract("trend reports do not contain the same ordered assets")
end

analyzer_source = File.join(repo_root, "scripts/support/measure_render_semantics.swift")
fail_contract("semantic analyzer source is missing") unless File.file?(analyzer_source)
quality_root = File.join(repo_root, ".quality")
report_assets = []
Dir.mktmpdir(".render-semantic-trend-", quality_root) do |temporary_root|
  analyzer = File.join(temporary_root, "semantic-analyzer")
  stdout, stderr, status = Open3.capture3(
    "/usr/bin/xcrun", "swiftc", "-parse-as-library", analyzer_source, "-o", analyzer,
  )
  fail_contract("semantic analyzer compilation failed: #{stderr.lines.first&.strip || stdout.lines.first&.strip}") unless status.success?

  asset_ids.each do |asset_id|
    measurements = directories.zip(indexed_reports, profile_ids).map do |directory, indexed, profile_id|
      asset = indexed.fetch(asset_id)
      output_path = File.join(directory, "#{asset_id}.jpg")
      fail_contract("#{profile_id} #{asset_id} output is missing") unless File.file?(output_path)
      expected_hash = asset.fetch("output_sha256")
      fail_contract("#{profile_id} #{asset_id} output hash changed") unless Digest::SHA256.file(output_path).hexdigest == expected_hash
      source_before = platform == "ios" ? asset.fetch("source_sha256") : asset.fetch("source_sha256_before")
      if platform == "android" && source_before != asset.fetch("source_sha256_after")
        fail_contract("#{profile_id} #{asset_id} source changed")
      end
      measurement_stdout, measurement_stderr, measurement_status = Open3.capture3(
        analyzer, output_path, "512",
      )
      unless measurement_status.success?
        fail_contract("#{profile_id} #{asset_id} measurement failed: #{measurement_stderr.lines.first&.strip}")
      end
      begin
        [source_before, JSON.parse(measurement_stdout)]
      rescue JSON::ParserError
        fail_contract("#{profile_id} #{asset_id} measurement is not JSON")
      end
    end
    unless measurements.map(&:first).uniq.length == 1
      fail_contract("#{asset_id} trend does not bind the same source")
    end
    report_assets << {
      "id" => asset_id,
      "source_sha256" => measurements.first.first,
      "negative" => measurements[0].last,
      "neutral" => measurements[1].last,
      "positive" => measurements[2].last,
    }
  end

  mean_luma_trends = report_assets.map do |asset|
    {
      "id" => asset.fetch("id"),
      "negative" => asset.dig("negative", "mean_luma"),
      "neutral" => asset.dig("neutral", "mean_luma"),
      "positive" => asset.dig("positive", "mean_luma"),
    }
  end
  violations = parameter == "exposure" ? RenderSemanticTrend.monotonic_violations(
    mean_luma_trends,
    metric: "mean_luma",
    minimum_step: 0.0,
  ) : []
  steps = mean_luma_trends.flat_map do |asset|
    [
      asset.fetch("neutral") - asset.fetch("negative"),
      asset.fetch("positive") - asset.fetch("neutral"),
    ]
  end
  report = {
    "schema" => 1,
    "engineering_only" => true,
    "observation_only" => true,
    "thresholds_frozen" => false,
    "platform" => platform,
    "parameter" => parameter,
    "profiles" => profile_ids,
    "sample_max_edge" => 512,
    "manifest_sha256" => reports.first.last.fetch("manifest_sha256"),
    "analyzer_source_sha256" => Digest::SHA256.file(analyzer_source).hexdigest,
    "runner_source_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
    "input_report_sha256" => reports.map { |path, _| Digest::SHA256.file(path).hexdigest },
    "asset_count" => report_assets.length,
    "minimum_mean_luma_step" => steps.min,
    "maximum_mean_luma_step" => steps.max,
    "strict_monotonic_violations" => violations,
    "assets" => report_assets,
  }
  staged_output = File.join(temporary_root, "output")
  FileUtils.mkdir_p(staged_output)
  File.write(
    File.join(staged_output, "observation-report.json"),
    JSON.pretty_generate(report) + "\n",
  )
  FileUtils.mkdir_p(File.dirname(output_root))
  FileUtils.mv(staged_output, output_root)
end

puts "Render semantic trend observation passed: #{platform} #{parameter}, #{report_assets.length} assets"
