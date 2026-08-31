import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum IOSPhotoFileRenderError: Error {
  case decodeFailed
  case renderFailed
}

struct IOSPhotoRenderedFile {
  let width: Int
  let height: Int
  let metadata: [String: Any]
}

struct IOSPhotoExportOptions {
  let format: String
  let longEdgePixels: Int?
  let compressionQuality: Double

  static let defaults = IOSPhotoExportOptions(
    format: "jpeg",
    longEdgePixels: nil,
    compressionQuality: 0.95
  )

  init(format: String, longEdgePixels: Int?, compressionQuality: Double) {
    self.format = format
    self.longEdgePixels = longEdgePixels
    self.compressionQuality = compressionQuality
  }

  init?(arguments: Any?) {
    guard
      let values = arguments as? [String: Any],
      let format = values["format"] as? String,
      ["jpeg", "heif"].contains(format),
      let size = values["size"] as? String,
      ["original", "longEdge"].contains(size),
      let quality = values["quality"] as? String,
      let compressionQuality = ["high": 0.95, "standard": 0.86, "compact": 0.74][quality],
      values["colorSpace"] as? String == "srgb"
    else { return nil }
    let longEdge = values["longEdgePixels"] as? NSNumber
    if size == "longEdge" {
      guard
        let longEdge,
        CFGetTypeID(longEdge) != CFBooleanGetTypeID(),
        longEdge.doubleValue.rounded(.towardZero) == longEdge.doubleValue,
        (640...16384).contains(longEdge.intValue)
      else { return nil }
      longEdgePixels = longEdge.intValue
    } else {
      guard longEdge == nil else { return nil }
      longEdgePixels = nil
    }
    self.format = format
    self.compressionQuality = compressionQuality
  }
}

/// Renders one app-owned source file through the same production pipeline used
/// before PhotoKit persistence. Keeping this seam independent from PhotoKit
/// makes the final JPEG contract directly inspectable without weakening the
/// system-library save boundary.
struct IOSPhotoFileRenderer {
  let context: CIContext

  func render(
    sourcePath: String,
    pipeline: IOSImagePipeline,
    destinationURL: URL,
    options: IOSPhotoExportOptions = .defaults,
    preparedPortraitContext: IOSPortraitRetouchContext? = nil,
    cancellationCheck: () throws -> Void = {}
  ) throws -> IOSPhotoRenderedFile {
    try cancellationCheck()
    guard let input = CIImage(
      contentsOf: URL(fileURLWithPath: sourcePath),
      options: [.applyOrientationProperty: true]
    ) else {
      throw IOSPhotoFileRenderError.decodeFailed
    }
    try cancellationCheck()
    let normalizedInput = input.transformed(
      by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY)
    )
    let metadata = ImageExportMetadata.sanitize(input.properties)
    let sourceExtent = normalizedInput.extent.integral
    try cancellationCheck()
    let portraitContext = preparedPortraitContext
      ?? (pipeline.textureSmoothing > 0
        || pipeline.skinToneLighting > 0
        || pipeline.blemishReduction > 0
        || !pipeline.targetedPortraitAdjustments.isEmpty
        || pipeline.portraitStrength > 0
        || pipeline.faceSlimStrengths.contains(where: { $0 > 0 })
        || pipeline.bodySlimStrength > 0
        || pipeline.faceGeometryTargets.contains(where: {
          $0.headSize != 0 || $0.jaw != 0 || $0.chin != 0 || $0.eyes != 0
            || $0.nose != 0 || $0.mouth != 0
        })
        || pipeline.bodyGeometryTargets.contains(where: {
          $0.height != 0 || $0.shoulders != 0 || $0.waist != 0 || $0.legs != 0
        })
        || pipeline.semanticEditing != .neutral
        ? IOSPortraitRetoucher.prepare(source: normalizedInput, extent: sourceExtent)
        : .unavailable)
    try cancellationCheck()
    var output = pipeline
      .applying(
        to: normalizedInput,
        extent: sourceExtent,
        portraitContext: portraitContext
      )
      .settingProperties(metadata)
    try cancellationCheck()
    if let longEdge = options.longEdgePixels {
      let currentLongEdge = max(output.extent.width, output.extent.height)
      if currentLongEdge > CGFloat(longEdge) {
        let scale = CGFloat(longEdge) / currentLongEdge
        output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      }
    }
    let outputExtent = output.extent.integral
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw IOSPhotoFileRenderError.renderFailed
    }
    try cancellationCheck()
    do {
      let representationOptions = [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption:
          options.compressionQuality
      ]
      if options.format == "heif" {
        try context.writeHEIFRepresentation(
          of: output,
          to: destinationURL,
          format: .RGBA8,
          colorSpace: colorSpace,
          options: representationOptions
        )
      } else {
        try context.writeJPEGRepresentation(
          of: output,
          to: destinationURL,
          colorSpace: colorSpace,
          options: representationOptions
        )
      }
    } catch {
      try? FileManager.default.removeItem(at: destinationURL)
      throw IOSPhotoFileRenderError.renderFailed
    }
    try cancellationCheck()
    return IOSPhotoRenderedFile(
      width: Int(outputExtent.width),
      height: Int(outputExtent.height),
      metadata: metadata
    )
  }
}

enum ImageExportMetadata {
  static func sanitize(_ source: [String: Any]) -> [String: Any] {
    var output: [String: Any] = [
      kCGImagePropertyOrientation as String: 1
    ]

    if let sourceExif = source[kCGImagePropertyExifDictionary as String] as? [String: Any] {
      var exif: [String: Any] = [:]
      copy(
        kCGImagePropertyExifDateTimeOriginal as String,
        from: sourceExif,
        to: &exif
      )
      copy(
        kCGImagePropertyExifDateTimeDigitized as String,
        from: sourceExif,
        to: &exif
      )
      if !exif.isEmpty {
        output[kCGImagePropertyExifDictionary as String] = exif
      }
    }

    if let sourceTiff = source[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
      var tiff: [String: Any] = [:]
      copy(kCGImagePropertyTIFFDateTime as String, from: sourceTiff, to: &tiff)
      if !tiff.isEmpty {
        output[kCGImagePropertyTIFFDictionary as String] = tiff
      }
    }
    return output
  }

  static func captureDate(from metadata: [String: Any]) -> Date? {
    let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
    let value =
      exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String
      ?? exif?[kCGImagePropertyExifDateTimeDigitized as String] as? String
      ?? tiff?[kCGImagePropertyTIFFDateTime as String] as? String
    guard let value else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter.date(from: value)
  }

  private static func copy(
    _ key: String,
    from source: [String: Any],
    to destination: inout [String: Any]
  ) {
    if let value = source[key] {
      destination[key] = value
    }
  }
}

struct IOSEraseStroke: Equatable {
  let radius: Double
  let points: [CGPoint]
}

struct IOSMaskStroke: Equatable {
  let operation: String
  let radius: Double
  let points: [CGPoint]
}

struct IOSSemanticEditingParameters: Equatable {
  let background: String
  let backgroundImagePath: String
  let backgroundBlur: Int
  let subjectExposure: Int
  let subjectSaturation: Int
  let backgroundExposure: Int
  let backgroundSaturation: Int
  let localExposure: Int
  let localSaturation: Int
  let subjectMaskStrokes: [IOSMaskStroke]
  let localAdjustmentStrokes: [IOSMaskStroke]
  let eraseStrokes: [IOSEraseStroke]

  static let neutral = IOSSemanticEditingParameters(
    background: "original", backgroundImagePath: "", backgroundBlur: 0,
    subjectExposure: 0, subjectSaturation: 0,
    backgroundExposure: 0, backgroundSaturation: 0,
    localExposure: 0, localSaturation: 0,
    subjectMaskStrokes: [], localAdjustmentStrokes: [],
    eraseStrokes: []
  )
}

