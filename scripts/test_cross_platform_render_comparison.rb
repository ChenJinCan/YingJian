#!/usr/bin/env ruby

require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class CrossPlatformRenderComparisonTest < Minitest::Test
  def test_reports_zero_for_identical_pixels_and_known_error_for_red_vs_black
    repo_root = File.expand_path("..", __dir__)
    comparator_source = File.join(
      repo_root,
      "scripts/support/compare_cross_platform_renders.swift",
    )

    Dir.mktmpdir("cross-platform-render-test-") do |root|
      fixture_source = File.join(root, "fixture.swift")
      File.write(fixture_source, fixture_generator_source)
      fixture_generator = File.join(root, "fixture-generator")
      comparator = File.join(root, "render-comparator")
      compile!(fixture_source, output: fixture_generator)
      compile!(comparator_source, output: comparator)

      black = File.join(root, "black.png")
      red = File.join(root, "red.png")
      run!(fixture_generator, black, "0", "0", "0")
      run!(fixture_generator, red, "255", "0", "0")

      identical = JSON.parse(run!(comparator, black, black, "32"))
      assert_equal(0.0, identical.fetch("mean_absolute_error"))
      assert_equal(0.0, identical.fetch("root_mean_square_error"))
      assert_nil(identical.fetch("psnr_db"))
      assert_equal(1.0, identical.fetch("exact_pixel_ratio"))
      assert_equal(0.0, identical.fetch("pixel_ratio_over_4_code_values"))
      assert_equal(0.0, identical.fetch("pixel_ratio_over_8_code_values"))

      changed = JSON.parse(run!(comparator, black, red, "32"))
      assert_in_delta(1.0 / 3.0, changed.fetch("mean_absolute_error"), 0.000_001)
      assert_in_delta(Math.sqrt(1.0 / 3.0), changed.fetch("root_mean_square_error"), 0.000_001)
      assert_in_delta(4.771_213, changed.fetch("psnr_db"), 0.000_01)
      assert_equal([1.0, 0.0, 0.0], changed.fetch("mean_absolute_rgb"))
      assert_equal([1.0, 0.0, 0.0], changed.fetch("mean_rgb_bias"))
      assert_equal(1.0, changed.fetch("p95_max_channel_error"))
      assert_equal(1.0, changed.fetch("pixel_ratio_over_4_code_values"))
      assert_equal(1.0, changed.fetch("pixel_ratio_over_8_code_values"))
    end
  end

  private

  def compile!(source, output:)
    _, stderr, status = Open3.capture3(
      "/usr/bin/xcrun",
      "swiftc",
      "-parse-as-library",
      source,
      "-o",
      output,
    )
    assert(status.success?, "Swift compilation failed: #{stderr}")
  end

  def run!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    assert(status.success?, "Command failed: #{stderr}")
    stdout
  end

  def fixture_generator_source
    <<~SWIFT
      import CoreGraphics
      import Foundation
      import ImageIO

      @main
      enum FixtureGenerator {
        static func main() throws {
          guard CommandLine.arguments.count == 5 else { throw FixtureError.arguments }
          let url = URL(fileURLWithPath: CommandLine.arguments[1])
          let components = CommandLine.arguments[2...4].compactMap(UInt8.init)
          guard components.count == 3 else { throw FixtureError.arguments }
          let bytes = [components[0], components[1], components[2], UInt8(255)]
          let data = Data(bytes)
          guard
            let provider = CGDataProvider(data: data as CFData),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let image = CGImage(
              width: 1,
              height: 1,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: 4,
              space: colorSpace,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
            ),
            let destination = CGImageDestinationCreateWithURL(
              url as CFURL,
              "public.png" as CFString,
              1,
              nil
            )
          else { throw FixtureError.image }
          CGImageDestinationAddImage(destination, image, nil)
          guard CGImageDestinationFinalize(destination) else { throw FixtureError.image }
        }
      }

      enum FixtureError: Error { case arguments, image }
    SWIFT
  end
end
