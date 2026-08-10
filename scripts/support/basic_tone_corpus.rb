# frozen_string_literal: true

module BasicToneCorpus
  class ContractError < StandardError; end

  PARAMETERS = %w[
    exposure contrast warmth highlights shadows tint saturation clarity
  ].freeze
  METRICS = %w[
    mean_luma mean_rgb mean_chroma mean_rgb_midpoint_distance mean_edge_energy
    mean_absolute_rgb_difference p95_max_channel_difference
    black_clip_ratio white_clip_ratio
  ].freeze
  ONE_CODE = 1.0 / 255

  module_function

  def validate_result!(asset_id:, result:)
    unless result.is_a?(Hash) && result["schema"] == 1 &&
           result["pipeline_schema"] == 10 && result["max_edge"] == 512 &&
           result["zero_is_exact"] == true
      raise ContractError, "#{asset_id} measurement identity is invalid"
    end
    width = positive_dimension!(asset_id, "width", result["width"])
    height = positive_dimension!(asset_id, "height", result["height"])
    raise ContractError, "#{asset_id} proxy exceeds 512 px" if [width, height].max > 512
    neutral = metrics!(asset_id, "neutral", result["neutral"])
    parameters = result["parameters"]
    unless parameters.is_a?(Hash) && parameters.keys.sort == PARAMETERS.sort
      raise ContractError, "#{asset_id} parameter set is invalid"
    end
    levels = parameters.to_h do |parameter, value|
      unless value.is_a?(Hash) && value.keys.sort == %w[negative positive]
        raise ContractError, "#{asset_id} #{parameter} levels are invalid"
      end
      [parameter, {
        "negative" => metrics!(asset_id, "#{parameter}.negative", value["negative"]),
        "positive" => metrics!(asset_id, "#{parameter}.positive", value["positive"]),
      }]
    end

    check_exposure!(asset_id, neutral, levels.fetch("exposure"))
    check_contrast!(asset_id, neutral, levels.fetch("contrast"))
    check_warmth!(asset_id, neutral, levels.fetch("warmth"))
    check_selective_tone!(asset_id, "highlights", neutral, levels.fetch("highlights"))
    check_selective_tone!(asset_id, "shadows", neutral, levels.fetch("shadows"))
    check_tint!(asset_id, neutral, levels.fetch("tint"))
    check_saturation!(asset_id, neutral, levels.fetch("saturation"))
    check_clarity!(asset_id, neutral, levels.fetch("clarity"))
  end

  def validate_corpus!(reports)
    unless reports.is_a?(Array) && reports.length == 48
      raise ContractError, "basic tone corpus requires 48 reports"
    end
    ids = reports.map { |report| report.fetch("id") }
    raise ContractError, "basic tone corpus repeats an asset" unless ids.uniq.length == ids.length
  end

  def check_exposure!(asset_id, neutral, levels)
    ordered_steps!(asset_id, "exposure", levels, neutral, "mean_luma", minimum: 4 * ONE_CODE)
  end
  private_class_method :check_exposure!

  def check_contrast!(asset_id, neutral, levels)
    require_visible!(asset_id, "contrast", levels, minimum: 3 * ONE_CODE)
    require_clip_budget!(asset_id, "contrast", levels, neutral, black: 0.015, white: 0.05)
  end
  private_class_method :check_contrast!

  def check_warmth!(asset_id, neutral, levels)
    axis = ->(metrics) { metrics.fetch("mean_rgb")[0] - metrics.fetch("mean_rgb")[2] }
    ordered_axis_steps!(asset_id, "warmth", levels, neutral, axis, minimum: 3 * ONE_CODE)
    require_visible!(asset_id, "warmth", levels, minimum: ONE_CODE)
    require_luma_budget!(asset_id, "warmth", levels, neutral, maximum: 2 * ONE_CODE)
    require_clip_budget!(asset_id, "warmth", levels, neutral, black: 0.005, white: 0.005)
  end
  private_class_method :check_warmth!

  def check_selective_tone!(asset_id, parameter, neutral, levels)
    ordered_steps!(asset_id, parameter, levels, neutral, "mean_luma", minimum: ONE_CODE)
    require_visible!(asset_id, parameter, levels, minimum: ONE_CODE)
    limits = parameter == "highlights" ? [0.005, 0.01] : [0.015, 0.005]
    require_clip_budget!(asset_id, parameter, levels, neutral, black: limits[0], white: limits[1])
  end
  private_class_method :check_selective_tone!

  def check_tint!(asset_id, neutral, levels)
    axis = lambda do |metrics|
      red, green, blue = metrics.fetch("mean_rgb")
      (red + blue) / 2 - green
    end
    ordered_axis_steps!(asset_id, "tint", levels, neutral, axis, minimum: 4 * ONE_CODE)
    require_visible!(asset_id, "tint", levels, minimum: 2 * ONE_CODE)
    require_luma_budget!(asset_id, "tint", levels, neutral, maximum: 5 * ONE_CODE)
    require_clip_budget!(asset_id, "tint", levels, neutral, black: 0.01, white: 0.01)
  end
  private_class_method :check_tint!

  def check_saturation!(asset_id, neutral, levels)
    if neutral.fetch("mean_chroma") < ONE_CODE
      levels.each do |level, metrics|
        if metrics.fetch("mean_chroma") > ONE_CODE ||
           metrics.fetch("mean_absolute_rgb_difference") > ONE_CODE
          raise ContractError, "#{asset_id} saturation invents color for an achromatic input"
        end
      end
    else
      ordered_steps!(asset_id, "saturation", levels, neutral, "mean_chroma", minimum: 3 * ONE_CODE)
      require_visible!(asset_id, "saturation", levels, minimum: ONE_CODE)
    end
    require_luma_budget!(asset_id, "saturation", levels, neutral, maximum: 5 * ONE_CODE)
    require_clip_budget!(asset_id, "saturation", levels, neutral, black: 0.005, white: 0.005)
  end
  private_class_method :check_saturation!

  def check_clarity!(asset_id, neutral, levels)
    ordered_steps!(asset_id, "clarity", levels, neutral, "mean_edge_energy", minimum: 0, exclusive: true)
    levels.each do |level, metrics|
      if metrics.fetch("p95_max_channel_difference") < ONE_CODE
        raise ContractError, "#{asset_id} clarity #{level} has no local pixel effect"
      end
    end
    require_luma_budget!(asset_id, "clarity", levels, neutral, maximum: ONE_CODE)
    require_clip_budget!(asset_id, "clarity", levels, neutral, black: 0.005, white: 0.005)
  end
  private_class_method :check_clarity!

  def ordered_steps!(asset_id, parameter, levels, neutral, metric, minimum:, exclusive: false)
    axis = ->(value) { value.fetch(metric) }
    ordered_axis_steps!(asset_id, parameter, levels, neutral, axis, minimum: minimum, exclusive: exclusive)
  end
  private_class_method :ordered_steps!

  def ordered_axis_steps!(asset_id, parameter, levels, neutral, axis, minimum:, exclusive: false)
    steps = [
      axis.call(neutral) - axis.call(levels.fetch("negative")),
      axis.call(levels.fetch("positive")) - axis.call(neutral),
    ]
    valid = exclusive ? steps.all? { |step| step > minimum } : steps.all? { |step| step >= minimum }
    raise ContractError, "#{asset_id} #{parameter} direction or strength is invalid" unless valid
  end
  private_class_method :ordered_axis_steps!

  def require_visible!(asset_id, parameter, levels, minimum:)
    levels.each do |level, metrics|
      if metrics.fetch("mean_absolute_rgb_difference") < minimum
        raise ContractError, "#{asset_id} #{parameter} #{level} is not visibly distinct"
      end
    end
  end
  private_class_method :require_visible!

  def require_luma_budget!(asset_id, parameter, levels, neutral, maximum:)
    levels.each do |level, metrics|
      if (metrics.fetch("mean_luma") - neutral.fetch("mean_luma")).abs > maximum
        raise ContractError, "#{asset_id} #{parameter} #{level} exceeds the luma budget"
      end
    end
  end
  private_class_method :require_luma_budget!

  def require_clip_budget!(asset_id, parameter, levels, neutral, black:, white:)
    levels.each do |level, metrics|
      if metrics.fetch("black_clip_ratio") - neutral.fetch("black_clip_ratio") > black
        raise ContractError, "#{asset_id} #{parameter} #{level} exceeds the black clipping budget"
      end
      if metrics.fetch("white_clip_ratio") - neutral.fetch("white_clip_ratio") > white
        raise ContractError, "#{asset_id} #{parameter} #{level} exceeds the white clipping budget"
      end
    end
  end
  private_class_method :require_clip_budget!

  def metrics!(asset_id, name, metrics)
    unless metrics.is_a?(Hash) && metrics.keys.sort == METRICS.sort
      raise ContractError, "#{asset_id} #{name} metrics are invalid"
    end
    rgb = metrics.fetch("mean_rgb")
    scalars = metrics.reject { |key, _| key == "mean_rgb" }.values
    unless rgb.is_a?(Array) && rgb.length == 3 &&
           (rgb + scalars).all? { |value| value.is_a?(Numeric) && value.finite? && (0.0..1.0).cover?(value.to_f) }
      raise ContractError, "#{asset_id} #{name} metrics are not bounded"
    end
    metrics
  end
  private_class_method :metrics!

  def positive_dimension!(asset_id, name, value)
    unless value.is_a?(Integer) && value.positive?
      raise ContractError, "#{asset_id} #{name} is invalid"
    end
    value
  end
  private_class_method :positive_dimension!
end
