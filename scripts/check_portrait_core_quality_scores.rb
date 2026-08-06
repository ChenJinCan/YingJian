#!/usr/bin/env ruby

require "csv"
require "digest"
require "json"
require "yaml"

CAPABILITIES = %w[
  one_tap_natural
  texture_smoothing
  skin_tone_lighting
  blemish_reduction
  face_slimming
  torso_slimming
].freeze
SCORE_DIMENSIONS = %w[naturalness identity_preservation protection].freeze
COMPARISON_VALUES = %w[yingjian_win tie xingtu_win].freeze
REQUIRED_HEADERS = %w[
  reviewer_id item_id naturalness identity_preservation protection
  catastrophic_error preferred_over_original comparison_to_xingtu notes
].freeze
XINGTU_IDENTITY = {
  "producer" => "xingtu",
  "app_store_id" => "1500526240",
  "bundle_id" => "com.xt.retouch",
}.freeze

def median(values)
  ordered = values.sort
  middle = ordered.length / 2
  ordered.length.odd? ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2.0
end

def parse_boolean(value)
  return true if value == "true" || value == true
  return false if value == "false" || value == false
  nil
end

def concrete_string?(value)
  value.is_a?(String) && !value.strip.empty?
end

def inside_directory?(path, directory)
  real = File.realpath(path)
  root = File.realpath(directory)
  real == root || real.start_with?("#{root}/")
rescue Errno::ENOENT, Errno::EACCES
  false
end

def validate_file_binding(binding, label:, quality_root:, errors:)
  unless binding.is_a?(Hash) && concrete_string?(binding["file"]) &&
      binding["sha256"].is_a?(String) && binding["sha256"].match?(/\A[0-9a-f]{64}\z/)
    errors << "#{label} file binding is incomplete"
    return nil
  end
  path = File.expand_path(binding["file"])
  unless File.file?(path) && inside_directory?(path, quality_root)
    errors << "#{label} must be a file inside the ignored .quality directory"
    return nil
  end
  actual = Digest::SHA256.file(path).hexdigest
  errors << "#{label}.sha256 does not match the file" unless actual == binding["sha256"]
  actual
end

def fail_with(errors, summary, output_path)
  summary["status"] = errors.empty? ? "passed" : "failed"
  summary["errors"] = errors.uniq
  File.write(output_path, JSON.pretty_generate(summary) + "\n") if output_path
  return false if errors.empty?
  warn "Portrait core quality score check failed:"
  errors.uniq.each { |error| warn "- #{error}" }
  true
end

plan_argument = ARGV.shift
scores_argument = ARGV.shift
output_index = ARGV.index("--output")
output_path = output_index && ARGV[output_index + 1]
unless plan_argument && scores_argument
  warn "Portrait core quality score check failed: usage: check_portrait_core_quality_scores.rb PLAN.yaml SCORES.csv [--output SUMMARY.json]"
  exit 1
end

repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
errors = []
summary = {
  "schema" => 1,
  "review_id" => nil,
  "blind_protocol" => nil,
  "reviewer_count" => 0,
  "item_count" => 0,
  "capabilities" => {},
}

begin
  plan_path = File.expand_path(plan_argument)
  unless File.file?(plan_path) && inside_directory?(plan_path, quality_root)
    raise Errno::ENOENT, "plan must be a file inside the ignored .quality directory"
  end
  plan = YAML.safe_load(File.read(plan_path), permitted_classes: [], aliases: false)
rescue Errno::ENOENT, Errno::EACCES, Psych::Exception => error
  warn "Portrait core quality score check failed: plan is unavailable: #{error.message}"
  exit 1
end

unless plan.is_a?(Hash) && plan["schema"] == 1 && plan["task"] == "portrait_core_parity"
  errors << "plan must use portrait_core_parity schema 1"
end
summary["review_id"] = plan["review_id"]
errors << "review_id must be a concrete string" unless concrete_string?(plan["review_id"])
minimum_reviewers = plan["minimum_reviewers"]
unless minimum_reviewers.is_a?(Integer) && minimum_reviewers >= 5
  errors << "minimum_reviewers must be at least 5"
  minimum_reviewers = 5
end

blind_protocol = plan["blind_protocol"]
if blind_protocol.is_a?(Hash)
  errors << "blind_protocol.randomized must equal true" unless blind_protocol["randomized"] == true
  unless blind_protocol["method"] == "seeded_candidate_position_shuffle"
    errors << "blind_protocol.method must equal seeded_candidate_position_shuffle"
  end
  seed_sha256 = blind_protocol["seed_sha256"]
  unless seed_sha256.is_a?(String) && seed_sha256.match?(/\A[0-9a-f]{64}\z/)
    errors << "blind_protocol.seed_sha256 must be a lowercase SHA-256"
  end
  mapping_sha256 = validate_file_binding(
    blind_protocol["mapping"],
    label: "blind_protocol.mapping",
    quality_root: quality_root,
    errors: errors,
  )
  summary["blind_protocol"] = {
    "randomized" => blind_protocol["randomized"] == true,
    "method" => blind_protocol["method"],
    "mapping_sha256" => mapping_sha256,
  }
