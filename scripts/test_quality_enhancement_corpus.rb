#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/quality_enhancement_corpus"

class QualityEnhancementCorpusTest < Minitest::Test
  def test_accepts_visible_bounded_quality_trends
    QualityEnhancementCorpus.validate_measurement!(
      asset_id: "low-light-001",
      tags: %w[low_light jpeg],
      result: valid_result,
    )
  end

  def test_rejects_shadow_clipping_and_weak_noise_reduction
    clipped = valid_result
    clipped["measurements"]["haze_removal"]["black_clip_ratio"] = 0.02
    assert_raises(QualityEnhancementCorpus::ContractError) do
      QualityEnhancementCorpus.validate_measurement!(
        asset_id: "low-light-001", tags: %w[low_light], result: clipped
      )
    end

    weak = valid_result
    weak["measurements"]["noise_reduction"]["mean_local_residual"] = 0.019
    assert_raises(QualityEnhancementCorpus::ContractError) do
      QualityEnhancementCorpus.validate_measurement!(
        asset_id: "low-light-001", tags: %w[low_light], result: weak
      )
    end
  end

  def test_rejects_nonexact_zero_and_missing_effects
    nonexact = valid_result.merge("zero_is_exact" => false)
    assert_raises(QualityEnhancementCorpus::ContractError) do
      QualityEnhancementCorpus.validate_measurement!(
        asset_id: "low-light-001", tags: %w[low_light], result: nonexact
      )
    end
    missing = valid_result
    missing["measurements"].delete("detail_sharpening")
    assert_raises(QualityEnhancementCorpus::ContractError) do
      QualityEnhancementCorpus.validate_measurement!(
        asset_id: "low-light-001", tags: %w[low_light], result: missing
      )
    end
  end

  private

  def valid_result
    neutral = {
      "mean_luma" => 0.25,
      "luma_standard_deviation" => 0.15,
      "mean_edge_energy" => 0.04,
      "mean_local_residual" => 0.02,
      "black_clip_ratio" => 0.001,
      "white_clip_ratio" => 0.001,
    }
    {
      "schema" => 1,
      "pipeline_schema" => 6,
      "max_edge" => 2_048,
      "width" => 2_048,
      "height" => 1_365,
      "zero_is_exact" => true,
      "measurements" => {
        "neutral" => neutral.dup,
        "noise_reduction" => neutral.merge(
          "mean_edge_energy" => 0.03,
          "mean_local_residual" => 0.014,
        ),
        "low_light_recovery" => neutral.merge("mean_luma" => 0.27),
        "haze_removal" => neutral.merge("luma_standard_deviation" => 0.155),
        "detail_sharpening" => neutral.merge("mean_edge_energy" => 0.045),
      },
    }
  end
end
