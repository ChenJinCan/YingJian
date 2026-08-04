#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"
require "yaml"
require_relative "support/portrait_capture_contract"

def fail_plan(message)
  warn "Portrait review plan build failed: #{message}"
  exit 1
end

intake_argument = ARGV.shift
output_argument = ARGV.shift
fail_plan("usage: build_portrait_review_plan.rb INTAKE OUTPUT") unless intake_argument && output_argument && ARGV.empty?

repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
FileUtils.mkdir_p(quality_root)
quality_root_real = File.realpath(quality_root)
intake_path = File.expand_path(intake_argument)
output_path = File.expand_path(output_argument)

def inside_quality_file?(path, quality_root)
  File.file?(path) && File.realpath(path).start_with?("#{quality_root}/")
rescue SystemCallError
  false
end

def concrete_string?(value)
  value.is_a?(String) && !value.strip.empty? && value !~ /\A(?:replace_with|unknown\z|not[-_]recorded\z)/i
end

def concrete_parameters?(value)
  case value
  when Hash
    !value.empty? && value.all? do |key, child|
      concrete_string?(key) && concrete_parameters?(child)
    end
  when Array
    !value.empty? && value.all? { |child| concrete_parameters?(child) }
  when String
    concrete_string?(value)
  when Numeric
    value.finite?
  when TrueClass, FalseClass
    true
  else
    false
  end
end

fail_plan("intake must remain inside the ignored .quality directory") unless inside_quality_file?(intake_path, quality_root_real)
intake_path = File.realpath(intake_path)
fail_plan("output already exists") if File.exist?(output_path)
output_parent = File.dirname(output_path)
fail_plan("output parent is missing") unless File.directory?(output_parent)
begin
  output_parent_real = File.realpath(output_parent)
rescue SystemCallError
  fail_plan("output parent could not be resolved")
end
unless output_parent_real == quality_root_real || output_parent_real.start_with?("#{quality_root_real}/")
  fail_plan("output must remain inside the ignored .quality directory")
end
unless output_parent_real == File.expand_path(output_parent)
  fail_plan("output parent must not resolve through a symlink")
end

begin
  intake = YAML.safe_load(File.read(intake_path), permitted_classes: [], aliases: false)
rescue Psych::Exception => error
  fail_plan("intake is invalid YAML: #{error.message}")
end
fail_plan("intake must be a mapping") unless intake.is_a?(Hash)
fail_plan("schema must equal 1") unless intake["schema"] == 1
review_id = intake["review_id"]
minimum_reviewers = intake["minimum_reviewers"]
items = intake["items"]
fail_plan("review_id must use lowercase letters, digits, dashes, or underscores") unless review_id.is_a?(String) && review_id.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
fail_plan("minimum_reviewers must be at least 5") unless minimum_reviewers.is_a?(Integer) && minimum_reviewers >= 5
fail_plan("items must be a non-empty list") unless items.is_a?(Array) && !items.empty?

