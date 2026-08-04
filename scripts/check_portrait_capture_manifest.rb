#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "support/portrait_capture_contract"

manifest_argument = ARGV.shift
allow_simulator = ARGV.delete("--allow-simulator")
unless manifest_argument && ARGV.empty?
  warn "Portrait capture check failed: usage: check_portrait_capture_manifest.rb MANIFEST [--allow-simulator]"
  exit 1
end

repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
begin
  validated = PortraitCaptureContract.validate(
    File.expand_path(manifest_argument),
    quality_root: quality_root,
    require_physical: !allow_simulator,
  )
rescue PortraitCaptureContract::ValidationError, SystemCallError => error
  warn "Portrait capture check failed: #{error.message}"
  exit 1
end

manifest = validated.fetch("manifest")
puts JSON.generate(
  status: "valid",
  capture_id: File.basename(validated.fetch("capture_root")),
  manifest_sha256: validated.fetch("manifest_sha256"),
  effect_version: manifest.fetch("effectVersion"),
  execution_environment: manifest.fetch("executionEnvironment"),
  face_count: manifest.fetch("faceCount"),
)
