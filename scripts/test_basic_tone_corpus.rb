#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/basic_tone_corpus"

class BasicToneCorpusTest < Minitest::Test
  def test_accepts_complete_visible_safe_tone_contract
    BasicToneCorpus.validate_result!(asset_id: "asset-1", result: valid_result)
    BasicToneCorpus.validate_corpus!(48.times.map { |index| { "id" => "asset-#{index}" } })
  end

  def test_rejects_wrong_direction_and_clarity_clipping
    direction = valid_result
    direction["parameters"]["highlights"]["positive"]["mean_luma"] = 0.5
    assert_raises(BasicToneCorpus::ContractError) do
      BasicToneCorpus.validate_result!(asset_id: "asset-1", result: direction)
    end
    clipping = valid_result
    clipping["parameters"]["clarity"]["positive"]["black_clip_ratio"] = 0.02
    assert_raises(BasicToneCorpus::ContractError) do
      BasicToneCorpus.validate_result!(asset_id: "asset-1", result: clipping)
    end
  end

  def test_allows_achromatic_saturation_to_remain_exact
    result = valid_result
    result["neutral"]["mean_chroma"] = 0
    %w[negative positive].each do |level|
      result["parameters"]["saturation"][level]["mean_chroma"] = 0
      result["parameters"]["saturation"][level]["mean_absolute_rgb_difference"] = 0
    end
    BasicToneCorpus.validate_result!(asset_id: "asset-1", result: result)
  end

  private

  def valid_result
    neutral = metrics(luma: 0.5, chroma: 0.2, midpoint: 0.2, edge: 0.1, rgb: [0.5, 0.5, 0.5])
    parameters = BasicToneCorpus::PARAMETERS.to_h do |parameter|
      negative = metrics(luma: 0.48, chroma: 0.18, midpoint: 0.18, edge: 0.09, rgb: [0.46, 0.52, 0.54])
      positive = metrics(luma: 0.52, chroma: 0.22, midpoint: 0.22, edge: 0.11, rgb: [0.54, 0.48, 0.46])
      case parameter
      when "contrast"
        negative["mean_luma"] = positive["mean_luma"] = 0.5
      when "warmth"
        negative.merge!("mean_luma" => 0.499, "mean_rgb" => [0.48, 0.5, 0.52])
        positive.merge!("mean_luma" => 0.501, "mean_rgb" => [0.52, 0.5, 0.48])
      when "highlights", "shadows", "exposure"
        # Luma ordering already matches the declared direction.
      when "tint"
        negative.merge!("mean_luma" => 0.499, "mean_rgb" => [0.48, 0.53, 0.48])
        positive.merge!("mean_luma" => 0.501, "mean_rgb" => [0.52, 0.47, 0.52])
      when "saturation"
        negative["mean_luma"] = positive["mean_luma"] = 0.5
      when "clarity"
        negative["mean_luma"] = positive["mean_luma"] = 0.5
      end
      [parameter, { "negative" => negative, "positive" => positive }]
    end
    {
      "schema" => 1,
      "pipeline_schema" => 10,
      "max_edge" => 512,
      "width" => 512,
      "height" => 384,
      "zero_is_exact" => true,
      "neutral" => neutral,
      "parameters" => parameters,
    }
  end

  def metrics(luma:, chroma:, midpoint:, edge:, rgb:)
    {
      "mean_luma" => luma,
      "mean_rgb" => rgb,
      "mean_chroma" => chroma,
      "mean_rgb_midpoint_distance" => midpoint,
      "mean_edge_energy" => edge,
      "mean_absolute_rgb_difference" => 0.03,
      "p95_max_channel_difference" => 0.05,
      "black_clip_ratio" => 0.001,
      "white_clip_ratio" => 0.001,
    }
  end
end
