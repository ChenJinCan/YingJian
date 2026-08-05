#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "socket"
require "tempfile"
require "time"
require "tmpdir"

def fail_capture(message)
  warn "iOS device capture failed: #{message}"
  exit 1
end

options = {}
OptionParser.new do |parser|
  parser.banner = "usage: scripts/capture_ios_device_evidence.rb --device SELECTOR --output FILE"
  parser.on("--device SELECTOR") { |value| options[:device] = value }
  parser.on("--output FILE") { |value| options[:output] = value }
end.parse!
fail_capture("unexpected arguments") unless ARGV.empty?
device = options[:device].to_s.strip
output = options[:output].to_s.strip
fail_capture("device selector is required") if device.empty?
fail_capture("output path is required") if output.empty?

destination = Pathname.new(output).expand_path
fail_capture("output already exists") if destination.exist?
FileUtils.mkdir_p(destination.dirname)

Dir.mktmpdir("yingjian-devicectl-capture-") do |directory|
  device_json = File.join(directory, "devices.json")
  apps_json = File.join(directory, "apps.json")
  commands = [
    ["/usr/bin/xcrun", "devicectl", "list", "devices", "--json-output", device_json],
    ["/usr/bin/xcrun", "devicectl", "device", "info", "apps", "--device", device,
     "--bundle-id", "com.babycompany.yingjian", "--json-output", apps_json],
  ]
  commands.each do |command|
    _stdout, stderr, status = Open3.capture3(*command)
    fail_capture("#{command[1..3].join(' ')} failed: #{stderr.strip}") unless status.success?
  end
  version, version_error, version_status = Open3.capture3("/usr/bin/xcrun", "devicectl", "--version")
  fail_capture("devicectl --version failed: #{version_error.strip}") unless version_status.success?
  device_record = JSON.parse(File.read(device_json))
  app_record = JSON.parse(File.read(apps_json))
  selected = device_record.dig("result", "devices")
  selected = [] unless selected.is_a?(Array)
  matching = selected.select do |entry|
    entry.is_a?(Hash) && [
      entry["identifier"], entry.dig("hardwareProperties", "udid"),
      entry.dig("deviceProperties", "name"),
    ].include?(device)
  end
  fail_capture("device selector did not resolve to exactly one devicectl device") unless matching.length == 1

  record = {
    "schema" => 1,
    "captured_at" => Time.now.utc.iso8601,
    "host_id" => Digest::SHA256.hexdigest(Socket.gethostname),
    "collector" => {
      "file" => "scripts/capture_ios_device_evidence.rb",
      "sha256" => Digest::SHA256.file(__FILE__).hexdigest,
      "xcrun" => "/usr/bin/xcrun",
      "devicectl_version" => version.strip,
    },
    "selected_device_id" => Digest::SHA256.hexdigest(matching.first.fetch("identifier")),
    "device_list" => device_record,
    "installed_apps" => app_record,
  }
  Tempfile.create([".device-capture-", ".json"], destination.dirname.to_s) do |file|
    file.chmod(0o600)
    file.write(JSON.pretty_generate(record))
    file.write("\n")
    file.flush
    file.fsync
    File.rename(file.path, destination)
  end
rescue JSON::ParserError => error
  fail_capture("devicectl returned invalid JSON: #{error.message}")
end

puts "Captured connected iPhone and installed Yingjian identity to #{destination}."