enum IOSSemanticEditor {
  static func applying(
    to source: CIImage,
    parameters: IOSSemanticEditingParameters,
    subjectMask: CIImage?,
    extent: CGRect
  ) -> CIImage {
    var output = applyingEraseStrokes(
      to: source.cropped(to: extent),
      strokes: parameters.eraseStrokes,
      extent: extent
    )
    let foregroundMask = applyingMaskStrokes(
      to: subjectMask,
      strokes: parameters.subjectMaskStrokes,
      extent: extent
    )
    if parameters.localExposure != 0 || parameters.localSaturation != 0,
       !parameters.localAdjustmentStrokes.isEmpty,
       let localMask = applyingMaskStrokes(
         to: nil,
         strokes: parameters.localAdjustmentStrokes,
         extent: extent
       )
    {
      output = applyingLocalColor(
        to: output,
        exposure: parameters.localExposure,
        saturation: parameters.localSaturation,
        mask: localMask,
        extent: extent
      )
    }
    guard let foregroundMask else { return output }
    let backgroundMask = foregroundMask
      .applyingFilter("CIColorInvert")
      .cropped(to: extent)

    if parameters.subjectExposure != 0 || parameters.subjectSaturation != 0 {
      output = applyingLocalColor(
        to: output,
        exposure: parameters.subjectExposure,
        saturation: parameters.subjectSaturation,
        mask: foregroundMask,
        extent: extent
      )
    }
    if parameters.backgroundExposure != 0 || parameters.backgroundSaturation != 0 {
      output = applyingLocalColor(
        to: output,
        exposure: parameters.backgroundExposure,
        saturation: parameters.backgroundSaturation,
        mask: backgroundMask,
        extent: extent
      )
    }

    let replacement: CIImage?
    switch parameters.background {
    case "blur":
      let radius = 2 + Double(parameters.backgroundBlur) / 100 * 28
      replacement = output.clampedToExtent().applyingFilter(
        "CIGaussianBlur",
        parameters: [kCIInputRadiusKey: radius]
      ).cropped(to: extent)
    case "white":
      replacement = CIImage(color: .white).cropped(to: extent)
    case "black":
      replacement = CIImage(color: .black).cropped(to: extent)
    case "warm":
      replacement = CIImage(
        color: CIColor(red: 0.94, green: 0.86, blue: 0.78, alpha: 1)
      ).cropped(to: extent)
    case "cool":
      replacement = CIImage(
        color: CIColor(red: 0.78, green: 0.87, blue: 0.94, alpha: 1)
      ).cropped(to: extent)
    case "image":
      replacement = aspectFillBackground(
        path: parameters.backgroundImagePath,
        extent: extent
      )
    default:
      replacement = nil
    }
    guard let replacement else { return output }
    return replacement.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: output,
        kCIInputMaskImageKey: backgroundMask,
      ]
    ).cropped(to: extent)
  }

  private static func aspectFillBackground(
    path: String,
    extent: CGRect
  ) -> CIImage? {
    guard !path.isEmpty,
          FileManager.default.fileExists(atPath: path),
          let image = CIImage(
            contentsOf: URL(fileURLWithPath: path),
            options: [.applyOrientationProperty: true]
          ),
          image.extent.width > 0,
          image.extent.height > 0
    else { return nil }
    let scale = max(
      extent.width / image.extent.width,
      extent.height / image.extent.height
    )
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let translation = CGAffineTransform(
      translationX: extent.midX - scaled.extent.midX,
      y: extent.midY - scaled.extent.midY
    )
    return scaled.transformed(by: translation).cropped(to: extent)
  }

  private static func applyingLocalColor(
    to input: CIImage,
    exposure: Int,
    saturation: Int,
    mask: CIImage,
    extent: CGRect
  ) -> CIImage {
    var adjusted = input
    if exposure != 0 {
      adjusted = adjusted.applyingFilter(
        "CIExposureAdjust",
        parameters: [kCIInputEVKey: Double(exposure) / 100]
      ).cropped(to: extent)
    }
    if saturation != 0 {
      adjusted = adjusted.applyingFilter(
        "CIColorControls",
        parameters: [kCIInputSaturationKey: 1 + Double(saturation) / 100 * 0.8]
      ).cropped(to: extent)
    }
    return adjusted.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: mask,
      ]
    ).cropped(to: extent)
  }

  static func applyingMaskStrokes(
    to baseMask: CIImage?,
    strokes: [IOSMaskStroke],
    extent: CGRect
  ) -> CIImage? {
    guard baseMask != nil || !strokes.isEmpty else { return nil }
    var mask = (baseMask ?? CIImage(color: .black).cropped(to: extent))
      .cropped(to: extent)
    let minimumDimension = min(extent.width, extent.height)
    for stroke in strokes {
      let radius = max(2, minimumDimension * stroke.radius)
      var previous: CGPoint?
      for normalized in stroke.points {
        let center = CGPoint(
          x: extent.minX + normalized.x * extent.width,
          y: extent.maxY - normalized.y * extent.height
        )
        if let previous,
           hypot(center.x - previous.x, center.y - previous.y) < radius * 0.35
        {
          continue
        }
        previous = center
        guard let brush = CIFilter(
          name: "CIRadialGradient",
          parameters: [
            "inputCenter": CIVector(cgPoint: center),
            "inputRadius0": radius * 0.72,
            "inputRadius1": radius,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.black,
          ]
        )?.outputImage?.cropped(to: extent) else { continue }
        if stroke.operation == "paint" {
          mask = brush.applyingFilter(
            "CIMaximumCompositing",
            parameters: [kCIInputBackgroundImageKey: mask]
          ).cropped(to: extent)
        } else {
          let inverse = brush.applyingFilter("CIColorInvert").cropped(to: extent)
          mask = mask.applyingFilter(
            "CIMultiplyCompositing",
            parameters: [kCIInputBackgroundImageKey: inverse]
          ).cropped(to: extent)
        }
      }
    }
    return mask
  }

  private static func applyingEraseStrokes(
    to source: CIImage,
    strokes: [IOSEraseStroke],
    extent: CGRect
  ) -> CIImage {
    var output = source
    let minimumDimension = min(extent.width, extent.height)
    for stroke in strokes {
      let radius = max(2, minimumDimension * stroke.radius)
      var previous: CGPoint?
      for normalized in stroke.points {
        let center = CGPoint(
          x: extent.minX + normalized.x * extent.width,
          y: extent.maxY - normalized.y * extent.height
        )
        if let previous,
           hypot(center.x - previous.x, center.y - previous.y) < radius * 0.35
        {
          continue
        }
        previous = center
        output = applyingEraseStamp(
          to: output,
          center: center,
          radius: radius,
          extent: extent
        )
      }
    }
    return output
  }

  private static func applyingEraseStamp(
    to input: CIImage,
    center: CGPoint,
    radius: CGFloat,
    extent: CGRect
  ) -> CIImage {
    let directions: [CGPoint] = [
      CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0),
      CGPoint(x: 0, y: -1), CGPoint(x: 0, y: 1),
      CGPoint(x: -0.7, y: -0.7), CGPoint(x: 0.7, y: -0.7),
      CGPoint(x: -0.7, y: 0.7), CGPoint(x: 0.7, y: 0.7),
    ]
    let samples = directions.map { direction in
      input.clampedToExtent()
        .transformed(by: CGAffineTransform(
          translationX: direction.x * radius * 1.15,
          y: direction.y * radius * 1.15
        ))
        .applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: 0.125, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 0.125, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 0.125, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.125),
        ])
        .cropped(to: extent)
    }
    let repair = samples.dropFirst().reduce(samples[0]) { current, sample in
      sample.applyingFilter(
        "CIAdditionCompositing",
        parameters: [kCIInputBackgroundImageKey: current]
      ).cropped(to: extent)
    }
    let brush = CIFilter(
      name: "CIRadialGradient",
      parameters: [
        "inputCenter": CIVector(cgPoint: center),
        "inputRadius0": radius * 0.72,
        "inputRadius1": radius,
        "inputColor0": CIColor.white,
        "inputColor1": CIColor.black,
      ]
    )?.outputImage?.cropped(to: extent)
    guard let brush else { return input }
    return repair.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: brush,
      ]
    ).cropped(to: extent)
  }
}

struct IOSTargetedPortraitAdjustment: Equatable {
  let targetId: String
  /// Normalized coordinates with a top-left origin, matching Flutter analysis.
  let region: CGRect
  let textureSmoothing: Int
  let skinToneLighting: Int
  let blemishReduction: Int
}

struct IOSDirectionalLightingAdjustment: Equatable {
  let targetId: String
  let region: CGRect
  let azimuth: Double
  let intensity: Int
}

struct IOSImagePipeline {
  let schemaVersion: Int
  let exposureEV: Double
  let highlights: Double
  let shadows: Double
  let contrast: Double
  let warmth: Double
  let tint: Double
  let saturation: Double
  let clarity: Double
  let portraitStrength: Double
  let faceSlimStrength: Double
  let faceSlimStrengths: [Double]
  let bodySlimStrength: Double
  let textureSmoothing: Int
  let skinToneLighting: Int
  let blemishReduction: Int
  let faceSlimming: Int
  let torsoSlimming: Int
  let portraitAnalysisVersion: String
  let portraitEffectVersion: String
  let noiseReduction: Int
  let lowLightRecovery: Int
  let hazeRemoval: Int
  let detailSharpening: Int
  let flipHorizontal: Bool
  let flipVertical: Bool
  let perspectiveHorizontal: Double
  let perspectiveVertical: Double
  let photoFilter: String
  let filterStrength: Int
  let hslAdjustments: [String: [String: Double]]
  let selectedFaceGeometryIndex: Int
  let faceGeometryTargets: [IOSFaceGeometryParameters]
  let selectedBodyGeometryIndex: Int
  let bodyGeometryTargets: [IOSBodyGeometryParameters]
  let semanticEditing: IOSSemanticEditingParameters
  let targetedPortraitAdjustments: [IOSTargetedPortraitAdjustment]
  let directionalLightingAdjustments: [IOSDirectionalLightingAdjustment]
  let crop: CGRect
  let quarterTurns: Int
  let straightenDegrees: Double

