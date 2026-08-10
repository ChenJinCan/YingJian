import CoreGraphics
import CoreImage
import Foundation

private enum BasicToneMeasurementError: Error {
  case invalidArguments
  case unreadableImage
  case invalidPipeline
  case renderFailed
}

@main
private enum BasicToneMeasurement {
  private static let maxEdge: CGFloat = 512
  private static let context = CIContext(options: [.cacheIntermediates: false])
  private static let profiles: [(String, String, Double)] = [
    ("exposure", "exposureEv", 0.5),
    ("contrast", "contrast", 0.35),
    ("warmth", "warmth", 0.4),
    ("highlights", "highlights", 0.4),
    ("shadows", "shadows", 0.4),
    ("tint", "tint", 0.4),
    ("saturation", "saturation", 0.35),
    ("clarity", "clarity", 0.25),
  ]

  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      throw BasicToneMeasurementError.invalidArguments
    }
    guard let source = CIImage(
      contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]),
      options: [.applyOrientationProperty: true]
    ) else { throw BasicToneMeasurementError.unreadableImage }
    let normalized = source.transformed(by: CGAffineTransform(
      translationX: -source.extent.minX,
      y: -source.extent.minY
    ))
    let longest = max(normalized.extent.width, normalized.extent.height)
    guard longest > 0 else { throw BasicToneMeasurementError.unreadableImage }
    let scale = min(1, maxEdge / longest)
    let input = normalized.applyingFilter(
      "CILanczosScaleTransform",
      parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
    )
    let extent = input.extent.integral
    let neutralBytes = try render(input, extent: extent, adjustments: [:])
    let neutralMetrics = metrics(neutralBytes, width: Int(extent.width), neutral: neutralBytes)
    var measurements: [String: Any] = [:]
    for (name, field, magnitude) in profiles {
      let negative = try render(input, extent: extent, adjustments: [field: -magnitude])
      let positive = try render(input, extent: extent, adjustments: [field: magnitude])
      measurements[name] = [
        "negative": metrics(negative, width: Int(extent.width), neutral: neutralBytes),
        "positive": metrics(positive, width: Int(extent.width), neutral: neutralBytes),
      ]
    }
    let explicitZero = try render(
      input,
      extent: extent,
      adjustments: Dictionary(uniqueKeysWithValues: profiles.map { ($0.1, 0.0) })
    )
    let result: [String: Any] = [
      "schema": 1,
      "pipeline_schema": 10,
      "max_edge": Int(maxEdge),
      "width": Int(extent.width),
      "height": Int(extent.height),
      "zero_is_exact": explicitZero == neutralBytes,
      "neutral": neutralMetrics,
      "parameters": measurements,
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }

  private static func render(
    _ input: CIImage,
    extent: CGRect,
    adjustments: [String: Double]
  ) throws -> [UInt8] {
    guard let pipeline = IOSImagePipeline(arguments: recipe(adjustments: adjustments))
    else { throw BasicToneMeasurementError.invalidPipeline }
    let output = pipeline.applying(to: input, extent: extent, portraitContext: .unavailable)
    let width = Int(output.extent.width)
    let height = Int(output.extent.height)
    guard width > 0, height > 0,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw BasicToneMeasurementError.renderFailed }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    context.render(
      output,
      toBitmap: &bytes,
      rowBytes: width * 4,
      bounds: output.extent,
      format: .RGBA8,
      colorSpace: colorSpace
    )
    return bytes
  }

  private static func metrics(
    _ bytes: [UInt8],
    width: Int,
    neutral: [UInt8]
  ) -> [String: Any] {
    let pixels = bytes.count / 4
    let height = pixels / width
    var luma = [Double](repeating: 0, count: pixels)
    var lumaSum = 0.0
    var redSum = 0.0
    var greenSum = 0.0
    var blueSum = 0.0
    var chromaSum = 0.0
    var midpointDistance = 0.0
    var black = 0
    var white = 0
    var differenceSum = 0.0
    var differences = [Double]()
    differences.reserveCapacity(pixels)
    for pixel in 0..<pixels {
      let offset = pixel * 4
      let red = Double(bytes[offset]) / 255
      let green = Double(bytes[offset + 1]) / 255
      let blue = Double(bytes[offset + 2]) / 255
      let value = 0.2126 * red + 0.7152 * green + 0.0722 * blue
      luma[pixel] = value
      lumaSum += value
      redSum += red
      greenSum += green
      blueSum += blue
      chromaSum += max(red, green, blue) - min(red, green, blue)
      midpointDistance += (abs(red - 0.5) + abs(green - 0.5) + abs(blue - 0.5)) / 3
      black += max(bytes[offset], bytes[offset + 1], bytes[offset + 2]) <= 1 ? 1 : 0
      white += min(bytes[offset], bytes[offset + 1], bytes[offset + 2]) >= 254 ? 1 : 0
      let difference = max(
        abs(Double(bytes[offset]) - Double(neutral[offset])),
        abs(Double(bytes[offset + 1]) - Double(neutral[offset + 1])),
        abs(Double(bytes[offset + 2]) - Double(neutral[offset + 2]))
      ) / 255
      differences.append(difference)
      differenceSum += (
        abs(Double(bytes[offset]) - Double(neutral[offset]))
          + abs(Double(bytes[offset + 1]) - Double(neutral[offset + 1]))
          + abs(Double(bytes[offset + 2]) - Double(neutral[offset + 2]))
      ) / 3 / 255
    }
    var edgeSum = 0.0
    var edgeCount = 0
    for y in 0..<height {
      for x in 0..<width {
        let value = luma[y * width + x]
        if x + 1 < width {
          edgeSum += abs(value - luma[y * width + x + 1])
          edgeCount += 1
        }
        if y + 1 < height {
          edgeSum += abs(value - luma[(y + 1) * width + x])
          edgeCount += 1
        }
      }
    }
    differences.sort()
    let p95Index = min(differences.count - 1, Int(Double(differences.count - 1) * 0.95))
    let count = Double(pixels)
    return [
      "mean_luma": lumaSum / count,
      "mean_rgb": [redSum / count, greenSum / count, blueSum / count],
      "mean_chroma": chromaSum / count,
      "mean_rgb_midpoint_distance": midpointDistance / count,
      "mean_edge_energy": edgeCount == 0 ? 0 : edgeSum / Double(edgeCount),
      "mean_absolute_rgb_difference": differenceSum / count,
      "p95_max_channel_difference": differences[p95Index],
      "black_clip_ratio": Double(black) / count,
      "white_clip_ratio": Double(white) / count,
    ]
  }

  private static func recipe(adjustments: [String: Double]) -> [String: Any] {
    func value(_ name: String) -> Double { adjustments[name] ?? 0 }
    return [
      "schemaVersion": 10,
      "workingColorSpace": "srgb",
      "adjustments": [
        "exposureEv": value("exposureEv"),
        "highlights": value("highlights"),
        "shadows": value("shadows"),
        "contrast": value("contrast"),
        "warmth": value("warmth"),
        "tint": value("tint"),
        "saturation": value("saturation"),
        "clarity": value("clarity"),
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
        "recipeVersion": 1, "selectedTargetIndex": 0, "targetStrengths": [0.0],
      ],
      "qualityEnhancementRecipeV1": [
        "recipeVersion": 1, "noiseReduction": 0, "lowLightRecovery": 0,
        "hazeRemoval": 0, "detailSharpening": 0,
      ],
      "basicEditingRecipeV1": [
        "recipeVersion": 1, "flipHorizontal": false, "flipVertical": false,
        "perspectiveHorizontal": 0, "perspectiveVertical": 0,
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
