#!/usr/bin/env ruby

require "json"
require_relative "support/cross_platform_render_tolerance"
require_relative "support/ios_color_detail_semantic_contract"

def fail_contract(message)
  warn "iOS color-detail semantic contract failed: #{message}"
  exit 1
end

arguments = 3.times.map { ARGV.shift }
if arguments.any?(&:nil?) || !ARGV.empty?
  fail_contract("usage: check_ios_color_detail_semantics.rb SATURATION_REPORT TINT_REPORT CLARITY_REPORT")
end

repo_root = File.expand_path("..", __dir__)
begin
  reports = arguments.map do |argument|
    path = CrossPlatformRenderTolerance.validated_report_path(argument, repo_root: repo_root)
    JSON.parse(File.read(path))
  end
  result = IOSColorDetailSemanticContract.check!(reports[0], reports[1], reports[2])
rescue JSON::ParserError
  fail_contract("observation report is not JSON")
rescue CrossPlatformRenderTolerance::ContractError, IOSColorDetailSemanticContract::ContractError => error
  fail_contract(error.message)
end

violations = result.fetch("violations")
unless violations.empty?
  violations.each { |violation| warn JSON.generate(violation) }
  fail_contract("#{violations.length} frozen contract violations")
end

puts "iOS color-detail semantic contract passed: saturation, tint, and clarity, 48 assets"
