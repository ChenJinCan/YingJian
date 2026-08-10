#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/basic_editing_corpus"

class BasicEditingCorpusTest < Minitest::Test
  def test_selects_one_unique_asset_per_priority_tag
    assets = BasicEditingCorpus::PRIORITY_TAGS.each_with_index.map do |tag, index|
      { "id" => "asset-#{index}", "tags" => [tag] }
    end
    assert_equal(12, BasicEditingCorpus.select_assets(assets).length)
  end

  def test_rejects_missing_coverage
    assert_raises(BasicEditingCorpus::ContractError) do
      BasicEditingCorpus.select_assets([{ "id" => "one", "tags" => ["portrait_single"] }])
    end
  end

  def test_accepts_visible_safe_filter_and_hsl_measurements
    result = valid_result
    BasicEditingCorpus.validate_result!(asset_id: "asset-1", result: result)
    reports = 12.times.map { |index| { "id" => "asset-#{index}", "result" => valid_result } }
    BasicEditingCorpus.validate_corpus!(reports)
  end

  def test_rejects_filter_shadow_crushing_and_nonexact_zero
    crushed = valid_result
    crushed["filters"]["cinematic"]["black_clip_ratio"] = 0.2
    assert_raises(BasicEditingCorpus::ContractError) do
      BasicEditingCorpus.validate_result!(asset_id: "asset-1", result: crushed)
    end
    nonexact = valid_result.merge("zero_is_exact" => false)
    assert_raises(BasicEditingCorpus::ContractError) do
      BasicEditingCorpus.validate_result!(asset_id: "asset-1", result: nonexact)
    end
  end

  private

  def valid_result
    neutral = metrics(diff: 0, luma: 0.3, chroma: 0.2)
    {
      "schema" => 1,
      "pipeline_schema" => 10,
      "max_edge" => 1_024,
      "width" => 1_024,
      "height" => 768,
      "zero_is_exact" => true,
      "neutral" => neutral,
      "filters" => BasicEditingCorpus::FILTERS.to_h do |filter|
        [filter, metrics(diff: 0.02, luma: 0.3, chroma: 0.2)]
      end,
      "hsl" => BasicEditingCorpus::CHANNELS.to_h do |channel|
        [
          channel,
          {
            "hue" => metrics(diff: 0.01, luma: 0.3, chroma: 0.2),
            "saturation" => metrics(diff: 0.01, luma: 0.3, chroma: 0.21),
            "lightness" => metrics(diff: 0.01, luma: 0.31, chroma: 0.2),
          },
        ]
      end,
    }
  end

  def metrics(diff:, luma:, chroma:)
    {
      "mean_luma" => luma,
      "mean_chroma" => chroma,
      "mean_absolute_rgb_difference" => diff,
      "black_clip_ratio" => 0.001,
      "white_clip_ratio" => 0.001,
    }
  end
end
