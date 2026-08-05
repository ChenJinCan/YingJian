#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "open3"
require "pathname"
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
  output, error, status = Open3.capture3(*command)
  fail_acceptance("gate failed: #{error.strip.empty? ? output.strip : error.strip}") unless status.success?
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
  final_report = evidence["final_report"]
  fail_acceptance("final_report must be a mapping") unless final_report.is_a?(Hash)
  final_path = quality_file(root, final_report["file"], "final report")
  expected_sha = final_report["sha256"].to_s
  fail_acceptance("final report SHA-256 is invalid") unless expected_sha.match?(/\A[0-9a-f]{64}\z/)
  fail_acceptance("final report SHA-256 does not match") unless Digest::SHA256.file(final_path).hexdigest == expected_sha

  run_gate("ruby", root.join("scripts/check_image_quality_corpus.rb").to_s, image_manifest.to_s)
  run_gate("ruby", root.join("scripts/check_blind_review_scores.rb").to_s,
           review_key.to_s, review_scores.to_s, "--candidate", candidate)
  run_gate("ruby", root.join("scripts/check_usability_evidence.rb").to_s,
           usability.to_s, "--source-commit", source_commit)
  run_gate("ruby", root.join("scripts/check_device_evidence.rb").to_s,
           devices.to_s, "--source-commit", source_commit)
  puts "MVP acceptance valid for #{source_commit}."
rescue KeyError => error
  fail_acceptance(error.message)
rescue Psych::Exception => error
  fail_acceptance("invalid YAML: #{error.message}")
rescue ArgumentError
  fail_acceptance("decided_at must be ISO-8601")
end
