#!/usr/bin/env ruby

require "csv"
require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

def median(values)
  ordered = values.sort
  middle = ordered.length / 2
  ordered.length.odd? ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2.0
end

def parse_boolean(value)
  return true if value == "true"
  return false if value == "false"
  nil
end

key_argument = ARGV.shift
scores_argument = ARGV.shift
candidate_index = ARGV.index("--candidate")
candidate_id = candidate_index && ARGV[candidate_index + 1]
output_index = ARGV.index("--output")
output_path = output_index && ARGV[output_index + 1]
unless key_argument && scores_argument && candidate_id && !candidate_id.empty?
  warn "Blind review score check failed: usage: check_blind_review_scores.rb KEY SCORES --candidate ID [--output SUMMARY.json]"
  exit 1
end

begin
  key_path = File.expand_path(key_argument)
  key = JSON.parse(File.read(key_path))
rescue Errno::ENOENT, JSON::ParserError => error
  warn "Blind review score check failed: review key is unavailable: #{error.message}"
  exit 1
end
unless key.is_a?(Hash) && key["schema"] == 1 && key["items"].is_a?(Array)
  warn "Blind review score check failed: review key has an unsupported schema"
  exit 1
end
unless key["task"] == "portrait"
  warn "Blind review score check failed: review key task must equal portrait"
  exit 1
end

errors = []
repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
quality_root_real = File.realpath(quality_root)

def inside_real_directory?(path, root)
  real = File.realpath(path)
  real == root || real.start_with?("#{root}/")
rescue Errno::ENOENT
  false
end

source_plan = key["source_plan"]
plan = nil
if !source_plan.is_a?(Hash) || !source_plan["file"].is_a?(String) ||
    !source_plan["sha256"].is_a?(String)
  errors << "review key source_plan is missing"
elsif !inside_real_directory?(source_plan["file"], quality_root_real)
  errors << "source plan must remain inside the ignored .quality directory"
elsif Digest::SHA256.file(source_plan["file"]).hexdigest != source_plan["sha256"]
  errors << "source plan sha256 does not match the review key"
else
  begin
    plan = YAML.safe_load(File.read(source_plan["file"]), permitted_classes: [], aliases: false)
  rescue Psych::Exception => error
    errors << "source plan is invalid YAML: #{error.message}"
  end
end
plan_items = if plan.is_a?(Hash) && plan["items"].is_a?(Array)
  plan["items"].each_with_object({}) { |item, result| result[item["asset_id"]] = item }
else
  errors << "source plan has an unsupported schema" if plan
  {}
end
seed = key["seed"]
if !seed.is_a?(String) || seed.empty? || Digest::SHA256.hexdigest(seed) != key["seed_sha256"]
  errors << "review key seed is missing or invalid"
  seed = "invalid-seed"
end
expected_item_codes = {}
expected_candidate_codes = {}
if plan.is_a?(Hash) && plan["items"].is_a?(Array)
  plan["items"].sort_by do |item|
    Digest::SHA256.hexdigest("#{seed}|item|#{item["asset_id"]}")
  end.each_with_index do |item, item_index|
    expected_item_codes[item["asset_id"]] = format("I%03d", item_index + 1)
    item.fetch("candidates", []).sort_by do |candidate|
      Digest::SHA256.hexdigest("#{seed}|#{item["asset_id"]}|#{candidate["id"]}")
    end.each_with_index do |candidate, candidate_index|
      expected_candidate_codes[[item["asset_id"], candidate["id"]]] = format("C%02d", candidate_index + 1)
    end
  end
end

sanitizer_directory = Dir.mktmpdir("blind-review-score-", quality_root)
at_exit { FileUtils.remove_entry(sanitizer_directory) if File.exist?(sanitizer_directory) }
sanitizer_path = File.join(sanitizer_directory, "sanitize-review-image")
sanitizer_source = File.join(repo_root, "scripts/support/sanitize_review_image.swift")
_stdout, sanitizer_stderr, sanitizer_compiled = Open3.capture3(
  "/usr/bin/xcrun", "swiftc", sanitizer_source, "-o", sanitizer_path,
)
unless sanitizer_compiled.success?
  errors << "review image sanitizer could not compile: #{sanitizer_stderr.strip}"
