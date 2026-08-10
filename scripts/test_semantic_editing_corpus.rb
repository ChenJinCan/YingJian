#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/semantic_editing_corpus"

class SemanticEditingCorpusTest < Minitest::Test
  def test_accepts_exact_localized_semantic_results
    SemanticEditingCorpus.validate_result!(asset_id: "portrait-001", result: valid_result)
  end

  def test_rejects_nonexact_empty_masks_and_protection_leaks
    nonexact = valid_result.merge("empty_local_mask_is_exact" => false)
    assert_raises(SemanticEditingCorpus::ContractError) do
      SemanticEditingCorpus.validate_result!(asset_id: "portrait-001", result: nonexact)
    end

    leaking = valid_result
    leaking["measurements"]["background_white"]["protected_mean_difference"] = 0.01
    assert_raises(SemanticEditingCorpus::ContractError) do
      SemanticEditingCorpus.validate_result!(asset_id: "portrait-001", result: leaking)
    end
  end

  def test_rejects_weak_core_operations_and_corpus_coverage
    weak = valid_result
    weak["measurements"]["local_adjustment"]["target_p95_difference"] = 0
    assert_raises(SemanticEditingCorpus::ContractError) do
      SemanticEditingCorpus.validate_result!(asset_id: "portrait-001", result: weak)
    end

    reports = 12.times.map do |index|
      result = valid_result
      result["measurements"]["background_blur"]["target_p95_difference"] = 0 if index < 4
      {"id" => "asset-#{index}", "result" => result}
    end
    assert_raises(SemanticEditingCorpus::ContractError) do
      SemanticEditingCorpus.validate_corpus!(reports)
    end
  end

  private

  def valid_result
    metrics = SemanticEditingCorpus::OPERATIONS.to_h do |name|
      [name, {
        "target_mean_difference" => 0.02,
        "target_p95_difference" => 0.04,
        "protected_mean_difference" => 0.0001,
      }]
    end
    {
      "schema" => 1,
      "pipeline_schema" => 10,
      "max_edge" => 1_024,
      "width" => 768,
      "height" => 1_024,
      "zero_is_exact" => true,
      "empty_local_mask_is_exact" => true,
      "empty_erase_mask_is_exact" => true,
      "measurements" => metrics,
    }
  end
end
