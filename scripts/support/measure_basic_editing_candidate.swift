import CoreGraphics
import CoreImage
import Foundation

private enum BasicEditingMeasurementError: Error {
  case invalidArguments
  case unreadableImage
  case invalidPipeline
  case renderFailed
}

@main
private enum BasicEditingMeasurement {
  private static let maxEdge: CGFloat = 1_024
  private static let filters = [
    "clean", "portrait", "cinematic", "film", "warmSun", "coolAir",
    "vivid", "faded", "noir", "food", "landscape", "night",
  ]
  private static let channels = [
    "red", "orange", "yellow", "green", "cyan", "blue", "purple", "magenta",
  ]

  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      throw BasicEditingMeasurementError.invalidArguments
    }
    guard let source = CIImage(
      contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]),
      options: [.applyOrientationProperty: true]
    ) else {
      throw BasicEditingMeasurementError.unreadableImage
    }
    let normalized = source.transformed(
      by: CGAffineTransform(
        translationX: -source.extent.minX,
        y: -source.extent.minY
      )
    )
    let longest = max(normalized.extent.width, normalized.extent.height)
    guard longest > 0 else { throw BasicEditingMeasurementError.unreadableImage }
    let scale = min(1, maxEdge / longest)
    let input = normalized.applyingFilter(
      "CILanczosScaleTransform",
      parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
    )
    let extent = input.extent.integral
    let context = CIContext(options: [.cacheIntermediates: false])
    let neutral = try render(
      input: input,
      extent: extent,
      context: context,
      filter: "none",
      filterStrength: 0,
      hsl: [:]
    )
    var filterMeasurements: [String: Any] = [:]
    for filter in filters {
      let bytes = try render(
        input: input,
        extent: extent,
        context: context,
        filter: filter,
        filterStrength: 60,
        hsl: [:]
      )
      filterMeasurements[filter] = metrics(bytes, neutral: neutral)
    }
    var hslMeasurements: [String: Any] = [:]
    for channel in channels {
      var channelMeasurements: [String: Any] = [:]
      for operation in ["hue", "saturation", "lightness"] {
        var values: [String: Double] = [
          "hue": 0, "saturation": 0, "lightness": 0,
        ]
        values[operation] = operation == "hue" ? 20 : (operation == "saturation" ? 25 : 15)
        let bytes = try render(
          input: input,
          extent: extent,
          context: context,
          filter: "none",
          filterStrength: 0,
          hsl: [channel: values]
        )
        channelMeasurements[operation] = metrics(bytes, neutral: neutral)
      }
      hslMeasurements[channel] = channelMeasurements
    }
    let zero = try render(
      input: input,
      extent: extent,
      context: context,
      filter: "clean",
      filterStrength: 0,
      hsl: [:]
    )
    let result: [String: Any] = [
      "schema": 1,
      "pipeline_schema": 10,
      "max_edge": Int(maxEdge),
      "width": Int(extent.width),
      "height": Int(extent.height),
      "zero_is_exact": neutral == zero,
      "neutral": metrics(neutral, neutral: neutral),
      "filters": filterMeasurements,
      "hsl": hslMeasurements,
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }

  private static func render(
    input: CIImage,
    extent: CGRect,
    context: CIContext,
    filter: String,
    filterStrength: Int,
    hsl: [String: [String: Double]]
  ) throws -> [UInt8] {
    guard let pipeline = IOSImagePipeline(
      arguments: recipe(filter: filter, filterStrength: filterStrength, hsl: hsl)
    ) else { throw BasicEditingMeasurementError.invalidPipeline }
    let output = pipeline.applying(
      to: input,
      extent: extent,
      portraitContext: .unavailable
    )
    let width = Int(extent.width)
    let height = Int(extent.height)
    guard width > 0, height > 0,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw BasicEditingMeasurementError.renderFailed }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    context.render(
      output,
      toBitmap: &bytes,
      rowBytes: width * 4,
      bounds: extent,
      format: .RGBA8,
      colorSpace: colorSpace
    )
    return bytes
  }

  private static func recipe(
    filter: String,
    filterStrength: Int,
    hsl: [String: [String: Double]]
  ) -> [String: Any] {
    var recipe: [String: Any] = [
      "schemaVersion": 10,
      "workingColorSpace": "srgb",
      "adjustments": [
        "exposureEv": 0.0, "highlights": 0.0, "shadows": 0.0,
        "contrast": 0.0, "warmth": 0.0, "tint": 0.0,
        "saturation": 0.0, "clarity": 0.0,
      ],
      "geometry": [
        "normalizedCrop": [0.0, 0.0, 1.0, 1.0],
        "quarterTurns": 0, "straightenDegrees": 0.0,
      ],
      "portraitRecipeV2": [
        "recipeVersion": 2,
        "analysisVersion": "vision-multiface-v1",
        "effectVersion": "portrait-core-contract-v2",
        "textureSmoothing": 0, "skinToneLighting": 0,
        "blemishReduction": 0, "faceSlimming": 0, "torsoSlimming": 0,
      ],
      "faceSlimRecipeV1": [
        "recipeVersion": 1, "selectedTargetIndex": 0,
        "targetStrengths": [0.0],
      ],
      "qualityEnhancementRecipeV1": [
        "recipeVersion": 1, "noiseReduction": 0, "lowLightRecovery": 0,
        "hazeRemoval": 0, "detailSharpening": 0,
      ],
      "basicEditingRecipeV1": [
        "recipeVersion": 1, "flipHorizontal": false, "flipVertical": false,
        "perspectiveHorizontal": 0, "perspectiveVertical": 0,
        "filter": filter, "filterStrength": filterStrength, "hsl": hsl,
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
    ]
    recipe["semanticEditingRecipeV2"] = [
      "recipeVersion": 3, "background": "original", "backgroundImagePath": "",
      "backgroundImageResourceId": "",
      "backgroundBlur": 0, "subjectExposure": 0, "subjectSaturation": 0,
      "backgroundExposure": 0, "backgroundSaturation": 0,
      "localExposure": 0, "localSaturation": 0,
      "subjectMaskStrokes": [], "localAdjustmentStrokes": [], "eraseStrokes": [],
    ]
    return recipe
  }

  private static func metrics(_ bytes: [UInt8], neutral: [UInt8]) -> [String: Any] {
    let pixels = bytes.count / 4
    var luma = 0.0
    var chroma = 0.0
    var difference = 0.0
    var black = 0
    var white = 0
    for pixel in 0..<pixels {
      let offset = pixel * 4
      let red = Double(bytes[offset]) / 255
      let green = Double(bytes[offset + 1]) / 255
      let blue = Double(bytes[offset + 2]) / 255
      luma += 0.2126 * red + 0.7152 * green + 0.0722 * blue
      chroma += max(red, green, blue) - min(red, green, blue)
      difference += (
        abs(Double(bytes[offset]) - Double(neutral[offset]))
          + abs(Double(bytes[offset + 1]) - Double(neutral[offset + 1]))
          + abs(Double(bytes[offset + 2]) - Double(neutral[offset + 2]))
      ) / 3 / 255
      black += max(bytes[offset], bytes[offset + 1], bytes[offset + 2]) <= 1 ? 1 : 0
      white += min(bytes[offset], bytes[offset + 1], bytes[offset + 2]) >= 254 ? 1 : 0
    }
    let count = Double(pixels)
    return [
      "mean_luma": luma / count,
      "mean_chroma": chroma / count,
      "mean_absolute_rgb_difference": difference / count,
      "black_clip_ratio": Double(black) / count,
      "white_clip_ratio": Double(white) / count,
    ]
  }
}