end
sanitizer_counter = 0

selected_by_item = {}
baseline_by_item = {}
tags_by_item = {}
baseline_hashes = []
normalized_hashes_by_slot = Hash.new { |hash, slot| hash[slot] = [] }
key["items"].each do |item|
  item_code = item["item_code"]
  asset_id = item["asset_id"]
  unless item_code == expected_item_codes[asset_id]
    errors << "item #{asset_id} item_code does not match the frozen anonymous mapping"
  end
  candidates = item.fetch("candidates", [])
  plan_item = plan_items[asset_id]
  if plan_item.nil?
    errors << "item #{item_code} is missing from the source plan"
  else
    errors << "item #{item_code} tags do not match the source plan" unless item["tags"] == plan_item["tags"].uniq.sort
  end
  plan_candidates = plan_item ? plan_item.fetch("candidates", []).each_with_object({}) do |entry, result|
    result[entry["id"]] = entry
  end : {}
  candidate = candidates.find do |entry|
    entry["candidate_id"] == candidate_id
  end
  baselines = candidates.select { |entry| entry["role"] == "baseline_original" }
  baseline_count = baselines.length
  errors << "item #{item_code} must contain exactly one baseline_original" unless baseline_count == 1
  baseline_hash = baselines.first["sha256"] if baseline_count == 1
  baseline_hashes << baseline_hash if baseline_hash
  baseline_by_item[item_code] = baselines.first["candidate_code"] if baseline_count == 1

  candidates.each do |entry|
    provenance = entry["provenance"]
    expected_candidate_code = expected_candidate_codes[[asset_id, entry["candidate_id"]]]
    unless entry["candidate_code"] == expected_candidate_code
      errors << "item #{item_code} candidate #{entry["candidate_id"]} candidate_code does not match the frozen anonymous mapping"
    end
    expected_review_file = "images/#{item_code}-#{entry["candidate_code"]}.png"
    unless entry["review_file"] == expected_review_file
      errors << "item #{item_code} candidate #{entry["candidate_id"]} review_file does not match the anonymous mapping"
    end
    review_path = File.join(File.dirname(key_path), "participant-package", entry["review_file"].to_s)
    normalized_raster_hash = entry["normalized_raster_sha256"]
    if !inside_real_directory?(review_path, quality_root_real) ||
        !normalized_raster_hash.is_a?(String) ||
        Digest::SHA256.file(review_path).hexdigest != normalized_raster_hash
      errors << "item #{item_code} candidate #{entry["candidate_id"]} normalized raster does not match the review package"
    end
    source_entry = plan_candidates[entry["candidate_id"]]
    unless source_entry && entry["role"] == source_entry["role"] &&
        entry["sha256"] == source_entry["sha256"] &&
        entry["provenance"] == source_entry["provenance"] &&
        File.expand_path(entry["file"].to_s) == File.expand_path(source_entry["file"].to_s, File.dirname(source_plan["file"].to_s))
      errors << "item #{item_code} candidate #{entry["candidate_id"]} does not match the source plan"
    end
    file_path = entry["file"]
    source_file_valid = true
    if !file_path.is_a?(String) || !inside_real_directory?(file_path, quality_root_real)
      errors << "item #{item_code} candidate #{entry["candidate_id"]} file must remain inside .quality"
      source_file_valid = false
    elsif !entry["sha256"].is_a?(String) ||
        Digest::SHA256.file(file_path).hexdigest != entry["sha256"]
      errors << "item #{item_code} candidate #{entry["candidate_id"]} sha256 does not match the source file"
      source_file_valid = false
    end
    if source_file_valid && sanitizer_compiled.success?
      sanitizer_counter += 1
      regenerated_path = File.join(sanitizer_directory, format("%04d.png", sanitizer_counter))
      stdout, stderr, regenerated = Open3.capture3(sanitizer_path, file_path, regenerated_path)
      regenerated_pixel_hash = stdout.strip
      expected_pixel_hash = entry["normalized_pixel_sha256"]
      if !regenerated.success? || !expected_pixel_hash.is_a?(String) ||
          regenerated_pixel_hash != expected_pixel_hash ||
          !File.file?(review_path) ||
          Digest::SHA256.file(regenerated_path).hexdigest != Digest::SHA256.file(review_path).hexdigest
        errors << "item #{item_code} candidate #{entry["candidate_id"]} review image is not the normalized source candidate#{stderr.empty? ? "" : ": #{stderr.strip}"}"
      elsif provenance.is_a?(Hash)
        slot = [entry["role"], provenance["variant"], provenance["render_kind"]].join(":")
        normalized_hashes_by_slot[slot] << regenerated_pixel_hash
      end
    end
    required_provenance = %w[producer version device os variant render_kind]
    unless provenance.is_a?(Hash) &&
        required_provenance.all? { |name| provenance[name].is_a?(String) && !provenance[name].empty? } &&
        provenance["parameters"].is_a?(Hash)
      errors << "item #{item_code} candidate #{entry["candidate_id"]} has incomplete provenance"
      next
    end
    next if entry["role"] == "baseline_original"
    unless baseline_hash && provenance["source_sha256"] == baseline_hash
      errors << "item #{item_code} candidate #{entry["candidate_id"]} source_sha256 does not match baseline_original"
    end
  end

  expected_slots = [
    ["baseline_original", "original", "source"],
    ["subject", "off", "export"],
    ["subject", "default", "export"],
    ["subject", "high_safe", "export"],
    ["subject", "default", "preview"],
    ["reference", "fixed_path", "export"],
  ]
  errors << "item #{item_code} must contain exactly six matrix results" unless candidates.length == 6
  expected_slots.each do |role, variant, render_kind|
    count = candidates.count do |entry|
      provenance = entry["provenance"]
      entry["role"] == role && provenance.is_a?(Hash) &&
        provenance["variant"] == variant && provenance["render_kind"] == render_kind
    end
    errors << "item #{item_code} must contain exactly one #{role} #{variant} #{render_kind}" unless count == 1
  end
  competitor = candidates.find { |entry| entry["role"] == "reference" }
  operation_path = competitor && competitor.dig("provenance", "operation_path")
  errors << "item #{item_code} competitor fixed_path export requires operation_path" unless operation_path.is_a?(String) && !operation_path.empty?
  rendered = candidates.reject { |entry| entry["role"] == "baseline_original" }
  %w[device os].each do |field|
    values = rendered.map { |entry| entry.dig("provenance", field) }.uniq
    errors << "item #{item_code} rendered candidates must share #{field}" unless values.length == 1
  end
  subjects = candidates.select { |entry| entry["role"] == "subject" }
  %w[version device os].each do |field|
    values = subjects.map { |entry| entry.dig("provenance", field) }.uniq
    errors << "item #{item_code} subject candidates must share #{field}" unless values.length == 1
  end
  default_renders = subjects.select { |entry| entry.dig("provenance", "variant") == "default" }
  unless default_renders.map { |entry| entry.dig("provenance", "parameters") }.uniq.length == 1
    errors << "item #{item_code} subject default preview and export must share parameters"
  end

  if candidate
    errors << "candidate #{candidate_id} must have role subject" unless candidate["role"] == "subject"
    provenance = candidate["provenance"]
    unless provenance.is_a?(Hash) &&
        provenance["producer"] == "yingjian" &&
        provenance["variant"] == "default" &&
        provenance["render_kind"] == "export"
      errors << "candidate #{candidate_id} must be the Yingjian default export"
    end
    selected_by_item[item_code] = candidate["candidate_code"]
    tags_by_item[item_code] = item.fetch("tags", [])
  else
    errors << "candidate #{candidate_id} is missing for item #{item_code}"
  end
