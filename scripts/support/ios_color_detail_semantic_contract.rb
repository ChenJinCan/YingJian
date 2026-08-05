# frozen_string_literal: true

module IOSColorDetailSemanticContract
  class ContractError < StandardError; end

  SATURATION_CHROMATIC_FLOOR = 1.0 / 255.0
  SATURATION_MINIMUM_CHROMA_STEP = 3.0 / 255.0
  SATURATION_MINIMUM_VISIBLE_DIFFERENCE = 1.0 / 255.0
  TINT_MINIMUM_INDEX_STEP = 4.0 / 255.0
  TINT_MINIMUM_VISIBLE_DIFFERENCE = 2.0 / 255.0
  COLOR_MAXIMUM_MEAN_LUMA_DRIFT = 5.0 / 255.0
  CLARITY_MINIMUM_LOCAL_PIXEL_DIFFERENCE = 1.0 / 255.0
  CLARITY_MAXIMUM_MEAN_LUMA_DRIFT = 1.0 / 255.0
  COLOR_MAXIMUM_NEW_CLIP_RATIO = 0.01
  SATURATION_MAXIMUM_NEW_CLIP_RATIO = 0.005
  CLARITY_MAXIMUM_NEW_CLIP_RATIO = 0.005

  module_function

  def check!(saturation_report, tint_report, clarity_report)
    reports = {
      "saturation" => validate_report!(saturation_report, parameter: "saturation"),
      "tint" => validate_report!(tint_report, parameter: "tint"),
      "clarity" => validate_report!(clarity_report, parameter: "clarity"),
    }
    unless reports.values.map { |report| report.fetch("manifest_sha256") }.uniq.length == 1
      raise ContractError, "color-detail reports do not bind the same corpus"
    end
    ordered_ids = reports.values.map do |report|
      report.fetch("assets").map { |asset| asset.fetch("id") }
    end
    raise ContractError, "color-detail reports do not contain the same ordered assets" unless ordered_ids.uniq.length == 1
    source_bindings = reports.values.map do |report|
      report.fetch("assets").map { |asset| [asset.fetch("id"), asset.fetch("source_sha256")] }
    end
    unless source_bindings.uniq.length == 1
      raise ContractError, "color-detail reports do not bind the same source assets"
    end

    violations = []
    check_saturation!(reports.fetch("saturation"), violations)
    check_tint!(reports.fetch("tint"), violations)
    check_clarity!(reports.fetch("clarity"), violations)
    { "asset_count" => 48, "violations" => violations }
  rescue KeyError => error
    raise ContractError, "color-detail report is missing #{error.key}"
  end

  def check_saturation!(report, violations)
    report.fetch("assets").each do |asset|
      asset_id = asset.fetch("id")
      levels = measurements!(asset, asset_id: asset_id)
      neutral_chroma = levels.fetch("neutral").fetch("mean_chroma")
      comparisons = comparisons!(asset, asset_id: asset_id)
      if neutral_chroma < SATURATION_CHROMATIC_FLOOR
        %w[negative positive].each do |level|
          chroma = levels.fetch(level).fetch("mean_chroma")
          next if chroma <= SATURATION_CHROMATIC_FLOOR
          violations << violation(asset_id, "saturation", "maximum_achromatic_chroma", level, chroma, SATURATION_CHROMATIC_FLOOR, "maximum")
        end
        comparisons.each do |step, comparison|
          difference = comparison.fetch("mean_absolute_error")
          next if difference <= SATURATION_CHROMATIC_FLOOR
          violations << violation(asset_id, "saturation", "maximum_achromatic_difference", step, difference, SATURATION_CHROMATIC_FLOOR, "maximum")
        end
      else
        chroma = %w[negative neutral positive].map do |level|
          levels.fetch(level).fetch("mean_chroma")
        end
        [chroma[1] - chroma[0], chroma[2] - chroma[1]].each_with_index do |step, index|
          next if step >= SATURATION_MINIMUM_CHROMA_STEP
          name = index.zero? ? "negative_to_neutral" : "neutral_to_positive"
          violations << violation(asset_id, "saturation", "minimum_chroma_step", name, step, SATURATION_MINIMUM_CHROMA_STEP, "minimum")
        end
        comparisons.each do |step, comparison|
          difference = comparison.fetch("mean_absolute_error")
          next if difference >= SATURATION_MINIMUM_VISIBLE_DIFFERENCE
          violations << violation(asset_id, "saturation", "minimum_visible_difference", step, difference, SATURATION_MINIMUM_VISIBLE_DIFFERENCE, "minimum")
        end
      end
      check_luma_and_clipping!(
        asset_id,
        "saturation",
        levels,
        violations,
        luma_maximum: COLOR_MAXIMUM_MEAN_LUMA_DRIFT,
        clip_maximum: SATURATION_MAXIMUM_NEW_CLIP_RATIO,
      )
    end
  end
  private_class_method :check_saturation!

  def check_tint!(report, violations)
    report.fetch("assets").each do |asset|
      asset_id = asset.fetch("id")
      levels = measurements!(asset, asset_id: asset_id)
      indexes = %w[negative neutral positive].map do |level|
        red, green, blue = levels.fetch(level).fetch("mean_rgb")
        (red + blue) / 2 - green
      end
      [indexes[1] - indexes[0], indexes[2] - indexes[1]].each_with_index do |step, index|
        next if step >= TINT_MINIMUM_INDEX_STEP
        name = index.zero? ? "negative_to_neutral" : "neutral_to_positive"
        violations << violation(asset_id, "tint", "minimum_tint_index_step", name, step, TINT_MINIMUM_INDEX_STEP, "minimum")
      end
      comparisons!(asset, asset_id: asset_id).each do |step, comparison|
        difference = comparison.fetch("mean_absolute_error")
        next if difference >= TINT_MINIMUM_VISIBLE_DIFFERENCE
        violations << violation(asset_id, "tint", "minimum_visible_difference", step, difference, TINT_MINIMUM_VISIBLE_DIFFERENCE, "minimum")
      end
      check_luma_and_clipping!(
        asset_id,
        "tint",
        levels,
        violations,
        luma_maximum: COLOR_MAXIMUM_MEAN_LUMA_DRIFT,
        clip_maximum: COLOR_MAXIMUM_NEW_CLIP_RATIO,
      )
    end
  end
  private_class_method :check_tint!

  def check_clarity!(report, violations)
    report.fetch("assets").each do |asset|
      asset_id = asset.fetch("id")
      levels = measurements!(asset, asset_id: asset_id)
      energy = %w[negative neutral positive].map do |level|
        levels.fetch(level).fetch("mean_edge_energy")
      end
      [energy[1] - energy[0], energy[2] - energy[1]].each_with_index do |step, index|
        next if step.positive?
        name = index.zero? ? "negative_to_neutral" : "neutral_to_positive"
        violations << violation(asset_id, "clarity", "minimum_edge_energy_step", name, step, 0.0, "minimum_exclusive")
      end
      comparisons!(asset, asset_id: asset_id).each do |step, comparison|
        difference = comparison.fetch("p95_max_channel_error")
        next if difference >= CLARITY_MINIMUM_LOCAL_PIXEL_DIFFERENCE
        violations << violation(asset_id, "clarity", "minimum_local_pixel_difference", step, difference, CLARITY_MINIMUM_LOCAL_PIXEL_DIFFERENCE, "minimum")
      end
      check_luma_and_clipping!(
        asset_id,
        "clarity",
        levels,
        violations,
        luma_maximum: CLARITY_MAXIMUM_MEAN_LUMA_DRIFT,
        clip_maximum: CLARITY_MAXIMUM_NEW_CLIP_RATIO,
      )
    end
  end
  private_class_method :check_clarity!

  def check_luma_and_clipping!(asset_id, parameter, levels, violations, luma_maximum:, clip_maximum:)
    neutral = levels.fetch("neutral")
    %w[negative positive].each do |level|
      measurement = levels.fetch(level)
      drift = (measurement.fetch("mean_luma") - neutral.fetch("mean_luma")).abs
      if drift > luma_maximum
        violations << violation(asset_id, parameter, "maximum_mean_luma_drift", level, drift, luma_maximum, "maximum")
      end
      %w[black_clip_ratio white_clip_ratio].each do |metric|
        increase = [measurement.fetch(metric) - neutral.fetch(metric), 0.0].max
        next if increase <= clip_maximum
        violations << violation(asset_id, parameter, "maximum_new_#{metric}", level, increase, clip_maximum, "maximum")
      end
    end
  end
  private_class_method :check_luma_and_clipping!

  def violation(asset_id, parameter, contract, step, actual, limit, limit_name)
    {
      "asset_id" => asset_id,
      "parameter" => parameter,
      "contract" => contract,
      "step" => step,
      "actual" => actual,
      limit_name => limit,
    }
  end
  private_class_method :violation

  def validate_report!(report, parameter:)
    unless report.is_a?(Hash) && report["schema"] == 1 &&
           report["engineering_only"] == true && report["observation_only"] == true &&
           report["thresholds_frozen"] == false && report["platform"] == "ios" &&
           report["parameter"] == parameter &&
           report["profiles"] == ["#{parameter}-negative", "neutral", "#{parameter}-positive"] &&
           report["sample_max_edge"] == 512 && report["asset_count"] == 48 &&
           report["assets"].is_a?(Array) && report["assets"].length == 48
      raise ContractError, "iOS #{parameter} observation report identity is invalid"
    end
    %w[manifest_sha256 analyzer_source_sha256 comparator_source_sha256 runner_source_sha256].each do |key|
      validate_sha!(report[key], key)
    end
    seen = {}
    report.fetch("assets").each do |asset|
      asset_id = asset["id"] if asset.is_a?(Hash)
      unless asset_id.is_a?(String) && asset_id.match?(/\A[a-z0-9-]+\z/)
        raise ContractError, "#{parameter} contains an invalid asset id"
      end
      raise ContractError, "#{parameter} repeats #{asset_id}" if seen.key?(asset_id)
      seen[asset_id] = true
      validate_sha!(asset["source_sha256"], "#{asset_id} source")
    end
    report
  end
  private_class_method :validate_report!

  def measurements!(asset, asset_id:)
    %w[negative neutral positive].to_h do |level|
      measurement = asset[level]
      rgb = measurement["mean_rgb"] if measurement.is_a?(Hash)
      values = %w[mean_chroma mean_luma mean_edge_energy black_clip_ratio white_clip_ratio].map do |key|
        measurement[key] if measurement.is_a?(Hash)
      end
      unless rgb.is_a?(Array) && rgb.length == 3 && rgb.all? { |value| ratio?(value) } &&
             values.all? { |value| ratio?(value) }
        raise ContractError, "#{asset_id} #{level} color-detail measurement is invalid"
      end
      [level, measurement]
    end
  end
  private_class_method :measurements!

  def comparisons!(asset, asset_id:)
    comparisons = asset["comparison"]
    raise ContractError, "#{asset_id} comparison is invalid" unless comparisons.is_a?(Hash)
    %w[negative_to_neutral neutral_to_positive].to_h do |step|
      comparison = comparisons[step]
      unless comparison.is_a?(Hash) && ratio?(comparison["mean_absolute_error"]) &&
             ratio?(comparison["p95_max_channel_error"])
        raise ContractError, "#{asset_id} #{step} comparison is invalid"
      end
      [step, comparison]
    end
  end
  private_class_method :comparisons!

  def validate_sha!(value, label)
    raise ContractError, "#{label} hash is invalid" unless value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
  end
  private_class_method :validate_sha!

  def ratio?(value)
    value.is_a?(Numeric) && value.finite? && (0.0..1.0).cover?(value.to_f)
  end
  private_class_method :ratio?
end