else
  errors << "blind_protocol must be a mapping"
end

items = plan["items"]
unless items.is_a?(Array) && !items.empty?
  errors << "items must be a non-empty list"
  items = []
end
items_by_id = {}
items_by_capability = Hash.new { |hash, key| hash[key] = [] }
items.each_with_index do |item, index|
  prefix = "items[#{index}]"
  unless item.is_a?(Hash)
    errors << "#{prefix} must be a mapping"
    next
  end
  item_id = item["id"]
  capability = item["capability"]
  if !concrete_string?(item_id)
    errors << "#{prefix}.id must be a concrete string"
    next
  elsif items_by_id.key?(item_id)
    errors << "duplicate item id #{item_id}"
    next
  end
  items_by_id[item_id] = item
  unless CAPABILITIES.include?(capability)
    errors << "#{prefix}.capability is unsupported: #{capability.inspect}"
    next
  end
  items_by_capability[capability] << item
  tags = item["tags"]
  unless tags.is_a?(Array) && !tags.empty? && tags.all? { |tag| concrete_string?(tag) } && tags.uniq == tags
    errors << "#{prefix}.tags must be a non-empty unique string list"
  end

  source_sha = validate_file_binding(item["source"], label: "#{prefix}.source", quality_root: quality_root, errors: errors)
  subject = item["subject"]
  competitor = item["competitor"]
  validate_file_binding(subject, label: "#{prefix}.subject", quality_root: quality_root, errors: errors)
  validate_file_binding(competitor, label: "#{prefix}.competitor", quality_root: quality_root, errors: errors)
  if subject.is_a?(Hash)
    errors << "#{prefix}.subject.producer must equal yingjian" unless subject["producer"] == "yingjian"
    errors << "#{prefix}.subject.effect_version must be concrete" unless concrete_string?(subject["effect_version"])
    errors << "#{prefix}.subject.parameters must be a non-empty mapping" unless subject["parameters"].is_a?(Hash) && !subject["parameters"].empty?
    errors << "#{prefix}.subject.operation_path must be concrete" unless concrete_string?(subject["operation_path"])
    unless source_sha && subject["source_sha256"] == source_sha
      errors << "#{prefix}.subject does not bind the same source"
    end
  else
    errors << "#{prefix}.subject must be a mapping"
  end
  if competitor.is_a?(Hash)
    XINGTU_IDENTITY.each do |field, value|
      errors << "#{prefix}.competitor.#{field} must equal #{value}" unless competitor[field] == value
    end
    errors << "#{prefix}.competitor.version must be concrete" unless concrete_string?(competitor["version"])
    errors << "#{prefix}.competitor.parameters must be a non-empty mapping" unless competitor["parameters"].is_a?(Hash) && !competitor["parameters"].empty?
    errors << "#{prefix}.competitor.operation_path must be concrete" unless concrete_string?(competitor["operation_path"])
    unless source_sha && competitor["source_sha256"] == source_sha
      errors << "#{prefix}.competitor does not bind the same source"
    end
  else
    errors << "#{prefix}.competitor must be a mapping"
  end
end

CAPABILITIES.each do |capability|
  capability_items = items_by_capability[capability]
  if capability_items.empty?
    errors << "missing capability #{capability}"
    next
  end
  unless capability_items.any? { |item| item.fetch("tags", []).include?("improvable") }
    errors << "capability #{capability} has no improvable item"
  end
  unless capability_items.any? { |item| item.fetch("tags", []).include?("protection") }
    errors << "capability #{capability} has no protection item"
  end
  unless capability_items.any? { |item| item.fetch("tags", []).include?("negative_safety") }
    errors << "capability #{capability} has no negative_safety item"
  end
end
summary["item_count"] = items_by_id.length

begin
  table = CSV.read(scores_argument, headers: true)
rescue Errno::ENOENT, Errno::EACCES, CSV::MalformedCSVError => error
  warn "Portrait core quality score check failed: scores are unavailable: #{error.message}"
  exit 1
end
missing_headers = REQUIRED_HEADERS - (table.headers || [])
errors << "score sheet is missing headers: #{missing_headers.join(", ")}" unless missing_headers.empty?

