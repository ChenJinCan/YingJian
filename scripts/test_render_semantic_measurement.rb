#!/usr/bin/env ruby

require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class RenderSemanticMeasurementTest < Minitest::Test
  def test_measures_normalized_srgb_luma_and_clipping
    source = File.expand_path(
      "support/measure_render_semantics.swift",
      __dir__,
    )
    Dir.mktmpdir("render-semantic-test-") do |root|
      fixture_source = File.join(root, "fixture.swift")
      File.write(fixture_source, fixture_generator_source)
      fixture = compile(fixture_source, File.join(root, "fixture"))
      analyzer = compile(source, File.join(root, "analyzer"))
      {
        "black" => [0.0, 1.0, 0.0, 0.5],
        "white" => [1.0, 0.0, 1.0, 0.5],
        "red" => [0.2126, 0.0, 0.0, 0.5],
        "middle" => [128.0 / 255.0, 0.0, 0.0, 0.5 / 255.0],
      }.each do |name, expected|
        image = File.join(root, "#{name}.png")
        system(fixture, name, image) || flunk("fixture generation failed")
        stdout, stderr, status = Open3.capture3(analyzer, image, "512")
        assert status.success?, stderr
        result = JSON.parse(stdout)
        assert_in_delta expected[0], result.fetch("mean_luma"), 1e-6
        assert_in_delta expected[1], result.fetch("black_clip_ratio"), 1e-6
        assert_in_delta expected[2], result.fetch("white_clip_ratio"), 1e-6
        assert_in_delta expected[3], result.fetch("mean_rgb_midpoint_distance"), 1e-6
        assert_equal 1, result.fetch("sample_pixels")
      end
    end
  end

  private

  def compile(source, output)
    stdout, stderr, status = Open3.capture3(
      "/usr/bin/xcrun", "swiftc", "-parse-as-library", source, "-o", output,
    )
    assert status.success?, stderr.empty? ? stdout : stderr
    output
  end

  def fixture_generator_source
    <<~SWIFT
      import CoreGraphics
      import Foundation
      import ImageIO
      import UniformTypeIdentifiers

      @main
      enum FixtureGenerator {
        static func main() throws {
          let colors: [String: [UInt8]] = [
            "black": [0, 0, 0, 255],
            "white": [255, 255, 255, 255],
            "red": [255, 0, 0, 255],
            "middle": [128, 128, 128, 255],
          ]
          let bytes = colors[CommandLine.arguments[1]]!
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
          let provider = CGDataProvider(data: Data(bytes) as CFData)!
          let image = CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
          )!
          let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL,
            UTType.png.identifier as CFString, 1, nil
          )!
          CGImageDestinationAddImage(destination, image, nil)
          precondition(CGImageDestinationFinalize(destination))
        }
      }
    SWIFT
  end
end
