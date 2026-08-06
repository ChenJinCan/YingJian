#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

checker = File.expand_path("check_altool_delivery.rb", __dir__)
Dir.mktmpdir("altool-delivery-") do |dir|
  input = File.join(dir, "delivery.json")
  output = File.join(dir, "status.json")
  File.write(input, JSON.generate("data" => { "deliveryId" => "delivery-123", "status" => "COMPLETE" }))
  _out, err, status = Open3.capture3("ruby", checker, input, "--version", "1.2.4", "--build", "112",
                                     "--source-commit", "a" * 40, "--sha256", "b" * 64, "--output", output)
  raise "valid delivery rejected: #{err}" unless status.success?
  report = JSON.parse(File.read(output))
  raise "delivery boundary collapsed" unless report["provider_valid"] && !report["test_group_distributed"]

  File.write(input, <<~DELIVERY)
    Running altool at path '/Applications/Xcode.app/altool'...
    UPLOAD SUCCEEDED with no errors
    Delivery UUID: delivery-456
    {
      "app-store-attributes": {"processingState": "VALID"},
      "build-status": "VALID",
      "bundle-short-version-string": "1.2.4",
      "bundle-version": "112",
      "delivery-uuid": "delivery-456",
      "import-status": "VALID"
    }
    {"success-message": "No errors uploading archive."}
  DELIVERY
  _out, err, status = Open3.capture3("ruby", checker, input, "--version", "1.2.4", "--build", "112",
                                     "--source-commit", "a" * 40, "--sha256", "b" * 64, "--output", output)
  raise "real altool mixed output rejected: #{err}" unless status.success?
  report = JSON.parse(File.read(output))
  raise "real altool delivery ID was not preserved" unless report["delivery_id"] == "delivery-456"

  File.write(input, JSON.generate("data" => { "deliveryId" => "delivery-123", "status" => "PROCESSING" }))
  _out, err, status = Open3.capture3("ruby", checker, input, "--version", "1.2.4", "--build", "112",
                                     "--source-commit", "a" * 40, "--sha256", "b" * 64, "--output", output)
  raise "processing delivery accepted" if status.success? || !err.include?("same delivery object")

  File.write(input, JSON.generate("data" => { "status" => "COMPLETE" }))
  _out, err, status = Open3.capture3("ruby", checker, input, "--version", "1.2.4", "--build", "112",
                                     "--source-commit", "a" * 40, "--sha256", "b" * 64, "--output", output)
  raise "delivery without ID accepted" if status.success? || !err.include?("same delivery object")

  File.write(input, JSON.generate(
    "request" => { "requestUUID" => "request-1", "status" => "SUCCESS" },
    "delivery" => { "deliveryId" => "delivery-123", "deliveryStatus" => "FAILED" }
  ))
  _out, err, status = Open3.capture3("ruby", checker, input, "--version", "1.2.4", "--build", "112",
                                     "--source-commit", "a" * 40, "--sha256", "b" * 64, "--output", output)
  raise "mixed success and failed delivery accepted" if status.success? || !err.include?("failure state")
end
puts "altool delivery tests passed."
