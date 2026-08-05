# frozen_string_literal: true

module IOSFileRenderCorpus
  class ContractError < StandardError; end

  module_function

  def expected_dimensions(media)
    width = media.fetch("width")
    height = media.fetch("height")
    orientation = media.fetch("orientation")
    unless width.is_a?(Integer) && width.positive? && height.is_a?(Integer) && height.positive?
      raise ContractError, "source dimensions must be positive integers"
    end
    unless orientation.is_a?(Integer) && (1..8).cover?(orientation)
      raise ContractError, "source orientation must be EXIF 1 through 8"
    end
    (5..8).cover?(orientation) ? [height, width] : [width, height]
  end

  def validated_output_root(path, repo_root:)
    expanded_repo = File.expand_path(repo_root)
    quality_root = File.join(expanded_repo, ".quality")
    expanded = File.expand_path(path, expanded_repo)
    unless expanded.start_with?("#{quality_root}/")
      raise ContractError, "output must remain inside .quality"
    end
    expanded
  end

  def validate_output_ancestry!(path, repo_root:)
    expanded_repo = File.expand_path(repo_root)
    quality_root = File.join(expanded_repo, ".quality")
    expanded = validated_output_root(path, repo_root: expanded_repo)
    unless File.directory?(quality_root)
      raise ContractError, ".quality must exist before validating output"
    end

    ancestor = File.dirname(expanded)
    ancestor = File.dirname(ancestor) until File.exist?(ancestor)
    quality_real = File.realpath(quality_root)
    ancestor_real = File.realpath(ancestor)
    unless ancestor_real == quality_real || ancestor_real.start_with?("#{quality_real}/")
      raise ContractError, "output resolves outside .quality"
    end
    expanded
  rescue SystemCallError => error
    raise ContractError, "output ancestry could not be resolved: #{error.message}"
  end

  def validate_render!(asset_id:, expected_dimensions:, result:)
    unless asset_id.is_a?(String) && !asset_id.empty? && result.is_a?(Hash)
      raise ContractError, "render result identity is invalid"
    end
    actual_dimensions = [result["width"], result["height"]]
    unless actual_dimensions == expected_dimensions
      raise ContractError, "#{asset_id} output dimensions changed"
    end
    unless result["format"] == "jpeg"
      raise ContractError, "#{asset_id} output must be JPEG"
    end
    unless result["color_space"].is_a?(String) && result["color_space"].match?(/sRGB/i)
      raise ContractError, "#{asset_id} output must be sRGB"
    end
    unless result["orientation"] == 1
      raise ContractError, "#{asset_id} output orientation must be normalized"
    end
    if result["has_gps"] != false || result["has_device_identity"] != false
      raise ContractError, "#{asset_id} output contains private metadata"
    end
  end
end