rows = []
seen = {}
table.each_with_index do |row, index|
  prefix = "row #{index + 2}"
  reviewer_id = row["reviewer_id"]
  item_id = row["item_id"]
  unless concrete_string?(reviewer_id)
    errors << "#{prefix}.reviewer_id must be concrete"
    next
  end
  unless items_by_id.key?(item_id)
    errors << "#{prefix}.item_id is unknown: #{item_id.inspect}"
    next
  end
  identity = [reviewer_id, item_id]
  if seen[identity]
    errors << "duplicate score for reviewer #{reviewer_id} and item #{item_id}"
    next
  end
  seen[identity] = true
  scores = {}
  SCORE_DIMENSIONS.each do |dimension|
    value = Integer(row[dimension], exception: false)
    if !value || !(1..5).include?(value)
      errors << "#{prefix}.#{dimension} must be an integer from 1 to 5"
    else
      scores[dimension] = value
    end
  end
  catastrophic = parse_boolean(row["catastrophic_error"])
  preferred = parse_boolean(row["preferred_over_original"])
  comparison = row["comparison_to_xingtu"]
  errors << "#{prefix}.catastrophic_error must be true or false" if catastrophic.nil?
  errors << "#{prefix}.preferred_over_original must be true or false" if preferred.nil?
  errors << "#{prefix}.comparison_to_xingtu is invalid" unless COMPARISON_VALUES.include?(comparison)
  rows << {
    "reviewer_id" => reviewer_id,
    "item_id" => item_id,
    "capability" => items_by_id[item_id]["capability"],
    "tags" => items_by_id[item_id].fetch("tags", []),
    "scores" => scores,
    "catastrophic" => catastrophic,
    "preferred" => preferred,
    "comparison" => comparison,
  }
end

reviewers = rows.map { |row| row["reviewer_id"] }.uniq.sort
summary["reviewer_count"] = reviewers.length
errors << "reviewer count #{reviewers.length} is below #{minimum_reviewers}" if reviewers.length < minimum_reviewers
reviewers.each do |reviewer_id|
  items_by_id.each_key do |item_id|
    errors << "reviewer #{reviewer_id} is missing score for item #{item_id}" unless seen[[reviewer_id, item_id]]
  end
end

CAPABILITIES.each do |capability|
  capability_rows = rows.select { |row| row["capability"] == capability }
  improvable_rows = capability_rows.select { |row| row["tags"].include?("improvable") }
  medians = SCORE_DIMENSIONS.to_h do |dimension|
    values = capability_rows.map { |row| row["scores"][dimension] }.compact
    [dimension, values.empty? ? nil : median(values)]
  end
  preference_rate = if improvable_rows.empty?
    nil
  else
    improvable_rows.count { |row| row["preferred"] == true }.to_f / improvable_rows.length
  end
  parity_rate = if capability_rows.empty?
    nil
  else
    capability_rows.count { |row| %w[yingjian_win tie].include?(row["comparison"]) }.to_f / capability_rows.length
  end
  catastrophic_count = capability_rows.count { |row| row["catastrophic"] == true }
  capability_errors = []
  capability_errors << "#{capability} has no scored improvable rows" if preference_rate.nil?
  if preference_rate && preference_rate < 0.65
    capability_errors << format("%s preference rate %.3f is below 0.650", capability, preference_rate)
  end
  capability_errors << "#{capability} has no scored rows" if parity_rate.nil?
  if parity_rate && parity_rate < 0.50
    capability_errors << format("%s Xingtu win-or-tie rate %.3f is below 0.500", capability, parity_rate)
  end
  SCORE_DIMENSIONS.each do |dimension|
    if medians[dimension].nil? || medians[dimension] < 4.0
      capability_errors << "#{capability} #{dimension} median is below 4.0"
    end
    if capability_rows.any? { |row| row["scores"][dimension] == 1 }
      capability_errors << "#{capability} #{dimension} contains a forbidden score of 1"
    end
  end
  capability_errors << "#{capability} catastrophic errors reported: #{catastrophic_count}" if catastrophic_count.positive?
  errors.concat(capability_errors)
  summary["capabilities"][capability] = {
    "item_count" => capability_rows.map { |row| row["item_id"] }.uniq.length,
    "score_row_count" => capability_rows.length,
    "medians" => medians,
    "preference_over_original_rate" => preference_rate,
    "xingtu_win_or_tie_rate" => parity_rate,
    "catastrophic_error_count" => catastrophic_count,
    "coverage_counts" => capability_rows.flat_map { |row| row["tags"] }.each_with_object(Hash.new(0)) do |tag, counts|
      counts[tag] += 1
    end.sort.to_h,
    "status" => capability_errors.empty? ? "passed" : "failed",
  }
end

failed = fail_with(errors, summary, output_path)
if failed
  exit 1
end

puts "Portrait core quality score gate passed: #{reviewers.length} reviewers, #{items_by_id.length} items, six capabilities"