  init?(arguments: Any?) {
    guard let envelope = arguments as? [String: Any] else { return nil }
    let pipeline: [String: Any]
    if let renderPlan = envelope["renderPlanV1"] {
      guard
        Self.isValidRenderPlan(renderPlan),
        let plan = renderPlan as? [String: Any],
        let backendPayload = plan["backendPayload"] as? [String: Any]
      else { return nil }
      pipeline = backendPayload
    } else {
      pipeline = envelope
    }
    guard
      let schemaVersion = Self.exactInteger(pipeline["schemaVersion"]),
      (1...12).contains(schemaVersion),
      pipeline["workingColorSpace"] as? String == "srgb",
      let adjustments = pipeline["adjustments"] as? [String: Any],
      let exposureEV = Self.finiteNumber(adjustments["exposureEv"]),
      let contrast = Self.finiteNumber(adjustments["contrast"]),
      let warmth = Self.finiteNumber(adjustments["warmth"]),
      exposureEV.isFinite,
      contrast.isFinite,
      warmth.isFinite,
      (-2.0...2.0).contains(exposureEV),
      (-1.0...1.0).contains(contrast),
      (-1.0...1.0).contains(warmth)
    else {
      return nil
    }
    self.exposureEV = exposureEV
    self.schemaVersion = schemaVersion
    self.contrast = contrast
    self.warmth = warmth
    if schemaVersion == 1 {
      highlights = 0
      shadows = 0
      tint = 0
      saturation = 0
      clarity = 0
      portraitStrength = 0
      faceSlimStrength = 0
      faceSlimStrengths = [0]
      bodySlimStrength = 0
      textureSmoothing = 0
      skinToneLighting = 0
      blemishReduction = 0
      faceSlimming = 0
      torsoSlimming = 0
      portraitAnalysisVersion = "vision-multiface-v1"
      portraitEffectVersion = "portrait-core-contract-v2"
      noiseReduction = 0
      lowLightRecovery = 0
      hazeRemoval = 0
      detailSharpening = 0
      flipHorizontal = false
      flipVertical = false
      perspectiveHorizontal = 0
      perspectiveVertical = 0
      photoFilter = "none"
      filterStrength = 0
      hslAdjustments = [:]
      selectedFaceGeometryIndex = 0
      faceGeometryTargets = [IOSFaceGeometryParameters(
        faceSlim: 0, headSize: 0, jaw: 0, chin: 0, eyes: 0, nose: 0, mouth: 0
      )]
      selectedBodyGeometryIndex = 0
      bodyGeometryTargets = [IOSBodyGeometryParameters(
        slimming: 0, height: 0, shoulders: 0, waist: 0, legs: 0
      )]
      semanticEditing = .neutral
      targetedPortraitAdjustments = []
      directionalLightingAdjustments = []
      crop = CGRect(x: 0, y: 0, width: 1, height: 1)
      quarterTurns = 0
      straightenDegrees = 0
      return
    }
    guard
      let highlights = Self.normalized(adjustments["highlights"]),
      let shadows = Self.normalized(adjustments["shadows"]),
      let tint = Self.normalized(adjustments["tint"]),
      let saturation = Self.normalized(adjustments["saturation"]),
      let clarity = Self.normalized(adjustments["clarity"]),
      let geometry = pipeline["geometry"] as? [String: Any],
      let normalizedCrop = geometry["normalizedCrop"] as? [Any],
      normalizedCrop.count == 4,
      let quarterTurns = Self.exactInteger(geometry["quarterTurns"]),
      (0...3).contains(quarterTurns),
      let straightenDegrees = Self.finiteNumber(geometry["straightenDegrees"]),
      (-45.0...45.0).contains(straightenDegrees)
    else {
      return nil
    }
    let values = normalizedCrop.compactMap(Self.finiteNumber)
    guard
      values.count == normalizedCrop.count,
      values.allSatisfy({ $0.isFinite && (0.0...1.0).contains($0) }),
      values[2] > values[0],
      values[3] > values[1]
    else {
      return nil
    }
    self.highlights = highlights
    self.shadows = shadows
    self.tint = tint
    self.saturation = saturation
    self.clarity = clarity
    if schemaVersion >= 4 {
      guard
        pipeline["portrait"] == nil,
        pipeline["reshape"] == nil,
        let portraitRecipe = pipeline["portraitRecipeV2"] as? [String: Any],
        Set(portraitRecipe.keys) == Set([
          "recipeVersion",
          "analysisVersion",
          "effectVersion",
          "textureSmoothing",
          "skinToneLighting",
          "blemishReduction",
          "faceSlimming",
          "torsoSlimming",
        ]),
        Self.exactInteger(portraitRecipe["recipeVersion"]) == 2,
        portraitRecipe["analysisVersion"] as? String == "vision-multiface-v1",
        portraitRecipe["effectVersion"] as? String == "portrait-core-contract-v2",
        let textureSmoothing = Self.percentage(portraitRecipe["textureSmoothing"]),
        let skinToneLighting = Self.percentage(portraitRecipe["skinToneLighting"]),
        let blemishReduction = Self.percentage(portraitRecipe["blemishReduction"]),
        let faceSlimming = Self.percentage(portraitRecipe["faceSlimming"]),
        let torsoSlimming = Self.percentage(portraitRecipe["torsoSlimming"])
      else {
        return nil
      }
      portraitStrength = 0
      if schemaVersion >= 5 {
        guard
          let faceSlimRecipe = pipeline["faceSlimRecipeV1"] as? [String: Any],
          Set(faceSlimRecipe.keys) == Set([
            "recipeVersion",
            "selectedTargetIndex",
            "targetStrengths",
          ]),
          Self.exactInteger(faceSlimRecipe["recipeVersion"]) == 1,
          let selectedTargetIndex = Self.exactInteger(
            faceSlimRecipe["selectedTargetIndex"]
          ),
          let rawStrengths = faceSlimRecipe["targetStrengths"] as? [Any],
          (1...3).contains(rawStrengths.count)
        else {
          return nil
        }
        let strengths = rawStrengths.compactMap(Self.finiteNumber)
        guard
          strengths.count == rawStrengths.count,
          strengths.allSatisfy({ $0.isFinite && (0.0...1.0).contains($0) }),
          strengths.indices.contains(selectedTargetIndex)
        else {
          return nil
        }
        faceSlimStrengths = strengths
        faceSlimStrength = strengths[selectedTargetIndex]
      } else {
        faceSlimStrength = Double(faceSlimming) / 100
        faceSlimStrengths = [faceSlimStrength]
      }
      bodySlimStrength = Double(torsoSlimming) / 100
      self.textureSmoothing = textureSmoothing
      self.skinToneLighting = skinToneLighting
      self.blemishReduction = blemishReduction
      self.faceSlimming = faceSlimming
      self.torsoSlimming = torsoSlimming
      portraitAnalysisVersion = "vision-multiface-v1"
      portraitEffectVersion = "portrait-core-contract-v2"
    } else {
      guard
        let portrait = pipeline["portrait"] as? [String: Any],
        Self.exactInteger(portrait["recipeVersion"]) == 1,
        let portraitStrength = Self.finiteNumber(portrait["strength"]),
        (0.0...1.0).contains(portraitStrength)
      else {
        return nil
      }
      self.portraitStrength = portraitStrength
      textureSmoothing = Int((portraitStrength * 100).rounded())
      skinToneLighting = Int((portraitStrength * 100).rounded())
      blemishReduction = 0
      portraitAnalysisVersion = "vision-multiface-v1"
      portraitEffectVersion = "portrait-core-contract-v2"
      if schemaVersion >= 3 {
        guard
          let reshape = pipeline["reshape"] as? [String: Any],
          Self.exactInteger(reshape["recipeVersion"]) == 1,
          let faceSlimStrength = Self.finiteNumber(reshape["faceSlimStrength"]),
          let bodySlimStrength = Self.finiteNumber(reshape["bodySlimStrength"]),
          (0.0...1.0).contains(faceSlimStrength),
          (0.0...1.0).contains(bodySlimStrength)
        else {
          return nil
        }
        self.faceSlimStrength = faceSlimStrength
        faceSlimStrengths = [faceSlimStrength]
        self.bodySlimStrength = bodySlimStrength
        faceSlimming = Int((faceSlimStrength * 100).rounded())
        torsoSlimming = Int((bodySlimStrength * 100).rounded())
      } else {
        faceSlimStrength = 0
        faceSlimStrengths = [0]
        bodySlimStrength = 0
        faceSlimming = 0
        torsoSlimming = 0
      }
    }
    if schemaVersion >= 6 {
      guard
        let qualityRecipe = pipeline["qualityEnhancementRecipeV1"] as? [String: Any],
        Set(qualityRecipe.keys) == Set([
          "recipeVersion",
          "noiseReduction",
          "lowLightRecovery",
          "hazeRemoval",
          "detailSharpening",
        ]),
        Self.exactInteger(qualityRecipe["recipeVersion"]) == 1,
        let noiseReduction = Self.percentage(qualityRecipe["noiseReduction"]),
        let lowLightRecovery = Self.percentage(qualityRecipe["lowLightRecovery"]),
        let hazeRemoval = Self.percentage(qualityRecipe["hazeRemoval"]),
        let detailSharpening = Self.percentage(qualityRecipe["detailSharpening"])
      else {
        return nil
      }
      self.noiseReduction = noiseReduction
      self.lowLightRecovery = lowLightRecovery
      self.hazeRemoval = hazeRemoval
      self.detailSharpening = detailSharpening
    } else {
      noiseReduction = 0
      lowLightRecovery = 0
      hazeRemoval = 0
      detailSharpening = 0
    }
    if schemaVersion >= 7 {
      guard
        let basic = pipeline["basicEditingRecipeV1"] as? [String: Any],
        Set(basic.keys) == Set([
          "recipeVersion", "flipHorizontal", "flipVertical",
          "perspectiveHorizontal", "perspectiveVertical", "filter",
          "filterStrength", "hsl",
        ]),
        Self.exactInteger(basic["recipeVersion"]) == 1,
        let flipHorizontal = basic["flipHorizontal"] as? Bool,
        let flipVertical = basic["flipVertical"] as? Bool,
        let perspectiveHorizontal = Self.finiteNumber(basic["perspectiveHorizontal"]),
        let perspectiveVertical = Self.finiteNumber(basic["perspectiveVertical"]),
        (-30.0...30.0).contains(perspectiveHorizontal),
        (-30.0...30.0).contains(perspectiveVertical),
        let photoFilter = basic["filter"] as? String,
        Self.supportedFilters.contains(photoFilter),
        let filterStrength = Self.percentage(basic["filterStrength"]),
        let rawHsl = basic["hsl"] as? [String: Any],
        let hsl = Self.parseHsl(rawHsl)
      else { return nil }
      self.flipHorizontal = flipHorizontal
      self.flipVertical = flipVertical
      self.perspectiveHorizontal = perspectiveHorizontal
      self.perspectiveVertical = perspectiveVertical
      self.photoFilter = photoFilter
      self.filterStrength = photoFilter == "none" ? 0 : filterStrength
      hslAdjustments = hsl
    } else {
      flipHorizontal = false
      flipVertical = false
      perspectiveHorizontal = 0
      perspectiveVertical = 0
      photoFilter = "none"
      filterStrength = 0
      hslAdjustments = [:]
    }
    if schemaVersion >= 8 {
      guard
        let geometryRecipe = pipeline["portraitGeometryRecipeV1"] as? [String: Any],
        Set(geometryRecipe.keys) == Set([
          "recipeVersion", "selectedFaceIndex", "faceTargets",
          "selectedBodyIndex", "bodyTargets",
        ]),
        Self.exactInteger(geometryRecipe["recipeVersion"]) == 1,
        let selectedFaceIndex = Self.exactInteger(geometryRecipe["selectedFaceIndex"]),
        let rawFaceTargets = geometryRecipe["faceTargets"] as? [Any],
        (1...3).contains(rawFaceTargets.count),
        rawFaceTargets.indices.contains(selectedFaceIndex),
        let selectedBodyIndex = Self.exactInteger(geometryRecipe["selectedBodyIndex"]),
        let rawBodyTargets = geometryRecipe["bodyTargets"] as? [Any],
        (1...3).contains(rawBodyTargets.count),
        rawBodyTargets.indices.contains(selectedBodyIndex),
        let faceTargets = Self.parseFaceGeometryTargets(rawFaceTargets),
        let bodyTargets = Self.parseBodyGeometryTargets(rawBodyTargets)
      else { return nil }
      selectedFaceGeometryIndex = selectedFaceIndex
      faceGeometryTargets = faceTargets
      selectedBodyGeometryIndex = selectedBodyIndex
      bodyGeometryTargets = bodyTargets
    } else {
      selectedFaceGeometryIndex = min(
        max(0, faceSlimStrengths.firstIndex(of: faceSlimStrength) ?? 0),
        faceSlimStrengths.count - 1
      )
      faceGeometryTargets = faceSlimStrengths.map {
        IOSFaceGeometryParameters(
          faceSlim: Int(($0 * 100).rounded()), headSize: 0, jaw: 0,
          chin: 0, eyes: 0, nose: 0, mouth: 0
        )
      }
      selectedBodyGeometryIndex = 0
      bodyGeometryTargets = [IOSBodyGeometryParameters(
        slimming: Int((bodySlimStrength * 100).rounded()),
        height: 0, shoulders: 0, waist: 0, legs: 0
      )]
    }
    if schemaVersion >= 10 {
      guard
        pipeline["semanticEditingRecipeV1"] == nil,
        let semantic = pipeline["semanticEditingRecipeV2"] as? [String: Any],
        let semanticVersion = Self.exactInteger(semantic["recipeVersion"]),
        (3...4).contains(semanticVersion)
      else { return nil }
      var semanticKeys = Set([
          "recipeVersion", "background", "backgroundBlur",
          "backgroundImagePath", "backgroundImageResourceId",
          "subjectExposure", "subjectSaturation", "backgroundExposure",
          "backgroundSaturation", "localExposure", "localSaturation",
          "subjectMaskStrokes", "localAdjustmentStrokes", "eraseStrokes",
        ])
      if semanticVersion >= 4 {
        semanticKeys.formUnion([
          "subjectMaskResourceId", "localMaskResourceId", "eraseMaskResourceId",
        ])
      }
      guard
        Set(semantic.keys) == semanticKeys,
        let background = semantic["background"] as? String,
        Self.supportedBackgroundTreatments.contains(background),
        let backgroundImagePath = semantic["backgroundImagePath"] as? String,
        (background == "image") == !backgroundImagePath.isEmpty,
        let backgroundImageResourceId = semantic["backgroundImageResourceId"] as? String,
        (background == "image") == (backgroundImageResourceId.range(
          of: "^resource-v1-[0-9a-f]{64}$",
          options: .regularExpression
        ) != nil),
        let backgroundBlur = Self.percentage(semantic["backgroundBlur"]),
        let subjectExposure = Self.signedPercentage(semantic["subjectExposure"]),
        let subjectSaturation = Self.signedPercentage(semantic["subjectSaturation"]),
        let backgroundExposure = Self.signedPercentage(semantic["backgroundExposure"]),
        let backgroundSaturation = Self.signedPercentage(semantic["backgroundSaturation"]),
        let localExposure = Self.signedPercentage(semantic["localExposure"]),
        let localSaturation = Self.signedPercentage(semantic["localSaturation"]),
        let rawSubjectMaskStrokes = semantic["subjectMaskStrokes"] as? [Any],
        rawSubjectMaskStrokes.count <= 40,
        let subjectMaskStrokes = Self.parseMaskStrokes(rawSubjectMaskStrokes),
        let rawLocalStrokes = semantic["localAdjustmentStrokes"] as? [Any],
        rawLocalStrokes.count <= 40,
        let localStrokes = Self.parseMaskStrokes(rawLocalStrokes),
        let rawEraseStrokes = semantic["eraseStrokes"] as? [Any],
        rawEraseStrokes.count <= 20,
        let eraseStrokes = Self.parseEraseStrokes(rawEraseStrokes)
      else { return nil }
      if semanticVersion >= 4 {
        guard
          let subjectMaskResourceId = semantic["subjectMaskResourceId"] as? String,
          let localMaskResourceId = semantic["localMaskResourceId"] as? String,
          let eraseMaskResourceId = semantic["eraseMaskResourceId"] as? String,
          [subjectMaskResourceId, localMaskResourceId, eraseMaskResourceId].allSatisfy({
            $0.isEmpty || $0.range(
              of: "^resource-v1-[0-9a-f]{64}$",
              options: .regularExpression
            ) != nil
          })
        else { return nil }
      }
      semanticEditing = IOSSemanticEditingParameters(
        background: background, backgroundImagePath: backgroundImagePath,
        backgroundBlur: backgroundBlur,
        subjectExposure: subjectExposure, subjectSaturation: subjectSaturation,
        backgroundExposure: backgroundExposure,
        backgroundSaturation: backgroundSaturation,
        localExposure: localExposure, localSaturation: localSaturation,
        subjectMaskStrokes: subjectMaskStrokes,
        localAdjustmentStrokes: localStrokes,
        eraseStrokes: eraseStrokes
      )
    } else if schemaVersion >= 9 {
      guard
        let semantic = pipeline["semanticEditingRecipeV1"] as? [String: Any],
        Set(semantic.keys) == Set([
          "recipeVersion", "background", "backgroundBlur",
          "subjectExposure", "subjectSaturation", "backgroundExposure",
          "backgroundSaturation", "eraseStrokes",
        ]),
        Self.exactInteger(semantic["recipeVersion"]) == 1,
        let background = semantic["background"] as? String,
        Self.supportedBackgroundTreatments.contains(background),
        let backgroundBlur = Self.percentage(semantic["backgroundBlur"]),
        let subjectExposure = Self.signedPercentage(semantic["subjectExposure"]),
        let subjectSaturation = Self.signedPercentage(semantic["subjectSaturation"]),
        let backgroundExposure = Self.signedPercentage(semantic["backgroundExposure"]),
        let backgroundSaturation = Self.signedPercentage(semantic["backgroundSaturation"]),
        let rawStrokes = semantic["eraseStrokes"] as? [Any],
        rawStrokes.count <= 20,
        let strokes = Self.parseEraseStrokes(rawStrokes)
      else { return nil }
      semanticEditing = IOSSemanticEditingParameters(
        background: background, backgroundImagePath: "",
        backgroundBlur: backgroundBlur,
        subjectExposure: subjectExposure, subjectSaturation: subjectSaturation,
        backgroundExposure: backgroundExposure,
        backgroundSaturation: backgroundSaturation,
        localExposure: 0, localSaturation: 0,
        subjectMaskStrokes: [], localAdjustmentStrokes: [],
        eraseStrokes: strokes
      )
    } else {
      semanticEditing = .neutral
    }
    if schemaVersion >= 11 {
      guard
        let targeted = pipeline["targetedPortraitRecipeV1"] as? [String: Any],
        Set(targeted.keys) == Set(["schemaVersion", "adjustments"]),
        Self.exactInteger(targeted["schemaVersion"]) == 1,
        let rawAdjustments = targeted["adjustments"] as? [Any],
        rawAdjustments.count <= 6,
        let parsed = Self.parseTargetedPortraitAdjustments(rawAdjustments)
      else { return nil }
      targetedPortraitAdjustments = parsed
    } else {
      targetedPortraitAdjustments = []
    }
    if schemaVersion >= 12 {
      guard
        let lighting = pipeline["directionalLightingRecipeV1"] as? [String: Any],
        Set(lighting.keys) == Set(["schemaVersion", "adjustments"]),
        Self.exactInteger(lighting["schemaVersion"]) == 1,
        let rawAdjustments = lighting["adjustments"] as? [Any],
        rawAdjustments.count <= 6,
        let parsed = Self.parseDirectionalLightingAdjustments(rawAdjustments)
      else { return nil }
      directionalLightingAdjustments = parsed
    } else {
      directionalLightingAdjustments = []
    }
    crop = CGRect(
      x: values[0],
      y: values[1],
      width: values[2] - values[0],
      height: values[3] - values[1]
    )
    self.quarterTurns = quarterTurns
    self.straightenDegrees = straightenDegrees
  }

