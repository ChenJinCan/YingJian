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
checker = File.join(repo_root, "scripts/check_usability_evidence.rb")
source_commit = "a" * 40

Dir.mktmpdir("checker-test-", usability_root) do |root|
  Dir.mktmpdir("usability-device-test-", device_root) do |device_directory|
    fixture = DeviceEvidenceFixture.build(
      repo_root: repo_root,
      directory: device_directory,
      source_commit: source_commit
    )
    device_manifest = fixture.fetch(:manifest)
    device_manifest_path = fixture.fetch(:manifest_path)
    selected_run = fixture.fetch(:selected_run)
    build = selected_run.fetch("build")
    selected_device = selected_run.fetch("device")

    participants = 5.times.map do |index|
      file = File.join(root, "session-#{index}.json")
      completed = index < 4
      understood = index < 4
      saved_effort = index < 3
      participant_id = Digest::SHA256.hexdigest("participant #{index}")
      session = {
        "schema" => UsabilityEvidenceContract::SESSION_SCHEMA,
        "session_id" => Digest::SHA256.hexdigest("session #{index}"),
        "participant_id" => participant_id,
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
          { "id" => id, "completed" => completed }
        end,
        "outcomes" => {
          "cloud_image_tasks_created" => 0,
          "export_origin" => "app_owned_original",
        },
        "responses" => {
          "group_scope" => understood ? "correct" : "incorrect",
          "current_photo_scope" => understood ? "correct" : "incorrect",
          "recommendations_saved_effort" => saved_effort,
          "recommendations_understood_as_local" => true,
        },
      }
      File.write(file, JSON.pretty_generate(session))
      {
        "participant_id" => participant_id,
        "uncoached" => true,
        "target_user" => true,
        "physical_iphone" => true,
        "completed_import_to_export" => completed,
        "understood_edit_scopes" => understood,
        "recommendations_saved_effort" => saved_effort,
        "evidence" => {
          "file" => File.basename(file),
          "sha256" => Digest::SHA256.file(file).hexdigest,
        },
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
        "sha256" => Digest::SHA256.file(File.join(repo_root, "docs/product/product-context.md")).hexdigest,
      },
      "device_run" => {
        "file" => Pathname.new(device_manifest_path).relative_path_from(Pathname.new(root)).to_s,
        "sha256" => Digest::SHA256.file(device_manifest_path).hexdigest,
        "run_id" => selected_run.fetch("run_id"),
      },
      "participants" => participants,
    }
    manifest_path = File.join(root, "manifest.yaml")
    File.write(manifest_path, manifest.to_yaml)
    _stdout, stderr, status = Open3.capture3(
      "ruby", checker, manifest_path, "--source-commit", source_commit
    )
    raise "valid usability evidence rejected: #{stderr}" unless status.success?

    frozen_device_run = manifest["device_run"]
    manifest["device_run"] = nil
    File.write(manifest_path, manifest.to_yaml)
    _stdout, stderr, status = Open3.capture3(
      "ruby", checker, manifest_path, "--source-commit", source_commit
    )
    raise "invalid device binding did not fail closed" if status.success? || !stderr.include?("device_run binding is invalid")
    manifest["device_run"] = frozen_device_run

    session_path = File.join(root, participants[4]["evidence"]["file"])
    session = JSON.parse(File.read(session_path))
    session["responses"]["current_photo_scope"] = "unknown"
    File.write(session_path, JSON.pretty_generate(session))
    participants[4]["evidence"]["sha256"] = Digest::SHA256.file(session_path).hexdigest
    File.write(manifest_path, manifest.to_yaml)
    _stdout, stderr, status = Open3.capture3(
      "ruby", checker, manifest_path, "--source-commit", source_commit
    )
    unless !status.success? && stderr.include?("current_photo_scope must be correct or incorrect")
      raise "unknown current-photo scope response accepted"
    end

    session["responses"]["current_photo_scope"] = "incorrect"
    session["protocol"]["target_user_eligibility"]["publishes_multiple_photos"] = false
    File.write(session_path, JSON.pretty_generate(session))
    participants[4]["target_user"] = false
    participants[4]["evidence"]["sha256"] = Digest::SHA256.file(session_path).hexdigest
    File.write(manifest_path, manifest.to_yaml)
    _stdout, stderr, status = Open3.capture3(
      "ruby", checker, manifest_path, "--source-commit", source_commit
    )
    raise "non-target participant accepted" if status.success? || !stderr.include?("must be a target user")

    session["protocol"]["target_user_eligibility"]["publishes_multiple_photos"] = true
    participants[4]["target_user"] = true
    session["build"] = build.merge("artifact_sha256" => "c" * 64)
    File.write(session_path, JSON.pretty_generate(session))
    participants[4]["evidence"]["sha256"] = Digest::SHA256.file(session_path).hexdigest
    File.write(manifest_path, manifest.to_yaml)
    _stdout, stderr, status = Open3.capture3(
      "ruby", checker, manifest_path, "--source-commit", source_commit
    )
    raise "mixed usability build artifact accepted" if status.success? || !stderr.include?("build identity is invalid")

    session["build"] = build
    File.write(session_path, "arbitrary observer claim\n")
    participants[4]["evidence"]["sha256"] = Digest::SHA256.file(session_path).hexdigest
    File.write(manifest_path, manifest.to_yaml)
    _stdout, stderr, status = Open3.capture3(
      "ruby", checker, manifest_path, "--source-commit", source_commit
    )
    raise "unstructured usability evidence accepted" if status.success? || !stderr.include?("valid session JSON")

    device_manifest["runs"][0]["device"]["model"] = "Pixel 9"
    File.write(device_manifest_path, device_manifest.to_yaml)
    manifest["device_run"]["sha256"] = Digest::SHA256.file(device_manifest_path).hexdigest
    File.write(manifest_path, manifest.to_yaml)
    _stdout, stderr, status = Open3.capture3(
      "ruby", checker, manifest_path, "--source-commit", source_commit
    )
    raise "non-iPhone device run accepted" if status.success? || !stderr.include?("physical iPhone")
  end
end

puts "Usability evidence tests passed."
