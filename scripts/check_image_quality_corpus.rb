#!/usr/bin/env ruby

require "digest"
require "open3"
require "pathname"
require "yaml"

repo_root = File.expand_path("..", __dir__)
allow_incomplete = ARGV.delete("--allow-incomplete")
asset_contract_only = ARGV.delete("--asset-contract-only")
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

errors << "schema must equal 2" unless manifest["schema"] == 2
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
if File.exist?(corpus_root)
  begin
    repo_real = File.realpath(repo_root)
    corpus_real = File.realpath(corpus_root)
    unless corpus_real.start_with?("#{repo_real}/")
      errors << "corpus_root resolves outside the repository"
    end
  rescue SystemCallError
    errors << "corpus_root could not be resolved"
  end
end

assets = manifest["assets"]
unless assets.is_a?(Array)
  errors << "assets must be a list"
  assets = []
end

required_assets = nil
required_single_assets = nil
required_group_sets = nil
required_members_per_group = nil
minimum_tag_counts = {}
unless asset_contract_only
  required_assets = manifest["required_assets"]
  required_single_assets = manifest["required_single_assets"]
  required_group_sets = manifest["required_group_sets"]
  required_members_per_group = manifest["required_members_per_group"]
  minimum_tag_counts = manifest["minimum_tag_counts"]

  errors << "required_assets must be a positive integer" unless required_assets.is_a?(Integer) && required_assets.positive?
  unless required_single_assets.is_a?(Integer) && required_single_assets >= 0
    errors << "required_single_assets must be a non-negative integer"
  end
  errors << "required_group_sets must be a positive integer" unless required_group_sets.is_a?(Integer) && required_group_sets.positive?
  unless required_members_per_group.is_a?(Integer) && required_members_per_group.positive?
    errors << "required_members_per_group must be a positive integer"
  end
  unless minimum_tag_counts.is_a?(Hash) && minimum_tag_counts.values.all? { |count| count.is_a?(Integer) && count.positive? }
    errors << "minimum_tag_counts must map tags to positive integers"
    minimum_tag_counts = {}
  end
end

