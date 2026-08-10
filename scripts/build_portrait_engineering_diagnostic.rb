#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "support/portrait_engineering_corpus"

def fail_diagnostic(message)
  warn "Portrait engineering diagnostic build failed: #{message}"
  exit 1
end

report_argument = ARGV.shift
manifest_argument = ARGV.shift
output_argument = ARGV.shift
seed = "portrait-engineering-diagnostic"
if ARGV.first == "--seed"
  ARGV.shift
  seed = ARGV.shift
end
unless report_argument && manifest_argument && output_argument && ARGV.empty? &&
       seed.is_a?(String) && !seed.empty?
  fail_diagnostic(
    "usage: build_portrait_engineering_diagnostic.rb REPORT MANIFEST OUTPUT [--seed SEED]",
  )
end

repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
FileUtils.mkdir_p(quality_root)
quality_root_real = File.realpath(quality_root)

resolve_quality_path = lambda do |path, require_file: false|
  expanded = File.expand_path(path, repo_root)
  return nil if require_file && !File.file?(expanded)

  real = File.realpath(expanded)
  return nil unless real.start_with?("#{quality_root_real}/")

  real
rescue SystemCallError
  nil
end

report_path = resolve_quality_path.call(report_argument, require_file: true)
manifest_path = resolve_quality_path.call(manifest_argument, require_file: true)
fail_diagnostic("report must be a file inside .quality") unless report_path
fail_diagnostic("manifest must be a file inside .quality") unless manifest_path

output_path = File.expand_path(output_argument, repo_root)
fail_diagnostic("output already exists") if File.exist?(output_path)
output_parent = File.dirname(output_path)
fail_diagnostic("output parent must exist") unless File.directory?(output_parent)
begin
  output_parent_real = File.realpath(output_parent)
rescue SystemCallError
  fail_diagnostic("output parent could not be resolved")
end
unless output_parent_real == quality_root_real ||
       output_parent_real.start_with?("#{quality_root_real}/")
  fail_diagnostic("output must remain inside .quality")
end
unless output_parent_real == File.expand_path(output_parent)
  fail_diagnostic("output parent must not resolve through a symlink")
end

begin
  report = JSON.parse(File.read(report_path))
rescue JSON::ParserError => error
  fail_diagnostic("report is invalid JSON: #{error.message}")
end
begin
  manifest = YAML.safe_load(File.read(manifest_path), permitted_classes: [], aliases: false)
rescue Psych::Exception => error
  fail_diagnostic("manifest is invalid YAML: #{error.message}")
end

begin
  PortraitEngineeringCorpus.validate_manifest!(manifest)
rescue PortraitEngineeringCorpus::ContractError => error
  fail_diagnostic(error.message)
end
  fail_diagnostic("report schema must equal 4") unless report.is_a?(Hash) && report["schema"] == 4
fail_diagnostic("report must remain engineering-only") unless report["engineering_only"] == true
unless report["manifest_sha256"] == Digest::SHA256.file(manifest_path).hexdigest
  fail_diagnostic("report does not bind the supplied manifest")
end

source_contract = {
  "retoucher_source_sha256" => File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift"),
  "renderer_source_sha256" => File.join(
    repo_root,
    "scripts/support/render_portrait_engineering_candidate.swift",
  ),
  "metrics_source_sha256" => File.join(
    repo_root,
    "scripts/support/portrait_engineering_metrics.swift",
  ),
  "runner_source_sha256" => File.join(repo_root, "scripts/run_portrait_engineering_corpus.rb"),
  "contract_source_sha256" => File.join(
    repo_root,
    "scripts/support/portrait_engineering_corpus.rb",
  ),
}
source_contract.each do |field, path|
  unless report[field] == Digest::SHA256.file(path).hexdigest
    fail_diagnostic("report #{field} is stale")
  end
end

report_assets = report["assets"]
unless report["asset_count"] == PortraitEngineeringCorpus::REQUIRED_ASSET_COUNT &&
       report_assets.is_a?(Array) &&
       report_assets.length == PortraitEngineeringCorpus::REQUIRED_ASSET_COUNT
  fail_diagnostic("report must contain exactly 48 assets")
end
manifest_assets = PortraitEngineeringCorpus.engineering_assets(manifest)
  .to_h { |asset| [asset.fetch("id"), asset] }
candidate_identity = report["candidate"]
unless candidate_identity.is_a?(Hash) &&
       candidate_identity["candidateKind"].is_a?(String) &&
       !candidate_identity["candidateKind"].empty? &&
       candidate_identity["effectVersion"].is_a?(String) &&
       !candidate_identity["effectVersion"].empty? &&
       candidate_identity["strengths"] == {
         "default" => 0.35,
         "high-safe" => 0.55,
         "off" => 0,
       }
  fail_diagnostic("report candidate identity and frozen strengths are incomplete")
