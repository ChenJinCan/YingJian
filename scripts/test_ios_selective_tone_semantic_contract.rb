#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/ios_selective_tone_semantic_contract"

class IOSSelectiveToneSemanticContractTest < Minitest::Test
  def test_accepts_visible_ordered_highlights_and_shadows_with_bounded_clipping
    result = IOSSelectiveToneSemanticContract.check!(
      report_for("highlights"),
      report_for("shadows"),
    )

    assert_equal 48, result.fetch("asset_count")
    assert_empty result.fetch("violations")
  end

  def test_reports_weak_steps_and_parameter_specific_clipping
    highlights = report_for("highlights")
    shadows = report_for("shadows")
    highlights.fetch("assets").first.fetch("positive")["mean_luma"] = 0.401
    highlights.fetch("assets").first.fetch("positive")["white_clip_ratio"] = 0.02
    shadows.fetch("assets").first.fetch("negative")["black_clip_ratio"] = 0.02
    shadows.fetch("assets").first
      .dig("comparison", "negative_to_neutral")["mean_absolute_error"] = 0.003

    contracts = IOSSelectiveToneSemanticContract.check!(highlights, shadows)
      .fetch("violations")
      .map { |item| item.fetch("contract") }

    assert_includes contracts, "minimum_mean_luma_step"
    assert_includes contracts, "minimum_visible_difference"
    assert_includes contracts, "maximum_new_white_clip_ratio"
    assert_includes contracts, "maximum_new_black_clip_ratio"
  end

  def test_rejects_wrong_identity_mismatched_corpus_and_duplicate_assets
    assert_raises(IOSSelectiveToneSemanticContract::ContractError) do
      IOSSelectiveToneSemanticContract.check!(
        report_for("shadows"),
        report_for("highlights"),
      )
    end
    shadows = report_for("shadows")
    shadows["manifest_sha256"] = "e" * 64
    assert_raises(IOSSelectiveToneSemanticContract::ContractError) do
      IOSSelectiveToneSemanticContract.check!(report_for("highlights"), shadows)
    end
    highlights = report_for("highlights")
    highlights.fetch("assets")[1]["id"] = "asset-01"
    assert_raises(IOSSelectiveToneSemanticContract::ContractError) do
      IOSSelectiveToneSemanticContract.check!(highlights, report_for("shadows"))
    end
  end

  private

  def report_for(parameter)
    assets = Array.new(48) do |index|
      {
        "id" => format("asset-%02d", index + 1),
        "source_sha256" => "f" * 64,
        "negative" => measurement(0.39),
        "neutral" => measurement(0.4),
        "positive" => measurement(0.41),
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

  def measurement(luma)
    {
      "mean_luma" => luma,
      "black_clip_ratio" => 0.001,
      "white_clip_ratio" => 0.001,
    }
  end
end
