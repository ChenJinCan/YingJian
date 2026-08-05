#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/render_semantic_trend"

class RenderSemanticTrendTest < Minitest::Test
  def test_accepts_every_asset_when_exposure_luma_is_strictly_monotonic
    assets = [
      { "id" => "asset-a", "negative" => 0.20, "neutral" => 0.40, "positive" => 0.60 },
      { "id" => "asset-b", "negative" => 0.30, "neutral" => 0.31, "positive" => 0.32 },
    ]

    assert_empty RenderSemanticTrend.monotonic_violations(
      assets,
      metric: "mean_luma",
      minimum_step: 1.0 / 255.0,
    )
  end

  def test_reports_each_non_monotonic_or_too_small_step
    assets = [
      { "id" => "reversed", "negative" => 0.4, "neutral" => 0.3, "positive" => 0.5 },
      { "id" => "flat", "negative" => 0.3, "neutral" => 0.301, "positive" => 0.5 },
    ]

    violations = RenderSemanticTrend.monotonic_violations(
      assets,
      metric: "mean_luma",
      minimum_step: 1.0 / 255.0,
    )

    assert_equal %w[flat reversed], violations.map { |item| item.fetch("asset_id") }.sort
    assert violations.all? { |item| item.fetch("metric") == "mean_luma" }
  end

  def test_rejects_duplicate_ids_and_non_finite_values
    assert_raises(RenderSemanticTrend::ContractError) do
      RenderSemanticTrend.monotonic_violations(
        [
          { "id" => "same", "negative" => 0.1, "neutral" => 0.2, "positive" => 0.3 },
          { "id" => "same", "negative" => 0.1, "neutral" => 0.2, "positive" => 0.3 },
        ],
        metric: "mean_luma",
        minimum_step: 0.0,
      )
    end
    assert_raises(RenderSemanticTrend::ContractError) do
      RenderSemanticTrend.monotonic_violations(
        [{ "id" => "bad", "negative" => 0.1, "neutral" => Float::NAN, "positive" => 0.3 }],
        metric: "mean_luma",
        minimum_step: 0.0,
      )
    end
  end

  def test_exposure_gate_requires_visible_steps_and_cross_platform_strength_alignment
    ios = exposure_assets(step: 0.04, clip_offset: 0.0)
    android = exposure_assets(step: 0.043, clip_offset: 0.004)

    result = RenderSemanticTrend.check_exposure_alignment!(ios, android)

    assert_empty result.fetch("violations")
    assert_equal 48, result.fetch("asset_count")
  end

  def test_exposure_gate_reports_weak_steps_strength_drift_and_clip_drift
    ios = exposure_assets(step: 0.04, clip_offset: 0.0)
    android = exposure_assets(step: 0.043, clip_offset: 0.004)
    android.first.fetch("neutral")["mean_luma"] = 0.201
    android[1].fetch("positive")["mean_luma"] = 0.30
    android[2].fetch("positive")["white_clip_ratio"] = 0.031

    result = RenderSemanticTrend.check_exposure_alignment!(ios, android)

    names = result.fetch("violations").map { |item| item.fetch("contract") }
    assert_includes names, "minimum_luma_step"
    assert_includes names, "cross_platform_luma_step_difference"
    assert_includes names, "cross_platform_clip_ratio_difference"
  end

  private

  def exposure_assets(step:, clip_offset:)
    Array.new(48) do |index|
      {
        "id" => format("asset-%02d", index + 1),
        "negative" => measurement(0.4 - step, 0.0 + clip_offset),
        "neutral" => measurement(0.4, 0.01 + clip_offset),
        "positive" => measurement(0.4 + step, 0.02 + clip_offset),
      }
    end
  end

  def measurement(luma, white_clip)
    {
      "mean_luma" => luma,
      "black_clip_ratio" => 0.0,
      "white_clip_ratio" => white_clip,
    }
  end
end
