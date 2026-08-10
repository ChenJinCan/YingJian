#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/composition_corpus"

class CompositionCorpusTest < Minitest::Test
  def test_selects_one_unique_asset_per_priority_tag
    assets = CompositionCorpus::PRIORITY_TAGS.each_with_index.map do |tag, index|
      { "id" => "asset-#{index}", "tags" => [tag] }
    end
    assert_equal(12, CompositionCorpus.select_assets(assets).length)
  end

  def test_accepts_safe_reversible_geometry
    CompositionCorpus.validate_result!(asset_id: "asset-1", result: valid_result)
    reports = 12.times.map { |index| { "id" => "asset-#{index}" } }
    CompositionCorpus.validate_corpus!(reports)
  end

  def test_rejects_wrong_crop_mapping_and_excessive_perspective_fill
    mapping = valid_result
    mapping["crop"]["mapping_difference"] = 0.1
    assert_raises(CompositionCorpus::ContractError) do
      CompositionCorpus.validate_result!(asset_id: "asset-1", result: mapping)
    end

    fill = valid_result
    fill["directional"]["perspective_vertical_positive"]["white_ratio_delta"] = 0.3
    assert_raises(CompositionCorpus::ContractError) do
      CompositionCorpus.validate_result!(asset_id: "asset-1", result: fill)
    end
  end

  private

  def valid_result
    directional = {}
    CompositionCorpus::DIRECTIONS.each do |name|
      directional[name] = {
        "width" => 1_024,
        "height" => 768,
        "effect_difference" => 0.1,
        "white_ratio_delta" => 0.1,
      }
    end
    {
      "schema" => 1,
      "pipeline_schema" => 10,
      "max_edge" => 1_024,
      "width" => 1_024,
      "height" => 768,
      "zero_is_exact" => true,
      "flip_horizontal" => { "effect_difference" => 0.1, "round_trip_difference" => 0 },
      "flip_vertical" => { "effect_difference" => 0.1, "round_trip_difference" => 0 },
      "crop" => {
        "width" => 778, "height" => 645,
        "expected_width" => 778, "expected_height" => 645,
        "mapping_difference" => 0,
      },
      "quarter_turn" => { "width" => 768, "height" => 1_024, "cycle_difference" => 0.001 },
      "directional" => directional,
      "combined" => { "width" => 584, "height" => 819, "white_ratio" => 0.02 },
    }
  end
end
