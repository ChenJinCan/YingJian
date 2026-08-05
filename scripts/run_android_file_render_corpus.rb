#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "tmpdir"
require "yaml"
require_relative "support/android_file_render_corpus"
require_relative "support/file_render_recipe_profile"

def fail_contract(message)
  warn "Android file-render corpus failed: #{message}"
  exit 1
end

def capture!(*command)
  stdout, stderr, status = Open3.capture3(*command)
  unless status.success?
    detail = stderr.lines.first&.strip || stdout.lines.first&.strip
    raise AndroidFileRenderCorpus::ContractError, "command failed: #{detail}"
  end
  stdout
end

repo_root = File.expand_path("..", __dir__)
manifest_argument = ARGV.shift
output_argument = ARGV.shift
profile_id = ARGV.shift || "neutral"
if manifest_argument.nil? || output_argument.nil? || !ARGV.empty?
  fail_contract("usage: run_android_file_render_corpus.rb MANIFEST OUTPUT_DIRECTORY [RECIPE_PROFILE]")
end
begin
  recipe = FileRenderRecipeProfile.fetch(profile_id)
rescue FileRenderRecipeProfile::ContractError => error
  fail_contract(error.message)
end

manifest_path = File.expand_path(manifest_argument, repo_root)
fail_contract("manifest is missing") unless File.file?(manifest_path)
begin
  output_root = AndroidFileRenderCorpus.validated_output_root(
    output_argument,
    repo_root: repo_root,
  )
rescue AndroidFileRenderCorpus::ContractError => error
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

android_sdk = ENV["ANDROID_HOME"] || ENV["ANDROID_SDK_ROOT"] || File.join(Dir.home, "Library/Android/sdk")
adb = File.join(android_sdk, "platform-tools/adb")
fail_contract("adb is unavailable") unless File.executable?(adb)
device_lines = capture!(adb, "devices").lines.drop(1).map(&:strip).reject(&:empty?)
devices = device_lines.each_with_object([]) do |line, ready|
  serial, state = line.split(/\s+/, 3)
  ready << serial if state == "device"
end
fail_contract("exactly one ready Android device or emulator is required") unless devices.length == 1
serial = devices.first

java_home = ENV["JAVA_HOME"]
android_studio_java = "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
java_home = android_studio_java if java_home.nil? && File.directory?(android_studio_java)
fail_contract("JAVA_HOME is unavailable") if java_home.nil? || !File.directory?(java_home)

android_root = File.join(repo_root, "android")
build_environment = { "JAVA_HOME" => java_home }
unless system(
  build_environment,
  "./gradlew",
  ":app:assembleDebug",
  ":app:assembleDebugAndroidTest",
  chdir: android_root,
  out: $stdout,
  err: $stderr
)
  fail_contract("Android app or test APK build failed")
end
app_apk = File.join(repo_root, "build/app/outputs/apk/debug/app-debug.apk")
test_apk = File.join(repo_root, "build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk")
fail_contract("debug app APK is missing") unless File.file?(app_apk)
fail_contract("debug test APK is missing") unless File.file?(test_apk)

package_name = "com.babycompany.yingjian"
test_runner = "#{package_name}.test/androidx.test.runner.AndroidJUnitRunner"
test_method = "#{package_name}.AndroidFileRenderCorpusInstrumentedTest#fixedCorpusTraversesTheProductionFileExporter"
remote_root = "/data/local/tmp/yingjian-file-render-#{Process.pid}-#{SecureRandom.hex(4)}"
quality_root = File.join(repo_root, ".quality")
FileUtils.mkdir_p(quality_root)
begin
  AndroidFileRenderCorpus.validate_output_ancestry!(output_root, repo_root: repo_root)
rescue AndroidFileRenderCorpus::ContractError => error
  fail_contract(error.message)
end

production_sources = %w[
  AndroidPhotoExporter.kt
  ImagePipelineV1.kt
  ArgbPixelTransformer.kt
].each_with_object({}) do |name, hashes|
  path = File.join(repo_root, "android/app/src/main/kotlin/com/babycompany/yingjian", name)
  fail_contract("production source is missing: #{name}") unless File.file?(path)
  hashes[name] = Digest::SHA256.file(path).hexdigest
end
test_source = File.join(
  repo_root,
  "android/app/src/androidTest/kotlin/com/babycompany/yingjian/AndroidFileRenderCorpusInstrumentedTest.kt",
)

