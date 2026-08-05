#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "time"

def fail_delivery(message)
  warn "TestFlight delivery verification failed: #{message}"
  exit 1
end

begin
options = {}
OptionParser.new do |parser|
  parser.on("--version VALUE") { |value| options[:version] = value }
  parser.on("--build VALUE") { |value| options[:build] = value }
  parser.on("--source-commit VALUE") { |value| options[:source_commit] = value }
  parser.on("--sha256 VALUE") { |value| options[:sha256] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
end.parse!
input = ARGV.shift
fail_delivery("one delivery JSON path is required") unless input && ARGV.empty?
data = JSON.parse(File.read(input))

objects = []
pairs = []
visit = lambda do |value|
  case value
  when Hash
    normalized = value.to_h { |key, child| [key.to_s.downcase.gsub(/[^a-z0-9]/, ""), child] }
    objects << normalized
    value.each do |key, child|
      pairs << [key.to_s.downcase.gsub(/[^a-z0-9]/, ""), child]
      visit.call(child)
    end
  when Array
    value.each { |child| visit.call(child) }
  end
end
visit.call(data)

id_keys = %w[deliveryid deliveryuuid uploadid]
status_keys = %w[status state deliverystatus uploadstatus]
success_states = %w[COMPLETE COMPLETED SUCCEEDED SUCCESS VALID]
failure_states = %w[FAILED FAILURE ERROR INVALID REJECTED CANCELLED CANCELED]
all_states = pairs.select { |key, _value| status_keys.include?(key) }.map { |_key, value| value.to_s.upcase }
fail_delivery("provider response contains a failure state") if (all_states & failure_states).any?
candidates = objects.each_with_object([]) do |object, result|
  id = id_keys.map { |key| object[key] }.compact.find { |value| !value.to_s.strip.empty? }
  state = status_keys.map { |key| object[key] }.compact.map { |value| value.to_s.upcase }.find { |value| success_states.include?(value) }
  result << [id.to_s, state] if id && state
end.uniq
fail_delivery("stable delivery identifier and terminal state must belong to the same delivery object") unless candidates.length == 1
delivery_id, terminal = candidates.first

report = {
  "schema_version" => 1,
  "platform" => "ios",
  "version" => options.fetch(:version),
  "build" => options.fetch(:build),
  "source_commit" => options.fetch(:source_commit),
  "sha256" => options.fetch(:sha256),
  "delivery_id" => delivery_id,
  "provider_state" => terminal,
  "uploaded" => true,
  "provider_processing" => false,
  "provider_valid" => true,
  "test_group_distributed" => false,
  "tester_reachability_verified" => false,
  "verified_at" => Time.now.utc.iso8601
}
File.write(options.fetch(:output), JSON.pretty_generate(report) + "\n", mode: "w", perm: 0o600)
puts "Provider valid delivery #{delivery_id} (#{terminal})."
rescue JSON::ParserError => error
  fail_delivery("invalid JSON: #{error.message}")
rescue KeyError => error
  fail_delivery(error.message)
end
