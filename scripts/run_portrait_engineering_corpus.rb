#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "support/portrait_engineering_corpus"

def fail_contract(message)
  warn "Portrait engineering corpus failed: #{message}"
  exit 1
end

repo_root = File.expand_path("..", __dir__)
manifest_argument = ARGV.shift
output_argument = ARGV.shift
if manifest_argument.nil? || output_argument.nil? || !ARGV.empty?
  fail_contract("usage: run_portrait_engineering_corpus.rb MANIFEST OUTPUT_DIRECTORY")
end

manifest_path = File.expand_path(manifest_argument, repo_root)
fail_contract("manifest is missing") unless File.file?(manifest_path)
begin
  output_root = PortraitEngineeringCorpus.validated_output_root(
    output_argument,
    repo_root: repo_root,
  )
rescue PortraitEngineeringCorpus::ContractError => error
  fail_contract(error.message)
end
fail_contract("output directory already exists") if File.exist?(output_root)

checker = File.join(repo_root, "scripts/check_image_quality_corpus.rb")
unless system("ruby", checker, "--asset-contract-only", manifest_path, out: $stdout, err: $stderr)
  fail_contract("image quality corpus contract did not pass")
end

begin
  manifest = YAML.safe_load(File.read(manifest_path), permitted_classes: [], aliases: false)
rescue Psych::Exception => error
  fail_contract("manifest YAML is invalid: #{error.message}")
end
begin
  PortraitEngineeringCorpus.validate_manifest!(manifest)
rescue PortraitEngineeringCorpus::ContractError => error
  fail_contract(error.message)
end
assets = manifest.fetch("assets")
corpus_root = File.expand_path(manifest.fetch("corpus_root"), repo_root)

renderer_source = File.join(
  repo_root,
  "scripts/support/render_portrait_engineering_candidate.swift",
)
retoucher_source = File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift")
runner_source = File.expand_path(__FILE__)
contract_source = File.join(repo_root, "scripts/support/portrait_engineering_corpus.rb")
report_assets = []
quality_root = File.join(repo_root, ".quality")
FileUtils.mkdir_p(quality_root)
begin
  PortraitEngineeringCorpus.validate_output_ancestry!(
    output_root,
    repo_root: repo_root,
  )
rescue PortraitEngineeringCorpus::ContractError => error
  fail_contract(error.message)
end

Dir.mktmpdir(".portrait-engineering-", quality_root) do |temporary_root|
  renderer = File.join(temporary_root, "portrait-engineering-renderer")
  staged_output_root = File.join(temporary_root, "outputs")
  stdout, stderr, status = Open3.capture3(
    "/usr/bin/xcrun",
    "swiftc",
    "-parse-as-library",
    retoucher_source,
    renderer_source,
    "-o",
    renderer,
  )
  fail_contract("renderer compilation failed: #{stderr.lines.first&.strip || stdout.lines.first&.strip}") unless status.success?

  identity_stdout, identity_stderr, identity_status = Open3.capture3(renderer, "identity")
  fail_contract("candidate identity failed: #{identity_stderr.lines.first&.strip}") unless identity_status.success?
  begin
    candidate_identity = JSON.parse(identity_stdout)
  rescue JSON::ParserError
    fail_contract("candidate identity was not JSON")
  end

  FileUtils.mkdir_p(staged_output_root)
  assets.each_with_index do |asset, index|
    fail_contract("assets[#{index}] must be a mapping") unless asset.is_a?(Hash)
    asset_id = asset.fetch("id")
    tags = asset.fetch("tags")
    source_path = File.expand_path(asset.fetch("file"), corpus_root)
    destination = File.join(staged_output_root, asset_id)
    render_stdout, render_stderr, render_status = Open3.capture3(
      renderer,
      source_path,
      destination,
    )
    unless render_status.success?
      detail = render_stderr.lines.first&.strip || render_stdout.lines.first&.strip
      fail_contract("#{asset_id} render failed: #{detail}")
    end
    begin
      effect_metrics = JSON.parse(render_stdout)
    rescue JSON::ParserError
      fail_contract("#{asset_id} effect metrics were not JSON")
    end

    output_files = {
      "baseline" => File.join(destination, "baseline.jpg"),
      "off" => File.join(destination, "off.jpg"),
      "default" => File.join(destination, "default.jpg"),
      "high_safe" => File.join(destination, "high-safe.jpg"),
    }
    output_hashes = output_files.transform_values do |path|
      fail_contract("#{asset_id} output is missing") unless File.file?(path)
      Digest::SHA256.file(path).hexdigest
    end
    begin
      classification = PortraitEngineeringCorpus.classify_hashes(output_hashes)
      PortraitEngineeringCorpus.validate_classification!(
        asset_id: asset_id,
        tags: tags,
        classification: classification,
      )
      PortraitEngineeringCorpus.validate_effect_metrics!(
        asset_id: asset_id,
        classification: classification,
        metrics: effect_metrics,
      )
    rescue PortraitEngineeringCorpus::ContractError => error
      fail_contract(error.message)
    end

    expected_width = asset.fetch("media").fetch("width")
    expected_height = asset.fetch("media").fetch("height")
    if (5..8).cover?(asset.fetch("media").fetch("orientation"))
      expected_width, expected_height = expected_height, expected_width
    end
    output_files.each_value do |path|
      probe_stdout, probe_stderr, probe_status = Open3.capture3(
        "sips",
        "-g", "pixelWidth",
        "-g", "pixelHeight",
        "-g", "format",
        "-g", "profile",
        path,
      )
      fail_contract("#{asset_id} output probe failed: #{probe_stderr.lines.first&.strip}") unless probe_status.success?
      width = Integer(probe_stdout[/pixelWidth:\s+(\d+)/, 1], exception: false)
      height = Integer(probe_stdout[/pixelHeight:\s+(\d+)/, 1], exception: false)
      format = probe_stdout[/format:\s+(\S+)/, 1]
      profile = probe_stdout[/profile:\s+(.+)/, 1]&.strip
      unless width == expected_width && height == expected_height
        fail_contract("#{asset_id} output dimensions changed")
      end
      fail_contract("#{asset_id} output must be JPEG") unless format == "jpeg"
      fail_contract("#{asset_id} output must be sRGB") unless profile&.match?(/sRGB/i)
    end

    report_assets << {
      "id" => asset_id,
      "source_sha256" => asset.fetch("sha256"),
      "classification" => classification,
      "output_sha256" => output_hashes,
      "effect_metrics" => effect_metrics,
    }
  end

  counts = report_assets.group_by { |asset| asset.fetch("classification") }
    .transform_values(&:length)
  report = {
    "schema" => 3,
    "engineering_only" => true,
    "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
    "retoucher_source_sha256" => Digest::SHA256.file(retoucher_source).hexdigest,
    "renderer_source_sha256" => Digest::SHA256.file(renderer_source).hexdigest,
    "runner_source_sha256" => Digest::SHA256.file(runner_source).hexdigest,
    "contract_source_sha256" => Digest::SHA256.file(contract_source).hexdigest,
    "candidate" => candidate_identity,
    "asset_count" => report_assets.length,
    "counts" => {
      "applied" => counts.fetch("applied", 0),
      "preserved" => counts.fetch("preserved", 0),
    },
    "assets" => report_assets,
  }
  File.write(
    File.join(staged_output_root, "engineering-report.json"),
    JSON.pretty_generate(report) + "\n",
  )
  FileUtils.mkdir_p(File.dirname(output_root))
  FileUtils.mv(staged_output_root, output_root)
end

puts "Portrait engineering corpus passed: #{report_assets.length} assets"
