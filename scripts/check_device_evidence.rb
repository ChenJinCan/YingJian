#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"

def fail_evidence(message)
  warn "Device evidence check failed: #{message}"
  exit 1
end

def concrete_string?(value)
  value.is_a?(String) && !value.strip.empty? && value !~ /replace_with|unknown|not[-_ ]recorded/i
end

def finite_number?(value)
  value.is_a?(Numeric) && value.finite?
end

def percentile(values, percentile)
  sorted = values.sort
  sorted[[(percentile * sorted.length).ceil - 1, 0].max]
end

allow_incomplete = ARGV.delete("--allow-incomplete")
source_index = ARGV.index("--source-commit")
expected_source = source_index && ARGV[source_index + 1]
if source_index
  fail_evidence("--source-commit requires a full commit SHA") unless expected_source
  ARGV.slice!(source_index, 2)
end
if expected_source && !expected_source.match?(/\A[0-9a-f]{40}\z/)
  fail_evidence("--source-commit requires a full lowercase Git SHA")
end
manifest_argument = ARGV.shift || ".quality/device-evidence.yaml"
fail_evidence("usage: check_device_evidence.rb [MANIFEST] [--allow-incomplete] [--source-commit SHA]") unless ARGV.empty?

repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
manifest_path = File.expand_path(manifest_argument, repo_root)
unless File.file?(manifest_path)
  if allow_incomplete
    puts "Device evidence incomplete: manifest is missing (0/6 runs)"
    exit 0
  end
  fail_evidence("manifest is missing: #{manifest_argument}")
end

begin
  quality_root_real = File.realpath(quality_root)
  manifest_real = File.realpath(manifest_path)
rescue SystemCallError => error
  fail_evidence(error.message)
end
unless manifest_real.start_with?("#{quality_root_real}/")
  fail_evidence("manifest must remain inside the ignored .quality directory")
end

begin
  manifest = YAML.safe_load(File.read(manifest_real), permitted_classes: [], aliases: false)
rescue Psych::Exception => error
  fail_evidence("manifest is invalid YAML: #{error.message}")
end
fail_evidence("manifest must be a mapping") unless manifest.is_a?(Hash)

errors = []
errors << "schema must equal 1" unless manifest["schema"] == 1
status = manifest["status"]
errors << "status must be blocked_missing_runs or ready" unless %w[blocked_missing_runs ready].include?(status)
source_commit = manifest["source_commit"]
unless source_commit.is_a?(String) && source_commit.match?(/\A[0-9a-f]{40}\z/)
  errors << "source_commit must be a full lowercase Git SHA"
end
if expected_source && expected_source != source_commit
  errors << "source_commit does not match --source-commit"
end
runs = manifest["runs"]
unless runs.is_a?(Array)
  errors << "runs must be a list"
  runs = []
end

budgets = {
  "low" => {
    first_preview: 4_000, recommendations: 12_000, slider: 120,
    fps: 24, export_12mp: 8_000, batch: 60_000,
  },
  "mid" => {
    first_preview: 2_500, recommendations: 8_000, slider: 100,
    fps: 30, export_12mp: 5_000, batch: 40_000,
  },
  "high" => {
    first_preview: 1_800, recommendations: 6_000, slider: 80,
    fps: 45, export_12mp: 3_500, export_48mp: 8_000, batch: 30_000,
  },
}.freeze
required_coverage = {
  ["ios", "low"] => %w[12mp portrait_single six_photo_group],
  ["ios", "mid"] => %w[12mp 24mp display_p3 heic six_photo_group],
  ["ios", "high"] => %w[48mp portrait_multi six_photo_batch],
  ["android", "low"] => %w[12mp jpeg legacy_api_path],
  ["android", "mid"] => %w[12mp 24mp heic six_photo_group],
  ["android", "high"] => %w[48mp portrait_multi six_photo_batch],
}.freeze
required_outcomes = %w[
  source_hash_unchanged final_artifacts_valid three_batch_rounds_completed
  no_system_kill background_restore low_memory_restore cancellation_recover
  offline_journey diagnostics_disabled cloud_image_tasks_zero accessibility_task_completed
].freeze