end

required_coverage = {
  "portrait_single" => 36,
  "negative_safety" => 12,
  "deep_skin" => 1,
  "beard" => 1,
  "freckles_moles" => 1,
  "glasses" => 1,
  "makeup" => 1,
  "improvable" => 1,
}
errors << "item count #{selected_by_item.length} is below 48" if selected_by_item.length < 48
if baseline_hashes.compact.uniq.length < 48
  errors << "unique baseline image count #{baseline_hashes.compact.uniq.length} is below 48"
end
expected_normalized_slots = [
  "baseline_original:original:source",
  "subject:off:export",
  "subject:default:export",
  "subject:high_safe:export",
  "subject:default:preview",
  "reference:fixed_path:export",
]
expected_normalized_slots.each do |slot|
  unique_count = normalized_hashes_by_slot[slot].uniq.length
  errors << "normalized raster slot #{slot} unique count #{unique_count} is below 48" if unique_count < 48
end
coverage_counts = Hash.new(0)
tags_by_item.each_value { |tags| tags.uniq.each { |tag| coverage_counts[tag] += 1 } }
overlapping_coverage = tags_by_item.select do |_item_code, tags|
  tags.include?("portrait_single") && tags.include?("negative_safety")
end
unless overlapping_coverage.empty?
  errors << "portrait_single and negative_safety overlap: #{overlapping_coverage.keys.sort.join(", ")}"