end
report_root = File.dirname(report_path)
seen_ids = {}
validated_assets = report_assets.map.with_index do |asset, index|
  fail_diagnostic("assets[#{index}] must be a mapping") unless asset.is_a?(Hash)
  asset_id = asset["id"]
  unless asset_id.is_a?(String) && asset_id.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
    fail_diagnostic("assets[#{index}].id is invalid")
  end
  fail_diagnostic("duplicate report asset: #{asset_id}") if seen_ids[asset_id]
  seen_ids[asset_id] = true
  manifest_asset = manifest_assets[asset_id]
  fail_diagnostic("#{asset_id} is absent from the manifest") unless manifest_asset
  source_sha256 = asset["source_sha256"]
  unless source_sha256.is_a?(String) &&
         source_sha256.match?(/\A[0-9a-f]{64}\z/) &&
         source_sha256 == manifest_asset["sha256"]
    fail_diagnostic("#{asset_id} source_sha256 does not match the manifest")
  end
  media = manifest_asset["media"]
  unless media.is_a?(Hash) &&
         media["width"].is_a?(Integer) && media["width"] > 0 &&
         media["height"].is_a?(Integer) && media["height"] > 0 &&
         media["orientation"].is_a?(Integer) && media["orientation"].between?(1, 8)
    fail_diagnostic("#{asset_id} manifest media identity is incomplete")
  end
  expected_width = media.fetch("width")
  expected_height = media.fetch("height")
  if media.fetch("orientation").between?(5, 8)
    expected_width, expected_height = expected_height, expected_width
  end

  files = {
    "baseline" => "baseline.jpg",
    "off" => "off.jpg",
    "default" => "default.jpg",
    "high_safe" => "high-safe.jpg",
  }.to_h do |variant, file|
    candidate = File.join(report_root, asset_id, file)
    resolved = resolve_quality_path.call(candidate, require_file: true)
    fail_diagnostic("#{asset_id} #{variant} output is missing or unsafe") unless resolved
    expected_hash = asset.dig("output_sha256", variant)
    unless expected_hash.is_a?(String) &&
           expected_hash.match?(/\A[0-9a-f]{64}\z/) &&
           Digest::SHA256.file(resolved).hexdigest == expected_hash
      fail_diagnostic("#{asset_id} #{variant} output hash does not match the report")
    end
    probe_stdout, probe_stderr, probe_status = Open3.capture3(
      "sips",
      "-g", "pixelWidth",
      "-g", "pixelHeight",
      "-g", "format",
      "-g", "profile",
      "-g", "orientation",
      resolved,
    )
    width = Integer(probe_stdout[/pixelWidth:\s+(\d+)/, 1], exception: false)
    height = Integer(probe_stdout[/pixelHeight:\s+(\d+)/, 1], exception: false)
    format = probe_stdout[/format:\s+(\S+)/, 1]
    profile = probe_stdout[/profile:\s+(.+)/, 1]&.strip
    orientation = probe_stdout[/orientation:\s+(.+)/, 1]&.strip
    unless probe_status.success? && format == "jpeg" &&
           width == expected_width && height == expected_height &&
           profile&.match?(/sRGB/i) && [nil, "<nil>", "1"].include?(orientation)
      detail = probe_stderr.lines.first&.strip
      fail_diagnostic(
        "#{asset_id} #{variant} output must be an orientation-normalized #{expected_width}x#{expected_height} sRGB JPEG#{": #{detail}" if detail}",
      )
    end
    [variant, resolved]
  end
  begin
    classification = PortraitEngineeringCorpus.classify_hashes(asset.fetch("output_sha256"))
    unless classification == asset["classification"]
      raise PortraitEngineeringCorpus::ContractError,
            "#{asset_id} classification does not match its output hashes"
    end
    PortraitEngineeringCorpus.validate_classification!(
      asset_id: asset_id,
      tags: manifest_asset.fetch("tags"),
      classification: classification,
    )
    PortraitEngineeringCorpus.validate_effect_metrics!(
      asset_id: asset_id,
      classification: classification,
      metrics: asset["effect_metrics"],
    )
  rescue KeyError, PortraitEngineeringCorpus::ContractError => error
    fail_diagnostic(error.message)
  end
  {
    "asset_id" => asset_id,
    "classification" => asset.fetch("classification"),
    "tags" => manifest_asset.fetch("tags"),
    "files" => files,
    "effect_metrics" => asset.fetch("effect_metrics"),
  }
