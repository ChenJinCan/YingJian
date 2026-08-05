#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

repo_root = File.expand_path("..", __dir__)
quality_root = File.join(repo_root, ".quality")
checker = File.join(repo_root, "scripts/check_image_quality_corpus.rb")
FileUtils.mkdir_p(quality_root)

def assert(condition, message)
  raise message unless condition
end

def run_checker(checker, repo_root, manifest_path, environment = {})
  relative = manifest_path.delete_prefix("#{repo_root}/")
  Open3.capture3(
    environment,
    RbConfig.ruby,
    checker,
    relative,
    chdir: repo_root,
  )
end

evidence = nil
begin
  Dir.mktmpdir("corpus-check-", quality_root) do |directory|
    corpus = File.join(directory, "corpus")
    evidence = File.join(quality_root, "evidence", File.basename(directory))
    FileUtils.mkdir_p(corpus)
    FileUtils.mkdir_p(evidence)
    source = File.join(directory, "fixture.ppm")
    image = File.join(corpus, "fixture.jpg")
    File.binwrite(source, "P6\n4 3\n255\n" + ([32, 96, 160].pack("C*") * 12))
    profile = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"
    _stdout, stderr, status = Open3.capture3(
      "sips", "-s", "format", "jpeg", "-m", profile, source, "--out", image
    )
    assert(status.success?, "fixture conversion failed: #{stderr}")
    evidence_file = File.join(evidence, "fixture-license.txt")
    File.write(evidence_file, "Generated fixture for corpus checker tests.\n")

    relative_directory = directory.delete_prefix("#{repo_root}/")
    manifest_path = File.join(directory, "manifest.yaml")
    manifest = {
      "schema" => 2,
      "status" => "ready",
      "corpus_root" => "#{relative_directory}/corpus",
      "required_assets" => 1,
      "required_single_assets" => 0,
      "required_group_sets" => 1,
      "required_members_per_group" => 1,
      "minimum_tag_counts" => {
        "no_face" => 1,
        "group_member" => 1,
        "jpeg" => 1,
        "srgb" => 1,
      },
      "assets" => [{
        "id" => "fixture-001",
        "file" => "fixture.jpg",
        "sha256" => Digest::SHA256.file(image).hexdigest,
        "tags" => ["no_face", "group_member", "jpeg", "srgb"],
        "group_id" => "group-001",
        "media" => {
          "format" => "jpeg",
          "width" => 4,
          "height" => 3,
          "color_space" => "srgb",
          "orientation" => 1,
        },
        "license" => {
          "source_type" => "generated_fixture",
          "rights_basis" => "project_generated_test_asset",
          "redistributable" => false,
          "evidence_ref" => evidence_file.delete_prefix("#{repo_root}/"),
        },
      }],
    }
    File.write(manifest_path, YAML.dump(manifest))

    stdout, stderr, status = run_checker(checker, repo_root, manifest_path)
    assert(status.success?, "valid media manifest failed: #{stdout}#{stderr}")

    oriented_image = File.join(corpus, "fixture-oriented.jpg")
    oriented_source = File.join(directory, "write-oriented.swift")
    File.write(
      oriented_source,
      <<~SWIFT,
        import Foundation
        import ImageIO
        import UniformTypeIdentifiers

        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL
        let source = CGImageSourceCreateWithURL(sourceURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let destination = CGImageDestinationCreateWithURL(
          outputURL,
          UTType.jpeg.identifier as CFString,
          1,
          nil
        )!
        CGImageDestinationAddImage(
          destination,
          image,
          [kCGImagePropertyOrientation: 6] as CFDictionary
        )
        precondition(CGImageDestinationFinalize(destination))
      SWIFT
    )
    oriented_binary = File.join(directory, "write-oriented")
    _stdout, stderr, status = Open3.capture3(
      "/usr/bin/xcrun", "swiftc", oriented_source, "-o", oriented_binary
    )
    assert(status.success?, "oriented fixture helper failed to compile: #{stderr}")
    _stdout, stderr, status = Open3.capture3(oriented_binary, image, oriented_image)
    assert(status.success?, "oriented fixture helper failed: #{stderr}")
    oriented_asset = Marshal.load(Marshal.dump(manifest["assets"][0]))
    oriented_asset["file"] = "fixture-oriented.jpg"
    oriented_asset["sha256"] = Digest::SHA256.file(oriented_image).hexdigest
    oriented_asset["tags"] = [
      "no_face", "group_member", "jpeg", "srgb", "exif_rotated",
    ]
    oriented_asset["media"]["orientation"] = 6
    manifest["assets"] = [oriented_asset]
    manifest["minimum_tag_counts"] = {
      "no_face" => 1,
      "group_member" => 1,
      "jpeg" => 1,
      "srgb" => 1,
      "exif_rotated" => 1,
    }
    File.write(manifest_path, YAML.dump(manifest))
    stdout, stderr, status = run_checker(checker, repo_root, manifest_path)
    assert(status.success?, "ImageIO orientation was not accepted: #{stdout}#{stderr}")

    manifest["assets"] = [Marshal.load(Marshal.dump(oriented_asset))]
    manifest["assets"][0]["file"] = "fixture.jpg"
    manifest["assets"][0]["sha256"] = Digest::SHA256.file(image).hexdigest
    manifest["assets"][0]["tags"] = ["no_face", "group_member", "jpeg", "srgb"]
    manifest["assets"][0]["media"]["orientation"] = 1
    manifest["minimum_tag_counts"] = {
      "no_face" => 1,
      "group_member" => 1,
      "jpeg" => 1,
      "srgb" => 1,
    }

    manifest["required_single_assets"] = 1
    File.write(manifest_path, YAML.dump(manifest))
    _stdout, stderr, status = run_checker(checker, repo_root, manifest_path)
    assert(!status.success?, "all-group corpus passed a single-asset requirement")
    assert(stderr.include?("single asset count 0 must equal 1"), "single asset count was not exact")
    manifest["required_single_assets"] = 0

    manifest["required_members_per_group"] = 2
    File.write(manifest_path, YAML.dump(manifest))
    _stdout, stderr, status = run_checker(checker, repo_root, manifest_path)
    assert(!status.success?, "undersized group passed an exact member requirement")
    assert(stderr.include?("member count 1 must equal 2"), "group member count was not exact")
    manifest["required_members_per_group"] = 1
    File.write(manifest_path, YAML.dump(manifest))

    empty_path = File.join(directory, "empty-path")
    FileUtils.mkdir_p(empty_path)
    File.symlink("/usr/bin/uname", File.join(empty_path, "uname"))
    _stdout, stderr, status = run_checker(
      checker,
      repo_root,
      manifest_path,
      {"PATH" => empty_path},
    )
    assert(!status.success?, "manifest passed without the media probe")
    assert(
      stderr.include?("media probe unavailable"),
      "missing media probe was not explicit: #{stderr}",
    )

    manifest["assets"][0]["media"]["width"] = 5
    File.write(manifest_path, YAML.dump(manifest))
    _stdout, stderr, status = run_checker(checker, repo_root, manifest_path)
    assert(!status.success?, "incorrect declared width passed")
    assert(stderr.include?("media.width does not match"), "width mismatch was not explicit")

    manifest["assets"][0]["media"]["width"] = 4
    manifest["assets"][0]["tags"] << "png"
    File.write(manifest_path, YAML.dump(manifest))
    _stdout, stderr, status = run_checker(checker, repo_root, manifest_path)
    assert(!status.success?, "mislabeled PNG passed")
    assert(stderr.include?("tagged png but is not PNG"), "format mismatch was not explicit")

    manifest["assets"][0]["tags"] = [
      "no_face", "group_member", "jpeg", "srgb", "high_resolution",
    ]
    manifest["minimum_tag_counts"]["high_resolution"] = 1
    File.write(manifest_path, YAML.dump(manifest))
    _stdout, stderr, status = run_checker(checker, repo_root, manifest_path)
    assert(!status.success?, "tiny high-resolution asset passed")
    assert(stderr.include?("below 24 MP"), "resolution mismatch was not explicit")

    outside_image = File.join(directory, "outside.jpg")
    FileUtils.cp(image, outside_image)
    FileUtils.rm_f(image)
    File.symlink("../outside.jpg", image)
    manifest["assets"][0]["sha256"] = Digest::SHA256.file(outside_image).hexdigest
    File.write(manifest_path, YAML.dump(manifest))
    _stdout, stderr, status = run_checker(checker, repo_root, manifest_path)
    assert(!status.success?, "corpus symlink escape passed")
    assert(stderr.include?("resolves outside corpus_root"), "symlink escape was not explicit")

    escaped_root = File.join(directory, "escaped-corpus")
    File.symlink(Dir.tmpdir, escaped_root)
    manifest["corpus_root"] = escaped_root.delete_prefix("#{repo_root}/")
    manifest["assets"] = []
    File.write(manifest_path, YAML.dump(manifest))
    _stdout, stderr, status = run_checker(checker, repo_root, manifest_path)
    assert(!status.success?, "corpus root symlink escape passed")
    assert(
      stderr.include?("corpus_root resolves outside the repository"),
      "corpus root symlink escape was not explicit",
    )
  end
ensure
  FileUtils.rm_rf(evidence) if evidence
end

puts "Image quality corpus checker tests passed."
