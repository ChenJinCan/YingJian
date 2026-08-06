#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "tmpdir"

def fail_check(message)
  warn "iOS reshape fixture check failed: #{message}"
  exit 1
end

def capture!(*command)
  stdout, stderr, status = Open3.capture3(*command)
  return stdout if status.success?

  detail = stderr.lines.first&.strip || stdout.lines.first&.strip || "unknown failure"
  fail_check("#{File.basename(command.first)} failed: #{detail}")
end

def parse_json(value, label)
  JSON.parse(value)
rescue JSON::ParserError => error
  fail_check("#{label} did not return JSON: #{error.message}")
end

repo_root = File.expand_path("..", __dir__)
fixtures = {
  "face" => {
    "path" => File.join(repo_root, "ios/RunnerTests/Fixtures/portrait-front-cc-by-sa.jpg"),
    "sha256" => "f57d7bdb6ae02759571a1f9c4b5df99b4b88c2f24978fafc3e7f61dca887b66c",
    "strength" => 0.5,
    "minimum" => 0.075,
    "maximum" => 0.11,
  },
  "body" => {
    "path" => File.join(repo_root, "ios/RunnerTests/Fixtures/body-standing-unoccluded-pd.jpg"),
    "sha256" => "8e1e4933ea09c54316a8326816f723a03377ac020045f5a85f134d4f7e9c5469",
    "strength" => 0.35,
    "minimum" => 0.02,
    "maximum" => 0.06,
  },
}

fixtures.each do |kind, fixture|
  fail_check("#{kind} fixture is missing") unless File.file?(fixture.fetch("path"))
  actual_hash = Digest::SHA256.file(fixture.fetch("path")).hexdigest
  fail_check("#{kind} fixture hash changed") unless actual_hash == fixture.fetch("sha256")
end

portrait_source = File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift")
renderer_source = File.join(repo_root, "ios/Runner/IOSPhotoFileRenderer.swift")
probe_source = File.join(repo_root, "scripts/support/render_ios_file_pipeline.swift")
metric_source = File.join(repo_root, "scripts/support/measure_ios_reshape_contours.swift")
[portrait_source, renderer_source, probe_source, metric_source].each do |path|
  fail_check("required production or metric source is missing: #{path}") unless File.file?(path)
end

Dir.mktmpdir("yingjian-reshape-fixtures-") do |directory|
  renderer = File.join(directory, "renderer")
  metric = File.join(directory, "metric")
  capture!(
    "/usr/bin/xcrun", "swiftc", "-parse-as-library",
    portrait_source, renderer_source, probe_source, "-o", renderer
  )
  capture!(
    "/usr/bin/xcrun", "swiftc", "-parse-as-library",
    metric_source, "-o", metric
  )

  fixtures.each do |kind, fixture|
    recipe = {
      "schemaVersion" => 3,
      "workingColorSpace" => "srgb",
      "adjustments" => {
        "exposureEv" => 0, "highlights" => 0, "shadows" => 0,
        "contrast" => 0, "warmth" => 0, "tint" => 0,
        "saturation" => 0, "clarity" => 0,
      },
      "geometry" => {
        "normalizedCrop" => [0, 0, 1, 1],
        "quarterTurns" => 0,
        "straightenDegrees" => 0,
      },
      "portrait" => { "recipeVersion" => 1, "strength" => 0 },
      "reshape" => {
        "recipeVersion" => 1,
        "faceSlimStrength" => kind == "face" ? fixture.fetch("strength") : 0,
        "bodySlimStrength" => kind == "body" ? fixture.fetch("strength") : 0,
      },
    }
    recipe_path = File.join(directory, "#{kind}-recipe.json")
    output_path = File.join(directory, "#{kind}-output.jpg")
    File.write(recipe_path, JSON.generate(recipe))

    render_result = parse_json(
      capture!(renderer, fixture.fetch("path"), output_path, recipe_path),
      "#{kind} renderer"
    )
    fail_check("#{kind} output dimensions changed") unless
      render_result["width"].is_a?(Integer) && render_result["width"].positive? &&
      render_result["height"].is_a?(Integer) && render_result["height"].positive?
    fail_check("#{kind} output was not a privacy-safe sRGB JPEG") unless
      render_result["format"] == "jpeg" &&
      render_result["color_space"].to_s.match?(/sRGB/i) &&
      render_result["has_gps"] == false &&
      render_result["has_device_identity"] == false

    measurement = parse_json(
      capture!(metric, kind, fixture.fetch("path"), output_path),
      "#{kind} contour metric"
    )
    reduction = -Float(measurement.fetch("relative_change"))
    unless measurement["narrowed"] == true &&
           reduction.between?(fixture.fetch("minimum"), fixture.fetch("maximum"))
      fail_check(
        "#{kind} contour reduction #{(reduction * 100).round(3)}% is outside " \
        "#{(fixture.fetch("minimum") * 100).round(1)}%..." \
        "#{(fixture.fetch("maximum") * 100).round(1)}%"
      )
    end
    puts "#{kind} contour reduction: #{(reduction * 100).round(3)}%"
  end
end

puts "iOS production reshape fixtures satisfy the frozen visible-effect ranges."
