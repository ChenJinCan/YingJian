#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/usability_evidence_contract"

def fail_usability(message)
  warn "Usability evidence failed: #{message}"
  exit 1
end

def concrete_string?(value)
  value.is_a?(String) && !value.strip.empty? && value !~ /replace-with|replace_with|unknown|not[-_ ]recorded/i
end

begin
  manifest_argument = ARGV.shift
  source_index = ARGV.index("--source-commit")
  source_commit = source_index && ARGV[source_index + 1]
  ARGV.slice!(source_index, 2) if source_index
  fail_usability("usage: MANIFEST --source-commit SHA") unless manifest_argument && ARGV.empty?
  fail_usability("source commit must be a full Git SHA") unless source_commit&.match?(/\A[0-9a-f]{40}\z/)

  repo_root = Pathname.new(File.expand_path("..", __dir__))
  quality_root = repo_root.join(".quality").realpath
  path = Pathname.new(manifest_argument).expand_path
  unless path.file? && !path.symlink? && path.realpath.to_s.start_with?("#{quality_root}/")
    fail_usability("manifest must be a regular non-symlink file inside .quality")
  end
  path = path.realpath
  manifest = YAML.safe_load(path.read, permitted_classes: [], aliases: false)
  fail_usability("manifest must be a mapping") unless manifest.is_a?(Hash)

  errors = []
  errors << "schema must be #{UsabilityEvidenceContract::MANIFEST_SCHEMA}" unless
    manifest["schema"] == UsabilityEvidenceContract::MANIFEST_SCHEMA
  errors << "status must be passed" unless manifest["status"] == "passed"
  errors << "platform must be ios" unless manifest["platform"] == "ios"
  errors << "source_commit does not match" unless manifest["source_commit"] == source_commit
  eligibility_definition = manifest["eligibility_definition"]
  eligibility_source = repo_root.join("docs", "product", "product-context.md")
  unless eligibility_definition.is_a?(Hash) &&
      eligibility_definition["version"] == UsabilityEvidenceContract::TARGET_USER_DEFINITION_VERSION &&
      eligibility_definition["source_file"] == "docs/product/product-context.md" &&
      eligibility_definition["sha256"] == Digest::SHA256.file(eligibility_source).hexdigest
    errors << "target-user eligibility definition is invalid"
  end

  device_binding = manifest["device_run"]
  selected_run = nil
  if device_binding.is_a?(Hash) && concrete_string?(device_binding["file"]) &&
      device_binding["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
      concrete_string?(device_binding["run_id"])
    device_path = path.dirname.join(device_binding["file"]).expand_path
    if device_path.file? && !device_path.symlink? &&
        device_path.realpath.to_s.start_with?("#{quality_root}/")
      errors << "device matrix SHA-256 does not match" unless
        Digest::SHA256.file(device_path).hexdigest == device_binding["sha256"]
      device_output, device_error, device_status = Open3.capture3(
        RbConfig.ruby, repo_root.join("scripts", "check_device_evidence.rb").to_s,
        device_path.to_s, "--source-commit", source_commit
      )
      unless device_status.success?
        details = device_error.strip.empty? ? device_output.strip : device_error.strip
        errors << "device matrix has not passed the complete device contract: #{details}"
      end
      device_manifest = YAML.safe_load(device_path.read, permitted_classes: [], aliases: false)
      if device_manifest.is_a?(Hash) && device_manifest["schema"] == 1 &&
          device_manifest["status"] == "ready" && device_manifest["source_commit"] == source_commit &&
          device_manifest["runs"].is_a?(Array)
        selected_run = device_manifest["runs"].find { |run| run.is_a?(Hash) && run["run_id"] == device_binding["run_id"] }
      end
      errors << "device matrix does not contain the frozen ready iOS run" unless selected_run
    else
      errors << "device matrix must remain inside .quality"
    end
  else
    errors << "device_run binding is invalid"
  end
  device_binding = {} unless device_binding.is_a?(Hash)

  selected_device = selected_run.is_a?(Hash) ? selected_run["device"] : {}
  selected_build = selected_run.is_a?(Hash) ? selected_run["build"] : {}
  selected_outcomes = selected_run.is_a?(Hash) ? selected_run["outcomes"] : {}
  selected_device = {} unless selected_device.is_a?(Hash)
  selected_build = {} unless selected_build.is_a?(Hash)
  selected_outcomes = {} unless selected_outcomes.is_a?(Hash)
  selected_tier = selected_run.is_a?(Hash) ? selected_run["tier"] : nil
  unless selected_run.is_a?(Hash) && selected_run["platform"] == "ios" &&
      DeviceEvidenceContract::BUDGETS.key?(selected_tier) &&
      selected_device.is_a?(Hash) && selected_device["physical"] == true &&
      selected_device["device_id"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
      selected_device["model"].to_s.match?(/\AiPhone(?:\s|[0-9])/) &&
      !selected_device["model"].to_s.match?(/simulator/i) && concrete_string?(selected_device["os_version"])
    errors << "device run must identify a physical iPhone tier"
  end
  unless selected_build.is_a?(Hash) && %w[profile release].include?(selected_build["mode"]) &&
      selected_build["source_commit"] == source_commit &&
      selected_build["bundle_id"] == "com.babycompany.yingjian" &&
      concrete_string?(selected_build["version"]) && concrete_string?(selected_build["build_number"]) &&
      selected_build["artifact_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
    errors << "device run build identity is invalid"
  end
  unless selected_outcomes.is_a?(Hash) && selected_outcomes["source_hash_unchanged"] == true &&
      selected_outcomes["final_artifacts_valid"] == true && selected_outcomes["cloud_image_tasks_zero"] == true
    errors << "device run does not prove original-source export and zero cloud image tasks"
  end
  build_artifact = selected_run.is_a?(Hash) && selected_run["artifacts"].is_a?(Array) ?
    selected_run["artifacts"].find { |artifact| artifact.is_a?(Hash) && artifact["kind"] == "build_artifact" } : nil
  if build_artifact.is_a?(Hash) && build_artifact["file"].is_a?(String)
    artifact_path = repo_root.join(build_artifact["file"]).expand_path
    if artifact_path.file? && !artifact_path.symlink? &&
        artifact_path.realpath.to_s.start_with?("#{quality_root}/device-evidence/")
      artifact_hash = Digest::SHA256.file(artifact_path).hexdigest
      unless artifact_hash == build_artifact["sha256"] && artifact_hash == selected_build["artifact_sha256"]
        errors << "device run build artifact SHA-256 does not match the actual file"
      end
    else
      errors << "device run build artifact must remain inside .quality/device-evidence"
    end
  else
    errors << "device run build artifact is missing"
  end

  participants = manifest["participants"]
  participants = [] unless participants.is_a?(Array)
  errors << "at least 5 participants are required" if participants.length < 5
  participant_ids = {}
  session_ids = {}
  participants.each_with_index do |participant, index|
    unless participant.is_a?(Hash)
      errors << "participants[#{index}] must be a mapping"
      next
    end
    participant_id = participant["participant_id"]
    errors << "participants[#{index}].participant_id must be an opaque SHA-256" unless
      participant_id.is_a?(String) && participant_id.match?(/\A[0-9a-f]{64}\z/)
    errors << "duplicate participant_id" if participant_ids[participant_id]
    participant_ids[participant_id] = true
    errors << "participants[#{index}] must be uncoached" unless participant["uncoached"] == true
    errors << "participants[#{index}] must be a target user" unless participant["target_user"] == true
    errors << "participants[#{index}] must use a physical iPhone" unless participant["physical_iphone"] == true
    %w[completed_import_to_export understood_edit_scopes recommendations_saved_effort].each do |field|
      errors << "participants[#{index}].#{field} must be boolean" unless [true, false].include?(participant[field])
    end

    evidence = participant["evidence"]
    unless evidence.is_a?(Hash) && evidence["file"].is_a?(String) &&
        evidence["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
      errors << "participants[#{index}].evidence is invalid"
      next
    end
    evidence_path = path.dirname.join(evidence["file"]).expand_path
    unless evidence_path.file? && !evidence_path.symlink? &&
        evidence_path.realpath.to_s.start_with?("#{path.dirname.realpath}/")
      errors << "participants[#{index}].evidence must remain beside the manifest"
      next
    end
    errors << "participants[#{index}].evidence SHA-256 does not match" unless
      Digest::SHA256.file(evidence_path).hexdigest == evidence["sha256"]
    begin
      session = JSON.parse(evidence_path.read)
    rescue JSON::ParserError
      errors << "participants[#{index}].evidence must contain valid session JSON"
      next
    end
    unless session.is_a?(Hash) && session["schema"] == UsabilityEvidenceContract::SESSION_SCHEMA
      errors << "participants[#{index}].evidence must contain valid session JSON"
      next
    end

    session_id = session["session_id"]
    errors << "participants[#{index}] session_id must be an opaque SHA-256" unless
      session_id.is_a?(String) && session_id.match?(/\A[0-9a-f]{64}\z/)
    errors << "duplicate session_id" if session_ids[session_id]
    session_ids[session_id] = true
    errors << "participants[#{index}] session participant_id does not match" unless session["participant_id"] == participant_id
    errors << "participants[#{index}] session source_commit does not match" unless session["source_commit"] == source_commit
    errors << "participants[#{index}] session platform must be ios" unless session["platform"] == "ios"
    errors << "participants[#{index}] session device_run_id does not match" unless session["device_run_id"] == device_binding["run_id"]

    device = session["device"]
    unless device.is_a?(Hash) && device["physical"] == true &&
        device["model"] == selected_device["model"] && device["os_version"] == selected_device["os_version"]
      errors << "participants[#{index}] session does not match the frozen physical iPhone"
    end
    build = session["build"]
    unless build.is_a?(Hash) && UsabilityEvidenceContract::BUILD_IDENTITY_FIELDS.all? do |field|
      build[field] == selected_build[field]
    end
      errors << "participants[#{index}] session build identity is invalid"
    end
    protocol = session["protocol"]
    unless protocol.is_a?(Hash) && protocol["uncoached"] == true && UsabilityEvidenceContract.target_user?(session) &&
        protocol["observer_interventions"] == 0 && protocol["experience_variant"] == "production" &&
        protocol["photo_count"].is_a?(Integer) && protocol["photo_count"].between?(2, 6)
      errors << "participants[#{index}] session protocol is invalid"
    end
    metrics = session["metrics"]
    recommendation_ms = metrics.is_a?(Hash) ? metrics["recommendations_ready_ms"] : nil
    budget_ms = DeviceEvidenceContract::BUDGETS.dig(selected_tier, :recommendations)
    unless recommendation_ms.is_a?(Numeric) && recommendation_ms.finite? && recommendation_ms.positive? &&
        budget_ms && recommendation_ms <= budget_ms
      errors << "participants[#{index}] recommendations exceeded the frozen device-tier budget"
    end
    outcomes = session["outcomes"]
    unless outcomes.is_a?(Hash) && outcomes["cloud_image_tasks_created"] == 0 &&
        outcomes["export_origin"] == "app_owned_original"
      errors << "participants[#{index}] session does not prove local original-source export"
    end
    errors << "participants[#{index}] session task contract is incomplete" unless
      UsabilityEvidenceContract.task_contract_valid?(session)
    completed = UsabilityEvidenceContract.completed?(session)
    errors << "participants[#{index}] completion summary does not match session tasks" unless
      participant["completed_import_to_export"] == completed

    responses = session["responses"]
    if responses.is_a?(Hash)
      %w[group_scope current_photo_scope].each do |field|
        errors << "participants[#{index}] #{field} must be correct or incorrect" unless
          %w[correct incorrect].include?(responses[field])
      end
      unless [true, false].include?(responses["recommendations_saved_effort"])
        errors << "participants[#{index}] recommendations_saved_effort response must be boolean"
      end
      unless [true, false].include?(responses["recommendations_understood_as_local"])
        errors << "participants[#{index}] recommendations_understood_as_local response must be boolean"
      end
      understood = UsabilityEvidenceContract.scope_understood?(session)
      errors << "participants[#{index}] scope summary does not match both session responses" unless
        participant["understood_edit_scopes"] == understood
      errors << "participants[#{index}] recommendation summary does not match session response" unless
        participant["recommendations_saved_effort"] == responses["recommendations_saved_effort"]
      errors << "participants[#{index}] must understand recommendations as local processing" unless
        responses["recommendations_understood_as_local"] == true
    else
      errors << "participants[#{index}] session responses are invalid"
    end
  end

  count = [participants.length, 1].max.to_f
  errors << "task completion rate is below 80%" if
    participants.count { |participant| participant.is_a?(Hash) && participant["completed_import_to_export"] } / count < 0.8
  errors << "scope understanding rate is below 70%" if
    participants.count { |participant| participant.is_a?(Hash) && participant["understood_edit_scopes"] } / count < 0.7
  errors << "recommendation value rate is below 60%" if
    participants.count { |participant| participant.is_a?(Hash) && participant["recommendations_saved_effort"] } / count < 0.6
  fail_usability(errors.uniq.join("; ")) unless errors.empty?
  puts "Usability evidence passed for #{participants.length} participants on #{device_binding["run_id"]}."
rescue Psych::Exception => error
  fail_usability("invalid YAML: #{error.message}")
rescue SystemCallError => error
  fail_usability(error.message)
end
