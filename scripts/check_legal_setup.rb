#!/usr/bin/env ruby
# frozen_string_literal: true

require "uri"
require "yaml"

root = File.expand_path("..", __dir__)
policy_path = File.join(root, "release", "legal-policy.yaml")
policy = YAML.safe_load(File.read(policy_path))
errors = []

errors << "legal policy schema must be 1" unless policy["schema_version"] == 1
privacy = policy.fetch("privacy_policy", {})
%w[public_url support_url].each do |field|
  value = privacy[field]
  begin
    uri = URI.parse(value.to_s)
    errors << "#{field} must be a public HTTPS URL" unless uri.is_a?(URI::HTTPS) && uri.host
  rescue URI::InvalidURIError
    errors << "#{field} must be a public HTTPS URL"
  end
end
errors << "support_contact must be configured" if privacy["support_contact"].to_s.strip.empty?

verification = policy.fetch("store_verification", {})
errors << "App Store privacy metadata is not verified" unless verification["app_store_privacy_verified"] == true
errors << "Google Play Data Safety is not verified" unless verification["google_play_data_safety_verified"] == true
errors << "Apple EULA mode must be standard or custom" unless %w[standard custom].include?(policy.dig("apple", "eula_mode"))

required_assets = %w[privacy_zh.md privacy_en.md terms_zh.md terms_en.md]
required_assets.each do |asset|
  errors << "missing in-app legal asset #{asset}" unless File.file?(File.join(root, "assets", "legal", asset))
end

if errors.any?
  warn "BLOCKED: legal/store setup is incomplete:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "Legal policy, public URLs, and store declarations are verified."
