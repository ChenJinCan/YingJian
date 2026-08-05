# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "portrait_engineering_corpus"

module PortraitReviewContract
  class ContractError < StandardError; end

  MVP_SCHEMA = 2
  LEGACY_SCHEMA = 1
  COMPETITOR_IDENTITIES = {
    "xingtu" => {
      "app_store_id" => "1500526240",
      "bundle_id" => "com.xt.retouch",
    },
    "berry" => {
      "app_store_id" => "6741474933",
      "bundle_id" => "com.seesun.berryFilm",
    },
  }.freeze
  BASE_SLOTS = [
    ["baseline_original", "original", "original", "source"],
    ["subject", "yingjian", "off", "export"],
    ["subject", "yingjian", "default", "export"],
    ["subject", "yingjian", "high_safe", "export"],
    ["subject", "yingjian", "default", "preview"],
  ].freeze
  MVP_REFERENCE_SLOTS = COMPETITOR_IDENTITIES.keys.map do |producer|
    ["reference", producer, "fixed_path", "export"]
  end.freeze
  LEGACY_REFERENCE_SLOTS = [
    ["reference", "competitor", "fixed_path", "export"],
  ].freeze

  module_function

  def supported_schema?(schema)
    [LEGACY_SCHEMA, MVP_SCHEMA].include?(schema)
  end

  def expected_slots(schema)
    case schema
    when MVP_SCHEMA
      BASE_SLOTS + MVP_REFERENCE_SLOTS
    when LEGACY_SCHEMA
      BASE_SLOTS + LEGACY_REFERENCE_SLOTS
    else
      raise ContractError, "unsupported portrait review schema: #{schema.inspect}"
    end
  end

  def valid_producers(role, schema)
    case role
    when "baseline_original" then ["original"]
    when "subject" then ["yingjian"]
    when "reference"
      schema == MVP_SCHEMA ? COMPETITOR_IDENTITIES.keys : ["competitor"]
    else
      []
    end
  end

  def slot_key(role:, provenance:)
    [role, provenance["producer"], provenance["variant"], provenance["render_kind"]].join(":")
  end

  def validate_competitor_identity!(competitor_id, competitor)
    expected = COMPETITOR_IDENTITIES.fetch(competitor_id) do
      raise ContractError, "unknown formal competitor: #{competitor_id}"
    end
    expected.each do |field, value|
      unless competitor[field] == value
        raise ContractError, "#{competitor_id}.#{field} must equal #{value}"
      end
    end
  end

  def validate_mvp_plan_bindings!(plan, plan_path:, quality_root:)
    raise ContractError, "source plan schema must equal 2" unless plan.is_a?(Hash) && plan["schema"] == MVP_SCHEMA

    plan_path = File.realpath(plan_path)
    plan_directory = File.dirname(plan_path)
    quality_root = File.realpath(quality_root)
    repo_root = File.dirname(quality_root)

    corpus_path = validate_bound_file!(
      plan["portrait_corpus_manifest"],
      directory: plan_directory,
      root: quality_root,
      label: "portrait_corpus_manifest",
    )
    begin
      corpus = YAML.safe_load(File.read(corpus_path), permitted_classes: [], aliases: false)
      raise ContractError, "portrait corpus manifest schema must equal 2" unless corpus.is_a?(Hash) && corpus["schema"] == 2
      PortraitEngineeringCorpus.validate_manifest!(corpus)
    rescue Psych::Exception, PortraitEngineeringCorpus::ContractError => error
      raise ContractError, "portrait corpus manifest is invalid: #{error.message}"
    end
    corpus_assets = corpus.fetch("assets").to_h { |asset| [asset["id"], asset] }

    device_binding = plan["device_evidence"]
    unless device_binding.is_a?(Hash) && %w[id device os].all? { |field| concrete_string?(device_binding[field]) }
      raise ContractError, "device_evidence identity is incomplete"
    end
    device_path = validate_bound_file!(
      device_binding,
      directory: plan_directory,
      root: File.join(quality_root, "evidence"),
      label: "device_evidence",
    )
    begin
      device_record = JSON.parse(File.read(device_path))
    rescue JSON::ParserError => error
      raise ContractError, "device_evidence is invalid JSON: #{error.message}"
    end
    unless device_record.is_a?(Hash) && device_record["schema"] == 1 &&
        device_record["device_evidence_id"] == device_binding["id"] &&
        device_record["device"] == device_binding["device"] && device_record["os"] == device_binding["os"]
      raise ContractError, "device_evidence does not match the frozen iPhone record"
    end

    items = plan["items"]
    raise ContractError, "items must be a non-empty list" unless items.is_a?(Array) && !items.empty?
    items.each_with_index do |item, index|
      asset_id = item["asset_id"]
      corpus_asset = corpus_assets[asset_id]
      raise ContractError, "items[#{index}] is missing from portrait_corpus_manifest" unless corpus_asset.is_a?(Hash)
      unless item["tags"].is_a?(Array) && corpus_asset["tags"].is_a?(Array) &&
          item["tags"].uniq.sort == corpus_asset["tags"].uniq.sort
        raise ContractError, "items[#{index}].tags do not match portrait_corpus_manifest"
      end
      baseline = item.fetch("candidates", []).find { |candidate| candidate["role"] == "baseline_original" }
      raw_source_sha256 = baseline&.dig("provenance", "parameters", "raw_source_sha256")
      unless raw_source_sha256 == corpus_asset["sha256"]
        raise ContractError, "items[#{index}] raw source does not match portrait_corpus_manifest"
      end
      validate_authorization!(corpus_asset, repo_root: repo_root, quality_root: quality_root, label: "items[#{index}]")

      unless baseline&.dig("provenance", "parameters", "device_evidence_id") == device_binding["id"]
        raise ContractError, "items[#{index}] original does not match the frozen iPhone record"
      end
      subjects = item.fetch("candidates", []).select { |candidate| candidate["role"] == "subject" }
      unless subjects.all? do |candidate|
        provenance = candidate["provenance"]
        provenance.is_a?(Hash) && provenance["device"] == device_binding["device"] &&
          provenance["os"] == device_binding["os"] &&
          provenance.dig("parameters", "device_evidence_id") == device_binding["id"]
      end
        raise ContractError, "items[#{index}] Yingjian results do not match the frozen iPhone record"
      end

      references = item.fetch("candidates", []).select { |candidate| candidate["role"] == "reference" }
      references.each do |candidate|
        provenance = candidate["provenance"]
        producer = provenance["producer"] if provenance.is_a?(Hash)
        validate_competitor_identity!(producer, provenance || {})
        unless provenance["device_evidence_id"] == device_binding["id"] &&
            provenance["device"] == device_binding["device"] && provenance["os"] == device_binding["os"]
          raise ContractError, "items[#{index}] #{producer} does not match the frozen iPhone record"
        end
      end
    end
    true
  rescue Errno::ENOENT, Errno::EACCES => error
    raise ContractError, error.message
  end

  def validate_bound_file!(binding, directory:, root:, label:)
    unless binding.is_a?(Hash) && concrete_string?(binding["file"]) &&
        binding["sha256"].is_a?(String) && binding["sha256"].match?(/\A[0-9a-f]{64}\z/)
      raise ContractError, "#{label} file binding is incomplete"
    end
    path = Pathname.new(binding["file"]).absolute? ? binding["file"] : File.expand_path(binding["file"], directory)
    root = File.realpath(root)
    real = File.realpath(path)
    unless File.file?(real) && real.start_with?("#{root}/")
      raise ContractError, "#{label} must remain inside #{root}"
    end
    unless Digest::SHA256.file(real).hexdigest == binding["sha256"]
      raise ContractError, "#{label}.sha256 does not match the file"
    end
    real
  end

  def validate_authorization!(asset, repo_root:, quality_root:, label:)
    license = asset["license"]
    unless license.is_a?(Hash) && license["internal_review_authorized"] == true &&
        concrete_string?(license["evidence_ref"]) &&
        license["evidence_sha256"].is_a?(String) && license["evidence_sha256"].match?(/\A[0-9a-f]{64}\z/)
      raise ContractError, "#{label} license does not authorize internal review"
    end
    evidence_path = File.expand_path(license["evidence_ref"], repo_root)
    evidence_root = File.join(quality_root, "evidence")
    real = File.realpath(evidence_path)
    unless File.file?(real) && real.start_with?("#{File.realpath(evidence_root)}/") &&
        Digest::SHA256.file(real).hexdigest == license["evidence_sha256"]
      raise ContractError, "#{label} license evidence is missing or changed"
    end
  end

  def concrete_string?(value)
    value.is_a?(String) && !value.strip.empty?
  end
end