end
required_coverage.each do |tag, minimum|
  errors << "tag #{tag} count #{coverage_counts[tag]} is below #{minimum}" if coverage_counts[tag] < minimum
end

required_headers = %w[
  reviewer_id item_code baseline_code candidate_code overall_improvement naturalness
  identity_preservation texture_preservation skin_tone_lighting local_boundaries
  non_skin_protection catastrophic_error preferred_over_baseline notes
]
begin
  table = CSV.read(scores_argument, headers: true)
rescue Errno::ENOENT, CSV::MalformedCSVError => error
  warn "Blind review score check failed: score sheet is unavailable: #{error.message}"
  exit 1
end
missing_headers = required_headers - (table.headers || [])
errors << "score sheet is missing headers: #{missing_headers.join(", ")}" unless missing_headers.empty?

score_dimensions = %w[
  overall_improvement naturalness identity_preservation texture_preservation
  skin_tone_lighting local_boundaries non_skin_protection
]
rows = []
seen = {}
table.each_with_index do |row, index|
  next unless selected_by_item[row["item_code"]] == row["candidate_code"]
  prefix = "row #{index + 2}"
  reviewer_id = row["reviewer_id"]
  item_code = row["item_code"]
  if row["baseline_code"] != baseline_by_item[item_code]
    errors << "#{prefix}.baseline_code does not match the original anchor"
  end
  if !reviewer_id.is_a?(String) || reviewer_id.strip.empty?
    errors << "#{prefix} has no reviewer_id"
    next
  end
  identity = [reviewer_id, item_code]
  if seen[identity]
    errors << "duplicate score for reviewer #{reviewer_id} and item #{item_code}"
    next
  end
  seen[identity] = true
  values = {}
  score_dimensions.each do |dimension|
    raw = row[dimension]
    value = Integer(raw, exception: false)
    if !value || !(1..5).include?(value)
      errors << "#{prefix}.#{dimension} must be an integer from 1 to 5"
    else
      values[dimension] = value
    end
  end
  catastrophic = parse_boolean(row["catastrophic_error"])
  preferred = parse_boolean(row["preferred_over_baseline"])
  errors << "#{prefix}.catastrophic_error must be true or false" if catastrophic.nil?
  errors << "#{prefix}.preferred_over_baseline must be true or false" if preferred.nil?
  rows << {
    "reviewer_id" => reviewer_id,
    "item_code" => item_code,
    "scores" => values,
    "catastrophic" => catastrophic,
    "preferred" => preferred,
  }
end

