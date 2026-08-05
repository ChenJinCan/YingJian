#!/usr/bin/env ruby

require "json"
require_relative "support/cross_platform_render_tolerance"
require_relative "support/render_semantic_trend"

def fail_contract(message)
  warn "Exposure semantic alignment failed: #{message}"
  exit 1
end

ios_argument = ARGV.shift
android_argument = ARGV.shift
if ios_argument.nil? || android_argument.nil? || !ARGV.empty?
  fail_contract("usage: check_exposure_semantic_alignment.rb IOS_REPORT ANDROID_REPORT")
end

repo_root = File.expand_path("..", __dir__)
reports = [[ios_argument, "ios"], [android_argument, "android"]].map do |argument, platform|
  begin
    path = CrossPlatformRenderTolerance.validated_report_path(argument, repo_root: repo_root)
    report = JSON.parse(File.read(path))
  rescue JSON::ParserError
    fail_contract("#{platform} observation report is not JSON")
  rescue CrossPlatformRenderTolerance::ContractError => error
    fail_contract(error.message)
  end
  unless report["schema"] == 1 && report["engineering_only"] == true &&
         report["observation_only"] == true && report["thresholds_frozen"] == false &&
         report["platform"] == platform && report["parameter"] == "exposure" &&
         report["profiles"] == %w[exposure-negative neutral exposure-positive] &&
         report["sample_max_edge"] == 512 && report["asset_count"] == 48
    fail_contract("#{platform} observation report identity is invalid")
  end
  report
end
unless reports.map { |report| report["manifest_sha256"] }.uniq.length == 1
  fail_contract("platform reports do not bind the same corpus manifest")
end

begin
  result = RenderSemanticTrend.check_exposure_alignment!(
    reports[0].fetch("assets"),
    reports[1].fetch("assets"),
  )
rescue KeyError, RenderSemanticTrend::ContractError => error
  fail_contract(error.message)
end

violations = result.fetch("violations")
unless violations.empty?
  violations.each { |violation| warn JSON.generate(violation) }
  fail_contract("#{violations.length} frozen contract violations")
end

puts "Exposure semantic alignment passed: 48 assets, iOS and Android"
