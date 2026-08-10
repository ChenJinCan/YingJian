#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"
require_relative "support/group_consistency_corpus"

def fail_contract(message)
  warn "Group consistency corpus failed: #{message}"
  exit 1
end

repo_root = File.expand_path("..", __dir__)
manifest_argument = ARGV.shift
output_argument = ARGV.shift
if manifest_argument.nil? || output_argument.nil? || !ARGV.empty?
  fail_contract("usage: run_group_consistency_corpus.rb MANIFEST OUTPUT_DIRECTORY")
end
manifest_path = File.expand_path(manifest_argument, repo_root)
fail_contract("manifest is missing") unless File.file?(manifest_path)
output_root = File.expand_path(output_argument, repo_root)
quality_root = File.join(repo_root, ".quality")
fail_contract("output must remain inside .quality") unless output_root.start_with?("#{quality_root}/")
fail_contract("output already exists") if File.exist?(output_root)

checker = File.join(repo_root, "scripts/check_image_quality_corpus.rb")
unless system("ruby", checker, manifest_path, out: $stdout, err: $stderr)
  fail_contract("image quality corpus contract did not pass")
end
manifest = YAML.safe_load(File.read(manifest_path), permitted_classes: [], aliases: false)
begin
  groups = GroupConsistencyCorpus.select_groups(manifest.fetch("assets"))
rescue GroupConsistencyCorpus::ContractError => error
  fail_contract(error.message)
end
corpus_root = File.realpath(File.expand_path(manifest.fetch("corpus_root"), repo_root))
pipeline_source = File.join(repo_root, "ios/Runner/IOSPhotoFileRenderer.swift")
portrait_source = File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift")
measure_source = File.join(repo_root, "scripts/support/measure_group_consistency_candidate.swift")
contract_source = File.join(repo_root, "scripts/support/group_consistency_corpus.rb")
FileUtils.mkdir_p(quality_root)

reports = []
Dir.mktmpdir(".group-consistency-", quality_root) do |temporary_root|
  executable = File.join(temporary_root, "measure-group-consistency")
  stdout, stderr, status = Open3.capture3(
    "/usr/bin/xcrun", "swiftc", "-O", "-parse-as-library",
    portrait_source, pipeline_source, measure_source, "-o", executable
  )
  detail = stderr.lines.first&.strip || stdout.lines.first&.strip
  fail_contract("measurement compilation failed: #{detail}") unless status.success?

  groups.each do |group_id, members|
    members.each do |asset|
      asset_id = asset.fetch("id")
      source_path = File.realpath(File.expand_path(asset.fetch("file"), corpus_root))
      fail_contract("#{asset_id} source escapes corpus") unless source_path.start_with?("#{corpus_root}/")
      source_hash = Digest::SHA256.file(source_path).hexdigest
      fail_contract("#{asset_id} source hash changed") unless source_hash == asset.fetch("sha256")
      output, error, measure_status = Open3.capture3(executable, source_path)
      fail_contract("#{asset_id} measurement failed: #{error.lines.first&.strip}") unless measure_status.success?
      begin
        result = JSON.parse(output)
        GroupConsistencyCorpus.validate_result!(asset_id: asset_id, result: result)
      rescue JSON::ParserError => error
        fail_contract("#{asset_id} measurement is not JSON: #{error.message}")
      rescue GroupConsistencyCorpus::ContractError => error
        fail_contract(error.message)
      end
      reports << {
        "id" => asset_id,
        "group_id" => group_id,
        "tags" => asset.fetch("tags"),
        "source_sha256" => source_hash,
        "result" => result,
      }
    end
  end
  begin
    GroupConsistencyCorpus.validate_corpus!(reports)
  rescue GroupConsistencyCorpus::ContractError => error
    fail_contract(error.message)
  end
  report = {
    "schema" => 1,
    "engineering_only" => true,
    "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
    "pipeline_source_sha256" => Digest::SHA256.file(pipeline_source).hexdigest,
    "portrait_source_sha256" => Digest::SHA256.file(portrait_source).hexdigest,
    "measure_source_sha256" => Digest::SHA256.file(measure_source).hexdigest,
    "contract_source_sha256" => Digest::SHA256.file(contract_source).hexdigest,
    "group_count" => groups.length,
    "asset_count" => reports.length,
    "assets" => reports,
  }
  FileUtils.mkdir_p(output_root)
  File.write(File.join(output_root, "engineering-report.json"), JSON.pretty_generate(report) + "\n")
end

puts "Group consistency engineering corpus passed: #{groups.length} groups / #{reports.length} assets"