  private static func exactInteger(_ value: Any?) -> Int? {
    guard let double = finiteNumber(value), double.rounded(.towardZero) == double else {
      return nil
    }
    return Int(exactly: double)
  }

  private static func isValidRenderPlan(_ value: Any) -> Bool {
    guard
      let plan = value as? [String: Any],
      exactInteger(plan["protocolVersion"]) == 1,
      let planId = plan["planId"] as? String,
      planId.range(of: #"^rp1-[a-f0-9]{8}$"#, options: .regularExpression) != nil,
      let sourceId = plan["sourceId"] as? String,
      !sourceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let revision = exactInteger(plan["stateRevision"]), revision >= 0,
      let stages = plan["stages"] as? [Any],
      let capabilities = plan["requiredCapabilities"] as? [Any],
      let output = plan["outputRequirements"] as? [String: Any],
      let purpose = output["purpose"] as? String,
      purpose == "preview" || purpose == "export",
      output["colorSpace"] as? String == "srgb",
      output["format"] is String,
      output["quality"] is String,
      plan["backendPayload"] is [String: Any],
      stages.allSatisfy({ $0 is [String: Any] }),
      capabilities.allSatisfy({ $0 is String })
    else { return false }
    return true
  }

  private static func finiteNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else { return nil }
    guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let result = number.doubleValue
    return result.isFinite ? result : nil
  }

