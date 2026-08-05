#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"
require "yaml"
require_relative "support/portrait_capture_contract"
require_relative "support/portrait_engineering_corpus"
require_relative "support/portrait_review_contract"

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
schema = intake["schema"]
fail_plan("schema must equal 1 or 2") unless PortraitReviewContract.supported_schema?(schema)
review_id = intake["review_id"]
minimum_reviewers = intake["minimum_reviewers"]
items = intake["items"]
fail_plan("review_id must use lowercase letters, digits, dashes, or underscores") unless review_id.is_a?(String) && review_id.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
fail_plan("minimum_reviewers must be at least 5") unless minimum_reviewers.is_a?(Integer) && minimum_reviewers >= 5
fail_plan("items must be a non-empty list") unless items.is_a?(Array) && !items.empty?
intake_directory = File.dirname(intake_path)

corpus_manifest_path = nil
corpus_manifest_sha256 = nil
corpus_assets_by_id = {}
device_evidence = nil
if schema == PortraitReviewContract::MVP_SCHEMA
  corpus_manifest_value = intake["portrait_corpus_manifest"]
  unless corpus_manifest_value.is_a?(String) && !corpus_manifest_value.empty?
    fail_plan("portrait_corpus_manifest must be a non-empty path")
  end
  corpus_manifest_path = if Pathname.new(corpus_manifest_value).absolute?
    corpus_manifest_value
  else
    File.expand_path(corpus_manifest_value, intake_directory)
  end
  unless inside_quality_file?(corpus_manifest_path, quality_root_real)
    fail_plan("portrait_corpus_manifest must remain inside the ignored .quality directory")
  end
  corpus_manifest_path = File.realpath(corpus_manifest_path)
  begin
    corpus_manifest = YAML.safe_load(File.read(corpus_manifest_path), permitted_classes: [], aliases: false)
    fail_plan("portrait corpus manifest schema must equal 2") unless corpus_manifest.is_a?(Hash) && corpus_manifest["schema"] == 2
    PortraitEngineeringCorpus.validate_manifest!(corpus_manifest)
  rescue Psych::Exception, PortraitEngineeringCorpus::ContractError => error
    fail_plan("portrait corpus manifest is invalid: #{error.message}")
  end
  corpus_manifest_sha256 = Digest::SHA256.file(corpus_manifest_path).hexdigest
  corpus_assets_by_id = corpus_manifest.fetch("assets").to_h { |asset| [asset["id"], asset] }

  evidence_input = intake["device_evidence"]
  fail_plan("device_evidence must be a mapping") unless evidence_input.is_a?(Hash)
  %w[id file sha256].each do |field|
    fail_plan("device_evidence.#{field} must be a concrete string") unless concrete_string?(evidence_input[field])
  end
  evidence_path = Pathname.new(evidence_input["file"]).absolute? ? evidence_input["file"] : File.expand_path(evidence_input["file"], intake_directory)
  evidence_root = File.join(quality_root_real, "evidence")
  unless inside_quality_file?(evidence_path, evidence_root)
    fail_plan("device_evidence.file must remain inside .quality/evidence")
  end
  unless evidence_input["sha256"].match?(PortraitCaptureContract::SHA256) &&
      Digest::SHA256.file(evidence_path).hexdigest == evidence_input["sha256"]
    fail_plan("device_evidence.sha256 does not match the file")
  end
  begin
    device_record = JSON.parse(File.read(evidence_path))
  rescue JSON::ParserError => error
    fail_plan("device_evidence.file is invalid JSON: #{error.message}")
  end
  unless device_record.is_a?(Hash) && device_record["schema"] == 1 &&
      device_record["device_evidence_id"] == evidence_input["id"] &&
      concrete_string?(device_record["device"]) && concrete_string?(device_record["os"])
    fail_plan("device_evidence.file does not match the declared device evidence identity")
  end
  device_evidence = evidence_input.merge(
    "path" => File.realpath(evidence_path),
    "device" => device_record["device"],
    "os" => device_record["os"],
  )
