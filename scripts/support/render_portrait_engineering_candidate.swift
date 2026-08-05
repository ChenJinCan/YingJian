import CoreGraphics
import CoreImage
import Foundation

private enum EngineeringCandidateError: Error {
  case invalidArguments
  case unreadableInput
  case unavailableColorSpace
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
    for (name, strength) in variants {
      let rendered = IOSPortraitRetoucher.applying(
        to: normalized,
        strength: strength,
        extent: extent
      )
      try context.writeJPEGRepresentation(
        of: rendered,
        to: outputDirectory.appendingPathComponent("\(name).jpg"),
        colorSpace: colorSpace,
        options: [
          kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
        ]
      )
    }
  }
}
