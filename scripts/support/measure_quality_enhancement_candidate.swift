import CoreGraphics
import CoreImage
import Foundation

private enum QualityMeasurementError: Error {
  case invalidArguments
  case unreadableImage
  case invalidPipeline
  case renderFailed
}

@main
private enum QualityEnhancementMeasurement {
  private static let maxEdge: CGFloat = 2_048
  private static let strengths: [(String, Int, Int, Int, Int)] = [
    ("neutral", 0, 0, 0, 0),
    ("noise_reduction", 28, 0, 0, 0),
    ("low_light_recovery", 0, 32, 0, 0),
    ("haze_removal", 0, 0, 18, 0),
    ("detail_sharpening", 0, 0, 0, 16),
  ]

  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      throw QualityMeasurementError.invalidArguments
    }
    guard let source = CIImage(
      contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]),
      options: [.applyOrientationProperty: true]
    ) else {
      throw QualityMeasurementError.unreadableImage
    }
    let normalized = source.transformed(
      by: CGAffineTransform(
        translationX: -source.extent.minX,
        y: -source.extent.minY
      )
    )
    let longest = max(normalized.extent.width, normalized.extent.height)
    guard longest > 0 else { throw QualityMeasurementError.unreadableImage }
    let scale = min(1, maxEdge / longest)
    let input = normalized
      .applyingFilter(
        "CILanczosScaleTransform",
        parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
      )
      .transformed(
        by: CGAffineTransform(
          translationX: -normalized.extent.minX * scale,
          y: -normalized.extent.minY * scale
        )
      )
    let extent = input.extent.integral
    let context = CIContext(options: [.cacheIntermediates: false])
    var measurements: [String: Any] = [:]
    var neutralBytes: [UInt8]?
    for strength in strengths {
      guard let pipeline = IOSImagePipeline(
        arguments: recipe(
          noiseReduction: strength.1,
          lowLightRecovery: strength.2,
          hazeRemoval: strength.3,
          detailSharpening: strength.4
        )
      ) else {
        throw QualityMeasurementError.invalidPipeline
      }
      let output = pipeline.applying(
        to: input,
        extent: extent,
        portraitContext: .unavailable
      )
      let bytes = try rgbaBytes(output, extent: extent, context: context)
      if strength.0 == "neutral" { neutralBytes = bytes }
      measurements[strength.0] = metrics(bytes, width: Int(extent.width), height: Int(extent.height))
    }
    guard
      let neutralBytes,
      let zeroPipeline = IOSImagePipeline(
        arguments: recipe(
          noiseReduction: 0,
          lowLightRecovery: 0,
          hazeRemoval: 0,
          detailSharpening: 0
        )
      )
    else {
      throw QualityMeasurementError.invalidPipeline
    }
    let zeroBytes = try rgbaBytes(
      zeroPipeline.applying(
        to: input,
        extent: extent,
        portraitContext: .unavailable
      ),
      extent: extent,
      context: context
    )
    let result: [String: Any] = [
      "schema": 1,
      "pipeline_schema": 6,
      "max_edge": Int(maxEdge),
      "width": Int(extent.width),
      "height": Int(extent.height),
      "zero_is_exact": neutralBytes == zeroBytes,
      "measurements": measurements,
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }

  private static func recipe(
    noiseReduction: Int,
    lowLightRecovery: Int,
    hazeRemoval: Int,
    detailSharpening: Int
  ) -> [String: Any] {
    [
      "schemaVersion": 6,
      "workingColorSpace": "srgb",
      "adjustments": [
        "exposureEv": 0.0, "highlights": 0.0, "shadows": 0.0,
        "contrast": 0.0, "warmth": 0.0, "tint": 0.0,
        "saturation": 0.0, "clarity": 0.0,
      ],
      "geometry": [
        "normalizedCrop": [0.0, 0.0, 1.0, 1.0],
        "quarterTurns": 0,
        "straightenDegrees": 0.0,
      ],
      "portraitRecipeV2": [
        "recipeVersion": 2,
        "analysisVersion": "vision-multiface-v1",
        "effectVersion": "portrait-core-contract-v2",
        "textureSmoothing": 0,
        "skinToneLighting": 0,
        "blemishReduction": 0,
        "faceSlimming": 0,
        "torsoSlimming": 0,
      ],
      "faceSlimRecipeV1": [
        "recipeVersion": 1,
        "selectedTargetIndex": 0,
        "targetStrengths": [0.0],
      ],
      "qualityEnhancementRecipeV1": [
        "recipeVersion": 1,
        "noiseReduction": noiseReduction,
        "lowLightRecovery": lowLightRecovery,
        "hazeRemoval": hazeRemoval,
        "detailSharpening": detailSharpening,
      ],
    ]
  }

  private static func rgbaBytes(
    _ image: CIImage,
    extent: CGRect,
    context: CIContext
  ) throws -> [UInt8] {
    let width = Int(extent.width)
    let height = Int(extent.height)
    guard width > 0, height > 0,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw QualityMeasurementError.renderFailed }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    context.render(
      image,
      toBitmap: &bytes,
      rowBytes: width * 4,
      bounds: extent,
      format: .RGBA8,
      colorSpace: colorSpace
    )
    return bytes
  }

  private static func metrics(
    _ bytes: [UInt8],
    width: Int,
    height: Int
  ) -> [String: Any] {
    let count = width * height
    var luma = [Double](repeating: 0, count: count)
    var sum = 0.0
    var squared = 0.0
    var black = 0
    var white = 0
    for pixel in 0..<count {
      let offset = pixel * 4
      let value = (
        0.2126 * Double(bytes[offset])
          + 0.7152 * Double(bytes[offset + 1])
          + 0.0722 * Double(bytes[offset + 2])
      ) / 255
      luma[pixel] = value
      sum += value
      squared += value * value
      black += value <= 1.0 / 255 ? 1 : 0
      white += value >= 254.0 / 255 ? 1 : 0
    }
    var edge = 0.0
    var edgeCount = 0
    var residual = 0.0
    var residualCount = 0
    if width > 2, height > 2 {
      for y in 1..<(height - 1) {
        for x in 1..<(width - 1) {
          let center = luma[y * width + x]
          let left = luma[y * width + x - 1]
          let right = luma[y * width + x + 1]
          let up = luma[(y - 1) * width + x]
          let down = luma[(y + 1) * width + x]
          edge += abs(right - left) + abs(down - up)
          edgeCount += 2
          residual += abs(center - (left + right + up + down) / 4)
          residualCount += 1
        }
      }
    }
    let sampleCount = Double(count)
    let mean = sum / sampleCount
    return [
      "mean_luma": mean,
      "luma_standard_deviation": sqrt(max(0, squared / sampleCount - mean * mean)),
      "mean_edge_energy": edgeCount == 0 ? 0 : edge / Double(edgeCount),
      "mean_local_residual": residualCount == 0 ? 0 : residual / Double(residualCount),
      "black_clip_ratio": Double(black) / sampleCount,
      "white_clip_ratio": Double(white) / sampleCount,
    ]
  }
}
