#!/usr/bin/env ruby

require "csv"
require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "yaml"

def fail_with(message)
  warn "Blind review package build failed: #{message}"
  exit 1
end

plan_argument = ARGV.shift
output_argument = ARGV.shift
seed_index = ARGV.index("--seed")
seed = seed_index && ARGV[seed_index + 1]
if !plan_argument || !output_argument || !seed || seed.empty?
  fail_with("usage: build_blind_review_package.rb PLAN OUTPUT --seed VALUE")
end

plan_path = File.expand_path(plan_argument)
output_path = File.expand_path(output_argument)
repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
FileUtils.mkdir_p(quality_root)
quality_root_real = File.realpath(quality_root)

def inside_real_directory?(path, root)
  real = File.realpath(path)
  real == root || real.start_with?("#{root}/")
rescue Errno::ENOENT
  false
end

output_ancestor = output_path
output_ancestor = File.dirname(output_ancestor) until File.exist?(output_ancestor)
unless inside_real_directory?(output_ancestor, quality_root_real)
  fail_with("output must remain inside the ignored .quality directory")
end
if File.exist?(output_path) && !inside_real_directory?(output_path, quality_root_real)
  fail_with("output must not resolve through a symlink outside .quality")
end
unless inside_real_directory?(plan_path, quality_root_real)
  fail_with("plan must remain inside the ignored .quality directory")
end
fail_with("plan is missing: #{plan_argument}") unless File.file?(plan_path)
if File.exist?(output_path)
  fail_with("output path must be a directory") unless File.directory?(output_path)
  fail_with("output directory must be absent or empty") unless Dir.empty?(output_path)
end

begin
  plan = YAML.safe_load(File.read(plan_path), permitted_classes: [], aliases: false)
rescue Psych::Exception => error
  fail_with("plan is invalid YAML: #{error.message}")
end
fail_with("plan must be a mapping") unless plan.is_a?(Hash)
fail_with("schema must equal 1") unless plan["schema"] == 1
review_id = plan["review_id"]
task = plan["task"]
minimum_reviewers = plan["minimum_reviewers"]
items = plan["items"]
fail_with("review_id must be a non-empty string") unless review_id.is_a?(String) && !review_id.empty?
fail_with("task must equal portrait") unless task == "portrait"
unless minimum_reviewers.is_a?(Integer) && minimum_reviewers >= 5
  fail_with("minimum_reviewers must be at least 5")
end
fail_with("items must be a non-empty list") unless items.is_a?(Array) && !items.empty?

