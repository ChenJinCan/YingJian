#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/group_consistency_corpus"

class GroupConsistencyCorpusTest < Minitest::Test
  def test_accepts_the_layered_group_contract
    GroupConsistencyCorpus.validate_result!(asset_id: "group-01-1", result: valid_result)
  end

  def test_rejects_missing_shared_style_and_wrong_adaptive_direction
    invisible = valid_result
    invisible["shared_difference"]["p95_difference"] = 0
    assert_raises(GroupConsistencyCorpus::ContractError) do
      GroupConsistencyCorpus.validate_result!(asset_id: "group-01-1", result: invisible)
    end

    wrong = valid_result(source_luma: 0.2, adaptive_luma: 0.19, adaptive_exposure: 0.15)
    assert_raises(GroupConsistencyCorpus::ContractError) do
      GroupConsistencyCorpus.validate_result!(asset_id: "group-01-1", result: wrong)
    end
  end

  def test_requires_six_complete_groups_and_material_adaptive_improvement
    reports = reports_with_two_improved_groups
    GroupConsistencyCorpus.validate_corpus!(reports)
    reports.each do |report|
      report["result"]["adaptive"]["mean_luma"] =
        report["result"]["source"]["mean_luma"]
    end
    assert_raises(GroupConsistencyCorpus::ContractError) do
      GroupConsistencyCorpus.validate_corpus!(reports)
    end
  end

  private

  def valid_result(source_luma: 0.5, shared_luma: 0.505, adaptive_luma: 0.505,
                   adaptive_exposure: 0.0)
    base = {
      "mean_luma" => source_luma,
      "red_blue_delta" => 0.0,
      "mean_chroma" => 0.2,
      "black_clip_ratio" => 0.001,
      "white_clip_ratio" => 0.001,
    }
    {
      "schema" => 1, "pipeline_schema" => 10, "max_edge" => 1_024,
      "width" => 768, "height" => 1_024, "zero_is_exact" => true,
      "shared_intensity" => 0.8, "shared_filter" => "cinematic",
      "shared_filter_strength" => 36.0,
      "shared_hsl_blue_saturation" => -9.6,
      "adaptive_exposure" => adaptive_exposure, "adaptive_warmth" => 0.0,
      "source" => base,
      "shared" => base.merge("mean_luma" => shared_luma),
      "adaptive" => base.merge("mean_luma" => adaptive_luma),
      "shared_difference" => {"mean_difference" => 0.01, "p95_difference" => 0.02},
      "adaptive_difference" => adaptive_exposure.zero? ?
        {"mean_difference" => 0.0, "p95_difference" => 0.0} :
        {"mean_difference" => 0.01, "p95_difference" => 0.02},
      "override_difference" => {"mean_difference" => 0.01, "p95_difference" => 0.02},
    }
  end

  def reports_with_two_improved_groups
    6.times.flat_map do |group_index|
      4.times.map do |member_index|
        source_luma = 0.3 + member_index * 0.03
        adaptive_luma = if group_index < 2 && member_index.zero?
          source_luma + 0.015
        else
          source_luma
        end
        {
          "id" => "group-#{group_index + 1}-#{member_index + 1}",
          "group_id" => "group-#{group_index + 1}",
          "result" => valid_result(
            source_luma: source_luma,
            shared_luma: source_luma,
            adaptive_luma: adaptive_luma
          ),
        }
      end
    end
  end
end
