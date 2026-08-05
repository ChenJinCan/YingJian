#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

checker = File.expand_path("check_usability_evidence.rb", __dir__)
sha = "a" * 40
Dir.mktmpdir("usability-evidence-") do |root|
  participants = 5.times.map do |index|
    file = File.join(root, "session-#{index}.json")
    File.write(file, "session #{index}\n")
    {
      "participant_id" => Digest::SHA256.hexdigest("participant #{index}"),
      "uncoached" => true, "physical_iphone" => true,
      "completed_import_to_export" => index < 4,
      "understood_group_scope" => index < 4,
      "recommendations_saved_effort" => index < 3,
      "evidence" => { "file" => File.basename(file), "sha256" => Digest::SHA256.file(file).hexdigest }
    }
  end
  manifest = { "schema" => 1, "status" => "passed", "platform" => "ios", "source_commit" => sha, "participants" => participants }
  path = File.join(root, "manifest.yaml")
  File.write(path, manifest.to_yaml)
  _out, err, status = Open3.capture3("ruby", checker, path, "--source-commit", sha)
  raise "valid usability evidence rejected: #{err}" unless status.success?
  manifest["participants"][2]["recommendations_saved_effort"] = false
  File.write(path, manifest.to_yaml)
  _out, err, status = Open3.capture3("ruby", checker, path, "--source-commit", sha)
  raise "low recommendation rate accepted" if status.success? || !err.include?("below 60%")
end
puts "Usability evidence tests passed."
