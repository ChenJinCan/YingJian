#!/usr/bin/env ruby

require "csv"
require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

REPO_ROOT = File.expand_path("..", __dir__)
CHECKER = File.join(REPO_ROOT, "scripts/check_portrait_core_quality_scores.rb")
QUALITY_ROOT = File.join(REPO_ROOT, ".quality")
CAPABILITIES = %w[
  one_tap_natural
  texture_smoothing
  skin_tone_lighting
  blemish_reduction
  face_slimming
  torso_slimming
].freeze

def assert(condition, message)
  raise message unless condition
end

def write_asset(directory, name, content)
  path = File.join(directory, name)
  File.binwrite(path, content)
  {
    "file" => path,
    "sha256" => Digest::SHA256.file(path).hexdigest,
  }
end

def build_fixture(directory)
  blind_mapping = write_asset(
    directory,
    "blind-mapping.json",
    JSON.generate("A" => "yingjian", "B" => "xingtu"),
  )
  items = []
  CAPABILITIES.each do |capability|
    %w[improvable protection].each do |role|
      item_id = "#{capability}-#{role}"
      source = write_asset(directory, "#{item_id}-source.bin", "#{item_id}-source")
      subject = write_asset(directory, "#{item_id}-yingjian.bin", "#{item_id}-yingjian")
      competitor = write_asset(directory, "#{item_id}-xingtu.bin", "#{item_id}-xingtu")
      items << {
        "id" => item_id,
        "capability" => capability,
        "tags" => role == "improvable" ? ["improvable"] : ["protection", "negative_safety", "identity_detail"],
        "source" => source,
        "subject" => subject.merge(
          "source_sha256" => source["sha256"],
          "producer" => "yingjian",
          "effect_version" => "fixture-v1",
          "parameters" => { "strength" => 50 },
          "operation_path" => "Import existing image, open #{capability}, use strength 50, export",
        ),
        "competitor" => competitor.merge(
          "source_sha256" => source["sha256"],
          "producer" => "xingtu",
          "version" => "fixture-xingtu-v1",
          "app_store_id" => "1500526240",
          "bundle_id" => "com.xt.retouch",
          "parameters" => { "tool" => capability, "strength" => 50 },
          "operation_path" => "Import same existing image, use frozen #{capability} path, export",
        ),
      }
    end
  end
  plan = {
    "schema" => 1,
    "review_id" => "portrait-core-parity-fixture",
    "task" => "portrait_core_parity",
    "minimum_reviewers" => 5,
    "blind_protocol" => {
      "randomized" => true,
      "method" => "seeded_candidate_position_shuffle",
      "seed_sha256" => Digest::SHA256.hexdigest("fixture-randomization-seed"),
      "mapping" => blind_mapping,
    },
    "items" => items,
  }
  plan_path = File.join(directory, "plan.yaml")
  File.write(plan_path, YAML.dump(plan))

  rows = []
  5.times do |reviewer_index|
    items.each do |item|
      rows << {
        "reviewer_id" => "reviewer-#{reviewer_index + 1}",
        "item_id" => item["id"],
        "naturalness" => 4,
        "identity_preservation" => 5,
        "protection" => 4,
        "catastrophic_error" => false,
        "preferred_over_original" => item["tags"].include?("improvable"),
        "comparison_to_xingtu" => "tie",
        "notes" => "fixture",
      }
    end
  end
  scores_path = File.join(directory, "scores.csv")
  write_scores(scores_path, rows)
  [plan, plan_path, rows, scores_path]
end

def write_scores(path, rows)
  CSV.open(path, "w") do |csv|
    csv << rows.first.keys
    rows.each { |row| csv << row.values }
  end
end

def run_checker(plan_path, scores_path, output_path)
  Open3.capture3(
    "ruby", CHECKER, plan_path, scores_path, "--output", output_path,
    chdir: REPO_ROOT,
  )
end

def items_first_id(plan)
  plan.fetch("items").first.fetch("id")
end

