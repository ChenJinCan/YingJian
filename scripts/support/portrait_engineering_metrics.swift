import CoreGraphics
import CoreImage
import Foundation

enum PortraitEngineeringMetricError: Error {
  case unreadableInput
  case unavailableColorSpace
  case incompatibleInputs
}

struct PortraitEngineeringDifferenceMetrics: Codable {
  let meanAbsoluteDifference: Double
  let changedPixelFractionAt2: Double
  let p99MaxChannelDifference: Int

  private enum CodingKeys: String, CodingKey {
    case meanAbsoluteDifference = "mean_absolute_difference"
    case changedPixelFractionAt2 = "changed_pixel_fraction_at_2"
    case p99MaxChannelDifference = "p99_max_channel_difference"
  }
}

struct PortraitEngineeringProgressionMetrics: Codable {
  let directionalCosineSimilarity: Double
  let defaultChangedPixelsRetainedFraction: Double

  private enum CodingKeys: String, CodingKey {
    case directionalCosineSimilarity = "directional_cosine_similarity"
    case defaultChangedPixelsRetainedFraction = "default_changed_pixels_retained_fraction"
  }
}

struct PortraitEngineeringMetricReport: Codable {
  let metricVersion: String
  let proxyMaxEdge: Int
  let off: PortraitEngineeringDifferenceMetrics
  let `default`: PortraitEngineeringDifferenceMetrics
  let highSafe: PortraitEngineeringDifferenceMetrics
  let progression: PortraitEngineeringProgressionMetrics

  private enum CodingKeys: String, CodingKey {
    case metricVersion = "metric_version"
    case proxyMaxEdge = "proxy_max_edge"
    case off
    case `default`
    case highSafe = "high_safe"
    case progression
  }
}

enum PortraitEngineeringMetrics {
  static let metricProxyMaxEdge = 512
  static let metricVersion = "whole-frame-srgb-rgba8-v1"

