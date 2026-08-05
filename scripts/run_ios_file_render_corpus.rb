#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"
require_relative "support/ios_file_render_corpus"
require_relative "support/file_render_recipe_profile"

def fail_contract(message)
  warn "iOS file-render corpus failed: #{message}"
  exit 1
end

repo_root = File.expand_path("..", __dir__)
manifest_argument = ARGV.shift
output_argument = ARGV.shift
profile_id = ARGV.shift || "neutral"
if manifest_argument.nil? || output_argument.nil? || !ARGV.empty?
  fail_contract("usage: run_ios_file_render_corpus.rb MANIFEST OUTPUT_DIRECTORY [RECIPE_PROFILE]")
end
begin
  recipe = FileRenderRecipeProfile.fetch(profile_id)
rescue FileRenderRecipeProfile::ContractError => error
  fail_contract(error.message)
end

manifest_path = File.expand_path(manifest_argument, repo_root)
fail_contract("manifest is missing") unless File.file?(manifest_path)
begin
  output_root = IOSFileRenderCorpus.validated_output_root(
    output_argument,
    repo_root: repo_root,
  )
rescue IOSFileRenderCorpus::ContractError => error
  fail_contract(error.message)
end
fail_contract("output directory already exists") if File.exist?(output_root)

checker = File.join(repo_root, "scripts/check_image_quality_corpus.rb")
unless system("ruby", checker, manifest_path, out: $stdout, err: $stderr)
  fail_contract("image quality corpus contract did not pass")
end

begin
  manifest = YAML.safe_load(File.read(manifest_path), permitted_classes: [], aliases: false)
rescue Psych::Exception => error
  fail_contract("manifest YAML is invalid: #{error.message}")
end
unless manifest.is_a?(Hash) && manifest["schema"] == 2 && manifest["status"] == "ready"
  fail_contract("manifest must be ready schema 2")
end
assets = manifest["assets"]
fail_contract("manifest assets must be a non-empty list") unless assets.is_a?(Array) && !assets.empty?
corpus_root = File.realpath(File.expand_path(manifest.fetch("corpus_root"), repo_root))

pipeline_source = File.join(repo_root, "ios/Runner/IOSPhotoFileRenderer.swift")
portrait_source = File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift")
probe_source = File.join(repo_root, "scripts/support/render_ios_file_pipeline.swift")
[pipeline_source, portrait_source, probe_source].each do |source|
  fail_contract("required renderer source is missing: #{source}") unless File.file?(source)
end

quality_root = File.join(repo_root, ".quality")
FileUtils.mkdir_p(quality_root)
begin
  IOSFileRenderCorpus.validate_output_ancestry!(output_root, repo_root: repo_root)
rescue IOSFileRenderCorpus::ContractError => error
  fail_contract(error.message)
end

report_assets = []
Dir.mktmpdir(".ios-file-render-", quality_root) do |temporary_root|
  renderer = File.join(temporary_root, "ios-file-renderer")
  staged_output_root = File.join(temporary_root, "outputs")
  recipe_path = File.join(temporary_root, "recipe.json")
  File.write(recipe_path, JSON.generate(recipe))
  stdout, stderr, status = Open3.capture3(
    "/usr/bin/xcrun",
    "swiftc",
    "-parse-as-library",
    portrait_source,
    pipeline_source,
    probe_source,
    "-o",
    renderer,
  )
  detail = stderr.lines.first&.strip || stdout.lines.first&.strip
  fail_contract("renderer compilation failed: #{detail}") unless status.success?

  identity_stdout, identity_stderr, identity_status = Open3.capture3(renderer, "identity")
  fail_contract("renderer identity failed: #{identity_stderr.lines.first&.strip}") unless identity_status.success?
  begin
    renderer_identity = JSON.parse(identity_stdout)
  rescue JSON::ParserError
    fail_contract("renderer identity was not JSON")
  end

  FileUtils.mkdir_p(staged_output_root)
  assets.each_with_index do |asset, index|
    fail_contract("assets[#{index}] must be a mapping") unless asset.is_a?(Hash)
    asset_id = asset.fetch("id")
    source_path = File.realpath(File.expand_path(asset.fetch("file"), corpus_root))
    unless source_path.start_with?("#{corpus_root}/")
      fail_contract("#{asset_id} source resolves outside corpus_root")
    end
    source_hash_before = Digest::SHA256.file(source_path).hexdigest
    unless source_hash_before == asset.fetch("sha256")
      fail_contract("#{asset_id} source hash changed before rendering")
    end

    destination = File.join(staged_output_root, "#{asset_id}.jpg")
    render_stdout, render_stderr, render_status = Open3.capture3(
      renderer,
      source_path,
      destination,
      recipe_path,
    )
    unless render_status.success?
      detail = render_stderr.lines.first&.strip || render_stdout.lines.first&.strip
      fail_contract("#{asset_id} render failed: #{detail}")
    end
    fail_contract("#{asset_id} output is missing") unless File.file?(destination)
    begin
      render_result = JSON.parse(render_stdout)
      expected_dimensions = IOSFileRenderCorpus.expected_dimensions(asset.fetch("media"))
      IOSFileRenderCorpus.validate_render!(
        asset_id: asset_id,
        expected_dimensions: expected_dimensions,
        result: render_result,
      )
    rescue JSON::ParserError
      fail_contract("#{asset_id} renderer result was not JSON")
    rescue IOSFileRenderCorpus::ContractError => error
      fail_contract(error.message)
    end
    source_hash_after = Digest::SHA256.file(source_path).hexdigest
    unless source_hash_after == source_hash_before
      fail_contract("#{asset_id} source was modified by rendering")
    end

    report_assets << {
      "id" => asset_id,
      "tags" => asset.fetch("tags"),
      "source_sha256" => source_hash_before,
      "output_sha256" => Digest::SHA256.file(destination).hexdigest,
      "output" => render_result,
    }
  end

  tag_counts = report_assets
    .flat_map { |asset| asset.fetch("tags") }
    .each_with_object(Hash.new(0)) { |tag, counts| counts[tag] += 1 }
    .sort
    .to_h
  report = {
    "schema" => 1,
    "engineering_only" => true,
    "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
    "pipeline_source_sha256" => Digest::SHA256.file(pipeline_source).hexdigest,
    "portrait_source_sha256" => Digest::SHA256.file(portrait_source).hexdigest,
    "probe_source_sha256" => Digest::SHA256.file(probe_source).hexdigest,
    "renderer" => renderer_identity,
    "recipe_profile" => profile_id,
    "recipe" => recipe,
    "recipe_sha256" => Digest::SHA256.hexdigest(JSON.generate(recipe)),
    "asset_count" => report_assets.length,
    "tag_counts" => tag_counts,
    "assets" => report_assets,
  }
  File.write(
    File.join(staged_output_root, "engineering-report.json"),
    JSON.pretty_generate(report) + "\n",
  )
  FileUtils.mkdir_p(File.dirname(output_root))
  FileUtils.mv(staged_output_root, output_root)
end

puts "iOS file-render corpus passed: #{report_assets.length} assets"
