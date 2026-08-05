# frozen_string_literal: true

module AndroidFileRenderCorpus
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

  def index_results!(results, expected_ids:)
    unless results.is_a?(Array) && results.all? { |result| result.is_a?(Hash) }
      raise ContractError, "instrumentation results must be a list of mappings"
    end
    indexed = {}
    results.each do |result|
      asset_id = result["id"]
      unless asset_id.is_a?(String) && !asset_id.empty?
        raise ContractError, "instrumentation result id is missing"
      end
      raise ContractError, "duplicate result for #{asset_id}" if indexed.key?(asset_id)
      indexed[asset_id] = result
    end
    missing = expected_ids - indexed.keys
    extra = indexed.keys - expected_ids
    unless missing.empty? && extra.empty?
      raise ContractError, "instrumentation result identities differ from manifest"
    end
    indexed
  end

  def validate_result!(asset_id:, expected_dimensions:, expected_source_sha256:, result:)
    before = result["source_sha256_before"]
    after = result["source_sha256_after"]
    unless before == expected_source_sha256 && after == before
      raise ContractError, "#{asset_id} source hash changed"
    end
    unless result["output_sha256"].is_a?(String) &&
           result["output_sha256"].match?(/\A[0-9a-f]{64}\z/)
      raise ContractError, "#{asset_id} output hash is invalid"
    end
    unless [result["width"], result["height"]] == expected_dimensions
      raise ContractError, "#{asset_id} output dimensions changed"
    end
    raise ContractError, "#{asset_id} output must be JPEG" unless result["format"] == "jpeg"
    raise ContractError, "#{asset_id} output must be sRGB" unless result["is_srgb"] == true
    unless result["orientation"] == 1
      raise ContractError, "#{asset_id} output orientation must be normalized"
    end
    if result["has_gps"] != false || result["has_device_identity"] != false
      raise ContractError, "#{asset_id} output contains private metadata"
    end
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
end
