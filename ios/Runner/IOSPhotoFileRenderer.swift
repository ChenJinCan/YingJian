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
    destinationURL: URL
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
    let output = pipeline
      .applying(to: normalizedInput, extent: normalizedInput.extent.integral)
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
  let exposureEV: Double
  let highlights: Double
  let shadows: Double
  let contrast: Double
  let warmth: Double
  let tint: Double
  let saturation: Double
  let clarity: Double
  let portraitStrength: Double
  let crop: CGRect
  let quarterTurns: Int
  let straightenDegrees: Double

  init?(arguments: Any?) {
    guard
      let pipeline = arguments as? [String: Any],
      let schemaVersion = Self.exactInteger(pipeline["schemaVersion"]),
      schemaVersion == 1 || schemaVersion == 2,
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
    self.contrast = contrast
    self.warmth = warmth
    if schemaVersion == 1 {
      highlights = 0
      shadows = 0
      tint = 0
      saturation = 0
      clarity = 0
      portraitStrength = 0
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
      (-45.0...45.0).contains(straightenDegrees),
      let portrait = pipeline["portrait"] as? [String: Any],
      Self.exactInteger(portrait["recipeVersion"]) == 1,
      let portraitStrength = Self.finiteNumber(portrait["strength"]),
      portraitStrength == 0
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
    self.portraitStrength = portraitStrength
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

  func applying(to input: CIImage, extent: CGRect) -> CIImage {
    let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
      .cropped(to: extent)
    let opaqueInput = input.composited(over: white)
    let transform = colorTransform
    var output = opaqueInput.applyingFilter(
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

    if highlights != 0 || shadows != 0 {
      output = output.applyingFilter(
        "CIHighlightShadowAdjust",
        parameters: [
          "inputHighlightAmount": 1 + highlights * 0.65,
          "inputShadowAmount": shadows * 0.65,
        ]
      ).cropped(to: extent)
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
    if clarity != 0 {
      output = output.applyingFilter(
        "CISharpenLuminance",
        parameters: [kCIInputSharpnessKey: clarity * 0.8]
      ).cropped(to: extent)
    }
    if portraitStrength > 0 {
      output = IOSPortraitRetoucher.applying(
        to: output,
        strength: portraitStrength,
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
