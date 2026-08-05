#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "pathname"
require "yaml"

def fail_usability(message)
  warn "Usability evidence failed: #{message}"
  exit 1
end

begin
manifest_argument = ARGV.shift
source_index = ARGV.index("--source-commit")
source_commit = source_index && ARGV[source_index + 1]
ARGV.slice!(source_index, 2) if source_index
fail_usability("usage: MANIFEST --source-commit SHA") unless manifest_argument && ARGV.empty?
fail_usability("source commit must be a full Git SHA") unless source_commit&.match?(/\A[0-9a-f]{40}\z/)
path = Pathname.new(manifest_argument).expand_path
fail_usability("manifest must be a regular non-symlink file") unless path.file? && !path.symlink?
manifest = YAML.safe_load(path.read, permitted_classes: [], aliases: false)
fail_usability("manifest must be a mapping") unless manifest.is_a?(Hash)
errors = []
errors << "schema must be 1" unless manifest["schema"] == 1
errors << "status must be passed" unless manifest["status"] == "passed"
errors << "platform must be ios" unless manifest["platform"] == "ios"
errors << "source_commit does not match" unless manifest["source_commit"] == source_commit
participants = manifest["participants"]
participants = [] unless participants.is_a?(Array)
errors << "at least 5 participants are required" if participants.length < 5
ids = {}
participants.each_with_index do |participant, index|
  unless participant.is_a?(Hash)
    errors << "participants[#{index}] must be a mapping"
    next
  end
  id = participant["participant_id"]
  errors << "participants[#{index}].participant_id must be an opaque SHA-256" unless id.is_a?(String) && id.match?(/\A[0-9a-f]{64}\z/)
  errors << "duplicate participant_id" if ids[id]
  ids[id] = true
  errors << "participants[#{index}] must be uncoached" unless participant["uncoached"] == true
  errors << "participants[#{index}] must use a physical iPhone" unless participant["physical_iphone"] == true
  %w[completed_import_to_export understood_group_scope recommendations_saved_effort].each do |field|
    errors << "participants[#{index}].#{field} must be boolean" unless [true, false].include?(participant[field])
  end
  evidence = participant["evidence"]
  unless evidence.is_a?(Hash) && evidence["file"].is_a?(String) && evidence["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
    errors << "participants[#{index}].evidence is invalid"
    next
  end
  evidence_path = path.dirname.join(evidence["file"]).expand_path
  expected_root = path.dirname.realpath
  unless evidence_path.file? && !evidence_path.symlink? && evidence_path.realpath.to_s.start_with?("#{expected_root}/")
    errors << "participants[#{index}].evidence must remain beside the manifest"
    next
  end
  errors << "participants[#{index}].evidence SHA-256 does not match" unless Digest::SHA256.file(evidence_path).hexdigest == evidence["sha256"]
end
count = [participants.length, 1].max.to_f
errors << "task completion rate is below 80%" if participants.count { |p| p.is_a?(Hash) && p["completed_import_to_export"] } / count < 0.8
errors << "scope understanding rate is below 70%" if participants.count { |p| p.is_a?(Hash) && p["understood_group_scope"] } / count < 0.7
errors << "recommendation value rate is below 60%" if participants.count { |p| p.is_a?(Hash) && p["recommendations_saved_effort"] } / count < 0.6
fail_usability(errors.uniq.join("; ")) unless errors.empty?
puts "Usability evidence passed for #{participants.length} participants."
rescue Psych::Exception => error
  fail_usability("invalid YAML: #{error.message}")
end
