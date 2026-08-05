#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/ios_contrast_semantic_contract"

class IOSContrastSemanticContractTest < Minitest::Test
  def test_accepts_visible_contrast_steps_without_new_clipping
    result = IOSContrastSemanticContract.check!(valid_report)

    assert_equal 48, result.fetch("asset_count")
    assert_empty result.fetch("violations")
  end

  def test_reports_invisible_steps_and_new_black_or_white_clipping
    report = valid_report
    first = report.fetch("assets").first
    first.dig("comparison", "negative_to_neutral")["mean_absolute_error"] = 2.0 / 255.0
    first.fetch("positive")["black_clip_ratio"] = 0.026
    first.fetch("positive")["white_clip_ratio"] = 0.061

    result = IOSContrastSemanticContract.check!(report)

    contracts = result.fetch("violations").map { |item| item.fetch("contract") }
    assert_includes contracts, "minimum_visible_difference"
    assert_includes contracts, "maximum_new_black_clip_ratio"
    assert_includes contracts, "maximum_new_white_clip_ratio"
  end

  def test_rejects_wrong_identity_duplicate_assets_and_invalid_measurements
    invalid_reports = [
      valid_report.merge("platform" => "android"),
      valid_report.merge("parameter" => "exposure"),
      valid_report.merge("asset_count" => 47),
    ]
    duplicate = valid_report
    duplicate.fetch("assets")[1]["id"] = "asset-01"
    invalid_reports << duplicate
    missing_comparison = valid_report
    missing_comparison.fetch("assets").first.delete("comparison")
    invalid_reports << missing_comparison

    invalid_reports.each do |report|
      assert_raises(IOSContrastSemanticContract::ContractError) do
        IOSContrastSemanticContract.check!(report)
      end
    end
  end

  private

  def valid_report
    assets = Array.new(48) do |index|
      {
        "id" => format("asset-%02d", index + 1),
        "source_sha256" => "f" * 64,
        "negative" => measurement(0.001, 0.001),
        "neutral" => measurement(0.002, 0.002),
        "positive" => measurement(0.010, 0.008),
        "comparison" => {
          "negative_to_neutral" => { "mean_absolute_error" => 5.0 / 255.0 },
          "neutral_to_positive" => { "mean_absolute_error" => 5.0 / 255.0 },
        },
      }
    end
    {
      "schema" => 1,
      "engineering_only" => true,
      "observation_only" => true,
      "thresholds_frozen" => false,
      "platform" => "ios",
      "parameter" => "contrast",
      "profiles" => %w[contrast-negative neutral contrast-positive],
      "sample_max_edge" => 512,
      "manifest_sha256" => "a" * 64,
      "analyzer_source_sha256" => "b" * 64,
      "comparator_source_sha256" => "c" * 64,
      "runner_source_sha256" => "d" * 64,
      "asset_count" => 48,
      "assets" => assets,
    }
  end

  def measurement(black_clip, white_clip)
    {
      "black_clip_ratio" => black_clip,
      "white_clip_ratio" => white_clip,
    }
  end
end
