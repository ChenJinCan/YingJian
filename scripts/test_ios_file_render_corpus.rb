#!/usr/bin/env ruby

require "minitest/autorun"
require "tmpdir"
require_relative "support/ios_file_render_corpus"

class IOSFileRenderCorpusTest < Minitest::Test
  def test_normalizes_dimensions_for_exif_orientation
    assert_equal([4_000, 3_000], IOSFileRenderCorpus.expected_dimensions(
      "width" => 4_000,
      "height" => 3_000,
      "orientation" => 1,
    ))
    assert_equal([3_000, 4_000], IOSFileRenderCorpus.expected_dimensions(
      "width" => 4_000,
      "height" => 3_000,
      "orientation" => 6,
    ))
  end

  def test_rejects_outputs_outside_the_private_quality_root
    assert_equal(
      "/repo/.quality/file-render-run",
      IOSFileRenderCorpus.validated_output_root(
        "/repo/.quality/file-render-run",
        repo_root: "/repo",
      ),
    )
    assert_raises(IOSFileRenderCorpus::ContractError) do
      IOSFileRenderCorpus.validated_output_root(
        "/repo/build/file-render-run",
        repo_root: "/repo",
      )
    end
  end

  def test_rejects_a_quality_subdirectory_symlink_that_escapes
    Dir.mktmpdir("ios-file-render-test-") do |root|
      quality_root = File.join(root, ".quality")
      outside = File.join(root, "outside")
      Dir.mkdir(quality_root)
      Dir.mkdir(outside)
      File.symlink(outside, File.join(quality_root, "escape"))

      assert_raises(IOSFileRenderCorpus::ContractError) do
        IOSFileRenderCorpus.validate_output_ancestry!(
          File.join(quality_root, "escape", "run-1"),
          repo_root: root,
        )
      end
    end
  end

  def test_requires_jpeg_srgb_full_size_and_sanitized_metadata
    IOSFileRenderCorpus.validate_render!(
      asset_id: "portrait-001",
      expected_dimensions: [4_000, 3_000],
      result: {
        "width" => 4_000,
        "height" => 3_000,
        "format" => "jpeg",
        "color_space" => "sRGB IEC61966-2.1",
        "orientation" => 1,
        "has_gps" => false,
        "has_device_identity" => false,
      },
    )
  end

  def test_rejects_private_metadata_or_dimension_changes
    base = {
      "width" => 4_000,
      "height" => 3_000,
      "format" => "jpeg",
      "color_space" => "sRGB",
      "orientation" => 1,
      "has_gps" => false,
      "has_device_identity" => false,
    }
    error = assert_raises(IOSFileRenderCorpus::ContractError) do
      IOSFileRenderCorpus.validate_render!(
        asset_id: "portrait-001",
        expected_dimensions: [4_000, 3_000],
        result: base.merge("has_gps" => true),
      )
    end
    assert_includes(error.message, "private metadata")

    assert_raises(IOSFileRenderCorpus::ContractError) do
      IOSFileRenderCorpus.validate_render!(
        asset_id: "portrait-001",
        expected_dimensions: [4_000, 3_000],
        result: base.merge("width" => 3_999),
      )
    end
  end
end