plan_directory = File.dirname(plan_path)
asset_ids = {}
validated = items.map.with_index do |item, item_index|
  prefix = "items[#{item_index}]"
  fail_with("#{prefix} must be a mapping") unless item.is_a?(Hash)
  asset_id = item["asset_id"]
  tags = item["tags"]
  candidates = item["candidates"]
  fail_with("#{prefix}.asset_id must be a non-empty string") unless asset_id.is_a?(String) && !asset_id.empty?
  fail_with("duplicate asset_id: #{asset_id}") if asset_ids[asset_id]
  asset_ids[asset_id] = true
  unless tags.is_a?(Array) && tags.all? { |tag| tag.is_a?(String) && !tag.empty? }
    fail_with("#{prefix}.tags must be a string list")
  end
  unless candidates.is_a?(Array) && !candidates.empty?
    fail_with("#{prefix}.candidates must be a non-empty list")
  end
  candidate_ids = {}
  normalized_candidates = candidates.map.with_index do |candidate, candidate_index|
    candidate_prefix = "#{prefix}.candidates[#{candidate_index}]"
    fail_with("#{candidate_prefix} must be a mapping") unless candidate.is_a?(Hash)
    candidate_id = candidate["id"]
    role = candidate["role"]
    provenance = candidate["provenance"]
    file_value = candidate["file"]
    expected_hash = candidate["sha256"]
    unless candidate_id.is_a?(String) && !candidate_id.empty?
      fail_with("#{candidate_prefix}.id must be a non-empty string")
    end
    fail_with("duplicate candidate id #{candidate_id} for #{asset_id}") if candidate_ids[candidate_id]
    candidate_ids[candidate_id] = true
    unless %w[baseline_original subject reference].include?(role)
      fail_with("#{candidate_prefix}.role must be baseline_original, subject, or reference")
    end
    unless provenance.is_a?(Hash)
      fail_with("#{candidate_prefix}.provenance must be a mapping")
    end
    %w[producer version device os variant render_kind].each do |name|
      value = provenance[name]
      unless value.is_a?(String) && !value.empty?
        fail_with("#{candidate_prefix}.provenance.#{name} must be a non-empty string")
      end
    end
    unless provenance["parameters"].is_a?(Hash)
      fail_with("#{candidate_prefix}.provenance.parameters must be a mapping")
    end
    expected_producer = {
      "baseline_original" => "original",
      "subject" => "yingjian",
      "reference" => "competitor",
    }.fetch(role)
    unless provenance["producer"] == expected_producer
      fail_with("#{candidate_prefix}.provenance.producer must equal #{expected_producer}")
    end
    unless file_value.is_a?(String) && !file_value.empty?
      fail_with("#{candidate_prefix}.file must be a non-empty path")
    end
    file_path = Pathname.new(file_value).absolute? ? file_value : File.expand_path(file_value, plan_directory)
    fail_with("#{candidate_prefix}.file is missing") unless File.file?(file_path)
    unless inside_real_directory?(file_path, quality_root_real)
      fail_with("#{candidate_prefix}.file must remain inside the ignored .quality directory")
    end
    extension = File.extname(file_path).downcase
    unless %w[.jpg .jpeg .png].include?(extension)
      fail_with("#{candidate_prefix}.file must be a browser-reviewable JPEG or PNG")
    end
    unless expected_hash.is_a?(String) && expected_hash.match?(/\A[0-9a-f]{64}\z/)
      fail_with("#{candidate_prefix}.sha256 must be a lowercase SHA-256")
    end
    actual_hash = Digest::SHA256.file(file_path).hexdigest
    fail_with("#{candidate_prefix}.sha256 does not match the file") unless actual_hash == expected_hash
    {
      "candidate_id" => candidate_id,
      "role" => role,
      "provenance" => provenance,
      "file" => File.expand_path(file_path),
      "sha256" => actual_hash,
      "extension" => extension,
    }
  end
  baseline_count = normalized_candidates.count { |candidate| candidate["role"] == "baseline_original" }
  fail_with("#{prefix} must contain exactly one baseline_original") unless baseline_count == 1
  baseline_hash = normalized_candidates.find { |candidate| candidate["role"] == "baseline_original" }["sha256"]
  normalized_candidates.reject { |candidate| candidate["role"] == "baseline_original" }.each do |candidate|
    unless candidate["provenance"]["source_sha256"] == baseline_hash
      fail_with("#{prefix} #{candidate["candidate_id"]} source_sha256 must match baseline_original")
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
  expected_slots.each do |role, variant, render_kind|
    matches = normalized_candidates.select do |candidate|
      provenance = candidate["provenance"]
      candidate["role"] == role && provenance["variant"] == variant &&
        provenance["render_kind"] == render_kind
    end
    unless matches.length == 1
      fail_with("#{prefix} must contain exactly one #{role} #{variant} #{render_kind}")
    end
  end
  fail_with("#{prefix}.candidates must contain exactly six matrix results") unless normalized_candidates.length == 6
  competitor = normalized_candidates.find { |candidate| candidate["role"] == "reference" }
  operation_path = competitor["provenance"]["operation_path"]
  unless operation_path.is_a?(String) && !operation_path.empty?
    fail_with("#{prefix} competitor fixed_path export requires operation_path")
  end
  rendered = normalized_candidates.reject { |candidate| candidate["role"] == "baseline_original" }
  %w[device os].each do |field|
    values = rendered.map { |candidate| candidate["provenance"][field] }.uniq
    fail_with("#{prefix} rendered candidates must share #{field}") unless values.length == 1
  end
  subjects = normalized_candidates.select { |candidate| candidate["role"] == "subject" }
  %w[version device os].each do |field|
    values = subjects.map { |candidate| candidate["provenance"][field] }.uniq
    fail_with("#{prefix} subject candidates must share #{field}") unless values.length == 1
  end
  default_renders = subjects.select { |candidate| candidate["provenance"]["variant"] == "default" }
  unless default_renders.map { |candidate| candidate["provenance"]["parameters"] }.uniq.length == 1
    fail_with("#{prefix} subject default preview and export must share parameters")
  end
  {
    "asset_id" => asset_id,
    "tags" => tags.uniq.sort,
    "candidates" => normalized_candidates,
  }
end

participant_path = File.join(output_path, "participant-package")
FileUtils.mkdir_p(File.join(participant_path, "images"))
sanitizer_path = File.join(output_path, ".sanitize-review-image")
sanitizer_source = File.join(repo_root, "scripts/support/sanitize_review_image.swift")
_stdout, stderr, compiled = Open3.capture3(
  "/usr/bin/xcrun", "swiftc", sanitizer_source, "-o", sanitizer_path,
)
fail_with("review image sanitizer could not compile: #{stderr.strip}") unless compiled.success?
review_key = {
  "schema" => 1,
  "review_id" => review_id,
  "task" => task,
  "minimum_reviewers" => minimum_reviewers,
  "source_plan" => {
    "file" => plan_path,
    "sha256" => Digest::SHA256.file(plan_path).hexdigest,
  },
  "seed" => seed,
  "seed_sha256" => Digest::SHA256.hexdigest(seed),
  "items" => [],
}

