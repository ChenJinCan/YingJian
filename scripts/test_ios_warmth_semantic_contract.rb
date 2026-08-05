#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/ios_warmth_semantic_contract"

class IOSWarmthSemanticContractTest < Minitest::Test
  def test_accepts_visible_ordered_warmth_with_stable_luma_and_clipping
    result = IOSWarmthSemanticContract.check!(valid_report)

    assert_equal 48, result.fetch("asset_count")
    assert_empty result.fetch("violations")
  end

  def test_reports_weak_direction_luma_drift_and_clipping
    report = valid_report
    first = report.fetch("assets").first
    first.fetch("positive")["mean_rgb"] = [0.403, 0.4, 0.397]
    first.fetch("positive")["mean_luma"] = 0.42
    first.fetch("positive")["white_clip_ratio"] = 0.012
    first.dig("comparison", "neutral_to_positive")["mean_absolute_error"] = 0.003

    contracts = IOSWarmthSemanticContract.check!(report)
      .fetch("violations")
      .map { |item| item.fetch("contract") }

    assert_includes contracts, "minimum_warmth_index_step"
    assert_includes contracts, "minimum_visible_difference"
    assert_includes contracts, "maximum_mean_luma_drift"
    assert_includes contracts, "maximum_new_white_clip_ratio"
  end

  def test_rejects_wrong_identity_duplicate_assets_and_missing_measurements
    invalid_reports = [
      valid_report.merge("platform" => "android"),
      valid_report.merge("parameter" => "contrast"),
      valid_report.merge("asset_count" => 47),
    ]
    duplicate = valid_report
    duplicate.fetch("assets")[1]["id"] = "asset-01"
    invalid_reports << duplicate
    missing_rgb = valid_report
    missing_rgb.fetch("assets").first.fetch("neutral").delete("mean_rgb")
    invalid_reports << missing_rgb

    invalid_reports.each do |report|
      assert_raises(IOSWarmthSemanticContract::ContractError) do
        IOSWarmthSemanticContract.check!(report)
      end
    end
  end

  private

  def valid_report
    assets = Array.new(48) do |index|
      {
        "id" => format("asset-%02d", index + 1),
        "source_sha256" => "f" * 64,
        "negative" => measurement([0.39, 0.4, 0.41]),
        "neutral" => measurement([0.4, 0.4, 0.4]),
        "positive" => measurement([0.41, 0.4, 0.39]),
        "comparison" => {
          "negative_to_neutral" => { "mean_absolute_error" => 0.01 },
          "neutral_to_positive" => { "mean_absolute_error" => 0.01 },
        },
      }
    end
    {
      "schema" => 1,
      "engineering_only" => true,
      "observation_only" => true,
      "thresholds_frozen" => false,
      "platform" => "ios",
      "parameter" => "warmth",
      "profiles" => %w[warmth-negative neutral warmth-positive],
      "sample_max_edge" => 512,
      "manifest_sha256" => "a" * 64,
      "analyzer_source_sha256" => "b" * 64,
      "comparator_source_sha256" => "c" * 64,
      "runner_source_sha256" => "d" * 64,
      "asset_count" => 48,
      "assets" => assets,
    }
  end

  def measurement(rgb)
    {
      "mean_rgb" => rgb,
      "mean_luma" => 0.4,
      "black_clip_ratio" => 0.001,
      "white_clip_ratio" => 0.001,
    }
  end
end
