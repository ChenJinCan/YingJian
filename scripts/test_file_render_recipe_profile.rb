#!/usr/bin/env ruby

require "minitest/autorun"
require_relative "support/file_render_recipe_profile"

class FileRenderRecipeProfileTest < Minitest::Test
  def test_exposes_neutral_and_symmetric_non_neutral_profiles
    assert_equal 17, FileRenderRecipeProfile.ids.length
    assert_equal "neutral", FileRenderRecipeProfile.ids.first

    expected_parameters = {
      "exposure" => "exposureEv",
      "contrast" => "contrast",
      "warmth" => "warmth",
      "highlights" => "highlights",
      "shadows" => "shadows",
      "tint" => "tint",
      "saturation" => "saturation",
      "clarity" => "clarity",
    }
    expected_parameters.each do |profile_name, parameter|
      negative = FileRenderRecipeProfile.fetch("#{profile_name}-negative")
      positive = FileRenderRecipeProfile.fetch("#{profile_name}-positive")
      assert_operator negative.dig("adjustments", parameter), :<, 0
      assert_operator positive.dig("adjustments", parameter), :>, 0
      assert_equal(
        negative.dig("adjustments", parameter).abs,
        positive.dig("adjustments", parameter).abs,
      )
    end
  end

  def test_every_profile_is_a_complete_bounded_v2_recipe_with_one_changed_adjustment
    neutral = FileRenderRecipeProfile.fetch("neutral")

    FileRenderRecipeProfile.ids.each do |profile_id|
      recipe = FileRenderRecipeProfile.fetch(profile_id)
      assert_equal 2, recipe.fetch("schemaVersion")
      assert_equal "srgb", recipe.fetch("workingColorSpace")
      assert_equal [0.0, 0.0, 1.0, 1.0], recipe.dig("geometry", "normalizedCrop")
      assert_equal 0.0, recipe.dig("portrait", "strength")
      changed = recipe.fetch("adjustments").count do |name, value|
        value != neutral.fetch("adjustments").fetch(name)
      end
      assert_equal(profile_id == "neutral" ? 0 : 1, changed)
    end
  end

  def test_fetch_returns_a_copy_and_rejects_unknown_profile
    recipe = FileRenderRecipeProfile.fetch("exposure-positive")
    recipe.fetch("adjustments")["exposureEv"] = 2.0

    assert_equal 0.5,
                 FileRenderRecipeProfile.fetch("exposure-positive").dig("adjustments", "exposureEv")
    assert_raises(FileRenderRecipeProfile::ContractError) do
      FileRenderRecipeProfile.fetch("unknown")
    end
  end
end
