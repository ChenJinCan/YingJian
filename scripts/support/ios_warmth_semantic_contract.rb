# frozen_string_literal: true

module IOSWarmthSemanticContract
  class ContractError < StandardError; end

  MINIMUM_WARMTH_INDEX_STEP = 3.0 / 255.0
  MINIMUM_VISIBLE_DIFFERENCE = 1.0 / 255.0
  MAXIMUM_MEAN_LUMA_DRIFT = 2.0 / 255.0
  MAXIMUM_NEW_CLIP_RATIO = 0.005

  module_function

  def check!(report)
    validate_identity!(report)
    seen = {}
    violations = []
    report.fetch("assets").each do |asset|
      asset_id = asset["id"] if asset.is_a?(Hash)
      unless asset_id.is_a?(String) && asset_id.match?(/\A[a-z0-9-]+\z/)
        raise ContractError, "warmth report contains an invalid asset id"
      end
      raise ContractError, "warmth report repeats #{asset_id}" if seen.key?(asset_id)
      seen[asset_id] = true
      validate_sha!(asset["source_sha256"], "#{asset_id} source")
      measurements = %w[negative neutral positive].to_h do |level|
        [level, measurement!(asset[level], asset_id: asset_id, level: level)]
      end
      comparisons = asset["comparison"]
      raise ContractError, "#{asset_id} comparison is invalid" unless comparisons.is_a?(Hash)

      indexes = %w[negative neutral positive].map do |level|
        rgb = measurements.fetch(level).fetch("mean_rgb")
        rgb[0] - rgb[2]
      end
      [indexes[1] - indexes[0], indexes[2] - indexes[1]].each_with_index do |step, index|
        next if step >= MINIMUM_WARMTH_INDEX_STEP
        violations << {
          "asset_id" => asset_id,
          "contract" => "minimum_warmth_index_step",
          "step" => index.zero? ? "negative_to_neutral" : "neutral_to_positive",
          "actual" => step,
          "minimum" => MINIMUM_WARMTH_INDEX_STEP,
        }
      end

      %w[negative_to_neutral neutral_to_positive].each do |step|
        comparison = comparisons[step]
        difference = comparison["mean_absolute_error"] if comparison.is_a?(Hash)
        raise ContractError, "#{asset_id} #{step} difference is invalid" unless ratio?(difference)
        next if difference >= MINIMUM_VISIBLE_DIFFERENCE
        violations << {
          "asset_id" => asset_id,
          "contract" => "minimum_visible_difference",
          "step" => step,
          "actual" => difference.to_f,
          "minimum" => MINIMUM_VISIBLE_DIFFERENCE,
        }
      end

      neutral = measurements.fetch("neutral")
      %w[negative positive].each do |level|
        measurement = measurements.fetch(level)
        luma_drift = (measurement.fetch("mean_luma") - neutral.fetch("mean_luma")).abs
        if luma_drift > MAXIMUM_MEAN_LUMA_DRIFT
          violations << {
            "asset_id" => asset_id,
            "contract" => "maximum_mean_luma_drift",
            "level" => level,
            "actual" => luma_drift,
            "maximum" => MAXIMUM_MEAN_LUMA_DRIFT,
          }
        end
        %w[black_clip_ratio white_clip_ratio].each do |metric|
          increase = [measurement.fetch(metric) - neutral.fetch(metric), 0.0].max
          next if increase <= MAXIMUM_NEW_CLIP_RATIO
          violations << {
            "asset_id" => asset_id,
            "contract" => "maximum_new_#{metric}",
            "level" => level,
            "actual" => increase,
            "maximum" => MAXIMUM_NEW_CLIP_RATIO,
          }
        end
      end
    end
    { "asset_count" => seen.length, "violations" => violations }
  rescue KeyError => error
    raise ContractError, "warmth report is missing #{error.key}"
  end

  def validate_identity!(report)
    unless report.is_a?(Hash) && report["schema"] == 1 &&
           report["engineering_only"] == true && report["observation_only"] == true &&
           report["thresholds_frozen"] == false && report["platform"] == "ios" &&
           report["parameter"] == "warmth" &&
           report["profiles"] == %w[warmth-negative neutral warmth-positive] &&
           report["sample_max_edge"] == 512 && report["asset_count"] == 48 &&
           report["assets"].is_a?(Array) && report["assets"].length == 48
      raise ContractError, "iOS warmth observation report identity is invalid"
    end
    %w[manifest_sha256 analyzer_source_sha256 comparator_source_sha256 runner_source_sha256].each do |key|
      validate_sha!(report[key], key)
    end
  end
  private_class_method :validate_identity!

  def measurement!(measurement, asset_id:, level:)
    rgb = measurement["mean_rgb"] if measurement.is_a?(Hash)
    unless rgb.is_a?(Array) && rgb.length == 3 && rgb.all? { |value| ratio?(value) } &&
           ratio?(measurement["mean_luma"]) && ratio?(measurement["black_clip_ratio"]) &&
           ratio?(measurement["white_clip_ratio"])
      raise ContractError, "#{asset_id} #{level} warmth measurement is invalid"
    end
    measurement
  end
  private_class_method :measurement!

  def validate_sha!(value, label)
    raise ContractError, "#{label} hash is invalid" unless value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
  end
  private_class_method :validate_sha!

  def ratio?(value)
    value.is_a?(Numeric) && value.finite? && (0.0..1.0).cover?(value.to_f)
  end
  private_class_method :ratio?
end
