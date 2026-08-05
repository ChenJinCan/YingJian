# frozen_string_literal: true

module CrossPlatformRenderTolerance
  class ContractError < StandardError; end

  PROFILE = "neutral-export-v1"
  EXPECTED_ASSET_COUNT = 48
  EXPECTED_SAMPLE_MAX_EDGE = 512
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/.freeze
  MAXIMUMS = {
    "mean_absolute_error" => 1.0 / 255.0,
    "root_mean_square_error" => 2.0 / 255.0,
    "maximum_absolute_error" => 32.0 / 255.0,
    "mean_absolute_luma_error" => 1.0 / 255.0,
    "maximum_absolute_rgb_bias" => 1.0 / 255.0,
    "p95_max_channel_error" => 3.0 / 255.0,
    "p99_max_channel_error" => 4.0 / 255.0,
    "pixel_ratio_over_4_code_values" => 0.01,
    "pixel_ratio_over_8_code_values" => 0.005,
  }.freeze
  MINIMUMS = {
    "psnr_db" => 42.0,
  }.freeze

  module_function

  def check!(report)
    validate_report_identity!(report)
    violations = []
    seen = {}
    report.fetch("assets").each do |asset|
      asset_id = asset["id"] if asset.is_a?(Hash)
      unless asset_id.is_a?(String) && asset_id.match?(/\A[a-z0-9-]+\z/)
        raise ContractError, "report contains an invalid asset id"
      end
      raise ContractError, "report repeats #{asset_id}" if seen.key?(asset_id)
      seen[asset_id] = true
      metric = asset["metric"]
      raise ContractError, "#{asset_id} metric is missing" unless metric.is_a?(Hash)

      MAXIMUMS.each do |name, maximum|
        actual = finite_metric!(metric, name, asset_id: asset_id)
        next unless actual > maximum
        violations << violation(asset_id, name, actual, "maximum", maximum)
      end
      MINIMUMS.each do |name, minimum|
        actual = metric[name]
        next if name == "psnr_db" && actual.nil?
        actual = finite_metric!(metric, name, asset_id: asset_id)
        next unless actual < minimum
        violations << violation(asset_id, name, actual, "minimum", minimum)
      end
    end
    {
      "profile" => PROFILE,
      "asset_count" => report.fetch("asset_count"),
      "violations" => violations,
    }
  end

  def validated_report_path(path, repo_root:)
    quality_root = File.join(File.expand_path(repo_root), ".quality")
    expanded = File.expand_path(path, repo_root)
    unless File.file?(expanded) && File.directory?(quality_root)
      raise ContractError, "observation report is missing"
    end
    quality_real = File.realpath(quality_root)
    report_real = File.realpath(expanded)
    unless report_real.start_with?("#{quality_real}/")
      raise ContractError, "observation report resolves outside .quality"
    end
    report_real
  rescue SystemCallError => error
    raise ContractError, "observation report could not be resolved: #{error.message}"
  end

  def validate_report_identity!(report)
    unless report.is_a?(Hash) &&
           report["schema"] == 1 &&
           report["engineering_only"] == true &&
           report["observation_only"] == true &&
           report["thresholds_frozen"] == false &&
           report["sample_max_edge"] == EXPECTED_SAMPLE_MAX_EDGE &&
           report["asset_count"] == EXPECTED_ASSET_COUNT
      raise ContractError, "report is not a neutral export observation contract"
    end
    %w[
      manifest_sha256
      ios_report_sha256
      android_report_sha256
      comparator_source_sha256
      runner_source_sha256
    ].each do |name|
      value = report[name]
      raise ContractError, "#{name} is invalid" unless value.is_a?(String) && value.match?(SHA256_PATTERN)
    end
    assets = report["assets"]
    unless assets.is_a?(Array) && assets.length == EXPECTED_ASSET_COUNT
      raise ContractError, "report must contain exactly #{EXPECTED_ASSET_COUNT} assets"
    end
  end
  private_class_method :validate_report_identity!

  def finite_metric!(metric, name, asset_id:)
    value = metric[name]
    unless value.is_a?(Numeric) && value.finite? && value >= 0
      raise ContractError, "#{asset_id} #{name} is invalid"
    end
    value.to_f
  end
  private_class_method :finite_metric!

  def violation(asset_id, metric, actual, bound_name, bound)
    {
      "asset_id" => asset_id,
      "metric" => metric,
      "actual" => actual,
      bound_name => bound,
    }
  end
  private_class_method :violation
end
