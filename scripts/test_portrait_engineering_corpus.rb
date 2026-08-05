#!/usr/bin/env ruby

require "minitest/autorun"
require "tmpdir"
require_relative "support/portrait_engineering_corpus"

class PortraitEngineeringCorpusTest < Minitest::Test
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
        "off" => "a" * 64,
        "default" => "a" * 64,
        "high_safe" => "a" * 64,
      ),
    )
    assert_equal(
      "applied",
      PortraitEngineeringCorpus.classify_hashes(
        "off" => "a" * 64,
        "default" => "b" * 64,
        "high_safe" => "c" * 64,
      ),
    )
    error = assert_raises(PortraitEngineeringCorpus::ContractError) do
      PortraitEngineeringCorpus.classify_hashes(
        "off" => "a" * 64,
        "default" => "b" * 64,
        "high_safe" => "b" * 64,
      )
    end
    assert_includes(error.message, "partially distinct")
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
      classification: "preserved",
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
        classification: "applied",
      )
    end
    assert_includes(error.message, "must be safely preserved")
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
end
