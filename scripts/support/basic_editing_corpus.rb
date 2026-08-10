# frozen_string_literal: true

module BasicEditingCorpus
  class ContractError < StandardError; end

  PRIORITY_TAGS = %w[
    portrait_single portrait_multi no_face landscape food pet low_light backlit
    mixed_light group_member exif_rotated display_p3
  ].freeze
  FILTERS = %w[
    clean portrait cinematic film warmSun coolAir vivid faded noir food landscape night
  ].freeze
  CHANNELS = %w[red orange yellow green cyan blue purple magenta].freeze
  OPERATIONS = %w[hue saturation lightness].freeze
  METRICS = %w[
    mean_luma mean_chroma mean_absolute_rgb_difference black_clip_ratio white_clip_ratio
  ].freeze

  module_function

  def select_assets(assets)
    raise ContractError, "assets must be a list" unless assets.is_a?(Array)
    selected = []
    used = {}
    PRIORITY_TAGS.each do |tag|
      asset = assets.find do |candidate|
        candidate.is_a?(Hash) && candidate["tags"].is_a?(Array) &&
          candidate["tags"].include?(tag) && !used[candidate["id"]]
      end
      raise ContractError, "no unique asset covers #{tag}" unless asset
      used[asset.fetch("id")] = true
      selected << asset
    end
    selected
  end

  def validate_result!(asset_id:, result:)
    unless result.is_a?(Hash) && result["schema"] == 1 &&
           result["pipeline_schema"] == 10 && result["max_edge"] == 1_024 &&
           result["zero_is_exact"] == true
      raise ContractError, "#{asset_id} measurement identity is invalid"
    end
    width = result["width"]
    height = result["height"]
    unless width.is_a?(Integer) && height.is_a?(Integer) &&
           width.positive? && height.positive? && [width, height].max <= 1_024
      raise ContractError, "#{asset_id} dimensions are invalid"
    end
    neutral = validate_metrics!(asset_id, "neutral", result["neutral"])
    filters = result["filters"]
    unless filters.is_a?(Hash) && filters.keys.sort == FILTERS.sort
      raise ContractError, "#{asset_id} filter set is invalid"
    end
    filters.each do |name, raw_metrics|
      metrics = validate_metrics!(asset_id, name, raw_metrics)
      if metrics.fetch("mean_absolute_rgb_difference") < 1.0 / 255
        raise ContractError, "#{asset_id} #{name} is not visibly distinct"
      end
      require_clip_budget!(asset_id, name, metrics, neutral, black: 0.005, white: 0.01)
    end
    hsl = result["hsl"]
    unless hsl.is_a?(Hash) && hsl.keys.sort == CHANNELS.sort
      raise ContractError, "#{asset_id} HSL channel set is invalid"
    end
    hsl.each do |channel, operations|
      unless operations.is_a?(Hash) && operations.keys.sort == OPERATIONS.sort
        raise ContractError, "#{asset_id} #{channel} operation set is invalid"
      end
      operations.each do |operation, raw_metrics|
        metrics = validate_metrics!(asset_id, "#{channel}.#{operation}", raw_metrics)
        require_clip_budget!(
          asset_id, "#{channel}.#{operation}", metrics, neutral,
          black: 0.005, white: 0.005
        )
      end
    end
  end

  def validate_corpus!(reports)
    unless reports.is_a?(Array) && reports.length == PRIORITY_TAGS.length
      raise ContractError, "basic editing corpus requires 12 reports"
    end
    ids = reports.map { |report| report.fetch("id") }
    raise ContractError, "basic editing corpus repeats an asset" unless ids.uniq.length == ids.length
    CHANNELS.each do |channel|
      hue_differences = reports.map do |report|
        report.dig("result", "hsl", channel, "hue", "mean_absolute_rgb_difference")
      end
      saturation_steps = reports.map do |report|
        result = report.fetch("result")
        result.dig("hsl", channel, "saturation", "mean_chroma") -
          result.dig("neutral", "mean_chroma")
      end
      lightness_steps = reports.map do |report|
        result = report.fetch("result")
        result.dig("hsl", channel, "lightness", "mean_luma") -
          result.dig("neutral", "mean_luma")
      end
      raise ContractError, "#{channel} hue has no visible corpus result" if hue_differences.max < 0.0007
      raise ContractError, "#{channel} saturation has no positive corpus result" if saturation_steps.max < 0.0005
      raise ContractError, "#{channel} lightness has no positive corpus result" if lightness_steps.max < 0.0015
    end
  end

  def validate_metrics!(asset_id, name, metrics)
    unless metrics.is_a?(Hash) && metrics.keys.sort == METRICS.sort
      raise ContractError, "#{asset_id} #{name} metrics are invalid"
    end
    unless metrics.values.all? { |value| value.is_a?(Numeric) && value.finite? && (0.0..1.0).cover?(value.to_f) }
      raise ContractError, "#{asset_id} #{name} metrics are not bounded"
    end
    metrics
  end
  private_class_method :validate_metrics!

  def require_clip_budget!(asset_id, name, metrics, neutral, black:, white:)
    if metrics.fetch("black_clip_ratio") - neutral.fetch("black_clip_ratio") > black
      raise ContractError, "#{asset_id} #{name} exceeds the black clipping budget"
    end
    if metrics.fetch("white_clip_ratio") - neutral.fetch("white_clip_ratio") > white
      raise ContractError, "#{asset_id} #{name} exceeds the white clipping budget"
    end
  end
  private_class_method :require_clip_budget!
end
