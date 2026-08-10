import CoreGraphics
import CoreImage
import Foundation

private enum CompositionMeasurementError: Error {
  case invalidArguments
  case unreadableImage
  case invalidPipeline
  case renderFailed
}

@main
private enum CompositionMeasurement {
  private static let maxEdge: CGFloat = 1_024
  private static let context = CIContext(options: [.cacheIntermediates: false])

  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      throw CompositionMeasurementError.invalidArguments
    }
    guard let source = CIImage(
      contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]),
      options: [.applyOrientationProperty: true]
    ) else { throw CompositionMeasurementError.unreadableImage }
    let normalized = source.transformed(by: CGAffineTransform(
      translationX: -source.extent.minX,
      y: -source.extent.minY
    ))
    let longest = max(normalized.extent.width, normalized.extent.height)
    guard longest > 0 else { throw CompositionMeasurementError.unreadableImage }
    let scale = min(1, maxEdge / longest)
    let input = normalized.applyingFilter(
      "CILanczosScaleTransform",
      parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
    )
    let extent = input.extent.integral
    let neutralImage = try apply(input, extent: extent)
    let neutral = try bytes(neutralImage)

    let zeroImage = try apply(
      input,
      extent: extent,
      flipHorizontal: false,
      flipVertical: false,
      perspectiveHorizontal: 0,
      perspectiveVertical: 0,
      crop: [0, 0, 1, 1],
      quarterTurns: 0,
      straightenDegrees: 0
    )

    let horizontal = try apply(input, extent: extent, flipHorizontal: true)
    let horizontalTwice = try apply(
      horizontal,
      extent: horizontal.extent,
      flipHorizontal: true
    )
    let vertical = try apply(input, extent: extent, flipVertical: true)
    let verticalTwice = try apply(
      vertical,
      extent: vertical.extent,
      flipVertical: true
    )

    let cropValues = [0.12, 0.08, 0.88, 0.92]
    let cropped = try apply(input, extent: extent, crop: cropValues)
    let expectedCrop = expectedCropImage(neutralImage, crop: cropValues)

    let quarter = try apply(input, extent: extent, quarterTurns: 1)
    var quarterCycle = neutralImage
    for _ in 0..<4 {
      quarterCycle = try apply(
        quarterCycle,
        extent: quarterCycle.extent,
        quarterTurns: 1
      )
    }

    var directional: [String: Any] = [:]
    for (name, perspectiveHorizontal, perspectiveVertical, straighten) in [
      ("straighten_positive", 0.0, 0.0, 5.0),
      ("straighten_negative", 0.0, 0.0, -5.0),
      ("perspective_horizontal_positive", 15.0, 0.0, 0.0),
      ("perspective_horizontal_negative", -15.0, 0.0, 0.0),
      ("perspective_vertical_positive", 0.0, 15.0, 0.0),
      ("perspective_vertical_negative", 0.0, -15.0, 0.0),
    ] {
      let output = try apply(
        input,
        extent: extent,
        perspectiveHorizontal: perspectiveHorizontal,
        perspectiveVertical: perspectiveVertical,
        straightenDegrees: straighten
      )
      directional[name] = try sameSizeMetrics(output, neutral: neutral)
    }

    let combined = try apply(
      input,
      extent: extent,
      flipHorizontal: true,
      perspectiveHorizontal: 8,
      perspectiveVertical: -6,
      crop: [0.1, 0.12, 0.9, 0.88],
      quarterTurns: 3,
      straightenDegrees: 3
    )
    let result: [String: Any] = [
      "schema": 1,
      "pipeline_schema": 10,
      "max_edge": Int(maxEdge),
      "width": Int(extent.width),
      "height": Int(extent.height),
      "zero_is_exact": try bytes(zeroImage) == neutral,
      "flip_horizontal": [
        "effect_difference": try difference(bytes(horizontal), neutral),
        "round_trip_difference": try difference(bytes(horizontalTwice), neutral),
      ],
      "flip_vertical": [
        "effect_difference": try difference(bytes(vertical), neutral),
        "round_trip_difference": try difference(bytes(verticalTwice), neutral),
      ],
      "crop": [
        "width": Int(cropped.extent.width),
        "height": Int(cropped.extent.height),
        "expected_width": Int(expectedCrop.extent.width),
        "expected_height": Int(expectedCrop.extent.height),
        "mapping_difference": try difference(bytes(cropped), bytes(expectedCrop)),
      ],
      "quarter_turn": [
        "width": Int(quarter.extent.width),
        "height": Int(quarter.extent.height),
        "cycle_difference": try difference(bytes(quarterCycle), neutral),
      ],
      "directional": directional,
      "combined": [
        "width": Int(combined.extent.width),
        "height": Int(combined.extent.height),
        "white_ratio": try whiteRatio(bytes(combined)),
      ],
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }

  private static func apply(
    _ input: CIImage,
    extent: CGRect,
    flipHorizontal: Bool = false,
    flipVertical: Bool = false,
    perspectiveHorizontal: Double = 0,
    perspectiveVertical: Double = 0,
    crop: [Double] = [0, 0, 1, 1],
    quarterTurns: Int = 0,
    straightenDegrees: Double = 0
  ) throws -> CIImage {
    guard let pipeline = IOSImagePipeline(arguments: recipe(
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
      perspectiveHorizontal: perspectiveHorizontal,
      perspectiveVertical: perspectiveVertical,
      crop: crop,
      quarterTurns: quarterTurns,
      straightenDegrees: straightenDegrees
    )) else { throw CompositionMeasurementError.invalidPipeline }
    return pipeline.applying(to: input, extent: extent, portraitContext: .unavailable)
  }

  private static func expectedCropImage(_ input: CIImage, crop: [Double]) -> CIImage {
    func aligned(_ value: CGFloat) -> CGFloat { floor(value + 0.5) }
    let extent = input.extent
    let width = min(extent.width, max(1, aligned(CGFloat(crop[2] - crop[0]) * extent.width)))
    let height = min(extent.height, max(1, aligned(CGFloat(crop[3] - crop[1]) * extent.height)))
    let left = min(extent.width - width, max(0, aligned(CGFloat(crop[0]) * extent.width)))
    let top = min(extent.height - height, max(0, aligned(CGFloat(crop[1]) * extent.height)))
    let rect = CGRect(
      x: extent.minX + left,
      y: extent.minY + extent.height - top - height,
      width: width,
      height: height
    )
    return input.cropped(to: rect).transformed(by: CGAffineTransform(
      translationX: -rect.minX,
      y: -rect.minY
    ))
  }

  private static func sameSizeMetrics(_ image: CIImage, neutral: [UInt8]) throws -> [String: Any] {
    let output = try bytes(image)
    return [
      "width": Int(image.extent.width),
      "height": Int(image.extent.height),
      "effect_difference": try difference(output, neutral),
      "white_ratio_delta": whiteRatio(output) - whiteRatio(neutral),
    ]
  }

  private static func bytes(_ image: CIImage) throws -> [UInt8] {
    let extent = image.extent.integral
    let width = Int(extent.width)
    let height = Int(extent.height)
    guard width > 0, height > 0,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw CompositionMeasurementError.renderFailed }
    var output = [UInt8](repeating: 0, count: width * height * 4)
    context.render(
      image,
      toBitmap: &output,
      rowBytes: width * 4,
      bounds: extent,
      format: .RGBA8,
      colorSpace: colorSpace
    )
    return output
  }

  private static func difference(_ lhs: [UInt8], _ rhs: [UInt8]) throws -> Double {
    guard lhs.count == rhs.count else { throw CompositionMeasurementError.renderFailed }
    var total = 0.0
    for offset in stride(from: 0, to: lhs.count, by: 4) {
      total += (
        abs(Double(lhs[offset]) - Double(rhs[offset]))
          + abs(Double(lhs[offset + 1]) - Double(rhs[offset + 1]))
          + abs(Double(lhs[offset + 2]) - Double(rhs[offset + 2]))
      ) / 3 / 255
    }
    return total / Double(lhs.count / 4)
  }

  private static func whiteRatio(_ bytes: [UInt8]) -> Double {
    var white = 0
    for offset in stride(from: 0, to: bytes.count, by: 4) {
      if min(bytes[offset], bytes[offset + 1], bytes[offset + 2]) >= 254 { white += 1 }
    }
    return Double(white) / Double(bytes.count / 4)
  }

  private static func recipe(
    flipHorizontal: Bool,
    flipVertical: Bool,
    perspectiveHorizontal: Double,
    perspectiveVertical: Double,
    crop: [Double],
    quarterTurns: Int,
    straightenDegrees: Double
  ) -> [String: Any] {
    return [
      "schemaVersion": 10,
      "workingColorSpace": "srgb",
      "adjustments": [
        "exposureEv": 0.0, "highlights": 0.0, "shadows": 0.0,
        "contrast": 0.0, "warmth": 0.0, "tint": 0.0,
        "saturation": 0.0, "clarity": 0.0,
      ],
      "geometry": [
        "normalizedCrop": crop,
        "quarterTurns": quarterTurns,
        "straightenDegrees": straightenDegrees,
      ],
      "portraitRecipeV2": [
        "recipeVersion": 2,
        "analysisVersion": "vision-multiface-v1",
        "effectVersion": "portrait-core-contract-v2",
        "textureSmoothing": 0, "skinToneLighting": 0,
        "blemishReduction": 0, "faceSlimming": 0, "torsoSlimming": 0,
      ],
      "faceSlimRecipeV1": [
        "recipeVersion": 1, "selectedTargetIndex": 0, "targetStrengths": [0.0],
      ],
      "qualityEnhancementRecipeV1": [
        "recipeVersion": 1, "noiseReduction": 0, "lowLightRecovery": 0,
        "hazeRemoval": 0, "detailSharpening": 0,
      ],
      "basicEditingRecipeV1": [
        "recipeVersion": 1,
        "flipHorizontal": flipHorizontal, "flipVertical": flipVertical,
        "perspectiveHorizontal": perspectiveHorizontal,
        "perspectiveVertical": perspectiveVertical,
        "filter": "none", "filterStrength": 0, "hsl": [:],
      ],
      "portraitGeometryRecipeV1": [
        "recipeVersion": 1, "selectedFaceIndex": 0,
        "faceTargets": [[
          "faceSlim": 0, "headSize": 0, "jaw": 0, "chin": 0,
          "eyes": 0, "nose": 0, "mouth": 0,
        ]],
        "selectedBodyIndex": 0,
        "bodyTargets": [[
          "slimming": 0, "height": 0, "shoulders": 0,
          "waist": 0, "legs": 0,
        ]],
      ],
      "semanticEditingRecipeV2": [
        "recipeVersion": 2, "background": "original", "backgroundImagePath": "",
        "backgroundBlur": 0, "subjectExposure": 0, "subjectSaturation": 0,
        "backgroundExposure": 0, "backgroundSaturation": 0,
        "localExposure": 0, "localSaturation": 0,
        "subjectMaskStrokes": [], "localAdjustmentStrokes": [], "eraseStrokes": [],
      ],
    ]
  }
}