FileUtils.mkdir_p(QUALITY_ROOT)
Dir.mktmpdir("portrait-core-quality-test-", QUALITY_ROOT) do |directory|
  plan, plan_path, rows, scores_path = build_fixture(directory)
  output_path = File.join(directory, "summary.json")

  stdout, stderr, status = run_checker(plan_path, scores_path, output_path)
  assert(status.success?, "passing six-capability round failed: #{stdout}\n#{stderr}")
  summary = JSON.parse(File.read(output_path))
  assert(summary["status"] == "passed", "passing summary was not passed")
  assert(summary.fetch("capabilities").keys.sort == CAPABILITIES.sort, "summary did not report all six capabilities")

  missing_blind_plan = Marshal.load(Marshal.dump(plan))
  missing_blind_plan.delete("blind_protocol")
  missing_blind_path = File.join(directory, "missing-blind-protocol.yaml")
  File.write(missing_blind_path, YAML.dump(missing_blind_plan))
  _stdout, stderr, status = run_checker(
    missing_blind_path,
    scores_path,
    File.join(directory, "missing-blind-protocol.json"),
  )
  assert(
    !status.success? && stderr.include?("blind_protocol"),
    "missing blind protocol did not fail closed: #{stderr}",
  )

  missing_plan = Marshal.load(Marshal.dump(plan))
  missing_plan["items"].reject! { |item| item["capability"] == "blemish_reduction" }
  missing_plan_path = File.join(directory, "missing-capability.yaml")
  File.write(missing_plan_path, YAML.dump(missing_plan))
  _stdout, stderr, status = run_checker(missing_plan_path, scores_path, File.join(directory, "missing.json"))
  assert(!status.success? && stderr.include?("missing capability blemish_reduction"), "missing capability did not fail closed: #{stderr}")

  missing_negative_plan = Marshal.load(Marshal.dump(plan))
  missing_negative_plan["items"].each do |item|
    item["tags"].delete("negative_safety") if item["capability"] == "torso_slimming"
  end
  missing_negative_path = File.join(directory, "missing-negative.yaml")
  File.write(missing_negative_path, YAML.dump(missing_negative_plan))
  _stdout, stderr, status = run_checker(missing_negative_path, scores_path, File.join(directory, "missing-negative.json"))
  assert(!status.success? && stderr.include?("capability torso_slimming has no negative_safety item"), "missing negative safety coverage did not fail closed: #{stderr}")

  low_preference = rows.map(&:dup)
  low_preference.each do |row|
    row["preferred_over_original"] = false if row["item_id"].start_with?("texture_smoothing-improvable")
  end
  low_preference_path = File.join(directory, "low-preference.csv")
  write_scores(low_preference_path, low_preference)
  _stdout, stderr, status = run_checker(plan_path, low_preference_path, File.join(directory, "low-preference.json"))
  assert(!status.success? && stderr.include?("texture_smoothing preference rate"), "low original preference was not capability-specific: #{stderr}")

  low_parity = rows.map(&:dup)
  low_parity.each do |row|
    row["comparison_to_xingtu"] = "xingtu_win" if row["item_id"].start_with?("skin_tone_lighting-")
  end
  low_parity_path = File.join(directory, "low-parity.csv")
  write_scores(low_parity_path, low_parity)
  _stdout, stderr, status = run_checker(plan_path, low_parity_path, File.join(directory, "low-parity.json"))
  assert(!status.success? && stderr.include?("skin_tone_lighting Xingtu win-or-tie rate"), "low competitor parity was not capability-specific: #{stderr}")

  catastrophic = rows.map(&:dup)
  catastrophic.first["catastrophic_error"] = true
  catastrophic_path = File.join(directory, "catastrophic.csv")
  write_scores(catastrophic_path, catastrophic)
  _stdout, stderr, status = run_checker(plan_path, catastrophic_path, File.join(directory, "catastrophic.json"))
  assert(!status.success? && stderr.include?("catastrophic errors"), "catastrophic error did not block the round: #{stderr}")

  incomplete = rows.reject { |row| row["reviewer_id"] == "reviewer-5" && row["item_id"] == items_first_id(plan) }
  incomplete_path = File.join(directory, "incomplete.csv")
  write_scores(incomplete_path, incomplete)
  _stdout, stderr, status = run_checker(plan_path, incomplete_path, File.join(directory, "incomplete.json"))
  assert(!status.success? && stderr.include?("is missing score"), "incomplete reviewer did not fail closed: #{stderr}")

  mismatched_plan = Marshal.load(Marshal.dump(plan))
  mismatched_plan["items"].first["competitor"]["source_sha256"] = "0" * 64
  mismatched_plan_path = File.join(directory, "mismatched-source.yaml")
  File.write(mismatched_plan_path, YAML.dump(mismatched_plan))
  _stdout, stderr, status = run_checker(mismatched_plan_path, scores_path, File.join(directory, "mismatched.json"))
  assert(!status.success? && stderr.include?("does not bind the same source"), "different competitor source did not fail closed: #{stderr}")
end

puts "Portrait core quality score checker tests passed"
