# frozen_string_literal: true

module DeviceEvidenceContract
  BUDGETS = {
    "low" => {
      first_preview: 4_000, recommendations: 12_000, slider: 120,
      fps: 24, export_12mp: 8_000, batch: 60_000,
    },
    "mid" => {
      first_preview: 2_500, recommendations: 8_000, slider: 100,
      fps: 30, export_12mp: 5_000, batch: 40_000,
    },
    "high" => {
      first_preview: 1_800, recommendations: 6_000, slider: 80,
      fps: 45, export_12mp: 3_500, export_48mp: 8_000, batch: 30_000,
    },
  }.freeze

  MID_TIER_PRODUCT_TYPES = %w[iPhone14,5 iPhone14,7 iPhone14,8].freeze

  module_function

  def physical_tier_matches?(tier:, product_type:, marketing_name:)
    case tier
    when "low"
      product_type == "iPhone12,1" && marketing_name == "iPhone 11"
    when "mid"
      MID_TIER_PRODUCT_TYPES.include?(product_type) &&
        ["iPhone 13", "iPhone 14", "iPhone 14 Plus"].include?(marketing_name)
    when "high"
      match = product_type.to_s.match(/\AiPhone(\d+),\d+\z/)
      match && match[1].to_i >= 16 && marketing_name.to_s.match?(/\AiPhone .+ Pro(?: Max)?\z/)
    else
      false
    end
  end
end
