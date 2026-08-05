#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "time"
require "yaml"

def fail_acceptance(message)
  warn "MVP acceptance failed: #{message}"
  exit 1
end

def quality_file(root, value, label)
  relative = value.to_s
  fail_acceptance("#{label} must be beneath .quality") unless relative.start_with?(".quality/")
  path = root.join(relative)
  fail_acceptance("#{label} must be a regular non-symlink file") unless path.file? && !path.symlink?
  quality_root = root.join(".quality").realpath
  real = path.realpath
  fail_acceptance("#{label} escapes .quality") unless real.to_s.start_with?("#{quality_root}/")
  real
end

def run_gate(*command)
  output, error, status = Open3.capture3(
    {
      "YINGJIAN_DEVICE_EVIDENCE_TEST" => nil,
      "YINGJIAN_ALLOW_TEST_TOOLS" => nil,
      "YINGJIAN_TEST_TOOL_DIRECTORY" => nil,
    },
    *command
  )
  fail_acceptance("gate failed: #{error.strip.empty? ? output.strip : error.strip}") unless status.success?
end

def string_list(value, label)
  fail_acceptance("interaction decision #{label} must be a non-empty list") unless value.is_a?(Array) && !value.empty?
  normalized = value.map { |item| item.to_s.strip }
  fail_acceptance("interaction decision #{label} contains an invalid value") if normalized.any?(&:empty?) || normalized.uniq.length != normalized.length
  normalized
end

