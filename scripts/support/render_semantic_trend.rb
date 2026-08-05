# frozen_string_literal: true

module RenderSemanticTrend
  class ContractError < StandardError; end

  EXPOSURE_MINIMUM_LUMA_STEP = 4.0 / 255.0
  EXPOSURE_MAXIMUM_STEP_DIFFERENCE = 1.0 / 255.0
  EXPOSURE_MAXIMUM_CLIP_RATIO_DIFFERENCE = 0.01

  module_function

  def monotonic_violations(assets, metric:, minimum_step:)
    unless assets.is_a?(Array) && finite_number?(minimum_step) && minimum_step >= 0
      raise ContractError, "trend input is invalid"
    end
    seen = {}
    assets.each_with_object([]) do |asset, violations|
      asset_id = asset["id"] if asset.is_a?(Hash)
      unless asset_id.is_a?(String) && asset_id.match?(/\A[a-z0-9-]+\z/)
        raise ContractError, "trend contains an invalid asset id"
      end
      raise ContractError, "trend repeats #{asset_id}" if seen.key?(asset_id)
      seen[asset_id] = true
      values = %w[negative neutral positive].map { |name| asset[name] }
      unless values.all? { |value| finite_number?(value) && (0.0..1.0).cover?(value.to_f) }
        raise ContractError, "#{asset_id} #{metric} trend is invalid"
      end
      negative, neutral, positive = values.map(&:to_f)
      negative_step = neutral - negative
      positive_step = positive - neutral
      next if negative_step >= minimum_step && positive_step >= minimum_step
      violations << {
        "asset_id" => asset_id,
        "metric" => metric,
        "negative" => negative,
        "neutral" => neutral,
        "positive" => positive,
        "negative_step" => negative_step,
        "positive_step" => positive_step,
        "minimum_step" => minimum_step.to_f,
      }
    end
  end

  def check_exposure_alignment!(ios_assets, android_assets)
    ios = index_measurements!(ios_assets, platform: "ios")
    android = index_measurements!(android_assets, platform: "android")
    unless ios.length == 48 && android.keys == ios.keys
      raise ContractError, "exposure alignment requires the same 48 ordered assets"
    end
    violations = []
    ios.each do |asset_id, ios_asset|
      android_asset = android.fetch(asset_id)
      platform_steps = {}
      { "ios" => ios_asset, "android" => android_asset }.each do |platform, asset|
        negative = measurement_value!(asset, "negative", "mean_luma", asset_id: asset_id)
        neutral = measurement_value!(asset, "neutral", "mean_luma", asset_id: asset_id)
        positive = measurement_value!(asset, "positive", "mean_luma", asset_id: asset_id)
        steps = [neutral - negative, positive - neutral]
        platform_steps[platform] = steps
        steps.each_with_index do |step, index|
          next if step >= EXPOSURE_MINIMUM_LUMA_STEP
          violations << {
            "asset_id" => asset_id,
            "contract" => "minimum_luma_step",
            "platform" => platform,
            "step" => index.zero? ? "negative_to_neutral" : "neutral_to_positive",
            "actual" => step,
            "minimum" => EXPOSURE_MINIMUM_LUMA_STEP,
          }
        end
      end
      platform_steps.fetch("ios").zip(platform_steps.fetch("android")).each_with_index do |steps, index|
        difference = (steps[0] - steps[1]).abs
        next if difference <= EXPOSURE_MAXIMUM_STEP_DIFFERENCE
        violations << {
          "asset_id" => asset_id,
          "contract" => "cross_platform_luma_step_difference",
          "step" => index.zero? ? "negative_to_neutral" : "neutral_to_positive",
          "actual" => difference,
          "maximum" => EXPOSURE_MAXIMUM_STEP_DIFFERENCE,
        }
      end
      %w[negative neutral positive].each do |level|
        %w[black_clip_ratio white_clip_ratio].each do |metric|
          ios_value = measurement_value!(ios_asset, level, metric, asset_id: asset_id)
          android_value = measurement_value!(android_asset, level, metric, asset_id: asset_id)
          difference = (ios_value - android_value).abs
          next if difference <= EXPOSURE_MAXIMUM_CLIP_RATIO_DIFFERENCE
          violations << {
            "asset_id" => asset_id,
            "contract" => "cross_platform_clip_ratio_difference",
            "level" => level,
            "metric" => metric,
            "actual" => difference,
            "maximum" => EXPOSURE_MAXIMUM_CLIP_RATIO_DIFFERENCE,
          }
        end
      end
    end
    { "asset_count" => ios.length, "violations" => violations }
  end

  def index_measurements!(assets, platform:)
    raise ContractError, "#{platform} measurements are invalid" unless assets.is_a?(Array)
    assets.each_with_object({}) do |asset, indexed|
      asset_id = asset["id"] if asset.is_a?(Hash)
      unless asset_id.is_a?(String) && asset_id.match?(/\A[a-z0-9-]+\z/)
        raise ContractError, "#{platform} contains an invalid asset id"
      end
      raise ContractError, "#{platform} repeats #{asset_id}" if indexed.key?(asset_id)
      indexed[asset_id] = asset
    end
  end
  private_class_method :index_measurements!

  def measurement_value!(asset, level, metric, asset_id:)
    measurement = asset[level]
    value = measurement[metric] if measurement.is_a?(Hash)
    unless finite_number?(value) && (0.0..1.0).cover?(value.to_f)
      raise ContractError, "#{asset_id} #{level} #{metric} is invalid"
    end
    value.to_f
  end
  private_class_method :measurement_value!

  def finite_number?(value)
    value.is_a?(Numeric) && value.finite?
  end
  private_class_method :finite_number?
end