  static func measure(
    baselineURL: URL,
    offURL: URL,
    defaultURL: URL,
    highSafeURL: URL,
    context: CIContext = CIContext(options: [.cacheIntermediates: false])
  ) throws -> PortraitEngineeringMetricReport {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw PortraitEngineeringMetricError.unavailableColorSpace
    }
    let baseline = try metricPixels(at: baselineURL, context: context, colorSpace: colorSpace)
    let off = try metricPixels(at: offURL, context: context, colorSpace: colorSpace)
    let defaultPixels = try metricPixels(at: defaultURL, context: context, colorSpace: colorSpace)
    let highSafe = try metricPixels(at: highSafeURL, context: context, colorSpace: colorSpace)
    return PortraitEngineeringMetricReport(
      metricVersion: metricVersion,
      proxyMaxEdge: metricProxyMaxEdge,
      off: try compare(off, to: baseline),
      default: try compare(defaultPixels, to: baseline),
      highSafe: try compare(highSafe, to: baseline),
      progression: try compareProgression(
        default: defaultPixels,
        highSafe: highSafe,
        baseline: baseline
      )
    )
  }

  private struct MetricPixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int
  }

  private static func metricPixels(
    at url: URL,
    context: CIContext,
    colorSpace: CGColorSpace
  ) throws -> MetricPixels {
    guard let source = CIImage(
      contentsOf: url,
      options: [.applyOrientationProperty: true]
    ) else {
      throw PortraitEngineeringMetricError.unreadableInput
    }
    let extent = source.extent.integral
    let longestEdge = max(extent.width, extent.height)
    guard longestEdge >= 1 else {
      throw PortraitEngineeringMetricError.incompatibleInputs
    }
    let scale = min(1, CGFloat(metricProxyMaxEdge) / longestEdge)
    let width = max(1, Int((extent.width * scale).rounded()))
    let height = max(1, Int((extent.height * scale).rounded()))
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let normalized = source.transformed(
      by: CGAffineTransform(
        translationX: -extent.minX,
        y: -extent.minY
      )
    )
    let proxy = normalized
      .applyingFilter(
        "CILanczosScaleTransform",
        parameters: [
          kCIInputScaleKey: scale,
          kCIInputAspectRatioKey: 1,
        ]
      )
      .cropped(to: bounds)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    context.render(
      proxy,
      toBitmap: &bytes,
      rowBytes: width * 4,
      bounds: bounds,
      format: .RGBA8,
      colorSpace: colorSpace
    )
    return MetricPixels(bytes: bytes, width: width, height: height)
  }

  private static func compare(
    _ candidate: MetricPixels,
    to baseline: MetricPixels
  ) throws -> PortraitEngineeringDifferenceMetrics {
    try validate(candidate, baseline)
    let pixelCount = candidate.width * candidate.height
    var absoluteDifferenceTotal: UInt64 = 0
    var changedPixelCount = 0
    var maximumChannelDifferences = [UInt8]()
    maximumChannelDifferences.reserveCapacity(pixelCount)
    for pixel in 0..<pixelCount {
      let offset = pixel * 4
      var maximumDifference = 0
      for channel in 0..<3 {
        let difference = abs(
          Int(candidate.bytes[offset + channel])
            - Int(baseline.bytes[offset + channel])
        )
        absoluteDifferenceTotal += UInt64(difference)
        maximumDifference = max(maximumDifference, difference)
      }
      if maximumDifference >= 2 { changedPixelCount += 1 }
      maximumChannelDifferences.append(UInt8(maximumDifference))
    }
    maximumChannelDifferences.sort()
    let p99Index = max(
      0,
      min(
        maximumChannelDifferences.count - 1,
        Int(ceil(Double(maximumChannelDifferences.count) * 0.99)) - 1
      )
    )
    return PortraitEngineeringDifferenceMetrics(
      meanAbsoluteDifference: Double(absoluteDifferenceTotal) / Double(pixelCount * 3),
      changedPixelFractionAt2: Double(changedPixelCount) / Double(pixelCount),
      p99MaxChannelDifference: Int(maximumChannelDifferences[p99Index])
    )
  }

  private static func compareProgression(
    default defaultPixels: MetricPixels,
    highSafe highSafePixels: MetricPixels,
    baseline: MetricPixels
  ) throws -> PortraitEngineeringProgressionMetrics {
    try validate(defaultPixels, baseline)
    try validate(highSafePixels, baseline)
    let pixelCount = baseline.width * baseline.height
    var dotProduct = 0.0
    var defaultMagnitudeSquared = 0.0
    var highSafeMagnitudeSquared = 0.0
    var defaultChangedPixelCount = 0
    var retainedChangedPixelCount = 0
    for pixel in 0..<pixelCount {
      let offset = pixel * 4
      var defaultMaximumDifference = 0
      var highSafeMaximumDifference = 0
      for channel in 0..<3 {
        let defaultDifference = Double(
          Int(defaultPixels.bytes[offset + channel]) - Int(baseline.bytes[offset + channel])
        )
        let highSafeDifference = Double(
          Int(highSafePixels.bytes[offset + channel]) - Int(baseline.bytes[offset + channel])
        )
        dotProduct += defaultDifference * highSafeDifference
        defaultMagnitudeSquared += defaultDifference * defaultDifference
        highSafeMagnitudeSquared += highSafeDifference * highSafeDifference
        defaultMaximumDifference = max(defaultMaximumDifference, Int(abs(defaultDifference)))
        highSafeMaximumDifference = max(highSafeMaximumDifference, Int(abs(highSafeDifference)))
      }
      if defaultMaximumDifference >= 2 {
        defaultChangedPixelCount += 1
        if highSafeMaximumDifference >= 2 { retainedChangedPixelCount += 1 }
      }
    }
    let cosine: Double
    if defaultMagnitudeSquared == 0, highSafeMagnitudeSquared == 0 {
      cosine = 1
    } else if defaultMagnitudeSquared == 0 || highSafeMagnitudeSquared == 0 {
      cosine = 0
    } else {
      cosine = max(
        0,
        min(1, dotProduct / sqrt(defaultMagnitudeSquared * highSafeMagnitudeSquared))
      )
    }
    let retention = defaultChangedPixelCount == 0
      ? 1
      : Double(retainedChangedPixelCount) / Double(defaultChangedPixelCount)
    return PortraitEngineeringProgressionMetrics(
      directionalCosineSimilarity: cosine,
      defaultChangedPixelsRetainedFraction: retention
    )
  }

  private static func validate(_ candidate: MetricPixels, _ baseline: MetricPixels) throws {
    guard
      candidate.width == baseline.width,
      candidate.height == baseline.height,
      candidate.bytes.count == baseline.bytes.count,
      candidate.width * candidate.height > 0
    else {
      throw PortraitEngineeringMetricError.incompatibleInputs
    }
  }
}
