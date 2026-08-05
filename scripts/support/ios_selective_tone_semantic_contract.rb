# frozen_string_literal: true

module IOSSelectiveToneSemanticContract
  class ContractError < StandardError; end

  MINIMUM_MEAN_LUMA_STEP = 1.0 / 255.0
  MINIMUM_VISIBLE_DIFFERENCE = 1.0 / 255.0
  CLIP_LIMITS = {
    "highlights" => { "black_clip_ratio" => 0.005, "white_clip_ratio" => 0.01 },
    "shadows" => { "black_clip_ratio" => 0.015, "white_clip_ratio" => 0.005 },
  }.freeze

  module_function

  def check!(highlights_report, shadows_report)
    reports = {
      "highlights" => validate_report!(highlights_report, parameter: "highlights"),
      "shadows" => validate_report!(shadows_report, parameter: "shadows"),
    }
    unless reports.values.map { |report| report.fetch("manifest_sha256") }.uniq.length == 1
      raise ContractError, "selective-tone reports do not bind the same corpus"
    end
    unless reports.values.map { |report| report.fetch("assets").map { |asset| asset.fetch("id") } }.uniq.length == 1
      raise ContractError, "selective-tone reports do not contain the same ordered assets"
    end
    source_bindings = reports.values.map do |report|
      report.fetch("assets").map { |asset| [asset.fetch("id"), asset.fetch("source_sha256")] }
    end
    unless source_bindings.uniq.length == 1
      raise ContractError, "selective-tone reports do not bind the same source assets"
    end

    violations = []
    reports.each do |parameter, report|
      report.fetch("assets").each do |asset|
        asset_id = asset.fetch("id")
        measurements = %w[negative neutral positive].to_h do |level|
          [level, measurement!(asset[level], asset_id: asset_id, level: level)]
        end
        lumas = %w[negative neutral positive].map do |level|
          measurements.fetch(level).fetch("mean_luma")
        end
        [lumas[1] - lumas[0], lumas[2] - lumas[1]].each_with_index do |step, index|
          next if step >= MINIMUM_MEAN_LUMA_STEP
          violations << {
            "asset_id" => asset_id,
            "parameter" => parameter,
            "contract" => "minimum_mean_luma_step",
            "step" => index.zero? ? "negative_to_neutral" : "neutral_to_positive",
            "actual" => step,
            "minimum" => MINIMUM_MEAN_LUMA_STEP,
          }
        end

        comparisons = asset["comparison"]
        raise ContractError, "#{asset_id} comparison is invalid" unless comparisons.is_a?(Hash)
        %w[negative_to_neutral neutral_to_positive].each do |step|
          comparison = comparisons[step]
          difference = comparison["mean_absolute_error"] if comparison.is_a?(Hash)
          raise ContractError, "#{asset_id} #{step} difference is invalid" unless ratio?(difference)
          next if difference >= MINIMUM_VISIBLE_DIFFERENCE
          violations << {
            "asset_id" => asset_id,
            "parameter" => parameter,
            "contract" => "minimum_visible_difference",
            "step" => step,
            "actual" => difference.to_f,
            "minimum" => MINIMUM_VISIBLE_DIFFERENCE,
          }
        end

        neutral = measurements.fetch("neutral")
        %w[negative positive].each do |level|
          CLIP_LIMITS.fetch(parameter).each do |metric, maximum|
            increase = [measurements.fetch(level).fetch(metric) - neutral.fetch(metric), 0.0].max
            next if increase <= maximum
            violations << {
              "asset_id" => asset_id,
              "parameter" => parameter,
              "contract" => "maximum_new_#{metric}",
              "level" => level,
              "actual" => increase,
              "maximum" => maximum,
            }
          end
        end
      end
    end
    { "asset_count" => 48, "violations" => violations }
  rescue KeyError => error
    raise ContractError, "selective-tone report is missing #{error.key}"
  end

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

  def measurement!(measurement, asset_id:, level:)
    unless measurement.is_a?(Hash) && ratio?(measurement["mean_luma"]) &&
           ratio?(measurement["black_clip_ratio"]) && ratio?(measurement["white_clip_ratio"])
      raise ContractError, "#{asset_id} #{level} selective-tone measurement is invalid"
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
