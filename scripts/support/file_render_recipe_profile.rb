# frozen_string_literal: true

require "json"

module FileRenderRecipeProfile
  class ContractError < StandardError; end

  PROFILE_VALUES = {
    "exposure" => ["exposureEv", 0.5],
    "contrast" => ["contrast", 0.35],
    "warmth" => ["warmth", 0.4],
    "highlights" => ["highlights", 0.4],
    "shadows" => ["shadows", 0.4],
    "tint" => ["tint", 0.4],
    "saturation" => ["saturation", 0.35],
    "clarity" => ["clarity", 0.25],
  }.freeze

  module_function

  def ids
    ["neutral"] + PROFILE_VALUES.keys.flat_map do |name|
      ["#{name}-negative", "#{name}-positive"]
    end
  end

  def fetch(profile_id)
    return deep_copy(base_recipe) if profile_id == "neutral"
    match = /\A([a-z]+)-(negative|positive)\z/.match(profile_id.to_s)
    definition = PROFILE_VALUES[match[1]] if match
    raise ContractError, "unknown file-render recipe profile: #{profile_id}" unless definition

    adjustment, magnitude = definition
    recipe = base_recipe
    recipe.fetch("adjustments")[adjustment] = match[2] == "negative" ? -magnitude : magnitude
    deep_copy(recipe)
  end

  def base_recipe
    {
      "schemaVersion" => 2,
      "workingColorSpace" => "srgb",
      "adjustments" => {
        "exposureEv" => 0.0,
        "highlights" => 0.0,
        "shadows" => 0.0,
        "contrast" => 0.0,
        "warmth" => 0.0,
        "tint" => 0.0,
        "saturation" => 0.0,
        "clarity" => 0.0,
      },
      "geometry" => {
        "normalizedCrop" => [0.0, 0.0, 1.0, 1.0],
        "quarterTurns" => 0,
        "straightenDegrees" => 0.0,
      },
      "portrait" => {
        "recipeVersion" => 1,
        "strength" => 0.0,
      },
    }
  end
  private_class_method :base_recipe

  def deep_copy(value)
    JSON.parse(JSON.generate(value))
  end
  private_class_method :deep_copy
end
