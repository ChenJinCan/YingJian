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
    preparedPortraitContext: IOSPortraitRetouchContext? = nil
  ) throws -> IOSPhotoRenderedFile {
    guard let input = CIImage(
      contentsOf: URL(fileURLWithPath: sourcePath),
      options: [.applyOrientationProperty: true]
    ) else {
      throw IOSPhotoFileRenderError.decodeFailed
    }
    let normalizedInput = input.transformed(
      by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY)
    )
    let metadata = ImageExportMetadata.sanitize(input.properties)
    let sourceExtent = normalizedInput.extent.integral
    let portraitContext = preparedPortraitContext
      ?? (pipeline.textureSmoothing > 0
        || pipeline.skinToneLighting > 0
        || pipeline.blemishReduction > 0
        || pipeline.portraitStrength > 0
        || pipeline.faceSlimStrengths.contains(where: { $0 > 0 })
        || pipeline.bodySlimStrength > 0
        ? IOSPortraitRetoucher.prepare(source: normalizedInput, extent: sourceExtent)
        : .unavailable)
    let output = pipeline
      .applying(
        to: normalizedInput,
        extent: sourceExtent,
        portraitContext: portraitContext
      )
      .settingProperties(metadata)
    let outputExtent = output.extent.integral
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw IOSPhotoFileRenderError.renderFailed
    }
    do {
      try context.writeJPEGRepresentation(
        of: output,
        to: destinationURL,
        colorSpace: colorSpace,
        options: [
          kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
        ]
      )
    } catch {
      try? FileManager.default.removeItem(at: destinationURL)
      throw IOSPhotoFileRenderError.renderFailed
    }
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
  let crop: CGRect
  let quarterTurns: Int
  let straightenDegrees: Double

  init?(arguments: Any?) {
    guard
      let pipeline = arguments as? [String: Any],
      let schemaVersion = Self.exactInteger(pipeline["schemaVersion"]),
      (1...6).contains(schemaVersion),
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

  func applying(
    to input: CIImage,
    extent: CGRect,
    portraitContext: IOSPortraitRetouchContext? = nil
  ) -> CIImage {
    let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
      .cropped(to: extent)
    let opaqueInput = input.composited(over: white)
    var reshapedInput = opaqueInput
    if bodySlimStrength > 0 {
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
    if faceSlimStrengths.contains(where: { $0 > 0 }) {
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
      output = output.applyingFilter(
        "CIColorControls",
        parameters: [
          kCIInputContrastKey: 1 + strength * 0.18,
          kCIInputSaturationKey: 1 + strength * 0.05,
        ]
      ).cropped(to: extent)
    }
    if clarity != 0 {
      output = output.applyingFilter(
        "CISharpenLuminance",
        parameters: [kCIInputSharpnessKey: clarity * 0.8]
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
      let shaped = value + contrast * 2.5 * value * (1 - value) * (value - 0.5)
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

  private func applyingGeometry(to input: CIImage, sourceExtent: CGRect) -> CIImage {
    func aligned(_ value: CGFloat) -> CGFloat {
      floor(value + 0.5)
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
      output = input.transformed(by: transform).cropped(to: cropRect)
    } else {
      output = input.cropped(to: cropRect)
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
