import CoreGraphics
import CoreImage
import Foundation

private enum EngineeringCandidateError: Error {
  case invalidArguments
  case unreadableInput
  case unavailableColorSpace
  case incompatibleMetricInputs
}

@main
private enum PortraitEngineeringCandidateRenderer {
  private static let metricProxyMaxEdge = 512
  private static let metricVersion = "whole-frame-srgb-rgba8-v1"
  private static let variants: [(name: String, strength: Double)] = [
    ("off", 0.0),
    ("default", 0.35),
    ("high-safe", 0.55),
  ]

  static func main() throws {
    if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "identity" {
      let data = try JSONSerialization.data(
        withJSONObject: [
          "candidateKind": IOSPortraitRetoucher.candidateKind,
          "effectVersion": IOSPortraitRetoucher.effectVersion,
          "strengths": Dictionary(
            uniqueKeysWithValues: variants.map { ($0.name, $0.strength) }
          ),
        ],
        options: [.sortedKeys]
      )
      print(String(decoding: data, as: UTF8.self))
      return
    }
    guard CommandLine.arguments.count == 3 else {
      throw EngineeringCandidateError.invalidArguments
    }

    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputDirectory = URL(
      fileURLWithPath: CommandLine.arguments[2],
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )
    guard let source = CIImage(
      contentsOf: sourceURL,
      options: [.applyOrientationProperty: true]
    ) else {
      throw EngineeringCandidateError.unreadableInput
    }
    let normalized = source.transformed(
      by: CGAffineTransform(
        translationX: -source.extent.minX,
        y: -source.extent.minY
      )
    )
    let extent = normalized.extent.integral
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw EngineeringCandidateError.unavailableColorSpace
    }
    let context = CIContext(options: [.cacheIntermediates: false])
    let baselineURL = outputDirectory.appendingPathComponent("baseline.jpg")
    try context.writeJPEGRepresentation(
      of: normalized,
      to: baselineURL,
      colorSpace: colorSpace,
      options: [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
      ]
    )
    var outputURLs: [String: URL] = [:]
    for (name, strength) in variants {
      let rendered = IOSPortraitRetoucher.applying(
        to: normalized,
        strength: strength,
        extent: extent
      )
      let outputURL = outputDirectory.appendingPathComponent("\(name).jpg")
      try context.writeJPEGRepresentation(
        of: rendered,
        to: outputURL,
        colorSpace: colorSpace,
        options: [
          kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
        ]
      )
      outputURLs[name] = outputURL
    }
    guard
      let offURL = outputURLs["off"],
      let defaultURL = outputURLs["default"],
      let highSafeURL = outputURLs["high-safe"]
    else {
      throw EngineeringCandidateError.incompatibleMetricInputs
    }
    let baselinePixels = try metricPixels(
      at: baselineURL,
      context: context,
      colorSpace: colorSpace
    )
    let offPixels = try metricPixels(
      at: offURL,
      context: context,
      colorSpace: colorSpace
    )
    let defaultPixels = try metricPixels(
      at: defaultURL,
      context: context,
      colorSpace: colorSpace
    )
    let highSafePixels = try metricPixels(
      at: highSafeURL,
      context: context,
      colorSpace: colorSpace
    )
    let metrics = EffectMetricReport(
      metricVersion: metricVersion,
      proxyMaxEdge: metricProxyMaxEdge,
      off: try compare(offPixels, to: baselinePixels),
      default: try compare(defaultPixels, to: baselinePixels),
      highSafe: try compare(highSafePixels, to: baselinePixels),
      progression: try compareProgression(
        default: defaultPixels,
        highSafe: highSafePixels,
        baseline: baselinePixels
      )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let metricData = try encoder.encode(metrics)
    print(String(decoding: metricData, as: UTF8.self))
  }

  private struct MetricPixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int
  }

  private struct DifferenceMetrics: Codable {
    let meanAbsoluteDifference: Double
    let changedPixelFractionAt2: Double
    let p99MaxChannelDifference: Int

    private enum CodingKeys: String, CodingKey {
      case meanAbsoluteDifference = "mean_absolute_difference"
      case changedPixelFractionAt2 = "changed_pixel_fraction_at_2"
      case p99MaxChannelDifference = "p99_max_channel_difference"
    }
  }

  private struct ProgressionMetrics: Codable {
    let directionalCosineSimilarity: Double
    let defaultChangedPixelsRetainedFraction: Double

    private enum CodingKeys: String, CodingKey {
      case directionalCosineSimilarity = "directional_cosine_similarity"
      case defaultChangedPixelsRetainedFraction = "default_changed_pixels_retained_fraction"
    }
  }

  private struct EffectMetricReport: Codable {
    let metricVersion: String
    let proxyMaxEdge: Int
    let off: DifferenceMetrics
    let `default`: DifferenceMetrics
    let highSafe: DifferenceMetrics
    let progression: ProgressionMetrics

    private enum CodingKeys: String, CodingKey {
      case metricVersion = "metric_version"
      case proxyMaxEdge = "proxy_max_edge"
      case off
      case `default`
      case highSafe = "high_safe"
      case progression
    }
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
      throw EngineeringCandidateError.unreadableInput
    }
    let extent = source.extent.integral
    let longestEdge = max(extent.width, extent.height)
    guard longestEdge >= 1 else {
      throw EngineeringCandidateError.incompatibleMetricInputs
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
  ) throws -> DifferenceMetrics {
    guard
      candidate.width == baseline.width,
      candidate.height == baseline.height,
      candidate.bytes.count == baseline.bytes.count
    else {
      throw EngineeringCandidateError.incompatibleMetricInputs
    }
    let pixelCount = candidate.width * candidate.height
    guard pixelCount > 0 else {
      throw EngineeringCandidateError.incompatibleMetricInputs
    }
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
      if maximumDifference >= 2 {
        changedPixelCount += 1
      }
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
    return DifferenceMetrics(
      meanAbsoluteDifference: Double(absoluteDifferenceTotal) / Double(pixelCount * 3),
      changedPixelFractionAt2: Double(changedPixelCount) / Double(pixelCount),
      p99MaxChannelDifference: Int(maximumChannelDifferences[p99Index])
    )
  }

  private static func compareProgression(
    default defaultPixels: MetricPixels,
    highSafe highSafePixels: MetricPixels,
    baseline: MetricPixels
  ) throws -> ProgressionMetrics {
    guard
      defaultPixels.width == baseline.width,
      defaultPixels.height == baseline.height,
      highSafePixels.width == baseline.width,
      highSafePixels.height == baseline.height,
      defaultPixels.bytes.count == baseline.bytes.count,
      highSafePixels.bytes.count == baseline.bytes.count
    else {
      throw EngineeringCandidateError.incompatibleMetricInputs
    }
    let pixelCount = baseline.width * baseline.height
    guard pixelCount > 0 else {
      throw EngineeringCandidateError.incompatibleMetricInputs
    }
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
        if highSafeMaximumDifference >= 2 {
          retainedChangedPixelCount += 1
        }
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
    return ProgressionMetrics(
      directionalCosineSimilarity: cosine,
      defaultChangedPixelsRetainedFraction: retention
    )
  }
}