reviewers = rows.map { |row| row["reviewer_id"] }.uniq.sort
minimum_reviewers = key["minimum_reviewers"]
unless minimum_reviewers.is_a?(Integer) && minimum_reviewers >= 5
  errors << "review key minimum_reviewers must be at least 5"
  minimum_reviewers = 5
end
if reviewers.length < minimum_reviewers
  errors << "reviewer count #{reviewers.length} is below #{minimum_reviewers}"
end
reviewers.each do |reviewer_id|
  selected_by_item.each_key do |item_code|
    unless seen[[reviewer_id, item_code]]
      errors << "reviewer #{reviewer_id} is missing item #{item_code}"
    end
  end
end

medians = {}
score_dimensions.each do |dimension|
  values = rows.map { |row| row["scores"][dimension] }.compact
  medians[dimension] = median(values) unless values.empty?
end
errors << "identity_preservation median is below 4.5" if medians.fetch("identity_preservation", 0) < 4.5
%w[naturalness texture_preservation skin_tone_lighting local_boundaries non_skin_protection].each do |dimension|
  errors << "#{dimension} median is below 4.0" if medians.fetch(dimension, 0) < 4.0
end
%w[naturalness identity_preservation local_boundaries].each do |dimension|
  if rows.any? { |row| row["scores"][dimension] == 1 }
    errors << "#{dimension} contains a forbidden score of 1"
  end
end
catastrophic_count = rows.count { |row| row["catastrophic"] == true }
errors << "catastrophic errors reported: #{catastrophic_count}" if catastrophic_count.positive?

improvable_rows = rows.select do |row|
  tags_by_item.fetch(row["item_code"], []).include?("improvable")
end
preference_rate = if improvable_rows.empty?
  nil
else
  improvable_rows.count { |row| row["preferred"] == true }.to_f / improvable_rows.length
end
errors << "no improvable items were scored" if preference_rate.nil?
if preference_rate && preference_rate < 0.65
  errors << format("pairwise preference rate %.3f is below 0.650", preference_rate)
end

subgroups = {}
required_coverage.each_key do |tag|
  tagged_rows = rows.select { |row| tags_by_item.fetch(row["item_code"], []).include?(tag) }
  next if tagged_rows.empty?
  tag_medians = {}
  score_dimensions.each do |dimension|
    values = tagged_rows.map { |row| row["scores"][dimension] }.compact
    tag_medians[dimension] = median(values) unless values.empty?
  end
  subgroups[tag] = {
    "item_count" => tagged_rows.map { |row| row["item_code"] }.uniq.length,
    "score_row_count" => tagged_rows.length,
    "medians" => tag_medians,
    "catastrophic_error_count" => tagged_rows.count { |row| row["catastrophic"] == true },
  }
  next unless %w[deep_skin beard freckles_moles glasses makeup].include?(tag)
  errors << "subgroup #{tag} identity_preservation median is below 4.5" if tag_medians.fetch("identity_preservation", 0) < 4.5
  %w[naturalness texture_preservation skin_tone_lighting local_boundaries non_skin_protection].each do |dimension|
    if tag_medians.fetch(dimension, 0) < 4.0
      errors << "subgroup #{tag} #{dimension} median is below 4.0"
    end
  end
end

summary = {
  "schema" => 1,
  "review_id" => key["review_id"],
  "candidate_id" => candidate_id,
  "reviewer_count" => reviewers.length,
  "item_count" => selected_by_item.length,
  "score_row_count" => rows.length,
  "medians" => medians,
  "pairwise_preference_rate" => preference_rate,
  "coverage_counts" => coverage_counts.sort.to_h,
  "subgroups" => subgroups,
  "catastrophic_error_count" => catastrophic_count,
  "status" => errors.empty? ? "passed" : "failed",
  "errors" => errors,
}
File.write(output_path, JSON.pretty_generate(summary) + "\n") if output_path

if errors.empty?
  puts "Blind review score gate passed for #{candidate_id}: #{reviewers.length} reviewers, #{selected_by_item.length} items"
  exit 0
end

warn "Blind review score check failed:"
errors.uniq.each { |error| warn "- #{error}" }
exit 1
