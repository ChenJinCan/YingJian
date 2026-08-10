# frozen_string_literal: true

module CompositionCorpus
  class ContractError < StandardError; end

  PRIORITY_TAGS = %w[
    portrait_single portrait_multi no_face landscape food pet low_light backlit
    mixed_light group_member exif_rotated display_p3
  ].freeze
  DIRECTIONS = %w[
    straighten_positive straighten_negative
    perspective_horizontal_positive perspective_horizontal_negative
    perspective_vertical_positive perspective_vertical_negative
  ].freeze

  module_function

  def select_assets(assets)
    raise ContractError, "assets must be a list" unless assets.is_a?(Array)
    selected = []
    used = {}
    PRIORITY_TAGS.each do |tag|
      asset = assets.find do |candidate|
        candidate.is_a?(Hash) && candidate["tags"].is_a?(Array) &&
          candidate["tags"].include?(tag) && !used[candidate["id"]]
      end
      raise ContractError, "no unique asset covers #{tag}" unless asset
      used[asset.fetch("id")] = true
      selected << asset
    end
    selected
  end

  def validate_result!(asset_id:, result:)
    unless result.is_a?(Hash) && result["schema"] == 1 &&
           result["pipeline_schema"] == 10 && result["max_edge"] == 1_024 &&
           result["zero_is_exact"] == true
      raise ContractError, "#{asset_id} measurement identity is invalid"
    end
    width = positive_dimension!(asset_id, "width", result["width"])
    height = positive_dimension!(asset_id, "height", result["height"])
    if [width, height].max > 1_024
      raise ContractError, "#{asset_id} source exceeds the proxy bound"
    end

    %w[flip_horizontal flip_vertical].each do |name|
      operation = require_hash!(asset_id, name, result[name])
      require_bounded_number!(asset_id, "#{name}.effect_difference", operation["effect_difference"], minimum: 1.0 / 255)
      require_bounded_number!(asset_id, "#{name}.round_trip_difference", operation["round_trip_difference"], maximum: 0.002)
    end

    crop = require_hash!(asset_id, "crop", result["crop"])
    crop_width = positive_dimension!(asset_id, "crop.width", crop["width"])
    crop_height = positive_dimension!(asset_id, "crop.height", crop["height"])
    unless crop_width == crop["expected_width"] && crop_height == crop["expected_height"]
      raise ContractError, "#{asset_id} crop dimensions do not match the declared coordinates"
    end
    require_bounded_number!(asset_id, "crop.mapping_difference", crop["mapping_difference"], maximum: 1.0 / 255)

    quarter = require_hash!(asset_id, "quarter_turn", result["quarter_turn"])
    unless quarter["width"] == height && quarter["height"] == width
      raise ContractError, "#{asset_id} quarter turn does not swap dimensions"
    end
    require_bounded_number!(asset_id, "quarter_turn.cycle_difference", quarter["cycle_difference"], maximum: 0.002)

    directional = require_hash!(asset_id, "directional", result["directional"])
    unless directional.keys.sort == DIRECTIONS.sort
      raise ContractError, "#{asset_id} directional operation set is invalid"
    end
    directional.each do |name, raw_metrics|
      metrics = require_hash!(asset_id, name, raw_metrics)
      unless metrics["width"] == width && metrics["height"] == height
        raise ContractError, "#{asset_id} #{name} changes canvas dimensions"
      end
      require_bounded_number!(asset_id, "#{name}.effect_difference", metrics["effect_difference"], minimum: 1.0 / 255)
      require_bounded_number!(asset_id, "#{name}.white_ratio_delta", metrics["white_ratio_delta"], minimum: -1, maximum: 0.16)
    end

    combined = require_hash!(asset_id, "combined", result["combined"])
    positive_dimension!(asset_id, "combined.width", combined["width"])
    positive_dimension!(asset_id, "combined.height", combined["height"])
    require_bounded_number!(asset_id, "combined.white_ratio", combined["white_ratio"], maximum: 0.2)
  end

  def validate_corpus!(reports)
    unless reports.is_a?(Array) && reports.length == PRIORITY_TAGS.length
      raise ContractError, "composition corpus requires 12 reports"
    end
    ids = reports.map { |report| report.fetch("id") }
    raise ContractError, "composition corpus repeats an asset" unless ids.uniq.length == ids.length
  end

  def require_hash!(asset_id, name, value)
    raise ContractError, "#{asset_id} #{name} is invalid" unless value.is_a?(Hash)
    value
  end
  private_class_method :require_hash!

  def positive_dimension!(asset_id, name, value)
    unless value.is_a?(Integer) && value.positive?
      raise ContractError, "#{asset_id} #{name} is invalid"
    end
    value
  end
  private_class_method :positive_dimension!

  def require_bounded_number!(asset_id, name, value, minimum: 0, maximum: 1)
    unless value.is_a?(Numeric) && value.finite? && (minimum..maximum).cover?(value.to_f)
      raise ContractError, "#{asset_id} #{name} is outside #{minimum}...#{maximum}"
    end
  end
  private_class_method :require_bounded_number!
end
