#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "support/usability_evidence_contract"
require_relative "test_support/device_evidence_fixture"

repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
usability_root = File.join(quality_root, "usability")
device_root = File.join(quality_root, "device-evidence")
FileUtils.mkdir_p([usability_root, device_root])
builder = File.join(repo_root, "scripts/build_usability_evidence.rb")
checker = File.join(repo_root, "scripts/check_usability_evidence.rb")
source_commit = "0123456789abcdef0123456789abcdef01234567"

Dir.mktmpdir("builder-test-", usability_root) do |directory|
  Dir.mktmpdir("usability-device-test-", device_root) do |device_directory|
    fixture = DeviceEvidenceFixture.build(
      repo_root: repo_root,
      directory: device_directory,
      source_commit: source_commit
    )
    device_manifest_path = fixture.fetch(:manifest_path)
    selected_run = fixture.fetch(:selected_run)
    build = selected_run.fetch("build")
    selected_device = selected_run.fetch("device")

    sessions = File.join(directory, "sessions")
    FileUtils.mkdir_p(sessions)
    5.times do |index|
      session = {
        "schema" => UsabilityEvidenceContract::SESSION_SCHEMA,
        "session_id" => Digest::SHA256.hexdigest("session #{index}"),
        "participant_id" => Digest::SHA256.hexdigest("participant #{index}"),
        "source_commit" => source_commit,
        "platform" => "ios",
        "device_run_id" => selected_run.fetch("run_id"),
        "device" => {
          "physical" => true,
          "model" => selected_device.fetch("model"),
          "os_version" => selected_device.fetch("os_version"),
        },
        "build" => build,
        "protocol" => {
          "uncoached" => true,
          "eligibility_attested_by_observer" => true,
          "target_user_eligibility" => UsabilityEvidenceContract::TARGET_USER_REQUIRED_CRITERIA.to_h do |criterion|
            [criterion, true]
          end,
          "observer_interventions" => 0,
          "experience_variant" => "production",
          "photo_count" => 6,
        },
        "metrics" => { "recommendations_ready_ms" => 7_500 },
        "tasks" => UsabilityEvidenceContract::REQUIRED_TASKS.map do |id|
          { "id" => id, "completed" => true }
        end,
        "outcomes" => {
          "cloud_image_tasks_created" => 0,
          "export_origin" => "app_owned_original",
        },
        "responses" => {
          "group_scope" => "correct",
          "current_photo_scope" => "correct",
          "recommendations_saved_effort" => index < 3,
          "recommendations_understood_as_local" => true,
        },
      }
      File.write(
        File.join(sessions, format("session-%02d.json", index + 1)),
        JSON.pretty_generate(session)
      )
    end

    output = File.join(directory, "ios-mvp.yaml")
    stdout, stderr, status = Open3.capture3(
      "ruby", builder, sessions, output,
      "--source-commit", source_commit,
      "--device-matrix", device_manifest_path,
      "--device-run", selected_run.fetch("run_id")
    )
    raise "valid usability sessions were not built: #{stdout}#{stderr}" unless status.success?
    manifest = YAML.safe_load(File.read(output), permitted_classes: [], aliases: false)
    raise "builder did not derive schema 2" unless manifest["schema"] == 2
    raise "builder did not derive five participants" unless manifest.fetch("participants").length == 5
    _stdout, checker_error, checker_status = Open3.capture3(
      "ruby", checker, output, "--source-commit", source_commit
    )
    raise "built manifest failed its public checker: #{checker_error}" unless checker_status.success?

    rejected_output = File.join(directory, "rejected.yaml")
    first_session = File.join(sessions, "session-01.json")
    invalid = JSON.parse(File.read(first_session))
    invalid["responses"]["recommendations_understood_as_local"] = false
    File.write(first_session, JSON.pretty_generate(invalid))
    _stdout, rejected_error, rejected_status = Open3.capture3(
      "ruby", builder, sessions, rejected_output,
      "--source-commit", source_commit,
      "--device-matrix", device_manifest_path,
      "--device-run", selected_run.fetch("run_id")
    )
    raise "cloud-misunderstood session was accepted" if rejected_status.success?
    raise "failed build left an acceptance manifest" if File.exist?(rejected_output)
    raise "builder hid the failed usability gate" unless rejected_error.include?("local processing")
  end
end

puts "Usability evidence builder tests passed."
