# frozen_string_literal: true

module CrossPlatformRenderComparison
  class ContractError < StandardError; end

  NORMALIZED_METRICS = %w[
    mean_absolute_error
    root_mean_square_error
    maximum_absolute_error
    mean_absolute_luma_error
    exact_pixel_ratio
    pixel_ratio_over_4_code_values
    pixel_ratio_over_8_code_values
    p95_max_channel_error
    p99_max_channel_error
  ].freeze

  module_function

  def index_assets!(report, platform:)
    unless report.is_a?(Hash) && report["asset_count"].is_a?(Integer)
      raise ContractError, "#{platform} report identity is invalid"
    end
    assets = report["assets"]
    unless assets.is_a?(Array) && assets.length == report["asset_count"]
      raise ContractError, "#{platform} report asset count is invalid"
    end
    indexed = {}
    assets.each do |asset|
      asset_id = asset["id"] if asset.is_a?(Hash)
      unless asset_id.is_a?(String) && asset_id.match?(/\A[a-z0-9-]+\z/)
        raise ContractError, "#{platform} report contains an invalid asset id"
      end
      raise ContractError, "#{platform} report repeats #{asset_id}" if indexed.key?(asset_id)
      indexed[asset_id] = asset
    end
    indexed
  end

  def summarize(values)
    unless values.is_a?(Array) && !values.empty? && values.all? { |value| finite_number?(value) }
      raise ContractError, "summary values must be finite numbers"
    end
    sorted = values.map(&:to_f).sort
    {
      "minimum" => sorted.first,
      "p50" => nearest_rank(sorted, 0.50),
      "p95" => nearest_rank(sorted, 0.95),
      "maximum" => sorted.last,
    }
  end

  def validate_metric!(metric, asset_id:)
    unless metric.is_a?(Hash) &&
           metric["sample_width"].is_a?(Integer) && metric["sample_width"].positive? &&
           metric["sample_height"].is_a?(Integer) && metric["sample_height"].positive? &&
           metric["sample_pixels"] == metric["sample_width"] * metric["sample_height"]
      raise ContractError, "#{asset_id} sample identity is invalid"
    end
    NORMALIZED_METRICS.each do |name|
      value = metric[name]
      unless finite_number?(value) && (0.0..1.0).cover?(value.to_f)
        raise ContractError, "#{asset_id} #{name} is outside 0...1"
      end
    end
    %w[mean_absolute_rgb root_mean_square_rgb].each do |name|
      validate_vector!(metric[name], asset_id: asset_id, name: name, signed: false)
    end
    validate_vector!(metric["mean_rgb_bias"], asset_id: asset_id, name: "mean_rgb_bias", signed: true)
    psnr = metric["psnr_db"]
    unless psnr.nil? || (finite_number?(psnr) && psnr.to_f >= 0)
      raise ContractError, "#{asset_id} psnr_db is invalid"
    end
    unless metric["mean_absolute_error"] <= metric["root_mean_square_error"] &&
           metric["root_mean_square_error"] <= metric["maximum_absolute_error"] &&
           metric["p95_max_channel_error"] <= metric["p99_max_channel_error"]
      raise ContractError, "#{asset_id} metric ordering is impossible"
    end
  end

  def validated_output_root(path, repo_root:)
    expanded_repo = File.expand_path(repo_root)
    quality_root = File.join(expanded_repo, ".quality")
    expanded = File.expand_path(path, expanded_repo)
    unless expanded.start_with?("#{quality_root}/")
      raise ContractError, "output must remain inside .quality"
    end
    expanded
  end

  def validated_quality_directory(path, repo_root:)
    expanded_repo = File.expand_path(repo_root)
    quality_root = File.join(expanded_repo, ".quality")
    expanded = File.expand_path(path, expanded_repo)
    unless File.directory?(expanded) && File.directory?(quality_root)
      raise ContractError, "quality input directory is missing"
    end
    quality_real = File.realpath(quality_root)
    input_real = File.realpath(expanded)
    unless input_real.start_with?("#{quality_real}/")
      raise ContractError, "quality input resolves outside .quality"
    end
    input_real
  rescue SystemCallError => error
    raise ContractError, "quality input could not be resolved: #{error.message}"
  end

  def validate_output_ancestry!(path, repo_root:)
    expanded_repo = File.expand_path(repo_root)
    quality_root = File.join(expanded_repo, ".quality")
    expanded = validated_output_root(path, repo_root: expanded_repo)
    unless File.directory?(quality_root)
      raise ContractError, ".quality must exist before validating output"
    end
    ancestor = File.dirname(expanded)
    ancestor = File.dirname(ancestor) until File.exist?(ancestor)
    quality_real = File.realpath(quality_root)
    ancestor_real = File.realpath(ancestor)
    unless ancestor_real == quality_real || ancestor_real.start_with?("#{quality_real}/")
      raise ContractError, "output resolves outside .quality"
    end
    expanded
  rescue SystemCallError => error
    raise ContractError, "output ancestry could not be resolved: #{error.message}"
  end

  def nearest_rank(sorted, percentile)
    sorted.fetch([((percentile * sorted.length).ceil - 1), 0].max)
  end
  private_class_method :nearest_rank

  def validate_vector!(value, asset_id:, name:, signed:)
    valid_range = signed ? (-1.0..1.0) : (0.0..1.0)
    unless value.is_a?(Array) && value.length == 3 &&
           value.all? { |item| finite_number?(item) && valid_range.cover?(item.to_f) }
      raise ContractError, "#{asset_id} #{name} is invalid"
    end
  end
  private_class_method :validate_vector!

  def finite_number?(value)
    value.is_a?(Numeric) && value.finite?
  end
  private_class_method :finite_number?
end