intake_directory = File.dirname(intake_path)
asset_ids = {}
raw_source_hashes = {}
capture_manifest_hashes = {}
baseline_hashes = {}
competitor_hashes = {}
round_signature = nil
begin
  plan_items = items.map.with_index do |item, index|
  prefix = "items[#{index}]"
  fail_plan("#{prefix} must be a mapping") unless item.is_a?(Hash)
  asset_id = item["asset_id"]
  tags = item["tags"]
  fail_plan("#{prefix}.asset_id is invalid") unless asset_id.is_a?(String) && asset_id.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
  fail_plan("duplicate asset_id: #{asset_id}") if asset_ids[asset_id]
  asset_ids[asset_id] = true
  unless tags.is_a?(Array) && !tags.empty? && tags.all? { |tag| tag.is_a?(String) && tag.match?(/\A[a-z0-9][a-z0-9_-]*\z/) }
    fail_plan("#{prefix}.tags must be a non-empty normalized string list")
  end
  fail_plan("#{prefix}.tags must not contain duplicates") unless tags.uniq.length == tags.length

  manifest_value = item["capture_manifest"]
  fail_plan("#{prefix}.capture_manifest must be a non-empty path") unless manifest_value.is_a?(String) && !manifest_value.empty?
  manifest_path = Pathname.new(manifest_value).absolute? ? manifest_value : File.expand_path(manifest_value, intake_directory)
  begin
    capture = PortraitCaptureContract.validate(
      manifest_path,
      quality_root: quality_root_real,
      require_physical: true,
    )
  rescue PortraitCaptureContract::ValidationError, SystemCallError => error
    fail_plan("#{prefix}.capture_manifest: #{error.message}")
  end
  manifest = capture.fetch("manifest")
  outputs = capture.fetch("outputs")
  raw_source_hash = manifest["rawSourceSha256"]
  fail_plan("duplicate raw source for #{asset_id}") if raw_source_hashes[raw_source_hash]
  raw_source_hashes[raw_source_hash] = true
  manifest_hash = capture["manifest_sha256"]
  fail_plan("duplicate capture manifest for #{asset_id}") if capture_manifest_hashes[manifest_hash]
  capture_manifest_hashes[manifest_hash] = true
  baseline_output_hash = outputs.fetch("baselineOriginal").fetch("sha256")
  fail_plan("duplicate baseline output for #{asset_id}") if baseline_hashes[baseline_output_hash]
  baseline_hashes[baseline_output_hash] = true

  source = item["source"]
  competitor = item["competitor"]
  fail_plan("#{prefix}.source must be a mapping") unless source.is_a?(Hash)
  fail_plan("#{prefix}.competitor must be a mapping") unless competitor.is_a?(Hash)
  %w[version device os].each do |field|
    value = source[field]
    fail_plan("#{prefix}.source.#{field} must be a concrete string") unless concrete_string?(value)
  end
  %w[file version device os operation_path sha256].each do |field|
    value = competitor[field]
    fail_plan("#{prefix}.competitor.#{field} must be a concrete string") unless concrete_string?(value)
  end
  fail_plan("#{prefix}.competitor.parameters must contain concrete values") unless concrete_parameters?(competitor["parameters"])
  unless competitor["device"] == manifest["device"] && competitor["os"] == manifest["os"]
    fail_plan("#{prefix}.competitor must use the same device and OS as the Yingjian capture")
  end

  competitor_path = Pathname.new(competitor["file"]).absolute? ? competitor["file"] : File.expand_path(competitor["file"], intake_directory)
  unless inside_quality_file?(competitor_path, quality_root_real)
    fail_plan("#{prefix}.competitor.file must remain inside the ignored .quality directory")
  end
  unless competitor["sha256"].match?(PortraitCaptureContract::SHA256)
    fail_plan("#{prefix}.competitor.sha256 must be a lowercase SHA-256")
  end
  competitor_sha256 = Digest::SHA256.file(competitor_path).hexdigest
  unless competitor_sha256 == competitor["sha256"]
    fail_plan("#{prefix}.competitor.sha256 does not match the file")
  end
  fail_plan("duplicate competitor output for #{asset_id}") if competitor_hashes[competitor_sha256]
  competitor_hashes[competitor_sha256] = true
  competitor_media = PortraitCaptureContract.probe_image(competitor_path, "#{prefix}.competitor.file")
  source_dimensions = [manifest["sourceWidth"], manifest["sourceHeight"]]
  unless %w[jpeg png].include?(competitor_media[:format]) && competitor_media[:color_space] == "srgb" &&
      competitor_media[:orientation] == 1 && [competitor_media[:width], competitor_media[:height]] == source_dimensions
    fail_plan("#{prefix}.competitor.file must be an orientation-1 sRGB JPEG/PNG at #{source_dimensions.join("x")}")
  end

  item_signature = {
    "candidate_kind" => manifest["candidateKind"],
    "effect_version" => manifest["effectVersion"],
    "app_version" => manifest["appVersion"],
    "app_build" => manifest["appBuild"],
    "device" => manifest["device"],
    "os" => manifest["os"],
    "default_strength" => manifest["defaultStrength"],
    "high_safe_strength" => manifest["highSafeStrength"],
    "competitor_version" => competitor["version"],
    "competitor_parameters" => competitor["parameters"],
    "competitor_operation_path" => competitor["operation_path"],
  }
  round_signature ||= item_signature
  unless item_signature == round_signature
    fail_plan("#{prefix} does not share the frozen Yingjian and competitor round configuration")
  end

  baseline_hash = baseline_output_hash
  manifest_identity = {
    "candidate_kind" => manifest["candidateKind"],
    "app_version" => manifest["appVersion"],
    "app_build" => manifest["appBuild"],
    "execution_environment" => manifest["executionEnvironment"],
    "captured_at_utc" => manifest["capturedAtUtc"],
    "raw_source_sha256" => manifest["rawSourceSha256"],
    "capture_manifest_sha256" => capture["manifest_sha256"],
  }
  relative_file = lambda do |path|
    Pathname.new(path).relative_path_from(Pathname.new(output_parent_real)).to_s
  end
  candidate = lambda do |id, role, output_name, strength|
    output = outputs.fetch(output_name)
    {
      "id" => id,
      "role" => role,
      "file" => relative_file.call(output.fetch("path")),
      "sha256" => output.fetch("sha256"),
      "provenance" => {
        "producer" => "yingjian",
        "version" => manifest["effectVersion"],
        "device" => manifest["device"],
        "os" => manifest["os"],
        "variant" => output.fetch("variant"),
        "render_kind" => output.fetch("renderKind"),
        "source_sha256" => baseline_hash,
        "parameters" => manifest_identity.merge("strength" => strength),
      },
    }
  end

  baseline = outputs.fetch("baselineOriginal")
  {
    "asset_id" => asset_id,
    "tags" => tags.uniq.sort,
    "candidates" => [
      {
        "id" => "original",
        "role" => "baseline_original",
        "file" => relative_file.call(baseline.fetch("path")),
        "sha256" => baseline_hash,
        "provenance" => {
          "producer" => "original",
          "version" => source["version"],
          "device" => source["device"],
          "os" => source["os"],
          "variant" => "original",
          "render_kind" => "source",
          "parameters" => {
            "raw_source_sha256" => manifest["rawSourceSha256"],
            "source_width" => manifest["sourceWidth"],
            "source_height" => manifest["sourceHeight"],
          },
        },
      },
      candidate.call("yingjian-off-export", "subject", "offExport", 0),
      candidate.call("yingjian-default-export", "subject", "defaultExport", manifest["defaultStrength"]),
      candidate.call("yingjian-high-safe-export", "subject", "highSafeExport", manifest["highSafeStrength"]),
      candidate.call("yingjian-default-preview", "subject", "defaultPreview", manifest["defaultStrength"]),
      {
        "id" => "competitor-fixed-path-export",
        "role" => "reference",
        "file" => relative_file.call(competitor_path),
        "sha256" => competitor_sha256,
        "provenance" => {
          "producer" => "competitor",
          "version" => competitor["version"],
          "device" => competitor["device"],
          "os" => competitor["os"],
          "variant" => "fixed_path",
          "render_kind" => "export",
          "source_sha256" => baseline_hash,
          "parameters" => competitor["parameters"],
          "operation_path" => competitor["operation_path"],
        },
      },
    ],
  }
  end
rescue PortraitCaptureContract::ValidationError, SystemCallError => error
  fail_plan(error.message)
end

plan = {
  "schema" => 1,
  "review_id" => review_id,
  "task" => "portrait",
  "minimum_reviewers" => minimum_reviewers,
  "items" => plan_items.sort_by { |item| item["asset_id"] },
}

temporary_path = "#{output_path}.tmp-#{Process.pid}"
begin
  File.write(temporary_path, YAML.dump(plan))
  File.rename(temporary_path, output_path)
ensure
  File.delete(temporary_path) if File.exist?(temporary_path)
end
puts "Portrait review plan built: #{output_path} (#{plan_items.length} items)"
