import CoreGraphics
import CoreImage
import Foundation

private enum SemanticMeasurementError: Error {
  case invalidArguments
  case unreadableImage
  case invalidPipeline(String)
  case renderFailed
}

@main
private enum SemanticEditingMeasurement {
  private static let maxEdge: CGFloat = 1_024
  private static let context = CIContext(options: [.cacheIntermediates: false])

  static func main() throws {
    guard CommandLine.arguments.count == 3 else {
      throw SemanticMeasurementError.invalidArguments
    }
    let input = try loadImage(CommandLine.arguments[1])
    let extent = input.extent.integral
    let subjectMask = makeSubjectMask(extent: extent)
    let portraitContext = IOSPortraitRetouchContext(
      effectiveMask: nil,
      faceSlimTargets: [],
      bodyReshapeTargets: [],
      semanticSubjectMask: subjectMask
    )
    let neutral = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: neutralSemantic()
    )

    let emptyLocal = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic(localExposure: 40)
    )
    let emptyErase = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic()
    )

    let subjectExposure = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic(subjectExposure: 35)
    )
    let backgroundExposure = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic(backgroundExposure: -35)
    )
    let blur = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic(background: "blur", backgroundBlur: 45)
    )
    let white = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic(background: "white")
    )
    let image = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic(
        background: "image",
        backgroundImagePath: CommandLine.arguments[2]
      )
    )

    let localPoint = CGPoint(x: 0.2, y: 0.22)
    let local = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic(
        localExposure: 40,
        localAdjustmentStrokes: [stroke(operation: "paint", radius: 0.09, point: localPoint)]
      )
    )
    let erasePoint = CGPoint(x: 0.76, y: 0.26)
    let erased = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic(
        eraseStrokes: [[
          "radius": 0.08,
          "points": [[Double(erasePoint.x), Double(erasePoint.y)]],
        ]]
      )
    )

    let paintPoint = CGPoint(x: 0.16, y: 0.78)
    let paintedSubject = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic(
        background: "white",
        subjectMaskStrokes: [stroke(operation: "paint", radius: 0.09, point: paintPoint)]
      )
    )
    let eraseMaskPoint = CGPoint(x: 0.5, y: 0.5)
    let erasedSubject = try render(
      input,
      extent: extent,
      portraitContext: portraitContext,
      semantic: semantic(
        background: "white",
        subjectMaskStrokes: [stroke(operation: "erase", radius: 0.1, point: eraseMaskPoint)]
      )
    )
    let sourceBytes = try bytes(input)
    let semanticNeutralBytes = try bytes(IOSSemanticEditor.applying(
      to: input,
      parameters: .neutral,
      subjectMask: subjectMask,
      extent: extent
    ))

    let result: [String: Any] = [
      "schema": 1,
      "pipeline_schema": 10,
      "max_edge": Int(maxEdge),
      "width": Int(extent.width),
      "height": Int(extent.height),
      "zero_is_exact": semanticNeutralBytes == sourceBytes,
      "empty_local_mask_is_exact": emptyLocal == neutral,
      "empty_erase_mask_is_exact": emptyErase == neutral,
      "measurements": [
        "subject_exposure": subjectMetrics(subjectExposure, neutral: neutral, extent: extent),
        "background_exposure": backgroundMetrics(backgroundExposure, neutral: neutral, extent: extent),
        "background_blur": backgroundMetrics(blur, neutral: neutral, extent: extent),
        "background_white": backgroundMetrics(white, neutral: neutral, extent: extent),
        "background_image": backgroundMetrics(image, neutral: neutral, extent: extent),
        "local_adjustment": brushMetrics(local, neutral: neutral, extent: extent, point: localPoint, radius: 0.09),
        "erase": brushMetrics(erased, neutral: neutral, extent: extent, point: erasePoint, radius: 0.08),
        "mask_paint": brushMetrics(paintedSubject, neutral: white, extent: extent, point: paintPoint, radius: 0.09),
        "mask_erase": brushMetrics(erasedSubject, neutral: white, extent: extent, point: eraseMaskPoint, radius: 0.1),
      ],
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }

  private static func loadImage(_ path: String) throws -> CIImage {
    guard let source = CIImage(
      contentsOf: URL(fileURLWithPath: path),
      options: [.applyOrientationProperty: true]
    ) else { throw SemanticMeasurementError.unreadableImage }
    let normalized = source.transformed(by: CGAffineTransform(
      translationX: -source.extent.minX,
      y: -source.extent.minY
    ))
    let longest = max(normalized.extent.width, normalized.extent.height)
    guard longest > 0 else { throw SemanticMeasurementError.unreadableImage }
    let scale = min(1, maxEdge / longest)
    return normalized.applyingFilter(
      "CILanczosScaleTransform",
      parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
    ).transformed(by: CGAffineTransform(
      translationX: -normalized.extent.minX * scale,
      y: -normalized.extent.minY * scale
    )).cropped(to: CGRect(
      x: 0,
      y: 0,
      width: floor(normalized.extent.width * scale),
      height: floor(normalized.extent.height * scale)
    ))
  }

  private static func makeSubjectMask(extent: CGRect) -> CIImage {
    let center = CGPoint(x: extent.midX, y: extent.midY)
    let baseRadius = min(extent.width, extent.height) * 0.25
    let gradient = CIFilter(
      name: "CIRadialGradient",
      parameters: [
        "inputCenter": CIVector(cgPoint: center),
        "inputRadius0": baseRadius * 0.96,
        "inputRadius1": baseRadius,
        "inputColor0": CIColor.white,
        "inputColor1": CIColor.black,
      ]
    )!.outputImage!
    let scaleX = extent.width * 0.22 / baseRadius
    let scaleY = extent.height * 0.34 / baseRadius
    return gradient.transformed(by: CGAffineTransform(
      translationX: -center.x,
      y: -center.y
    )).transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
      .transformed(by: CGAffineTransform(translationX: center.x, y: center.y))
      .cropped(to: extent)
  }

  private static func render(
    _ input: CIImage,
    extent: CGRect,
    portraitContext: IOSPortraitRetouchContext,
    semantic: [String: Any]
  ) throws -> [UInt8] {
    let encoded = try JSONSerialization.data(withJSONObject: recipe(semantic: semantic))
    let methodChannelArguments = try JSONSerialization.jsonObject(with: encoded)
    guard let pipeline = IOSImagePipeline(arguments: methodChannelArguments) else {
      throw SemanticMeasurementError.invalidPipeline(semantic["background"] as? String ?? "unknown")
    }
    return try bytes(pipeline.applying(
      to: input,
      extent: extent,
      portraitContext: portraitContext
    ))
  }

  private static func bytes(_ image: CIImage) throws -> [UInt8] {
    let extent = image.extent.integral
    let width = Int(extent.width)
    let height = Int(extent.height)
    guard width > 0, height > 0,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw SemanticMeasurementError.renderFailed }
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

  private static func subjectMetrics(
    _ output: [UInt8], neutral: [UInt8], extent: CGRect
  ) -> [String: Any] {
    regionMetrics(output, neutral: neutral, extent: extent) { x, y in
      let value = ellipseValue(x: x, y: y)
      if value <= 0.68 { return true }
      if value >= 1.35 { return false }
      return nil
    }
  }

  private static func backgroundMetrics(
    _ output: [UInt8], neutral: [UInt8], extent: CGRect
  ) -> [String: Any] {
    regionMetrics(output, neutral: neutral, extent: extent) { x, y in
      let value = ellipseValue(x: x, y: y)
      if value >= 1.35 { return true }
      if value <= 0.68 { return false }
      return nil
    }
  }

  private static func brushMetrics(
    _ output: [UInt8],
    neutral: [UInt8],
    extent: CGRect,
    point: CGPoint,
    radius: CGFloat
  ) -> [String: Any] {
    let scale = min(extent.width, extent.height)
    return regionMetrics(output, neutral: neutral, extent: extent) { x, y in
      let dx = (x - point.x) * extent.width
      let dy = (y - point.y) * extent.height
      let distance = hypot(dx, dy) / scale
      if distance <= radius * 0.58 { return true }
      if distance >= radius * 1.5 { return false }
      return nil
    }
  }

  private static func ellipseValue(x: CGFloat, y: CGFloat) -> CGFloat {
    let dx = (x - 0.5) / 0.22
    let dy = (y - 0.5) / 0.34
    return sqrt(dx * dx + dy * dy)
  }

  private static func regionMetrics(
    _ output: [UInt8],
    neutral: [UInt8],
    extent: CGRect,
    selector: (CGFloat, CGFloat) -> Bool?
  ) -> [String: Any] {
    let width = Int(extent.width)
    let height = Int(extent.height)
    var targetTotal = 0.0
    var protectedTotal = 0.0
    var targetCount = 0
    var protectedCount = 0
    var targetValues: [Double] = []
    for y in 0..<height {
      for x in 0..<width {
        guard let target = selector(
          (CGFloat(x) + 0.5) / CGFloat(width),
          (CGFloat(y) + 0.5) / CGFloat(height)
        ) else { continue }
        let offset = (y * width + x) * 4
        let difference = (
          abs(Double(output[offset]) - Double(neutral[offset]))
            + abs(Double(output[offset + 1]) - Double(neutral[offset + 1]))
            + abs(Double(output[offset + 2]) - Double(neutral[offset + 2]))
        ) / 3 / 255
        if target {
          targetTotal += difference
          targetCount += 1
          targetValues.append(difference)
        } else {
          protectedTotal += difference
          protectedCount += 1
        }
      }
    }
    targetValues.sort()
    let percentileIndex = max(0, Int(Double(max(0, targetValues.count - 1)) * 0.95))
    return [
      "target_mean_difference": targetCount == 0 ? 0 : targetTotal / Double(targetCount),
      "target_p95_difference": targetValues.isEmpty ? 0 : targetValues[percentileIndex],
      "protected_mean_difference": protectedCount == 0 ? 0 : protectedTotal / Double(protectedCount),
    ]
  }

  private static func stroke(
    operation: String,
    radius: Double,
    point: CGPoint
  ) -> [String: Any] {
    [
      "operation": operation,
      "radius": radius,
      "points": [[Double(point.x), Double(point.y)]],
    ]
  }

  private static func neutralSemantic() -> [String: Any] { semantic() }

  private static func semantic(
    background: String = "original",
    backgroundImagePath: String = "",
    backgroundBlur: Int = 0,
    subjectExposure: Int = 0,
    backgroundExposure: Int = 0,
    localExposure: Int = 0,
    subjectMaskStrokes: [[String: Any]] = [],
    localAdjustmentStrokes: [[String: Any]] = [],
    eraseStrokes: [[String: Any]] = []
  ) -> [String: Any] {
    [
      "recipeVersion": 3,
      "background": background,
      "backgroundImagePath": backgroundImagePath,
      "backgroundImageResourceId": background == "image"
        ? "resource-v1-0000000000000000000000000000000000000000000000000000000000000000"
        : "",
      "backgroundBlur": backgroundBlur,
      "subjectExposure": subjectExposure,
      "subjectSaturation": 0,
      "backgroundExposure": backgroundExposure,
      "backgroundSaturation": 0,
      "localExposure": localExposure,
      "localSaturation": 0,
      "subjectMaskStrokes": subjectMaskStrokes,
      "localAdjustmentStrokes": localAdjustmentStrokes,
      "eraseStrokes": eraseStrokes,
    ]
  }

  private static func recipe(semantic: [String: Any]) -> [String: Any] {
    [
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
        "recipeVersion": 1, "selectedTargetIndex": 0, "targetStrengths": [0.0],
      ],
      "qualityEnhancementRecipeV1": [
        "recipeVersion": 1, "noiseReduction": 0, "lowLightRecovery": 0,
        "hazeRemoval": 0, "detailSharpening": 0,
      ],
      "basicEditingRecipeV1": [
        "recipeVersion": 1, "flipHorizontal": false, "flipVertical": false,
        "perspectiveHorizontal": 0.0, "perspectiveVertical": 0.0,
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
      "semanticEditingRecipeV2": semantic,
    ]
  }
}
