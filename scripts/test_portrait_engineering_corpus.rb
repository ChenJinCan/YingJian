#!/usr/bin/env ruby

require "minitest/autorun"
require "json"
require "open3"
require "tmpdir"
require_relative "support/portrait_engineering_corpus"

class PortraitEngineeringCorpusTest < Minitest::Test
  def difference_metrics(mean: 0, changed: 0, p99: 0)
    {
      "mean_absolute_difference" => mean,
      "changed_pixel_fraction_at_2" => changed,
      "p99_max_channel_difference" => p99,
    }
  end

  def effect_metrics(
    off: difference_metrics,
    default: difference_metrics(mean: 0.4, changed: 0.06, p99: 14),
    high_safe: difference_metrics(mean: 0.7, changed: 0.08, p99: 20),
    cosine: 0.98,
    retention: 0.97
  )
    {
      "metric_version" => "whole-frame-srgb-rgba8-v1",
      "proxy_max_edge" => 512,
      "off" => off,
      "default" => default,
      "high_safe" => high_safe,
      "progression" => {
        "directional_cosine_similarity" => cosine,
        "default_changed_pixels_retained_fraction" => retention,
      },
    }
  end

  def portrait_manifest(assets)
    {
      "status" => "ready",
      "portrait_required_assets" => 48,
      "portrait_minimum_single_assets" => 36,
      "portrait_roles" => %w[portrait_single portrait_multi no_face],
      "assets" => assets,
    }
  end

  def test_requires_the_frozen_portrait_quality_matrix
    assets = Array.new(36) do |index|
      {
        "id" => format("portrait-%03d", index + 1),
        "tags" => ["portrait_single"],
      }
    end
    assets.concat(
      Array.new(8) do |index|
        {
          "id" => format("no-face-%03d", index + 1),
          "tags" => ["no_face"],
        }
      end,
    )
    assets.concat(
      Array.new(4) do |index|
        {
          "id" => format("portrait-multi-%03d", index + 1),
          "tags" => ["portrait_multi"],
        }
      end,
    )

    PortraitEngineeringCorpus.validate_manifest!(portrait_manifest(assets))

    supplemental = {
      "id" => "blemish-supplemental-001",
      "tags" => [
        "portrait_single",
        PortraitEngineeringCorpus::SUPPLEMENTAL_TAG,
      ],
    }
    manifest_with_supplement = portrait_manifest(assets + [supplemental])
    PortraitEngineeringCorpus.validate_manifest!(manifest_with_supplement)
    assert_equal(
      48,
      PortraitEngineeringCorpus.engineering_assets(manifest_with_supplement).length,
    )

    too_few_portraits = assets.map(&:dup)
    too_few_portraits[35] = {
      "id" => "no-face-009",
      "tags" => ["no_face"],
    }
    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_manifest!(portrait_manifest(too_few_portraits))
    end
    assert_includes(error.message, "at least 36 portrait_single")
  end

  def test_rejects_ambiguous_or_missing_portrait_safety_roles
    assets = Array.new(48) do |index|
      {
        "id" => format("portrait-%03d", index + 1),
        "tags" => ["portrait_single"],
      }
    end
    assets[36] = {
      "id" => "ambiguous-001",
      "tags" => ["portrait_single", "no_face"],
    }

    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_manifest!(portrait_manifest(assets))
    end
    assert_includes(error.message, "exactly one portrait role")
  end

  def test_rejects_manifest_declarations_that_drift_from_the_frozen_matrix
    manifest = portrait_manifest([])
    manifest["portrait_minimum_single_assets"] = 35

    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_manifest!(manifest)
    end
    assert_includes(error.message, "portrait_minimum_single_assets must equal 36")
  end

  def test_classifies_only_complete_effect_or_complete_preservation
    assert_equal(
      "preserved",
      PortraitEngineeringCorpus.classify_hashes(
        "baseline" => "a" * 64,
        "off" => "a" * 64,
        "default" => "a" * 64,
        "high_safe" => "a" * 64,
      ),
    )
    assert_equal(
      "applied",
      PortraitEngineeringCorpus.classify_hashes(
        "baseline" => "a" * 64,
        "off" => "a" * 64,
        "default" => "b" * 64,
        "high_safe" => "c" * 64,
      ),
    )
    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.classify_hashes(
        "baseline" => "a" * 64,
        "off" => "a" * 64,
        "default" => "b" * 64,
        "high_safe" => "b" * 64,
      )
    end
    assert_includes(error.message, "partially distinct")
  end

  def test_rejects_an_off_variant_that_differs_from_the_independent_baseline
    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.classify_hashes(
        "baseline" => "a" * 64,
        "off" => "b" * 64,
        "default" => "c" * 64,
        "high_safe" => "d" * 64,
      )
    end

    assert_includes(error.message, "off must match the independent baseline")
  end

  def test_enforces_safety_expectations_from_corpus_tags
    PortraitEngineeringCorpus.validate_classification!(
      asset_id: "no-face-001",
      tags: ["no_face"],
      classification: "preserved",
    )
    PortraitEngineeringCorpus.validate_classification!(
      asset_id: "portrait-multi-001",
      tags: ["portrait_multi"],
      classification: "applied",
    )
    PortraitEngineeringCorpus.validate_classification!(
      asset_id: "portrait-001",
      tags: ["portrait_single"],
      classification: "applied",
    )

    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_classification!(
        asset_id: "portrait-multi-001",
        tags: ["portrait_multi"],
        classification: "preserved",
      )
    end
    assert_includes(error.message, "must apply the portrait candidate")
  end

  def test_accepts_a_visible_bounded_and_monotonic_applied_effect
    PortraitEngineeringCorpus.validate_effect_metrics!(
      asset_id: "portrait-001",
      classification: "applied",
      metrics: effect_metrics,
    )
  end

  def test_rejects_an_applied_effect_that_is_only_hash_distinct
    metrics = effect_metrics(
      default: difference_metrics(mean: 0.01, changed: 0.001, p99: 1),
      high_safe: difference_metrics(mean: 0.03, changed: 0.003, p99: 2),
    )

    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_effect_metrics!(
        asset_id: "portrait-001",
        classification: "applied",
        metrics: metrics,
      )
    end

    assert_includes(error.message, "default effect is below the engineering visibility floor")
  end

  def test_rejects_a_high_safe_effect_that_is_not_stronger_than_default
    metrics = effect_metrics(
      default: difference_metrics(mean: 0.5, changed: 0.08, p99: 16),
      high_safe: difference_metrics(mean: 0.49, changed: 0.07, p99: 15),
    )

    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_effect_metrics!(
        asset_id: "portrait-001",
        classification: "applied",
        metrics: metrics,
      )
    end

    assert_includes(error.message, "high-safe effect must be stronger than default")
  end

  def test_rejects_any_pixel_change_for_a_preserved_negative_input
    metrics = effect_metrics(
      default: difference_metrics(mean: 0.01),
      high_safe: difference_metrics,
      cosine: 1,
      retention: 1,
    )

    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_effect_metrics!(
        asset_id: "no-face-001",
        classification: "preserved",
        metrics: metrics,
      )
    end

    assert_includes(error.message, "preserved input changed pixels")
  end

  def test_accepts_a_preserved_negative_input_with_identity_progression
    PortraitEngineeringCorpus.validate_effect_metrics!(
      asset_id: "no-face-001",
      classification: "preserved",
      metrics: effect_metrics(
        default: difference_metrics,
        high_safe: difference_metrics,
        cosine: 1,
        retention: 1,
      ),
    )
  end

  def test_rejects_an_applied_effect_that_exceeds_the_whole_frame_change_budget
    metrics = effect_metrics(
      default: difference_metrics(mean: 8, changed: 0.8, p99: 120),
      high_safe: difference_metrics(mean: 10, changed: 0.9, p99: 160),
    )

    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_effect_metrics!(
        asset_id: "portrait-001",
        classification: "applied",
        metrics: metrics,
      )
    end

    assert_includes(error.message, "effect exceeds the whole-frame change ceiling")
  end

  def test_rejects_nonzero_off_metrics_against_the_independent_baseline
    metrics = effect_metrics(off: difference_metrics(mean: 0.01))

    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_effect_metrics!(
        asset_id: "portrait-001",
        classification: "applied",
        metrics: metrics,
      )
    end

    assert_includes(error.message, "off differs from the independent baseline")
  end

  def test_rejects_a_strength_progression_that_changes_direction_or_region
    low_direction = effect_metrics(cosine: 0.8)
    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_effect_metrics!(
        asset_id: "portrait-001",
        classification: "applied",
        metrics: low_direction,
      )
    end
    assert_includes(error.message, "effect direction")

    low_retention = effect_metrics(retention: 0.8)
    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validate_effect_metrics!(
        asset_id: "portrait-001",
        classification: "applied",
        metrics: low_retention,
      )
    end
    assert_includes(error.message, "changed-pixel region")
  end

  def test_rejects_outputs_outside_the_private_quality_root
    quality_root = "/repo/.quality"
    assert_equal(
      "/repo/.quality/run-1",
      PortraitEngineeringCorpus.validated_output_root(
        "/repo/.quality/run-1",
        repo_root: "/repo",
      ),
    )
    assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.validated_output_root(
        "/repo/build/run-1",
        repo_root: "/repo",
      )
    end
  end

  def test_rejects_a_quality_subdirectory_symlink_that_escapes
    Dir.mktmpdir("portrait-corpus-test-") do |root|
      quality_root = File.join(root, ".quality")
      outside = File.join(root, "outside")
      Dir.mkdir(quality_root)
      Dir.mkdir(outside)
      File.symlink(outside, File.join(quality_root, "escape"))

      assert_raises(PortraitEngineeringCorpus::ContractError) do
        PortraitEngineeringCorpus.validate_output_ancestry!(
          File.join(quality_root, "escape", "run-1"),
          repo_root: root,
        )
      end
    end
  end

  def test_renderer_reports_zero_effect_metrics_for_a_preserved_input
    repo_root = File.expand_path("..", __dir__)
    Dir.mktmpdir("portrait-metric-renderer-test-") do |directory|
      renderer = File.join(directory, "renderer")
      _stdout, stderr, status = Open3.capture3(
        "/usr/bin/xcrun",
        "swiftc",
        "-parse-as-library",
        File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift"),
        File.join(repo_root, "scripts/support/portrait_engineering_metrics.swift"),
        File.join(repo_root, "scripts/support/render_portrait_engineering_candidate.swift"),
        "-o",
        renderer,
      )
      assert(status.success?, stderr)

      stdout, render_stderr, render_status = Open3.capture3(
        renderer,
        File.join(repo_root, "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png"),
        File.join(directory, "output"),
      )
      assert(render_status.success?, render_stderr)
      metrics = JSON.parse(stdout)

      assert_equal("whole-frame-srgb-rgba8-v1", metrics["metric_version"])
      assert_equal(512, metrics["proxy_max_edge"])
      assert(File.file?(File.join(directory, "output", "baseline.jpg")))
      %w[off default high_safe].each do |variant|
        assert_equal(0, metrics.dig(variant, "mean_absolute_difference"))
        assert_equal(0, metrics.dig(variant, "changed_pixel_fraction_at_2"))
        assert_equal(0, metrics.dig(variant, "p99_max_channel_difference"))
      end
      assert_equal(1, metrics.dig("progression", "directional_cosine_similarity"))
      assert_equal(1, metrics.dig("progression", "default_changed_pixels_retained_fraction"))
    end
  end
end
