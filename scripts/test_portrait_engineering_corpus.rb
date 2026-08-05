#!/usr/bin/env ruby

require "minitest/autorun"
require "tmpdir"
require_relative "support/portrait_engineering_corpus"

class PortraitEngineeringCorpusTest < Minitest::Test
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
