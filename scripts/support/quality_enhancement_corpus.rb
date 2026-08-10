# frozen_string_literal: true

module QualityEnhancementCorpus
  class ContractError < StandardError; end

  EXPECTED_EFFECTS = %w[
    neutral
    noise_reduction
    low_light_recovery
    haze_removal
    detail_sharpening
  ].freeze
  METRICS = %w[
    mean_luma
    luma_standard_deviation
    mean_edge_energy
    mean_local_residual
    black_clip_ratio
    white_clip_ratio
  ].freeze
  MAX_CLIP_INCREASE = 0.005

  module_function

  def validate_measurement!(asset_id:, tags:, result:)
    unless asset_id.is_a?(String) && !asset_id.empty? && tags.is_a?(Array)
      raise ContractError, "measurement identity is invalid"
    end
    unless result.is_a?(Hash) && result["schema"] == 1 &&
           result["pipeline_schema"] == 6 && result["max_edge"] == 2_048 &&
           result["zero_is_exact"] == true
      raise ContractError, "#{asset_id} measurement identity is invalid"
    end
    width = result["width"]
    height = result["height"]
    unless width.is_a?(Integer) && height.is_a?(Integer) &&
           width.positive? && height.positive? && [width, height].max <= 2_048
      raise ContractError, "#{asset_id} proxy dimensions are invalid"
    end
    measurements = result["measurements"]
    unless measurements.is_a?(Hash) && measurements.keys.sort == EXPECTED_EFFECTS.sort
      raise ContractError, "#{asset_id} effect set is invalid"
    end
    measurements.each do |effect, metrics|
      unless metrics.is_a?(Hash) && metrics.keys.sort == METRICS.sort
        raise ContractError, "#{asset_id} #{effect} metric set is invalid"
      end
      metrics.each do |name, value|
        unless finite_number?(value) && (0.0..1.0).cover?(value.to_f)
          raise ContractError, "#{asset_id} #{effect} #{name} is invalid"
        end
      end
    end

    neutral = measurements.fetch("neutral")
    noise = measurements.fetch("noise_reduction")
    low_light = measurements.fetch("low_light_recovery")
    haze = measurements.fetch("haze_removal")
    sharpen = measurements.fetch("detail_sharpening")
    require_ratio!(asset_id, "noise residual", noise, neutral, "mean_local_residual", maximum: 0.9)
    require_ratio!(asset_id, "noise edge preservation", noise, neutral, "mean_edge_energy", minimum: 0.5)
    if tags.include?("low_light") &&
       low_light.fetch("mean_luma") - neutral.fetch("mean_luma") < 2.0 / 255
      raise ContractError, "#{asset_id} low-light recovery is not visible"
    end
    unless haze.fetch("luma_standard_deviation") - neutral.fetch("luma_standard_deviation") >= 0.0005
      raise ContractError, "#{asset_id} haze removal does not improve separation"
    end
    require_ratio!(asset_id, "detail edge", sharpen, neutral, "mean_edge_energy", minimum: 1.01)
    [low_light, haze, sharpen].each do |effect|
      %w[black_clip_ratio white_clip_ratio].each do |metric|
        if effect.fetch(metric) - neutral.fetch(metric) > MAX_CLIP_INCREASE
          raise ContractError, "#{asset_id} #{metric} increase exceeds the safety budget"
        end
      end
    end
  end

  def require_ratio!(asset_id, name, effect, neutral, metric, minimum: nil, maximum: nil)
    baseline = neutral.fetch(metric)
    raise ContractError, "#{asset_id} #{metric} baseline is empty" unless baseline.positive?
    ratio = effect.fetch(metric) / baseline
    if minimum && ratio < minimum
      raise ContractError, "#{asset_id} #{name} ratio is below #{minimum}"
    end
    if maximum && ratio > maximum
      raise ContractError, "#{asset_id} #{name} ratio exceeds #{maximum}"
    end
  end
  private_class_method :require_ratio!

  def finite_number?(value)
    value.is_a?(Numeric) && value.finite?
  end
  private_class_method :finite_number?
end
