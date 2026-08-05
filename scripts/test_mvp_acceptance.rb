#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "time"
require "yaml"

checker = File.expand_path("check_mvp_acceptance.rb", __dir__)
sha = "0123456789abcdef0123456789abcdef01234567"

Dir.mktmpdir("mvp-acceptance-") do |root|
  quality = File.join(root, ".quality")
  scripts = File.join(root, "scripts")
  product_docs = File.join(root, "docs", "product")
  FileUtils.mkdir_p([quality, scripts, product_docs])
  %w[check_image_quality_corpus.rb check_blind_review_scores.rb check_usability_evidence.rb check_device_evidence.rb].each do |name|
    File.write(File.join(scripts, name), "exit ENV['REJECT_GATE'] == '1' ? 1 : 0\n")
  end
  paths = %w[corpus.yaml key.json scores.csv usability.yaml devices.yaml]
  paths.each { |name| File.write(File.join(quality, name), "verified #{name}\n") }
  spec_path = File.join(product_docs, "mvp-spec.md")
  File.write(
    spec_path,
    "MVP_INTERACTION_DECISION_STATUS: frozen\n" \
      "MVP_INTERACTION_WINNING_VARIANT: production\n" \
      "MVP_INTERACTION_RETAINABLE_STRUCTURES: result_first_recommendations,explicit_edit_scope\n" \
      "MVP_INTERACTION_REJECTABLE_STRUCTURES: web_tool_dashboard,poster_style_mobile\n"
  )
  session_ids = 5.times.map { |index| Digest::SHA256.hexdigest("session-#{index}") }
  final_report_path = File.join(quality, "final.yaml")
  final_report = {
    "schema" => 1,
    "source_commit" => sha,
    "decision" => "implemented_and_validated",
    "interaction_decision" => {
      "status" => "frozen",
      "winning_variant" => "production",
      "retained_structures" => %w[result_first_recommendations explicit_edit_scope],
      "rejected_structures" => %w[web_tool_dashboard poster_style_mobile],
      "spec_file" => "docs/product/mvp-spec.md",
      "spec_sha256" => Digest::SHA256.file(spec_path).hexdigest,
      "usability_manifest" => ".quality/usability.yaml",
      "usability_sha256" => nil,
      "device_run_id" => "ios-mid-001",
      "session_ids" => session_ids,
    },
  }
  File.write(final_report_path, final_report.to_yaml)
  device_path = File.join(quality, "devices.yaml")
  usability_path = File.join(quality, "usability.yaml")
  usability = {
    "schema" => 2,
    "device_run" => {
      "file" => "devices.yaml",
      "sha256" => Digest::SHA256.file(device_path).hexdigest,
      "run_id" => "ios-mid-001",
    },
    "participants" => session_ids.map.with_index do |session_id, index|
      session_file = File.join(quality, "session-#{index}.json")
      File.write(session_file, JSON.generate("session_id" => session_id))
      {
        "evidence" => {
          "file" => File.basename(session_file),
          "sha256" => Digest::SHA256.file(session_file).hexdigest,
        },
      }
    end,
  }
  File.write(usability_path, usability.to_yaml)
  final_report["interaction_decision"]["usability_sha256"] = Digest::SHA256.file(usability_path).hexdigest
  File.write(final_report_path, final_report.to_yaml)
  manifest = {
    "schema" => 1, "decision" => "implemented_and_validated",
    "authorized_terminal_stage" => "testflight", "source_commit" => sha,
    "decided_at" => Time.now.utc.iso8601,
    "evidence" => {
      "image_corpus_manifest" => ".quality/corpus.yaml",
      "portrait_review" => {
        "key_file" => ".quality/key.json", "scores_file" => ".quality/scores.csv",
        "candidate_id" => "yingjian-default"
      },
      "usability_manifest" => ".quality/usability.yaml",
      "device_matrix_manifest" => ".quality/devices.yaml",
      "final_report" => {
        "file" => ".quality/final.yaml",
        "sha256" => Digest::SHA256.file(final_report_path).hexdigest
      }
    }
  }
  manifest_path = File.join(quality, "mvp-acceptance.yaml")
  File.write(manifest_path, manifest.to_yaml)
  _out, err, status = Open3.capture3("ruby", checker, root, sha)
  raise "valid acceptance rejected: #{err}" unless status.success?

  _out, err, status = Open3.capture3({ "REJECT_GATE" => "1" }, "ruby", checker, root, sha)
  raise "failed underlying gate accepted" if status.success? || !err.include?("gate failed")

  fake_bin = File.join(root, "fake-bin")
  FileUtils.mkdir_p(fake_bin)
  File.write(File.join(fake_bin, "ruby"), "#!/bin/sh\nexit 0\n")
  FileUtils.chmod(0o755, File.join(fake_bin, "ruby"))
  hostile_path = "#{fake_bin}:#{ENV.fetch('PATH')}"
  _out, err, status = Open3.capture3(
    { "REJECT_GATE" => "1", "PATH" => hostile_path },
    RbConfig.ruby, checker, root, sha
  )
  raise "PATH ruby bypassed an underlying acceptance gate" if status.success? || !err.include?("gate failed")

  other_devices = File.join(quality, "other-devices.yaml")
  File.write(other_devices, "different device matrix\n")
  usability["device_run"]["file"] = "other-devices.yaml"
  usability["device_run"]["sha256"] = Digest::SHA256.file(other_devices).hexdigest
  File.write(usability_path, usability.to_yaml)
  _out, err, status = Open3.capture3("ruby", checker, root, sha)
  raise "usability evidence used a different device matrix" if status.success? || !err.include?("same device matrix")
  usability["device_run"]["file"] = "devices.yaml"
  usability["device_run"]["sha256"] = Digest::SHA256.file(device_path).hexdigest
  File.write(usability_path, usability.to_yaml)
  final_report["interaction_decision"]["usability_sha256"] = Digest::SHA256.file(usability_path).hexdigest
  File.write(final_report_path, final_report.to_yaml)
  manifest["evidence"]["final_report"]["sha256"] = Digest::SHA256.file(final_report_path).hexdigest
  File.write(manifest_path, manifest.to_yaml)

  wrong_sessions = Marshal.load(Marshal.dump(final_report))
  wrong_sessions["interaction_decision"]["session_ids"] =
    5.times.map { |index| Digest::SHA256.hexdigest("unrelated-session-#{index}") }
  File.write(final_report_path, wrong_sessions.to_yaml)
  manifest["evidence"]["final_report"]["sha256"] = Digest::SHA256.file(final_report_path).hexdigest
  File.write(manifest_path, manifest.to_yaml)
  _out, err, status = Open3.capture3("ruby", checker, root, sha)
  raise "acceptance passed with unrelated session IDs" if status.success? || !err.include?("session IDs")
  File.write(final_report_path, final_report.to_yaml)
  manifest["evidence"]["final_report"]["sha256"] = Digest::SHA256.file(final_report_path).hexdigest
  File.write(manifest_path, manifest.to_yaml)

  incomplete_report = Marshal.load(Marshal.dump(final_report))
  incomplete_report.delete("interaction_decision")
  File.write(final_report_path, incomplete_report.to_yaml)
  manifest["evidence"]["final_report"]["sha256"] = Digest::SHA256.file(final_report_path).hexdigest
  File.write(manifest_path, manifest.to_yaml)
  _out, err, status = Open3.capture3("ruby", checker, root, sha)
  raise "acceptance passed without the interaction decision" if status.success? || !err.include?("interaction decision")
  File.write(final_report_path, final_report.to_yaml)
  manifest["evidence"]["final_report"]["sha256"] = Digest::SHA256.file(final_report_path).hexdigest
  File.write(manifest_path, manifest.to_yaml)

  manifest["decision"] = "implemented_only"
  File.write(manifest_path, manifest.to_yaml)
  _out, err, status = Open3.capture3("ruby", checker, root, sha)
  raise "unvalidated decision accepted" if status.success? || !err.include?("implemented_and_validated")
end

puts "MVP acceptance tests passed."