begin
  root = Pathname.new(ARGV.fetch(0, File.expand_path("..", __dir__))).expand_path
  source_commit = ARGV.fetch(1, ENV.fetch("RELEASE_SOURCE_COMMIT", "")).strip
  manifest_path = root.join(".quality", "mvp-acceptance.yaml")
  fail_acceptance("missing #{manifest_path}") unless manifest_path.file? && !manifest_path.symlink?
  manifest = YAML.safe_load(manifest_path.read, permitted_classes: [Time], aliases: false)
  fail_acceptance("manifest must be a mapping") unless manifest.is_a?(Hash)
  fail_acceptance("schema must be 1") unless manifest["schema"] == 1
  fail_acceptance("decision must be implemented_and_validated") unless manifest["decision"] == "implemented_and_validated"
  fail_acceptance("authorized_terminal_stage must be testflight") unless manifest["authorized_terminal_stage"] == "testflight"
  fail_acceptance("source commit must be a full Git SHA") unless source_commit.match?(/\A[0-9a-f]{40}\z/)
  fail_acceptance("source commit does not match the frozen release source") unless manifest["source_commit"] == source_commit
  decided_at = Time.iso8601(manifest["decided_at"].to_s)
  age = Time.now.utc - decided_at.utc
  fail_acceptance("decided_at is in the future") if age < -300
  fail_acceptance("acceptance decision is older than 7 days") if age > 7 * 24 * 60 * 60

  evidence = manifest["evidence"]
  fail_acceptance("evidence must be a mapping") unless evidence.is_a?(Hash)
  image_manifest = quality_file(root, evidence["image_corpus_manifest"], "image corpus manifest")
  portrait = evidence["portrait_review"]
  fail_acceptance("portrait_review must be a mapping") unless portrait.is_a?(Hash)
  review_key = quality_file(root, portrait["key_file"], "portrait review key")
  review_scores = quality_file(root, portrait["scores_file"], "portrait review scores")
  candidate = portrait["candidate_id"].to_s
  fail_acceptance("portrait candidate_id is required") if candidate.empty?
  usability = quality_file(root, evidence["usability_manifest"], "usability manifest")
  devices = quality_file(root, evidence["device_matrix_manifest"], "device matrix manifest")
  usability_record = YAML.safe_load(usability.read, permitted_classes: [], aliases: false)
  usability_binding = usability_record.is_a?(Hash) ? usability_record["device_run"] : nil
  fail_acceptance("usability manifest must bind the device matrix") unless usability_binding.is_a?(Hash)
  usability_device_file = usability_binding["file"]
  usability_device_sha = usability_binding["sha256"]
  fail_acceptance("usability device matrix binding is invalid") unless
    usability_device_file.is_a?(String) && !usability_device_file.empty? &&
    usability_device_sha.to_s.match?(/\A[0-9a-f]{64}\z/)
  usability_devices = usability.dirname.join(usability_device_file).expand_path
  fail_acceptance("usability and acceptance must use the same device matrix") unless
    usability_devices.file? && !usability_devices.symlink? &&
    usability_devices.realpath == devices && Digest::SHA256.file(devices).hexdigest == usability_device_sha
  final_report = evidence["final_report"]
  fail_acceptance("final_report must be a mapping") unless final_report.is_a?(Hash)
  final_path = quality_file(root, final_report["file"], "final report")
  expected_sha = final_report["sha256"].to_s
  fail_acceptance("final report SHA-256 is invalid") unless expected_sha.match?(/\A[0-9a-f]{64}\z/)
  fail_acceptance("final report SHA-256 does not match") unless Digest::SHA256.file(final_path).hexdigest == expected_sha
  final_record = YAML.safe_load(final_path.read, permitted_classes: [], aliases: false)
  fail_acceptance("final report must be a mapping") unless final_record.is_a?(Hash)
  fail_acceptance("final report schema must be 1") unless final_record["schema"] == 1
  fail_acceptance("final report source commit does not match") unless final_record["source_commit"] == source_commit
  fail_acceptance("final report decision must be implemented_and_validated") unless final_record["decision"] == "implemented_and_validated"

  interaction = final_record["interaction_decision"]
  fail_acceptance("interaction decision must be a mapping") unless interaction.is_a?(Hash)
  fail_acceptance("interaction decision status must be frozen") unless interaction["status"] == "frozen"
  fail_acceptance("interaction decision winning variant must be production") unless interaction["winning_variant"] == "production"
  retained = string_list(interaction["retained_structures"], "retained_structures")
  rejected = string_list(interaction["rejected_structures"], "rejected_structures")
  fail_acceptance("interaction decision retained and rejected structures overlap") unless (retained & rejected).empty?
  fail_acceptance("interaction decision spec_file must be docs/product/mvp-spec.md") unless interaction["spec_file"] == "docs/product/mvp-spec.md"
  spec_path = root.join(interaction["spec_file"])
  fail_acceptance("interaction decision spec file must be a regular non-symlink file") unless spec_path.file? && !spec_path.symlink?
  spec_sha = interaction["spec_sha256"].to_s
  fail_acceptance("interaction decision spec SHA-256 is invalid") unless spec_sha.match?(/\A[0-9a-f]{64}\z/)
  fail_acceptance("interaction decision spec SHA-256 does not match") unless Digest::SHA256.file(spec_path).hexdigest == spec_sha
  spec = spec_path.read
  spec_lines = spec.lines.map(&:strip)
  fail_acceptance("interaction decision is not frozen in the MVP spec") unless spec_lines.include?("MVP_INTERACTION_DECISION_STATUS: frozen")
  fail_acceptance("interaction decision winning variant is not frozen in the MVP spec") unless spec_lines.include?("MVP_INTERACTION_WINNING_VARIANT: production")
  retained_catalog_line = spec_lines.find { |line| line.start_with?("MVP_INTERACTION_RETAINABLE_STRUCTURES: ") }
  rejected_catalog_line = spec_lines.find { |line| line.start_with?("MVP_INTERACTION_REJECTABLE_STRUCTURES: ") }
  retained_catalog = retained_catalog_line.to_s.delete_prefix("MVP_INTERACTION_RETAINABLE_STRUCTURES: ").split(",").map(&:strip)
  rejected_catalog = rejected_catalog_line.to_s.delete_prefix("MVP_INTERACTION_REJECTABLE_STRUCTURES: ").split(",").map(&:strip)
  fail_acceptance("interaction decision retained structures are not frozen Spec IDs") unless
    !retained_catalog.empty? && (retained - retained_catalog).empty?
  fail_acceptance("interaction decision rejected structures are not frozen Spec IDs") unless
    !rejected_catalog.empty? && (rejected - rejected_catalog).empty?

  final_usability = quality_file(root, interaction["usability_manifest"], "interaction decision usability manifest")
  fail_acceptance("interaction decision must bind the accepted usability manifest") unless final_usability == usability
  final_usability_sha = interaction["usability_sha256"].to_s
  fail_acceptance("interaction decision usability SHA-256 is invalid") unless final_usability_sha.match?(/\A[0-9a-f]{64}\z/)
  fail_acceptance("interaction decision usability SHA-256 does not match") unless
    Digest::SHA256.file(usability).hexdigest == final_usability_sha
  fail_acceptance("interaction decision device run does not match usability evidence") unless
    interaction["device_run_id"] == usability_binding["run_id"]
  bound_session_ids = string_list(interaction["session_ids"], "session_ids")
  fail_acceptance("interaction decision session IDs must contain at least five opaque IDs") unless
    bound_session_ids.length >= 5 && bound_session_ids.all? { |id| id.match?(/\A[0-9a-f]{64}\z/) }
  participant_records = usability_record["participants"]
  fail_acceptance("interaction decision cannot read usability participants") unless participant_records.is_a?(Array)
  actual_session_ids = participant_records.map.with_index do |participant, index|
    evidence_record = participant.is_a?(Hash) ? participant["evidence"] : nil
    fail_acceptance("interaction decision participant #{index} evidence is invalid") unless evidence_record.is_a?(Hash)
    session_path = usability.dirname.join(evidence_record["file"].to_s).expand_path
    fail_acceptance("interaction decision participant #{index} session is missing") unless
      session_path.file? && !session_path.symlink? && session_path.realpath.to_s.start_with?("#{usability.dirname.realpath}/")
    fail_acceptance("interaction decision participant #{index} session SHA-256 does not match") unless
      Digest::SHA256.file(session_path).hexdigest == evidence_record["sha256"]
    session_record = JSON.parse(session_path.read)
    session_record["session_id"]
  end
  fail_acceptance("interaction decision session IDs do not match the accepted usability sessions") unless
    actual_session_ids.length == actual_session_ids.uniq.length && actual_session_ids.sort == bound_session_ids.sort

  run_gate(RbConfig.ruby, root.join("scripts/check_image_quality_corpus.rb").to_s, image_manifest.to_s)
  run_gate(RbConfig.ruby, root.join("scripts/check_blind_review_scores.rb").to_s,
           review_key.to_s, review_scores.to_s, "--candidate", candidate)
  run_gate(RbConfig.ruby, root.join("scripts/check_usability_evidence.rb").to_s,
           usability.to_s, "--source-commit", source_commit)
  run_gate(RbConfig.ruby, root.join("scripts/check_device_evidence.rb").to_s,
           devices.to_s, "--source-commit", source_commit)
  puts "MVP acceptance valid for #{source_commit}."
rescue KeyError => error
  fail_acceptance(error.message)
rescue Psych::Exception => error
  fail_acceptance("invalid YAML: #{error.message}")
rescue JSON::ParserError => error
  fail_acceptance("interaction decision session JSON is invalid: #{error.message}")
rescue ArgumentError
  fail_acceptance("decided_at must be ISO-8601")
end
