#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

require_relative "support/portrait_engineering_corpus"

class PortraitEngineeringDiagnosticTest
  def self.run
    repo_root = File.expand_path("..", __dir__)
    quality_root = File.join(repo_root, ".quality")
    FileUtils.mkdir_p(quality_root)
    Dir.mktmpdir("portrait-diagnostic-test-", quality_root) do |directory|
      manifest_path, report_path = build_fixture(repo_root, directory)
      output = File.join(directory, "diagnostic")
      stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(repo_root, "scripts/build_portrait_engineering_diagnostic.rb"),
        report_path,
        manifest_path,
        output,
        "--seed",
        "stable-seed",
      )
      raise "valid diagnostic failed: #{stdout}#{stderr}" unless status.success?

      participant = File.join(output, "participant-package")
      index = File.read(File.join(participant, "index.html"))
      key = JSON.parse(File.read(File.join(output, "diagnostic-key.json")))
      raise "diagnostic disclaimer missing" unless index.include?("不能用于冻结生产候选")
      raise "asset identity leaked" if index.include?("portrait-001")
      raise "absolute quality path leaked" if index.include?(directory)
      raise "wrong item count" unless key.fetch("items").length == 48
      raise "wrong sanitized image count" unless Dir.glob(File.join(participant, "images", "*.png")).length == 192
      raise "full-resolution zoom links are incomplete" unless index.scan(/href="images\//).length == 192
      raise "private key leaked to participant" if File.exist?(File.join(participant, "diagnostic-key.json"))
      raise "diagnostic scope is not machine-readable" unless
        key["engineering_only"] == true &&
          key["evidence_scope"] == "local-desktop-engineering" &&
          key["physical_device"] == false &&
          key["freeze_eligible"] == false &&
          key["review_max_edge"] == 2048

      second_output = File.join(directory, "diagnostic-repeat")
      _stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(repo_root, "scripts/build_portrait_engineering_diagnostic.rb"),
        report_path,
        manifest_path,
        second_output,
        "--seed",
        "stable-seed",
      )
      raise "deterministic rebuild failed: #{stderr}" unless status.success?
      raise "same seed changed the diagnostic key" unless
        File.read(File.join(output, "diagnostic-key.json")) ==
          File.read(File.join(second_output, "diagnostic-key.json"))

      original_manifest = File.read(manifest_path)
      original_report = File.read(report_path)
      supplemental_manifest = YAML.safe_load(
        original_manifest,
        permitted_classes: [],
        aliases: false,
      )
      supplemental_asset = Marshal.load(
        Marshal.dump(supplemental_manifest.fetch("assets").first),
      )
      supplemental_asset["id"] = "portrait-supplemental-001"
      supplemental_asset["tags"] = supplemental_asset.fetch("tags") + [
        PortraitEngineeringCorpus::SUPPLEMENTAL_TAG,
      ]
      supplemental_manifest.fetch("assets") << supplemental_asset
      File.write(manifest_path, YAML.dump(supplemental_manifest))
      supplemental_report = JSON.parse(original_report)
      supplemental_report["manifest_sha256"] = Digest::SHA256.file(
        manifest_path,
      ).hexdigest
      File.write(report_path, JSON.pretty_generate(supplemental_report))
      _stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(repo_root, "scripts/build_portrait_engineering_diagnostic.rb"),
        report_path,
        manifest_path,
        File.join(directory, "supplemental-diagnostic"),
      )
      raise "supplemental manifest asset blocked the diagnostic: #{stderr}" unless status.success?
      File.write(manifest_path, original_manifest)
      File.write(report_path, original_report)

      stale_report = JSON.parse(original_report)
      stale_report["contract_source_sha256"] = "0" * 64
      File.write(report_path, JSON.pretty_generate(stale_report))
      _stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(repo_root, "scripts/build_portrait_engineering_diagnostic.rb"),
        report_path,
        manifest_path,
        File.join(directory, "stale-diagnostic"),
      )
      raise "stale report entered the diagnostic" if status.success?
      raise "stale source failure was not explicit" unless stderr.include?("stale")
      File.write(report_path, original_report)

      incomplete_report = JSON.parse(original_report)
      incomplete_report.fetch("assets").pop
      File.write(report_path, JSON.pretty_generate(incomplete_report))
      _stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(repo_root, "scripts/build_portrait_engineering_diagnostic.rb"),
        report_path,
        manifest_path,
        File.join(directory, "incomplete-diagnostic"),
      )
      raise "incomplete matrix entered the diagnostic" if status.success?
      raise "incomplete matrix failure was not explicit" unless stderr.include?("exactly 48")
      File.write(report_path, original_report)

      mismatched_source_report = JSON.parse(original_report)
      mismatched_source_report.fetch("assets").first["source_sha256"] = "0" * 64
      File.write(report_path, JSON.pretty_generate(mismatched_source_report))
      _stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(repo_root, "scripts/build_portrait_engineering_diagnostic.rb"),
        report_path,
        manifest_path,
        File.join(directory, "mismatched-source-diagnostic"),
      )
      raise "mismatched source entered the diagnostic" if status.success?
      raise "source mismatch failure was not explicit" unless stderr.include?("source_sha256")
      File.write(report_path, original_report)

      stale_metrics_report = JSON.parse(original_report)
      stale_default_metrics = stale_metrics_report.fetch("assets").first
        .fetch("effect_metrics").fetch("default")
      stale_default_metrics["mean_absolute_difference"] += 0.000001
      File.write(report_path, JSON.pretty_generate(stale_metrics_report))
      _stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(repo_root, "scripts/build_portrait_engineering_diagnostic.rb"),
        report_path,
        manifest_path,
        File.join(directory, "stale-metrics-diagnostic"),
      )
      raise "stale effect metrics entered the diagnostic" if status.success?
      raise "stale metrics failure was not explicit" unless stderr.include?("effect metrics")
      File.write(report_path, original_report)

      duplicate_pixel_report = JSON.parse(original_report)
      duplicate_asset = duplicate_pixel_report.fetch("assets").first
      duplicate_directory = File.join(File.dirname(report_path), duplicate_asset.fetch("id"))
      duplicate_default = File.join(duplicate_directory, "default.jpg")
      original_default = File.binread(duplicate_default)
      baseline_bytes = File.binread(File.join(duplicate_directory, "baseline.jpg"))
      File.binwrite(duplicate_default, baseline_bytes + "encoded-but-pixel-identical")
      duplicate_asset.fetch("output_sha256")["default"] = Digest::SHA256.file(duplicate_default).hexdigest
      File.write(report_path, JSON.pretty_generate(duplicate_pixel_report))
      _stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(repo_root, "scripts/build_portrait_engineering_diagnostic.rb"),
        report_path,
        manifest_path,
        File.join(directory, "duplicate-pixel-diagnostic"),
      )
      raise "pixel-identical applied variants entered the diagnostic" if status.success?
      unless stderr.include?("effect metrics") || stderr.include?("pixel-distinct")
        raise "pixel identity failure was not explicit"
      end
      File.binwrite(duplicate_default, original_default)
      File.write(report_path, original_report)

      report = JSON.parse(File.read(report_path))
      broken_asset = report.fetch("assets").first
      broken_path = File.join(File.dirname(report_path), broken_asset.fetch("id"), "default.jpg")
      File.binwrite(broken_path, "not-a-jpeg")
      broken_asset.fetch("output_sha256")["default"] = Digest::SHA256.file(broken_path).hexdigest
      File.write(report_path, JSON.pretty_generate(report))
      _stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(repo_root, "scripts/build_portrait_engineering_diagnostic.rb"),
        report_path,
        manifest_path,
        File.join(directory, "broken-diagnostic"),
      )
      raise "non-JPEG output entered the visual diagnostic" if status.success?
      raise "broken image failure was not explicit" unless stderr.include?("JPEG")
    end
    puts "Portrait engineering diagnostic tests passed"
  end

  def self.build_fixture(repo_root, directory)
    fixture_bytes = generate_fixture_jpegs(directory)
    fixture_metrics = measure_fixture_metrics(repo_root, directory)
    source_sha256 = Digest::SHA256.hexdigest("fixture-source")
    manifest = {
      "status" => "ready",
      "portrait_required_assets" => 48,
      "portrait_minimum_single_assets" => 36,
      "portrait_minimum_skin_tone_counts" => {
        "skin_tone_light" => 2,
        "skin_tone_medium" => 2,
        "skin_tone_deep" => 2,
      },
      "portrait_roles" => %w[portrait_single portrait_multi no_face],
      "assets" => 48.times.map do |index|
        role = index < 36 ? "portrait_single" : (index < 40 ? "portrait_multi" : "no_face")
        {
          "id" => format("portrait-%03d", index + 1),
          "sha256" => source_sha256,
          "tags" => [
            role,
            ("skin_tone_light" if index < 2),
            ("skin_tone_medium" if index >= 2 && index < 4),
            ("skin_tone_deep" if index >= 4 && index < 6),
          ].compact,
          "media" => {
            "format" => "jpeg",
            "width" => 64,
            "height" => 64,
            "color_space" => "srgb",
            "orientation" => 1,
          },
        }
      end,
    }
    manifest_path = File.join(directory, "manifest.yaml")
    File.write(manifest_path, YAML.dump(manifest))

    assets = manifest.fetch("assets").map.with_index do |asset, index|
      asset_directory = File.join(directory, "run", asset.fetch("id"))
      FileUtils.mkdir_p(asset_directory)
      applied = index < 40
      bytes = {
        "baseline" => fixture_bytes.fetch("baseline"),
        "off" => fixture_bytes.fetch("baseline"),
        "default" => applied ? fixture_bytes.fetch("default") : fixture_bytes.fetch("baseline"),
        "high_safe" => applied ? fixture_bytes.fetch("high_safe") : fixture_bytes.fetch("baseline"),
      }
      files = {
        "baseline" => "baseline.jpg",
        "off" => "off.jpg",
        "default" => "default.jpg",
        "high_safe" => "high-safe.jpg",
      }
      files.each { |name, file| File.binwrite(File.join(asset_directory, file), bytes.fetch(name)) }
      {
        "id" => asset.fetch("id"),
        "source_sha256" => asset.fetch("sha256"),
        "classification" => applied ? "applied" : "preserved",
        "output_sha256" => files.to_h do |name, file|
          [name, Digest::SHA256.file(File.join(asset_directory, file)).hexdigest]
        end,
        "effect_metrics" => fixture_metrics.fetch(applied ? "applied" : "preserved"),
      }
    end
    report = {
      "schema" => 4,
      "engineering_only" => true,
      "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
      "retoucher_source_sha256" => Digest::SHA256.file(File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift")).hexdigest,
      "renderer_source_sha256" => Digest::SHA256.file(File.join(repo_root, "scripts/support/render_portrait_engineering_candidate.swift")).hexdigest,
      "metrics_source_sha256" => Digest::SHA256.file(File.join(repo_root, "scripts/support/portrait_engineering_metrics.swift")).hexdigest,
      "runner_source_sha256" => Digest::SHA256.file(File.join(repo_root, "scripts/run_portrait_engineering_corpus.rb")).hexdigest,
      "contract_source_sha256" => Digest::SHA256.file(File.join(repo_root, "scripts/support/portrait_engineering_corpus.rb")).hexdigest,
      "candidate" => {
        "candidateKind" => "vision-landmarks-geometry-roi",
        "effectVersion" => "ios-geometry-retouch-candidate-v4",
        "strengths" => { "default" => 0.35, "high-safe" => 0.55, "off" => 0 },
      },
      "asset_count" => 48,
      "counts" => { "applied" => 40, "preserved" => 8 },
      "assets" => assets,
    }
    report_path = File.join(directory, "run", "engineering-report.json")
    File.write(report_path, JSON.pretty_generate(report))
    [manifest_path, report_path]
  end

  def self.generate_fixture_jpegs(directory)
    source = File.join(directory, "fixture-images.swift")
    binary = File.join(directory, "fixture-images")
    File.write(
      source,
      <<~SWIFT,
        import CoreImage
        import Foundation

        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let context = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let baseline = CIImage(color: CIColor(red: 0.25, green: 0.35, blue: 0.45)).cropped(to: extent)
        let defaultPatch = CIImage(color: CIColor(red: 0.28, green: 0.38, blue: 0.48))
          .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let highPatch = CIImage(color: CIColor(red: 0.28, green: 0.38, blue: 0.48))
          .cropped(to: CGRect(x: 0, y: 0, width: 17, height: 16))
        let images: [(String, CIImage)] = [
          ("baseline", baseline),
          ("default", defaultPatch.composited(over: baseline).cropped(to: extent)),
          ("high-safe", highPatch.composited(over: baseline).cropped(to: extent)),
        ]
        for (name, image) in images {
          try context.writeJPEGRepresentation(
            of: image,
            to: output.appendingPathComponent("fixture-\\(name).jpg"),
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
          )
        }
      SWIFT
    )
    _stdout, stderr, status = Open3.capture3("/usr/bin/xcrun", "swiftc", source, "-o", binary)
    raise "fixture image compiler failed: #{stderr}" unless status.success?
    _stdout, stderr, status = Open3.capture3(binary, directory)
    raise "fixture images failed: #{stderr}" unless status.success?
    {
      "baseline" => File.binread(File.join(directory, "fixture-baseline.jpg")),
      "default" => File.binread(File.join(directory, "fixture-default.jpg")),
      "high_safe" => File.binread(File.join(directory, "fixture-high-safe.jpg")),
    }
  end

  def self.measure_fixture_metrics(repo_root, directory)
    renderer = File.join(directory, "fixture-metric-renderer")
    _stdout, stderr, status = Open3.capture3(
      "/usr/bin/xcrun",
      "swiftc",
      "-parse-as-library",
      File.join(repo_root, "ios/Runner/IOSPortraitRetoucher.swift"),
      File.join(repo_root, "scripts/support/portrait_engineering_metrics.swift"),
      File.join(repo_root, "scripts/support/render_portrait_engineering_candidate.swift"),
      "-o",
      renderer,
    )
    raise "fixture metric renderer failed to compile: #{stderr}" unless status.success?
    baseline = File.join(directory, "fixture-baseline.jpg")
    metric_set = lambda do |default_path, high_safe_path|
      stdout, stderr, status = Open3.capture3(
        renderer,
        "metrics",
        baseline,
        baseline,
        default_path,
        high_safe_path,
      )
      raise "fixture metrics failed: #{stderr}" unless status.success?
      JSON.parse(stdout)
    end
    {
      "applied" => metric_set.call(
        File.join(directory, "fixture-default.jpg"),
        File.join(directory, "fixture-high-safe.jpg"),
      ),
      "preserved" => metric_set.call(baseline, baseline),
    }
  end
end

PortraitEngineeringDiagnosticTest.run
