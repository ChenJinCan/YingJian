#!/usr/bin/env ruby

require "minitest/autorun"
require "tmpdir"
require_relative "support/android_file_render_corpus"

class AndroidFileRenderCorpusTest < Minitest::Test
  def test_validates_complete_production_export_result
    AndroidFileRenderCorpus.validate_result!(
      asset_id: "portrait-001",
      expected_dimensions: [3_000, 4_000],
      expected_source_sha256: "a" * 64,
      result: {
        "source_sha256_before" => "a" * 64,
        "source_sha256_after" => "a" * 64,
        "output_sha256" => "b" * 64,
        "width" => 3_000,
        "height" => 4_000,
        "format" => "jpeg",
        "is_srgb" => true,
        "orientation" => 1,
        "has_gps" => false,
        "has_device_identity" => false,
      },
    )
  end

  def test_rejects_source_mutation_and_private_metadata
    result = {
      "source_sha256_before" => "a" * 64,
      "source_sha256_after" => "c" * 64,
      "output_sha256" => "b" * 64,
      "width" => 3_000,
      "height" => 4_000,
      "format" => "jpeg",
      "is_srgb" => true,
      "orientation" => 1,
      "has_gps" => false,
      "has_device_identity" => false,
    }
    error = assert_raises(AndroidFileRenderCorpus::ContractError) do
      AndroidFileRenderCorpus.validate_result!(
        asset_id: "portrait-001",
        expected_dimensions: [3_000, 4_000],
        expected_source_sha256: "a" * 64,
        result: result,
      )
    end
    assert_includes(error.message, "source hash")

    result["source_sha256_after"] = "a" * 64
    result["has_device_identity"] = true
    assert_raises(AndroidFileRenderCorpus::ContractError) do
      AndroidFileRenderCorpus.validate_result!(
        asset_id: "portrait-001",
        expected_dimensions: [3_000, 4_000],
        expected_source_sha256: "a" * 64,
        result: result,
      )
    end
  end

  def test_rejects_missing_or_duplicate_asset_results
    expected = %w[portrait-001 portrait-002]
    assert_raises(AndroidFileRenderCorpus::ContractError) do
      AndroidFileRenderCorpus.index_results!(
        [{ "id" => "portrait-001" }],
        expected_ids: expected,
      )
    end
    assert_raises(AndroidFileRenderCorpus::ContractError) do
      AndroidFileRenderCorpus.index_results!(
        [{ "id" => "portrait-001" }, { "id" => "portrait-001" }],
        expected_ids: expected,
      )
    end
  end

  def test_rejects_a_quality_subdirectory_symlink_that_escapes
    Dir.mktmpdir("android-file-render-test-") do |root|
      quality_root = File.join(root, ".quality")
      outside = File.join(root, "outside")
      Dir.mkdir(quality_root)
      Dir.mkdir(outside)
      File.symlink(outside, File.join(quality_root, "escape"))

      assert_raises(AndroidFileRenderCorpus::ContractError) do
        AndroidFileRenderCorpus.validate_output_ancestry!(
          File.join(quality_root, "escape", "run-1"),
          repo_root: root,
        )
      end
    end
  end
end