  private static func normalized(_ value: Any?) -> Double? {
    guard let result = finiteNumber(value),
          (-1.0...1.0).contains(result)
    else { return nil }
    return result
  }

  private static func percentage(_ value: Any?) -> Int? {
    guard let result = exactInteger(value), (0...100).contains(result) else {
      return nil
    }
    return result
  }

  private static func signedPercentage(_ value: Any?) -> Int? {
    guard let result = exactInteger(value), (-100...100).contains(result) else {
      return nil
    }
    return result
  }

  private static func roundedPercentage(_ value: Any?) -> Int? {
    guard let result = finiteNumber(value), (0.0...100.0).contains(result) else {
      return nil
    }
    return Int(result.rounded())
  }

  private static func roundedSignedPercentage(_ value: Any?) -> Int? {
    guard let result = finiteNumber(value), (-100.0...100.0).contains(result) else {
      return nil
    }
    return Int(result.rounded())
  }

  private static func parseFaceGeometryTargets(
    _ rawTargets: [Any]
  ) -> [IOSFaceGeometryParameters]? {
    var parsed: [IOSFaceGeometryParameters] = []
    for raw in rawTargets {
      guard
        let target = raw as? [String: Any],
        Set(target.keys) == Set([
          "faceSlim", "headSize", "jaw", "chin", "eyes", "nose", "mouth",
        ]),
        let faceSlim = roundedPercentage(target["faceSlim"]),
        let headSize = roundedPercentage(target["headSize"]),
        let jaw = roundedSignedPercentage(target["jaw"]),
        let chin = roundedSignedPercentage(target["chin"]),
        let eyes = roundedSignedPercentage(target["eyes"]),
        let nose = roundedSignedPercentage(target["nose"]),
        let mouth = roundedSignedPercentage(target["mouth"])
      else { return nil }
      parsed.append(IOSFaceGeometryParameters(
        faceSlim: faceSlim, headSize: headSize, jaw: jaw, chin: chin,
        eyes: eyes, nose: nose, mouth: mouth
      ))
    }
    return parsed
  }

  private static func parseBodyGeometryTargets(
    _ rawTargets: [Any]
  ) -> [IOSBodyGeometryParameters]? {
    var parsed: [IOSBodyGeometryParameters] = []
    for raw in rawTargets {
      guard
        let target = raw as? [String: Any],
        Set(target.keys) == Set(["slimming", "height", "shoulders", "waist", "legs"]),
        let slimming = roundedPercentage(target["slimming"]),
        let height = roundedPercentage(target["height"]),
        let shoulders = roundedSignedPercentage(target["shoulders"]),
        let waist = roundedSignedPercentage(target["waist"]),
        let legs = roundedPercentage(target["legs"])
      else { return nil }
      parsed.append(IOSBodyGeometryParameters(
        slimming: slimming, height: height, shoulders: shoulders,
        waist: waist, legs: legs
      ))
    }
    return parsed
  }

  private static func parseTargetedPortraitAdjustments(
    _ rawAdjustments: [Any]
  ) -> [IOSTargetedPortraitAdjustment]? {
    var parsed: [IOSTargetedPortraitAdjustment] = []
    var targetIds = Set<String>()
    for raw in rawAdjustments {
      guard
        let adjustment = raw as? [String: Any],
        Set(adjustment.keys) == Set([
          "targetId", "region", "textureSmoothing",
          "skinToneLighting", "blemishReduction",
        ]),
        let targetId = adjustment["targetId"] as? String,
        isStableTargetId(targetId),
        targetIds.insert(targetId).inserted,
        let rawRegion = adjustment["region"] as? [String: Any],
        Set(rawRegion.keys) == Set(["left", "top", "right", "bottom"]),
        let left = finiteNumber(rawRegion["left"]),
        let top = finiteNumber(rawRegion["top"]),
        let right = finiteNumber(rawRegion["right"]),
        let bottom = finiteNumber(rawRegion["bottom"]),
        [left, top, right, bottom].allSatisfy({ (0.0...1.0).contains($0) }),
        right > left, bottom > top,
        let textureSmoothing = percentage(adjustment["textureSmoothing"]),
        let skinToneLighting = percentage(adjustment["skinToneLighting"]),
        let blemishReduction = percentage(adjustment["blemishReduction"])
      else { return nil }
      parsed.append(IOSTargetedPortraitAdjustment(
        targetId: targetId,
        region: CGRect(x: left, y: top, width: right - left, height: bottom - top),
        textureSmoothing: textureSmoothing,
        skinToneLighting: skinToneLighting,
        blemishReduction: blemishReduction
      ))
    }
    return parsed
  }

  private static func parseDirectionalLightingAdjustments(
    _ rawAdjustments: [Any]
  ) -> [IOSDirectionalLightingAdjustment]? {
    var parsed: [IOSDirectionalLightingAdjustment] = []
    var targetIds = Set<String>()
    for raw in rawAdjustments {
      guard
        let adjustment = raw as? [String: Any],
        Set(adjustment.keys) == Set(["targetId", "region", "azimuth", "intensity"]),
        let targetId = adjustment["targetId"] as? String,
        isStableTargetId(targetId), targetIds.insert(targetId).inserted,
        let rawRegion = adjustment["region"] as? [String: Any],
        Set(rawRegion.keys) == Set(["left", "top", "right", "bottom"]),
        let left = finiteNumber(rawRegion["left"]),
        let top = finiteNumber(rawRegion["top"]),
        let right = finiteNumber(rawRegion["right"]),
        let bottom = finiteNumber(rawRegion["bottom"]),
        [left, top, right, bottom].allSatisfy({ (0.0...1.0).contains($0) }),
        right > left, bottom > top,
        let azimuth = finiteNumber(adjustment["azimuth"]),
        (-90.0...90.0).contains(azimuth),
        let intensity = percentage(adjustment["intensity"])
      else { return nil }
      parsed.append(IOSDirectionalLightingAdjustment(
        targetId: targetId,
        region: CGRect(x: left, y: top, width: right - left, height: bottom - top),
        azimuth: azimuth,
        intensity: intensity
      ))
    }
    return parsed
  }

  private static func isStableTargetId(_ value: String) -> Bool {
    guard value.hasPrefix("target-v1-"), value.count == 18 else { return false }
    return value.dropFirst(10).allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }

  private static let supportedFilters: Set<String> = [
    "none", "clean", "portrait", "cinematic", "film", "warmSun",
    "coolAir", "vivid", "faded", "noir", "food", "landscape", "night",
  ]

  private static let supportedBackgroundTreatments: Set<String> = [
    "original", "blur", "white", "black", "warm", "cool", "image",
  ]

  private static func parseEraseStrokes(_ rawStrokes: [Any]) -> [IOSEraseStroke]? {
    var parsed: [IOSEraseStroke] = []
    for raw in rawStrokes {
      guard
        let stroke = raw as? [String: Any],
        Set(stroke.keys) == Set(["radius", "points"]),
        let radius = finiteNumber(stroke["radius"]),
        (0.005...0.12).contains(radius),
        let rawPoints = stroke["points"] as? [Any],
        (1...200).contains(rawPoints.count)
      else { return nil }
      var points: [CGPoint] = []
      for rawPoint in rawPoints {
        guard
          let pair = rawPoint as? [Any], pair.count == 2,
          let x = finiteNumber(pair[0]), let y = finiteNumber(pair[1]),
          (0.0...1.0).contains(x), (0.0...1.0).contains(y)
        else { return nil }
        points.append(CGPoint(x: x, y: y))
      }
      parsed.append(IOSEraseStroke(radius: radius, points: points))
    }
    return parsed
  }

  private static func parseMaskStrokes(_ rawStrokes: [Any]) -> [IOSMaskStroke]? {
    var parsed: [IOSMaskStroke] = []
    for raw in rawStrokes {
      guard
        let stroke = raw as? [String: Any],
        Set(stroke.keys) == Set(["operation", "radius", "points"]),
        let operation = stroke["operation"] as? String,
        operation == "paint" || operation == "erase",
        let radius = finiteNumber(stroke["radius"]),
        (0.005...0.12).contains(radius),
        let rawPoints = stroke["points"] as? [Any],
        (1...200).contains(rawPoints.count)
      else { return nil }
      var points: [CGPoint] = []
      for rawPoint in rawPoints {
        guard
          let pair = rawPoint as? [Any], pair.count == 2,
          let x = finiteNumber(pair[0]), let y = finiteNumber(pair[1]),
          (0.0...1.0).contains(x), (0.0...1.0).contains(y)
        else { return nil }
        points.append(CGPoint(x: x, y: y))
      }
      parsed.append(IOSMaskStroke(operation: operation, radius: radius, points: points))
    }
    return parsed
  }

