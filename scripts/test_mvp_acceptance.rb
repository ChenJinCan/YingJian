#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "tmpdir"
require "time"
require "yaml"

checker = File.expand_path("check_mvp_acceptance.rb", __dir__)
sha = "0123456789abcdef0123456789abcdef01234567"

Dir.mktmpdir("mvp-acceptance-") do |root|
  quality = File.join(root, ".quality")
  scripts = File.join(root, "scripts")
  FileUtils.mkdir_p([quality, scripts])
  %w[check_image_quality_corpus.rb check_blind_review_scores.rb check_usability_evidence.rb check_device_evidence.rb].each do |name|
    File.write(File.join(scripts, name), "exit ENV['REJECT_GATE'] == '1' ? 1 : 0\n")
  end
  paths = %w[corpus.yaml key.json scores.csv usability.yaml devices.yaml final.md]
  paths.each { |name| File.write(File.join(quality, name), "verified #{name}\n") }
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
        "file" => ".quality/final.md",
        "sha256" => Digest::SHA256.file(File.join(quality, "final.md")).hexdigest
      }
    }
  }
  manifest_path = File.join(quality, "mvp-acceptance.yaml")
  File.write(manifest_path, manifest.to_yaml)
  _out, err, status = Open3.capture3("ruby", checker, root, sha)
  raise "valid acceptance rejected: #{err}" unless status.success?

  _out, err, status = Open3.capture3({ "REJECT_GATE" => "1" }, "ruby", checker, root, sha)
  raise "failed underlying gate accepted" if status.success? || !err.include?("gate failed")

  manifest["decision"] = "implemented_only"
  File.write(manifest_path, manifest.to_yaml)
  _out, err, status = Open3.capture3("ruby", checker, root, sha)
  raise "unvalidated decision accepted" if status.success? || !err.include?("implemented_and_validated")
end

puts "MVP acceptance tests passed."
