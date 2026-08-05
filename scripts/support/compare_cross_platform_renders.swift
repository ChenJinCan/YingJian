import CoreGraphics
import CoreImage
import Foundation

private enum RenderComparisonError: Error {
  case invalidArguments
  case unreadableImage
  case dimensionMismatch
  case unavailableColorSpace
  case renderFailed
}

@main
private enum CrossPlatformRenderComparator {
  static func main() throws {
    guard
      CommandLine.arguments.count == 4,
      let maxEdge = Int(CommandLine.arguments[3]),
      (1...2_048).contains(maxEdge)
    else {
      throw RenderComparisonError.invalidArguments
    }

    let first = try normalizedImage(at: CommandLine.arguments[1])
    let second = try normalizedImage(at: CommandLine.arguments[2])
    let firstExtent = first.extent.integral
    let secondExtent = second.extent.integral
    guard firstExtent.size == secondExtent.size else {
      throw RenderComparisonError.dimensionMismatch
    }
    let target = sampledSize(for: firstExtent.size, maxEdge: maxEdge)
    let firstBytes = try render(first, sourceExtent: firstExtent, target: target)
    let secondBytes = try render(second, sourceExtent: secondExtent, target: target)
    try printJSON(metrics(first: firstBytes, second: secondBytes, size: target))
  }

  private static func normalizedImage(at path: String) throws -> CIImage {
    guard let image = CIImage(
      contentsOf: URL(fileURLWithPath: path),
      options: [.applyOrientationProperty: true]
    ) else {
      throw RenderComparisonError.unreadableImage
    }
    let extent = image.extent.integral
    guard extent.width > 0, extent.height > 0, !extent.isInfinite else {
      throw RenderComparisonError.unreadableImage
    }
    return image.transformed(
      by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
    )
  }

  private static func sampledSize(for source: CGSize, maxEdge: Int) -> CGSize {
    let scale = min(1, CGFloat(maxEdge) / max(source.width, source.height))
    return CGSize(
      width: max(1, (source.width * scale).rounded()),
      height: max(1, (source.height * scale).rounded())
    )
  }

  private static func render(
    _ image: CIImage,
    sourceExtent: CGRect,
    target: CGSize
  ) throws -> [UInt8] {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw RenderComparisonError.unavailableColorSpace
    }
    let scaleX = target.width / sourceExtent.width
    let scaleY = target.height / sourceExtent.height
    let sampled = image.applyingFilter(
      "CILanczosScaleTransform",
      parameters: [
        kCIInputScaleKey: scaleY,
        kCIInputAspectRatioKey: scaleX / scaleY,
      ]
    )
    let sampledExtent = sampled.extent
    let normalized = sampled.transformed(
      by: CGAffineTransform(
        translationX: -sampledExtent.minX,
        y: -sampledExtent.minY
      )
    ).cropped(to: CGRect(origin: .zero, size: target))
    let width = Int(target.width)
    let height = Int(target.height)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let context = CIContext(options: [.cacheIntermediates: false])
    context.render(
      normalized,
      toBitmap: &bytes,
      rowBytes: width * 4,
      bounds: CGRect(origin: .zero, size: target),
      format: .RGBA8,
      colorSpace: colorSpace
    )
    guard bytes.count == width * height * 4 else {
      throw RenderComparisonError.renderFailed
    }
    return bytes
  }

  private static func metrics(
    first: [UInt8],
    second: [UInt8],
    size: CGSize
  ) -> [String: Any] {
    let pixelCount = first.count / 4
    var absoluteSums = [Double](repeating: 0, count: 3)
    var squaredSums = [Double](repeating: 0, count: 3)
    var biasSums = [Double](repeating: 0, count: 3)
    var maxDifference = 0
    var exactPixels = 0
    var maxChannelHistogram = [Int](repeating: 0, count: 256)
    var absoluteLumaSum = 0.0

    for pixel in 0..<pixelCount {
      let offset = pixel * 4
      var pixelMaximum = 0
      var exact = true
      var lumaDifference = 0.0
      for channel in 0..<3 {
        let difference = Int(second[offset + channel]) - Int(first[offset + channel])
        let absolute = abs(difference)
        absoluteSums[channel] += Double(absolute)
        squaredSums[channel] += Double(difference * difference)
        biasSums[channel] += Double(difference)
        pixelMaximum = max(pixelMaximum, absolute)
        maxDifference = max(maxDifference, absolute)
        exact = exact && difference == 0
        let weight = [0.2126, 0.7152, 0.0722][channel]
        lumaDifference += Double(difference) * weight
      }
      maxChannelHistogram[pixelMaximum] += 1
      absoluteLumaSum += abs(lumaDifference)
      if exact { exactPixels += 1 }
    }

    let channelSamples = Double(pixelCount)
    let allSamples = channelSamples * 3
    let absoluteTotal = absoluteSums.reduce(0, +)
    let squaredTotal = squaredSums.reduce(0, +)
    let meanSquaredError = squaredTotal / allSamples / (255 * 255)
    let psnr: Any = meanSquaredError == 0
      ? NSNull()
      : 10 * log10(1 / meanSquaredError)

    return [
      "sample_width": Int(size.width),
      "sample_height": Int(size.height),
      "sample_pixels": pixelCount,
      "mean_absolute_error": absoluteTotal / allSamples / 255,
      "root_mean_square_error": sqrt(meanSquaredError),
      "maximum_absolute_error": Double(maxDifference) / 255,
      "mean_absolute_luma_error": absoluteLumaSum / channelSamples / 255,
      "mean_absolute_rgb": absoluteSums.map { $0 / channelSamples / 255 },
      "root_mean_square_rgb": squaredSums.map {
        sqrt($0 / channelSamples) / 255
      },
      "mean_rgb_bias": biasSums.map { $0 / channelSamples / 255 },
      "exact_pixel_ratio": Double(exactPixels) / channelSamples,
      "pixel_ratio_over_4_code_values": ratioAbove(
        4,
        histogram: maxChannelHistogram,
        count: pixelCount
      ),
      "pixel_ratio_over_8_code_values": ratioAbove(
        8,
        histogram: maxChannelHistogram,
        count: pixelCount
      ),
      "p95_max_channel_error": percentile(
        0.95,
        histogram: maxChannelHistogram,
        count: pixelCount
      ),
      "p99_max_channel_error": percentile(
        0.99,
        histogram: maxChannelHistogram,
        count: pixelCount
      ),
      "psnr_db": psnr,
    ]
  }

  private static func percentile(
    _ percentile: Double,
    histogram: [Int],
    count: Int
  ) -> Double {
    let target = Int(ceil(percentile * Double(count)))
    var accumulated = 0
    for (value, frequency) in histogram.enumerated() {
      accumulated += frequency
      if accumulated >= target { return Double(value) / 255 }
    }
    return 1
  }

  private static func ratioAbove(
    _ codeValue: Int,
    histogram: [Int],
    count: Int
  ) -> Double {
    let matching = histogram.enumerated().reduce(0) { total, entry in
      total + (entry.offset > codeValue ? entry.element : 0)
    }
    return Double(matching) / Double(count)
  }

  private static func printJSON(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
