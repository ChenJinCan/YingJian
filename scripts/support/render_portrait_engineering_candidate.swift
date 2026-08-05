import CoreGraphics
import CoreImage
import Foundation

private enum EngineeringCandidateError: Error {
  case invalidArguments
  case unreadableInput
  case unavailableColorSpace
  case incompleteOutputs
}

@main
private enum PortraitEngineeringCandidateRenderer {
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
    if CommandLine.arguments.count == 6, CommandLine.arguments[1] == "metrics" {
      let report = try PortraitEngineeringMetrics.measure(
        baselineURL: URL(fileURLWithPath: CommandLine.arguments[2]),
        offURL: URL(fileURLWithPath: CommandLine.arguments[3]),
        defaultURL: URL(fileURLWithPath: CommandLine.arguments[4]),
        highSafeURL: URL(fileURLWithPath: CommandLine.arguments[5])
      )
      try printMetrics(report)
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
    try write(normalized, to: baselineURL, context: context, colorSpace: colorSpace)
    var outputURLs: [String: URL] = [:]
    for (name, strength) in variants {
      let rendered = IOSPortraitRetoucher.applying(
        to: normalized,
        strength: strength,
        extent: extent
      )
      let outputURL = outputDirectory.appendingPathComponent("\(name).jpg")
      try write(rendered, to: outputURL, context: context, colorSpace: colorSpace)
      outputURLs[name] = outputURL
    }
    guard
      let offURL = outputURLs["off"],
      let defaultURL = outputURLs["default"],
      let highSafeURL = outputURLs["high-safe"]
    else {
      throw EngineeringCandidateError.incompleteOutputs
    }
    let report = try PortraitEngineeringMetrics.measure(
      baselineURL: baselineURL,
      offURL: offURL,
      defaultURL: defaultURL,
      highSafeURL: highSafeURL,
      context: context
    )
    try printMetrics(report)
  }

  private static func write(
    _ image: CIImage,
    to url: URL,
    context: CIContext,
    colorSpace: CGColorSpace
  ) throws {
    try context.writeJPEGRepresentation(
      of: image,
      to: url,
      colorSpace: colorSpace,
      options: [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
      ]
    )
  }

  private static func printMetrics(_ report: PortraitEngineeringMetricReport) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
  }
}