ordered_items = validated.sort_by do |item|
  Digest::SHA256.hexdigest("#{seed}|item|#{item["asset_id"]}")
end
page_items = []
ordered_items.each_with_index do |item, item_index|
  item_code = format("I%03d", item_index + 1)
  ordered_candidates = item["candidates"].sort_by do |candidate|
    Digest::SHA256.hexdigest("#{seed}|#{item["asset_id"]}|#{candidate["candidate_id"]}")
  end
  key_candidates = []
  page_candidates = []
  ordered_candidates.each_with_index do |candidate, candidate_index|
    candidate_code = format("C%02d", candidate_index + 1)
    filename = "#{item_code}-#{candidate_code}.png"
    review_image = File.join(participant_path, "images", filename)
    stdout, stderr, sanitized = Open3.capture3(sanitizer_path, candidate["file"], review_image)
    fail_with("could not sanitize #{item_code} #{candidate_code}: #{stderr.strip}") unless sanitized.success?
    normalized_pixel_sha256 = stdout.strip
    unless normalized_pixel_sha256.match?(/\A[0-9a-f]{64}\z/)
      fail_with("sanitizer did not return a normalized pixel SHA-256")
    end
    key_candidates << candidate.merge(
      "candidate_code" => candidate_code,
      "review_file" => "images/#{filename}",
      "normalized_raster_sha256" => Digest::SHA256.file(review_image).hexdigest,
      "normalized_pixel_sha256" => normalized_pixel_sha256,
    )
    page_candidates << {
      "code" => candidate_code,
      "file" => "images/#{filename}",
      "is_baseline" => candidate["role"] == "baseline_original",
    }
  end
  baseline_code = page_candidates.find { |candidate| candidate["is_baseline"] }["code"]
  review_key["items"] << {
    "item_code" => item_code,
    "asset_id" => item["asset_id"],
    "tags" => item["tags"],
    "candidates" => key_candidates,
  }
  page_items << {
    "code" => item_code,
    "baseline_code" => baseline_code,
    "candidates" => page_candidates,
  }
end

File.write(
  File.join(output_path, "review-key.json"),
  JSON.pretty_generate(review_key) + "\n",
)

headers = %w[
  reviewer_id item_code baseline_code candidate_code overall_improvement naturalness
  identity_preservation texture_preservation skin_tone_lighting local_boundaries
  non_skin_protection catastrophic_error preferred_over_baseline notes
]
CSV.open(File.join(participant_path, "score-sheet.csv"), "w") do |csv|
  csv << headers
  page_items.each do |item|
    item["candidates"].each do |candidate|
      csv << [nil, item["code"], item["baseline_code"], candidate["code"]]
    end
  end
end

cards = page_items.map do |item|
  images = item["candidates"].map do |candidate|
    <<~HTML
      <figure><img src="#{candidate["file"]}" alt="#{item["code"]} #{candidate["code"]}"><figcaption>#{candidate["code"]}#{candidate["is_baseline"] ? " · 原图锚点" : ""}</figcaption></figure>
    HTML
  end.join
  <<~HTML
    <section><h2>#{item["code"]}</h2><div class="grid">#{images}</div></section>
  HTML
end.join

html = <<~HTML
  <!doctype html>
  <html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>匿名图片评审</title>
  <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:24px;background:#111;color:#f5f5f5}section{margin:0 0 48px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}figure{margin:0;background:#222;border-radius:16px;overflow:hidden}img{display:block;width:100%;height:auto}figcaption{padding:10px;text-align:center;font-weight:700}.note{color:#bbb;max-width:760px}</style>
  </head><body><h1>匿名图片评审</h1><p class="note">请在校准显示环境中查看，可放大检查纹理与边界。按 1–5 分填写 score-sheet.csv；任何灾难性身份或边界破坏请标记 catastrophic_error=true。候选身份保存在独立 review-key.json 中，评审期间不要打开。</p>#{cards}</body></html>
HTML
File.write(File.join(participant_path, "index.html"), html)
FileUtils.rm_f(sanitizer_path)

puts "Blind review package built: #{page_items.length} items, #{review_key["items"].sum { |item| item["candidates"].length }} results"
