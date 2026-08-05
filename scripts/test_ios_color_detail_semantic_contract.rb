#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/ios_color_detail_semantic_contract"

class IOSColorDetailSemanticContractTest < Minitest::Test
  def test_accepts_saturation_tint_and_clarity_contracts
    result = IOSColorDetailSemanticContract.check!(
      saturation_report,
      tint_report,
      clarity_report,
    )

    assert_equal 48, result.fetch("asset_count")
    assert_empty result.fetch("violations")
  end

  def test_accepts_saturation_noop_for_achromatic_input
    report = saturation_report
    asset = report.fetch("assets").last
    %w[negative neutral positive].each { |level| asset.fetch(level)["mean_chroma"] = 0.0 }
    asset.fetch("comparison").each_value { |comparison| comparison["mean_absolute_error"] = 0.0 }

    result = IOSColorDetailSemanticContract.check!(report, tint_report, clarity_report)

    assert_empty result.fetch("violations")
  end

  def test_reports_parameter_specific_direction_strength_and_safety_failures
    saturation = saturation_report
    tint = tint_report
    clarity = clarity_report
    saturation.fetch("assets").first.fetch("positive")["mean_chroma"] = 0.121
    tint.fetch("assets").first.fetch("positive")["mean_rgb"] = [0.402, 0.4, 0.402]
    clarity.fetch("assets").first.fetch("positive")["mean_edge_energy"] = 0.019
    clarity.fetch("assets").first
      .dig("comparison", "neutral_to_positive")["p95_max_channel_error"] = 0.0
    clarity.fetch("assets").first.fetch("positive")["black_clip_ratio"] = 0.01

    contracts = IOSColorDetailSemanticContract.check!(saturation, tint, clarity)
      .fetch("violations")
      .map { |item| item.fetch("contract") }

    assert_includes contracts, "minimum_chroma_step"
    assert_includes contracts, "minimum_tint_index_step"
    assert_includes contracts, "minimum_edge_energy_step"
    assert_includes contracts, "minimum_local_pixel_difference"
    assert_includes contracts, "maximum_new_black_clip_ratio"
  end

  def test_rejects_wrong_identity_and_mismatched_corpus
    assert_raises(IOSColorDetailSemanticContract::ContractError) do
      IOSColorDetailSemanticContract.check!(tint_report, saturation_report, clarity_report)
    end
    tint = tint_report
    tint["manifest_sha256"] = "e" * 64
    assert_raises(IOSColorDetailSemanticContract::ContractError) do
      IOSColorDetailSemanticContract.check!(saturation_report, tint, clarity_report)
    end
  end

  private

  def saturation_report
    report_for("saturation") do
      [
        measurement(chroma: 0.10),
        measurement(chroma: 0.12),
        measurement(chroma: 0.14),
      ]
    end
  end

  def tint_report
    report_for("tint") do
      [
        measurement(rgb: [0.39, 0.41, 0.39]),
        measurement(rgb: [0.4, 0.4, 0.4]),
        measurement(rgb: [0.41, 0.39, 0.41]),
      ]
    end
  end

  def clarity_report
    report_for("clarity", p95: 1.0 / 255.0) do
      [
        measurement(edge: 0.019),
        measurement(edge: 0.020),
        measurement(edge: 0.021),
      ]
    end
  end

  def report_for(parameter, p95: 0.01)
    assets = Array.new(48) do |index|
      negative, neutral, positive = yield
      {
        "id" => format("asset-%02d", index + 1),
        "source_sha256" => "f" * 64,
        "negative" => negative,
        "neutral" => neutral,
        "positive" => positive,
        "comparison" => {
          "negative_to_neutral" => comparison(p95),
          "neutral_to_positive" => comparison(p95),
        },
      }
    end
    {
      "schema" => 1,
      "engineering_only" => true,
      "observation_only" => true,
      "thresholds_frozen" => false,
      "platform" => "ios",
      "parameter" => parameter,
      "profiles" => ["#{parameter}-negative", "neutral", "#{parameter}-positive"],
      "sample_max_edge" => 512,
      "manifest_sha256" => "a" * 64,
      "analyzer_source_sha256" => "b" * 64,
      "comparator_source_sha256" => "c" * 64,
      "runner_source_sha256" => "d" * 64,
      "asset_count" => 48,
      "assets" => assets,
    }
  end

  def measurement(chroma: 0.1, rgb: [0.4, 0.4, 0.4], edge: 0.02)
    {
      "mean_chroma" => chroma,
      "mean_rgb" => rgb,
      "mean_luma" => 0.4,
      "mean_edge_energy" => edge,
      "black_clip_ratio" => 0.001,
      "white_clip_ratio" => 0.001,
    }
  end

  def comparison(p95)
    { "mean_absolute_error" => 0.01, "p95_max_channel_error" => p95 }
  end
end
