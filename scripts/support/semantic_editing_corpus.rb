# frozen_string_literal: true

module SemanticEditingCorpus
  class ContractError < StandardError; end

  PRIORITY_TAGS = %w[
    portrait_single portrait_multi no_face landscape food pet low_light backlit
    mixed_light group_member exif_rotated display_p3
  ].freeze
  OPERATIONS = %w[
    subject_exposure background_exposure background_blur background_white
    background_image local_adjustment erase mask_paint mask_erase
  ].freeze
  ALWAYS_VISIBLE = %w[
    subject_exposure background_exposure background_white background_image
    local_adjustment mask_paint mask_erase
  ].freeze
  PROTECTION_LIMIT = 0.0005
  VISIBLE_LIMIT = 1.0 / 255

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
           result["zero_is_exact"] == true &&
           result["empty_local_mask_is_exact"] == true &&
           result["empty_erase_mask_is_exact"] == true
      raise ContractError, "#{asset_id} semantic measurement identity is invalid"
    end
    width = result["width"]
    height = result["height"]
    unless width.is_a?(Integer) && height.is_a?(Integer) && width.positive? &&
           height.positive? && [width, height].max <= 1_024
      raise ContractError, "#{asset_id} semantic proxy dimensions are invalid"
    end
    measurements = result["measurements"]
    unless measurements.is_a?(Hash) && measurements.keys.sort == OPERATIONS.sort
      raise ContractError, "#{asset_id} semantic operation set is invalid"
    end
    measurements.each do |name, metrics|
      validate_metrics!(asset_id, name, metrics)
    end
    ALWAYS_VISIBLE.each do |name|
      p95 = measurements.fetch(name).fetch("target_p95_difference")
      if p95 < VISIBLE_LIMIT
        raise ContractError, "#{asset_id} #{name} is not visibly effective"
      end
    end
  end

  def validate_corpus!(reports)
    unless reports.is_a?(Array) && reports.length == PRIORITY_TAGS.length
      raise ContractError, "semantic editing corpus requires 12 reports"
    end
    ids = reports.map { |report| report.fetch("id") }
    raise ContractError, "semantic editing corpus repeats an asset" unless ids.uniq.length == ids.length

    %w[background_blur erase].each do |operation|
      visible = reports.count do |report|
        report.fetch("result").fetch("measurements").fetch(operation)
          .fetch("target_p95_difference") >= VISIBLE_LIMIT
      end
      if visible < 9
        raise ContractError, "#{operation} is visible on only #{visible}/12 assets"
      end
    end
  end

  def validate_metrics!(asset_id, name, metrics)
    unless metrics.is_a?(Hash) && metrics.keys.sort == %w[
      protected_mean_difference target_mean_difference target_p95_difference
    ].sort
      raise ContractError, "#{asset_id} #{name} metrics are invalid"
    end
    metrics.each do |key, value|
      unless value.is_a?(Numeric) && value.finite? && (0.0..1.0).cover?(value.to_f)
        raise ContractError, "#{asset_id} #{name}.#{key} is invalid"
      end
    end
    if metrics["protected_mean_difference"] > PROTECTION_LIMIT
      raise ContractError, "#{asset_id} #{name} changes the protected region"
    end
  end
  private_class_method :validate_metrics!
end