ids = {}
files = {}
hashes = {}
tag_counts = Hash.new(0)
group_counts = Hash.new(0)
single_asset_count = 0

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
  media = asset["media"]

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
    else
      single_asset_count += 1
      if asset.key?("group_id")
        errors << "#{prefix}.group_id is only allowed for group_member"
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
    elsif !license["evidence_ref"].start_with?(".quality/evidence/")
      errors << "#{prefix}.license.evidence_ref must remain inside .quality/evidence"
    else
      evidence_file = File.expand_path(license["evidence_ref"], repo_root)
      if !File.file?(evidence_file)
        errors << "#{prefix}.license.evidence_ref is missing"
      else
        evidence_root = File.expand_path(".quality/evidence", repo_root)
        evidence_real = File.realpath(evidence_file)
        unless evidence_real.start_with?("#{evidence_root}/")
          errors << "#{prefix}.license.evidence_ref resolves outside .quality/evidence"
        end
      end
    end
  end

  valid_media = media.is_a?(Hash) &&
                ["jpeg", "png", "heic"].include?(media["format"]) &&
                media["width"].is_a?(Integer) && media["width"].positive? &&
                media["height"].is_a?(Integer) && media["height"].positive? &&
                ["srgb", "display_p3"].include?(media["color_space"]) &&
                media["orientation"].is_a?(Integer) && (1..8).cover?(media["orientation"])
  unless valid_media
    errors << "#{prefix}.media must include format, positive width/height, color_space, and orientation"
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
  begin
    real_path = File.realpath(full_path)
    resolved_corpus_root = File.realpath(corpus_root)
    unless real_path.start_with?("#{resolved_corpus_root}/")
      errors << "#{prefix}.file resolves outside corpus_root"
      next
    end
  rescue SystemCallError
    errors << "#{prefix}.file could not be resolved"
    next
  end
  if sha256.is_a?(String) && sha256.match?(/\A[0-9a-f]{64}\z/)
    actual = Digest::SHA256.file(full_path).hexdigest
    errors << "#{prefix}.sha256 does not match the file" unless actual == sha256
  end

  begin
    stdout, stderr, probe_status = Open3.capture3(
      "sips",
      "-g", "pixelWidth",
      "-g", "pixelHeight",
      "-g", "format",
      "-g", "profile",
      "-g", "orientation",
      full_path,
    )
  rescue Errno::ENOENT
    errors << "#{prefix}.file media probe unavailable: macOS sips was not found"
    next
  end
  unless probe_status.success?
    errors << "#{prefix}.file media probe failed: #{stderr.lines.first&.strip || "unknown error"}"
    next
  end
  probed = stdout.each_line.each_with_object({}) do |line, values|
    match = line.match(/^\s+(pixelWidth|pixelHeight|format|profile|orientation):\s*(.+)$/)
    values[match[1]] = match[2].strip if match
  end
  actual_format = probed["format"] == "heif" ? "heic" : probed["format"]
  actual_width = Integer(probed["pixelWidth"], exception: false)
  actual_height = Integer(probed["pixelHeight"], exception: false)
  actual_orientation = Integer(probed["orientation"], exception: false)
  if actual_orientation.nil?
    orientation_probe = File.join(repo_root, "scripts/support/probe_image_orientation.swift")
    orientation_stdout, orientation_stderr, orientation_status = Open3.capture3(
      "/usr/bin/xcrun",
      "swift",
      orientation_probe,
      full_path,
    )
    if orientation_status.success?
      actual_orientation = Integer(orientation_stdout.strip, exception: false)
    else
      detail = orientation_stderr.lines.first&.strip || "unknown error"
      errors << "#{prefix}.file ImageIO orientation probe failed: #{detail}"
    end
  end
  actual_color_space = if probed["profile"]&.match?(/display\s*p3|\bp3\b/i)
                         "display_p3"
                       elsif probed["profile"]&.match?(/srgb/i)
                         "srgb"
                       end
  if valid_media
    errors << "#{prefix}.media.format does not match the file" unless media["format"] == actual_format
    errors << "#{prefix}.media.width does not match the file" unless media["width"] == actual_width
    errors << "#{prefix}.media.height does not match the file" unless media["height"] == actual_height
    errors << "#{prefix}.media.orientation does not match the file" unless media["orientation"] == actual_orientation
    errors << "#{prefix}.media.color_space does not match the embedded profile" unless media["color_space"] == actual_color_space
  end
  if tags.is_a?(Array)
    errors << "#{prefix} is tagged jpeg but is not JPEG" if tags.include?("jpeg") && actual_format != "jpeg"
    errors << "#{prefix} is tagged png but is not PNG" if tags.include?("png") && actual_format != "png"
    errors << "#{prefix} is tagged heic but is not HEIC" if tags.include?("heic") && actual_format != "heic"
    errors << "#{prefix} is tagged srgb but is not tagged sRGB" if tags.include?("srgb") && actual_color_space != "srgb"
    if tags.include?("display_p3") && actual_color_space != "display_p3"
      errors << "#{prefix} is tagged display_p3 but is not tagged Display P3"
    end
    pixels = actual_width.to_i * actual_height.to_i
    if tags.include?("high_resolution") && pixels < 24_000_000
      errors << "#{prefix} is tagged high_resolution but is below 24 MP"
    end
    if tags.include?("exif_rotated") && actual_orientation == 1
      errors << "#{prefix} is tagged exif_rotated but has normal orientation"
    end
  end
  if actual_width.to_i * actual_height.to_i > 48_000_000
    errors << "#{prefix}.file exceeds the 48 MP input contract"
  end
  if [actual_width.to_i, actual_height.to_i].max > 12_000
    errors << "#{prefix}.file exceeds the 12,000 px edge contract"
  end
  errors << "#{prefix}.file exceeds the 100 MB input contract" if File.size(full_path) > 100 * 1024 * 1024
end

unless allow_incomplete || asset_contract_only
  errors << "status must be ready for the complete gate" unless status == "ready"
  if required_assets.is_a?(Integer) && assets.length != required_assets
    errors << "asset count #{assets.length} must equal #{required_assets}"
  end
  if required_single_assets.is_a?(Integer) && single_asset_count != required_single_assets
    errors << "single asset count #{single_asset_count} must equal #{required_single_assets}"
  end
  if required_group_sets.is_a?(Integer) && group_counts.length != required_group_sets
    errors << "group set count #{group_counts.length} must equal #{required_group_sets}"
  end
  if required_members_per_group.is_a?(Integer)
    group_counts.each do |group_id, count|
      unless count == required_members_per_group
        errors << "group #{group_id} member count #{count} must equal #{required_members_per_group}"
      end
    end
  end
  minimum_tag_counts.each do |tag, minimum|
    errors << "tag #{tag} count #{tag_counts[tag]} is below #{minimum}" if tag_counts[tag] < minimum
  end
end

if errors.empty?
  mode = if asset_contract_only
           "asset-contract"
         elsif allow_incomplete
           "schema-only"
         else
           "complete"
         end
  puts "Image quality corpus check passed (#{mode}, #{assets.length} assets)"
  exit 0
end

warn "Image quality corpus check failed:"
errors.each { |error| warn "- #{error}" }
exit 1
