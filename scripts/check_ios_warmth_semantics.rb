#!/usr/bin/env ruby

require "json"
require_relative "support/cross_platform_render_tolerance"
require_relative "support/ios_warmth_semantic_contract"

def fail_contract(message)
  warn "iOS warmth semantic contract failed: #{message}"
  exit 1
end

argument = ARGV.shift
fail_contract("usage: check_ios_warmth_semantics.rb OBSERVATION_REPORT") if argument.nil? || !ARGV.empty?

repo_root = File.expand_path("..", __dir__)
begin
  path = CrossPlatformRenderTolerance.validated_report_path(argument, repo_root: repo_root)
  report = JSON.parse(File.read(path))
  result = IOSWarmthSemanticContract.check!(report)
rescue JSON::ParserError
  fail_contract("observation report is not JSON")
rescue CrossPlatformRenderTolerance::ContractError, IOSWarmthSemanticContract::ContractError => error
  fail_contract(error.message)
end

violations = result.fetch("violations")
unless violations.empty?
  violations.each { |violation| warn JSON.generate(violation) }
  fail_contract("#{violations.length} frozen contract violations")
end

puts "iOS warmth semantic contract passed: 48 assets"
