#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/cross_platform_render_tolerance"

class CrossPlatformRenderToleranceTest < Minitest::Test
  def test_accepts_complete_neutral_report_with_code_value_anchored_limits
    report = valid_report

    result = CrossPlatformRenderTolerance.check!(report)

    assert_equal "neutral-export-v1", result.fetch("profile")
    assert_equal 48, result.fetch("asset_count")
    assert_empty result.fetch("violations")
  end

  def test_reports_every_asset_metric_above_its_limit
    report = valid_report
    metric = report.fetch("assets").first.fetch("metric")
    metric["mean_absolute_error"] = 2.0 / 255.0
    metric["pixel_ratio_over_8_code_values"] = 0.006

    result = CrossPlatformRenderTolerance.check!(report)

    assert_equal 2, result.fetch("violations").length
    assert_includes result.fetch("violations"), {
      "asset_id" => "asset-01",
      "metric" => "mean_absolute_error",
      "actual" => 2.0 / 255.0,
      "maximum" => 1.0 / 255.0,
    }
    assert_includes result.fetch("violations"), {
      "asset_id" => "asset-01",
      "metric" => "pixel_ratio_over_8_code_values",
      "actual" => 0.006,
      "maximum" => 0.005,
    }
  end

  def test_rejects_report_that_is_not_the_frozen_neutral_observation_contract
    invalid_reports = [
      valid_report.merge("asset_count" => 47),
      valid_report.merge("sample_max_edge" => 256),
      valid_report.merge("observation_only" => false),
      valid_report.merge("thresholds_frozen" => true),
      valid_report.merge("manifest_sha256" => "not-a-sha"),
      valid_report.merge("assets" => valid_report.fetch("assets")[0...47]),
    ]

    invalid_reports.each do |report|
      assert_raises(CrossPlatformRenderTolerance::ContractError) do
        CrossPlatformRenderTolerance.check!(report)
      end
    end
  end

  def test_rejects_duplicate_assets_and_invalid_metrics
    duplicated = valid_report
    duplicated.fetch("assets")[1]["id"] = "asset-01"
    invalid_metric = valid_report
    invalid_metric.fetch("assets").first.fetch("metric").delete("p99_max_channel_error")

    assert_raises(CrossPlatformRenderTolerance::ContractError) do
      CrossPlatformRenderTolerance.check!(duplicated)
    end
    assert_raises(CrossPlatformRenderTolerance::ContractError) do
      CrossPlatformRenderTolerance.check!(invalid_metric)
    end
  end

  private

  def valid_report
    assets = Array.new(48) do |index|
      {
        "id" => format("asset-%02d", index + 1),
        "metric" => {
          "mean_absolute_error" => 0.0,
          "root_mean_square_error" => 0.0,
          "maximum_absolute_error" => 0.0,
          "mean_absolute_luma_error" => 0.0,
          "maximum_absolute_rgb_bias" => 0.0,
          "p95_max_channel_error" => 0.0,
          "p99_max_channel_error" => 0.0,
          "pixel_ratio_over_4_code_values" => 0.0,
          "pixel_ratio_over_8_code_values" => 0.0,
          "psnr_db" => nil,
        },
      }
    end
    {
      "schema" => 1,
      "engineering_only" => true,
      "observation_only" => true,
      "thresholds_frozen" => false,
      "sample_max_edge" => 512,
      "manifest_sha256" => "a" * 64,
      "ios_report_sha256" => "b" * 64,
      "android_report_sha256" => "c" * 64,
      "comparator_source_sha256" => "d" * 64,
      "runner_source_sha256" => "e" * 64,
      "asset_count" => 48,
      "assets" => assets,
    }
  end
end
