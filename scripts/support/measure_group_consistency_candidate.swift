import CoreGraphics
import CoreImage
import Foundation

private enum GroupMeasurementError: Error {
  case invalidArguments
  case unreadableImage
  case invalidPipeline
  case renderFailed
}

@main
private enum GroupConsistencyMeasurement {
  private static let maxEdge: CGFloat = 1_024
  private static let sharedIntensity = 0.8
  private static let context = CIContext(options: [.cacheIntermediates: false])

  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      throw GroupMeasurementError.invalidArguments
    }
    let input = try loadImage(CommandLine.arguments[1])
    let extent = input.extent.integral
    let sourceBytes = try bytes(input)
    let sourceMetrics = metrics(sourceBytes, width: Int(extent.width), height: Int(extent.height))
    let sourceLuma = sourceMetrics["mean_luma"] as! Double
    let sourceRedBlue = sourceMetrics["red_blue_delta"] as! Double
    let adaptiveExposure: Double
    if sourceLuma < 0.34 {
      adaptiveExposure = 0.15
    } else if sourceLuma > 0.72 {
      adaptiveExposure = -0.12
    } else {
      adaptiveExposure = 0
    }
    let adaptiveWarmth: Double
    if sourceRedBlue > 0.10 {
      adaptiveWarmth = -0.08
    } else if sourceRedBlue < -0.10 {
      adaptiveWarmth = 0.08
    } else {
      adaptiveWarmth = 0
    }

    let neutral = try render(input, extent: extent, exposure: 0, warmth: 0, includeSharedLook: false)
    let zeroConfigured = try render(
      input,
      extent: extent,
      exposure: 0,
      warmth: 0,
      includeSharedLook: false,
      zeroConfiguredLook: true
    )
    let shared = try render(input, extent: extent, exposure: 0, warmth: 0)
    let adaptive = try render(
      input,
      extent: extent,
      exposure: adaptiveExposure,
      warmth: adaptiveWarmth
    )
    let override = try render(
      input,
      extent: extent,
      exposure: adaptiveExposure + 0.08,
      warmth: adaptiveWarmth
    )

    let result: [String: Any] = [
      "schema": 1,
      "pipeline_schema": 10,
      "max_edge": Int(maxEdge),
      "width": Int(extent.width),
      "height": Int(extent.height),
      "zero_is_exact": neutral == zeroConfigured,
      "shared_intensity": sharedIntensity,
      "shared_filter": "cinematic",
      "shared_filter_strength": 45 * sharedIntensity,
      "shared_hsl_blue_saturation": -12 * sharedIntensity,
      "adaptive_exposure": adaptiveExposure,
      "adaptive_warmth": adaptiveWarmth,
      "source": sourceMetrics,
      "shared": metrics(shared, width: Int(extent.width), height: Int(extent.height)),
      "adaptive": metrics(adaptive, width: Int(extent.width), height: Int(extent.height)),
      "shared_difference": differenceMetrics(shared, neutral),
      "adaptive_difference": differenceMetrics(adaptive, shared),
      "override_difference": differenceMetrics(override, adaptive),
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }

  private static func loadImage(_ path: String) throws -> CIImage {
    guard let source = CIImage(
      contentsOf: URL(fileURLWithPath: path),
      options: [.applyOrientationProperty: true]
    ) else { throw GroupMeasurementError.unreadableImage }
    let normalized = source.transformed(by: CGAffineTransform(
      translationX: -source.extent.minX,
      y: -source.extent.minY
    ))
    let longest = max(normalized.extent.width, normalized.extent.height)
    guard longest > 0 else { throw GroupMeasurementError.unreadableImage }
    let scale = min(1, maxEdge / longest)
    let width = max(1, floor(normalized.extent.width * scale))
    let height = max(1, floor(normalized.extent.height * scale))
    return normalized.applyingFilter(
      "CILanczosScaleTransform",
      parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
    ).transformed(by: CGAffineTransform(
      translationX: -normalized.extent.minX * scale,
      y: -normalized.extent.minY * scale
    )).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
  }

  private static func render(
    _ input: CIImage,
    extent: CGRect,
    exposure: Double,
    warmth: Double,
    includeSharedLook: Bool = true,
    zeroConfiguredLook: Bool = false
  ) throws -> [UInt8] {
    guard let pipeline = IOSImagePipeline(arguments: recipe(
      exposure: includeSharedLook ? 0.04 * sharedIntensity + exposure : 0,
      highlights: includeSharedLook ? -0.08 * sharedIntensity : 0,
      shadows: includeSharedLook ? 0.08 * sharedIntensity : 0,
      contrast: includeSharedLook ? 0.03 * sharedIntensity : 0,
      warmth: includeSharedLook ? 0.02 * sharedIntensity + warmth : 0,
      saturation: includeSharedLook ? 0.02 * sharedIntensity : 0,
      filter: includeSharedLook || zeroConfiguredLook ? "cinematic" : "none",
      filterStrength: includeSharedLook ? 45 * sharedIntensity : 0,
      blueSaturation: includeSharedLook ? -12 * sharedIntensity : 0,
      blueLightness: includeSharedLook ? 4 * sharedIntensity : 0
    )) else { throw GroupMeasurementError.invalidPipeline }
    return try bytes(pipeline.applying(
      to: input,
      extent: extent,
      portraitContext: .unavailable
    ))
  }

  private static func bytes(_ image: CIImage) throws -> [UInt8] {
    let extent = image.extent.integral
    let width = Int(extent.width)
    let height = Int(extent.height)
    guard width > 0, height > 0,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw GroupMeasurementError.renderFailed }
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

  private static func metrics(
    _ bytes: [UInt8], width: Int, height: Int
  ) -> [String: Any] {
    let count = width * height
    var luma = 0.0
    var redBlue = 0.0
    var chroma = 0.0
    var black = 0
    var white = 0
    for offset in stride(from: 0, to: bytes.count, by: 4) {
      let red = Double(bytes[offset]) / 255
      let green = Double(bytes[offset + 1]) / 255
      let blue = Double(bytes[offset + 2]) / 255
      let value = 0.2126 * red + 0.7152 * green + 0.0722 * blue
      luma += value
      redBlue += red - blue
      chroma += max(red, green, blue) - min(red, green, blue)
      if max(red, green, blue) <= 1.0 / 255 { black += 1 }
      if min(red, green, blue) >= 254.0 / 255 { white += 1 }
    }
    return [
      "mean_luma": luma / Double(count),
      "red_blue_delta": redBlue / Double(count),
      "mean_chroma": chroma / Double(count),
      "black_clip_ratio": Double(black) / Double(count),
      "white_clip_ratio": Double(white) / Double(count),
    ]
  }

  private static func differenceMetrics(
    _ lhs: [UInt8], _ rhs: [UInt8]
  ) -> [String: Any] {
    guard lhs.count == rhs.count else {
      return ["mean_difference": 1.0, "p95_difference": 1.0]
    }
    var values: [Double] = []
    values.reserveCapacity(lhs.count / 4)
    var total = 0.0
    for offset in stride(from: 0, to: lhs.count, by: 4) {
      let difference = (
        abs(Double(lhs[offset]) - Double(rhs[offset]))
          + abs(Double(lhs[offset + 1]) - Double(rhs[offset + 1]))
          + abs(Double(lhs[offset + 2]) - Double(rhs[offset + 2]))
      ) / 3 / 255
      values.append(difference)
      total += difference
    }
    values.sort()
    return [
      "mean_difference": total / Double(values.count),
      "p95_difference": values[Int(Double(values.count - 1) * 0.95)],
    ]
  }

  private static func recipe(
    exposure: Double,
    highlights: Double,
    shadows: Double,
    contrast: Double,
    warmth: Double,
    saturation: Double,
    filter: String,
    filterStrength: Double,
    blueSaturation: Double,
    blueLightness: Double
  ) -> [String: Any] {
    [
      "schemaVersion": 10,
      "workingColorSpace": "srgb",
      "adjustments": [
        "exposureEv": exposure, "highlights": highlights, "shadows": shadows,
        "contrast": contrast, "warmth": warmth, "tint": 0.0,
        "saturation": saturation, "clarity": 0.0,
      ],
      "geometry": [
        "normalizedCrop": [0.0, 0.0, 1.0, 1.0],
        "quarterTurns": 0, "straightenDegrees": 0.0,
      ],
      "portraitRecipeV2": [
        "recipeVersion": 2, "analysisVersion": "vision-multiface-v1",
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
        "recipeVersion": 1, "flipHorizontal": false, "flipVertical": false,
        "perspectiveHorizontal": 0.0, "perspectiveVertical": 0.0,
        "filter": filter, "filterStrength": filterStrength,
        "hsl": blueSaturation == 0 && blueLightness == 0 ? [:] : [
          "blue": [
            "hue": 0.0, "saturation": blueSaturation,
            "lightness": blueLightness,
          ],
        ],
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
