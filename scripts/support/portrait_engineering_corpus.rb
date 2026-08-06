# frozen_string_literal: true

module PortraitEngineeringCorpus
  class ContractError < StandardError; end

  REQUIRED_ASSET_COUNT = 48
  MINIMUM_SINGLE_PORTRAIT_COUNT = 36
  PORTRAIT_ROLES = %w[portrait_single portrait_multi no_face].freeze
  SUPPLEMENTAL_TAG = "portrait_engineering_supplemental"
  EFFECT_METRIC_VERSION = "whole-frame-srgb-rgba8-v1"
  EFFECT_METRIC_VARIANTS = %w[off default high_safe].freeze
  EFFECT_METRIC_FIELDS = %w[
    mean_absolute_difference
    changed_pixel_fraction_at_2
    p99_max_channel_difference
  ].freeze
  DEFAULT_MINIMUM_MEAN_ABSOLUTE_DIFFERENCE = 0.10
  DEFAULT_MINIMUM_CHANGED_PIXEL_FRACTION = 0.02
  DEFAULT_MINIMUM_P99_MAX_CHANNEL_DIFFERENCE = 4
  EFFECT_WHOLE_FRAME_CHANGE_CEILINGS = {
    "off" => {
      "mean_absolute_difference" => 0,
      "changed_pixel_fraction_at_2" => 0,
      "p99_max_channel_difference" => 0,
    },
    "default" => {
      "mean_absolute_difference" => 3.0,
      "changed_pixel_fraction_at_2" => 0.30,
      "p99_max_channel_difference" => 48,
    },
    "high_safe" => {
      "mean_absolute_difference" => 4.0,
      "changed_pixel_fraction_at_2" => 0.35,
      "p99_max_channel_difference" => 64,
    },
  }.freeze
  MINIMUM_DIRECTIONAL_COSINE_SIMILARITY = 0.95
  MINIMUM_DEFAULT_CHANGED_PIXELS_RETAINED_FRACTION = 0.95
  PROGRESSION_METRIC_FIELDS = %w[
    directional_cosine_similarity
    default_changed_pixels_retained_fraction
  ].freeze

  module_function

  def validate_manifest!(manifest)
    unless manifest.is_a?(Hash) && manifest["status"] == "ready"
      raise ContractError, "manifest must be ready"
    end
    unless manifest["portrait_required_assets"] == REQUIRED_ASSET_COUNT
      raise ContractError, "portrait_required_assets must equal #{REQUIRED_ASSET_COUNT}"
    end
    unless manifest["portrait_minimum_single_assets"] == MINIMUM_SINGLE_PORTRAIT_COUNT
      raise ContractError,
            "portrait_minimum_single_assets must equal #{MINIMUM_SINGLE_PORTRAIT_COUNT}"
    end
    unless manifest["portrait_roles"] == PORTRAIT_ROLES
      raise ContractError, "portrait_roles must equal #{PORTRAIT_ROLES.join(", ")}"
    end
    assets = engineering_assets(manifest)
    unless assets.is_a?(Array) && assets.length == REQUIRED_ASSET_COUNT
      raise ContractError, "manifest must contain exactly #{REQUIRED_ASSET_COUNT} assets"
    end

    single_portrait_count = 0
    assets.each_with_index do |asset, index|
      unless asset.is_a?(Hash)
        raise ContractError, "assets[#{index}] must be a mapping"
      end
      tags = asset["tags"]
      unless tags.is_a?(Array) && tags.all? { |tag| tag.is_a?(String) }
        raise ContractError, "assets[#{index}] tags must be strings"
      end
      roles = tags & PORTRAIT_ROLES
      unless roles.length == 1
        asset_id = asset["id"] || "assets[#{index}]"
        raise ContractError, "#{asset_id} must declare exactly one portrait role"
      end
      single_portrait_count += 1 if roles.first == "portrait_single"
    end

    return if single_portrait_count >= MINIMUM_SINGLE_PORTRAIT_COUNT

    raise ContractError,
          "manifest must contain at least #{MINIMUM_SINGLE_PORTRAIT_COUNT} portrait_single assets"
  end

  def engineering_assets(manifest)
    assets = manifest["assets"]
    return assets unless assets.is_a?(Array)

    assets.reject do |asset|
      asset.is_a?(Hash) && Array(asset["tags"]).include?(SUPPLEMENTAL_TAG)
    end
  end

  def classify_hashes(hashes)
    values = %w[baseline off default high_safe].to_h do |name|
      value = hashes[name]
      unless value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
        raise ContractError, "#{name} must be a lowercase SHA-256"
      end
      [name, value]
    end
    unless values.fetch("off") == values.fetch("baseline")
      raise ContractError, "off must match the independent baseline"
    end
    return "preserved" if values.values.uniq.length == 1
    if values.fetch("default") != values.fetch("baseline") &&
       values.fetch("high_safe") != values.fetch("baseline") &&
       values.fetch("default") != values.fetch("high_safe")
      return "applied"
    end

    raise ContractError, "portrait variants are partially distinct"
  end

  def validate_classification!(asset_id:, tags:, classification:)
    unless asset_id.is_a?(String) && !asset_id.empty?
      raise ContractError, "asset id must be present"
    end
    unless tags.is_a?(Array) && tags.all? { |tag| tag.is_a?(String) }
      raise ContractError, "#{asset_id} tags must be strings"
    end
    if tags.include?("no_face") && classification != "preserved"
      raise ContractError, "#{asset_id} must be safely preserved"
    end
    if (tags.include?("portrait_single") || tags.include?("portrait_multi")) &&
       classification != "applied"
      raise ContractError, "#{asset_id} must apply the portrait candidate"
    end
  end

  def validate_effect_metrics!(asset_id:, classification:, metrics:)
    unless asset_id.is_a?(String) && !asset_id.empty?
      raise ContractError, "asset id must be present"
    end
    unless %w[applied preserved].include?(classification)
      raise ContractError, "#{asset_id} classification is invalid"
    end
    unless metrics.is_a?(Hash) && metrics["metric_version"] == EFFECT_METRIC_VERSION
      raise ContractError, "#{asset_id} effect metric version is invalid"
    end
    unless metrics["proxy_max_edge"] == 512
      raise ContractError, "#{asset_id} effect metrics must use a 512 px proxy"
    end
    EFFECT_METRIC_VARIANTS.each do |variant|
      values = metrics[variant]
      unless values.is_a?(Hash)
        raise ContractError, "#{asset_id} #{variant} effect metrics are missing"
      end
      EFFECT_METRIC_FIELDS.each do |field|
        value = values[field]
        unless value.is_a?(Numeric) && value.finite? && value >= 0
          raise ContractError, "#{asset_id} #{variant} #{field} must be finite and non-negative"
        end
      end
      exceeds_change_ceiling = EFFECT_METRIC_FIELDS.any? do |field|
        values.fetch(field) > EFFECT_WHOLE_FRAME_CHANGE_CEILINGS.fetch(variant).fetch(field)
      end
      if exceeds_change_ceiling
        if variant == "off"
          raise ContractError, "#{asset_id} off differs from the independent baseline"
        end
        raise ContractError, "#{asset_id} #{variant} effect exceeds the whole-frame change ceiling"
      end
    end
    progression = metrics["progression"]
    unless progression.is_a?(Hash)
      raise ContractError, "#{asset_id} progression metrics are missing"
    end
    PROGRESSION_METRIC_FIELDS.each do |field|
      value = progression[field]
      unless value.is_a?(Numeric) && value.finite? && value.between?(0, 1)
        raise ContractError, "#{asset_id} progression #{field} must be finite and between 0 and 1"
      end
    end
    if classification == "preserved"
      changed = EFFECT_METRIC_VARIANTS.any? do |variant|
        EFFECT_METRIC_FIELDS.any? { |field| metrics.fetch(variant).fetch(field) != 0 }
      end
      raise ContractError, "#{asset_id} preserved input changed pixels" if changed
      unless PROGRESSION_METRIC_FIELDS.all? { |field| progression.fetch(field) == 1 }
        raise ContractError, "#{asset_id} preserved input progression must remain identity"
      end

      return
    end

    default = metrics.fetch("default")
    if default.fetch("mean_absolute_difference") < DEFAULT_MINIMUM_MEAN_ABSOLUTE_DIFFERENCE ||
       default.fetch("changed_pixel_fraction_at_2") < DEFAULT_MINIMUM_CHANGED_PIXEL_FRACTION ||
       default.fetch("p99_max_channel_difference") < DEFAULT_MINIMUM_P99_MAX_CHANNEL_DIFFERENCE
      raise ContractError, "#{asset_id} default effect is below the engineering visibility floor"
    end
    high_safe = metrics.fetch("high_safe")
    unless high_safe.fetch("mean_absolute_difference") > default.fetch("mean_absolute_difference") &&
           high_safe.fetch("changed_pixel_fraction_at_2") > default.fetch("changed_pixel_fraction_at_2")
      raise ContractError, "#{asset_id} high-safe effect must be stronger than default"
    end
    if progression.fetch("directional_cosine_similarity") < MINIMUM_DIRECTIONAL_COSINE_SIMILARITY
      raise ContractError, "#{asset_id} high-safe effect direction diverges from default"
    end
    if progression.fetch("default_changed_pixels_retained_fraction") <
       MINIMUM_DEFAULT_CHANGED_PIXELS_RETAINED_FRACTION
      raise ContractError, "#{asset_id} high-safe changed-pixel region diverges from default"
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