  private static let supportedHslChannels: Set<String> = [
    "red", "orange", "yellow", "green", "cyan", "blue", "purple", "magenta",
  ]

  private static func parseHsl(_ raw: [String: Any]) -> [String: [String: Double]]? {
    guard Set(raw.keys).isSubset(of: supportedHslChannels) else { return nil }
    var parsed: [String: [String: Double]] = [:]
    for (channel, value) in raw {
      guard
        let values = value as? [String: Any],
        Set(values.keys) == Set(["hue", "saturation", "lightness"]),
        let hue = finiteNumber(values["hue"]),
        let saturation = finiteNumber(values["saturation"]),
        let lightness = finiteNumber(values["lightness"]),
        (-100.0...100.0).contains(hue),
        (-100.0...100.0).contains(saturation),
        (-100.0...100.0).contains(lightness)
      else { return nil }
      parsed[channel] = ["hue": hue, "saturation": saturation, "lightness": lightness]
    }
    return parsed
  }

  private var colorTransform: ColorTransform {
    let exposureScale = pow(2, exposureEV)
    let redWarmthScale = 1 + warmth * 0.15
    let blueWarmthScale = 1 - warmth * 0.15
    return ColorTransform(
      redScale: exposureScale * redWarmthScale,
      greenScale: exposureScale,
      blueScale: exposureScale * blueWarmthScale
    )
  }

  private func matchedFaceTargetIndex(
    for adjustment: IOSTargetedPortraitAdjustment,
    targets: [IOSFaceSlimTargetContext],
    extent: CGRect,
    excluding usedIndices: Set<Int>
  ) -> Int? {
    matchedFaceTargetIndex(
      for: adjustment.region,
      targets: targets,
      extent: extent,
      excluding: usedIndices
    )
  }

  private func matchedFaceTargetIndex(
    for adjustment: IOSDirectionalLightingAdjustment,
    targets: [IOSFaceSlimTargetContext],
    extent: CGRect,
    excluding usedIndices: Set<Int>
  ) -> Int? {
    matchedFaceTargetIndex(
      for: adjustment.region,
      targets: targets,
      extent: extent,
      excluding: usedIndices
    )
  }