end

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

  corpus_asset = corpus_assets_by_id[asset_id] if schema == PortraitReviewContract::MVP_SCHEMA
  if schema == PortraitReviewContract::MVP_SCHEMA
    fail_plan("#{prefix}.asset_id is missing from portrait_corpus_manifest") unless corpus_asset.is_a?(Hash)
    unless corpus_asset["sha256"] == raw_source_hash
      fail_plan("#{prefix} raw source does not match the authorized portrait corpus asset")
    end
    unless corpus_asset["tags"] == tags
      fail_plan("#{prefix}.tags must exactly match the authorized portrait corpus asset")
    end
    license = corpus_asset["license"]
    unless license.is_a?(Hash) && license["internal_review_authorized"] == true &&
        concrete_string?(license["evidence_ref"]) &&
        license["evidence_sha256"].is_a?(String) && license["evidence_sha256"].match?(PortraitCaptureContract::SHA256)
      fail_plan("#{prefix} corpus license must explicitly authorize internal review and bind evidence")
    end
    license_path = File.expand_path(license["evidence_ref"], repo_root)
    evidence_root = File.join(quality_root_real, "evidence")
    unless inside_quality_file?(license_path, evidence_root) &&
        Digest::SHA256.file(license_path).hexdigest == license["evidence_sha256"]
      fail_plan("#{prefix} corpus license evidence is missing or has changed")
    end
  end

  source = item["source"]
  fail_plan("#{prefix}.source must be a mapping") unless source.is_a?(Hash)
  %w[version device os].each do |field|
    value = source[field]
    fail_plan("#{prefix}.source.#{field} must be a concrete string") unless concrete_string?(value)
  end
  if schema == PortraitReviewContract::MVP_SCHEMA
    unless source["device_evidence_id"] == device_evidence["id"] &&
        manifest["device"] == device_evidence["device"] && manifest["os"] == device_evidence["os"]
      fail_plan("#{prefix}.source device_evidence_id, device, and os must match the frozen iPhone record")
    end
  end
  source_dimensions = [manifest["sourceWidth"], manifest["sourceHeight"]]
  competitor_inputs = if schema == 2
    competitors = item["competitors"]
    expected_competitors = PortraitReviewContract::COMPETITOR_IDENTITIES.keys.sort
    fail_plan("#{prefix}.competitors must contain exactly xingtu and berry") unless
      competitors.is_a?(Hash) && competitors.keys.sort == expected_competitors
    competitors
  else
    competitor = item["competitor"]
    fail_plan("#{prefix}.competitor must be a mapping") unless competitor.is_a?(Hash)
    { "competitor" => competitor }
  end
  competitor_records = competitor_inputs.map do |competitor_id, competitor|
    competitor_prefix = schema == 2 ? "#{prefix}.competitors.#{competitor_id}" : "#{prefix}.competitor"
    fail_plan("#{competitor_prefix} must be a mapping") unless competitor.is_a?(Hash)
    %w[file version device os operation_path sha256].each do |field|
      value = competitor[field]
      fail_plan("#{competitor_prefix}.#{field} must be a concrete string") unless concrete_string?(value)
    end
    if schema == PortraitReviewContract::MVP_SCHEMA
      begin
        PortraitReviewContract.validate_competitor_identity!(competitor_id, competitor)
      rescue PortraitReviewContract::ContractError => error
        fail_plan("#{prefix}.competitors.#{error.message}")
      end
      unless competitor["device_evidence_id"] == device_evidence["id"]
        fail_plan("#{competitor_prefix}.device_evidence_id must match the frozen iPhone record")
      end
    end
    unless concrete_parameters?(competitor["parameters"])
      fail_plan("#{competitor_prefix}.parameters must contain concrete values")
    end
    unless competitor["device"] == manifest["device"] && competitor["os"] == manifest["os"]
      fail_plan("#{competitor_prefix} must use the same device and OS as the Yingjian capture")
    end
    if schema == PortraitReviewContract::MVP_SCHEMA &&
        (competitor["device"] != device_evidence["device"] || competitor["os"] != device_evidence["os"])
      fail_plan("#{competitor_prefix} must match the frozen iPhone record")
    end
    competitor_path = if Pathname.new(competitor["file"]).absolute?
      competitor["file"]
    else
      File.expand_path(competitor["file"], intake_directory)
    end
    unless inside_quality_file?(competitor_path, quality_root_real)
      fail_plan("#{competitor_prefix}.file must remain inside the ignored .quality directory")
    end
    unless competitor["sha256"].match?(PortraitCaptureContract::SHA256)
      fail_plan("#{competitor_prefix}.sha256 must be a lowercase SHA-256")
    end
    competitor_sha256 = Digest::SHA256.file(competitor_path).hexdigest
    unless competitor_sha256 == competitor["sha256"]
      fail_plan("#{competitor_prefix}.sha256 does not match the file")
    end
    fail_plan("duplicate competitor output for #{asset_id}") if competitor_hashes[competitor_sha256]
    competitor_hashes[competitor_sha256] = true
    competitor_media = PortraitCaptureContract.probe_image(competitor_path, "#{competitor_prefix}.file")
    unless %w[jpeg png].include?(competitor_media[:format]) && competitor_media[:color_space] == "srgb" &&
        competitor_media[:orientation] == 1 && [competitor_media[:width], competitor_media[:height]] == source_dimensions
      fail_plan("#{competitor_prefix}.file must be an orientation-1 sRGB JPEG/PNG at #{source_dimensions.join("x")}")
    end
    {
      "id" => competitor_id,
      "data" => competitor,
      "path" => competitor_path,
      "sha256" => competitor_sha256,
    }
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
    "competitors" => competitor_records.to_h do |record|
      competitor = record["data"]
      [record["id"], {
        "version" => competitor["version"],
        "app_store_id" => competitor["app_store_id"],
        "bundle_id" => competitor["bundle_id"],
        "device_evidence_id" => competitor["device_evidence_id"],
        "parameters" => competitor["parameters"],
        "operation_path" => competitor["operation_path"],
      }]
    end,
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
    "device_evidence_id" => source["device_evidence_id"],
  }.compact
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
            "device_evidence_id" => source["device_evidence_id"],
          }.compact,
        },
      },
      candidate.call("yingjian-off-export", "subject", "offExport", 0),
      candidate.call("yingjian-default-export", "subject", "defaultExport", manifest["defaultStrength"]),
      candidate.call("yingjian-high-safe-export", "subject", "highSafeExport", manifest["highSafeStrength"]),
      candidate.call("yingjian-default-preview", "subject", "defaultPreview", manifest["defaultStrength"]),
      *competitor_records.map do |record|
        competitor = record["data"]
        competitor_id = record["id"]
        {
          "id" => "#{competitor_id}-fixed-path-export",
          "role" => "reference",
          "file" => relative_file.call(record["path"]),
          "sha256" => record["sha256"],
          "provenance" => {
            "producer" => competitor_id,
            "version" => competitor["version"],
            "app_store_id" => competitor["app_store_id"],
            "bundle_id" => competitor["bundle_id"],
            "device_evidence_id" => competitor["device_evidence_id"],
            "device" => competitor["device"],
            "os" => competitor["os"],
            "variant" => "fixed_path",
            "render_kind" => "export",
            "source_sha256" => baseline_hash,
            "parameters" => competitor["parameters"],
            "operation_path" => competitor["operation_path"],
          },
        }
      end,
    ],
  }
  end