run_ids = {}
device_ids = {}
slots = {}
artifact_paths = {}
artifact_hashes = {}
platform_builds = {}
summaries = []
runs.each_with_index do |run, index|
  prefix = "runs[#{index}]"
  unless run.is_a?(Hash)
    errors << "#{prefix} must be a mapping"
    next
  end
  run_id = run["run_id"]
  platform = run["platform"]
  tier = run["tier"]
  slot = [platform, tier]
  if !concrete_string?(run_id) || !run_id.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
    errors << "#{prefix}.run_id is invalid"
  elsif run_ids[run_id]
    errors << "duplicate run_id: #{run_id}"
  else
    run_ids[run_id] = true
  end
  unless required_coverage.key?(slot)
    errors << "#{prefix} platform/tier must be one frozen iOS/Android low/mid/high slot"
    next
  end
  if slots[slot]
    errors << "duplicate device slot: #{platform}/#{tier}"
  else
    slots[slot] = true
  end

  device = run["device"]
  build = run["build"]
  methodology = run["methodology"]
  measurements = run["measurements"]
  outcomes = run["outcomes"]
  coverage = run["coverage"]
  artifacts = run["artifacts"]
  unless device.is_a?(Hash)
    errors << "#{prefix}.device must be a mapping"
    next
  end
  %w[model hardware_class os_version tier_basis].each do |field|
    errors << "#{prefix}.device.#{field} must be concrete" unless concrete_string?(device[field])
  end
  device_id = device["device_id"]
  if !device_id.is_a?(String) || !device_id.match?(/\A[0-9a-f]{64}\z/)
    errors << "#{prefix}.device.device_id must be an opaque lowercase SHA-256"
  elsif device_ids[device_id]
    errors << "duplicate physical device identity: #{device_id}"
  else
    device_ids[device_id] = true
  end
  physical_memory = device["physical_memory_mb"]
  unless finite_number?(physical_memory) && physical_memory.positive?
    errors << "#{prefix}.device.physical_memory_mb must be positive"
  end
  errors << "#{prefix}.device.physical must equal true" unless device["physical"] == true

  unless build.is_a?(Hash)
    errors << "#{prefix}.build must be a mapping"
    next
  end
  unless methodology.is_a?(Hash)
    errors << "#{prefix}.methodology must be a mapping"
    methodology = {}
  end
  %w[timing_tool memory_tool frame_tool thermal_tool lifecycle_protocol].each do |field|
    errors << "#{prefix}.methodology.#{field} must be concrete" unless concrete_string?(methodology[field])
  end
  %w[bundle_id version build_number artifact_sha256].each do |field|
    errors << "#{prefix}.build.#{field} must be concrete" unless concrete_string?(build[field])
  end
  unless %w[profile release].include?(build["mode"])
    errors << "#{prefix}.build.mode must be profile or release"
  end
  errors << "#{prefix}.build.source_commit must match manifest source_commit" unless build["source_commit"] == source_commit
  unless build["artifact_sha256"].is_a?(String) && build["artifact_sha256"].match?(/\A[0-9a-f]{64}\z/)
    errors << "#{prefix}.build.artifact_sha256 must be a lowercase SHA-256"
  end
  build_signature = %w[mode source_commit bundle_id version build_number artifact_sha256].to_h do |field|
    [field, build[field]]
  end
  platform_builds[platform] ||= build_signature
  unless platform_builds[platform] == build_signature
    errors << "#{prefix}.build must match the frozen #{platform} build used by the other tiers"
  end

  unless coverage.is_a?(Array) && coverage.all? { |value| concrete_string?(value) }
    errors << "#{prefix}.coverage must be a concrete string list"
    coverage = []
  end
  missing_coverage = required_coverage.fetch(slot) - coverage
  errors << "#{prefix}.coverage is missing #{missing_coverage.join(", ")}" unless missing_coverage.empty?

  unless outcomes.is_a?(Hash)
    errors << "#{prefix}.outcomes must be a mapping"
    outcomes = {}
  end
  required_outcomes.each do |name|
    errors << "#{prefix}.outcomes.#{name} must equal true" unless outcomes[name] == true
  end
  if platform == "ios"
    %w[system_share_success system_share_cancel system_share_failure].each do |name|
      errors << "#{prefix}.outcomes.#{name} must equal true" unless outcomes[name] == true
    end
  end

  unless artifacts.is_a?(Array) && artifacts.length >= 3
    errors << "#{prefix}.artifacts must contain build_artifact, metrics_log, and final_artifact_probe"
    artifacts = []
  end
  artifact_kinds = {}
  artifact_files = {}
  artifacts.each_with_index do |artifact, artifact_index|
    artifact_prefix = "#{prefix}.artifacts[#{artifact_index}]"
    unless artifact.is_a?(Hash)
      errors << "#{artifact_prefix} must be a mapping"
      next
    end
    kind = artifact["kind"]
    relative_file = artifact["file"]
    sha256 = artifact["sha256"]
    if !concrete_string?(kind)
      errors << "#{artifact_prefix}.kind must be concrete"
    elsif artifact_kinds[kind]
      errors << "#{prefix} has duplicate artifact kind #{kind}"
    else
      artifact_kinds[kind] = true
    end
    unless relative_file.is_a?(String) && !relative_file.empty?
      errors << "#{artifact_prefix}.file must be a relative path"
      next
    end
    path = Pathname.new(relative_file)
    if path.absolute? || path.each_filename.include?("..") || !relative_file.start_with?(".quality/device-evidence/")
      errors << "#{artifact_prefix}.file must remain inside .quality/device-evidence"
      next
    end
    full_path = File.expand_path(relative_file, repo_root)
    unless File.file?(full_path)
      errors << "#{artifact_prefix}.file is missing"
      next
    end
    begin
      real_path = File.realpath(full_path)
      unless real_path.start_with?("#{quality_root_real}/device-evidence/")
        errors << "#{artifact_prefix}.file resolves outside .quality/device-evidence"
        next
      end
    rescue SystemCallError
      errors << "#{artifact_prefix}.file could not be resolved"
      next
    end
    unless kind == "build_artifact"
      if artifact_paths[real_path]
        errors << "duplicate evidence artifact path: #{relative_file}"
      else
        artifact_paths[real_path] = true
      end
    end
    artifact_files[kind] = real_path if concrete_string?(kind)
    unless sha256.is_a?(String) && sha256.match?(/\A[0-9a-f]{64}\z/)
      errors << "#{artifact_prefix}.sha256 must be a lowercase SHA-256"
      next
    end
    actual_hash = Digest::SHA256.file(real_path).hexdigest
    errors << "#{artifact_prefix}.sha256 does not match the file" unless actual_hash == sha256
    if kind == "build_artifact" && build["artifact_sha256"] != sha256
      errors << "#{artifact_prefix}.sha256 must match build.artifact_sha256"
    end
    unless kind == "build_artifact"
      if artifact_hashes[sha256]
        errors << "duplicate evidence artifact hash: #{sha256}"
      else
        artifact_hashes[sha256] = true
      end
    end
  end
  %w[build_artifact metrics_log final_artifact_probe].each do |kind|
    errors << "#{prefix}.artifacts is missing #{kind}" unless artifact_kinds[kind]
  end

  metrics_file = artifact_files["metrics_log"]
  if metrics_file
    begin
      metrics_record = JSON.parse(File.read(metrics_file))
      unless metrics_record.is_a?(Hash) && metrics_record["schema"] == 1 &&
          metrics_record["run_id"] == run_id && metrics_record["methodology"] == methodology &&
          metrics_record["measurements"] == measurements &&
          metrics_record["outcomes"] == outcomes
        errors << "#{prefix} metrics_log does not exactly bind run_id, methodology, measurements, and outcomes"
      end
    rescue JSON::ParserError, SystemCallError => error
      errors << "#{prefix} metrics_log is unreadable: #{error.message}"
    end
  end
  probe_file = artifact_files["final_artifact_probe"]
  if probe_file
    begin
      probe = JSON.parse(File.read(probe_file))
      required_checks = %w[
        orientation dimensions crop srgb jpeg_quality_95 capture_time
        sensitive_metadata_removed source_hash_unchanged
      ]
      valid_probe = probe.is_a?(Hash) && probe["schema"] == 1 && probe["run_id"] == run_id &&
        probe["source_commit"] == source_commit && probe["probed_output_count"].is_a?(Integer) &&
        probe["probed_output_count"] >= 6 && probe["checks"].is_a?(Hash) &&
        required_checks.all? { |name| probe["checks"][name] == true }
      errors << "#{prefix} final_artifact_probe is incomplete" unless valid_probe
    rescue JSON::ParserError, SystemCallError => error
      errors << "#{prefix} final_artifact_probe is unreadable: #{error.message}"
    end
  end

  unless measurements.is_a?(Hash)
    errors << "#{prefix}.measurements must be a mapping"
    next
  end
  sample_contracts = {
    "first_preview_ms" => 5,
    "six_photo_recommendations_ms" => 5,
    "slider_response_ms" => 20,
    "continuous_preview_fps" => 20,
    "export_12mp_ms" => 3,
    "batch_six_12mp_ms" => 3,
    "ui_main_thread_stalls_ms" => 20,
  }
  sample_contracts["export_24mp_ms"] = 3 if tier == "mid"
  sample_contracts["export_48mp_ms"] = 3 if tier == "high"
  samples = {}
  sample_contracts.each do |name, minimum_count|
    values = measurements[name]
    unless values.is_a?(Array) && values.length >= minimum_count &&
        values.all? { |value| finite_number?(value) && value >= 0 }
      errors << "#{prefix}.measurements.#{name} needs at least #{minimum_count} finite non-negative samples"
      next
    end
    samples[name] = values
  end
  peak_memory = measurements["peak_additional_memory_mb"]
  unless finite_number?(peak_memory) && peak_memory >= 0
    errors << "#{prefix}.measurements.peak_additional_memory_mb must be non-negative"
  end
  thermal_states = measurements["thermal_states"]
  unless thermal_states.is_a?(Array) && !thermal_states.empty? &&
      thermal_states.all? { |state| %w[nominal fair serious critical].include?(state) }
    errors << "#{prefix}.measurements.thermal_states is invalid"
    thermal_states = []
  end
  errors << "#{prefix} reached critical thermal state" if thermal_states.include?("critical")
  if thermal_states.include?("serious") && measurements["thermal_mitigation_activated"] != true
    errors << "#{prefix} reached serious thermal state without mitigation"
  end

  next unless samples.keys.length == sample_contracts.keys.length && finite_number?(peak_memory) &&
    finite_number?(physical_memory) && physical_memory.positive?

  budget = budgets.fetch(tier)
  computed = {
    "first_preview_p50_ms" => percentile(samples["first_preview_ms"], 0.50),
    "first_preview_p95_ms" => percentile(samples["first_preview_ms"], 0.95),
    "recommendations_p50_ms" => percentile(samples["six_photo_recommendations_ms"], 0.50),
    "recommendations_p95_ms" => percentile(samples["six_photo_recommendations_ms"], 0.95),
    "slider_p50_ms" => percentile(samples["slider_response_ms"], 0.50),
    "slider_p95_ms" => percentile(samples["slider_response_ms"], 0.95),
    "minimum_preview_fps" => samples["continuous_preview_fps"].min,
    "export_12mp_p95_ms" => percentile(samples["export_12mp_ms"], 0.95),
    "batch_six_12mp_p95_ms" => percentile(samples["batch_six_12mp_ms"], 0.95),
    "peak_additional_memory_mb" => peak_memory,
  }
  if tier == "high"
    computed["export_48mp_p95_ms"] = percentile(samples["export_48mp_ms"], 0.95)
  end
  errors << "#{prefix} first preview p95 exceeds #{budget[:first_preview]} ms" if computed["first_preview_p95_ms"] > budget[:first_preview]
  errors << "#{prefix} six-photo recommendations p95 exceeds #{budget[:recommendations]} ms" if computed["recommendations_p95_ms"] > budget[:recommendations]
  errors << "#{prefix} slider response p95 exceeds #{budget[:slider]} ms" if computed["slider_p95_ms"] > budget[:slider]
  errors << "#{prefix} continuous preview falls below #{budget[:fps]} fps" if computed["minimum_preview_fps"] < budget[:fps]
  errors << "#{prefix} 12 MP export p95 exceeds #{budget[:export_12mp]} ms" if computed["export_12mp_p95_ms"] > budget[:export_12mp]
  errors << "#{prefix} six-photo batch p95 exceeds #{budget[:batch]} ms" if computed["batch_six_12mp_p95_ms"] > budget[:batch]
  if tier == "high" && computed["export_48mp_p95_ms"] > budget[:export_48mp]
    errors << "#{prefix} 48 MP export p95 exceeds #{budget[:export_48mp]} ms"
  end
  memory_limit = [512.0, physical_memory * 0.25].min
  errors << "#{prefix} peak additional memory exceeds #{memory_limit} MB" if peak_memory > memory_limit
  errors << "#{prefix} Flutter UI main-thread stall exceeds 100 ms" if samples["ui_main_thread_stalls_ms"].max > 100
  summaries << { "run_id" => run_id, "platform" => platform, "tier" => tier }.merge(computed)
end

if runs.length < 6 && status != "blocked_missing_runs"
  errors << "status must equal blocked_missing_runs until all six runs exist"
end
if platform_builds.keys.sort == %w[android ios] &&
    platform_builds["android"]["artifact_sha256"] == platform_builds["ios"]["artifact_sha256"]
  errors << "iOS and Android build artifacts must be distinct"
end

unless allow_incomplete
  errors << "status must equal ready for the complete gate" unless status == "ready"
  errors << "device run count must equal 6" unless runs.length == 6
  missing_slots = required_coverage.keys - slots.keys
  errors << "missing device slots: #{missing_slots.map { |slot| slot.join("/") }.join(", ")}" unless missing_slots.empty?
end

unless errors.empty?
  errors.each { |error| warn "- #{error}" }
  fail_evidence("#{errors.length} violation(s)")
end

if allow_incomplete
  puts "Device evidence check passed (incomplete, #{runs.length}/6 runs)"
else
  puts "Device evidence check passed (6/6 physical runs)"
  summaries.sort_by { |summary| [summary["platform"], summary["tier"]] }.each do |summary|
    puts YAML.dump(summary).sub(/\A---\s*\n/, "").strip
  end
end
