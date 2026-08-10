# frozen_string_literal: true

module GroupConsistencyCorpus
  class ContractError < StandardError; end

  GROUP_COUNT = 6
  MEMBERS_PER_GROUP = 4
  ONE_CODE = 1.0 / 255
  METRICS = %w[
    black_clip_ratio mean_chroma mean_luma red_blue_delta white_clip_ratio
  ].freeze
  DIFFERENCE_METRICS = %w[mean_difference p95_difference].freeze

  module_function

  def select_groups(assets)
    raise ContractError, "assets must be a list" unless assets.is_a?(Array)
    members = assets.select do |asset|
      asset.is_a?(Hash) && asset["tags"].is_a?(Array) &&
        asset["tags"].include?("group_member")
    end
    groups = members.group_by { |asset| asset["group_id"] }
    unless groups.keys.compact.length == GROUP_COUNT && groups.length == GROUP_COUNT
      raise ContractError, "group corpus requires exactly 6 named groups"
    end
    groups.each do |group_id, group_members|
      unless group_id.is_a?(String) && !group_id.empty? &&
             group_members.length == MEMBERS_PER_GROUP
        raise ContractError, "#{group_id || 'unnamed'} must contain exactly 4 members"
      end
    end
    groups.sort.to_h
  end

  def validate_result!(asset_id:, result:)
    unless result.is_a?(Hash) && result["schema"] == 1 &&
           result["pipeline_schema"] == 10 && result["max_edge"] == 1_024 &&
           result["zero_is_exact"] == true
      raise ContractError, "#{asset_id} group measurement identity is invalid"
    end
    width = result["width"]
    height = result["height"]
    unless width.is_a?(Integer) && height.is_a?(Integer) && width.positive? &&
           height.positive? && [width, height].max <= 1_024
      raise ContractError, "#{asset_id} group proxy dimensions are invalid"
    end
    unless result["shared_intensity"] == 0.8 &&
           result["shared_filter"] == "cinematic" &&
           close?(result["shared_filter_strength"], 36) &&
           close?(result["shared_hsl_blue_saturation"], -9.6)
      raise ContractError, "#{asset_id} shared style signature is invalid"
    end

    source = metrics!(asset_id, "source", result["source"])
    shared = metrics!(asset_id, "shared", result["shared"])
    adaptive = metrics!(asset_id, "adaptive", result["adaptive"])
    shared_difference = difference!(asset_id, "shared", result["shared_difference"])
    adaptive_difference = difference!(asset_id, "adaptive", result["adaptive_difference"])
    override_difference = difference!(asset_id, "override", result["override_difference"])
    if shared_difference.fetch("p95_difference") < ONE_CODE
      raise ContractError, "#{asset_id} shared style is not visibly effective"
    end
    if override_difference.fetch("p95_difference") < ONE_CODE
      raise ContractError, "#{asset_id} per-photo override is not visibly effective"
    end

    expected_exposure = source.fetch("mean_luma") < 0.34 ? 0.15 :
      (source.fetch("mean_luma") > 0.72 ? -0.12 : 0.0)
    expected_warmth = source.fetch("red_blue_delta") > 0.10 ? -0.08 :
      (source.fetch("red_blue_delta") < -0.10 ? 0.08 : 0.0)
    unless close?(result["adaptive_exposure"], expected_exposure) &&
           close?(result["adaptive_warmth"], expected_warmth)
      raise ContractError, "#{asset_id} adaptive parameter semantics are invalid"
    end
    if expected_exposure.zero? && expected_warmth.zero?
      unless adaptive_difference.values.all?(&:zero?)
        raise ContractError, "#{asset_id} neutral adaptive layer is not exact"
      end
    elsif adaptive_difference.fetch("p95_difference") <= 0
      raise ContractError, "#{asset_id} adaptive layer has no pixel effect"
    end
    luma_step = adaptive.fetch("mean_luma") - shared.fetch("mean_luma")
    warmth_step = adaptive.fetch("red_blue_delta") - shared.fetch("red_blue_delta")
    if expected_exposure.positive? && luma_step < 2 * ONE_CODE
      raise ContractError, "#{asset_id} underexposure compensation is weak or reversed"
    end
    if expected_exposure.negative? && luma_step > -2 * ONE_CODE
      raise ContractError, "#{asset_id} overexposure compensation is weak or reversed"
    end
    if expected_exposure.zero? && expected_warmth.positive? && warmth_step < 0.0025
      raise ContractError, "#{asset_id} cool-cast compensation is weak or reversed"
    end
    if expected_exposure.zero? && expected_warmth.negative? && warmth_step > -0.0025
      raise ContractError, "#{asset_id} warm-cast compensation is weak or reversed"
    end
    if adaptive.fetch("black_clip_ratio") - source.fetch("black_clip_ratio") > 0.02 ||
       adaptive.fetch("white_clip_ratio") - source.fetch("white_clip_ratio") > 0.02
      raise ContractError, "#{asset_id} group processing exceeds the clipping budget"
    end
  end

  def validate_corpus!(reports)
    unless reports.is_a?(Array) && reports.length == GROUP_COUNT * MEMBERS_PER_GROUP
      raise ContractError, "group consistency corpus requires 24 reports"
    end
    ids = reports.map { |report| report.fetch("id") }
    raise ContractError, "group corpus repeats an asset" unless ids.uniq.length == ids.length
    groups = reports.group_by { |report| report.fetch("group_id") }
    unless groups.length == GROUP_COUNT && groups.values.all? { |members| members.length == MEMBERS_PER_GROUP }
      raise ContractError, "group corpus shape is invalid"
    end

    improved = 0
    groups.each do |group_id, members|
      source_range = luma_range(members, "source")
      shared_range = luma_range(members, "shared")
      adaptive_range = luma_range(members, "adaptive")
      if shared_range > source_range + 0.005
        raise ContractError, "#{group_id} shared style destabilizes same-scene luma"
      end
      if adaptive_range > source_range + 0.005
        raise ContractError, "#{group_id} adaptive layer destabilizes same-scene luma"
      end
      improved += 1 if source_range - adaptive_range >= 0.01
    end
    if improved < 2
      raise ContractError, "adaptive layer materially improves only #{improved}/6 groups"
    end
  end

  def metrics!(asset_id, name, metrics)
    unless metrics.is_a?(Hash) && metrics.keys.sort == METRICS.sort &&
           metrics.values.all? { |value| finite_number?(value) } &&
           (0.0..1.0).cover?(metrics.fetch("mean_luma").to_f) &&
           (0.0..1.0).cover?(metrics.fetch("mean_chroma").to_f) &&
           (-1.0..1.0).cover?(metrics.fetch("red_blue_delta").to_f) &&
           (0.0..1.0).cover?(metrics.fetch("black_clip_ratio").to_f) &&
           (0.0..1.0).cover?(metrics.fetch("white_clip_ratio").to_f)
      raise ContractError, "#{asset_id} #{name} metrics are invalid"
    end
    metrics
  end
  private_class_method :metrics!

  def difference!(asset_id, name, metrics)
    unless metrics.is_a?(Hash) && metrics.keys.sort == DIFFERENCE_METRICS.sort &&
           metrics.values.all? { |value| finite_number?(value) && (0.0..1.0).cover?(value.to_f) }
      raise ContractError, "#{asset_id} #{name} difference metrics are invalid"
    end
    metrics
  end
  private_class_method :difference!

  def luma_range(members, layer)
    values = members.map { |member| member.fetch("result").fetch(layer).fetch("mean_luma") }
    values.max - values.min
  end
  private_class_method :luma_range

  def finite_number?(value)
    value.is_a?(Numeric) && value.finite?
  end
  private_class_method :finite_number?

  def close?(value, expected)
    finite_number?(value) && (value.to_f - expected).abs <= 1e-9
  end
  private_class_method :close?
end