rescue PortraitCaptureContract::ValidationError, SystemCallError => error
  fail_plan(error.message)
end

plan = {
  "schema" => schema,
  "review_id" => review_id,
  "task" => "portrait",
  "minimum_reviewers" => minimum_reviewers,
  "items" => plan_items.sort_by { |item| item["asset_id"] },
}
if schema == PortraitReviewContract::MVP_SCHEMA
  relative_file = lambda do |path|
    Pathname.new(path).relative_path_from(Pathname.new(output_parent_real)).to_s
  end
  plan["portrait_corpus_manifest"] = {
    "file" => relative_file.call(corpus_manifest_path),
    "sha256" => corpus_manifest_sha256,
  }
  plan["device_evidence"] = {
    "id" => device_evidence["id"],
    "file" => relative_file.call(device_evidence["path"]),
    "sha256" => device_evidence["sha256"],
    "device" => device_evidence["device"],
    "os" => device_evidence["os"],
  }
end

temporary_path = "#{output_path}.tmp-#{Process.pid}"
begin
  File.write(temporary_path, YAML.dump(plan))
  if schema == PortraitReviewContract::MVP_SCHEMA
    begin
      PortraitReviewContract.validate_mvp_plan_bindings!(
        plan,
        plan_path: temporary_path,
        quality_root: quality_root_real,
      )
    rescue PortraitReviewContract::ContractError => error
      fail_plan(error.message)
    end
  end
  File.rename(temporary_path, output_path)
ensure
  File.delete(temporary_path) if File.exist?(temporary_path)
end
puts "Portrait review plan built: #{output_path} (#{plan_items.length} items)"