begin
  capture!(adb, "-s", serial, "install", "-r", app_apk)
  capture!(adb, "-s", serial, "install", "-r", test_apk)
  capture!(adb, "-s", serial, "shell", "mkdir", "-p", "#{remote_root}/input")

  Dir.mktmpdir(".android-file-render-", quality_root) do |temporary_root|
    staged_output_root = File.join(temporary_root, "outputs")
    FileUtils.mkdir_p(staged_output_root)
    index_assets = assets.map.with_index do |asset, index|
      fail_contract("assets[#{index}] must be a mapping") unless asset.is_a?(Hash)
      asset_id = asset.fetch("id")
      fail_contract("#{asset_id} has an unsafe id") unless asset_id.match?(/\A[a-z0-9-]+\z/)
      source_path = File.realpath(File.expand_path(asset.fetch("file"), corpus_root))
      unless source_path.start_with?("#{corpus_root}/")
        fail_contract("#{asset_id} source resolves outside corpus_root")
      end
      source_hash = Digest::SHA256.file(source_path).hexdigest
      fail_contract("#{asset_id} source hash changed") unless source_hash == asset.fetch("sha256")
      extension = File.extname(source_path).downcase
      device_name = "#{asset_id}#{extension}"
      capture!(adb, "-s", serial, "push", source_path, "#{remote_root}/input/#{device_name}")
      { "id" => asset_id, "file" => device_name }
    end
    index_path = File.join(temporary_root, "corpus-index.json")
    File.write(
      index_path,
      JSON.generate(
        "recipe_profile" => profile_id,
        "pipeline" => recipe,
        "assets" => index_assets,
      ),
    )
    capture!(adb, "-s", serial, "push", index_path, "#{remote_root}/corpus-index.json")

    capture!(
      adb, "-s", serial, "shell", "run-as", package_name,
      "rm", "-rf", "cache/file-render-corpus-input", "files/file-render-corpus-output",
      "files/file-render-corpus-report.json",
    )
    capture!(adb, "-s", serial, "shell", "run-as", package_name, "mkdir", "cache/file-render-corpus-input")
    capture!(
      adb, "-s", serial, "shell", "run-as", package_name,
      "cp", "-R", "#{remote_root}/input/.", "cache/file-render-corpus-input/",
    )
    capture!(
      adb, "-s", serial, "shell", "run-as", package_name,
      "cp", "#{remote_root}/corpus-index.json", "cache/file-render-corpus-index.json",
    )

    instrumentation = capture!(
      adb, "-s", serial, "shell", "am", "instrument", "-w", "-r",
      "-e", "fileRenderCorpus", "true", "-e", "class", test_method, test_runner,
    )
    unless instrumentation.include?("OK (1 test)") && !instrumentation.include?("FAILURES!!!")
      fail_contract("corpus instrumentation did not pass")
    end

    report_json = capture!(
      adb, "-s", serial, "exec-out", "run-as", package_name,
      "cat", "files/file-render-corpus-report.json",
    )
    begin
      device_report = JSON.parse(report_json)
    rescue JSON::ParserError
      fail_contract("device report was not JSON")
    end
    begin
      indexed_results = AndroidFileRenderCorpus.index_results!(
        device_report.fetch("assets"),
        expected_ids: assets.map { |asset| asset.fetch("id") },
      )
    rescue AndroidFileRenderCorpus::ContractError => error
      fail_contract(error.message)
    end

    report_assets = assets.map do |asset|
      asset_id = asset.fetch("id")
      result = indexed_results.fetch(asset_id)
      begin
        AndroidFileRenderCorpus.validate_result!(
          asset_id: asset_id,
          expected_dimensions: AndroidFileRenderCorpus.expected_dimensions(asset.fetch("media")),
          expected_source_sha256: asset.fetch("sha256"),
          result: result,
        )
      rescue AndroidFileRenderCorpus::ContractError => error
        fail_contract(error.message)
      end
      output_data = capture!(
        adb, "-s", serial, "exec-out", "run-as", package_name,
        "cat", "files/file-render-corpus-output/#{asset_id}.jpg",
      )
      output_path = File.join(staged_output_root, "#{asset_id}.jpg")
      File.binwrite(output_path, output_data.b)
      unless Digest::SHA256.file(output_path).hexdigest == result.fetch("output_sha256")
        fail_contract("#{asset_id} pulled output hash changed")
      end
      result.merge("tags" => asset.fetch("tags"))
    end

    final_report = device_report.merge(
      "recipe" => recipe,
      "recipe_sha256" => Digest::SHA256.hexdigest(JSON.generate(recipe)),
      "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
      "production_source_sha256" => production_sources,
      "instrumentation_source_sha256" => Digest::SHA256.file(test_source).hexdigest,
      "runner_source_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
      "source_commit" => capture!("git", "-C", repo_root, "rev-parse", "HEAD").strip,
      "device_serial" => serial,
      "build_fingerprint" => capture!(adb, "-s", serial, "shell", "getprop", "ro.build.fingerprint").strip,
      "asset_count" => report_assets.length,
      "assets" => report_assets,
    )
    File.write(
      File.join(staged_output_root, "engineering-report.json"),
      JSON.pretty_generate(final_report) + "\n",
    )
    FileUtils.mkdir_p(File.dirname(output_root))
    FileUtils.mv(staged_output_root, output_root)
  end
rescue AndroidFileRenderCorpus::ContractError => error
  fail_contract(error.message)
ensure
  system(adb, "-s", serial, "shell", "rm", "-rf", remote_root, out: File::NULL, err: File::NULL)
  system(
    adb, "-s", serial, "shell", "run-as", package_name,
    "rm", "-rf", "cache/file-render-corpus-input", "cache/file-render-corpus-index.json",
    "files/file-render-corpus-output", "files/file-render-corpus-report.json",
    out: File::NULL,
    err: File::NULL,
  )
end

puts "Android file-render corpus passed: #{assets.length} assets"