  private func matchedFaceTargetIndex(
    for adjustmentRegion: CGRect,
    targets: [IOSFaceSlimTargetContext],
    extent: CGRect,
    excluding usedIndices: Set<Int>
  ) -> Int? {
    guard extent.width > 0, extent.height > 0 else { return nil }
    func normalizedTopLeft(_ bounds: CGRect) -> CGRect {
      CGRect(
        x: (bounds.minX - extent.minX) / extent.width,
        y: 1 - ((bounds.maxY - extent.minY) / extent.height),
        width: bounds.width / extent.width,
        height: bounds.height / extent.height
      )
    }
    func intersectionOverUnion(_ left: CGRect, _ right: CGRect) -> CGFloat {
      let intersection = left.intersection(right)
      guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
        return 0
      }
      let intersectionArea = intersection.width * intersection.height
      let unionArea = left.width * left.height + right.width * right.height - intersectionArea
      return unionArea > 0 ? intersectionArea / unionArea : 0
    }
    let candidates = targets.indices.compactMap { index -> (Int, CGFloat, CGFloat)? in
      guard !usedIndices.contains(index) else { return nil }
      let region = normalizedTopLeft(targets[index].features.faceBounds)
      let iou = intersectionOverUnion(adjustmentRegion, region)
      let centerDistance = hypot(
        adjustmentRegion.midX - region.midX,
        adjustmentRegion.midY - region.midY
      )
      return (index, iou, centerDistance)
    }.sorted { left, right in
      if abs(left.1 - right.1) > 0.000_001 { return left.1 > right.1 }
      return left.2 < right.2
    }
    guard let best = candidates.first, best.1 >= 0.65, best.2 <= 0.08 else {
      return nil
    }
    if candidates.count > 1 {
      let runnerUp = candidates[1]
      guard best.1 - runnerUp.1 >= 0.10 || runnerUp.2 - best.2 >= 0.04 else {
        return nil
      }
    }
    return best.0
  }

  private func applyingDirectionalLighting(
    to input: CIImage,
    adjustment: IOSDirectionalLightingAdjustment,
    target: IOSFaceSlimTargetContext,
    extent: CGRect
  ) -> CIImage {
    let strength = Double(adjustment.intensity) / 100
    guard strength > 0 else { return input }
    let faceBounds = target.features.faceBounds.intersection(extent)
    guard !faceBounds.isNull, faceBounds.width > 0 else { return input }
    let direction = adjustment.azimuth / 90
    let directionalAmount = abs(direction)
    let startX = direction <= 0 ? faceBounds.minX : faceBounds.maxX
    let endX = direction <= 0 ? faceBounds.maxX : faceBounds.minX
    let gradient = CIFilter(
      name: "CILinearGradient",
      parameters: [
        "inputPoint0": CIVector(x: startX, y: faceBounds.midY),
        "inputPoint1": CIVector(x: endX, y: faceBounds.midY),
        "inputColor0": CIColor.white,
        "inputColor1": CIColor(
          red: 1 - 0.65 * directionalAmount,
          green: 1 - 0.65 * directionalAmount,
          blue: 1 - 0.65 * directionalAmount,
          alpha: 1
        ),
      ]
    )?.outputImage?.cropped(to: extent)
    guard let gradient else { return input }
    let weightedMask = gradient.applyingFilter(
      "CIMultiplyCompositing",
      parameters: [kCIInputBackgroundImageKey: target.mask.cropped(to: extent)]
    ).cropped(to: extent)
    let lit = input.applyingFilter(
      "CIExposureAdjust",
      parameters: [kCIInputEVKey: 0.42 * strength]
    ).cropped(to: extent)
    return lit.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: weightedMask,
      ]
    ).cropped(to: extent)
  }

  func applying(
    to input: CIImage,
    extent: CGRect,
    portraitContext: IOSPortraitRetouchContext? = nil
  ) -> CIImage {
    let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
      .cropped(to: extent)
    let opaqueInput = input.composited(over: white)
    var reshapedInput = opaqueInput
    if schemaVersion >= 8 && bodyGeometryTargets.contains(where: {
      $0.slimming != 0 || $0.height != 0 || $0.shoulders != 0 || $0.waist != 0 || $0.legs != 0
    }) {
      let context = portraitContext ?? IOSPortraitRetoucher.prepare(
        source: opaqueInput,
        extent: extent
      )
      reshapedInput = IOSPortraitRetoucher.applyingBodyGeometry(
        to: reshapedInput,
        parameters: bodyGeometryTargets,
        extent: extent,
        context: context
      )
    } else if bodySlimStrength > 0 {
      let context = portraitContext ?? IOSPortraitRetoucher.prepare(
        source: opaqueInput,
        extent: extent
      )
      reshapedInput = IOSPortraitRetoucher.applyingBodySlim(
        to: reshapedInput,
        strength: bodySlimStrength,
        extent: extent,
        context: context
      )
    }
    if schemaVersion >= 8 && faceGeometryTargets.contains(where: {
      $0.faceSlim != 0 || $0.headSize != 0 || $0.jaw != 0 || $0.chin != 0
        || $0.eyes != 0 || $0.nose != 0 || $0.mouth != 0
    }) {
      let context = portraitContext ?? IOSPortraitRetoucher.prepare(
        source: opaqueInput,
        extent: extent
      )
      reshapedInput = IOSPortraitRetoucher.applyingFaceGeometry(
        to: reshapedInput,
        parameters: faceGeometryTargets,
        extent: extent,
        context: context
      )
    } else if faceSlimStrengths.contains(where: { $0 > 0 }) {
      let context = portraitContext ?? IOSPortraitRetoucher.prepare(
        source: opaqueInput,
        extent: extent
      )
      reshapedInput = IOSPortraitRetoucher.applyingFaceSlim(
        to: reshapedInput,
        strengths: faceSlimStrengths,
        extent: extent,
        context: context
      )
    }
    let transform = colorTransform
    var output = reshapedInput.applyingFilter(
      "CIColorMatrix",
      parameters: [
        "inputRVector": CIVector(x: transform.redScale, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: transform.greenScale, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: transform.blueScale, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
      ]
    ).cropped(to: extent)

    if contrast != 0 {
      let dimension = 32
      if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
        output = output.applyingFilter(
          "CIColorCubeWithColorSpace",
          parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": Self.contrastCubeData(
              dimension: dimension,
              contrast: contrast
            ),
            "inputColorSpace": colorSpace,
          ]
        ).cropped(to: extent)
      }
    }

    if highlights != 0 {
      let dimension = 32
      if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
        output = output.applyingFilter(
          "CIColorCubeWithColorSpace",
          parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": Self.highlightCubeData(
              dimension: dimension,
              highlights: highlights
            ),
            "inputColorSpace": colorSpace,
          ]
        ).cropped(to: extent)
      }
    }
    if shadows != 0 {
      let dimension = 32
      if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
        output = output.applyingFilter(
          "CIColorCubeWithColorSpace",
          parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": Self.shadowCubeData(
              dimension: dimension,
              shadows: shadows
            ),
            "inputColorSpace": colorSpace,
          ]
        ).cropped(to: extent)
      }
    }
    if saturation != 0 {
      output = output.applyingFilter(
        "CIColorControls",
        parameters: [kCIInputSaturationKey: 1 + saturation]
      ).cropped(to: extent)
    }
    if tint != 0 {
      output = output.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: tint * 0.04, y: -tint * 0.025, z: tint * 0.04, w: 0),
        ]
      ).cropped(to: extent)
    }
    if filterStrength > 0, photoFilter != "none" {
      output = applyingPhotoFilter(to: output, extent: extent)
    }
    if !hslAdjustments.isEmpty, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
      let dimension = 32
      output = output.applyingFilter(
        "CIColorCubeWithColorSpace",
        parameters: [
          "inputCubeDimension": dimension,
          "inputCubeData": Self.hslCubeData(dimension: dimension, adjustments: hslAdjustments),
          "inputColorSpace": colorSpace,
        ]
      ).cropped(to: extent)
    }
    if noiseReduction > 0 {
      let strength = Double(noiseReduction) / 100
      output = output.applyingFilter(
        "CINoiseReduction",
        parameters: [
          "inputNoiseLevel": 0.025 + strength * 0.075,
          "inputSharpness": 0.0,
        ]
      ).cropped(to: extent)
    }
    if lowLightRecovery > 0 {
      let dimension = 32
      if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
        output = output.applyingFilter(
          "CIColorCubeWithColorSpace",
          parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": Self.shadowCubeData(
              dimension: dimension,
              shadows: Double(lowLightRecovery) / 100 * 0.65
            ),
            "inputColorSpace": colorSpace,
          ]
        ).cropped(to: extent)
      }
    }
    if hazeRemoval > 0 {
      let strength = Double(hazeRemoval) / 100
      let dimension = 32
      if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
        output = output.applyingFilter(
          "CIColorCubeWithColorSpace",
          parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": Self.contrastCubeData(
              dimension: dimension,
              contrast: strength * 0.18
            ),
            "inputColorSpace": colorSpace,
          ]
        ).cropped(to: extent)
      }
      output = output.applyingFilter(
        "CIColorControls",
        parameters: [kCIInputSaturationKey: 1 + strength * 0.05]
      ).cropped(to: extent)
    }
    if clarity != 0 {
      let clarityInput = output
      let sharpened = clarityInput.applyingFilter(
        "CISharpenLuminance",
        parameters: [kCIInputSharpnessKey: clarity * 0.8]
      ).cropped(to: extent)
      let grayscale = clarityInput.applyingFilter(
        "CIColorControls",
        parameters: [kCIInputSaturationKey: 0]
      ).cropped(to: extent)
      let midtoneMask = grayscale.applyingFilter(
        "CIColorPolynomial",
        parameters: [
          "inputRedCoefficients": CIVector(x: 0, y: 4, z: -4, w: 0),
          "inputGreenCoefficients": CIVector(x: 0, y: 4, z: -4, w: 0),
          "inputBlueCoefficients": CIVector(x: 0, y: 4, z: -4, w: 0),
          "inputAlphaCoefficients": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]
      ).cropped(to: extent)
      output = sharpened.applyingFilter(
        "CIBlendWithMask",
        parameters: [
          kCIInputBackgroundImageKey: clarityInput,
          kCIInputMaskImageKey: midtoneMask,
        ]
      ).cropped(to: extent)
    }
    if detailSharpening > 0 {
      output = output.applyingFilter(
        "CISharpenLuminance",
        parameters: [
          kCIInputSharpnessKey: Double(detailSharpening) / 100 * 0.5,
        ]
      ).cropped(to: extent)
    }
    if schemaVersion >= 4 {
      if blemishReduction > 0, let mask = portraitContext?.effectiveMask {
        output = IOSBlemishReductionCandidate.applying(
          to: output,
          strength: Double(blemishReduction) / 100,
          effectiveFaceMask: mask,
          extent: extent
        )
      }
      if skinToneLighting > 0, let mask = portraitContext?.effectiveMask {
        output = IOSPortraitRetoucher.applyingSkinToneLighting(
          to: output,
          strength: Double(skinToneLighting) / 100,
          mask: mask,
          extent: extent
        )
      }
      if textureSmoothing > 0, let mask = portraitContext?.effectiveMask {
        output = IOSPortraitRetoucher.applyingTextureSmoothing(
          to: output,
          strength: Double(textureSmoothing) / 100,
          mask: mask,
          extent: extent
        )
      }
    } else if portraitStrength > 0 {
      if let portraitContext {
        output = IOSPortraitRetoucher.applying(
          to: output,
          strength: portraitStrength,
          extent: extent,
          context: portraitContext
        )
      } else {
        output = IOSPortraitRetoucher.applying(
          to: output,
          strength: portraitStrength,
          extent: extent
        )
      }
    }
    if schemaVersion >= 11, let portraitContext {
      var usedTargetIndices = Set<Int>()
      for adjustment in targetedPortraitAdjustments {
        guard let targetIndex = matchedFaceTargetIndex(
          for: adjustment,
          targets: portraitContext.faceTargets,
          extent: extent,
          excluding: usedTargetIndices
        ) else {
          continue
        }
        usedTargetIndices.insert(targetIndex)
        let mask = portraitContext.faceTargets[targetIndex].mask
        if adjustment.blemishReduction > 0 {
          output = IOSBlemishReductionCandidate.applying(
            to: output,
            strength: Double(adjustment.blemishReduction) / 100,
            effectiveFaceMask: mask,
            extent: extent
          )
        }
        if adjustment.skinToneLighting > 0 {
          output = IOSPortraitRetoucher.applyingSkinToneLighting(
            to: output,
            strength: Double(adjustment.skinToneLighting) / 100,
            mask: mask,
            extent: extent
          )
        }
        if adjustment.textureSmoothing > 0 {
          output = IOSPortraitRetoucher.applyingTextureSmoothing(
            to: output,
            strength: Double(adjustment.textureSmoothing) / 100,
            mask: mask,
            extent: extent
          )
        }
      }
    }
    if schemaVersion >= 12, let portraitContext {
      var usedTargetIndices = Set<Int>()
      for adjustment in directionalLightingAdjustments {
        guard let targetIndex = matchedFaceTargetIndex(
          for: adjustment,
          targets: portraitContext.faceTargets,
          extent: extent,
          excluding: usedTargetIndices
        ) else { continue }
        usedTargetIndices.insert(targetIndex)
        output = applyingDirectionalLighting(
          to: output,
          adjustment: adjustment,
          target: portraitContext.faceTargets[targetIndex],
          extent: extent
        )
      }
    }
    if schemaVersion >= 9 && semanticEditing != .neutral {
      let context = portraitContext ?? IOSPortraitRetoucher.prepare(
        source: opaqueInput,
        extent: extent
      )
      output = IOSSemanticEditor.applying(
        to: output,
        parameters: semanticEditing,
        subjectMask: context.combinedPersonMask,
        extent: extent
      )
    }
    let geometricallyAdjusted = applyingGeometry(to: output, sourceExtent: extent)
    let geometryExtent = geometricallyAdjusted.extent.integral
    let geometryBackground = CIImage(
      color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)
    ).cropped(to: geometryExtent)
    return geometricallyAdjusted
      .composited(over: geometryBackground)
      .cropped(to: geometryExtent)
  }

  private static func contrastCubeData(dimension: Int, contrast: Double) -> Data {
    var cube = [Float]()
    cube.reserveCapacity(dimension * dimension * dimension * 4)
    let denominator = Double(dimension - 1)
    func adjusted(_ value: Double) -> Float {
      let endpointWeight = 4 * value * (1 - value)
      let shaped = value
        + contrast * 3.2 * value * (1 - value) * (value - 0.5) * endpointWeight
      return Float(min(max(shaped, 0), 1))
    }
    for blueIndex in 0..<dimension {
      let blue = Double(blueIndex) / denominator
      for greenIndex in 0..<dimension {
        let green = Double(greenIndex) / denominator
        for redIndex in 0..<dimension {
          let red = Double(redIndex) / denominator
          cube.append(adjusted(red))
          cube.append(adjusted(green))
          cube.append(adjusted(blue))
          cube.append(1)
        }
      }
    }
    return cube.withUnsafeBytes { Data($0) }
  }

  private static func highlightCubeData(dimension: Int, highlights: Double) -> Data {
    var cube = [Float]()
    cube.reserveCapacity(dimension * dimension * dimension * 4)
    let denominator = Double(dimension - 1)
    func clamped(_ value: Double) -> Float {
      Float(min(max(value, 0), 1))
    }
    for blueIndex in 0..<dimension {
      let blue = Double(blueIndex) / denominator
      for greenIndex in 0..<dimension {
        let green = Double(greenIndex) / denominator
        for redIndex in 0..<dimension {
          let red = Double(redIndex) / denominator
          let luma = red * 0.2126 + green * 0.7152 + blue * 0.0722
          let delta = highlights * pow(luma, 3) * (1 - luma)
          cube.append(clamped(red + delta))
          cube.append(clamped(green + delta))
          cube.append(clamped(blue + delta))
          cube.append(1)
        }
      }
    }
    return cube.withUnsafeBytes { Data($0) }
  }

  private static func shadowCubeData(dimension: Int, shadows: Double) -> Data {
    var cube = [Float]()
    cube.reserveCapacity(dimension * dimension * dimension * 4)
    let denominator = Double(dimension - 1)
    func clamped(_ value: Double) -> Float {
      Float(min(max(value, 0), 1))
    }
    for blueIndex in 0..<dimension {
      let blue = Double(blueIndex) / denominator
      for greenIndex in 0..<dimension {
        let green = Double(greenIndex) / denominator
        for redIndex in 0..<dimension {
          let red = Double(redIndex) / denominator
          let luma = red * 0.2126 + green * 0.7152 + blue * 0.0722
          let delta = shadows * pow(1 - luma, 3) * luma
          cube.append(clamped(red + delta))
          cube.append(clamped(green + delta))
          cube.append(clamped(blue + delta))
          cube.append(1)
        }
      }
    }
    return cube.withUnsafeBytes { Data($0) }
  }

  private func applyingPhotoFilter(to input: CIImage, extent: CGRect) -> CIImage {
    let amount = Double(filterStrength) / 100
    let settings: (saturation: Double, contrast: Double, brightness: Double, temperature: Double)
    switch photoFilter {
    case "clean": settings = (1.04, 1.03, 0.025, 100)
    case "portrait": settings = (0.96, 1.02, 0.035, 180)
    case "cinematic": settings = (0.86, 1.16, -0.025, -220)
    case "film": settings = (0.82, 1.08, 0.015, 120)
    case "warmSun": settings = (1.05, 1.05, 0.025, 420)
    case "coolAir": settings = (0.92, 1.04, 0.035, -420)
    case "vivid": settings = (1.28, 1.10, 0.01, 0)
    case "faded": settings = (0.78, 0.84, 0.055, 80)
    case "noir": settings = (0, 1.20, 0, 0)
    case "food": settings = (1.18, 1.08, 0.025, 260)
    case "landscape": settings = (1.16, 1.12, -0.005, -80)
    case "night": settings = (0.88, 1.10, 0.035, -260)
    default: return input
    }
    var filtered = input.applyingFilter("CIColorControls", parameters: [
      kCIInputSaturationKey: 1 + (settings.saturation - 1) * amount,
    ])
    let contrast = (settings.contrast - 1) * amount
    let brightness = settings.brightness * amount
    if (contrast != 0 || brightness != 0),
       let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    {
      let dimension = 32
      filtered = filtered.applyingFilter(
        "CIColorCubeWithColorSpace",
        parameters: [
          "inputCubeDimension": dimension,
          "inputCubeData": Self.filterToneCubeData(
            dimension: dimension,
            contrast: contrast,
            brightness: brightness
          ),
          "inputColorSpace": colorSpace,
        ]
      )
    }
    if settings.temperature != 0 {
      filtered = filtered.applyingFilter("CITemperatureAndTint", parameters: [
        "inputNeutral": CIVector(x: 6500, y: 0),
        "inputTargetNeutral": CIVector(x: 6500 + settings.temperature * amount, y: 0),
      ])
    }
    return filtered.cropped(to: extent)
  }

  private static func filterToneCubeData(
    dimension: Int,
    contrast: Double,
    brightness: Double
  ) -> Data {
    var cube = [Float]()
    cube.reserveCapacity(dimension * dimension * dimension * 4)
    let denominator = Double(dimension - 1)
    func adjusted(_ value: Double) -> Float {
      let lifted = value + brightness * 4 * value * (1 - value)
      let shaped = lifted
        + contrast * 2.5 * lifted * (1 - lifted) * (lifted - 0.5)
      return Float(min(max(shaped, 0), 1))
    }
    for blueIndex in 0..<dimension {
      let blue = Double(blueIndex) / denominator
      for greenIndex in 0..<dimension {
        let green = Double(greenIndex) / denominator
        for redIndex in 0..<dimension {
          let red = Double(redIndex) / denominator
          cube.append(adjusted(red))
          cube.append(adjusted(green))
          cube.append(adjusted(blue))
          cube.append(1)
        }
      }
    }
    return cube.withUnsafeBytes { Data($0) }
  }

  private static func hslCubeData(
    dimension: Int,
    adjustments: [String: [String: Double]]
  ) -> Data {
    let centers: [String: Double] = [
      "red": 0, "orange": 30, "yellow": 60, "green": 120,
      "cyan": 180, "blue": 240, "purple": 275, "magenta": 315,
    ]
    var cube = [Float]()
    cube.reserveCapacity(dimension * dimension * dimension * 4)
    let denominator = Double(dimension - 1)
    for blueIndex in 0..<dimension {
      for greenIndex in 0..<dimension {
        for redIndex in 0..<dimension {
          var hsv = rgbToHsv(
            Double(redIndex) / denominator,
            Double(greenIndex) / denominator,
            Double(blueIndex) / denominator
          )
          var hueDelta = 0.0
          var saturationDelta = 0.0
          var lightnessDelta = 0.0
          for (channel, values) in adjustments {
            guard let center = centers[channel] else { continue }
            let distance = abs(((hsv.h - center + 540).truncatingRemainder(dividingBy: 360)) - 180)
            let weight = max(0, 1 - distance / 45)
            hueDelta += (values["hue"] ?? 0) * 0.45 * weight
            saturationDelta += (values["saturation"] ?? 0) / 100 * weight
            lightnessDelta += (values["lightness"] ?? 0) / 100 * weight
          }
          hsv.h = (hsv.h + hueDelta + 360).truncatingRemainder(dividingBy: 360)
          hsv.s = min(max(hsv.s * (1 + saturationDelta), 0), 1)
          hsv.v = min(max(hsv.v + lightnessDelta * 0.35, 0), 1)
          let rgb = hsvToRgb(hsv.h, hsv.s, hsv.v)
          cube.append(Float(rgb.r)); cube.append(Float(rgb.g)); cube.append(Float(rgb.b)); cube.append(1)
        }
      }
    }
    return cube.withUnsafeBytes { Data($0) }
  }

  private static func rgbToHsv(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
    let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
    var hue = 0.0
    if delta != 0 {
      if maximum == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
      else if maximum == g { hue = 60 * ((b - r) / delta + 2) }
      else { hue = 60 * ((r - g) / delta + 4) }
    }
    if hue < 0 { hue += 360 }
    return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
  }

  private static func hsvToRgb(_ h: Double, _ s: Double, _ v: Double) -> (r: Double, g: Double, b: Double) {
    let chroma = v * s, x = chroma * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - chroma
    let rgb: (Double, Double, Double)
    switch h {
    case 0..<60: rgb = (chroma, x, 0)
    case 60..<120: rgb = (x, chroma, 0)
    case 120..<180: rgb = (0, chroma, x)
    case 180..<240: rgb = (0, x, chroma)
    case 240..<300: rgb = (x, 0, chroma)
    default: rgb = (chroma, 0, x)
    }
    return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
  }

  private func applyingGeometry(to input: CIImage, sourceExtent: CGRect) -> CIImage {
    func aligned(_ value: CGFloat) -> CGFloat {
      floor(value + 0.5)
    }
    var geometryInput = input
    if flipHorizontal || flipVertical {
      let transform = CGAffineTransform(
        a: flipHorizontal ? -1 : 1, b: 0, c: 0,
        d: flipVertical ? -1 : 1,
        tx: flipHorizontal ? sourceExtent.maxX + sourceExtent.minX : 0,
        ty: flipVertical ? sourceExtent.maxY + sourceExtent.minY : 0
      )
      geometryInput = geometryInput.transformed(by: transform).cropped(to: sourceExtent)
    }
    if perspectiveHorizontal != 0 || perspectiveVertical != 0 {
      let dx = sourceExtent.width * CGFloat(perspectiveHorizontal / 100)
      let dy = sourceExtent.height * CGFloat(perspectiveVertical / 100)
      geometryInput = geometryInput.applyingFilter("CIPerspectiveTransform", parameters: [
        "inputTopLeft": CIVector(cgPoint: CGPoint(x: sourceExtent.minX + max(0, dx), y: sourceExtent.maxY - max(0, dy))),
        "inputTopRight": CIVector(cgPoint: CGPoint(x: sourceExtent.maxX + min(0, dx), y: sourceExtent.maxY + min(0, dy))),
        "inputBottomLeft": CIVector(cgPoint: CGPoint(x: sourceExtent.minX - min(0, dx), y: sourceExtent.minY - min(0, dy))),
        "inputBottomRight": CIVector(cgPoint: CGPoint(x: sourceExtent.maxX - max(0, dx), y: sourceExtent.minY + max(0, dy))),
      ]).cropped(to: sourceExtent)
    }
    let cropWidth = min(
      sourceExtent.width,
      max(1, aligned(crop.width * sourceExtent.width))
    )
    let cropHeight = min(
      sourceExtent.height,
      max(1, aligned(crop.height * sourceExtent.height))
    )
    let top = min(
      sourceExtent.height - cropHeight,
      max(0, aligned(crop.minY * sourceExtent.height))
    )
    let cropRect = CGRect(
      x: sourceExtent.minX + min(
        sourceExtent.width - cropWidth,
        max(0, aligned(crop.minX * sourceExtent.width))
      ),
      y: sourceExtent.minY + sourceExtent.height - top - cropHeight,
      width: cropWidth,
      height: cropHeight
    )
    var output: CIImage
    if straightenDegrees != 0 {
      let radians = CGFloat(-straightenDegrees * .pi / 180)
      let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
      let transform = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: radians)
        .translatedBy(x: -center.x, y: -center.y)
      output = geometryInput.transformed(by: transform).cropped(to: cropRect)
    } else {
      output = geometryInput.cropped(to: cropRect)
    }
    if quarterTurns != 0 {
      let expectedSize = quarterTurns.isMultiple(of: 2)
        ? output.extent.size
        : CGSize(width: output.extent.height, height: output.extent.width)
      let center = CGPoint(x: output.extent.midX, y: output.extent.midY)
      let transform = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: CGFloat(-quarterTurns) * .pi / 2)
        .translatedBy(x: -center.x, y: -center.y)
      output = output.transformed(by: transform)
      let transformedExtent = output.extent
      return output.transformed(
        by: CGAffineTransform(
          translationX: -transformedExtent.minX,
          y: -transformedExtent.minY
        )
      ).cropped(to: CGRect(origin: .zero, size: expectedSize))
    }
    let transformedExtent = output.extent.integral
    return output.transformed(
      by: CGAffineTransform(
        translationX: -transformedExtent.minX,
        y: -transformedExtent.minY
      )
    ).cropped(to: CGRect(origin: .zero, size: transformedExtent.size))
  }
}

private struct ColorTransform {
  let redScale: Double
  let greenScale: Double
  let blueScale: Double
}
