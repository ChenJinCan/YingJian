# frozen_string_literal: true

module IOSContrastSemanticContract
  class ContractError < StandardError; end

  MINIMUM_VISIBLE_DIFFERENCE = 3.0 / 255.0
  MAXIMUM_NEW_BLACK_CLIP_RATIO = 0.015
  MAXIMUM_NEW_WHITE_CLIP_RATIO = 0.05

  module_function

  def check!(report)
    validate_identity!(report)
    seen = {}
    violations = []
    report.fetch("assets").each do |asset|
      asset_id = asset["id"] if asset.is_a?(Hash)
      unless asset_id.is_a?(String) && asset_id.match?(/\A[a-z0-9-]+\z/)
        raise ContractError, "contrast report contains an invalid asset id"
      end
      raise ContractError, "contrast report repeats #{asset_id}" if seen.key?(asset_id)
      seen[asset_id] = true
      validate_sha!(asset["source_sha256"], "#{asset_id} source")

      measurements = %w[negative neutral positive].to_h do |level|
        [level, measurement!(asset[level], asset_id: asset_id, level: level)]
      end
      comparisons = asset["comparison"]
      raise ContractError, "#{asset_id} comparison is invalid" unless comparisons.is_a?(Hash)
      %w[negative_to_neutral neutral_to_positive].each do |step|
        comparison = comparisons[step]
        difference = comparison["mean_absolute_error"] if comparison.is_a?(Hash)
        unless ratio?(difference)
          raise ContractError, "#{asset_id} #{step} difference is invalid"
        end
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
        {
          "black_clip_ratio" => MAXIMUM_NEW_BLACK_CLIP_RATIO,
          "white_clip_ratio" => MAXIMUM_NEW_WHITE_CLIP_RATIO,
        }.each do |metric, maximum|
          increase = [measurement.fetch(metric) - neutral.fetch(metric), 0.0].max
          next if increase <= maximum
          violations << {
            "asset_id" => asset_id,
            "contract" => "maximum_new_#{metric}",
            "level" => level,
            "actual" => increase,
            "maximum" => maximum,
          }
        end
      end
    end
    { "asset_count" => seen.length, "violations" => violations }
  rescue KeyError => error
    raise ContractError, "contrast report is missing #{error.key}"
  end

  def validate_identity!(report)
    unless report.is_a?(Hash) && report["schema"] == 1 &&
           report["engineering_only"] == true && report["observation_only"] == true &&
           report["thresholds_frozen"] == false && report["platform"] == "ios" &&
           report["parameter"] == "contrast" &&
           report["profiles"] == %w[contrast-negative neutral contrast-positive] &&
           report["sample_max_edge"] == 512 && report["asset_count"] == 48 &&
           report["assets"].is_a?(Array) && report["assets"].length == 48
      raise ContractError, "iOS contrast observation report identity is invalid"
    end
    %w[manifest_sha256 analyzer_source_sha256 comparator_source_sha256 runner_source_sha256].each do |key|
      validate_sha!(report[key], key)
    end
  end
  private_class_method :validate_identity!

  def measurement!(measurement, asset_id:, level:)
    unless measurement.is_a?(Hash) &&
           ratio?(measurement["black_clip_ratio"]) && ratio?(measurement["white_clip_ratio"])
      raise ContractError, "#{asset_id} #{level} clipping measurement is invalid"
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
