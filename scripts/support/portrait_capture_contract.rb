# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "time"

module PortraitCaptureContract
  class ValidationError < StandardError; end

  SHA256 = /\A[0-9a-f]{64}\z/
  EXPECTED_OUTPUTS = {
    "baselineOriginal" => {
      file: "baseline-original.jpg", variant: "original", render_kind: "source", format: "jpeg"
    },
    "offExport" => {
      file: "yingjian-off-export.jpg", variant: "off", render_kind: "export", format: "jpeg"
    },
    "defaultExport" => {
      file: "yingjian-default-export.jpg", variant: "default", render_kind: "export", format: "jpeg"
    },
    "highSafeExport" => {
      file: "yingjian-high-safe-export.jpg", variant: "high_safe", render_kind: "export", format: "jpeg"
    },
    "defaultPreview" => {
      file: "candidate-default-preview.png", variant: "default", render_kind: "preview", format: "png"
    },
  }.freeze

  module_function

  def validate(manifest_path, quality_root:, require_physical: true)
    quality_root = File.realpath(quality_root)
    manifest_path = File.expand_path(manifest_path)
    ensure_file_inside!(manifest_path, quality_root, "manifest")
    capture_root = File.realpath(File.dirname(manifest_path))
    expect(File.basename(manifest_path) == "capture-manifest.json",
           "manifest file must be named capture-manifest.json")
    expect(File.dirname(File.realpath(manifest_path)) == capture_root,
           "manifest must not resolve outside the capture directory")

    manifest = parse_json(manifest_path)
    expect(manifest.is_a?(Hash), "manifest must be a JSON object")
    expect(manifest["schema"] == 1, "schema must equal 1")
    expect(manifest["productionEligible"] == false, "productionEligible must equal false")
    expect_nonempty(manifest, "candidateKind")
    expect_nonempty(manifest, "effectVersion")
    expect_nonempty(manifest, "executionEnvironment")
    if require_physical
      expect(
        manifest["executionEnvironment"] == "physical-device",
        "executionEnvironment must equal physical-device for review intake",
      )
    end
    %w[device os appVersion appBuild capturedAtUtc].each { |field| expect_nonempty(manifest, field) }
    expect(manifest["appVersion"] != "unknown", "appVersion must be captured")
    expect(manifest["appBuild"] != "unknown", "appBuild must be captured")
    begin
      captured_at = Time.iso8601(manifest["capturedAtUtc"])
      expect(captured_at.utc_offset.zero?, "capturedAtUtc must use UTC")
    rescue ArgumentError
      raise ValidationError, "capturedAtUtc must be ISO-8601"
    end

    raw_source_sha256 = manifest["rawSourceSha256"]
    expect(raw_source_sha256.is_a?(String) && raw_source_sha256.match?(SHA256),
           "rawSourceSha256 must be a lowercase SHA-256")
    source_width = manifest["sourceWidth"]
    source_height = manifest["sourceHeight"]
    expect(source_width.is_a?(Integer) && source_width.positive?, "sourceWidth must be positive")
    expect(source_height.is_a?(Integer) && source_height.positive?, "sourceHeight must be positive")
    expect(source_width <= 12_000 && source_height <= 12_000, "source dimensions exceed 12,000 px")
    expect(source_width <= 48_000_000 / source_height, "source dimensions exceed 48 MP")
    face_count = manifest["faceCount"]
    expect(face_count.is_a?(Integer) && face_count >= 0, "faceCount must be a non-negative integer")

    default_strength = number_in_unit_interval(manifest, "defaultStrength")
    high_safe_strength = number_in_unit_interval(manifest, "highSafeStrength")
    expect(default_strength.positive?, "defaultStrength must be greater than zero")
    expect(high_safe_strength > default_strength, "highSafeStrength must exceed defaultStrength")

    outputs = manifest["outputs"]
    expect(outputs.is_a?(Hash), "outputs must be an object")
    expect(outputs.keys.sort == EXPECTED_OUTPUTS.keys.sort,
           "outputs must contain exactly #{EXPECTED_OUTPUTS.keys.sort.join(", ")}")

    validated_outputs = EXPECTED_OUTPUTS.to_h do |name, contract|
      entry = outputs[name]
      expect(entry.is_a?(Hash), "outputs.#{name} must be an object")
      expect(entry["file"] == contract[:file], "outputs.#{name}.file must equal #{contract[:file]}")
      expect(entry["variant"] == contract[:variant],
             "outputs.#{name}.variant must equal #{contract[:variant]}")
      expect(entry["renderKind"] == contract[:render_kind],
             "outputs.#{name}.renderKind must equal #{contract[:render_kind]}")
      expected_hash = entry["sha256"]
      expect(expected_hash.is_a?(String) && expected_hash.match?(SHA256),
             "outputs.#{name}.sha256 must be a lowercase SHA-256")

      output_path = File.expand_path(entry["file"], capture_root)
      expect(File.dirname(output_path) == capture_root,
             "outputs.#{name}.file must be a direct child of the capture directory")
      ensure_file_inside!(output_path, quality_root, "outputs.#{name}.file")
      expect(File.dirname(File.realpath(output_path)) == capture_root,
             "outputs.#{name}.file must not resolve outside the capture directory")
      actual_hash = Digest::SHA256.file(output_path).hexdigest
      expect(actual_hash == expected_hash, "outputs.#{name}.sha256 does not match the file")

      media = probe_image(output_path, "outputs.#{name}.file")
      expect(media[:format] == contract[:format],
             "outputs.#{name}.file must be #{contract[:format]}")
      expect(media[:color_space] == "srgb", "outputs.#{name}.file must be sRGB")
      expect(media[:orientation] == 1, "outputs.#{name}.file orientation must equal 1")
      expected_dimensions = if name == "defaultPreview"
        preview_dimensions(source_width, source_height)
      else
        [source_width, source_height]
      end
      expect([media[:width], media[:height]] == expected_dimensions,
             "outputs.#{name}.file dimensions must equal #{expected_dimensions.join("x")}")

      [name, entry.merge("path" => output_path, "media" => media)]
    end

    baseline_hash = validated_outputs.fetch("baselineOriginal").fetch("sha256")
    expect(validated_outputs.fetch("offExport").fetch("sha256") == baseline_hash,
           "offExport must be byte-identical to baselineOriginal")
    if face_count.zero?
      %w[defaultExport highSafeExport].each do |name|
        expect(validated_outputs.fetch(name).fetch("sha256") == baseline_hash,
               "#{name} must be byte-identical to baselineOriginal when faceCount is zero")
      end
    end

    {
      "manifest" => manifest,
      "manifest_path" => manifest_path,
      "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
      "capture_root" => capture_root,
      "outputs" => validated_outputs,
    }
  end

  def ensure_file_inside!(path, root, label)
    raise ValidationError, "#{label} is missing" unless File.file?(path)

    real = File.realpath(path)
    unless real.start_with?("#{root}/")
      raise ValidationError, "#{label} must remain inside the ignored .quality directory"
    end
  rescue Errno::ENOENT
    raise ValidationError, "#{label} could not be resolved"
  end

  def probe_image(path, label)
    stdout, stderr, status = Open3.capture3(
      "/usr/bin/sips",
      "-g", "pixelWidth",
      "-g", "pixelHeight",
      "-g", "format",
      "-g", "profile",
      "-g", "orientation",
      path,
    )
    unless status.success?
      detail = stderr.lines.first&.strip || "unknown error"
      raise ValidationError, "#{label} media probe failed: #{detail}"
    end
    values = stdout.each_line.each_with_object({}) do |line, parsed|
      match = line.match(/^\s+(pixelWidth|pixelHeight|format|profile|orientation):\s*(.+)$/)
      parsed[match[1]] = match[2].strip if match
    end
    width = Integer(values["pixelWidth"], exception: false)
    height = Integer(values["pixelHeight"], exception: false)
    orientation = values["orientation"] == "<nil>" ? 1 : Integer(values["orientation"], exception: false)
    format = values["format"] == "jpg" ? "jpeg" : values["format"]
    color_space = values["profile"]&.match?(/\bsrgb\b/i) ? "srgb" : "unknown"
    unless width&.positive? && height&.positive? && orientation && format
      raise ValidationError, "#{label} media probe returned incomplete metadata"
    end
    { width: width, height: height, orientation: orientation, format: format, color_space: color_space }
  rescue Errno::ENOENT
    raise ValidationError, "#{label} media probe unavailable: macOS sips was not found"
  end

  def preview_dimensions(width, height)
    scale = [1.0, 1_600.0 / [width, height].max].min
    [(width * scale).ceil, (height * scale).ceil]
  end

  def parse_json(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError => error
    raise ValidationError, "manifest is invalid JSON: #{error.message}"
  end

  def expect_nonempty(mapping, field)
    value = mapping[field]
    expect(value.is_a?(String) && !value.empty?, "#{field} must be a non-empty string")
  end

  def number_in_unit_interval(mapping, field)
    value = mapping[field]
    expect(value.is_a?(Numeric) && value.finite? && value.between?(0, 1),
           "#{field} must be a finite number between 0 and 1")
    value
  end

  def expect(condition, message)
    raise ValidationError, message unless condition
  end
end
