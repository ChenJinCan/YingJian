#!/usr/bin/env ruby

require "json"
require_relative "support/cross_platform_render_tolerance"

def fail_contract(message)
  warn "Cross-platform render tolerance failed: #{message}"
  exit 1
end

argument = ARGV.shift
if argument.nil? || !ARGV.empty?
  fail_contract("usage: check_cross_platform_render_tolerance.rb OBSERVATION_REPORT")
end

repo_root = File.expand_path("..", __dir__)
begin
  report_path = CrossPlatformRenderTolerance.validated_report_path(
    argument,
    repo_root: repo_root,
  )
  report = JSON.parse(File.read(report_path))
  result = CrossPlatformRenderTolerance.check!(report)
rescue JSON::ParserError
  fail_contract("observation report is not JSON")
rescue CrossPlatformRenderTolerance::ContractError => error
  fail_contract(error.message)
end

violations = result.fetch("violations")
unless violations.empty?
  violations.each do |violation|
    bound_name = violation.key?("maximum") ? "maximum" : "minimum"
    warn format(
      "%s %s actual=%.9f %s=%.9f",
      violation.fetch("asset_id"),
      violation.fetch("metric"),
      violation.fetch("actual"),
      bound_name,
      violation.fetch(bound_name),
    )
  end
  fail_contract("#{violations.length} metric violations for #{result.fetch("profile")}")
end

puts "Cross-platform render tolerance passed: #{result.fetch("profile")}, #{result.fetch("asset_count")} assets"
