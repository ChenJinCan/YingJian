#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "tempfile"
require "yaml"
require_relative "support/usability_evidence_contract"

def fail_build(message)
  warn "Usability evidence build failed: #{message}"
  exit 1
end

session_argument = ARGV.shift
output_argument = ARGV.shift
source_index = ARGV.index("--source-commit")
source_commit = source_index && ARGV[source_index + 1]
ARGV.slice!(source_index, 2) if source_index
device_index = ARGV.index("--device-matrix")
device_argument = device_index && ARGV[device_index + 1]
ARGV.slice!(device_index, 2) if device_index
run_index = ARGV.index("--device-run")
device_run = run_index && ARGV[run_index + 1]
ARGV.slice!(run_index, 2) if run_index
unless session_argument && output_argument && ARGV.empty?
  fail_build("usage: SESSION_DIRECTORY OUTPUT --source-commit SHA --device-matrix FILE --device-run ID")
end
unless source_commit&.match?(/\A[0-9a-f]{40}\z/)
  fail_build("source commit must be a full Git SHA")
end

repo_root = Pathname.new(File.expand_path("..", __dir__))
quality_root = repo_root.join(".quality")
quality_root.mkpath
quality_root_real = quality_root.realpath
sessions = Pathname.new(session_argument).expand_path
output = Pathname.new(output_argument).expand_path
fail_build("session directory must be a regular directory") unless sessions.directory? && !sessions.symlink?
sessions_real = sessions.realpath
unless sessions_real.to_s.start_with?("#{quality_root_real}/")
  fail_build("session directory must remain inside the ignored .quality directory")
end
fail_build("output already exists") if output.exist?
output_parent = output.dirname
fail_build("output parent must be a regular directory") unless output_parent.directory? && !output_parent.symlink?
output_parent_real = output_parent.realpath
unless output_parent_real == quality_root_real || output_parent_real.to_s.start_with?("#{quality_root_real}/")
  fail_build("output must remain inside the ignored .quality directory")
end
unless sessions_real == output_parent_real || sessions_real.to_s.start_with?("#{output_parent_real}/")
  fail_build("session directory must remain beside the output manifest")
end
fail_build("device matrix and device run are required") unless device_argument && device_run
device_matrix = Pathname.new(device_argument).expand_path
unless device_matrix.file? && !device_matrix.symlink? &&
    device_matrix.realpath.to_s.start_with?("#{quality_root_real}/")
  fail_build("device matrix must remain inside the ignored .quality directory")
end
device_matrix = device_matrix.realpath

session_paths = sessions_real.children.select { |path| path.extname == ".json" }.sort
fail_build("at least 5 session JSON files are required") if session_paths.length < 5

participants = session_paths.map.with_index do |path, index|
  unless path.file? && !path.symlink? && path.realpath.dirname == sessions_real
    fail_build("session #{index + 1} must be a regular non-symlink JSON file")
  end
  begin
    session = JSON.parse(path.read)
  rescue JSON::ParserError => error
    fail_build("#{path.basename} is invalid JSON: #{error.message}")
  end
  fail_build("#{path.basename} must contain a session mapping") unless session.is_a?(Hash)
  responses = session["responses"].is_a?(Hash) ? session["responses"] : {}
  protocol = session["protocol"].is_a?(Hash) ? session["protocol"] : {}
  device = session["device"].is_a?(Hash) ? session["device"] : {}
  {
    "participant_id" => session["participant_id"],
    "uncoached" => protocol["uncoached"],
    "target_user" => UsabilityEvidenceContract.target_user?(session),
    "physical_iphone" => device["physical"],
    "completed_import_to_export" => UsabilityEvidenceContract.completed?(session),
    "understood_edit_scopes" => UsabilityEvidenceContract.scope_understood?(session),
    "recommendations_saved_effort" => responses["recommendations_saved_effort"],
    "evidence" => {
      "file" => path.realpath.relative_path_from(output_parent_real).to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  }
end

manifest = {
  "schema" => UsabilityEvidenceContract::MANIFEST_SCHEMA,
  "status" => "passed",
  "platform" => "ios",
  "source_commit" => source_commit,
  "eligibility_definition" => {
    "version" => UsabilityEvidenceContract::TARGET_USER_DEFINITION_VERSION,
    "source_file" => "docs/product/product-context.md",
    "sha256" => Digest::SHA256.file(repo_root.join("docs", "product", "product-context.md")).hexdigest,
  },
  "device_run" => {
    "file" => device_matrix.relative_path_from(output_parent_real).to_s,
    "sha256" => Digest::SHA256.file(device_matrix).hexdigest,
    "run_id" => device_run,
  },
  "participants" => participants
}
checker = repo_root.join("scripts", "check_usability_evidence.rb").to_s
temporary = Tempfile.new([".usability-evidence-", ".yaml"], output_parent_real.to_s)
begin
  temporary.chmod(0o600)
  temporary.write(manifest.to_yaml)
  temporary.flush
  temporary.fsync
  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby, checker, temporary.path, "--source-commit", source_commit
  )
  fail_build((stderr.empty? ? stdout : stderr).strip) unless status.success?
  temporary.close
  File.rename(temporary.path, output.to_s)
rescue SystemCallError => error
  fail_build(error.message)
ensure
  temporary.close! if temporary
end

puts "Usability evidence manifest built for #{participants.length} participants."
