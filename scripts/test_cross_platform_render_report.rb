#!/usr/bin/env ruby

require "minitest/autorun"
require "tmpdir"
require_relative "support/cross_platform_render_comparison"

class CrossPlatformRenderReportTest < Minitest::Test
  def test_indexes_exactly_the_declared_asset_identities
    report = {
      "asset_count" => 2,
      "assets" => [
        { "id" => "portrait-001" },
        { "id" => "portrait-002" },
      ],
    }
    indexed = CrossPlatformRenderComparison.index_assets!(report, platform: "ios")
    assert_equal(%w[portrait-001 portrait-002], indexed.keys)

    report["assets"] <<({ "id" => "portrait-002" })
    assert_raises(CrossPlatformRenderComparison::ContractError) do
      CrossPlatformRenderComparison.index_assets!(report, platform: "ios")
    end
  end

  def test_summarizes_observed_values_without_inventing_a_pass_threshold
    summary = CrossPlatformRenderComparison.summarize([0.01, 0.02, 0.03, 0.8])
    assert_equal(0.01, summary.fetch("minimum"))
    assert_equal(0.02, summary.fetch("p50"))
    assert_equal(0.8, summary.fetch("p95"))
    assert_equal(0.8, summary.fetch("maximum"))
  end

  def test_rejects_invalid_metric_ranges
    valid = {
      "sample_width" => 512,
      "sample_height" => 384,
      "sample_pixels" => 196_608,
      "mean_absolute_error" => 0.01,
      "root_mean_square_error" => 0.02,
      "maximum_absolute_error" => 0.3,
      "mean_absolute_luma_error" => 0.01,
      "mean_absolute_rgb" => [0.01, 0.01, 0.01],
      "root_mean_square_rgb" => [0.02, 0.02, 0.02],
      "mean_rgb_bias" => [-0.01, 0.0, 0.01],
      "exact_pixel_ratio" => 0.4,
      "pixel_ratio_over_4_code_values" => 0.01,
      "pixel_ratio_over_8_code_values" => 0.001,
      "p95_max_channel_error" => 0.05,
      "p99_max_channel_error" => 0.1,
      "psnr_db" => 34.0,
    }
    CrossPlatformRenderComparison.validate_metric!(valid, asset_id: "portrait-001")
    assert_raises(CrossPlatformRenderComparison::ContractError) do
      CrossPlatformRenderComparison.validate_metric!(
        valid.merge("mean_absolute_error" => 1.1),
        asset_id: "portrait-001",
      )
    end
  end

  def test_rejects_a_quality_subdirectory_symlink_that_escapes
    Dir.mktmpdir("cross-platform-report-test-") do |root|
      quality_root = File.join(root, ".quality")
      outside = File.join(root, "outside")
      Dir.mkdir(quality_root)
      Dir.mkdir(outside)
      File.symlink(outside, File.join(quality_root, "escape"))

      assert_raises(CrossPlatformRenderComparison::ContractError) do
        CrossPlatformRenderComparison.validate_output_ancestry!(
          File.join(quality_root, "escape", "report"),
          repo_root: root,
        )
      end
      assert_raises(CrossPlatformRenderComparison::ContractError) do
        CrossPlatformRenderComparison.validated_quality_directory(
          File.join(quality_root, "escape"),
          repo_root: root,
        )
      end
    end
  end
end