end
unless seen_ids.keys.sort == manifest_assets.keys.sort
  fail_diagnostic("report and manifest asset identities differ")
end
actual_counts = validated_assets.group_by { |asset| asset.fetch("classification") }
  .transform_values(&:length)
expected_counts = {
  "applied" => actual_counts.fetch("applied", 0),
  "preserved" => actual_counts.fetch("preserved", 0),
}
fail_diagnostic("report classification counts are inconsistent") unless report["counts"] == expected_counts

seed_value = Digest::SHA256.digest(seed).unpack1("Q>")
random = Random.new(seed_value)
ordered_assets = validated_assets.shuffle(random: random)
review_max_edge = 2_048

Dir.mktmpdir(".portrait-diagnostic-", quality_root_real) do |temporary_root|
  staging = File.join(temporary_root, "output")
  FileUtils.mkdir_p(staging)
  participant = File.join(staging, "participant-package")
  image_directory = File.join(participant, "images")
  FileUtils.mkdir_p(image_directory)
  metric_renderer = File.join(temporary_root, "portrait-engineering-metrics")
  metric_stdout, metric_stderr, metric_status = Open3.capture3(
    "/usr/bin/xcrun",
    "swiftc",
    "-parse-as-library",
    File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift"),
    File.join(repo_root, "scripts/support/portrait_engineering_metrics.swift"),
    File.join(repo_root, "scripts/support/render_portrait_engineering_candidate.swift"),
    "-o",
    metric_renderer,
  )
  unless metric_status.success?
    detail = metric_stderr.lines.first&.strip || metric_stdout.lines.first&.strip
    fail_diagnostic("effect metric verifier could not compile: #{detail}")
  end
  sanitizer = File.join(temporary_root, "sanitize-review-image")
  sanitizer_source = File.join(repo_root, "scripts/support/sanitize_review_image.swift")
  _stdout, sanitizer_stderr, sanitizer_status = Open3.capture3(
    "/usr/bin/xcrun",
    "swiftc",
    sanitizer_source,
    "-o",
    sanitizer,
  )
  unless sanitizer_status.success?
    fail_diagnostic("review image sanitizer could not compile: #{sanitizer_stderr.strip}")
  end
  sanitize = lambda do |source, destination, label|
    stdout, stderr, status = Open3.capture3(
      sanitizer,
      source,
      destination,
      "--max-edge",
      review_max_edge.to_s,
    )
    fail_diagnostic("could not sanitize #{label}: #{stderr.strip}") unless status.success?
    pixel_sha256 = stdout.strip
    unless pixel_sha256.match?(/\A[0-9a-f]{64}\z/)
      fail_diagnostic("sanitizer did not return a normalized pixel SHA-256 for #{label}")
    end
    pixel_sha256
  end
  key_items = []
  cards = ordered_assets.map.with_index do |asset, item_index|
    item_code = format("P%02d", item_index + 1)
    metric_stdout, metric_stderr, metric_status = Open3.capture3(
      metric_renderer,
      "metrics",
      asset.dig("files", "baseline"),
      asset.dig("files", "off"),
      asset.dig("files", "default"),
      asset.dig("files", "high_safe"),
    )
    fail_diagnostic("#{asset.fetch("asset_id")} effect metrics could not be recomputed: #{metric_stderr.strip}") unless metric_status.success?
    begin
      recomputed_metrics = JSON.parse(metric_stdout)
    rescue JSON::ParserError
      fail_diagnostic("#{asset.fetch("asset_id")} recomputed effect metrics were invalid")
    end
    unless recomputed_metrics == asset.fetch("effect_metrics")
      fail_diagnostic("#{asset.fetch("asset_id")} effect metrics do not match final JPEG pixels")
    end
    baseline_name = format("%s-anchor.png", item_code.downcase)
    baseline_destination = File.join(image_directory, baseline_name)
    baseline_pixel_sha256 = sanitize.call(
      asset.dig("files", "baseline"),
      baseline_destination,
      "#{item_code} baseline",
    )
    variants = %w[off default high_safe].shuffle(random: random)
    variant_pixel_hashes = {}
    candidate_cells = variants.map.with_index do |variant, candidate_index|
      candidate_code = (65 + candidate_index).chr
      file_name = format("%s-%s.png", item_code.downcase, candidate_code.downcase)
      destination = File.join(image_directory, file_name)
      variant_pixel_hashes[variant] = sanitize.call(
        asset.dig("files", variant),
        destination,
        "#{item_code} candidate #{candidate_code}",
      )
      <<~HTML
        <figure>
          <a href="images/#{file_name}" target="_blank" rel="noopener">
            <img src="images/#{file_name}" alt="#{item_code} 候选 #{candidate_code}" loading="lazy">
          </a>
          <figcaption>候选 #{candidate_code}</figcaption>
        </figure>
      HTML
    end
    unless variant_pixel_hashes.fetch("off") == baseline_pixel_sha256
      fail_diagnostic("#{asset.fetch("asset_id")} off pixels differ from baseline")
    end
    pixel_hashes = [
      baseline_pixel_sha256,
      variant_pixel_hashes.fetch("default"),
      variant_pixel_hashes.fetch("high_safe"),
    ]
    if asset.fetch("classification") == "preserved"
      fail_diagnostic("#{asset.fetch("asset_id")} preserved pixels changed") unless pixel_hashes.uniq.length == 1
    elsif pixel_hashes.uniq.length != 3
      fail_diagnostic("#{asset.fetch("asset_id")} applied variants are not pixel-distinct")
    end
    key_items << {
      "item_code" => item_code,
      "asset_id" => asset.fetch("asset_id"),
      "classification" => asset.fetch("classification"),
      "tags" => asset.fetch("tags"),
      "baseline" => {
        "normalized_pixel_sha256" => baseline_pixel_sha256,
        "normalized_raster_sha256" => Digest::SHA256.file(baseline_destination).hexdigest,
      },
      "candidates" => variants.map.with_index do |variant, candidate_index|
        file_name = format("%s-%s.png", item_code.downcase, (65 + candidate_index).chr.downcase)
        destination = File.join(image_directory, file_name)
        {
          "candidate_code" => (65 + candidate_index).chr,
          "variant" => variant,
          "normalized_pixel_sha256" => variant_pixel_hashes.fetch(variant),
          "normalized_raster_sha256" => Digest::SHA256.file(destination).hexdigest,
        }
      end,
    }
    <<~HTML
      <section class="item">
        <h2>#{item_code}</h2>
        <div class="grid">
          <figure class="anchor">
            <a href="images/#{baseline_name}" target="_blank" rel="noopener">
              <img src="images/#{baseline_name}" alt="#{item_code} 原图锚点" loading="lazy">
            </a>
            <figcaption>原图锚点</figcaption>
          </figure>
          #{candidate_cells.join("\n")}
        </div>
        <label><input type="checkbox"> 已检查皮肤、五官、头发、背景边缘与局部 halo</label>
      </section>
    HTML
  end
  candidate = candidate_identity
  title = "映见人像候选工程诊断"
  html = <<~HTML
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{CGI.escapeHTML(title)}</title>
      <style>
        :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
        body { margin: 0 auto; max-width: 1180px; padding: 24px; line-height: 1.5; }
        .notice { border: 2px solid #d97706; border-radius: 16px; padding: 16px; background: color-mix(in srgb, #f59e0b 12%, Canvas); }
        .item { margin: 32px 0; padding-top: 16px; border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent); }
        .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
        figure { margin: 0; }
        img { width: 100%; height: auto; display: block; border-radius: 12px; background: #777; }
        figcaption { padding: 6px 2px 12px; font-weight: 600; }
        .anchor figcaption { color: #2563eb; }
        label { display: block; padding: 12px 0; }
        @media (max-width: 680px) { body { padding: 14px; } .grid { grid-template-columns: 1fr; } }
      </style>
    </head>
    <body>
      <h1>#{CGI.escapeHTML(title)}</h1>
      <div class="notice">
        <strong>仅限工程诊断，不能用于冻结生产候选。</strong>
        本包没有竞品同路径、五名独立评审或物理设备证据；请勿据此开启生产人像入口。
      </div>
      <p>候选已随机化。逐项比较原图锚点与 A/B/C，重点检查自然度、身份、皮肤纹理、五官保护、非皮肤区域和边界。</p>
      #{cards.join("\n")}
    </body>
    </html>
  HTML
  File.write(File.join(participant, "index.html"), html)
  key = {
    "schema" => 1,
    "engineering_only" => true,
    "evidence_scope" => "local-desktop-engineering",
    "physical_device" => false,
    "freeze_eligible" => false,
    "review_max_edge" => review_max_edge,
    "seed_sha256" => Digest::SHA256.hexdigest(seed),
    "candidate" => candidate,
    "report_sha256" => Digest::SHA256.file(report_path).hexdigest,
    "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
    "items" => key_items,
  }
  File.write(File.join(staging, "diagnostic-key.json"), JSON.pretty_generate(key) + "\n")
  FileUtils.mv(staging, output_path)
end

puts "Portrait engineering diagnostic built: #{output_path}"
