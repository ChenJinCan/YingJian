#!/usr/bin/env ruby

require "digest"
require "pathname"
require "yaml"

repo_root = File.expand_path("..", __dir__)
allow_incomplete = ARGV.delete("--allow-incomplete")
manifest_argument = ARGV.shift || "quality/corpus-manifest.yaml"
manifest_path = File.expand_path(manifest_argument, repo_root)

errors = []

unless File.file?(manifest_path)
  warn "Image quality corpus manifest is missing: #{manifest_argument}"
  exit 1
end

begin
  manifest = YAML.safe_load(File.read(manifest_path), permitted_classes: [], aliases: false)
rescue Psych::Exception => error
  warn "Image quality corpus manifest is invalid YAML: #{error.message}"
  exit 1
end
unless manifest.is_a?(Hash)
  warn "Image quality corpus manifest must be a mapping"
  exit 1
end

errors << "schema must equal 1" unless manifest["schema"] == 1
status = manifest["status"]
unless ["blocked_missing_assets", "ready"].include?(status)
  errors << "status must be blocked_missing_assets or ready"
end

corpus_root_value = manifest["corpus_root"]
if !corpus_root_value.is_a?(String) || corpus_root_value.empty?
  errors << "corpus_root must be a non-empty relative path"
  corpus_root = repo_root
else
  path = Pathname.new(corpus_root_value)
  errors << "corpus_root must be relative" if path.absolute?
  errors << "corpus_root must not escape the repository" if path.each_filename.include?("..")
  corpus_root = File.expand_path(corpus_root_value, repo_root)
end

assets = manifest["assets"]
unless assets.is_a?(Array)
  errors << "assets must be a list"
  assets = []
end

minimum_assets = manifest["minimum_assets"]
minimum_group_sets = manifest["minimum_group_sets"]
minimum_members_per_group = manifest["minimum_members_per_group"]
minimum_tag_counts = manifest["minimum_tag_counts"]

errors << "minimum_assets must be a positive integer" unless minimum_assets.is_a?(Integer) && minimum_assets.positive?
errors << "minimum_group_sets must be a positive integer" unless minimum_group_sets.is_a?(Integer) && minimum_group_sets.positive?
unless minimum_members_per_group.is_a?(Integer) && minimum_members_per_group.positive?
  errors << "minimum_members_per_group must be a positive integer"
end
unless minimum_tag_counts.is_a?(Hash) && minimum_tag_counts.values.all? { |count| count.is_a?(Integer) && count.positive? }
  errors << "minimum_tag_counts must map tags to positive integers"
  minimum_tag_counts = {}
end

ids = {}
files = {}
hashes = {}
tag_counts = Hash.new(0)
group_counts = Hash.new(0)

assets.each_with_index do |asset, index|
  prefix = "assets[#{index}]"
  unless asset.is_a?(Hash)
    errors << "#{prefix} must be a mapping"
    next
  end

  id = asset["id"]
  relative_file = asset["file"]
  sha256 = asset["sha256"]
  tags = asset["tags"]
  license = asset["license"]

  if !id.is_a?(String) || id.empty?
    errors << "#{prefix}.id must be a non-empty string"
  elsif ids.key?(id)
    errors << "duplicate asset id: #{id}"
  else
    ids[id] = true
  end

  safe_relative_file = false
  if !relative_file.is_a?(String) || relative_file.empty?
    errors << "#{prefix}.file must be a non-empty relative path"
  else
    path = Pathname.new(relative_file)
    if path.absolute? || path.each_filename.include?("..")
      errors << "#{prefix}.file must remain inside corpus_root"
    elsif files.key?(relative_file)
      errors << "duplicate asset file: #{relative_file}"
    else
      files[relative_file] = true
      safe_relative_file = true
    end
  end

  unless sha256.is_a?(String) && sha256.match?(/\A[0-9a-f]{64}\z/)
    errors << "#{prefix}.sha256 must be a lowercase SHA-256"
  else
    errors << "duplicate asset content hash: #{sha256}" if hashes.key?(sha256)
    hashes[sha256] = true
  end

  if !tags.is_a?(Array) || tags.empty? || !tags.all? { |tag| tag.is_a?(String) && !tag.empty? }
    errors << "#{prefix}.tags must be a non-empty string list"
  else
    tags.uniq.each { |tag| tag_counts[tag] += 1 }
    if tags.include?("group_member")
      group_id = asset["group_id"]
      if !group_id.is_a?(String) || group_id.empty?
        errors << "#{prefix}.group_id is required for group_member"
      else
        group_counts[group_id] += 1
      end
    end
  end

  valid_license = license.is_a?(Hash) &&
         license["source_type"].is_a?(String) && !license["source_type"].empty? &&
         license["rights_basis"].is_a?(String) && !license["rights_basis"].empty? &&
         license.key?("redistributable") &&
         [true, false].include?(license["redistributable"]) &&
         license["evidence_ref"].is_a?(String) && !license["evidence_ref"].empty?
  unless valid_license
    errors << "#{prefix}.license must include source_type, rights_basis, redistributable, and evidence_ref"
  else
    evidence_path = Pathname.new(license["evidence_ref"])
    if evidence_path.absolute? || evidence_path.each_filename.include?("..")
      errors << "#{prefix}.license.evidence_ref must remain inside the repository"
    elsif !File.file?(File.expand_path(license["evidence_ref"], repo_root))
      errors << "#{prefix}.license.evidence_ref is missing"
    end
  end

  next unless safe_relative_file

  full_path = File.expand_path(relative_file, corpus_root)
  unless full_path.start_with?("#{corpus_root}/")
    errors << "#{prefix}.file resolves outside corpus_root"
    next
  end
  unless File.file?(full_path)
    errors << "#{prefix}.file is missing"
    next
  end
  if sha256.is_a?(String) && sha256.match?(/\A[0-9a-f]{64}\z/)
    actual = Digest::SHA256.file(full_path).hexdigest
    errors << "#{prefix}.sha256 does not match the file" unless actual == sha256
  end
end

unless allow_incomplete
  errors << "status must be ready for the complete gate" unless status == "ready"
  errors << "asset count #{assets.length} is below #{minimum_assets}" if minimum_assets.is_a?(Integer) && assets.length < minimum_assets
  if minimum_group_sets.is_a?(Integer)
    complete_groups = group_counts.count { |_group_id, count| minimum_members_per_group.is_a?(Integer) && count >= minimum_members_per_group }
    errors << "complete group set count #{complete_groups} is below #{minimum_group_sets}" if complete_groups < minimum_group_sets
  end
  minimum_tag_counts.each do |tag, minimum|
    errors << "tag #{tag} count #{tag_counts[tag]} is below #{minimum}" if tag_counts[tag] < minimum
  end
end

if errors.empty?
  mode = allow_incomplete ? "schema-only" : "complete"
  puts "Image quality corpus check passed (#{mode}, #{assets.length} assets)"
  exit 0
end

warn "Image quality corpus check failed:"
errors.each { |error| warn "- #{error}" }
exit 1
