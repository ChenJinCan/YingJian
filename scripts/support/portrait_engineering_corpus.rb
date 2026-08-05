# frozen_string_literal: true

module PortraitEngineeringCorpus
  class ContractError < StandardError; end

  module_function

  def classify_hashes(hashes)
    values = %w[off default high_safe].map do |name|
      value = hashes[name]
      unless value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
        raise ContractError, "#{name} must be a lowercase SHA-256"
      end
      value
    end
    return "preserved" if values.uniq.length == 1
    return "applied" if values.uniq.length == values.length

    raise ContractError, "portrait variants are partially distinct"
  end

  def validate_classification!(asset_id:, tags:, classification:)
    unless asset_id.is_a?(String) && !asset_id.empty?
      raise ContractError, "asset id must be present"
    end
    unless tags.is_a?(Array) && tags.all? { |tag| tag.is_a?(String) }
      raise ContractError, "#{asset_id} tags must be strings"
    end
    if (tags.include?("no_face") || tags.include?("portrait_multi")) &&
       classification != "preserved"
      raise ContractError, "#{asset_id} must be safely preserved"
    end
    if tags.include?("portrait_single") && classification != "applied"
      raise ContractError, "#{asset_id} must apply the portrait candidate"
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
