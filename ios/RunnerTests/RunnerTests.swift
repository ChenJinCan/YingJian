import CoreImage
import Flutter
import ImageIO
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  private let imageContext = CIContext(options: [.cacheIntermediates: false])
  private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  func testImagePipelineV2NeutralIsOpaqueAndPixelStable() throws {
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2()))
    let extent = CGRect(x: 0, y: 0, width: 8, height: 4)
    let source = CIImage(
      color: CIColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)
    ).cropped(to: extent)

    let output = pipeline.applying(to: source, extent: extent)
    let pixel = try firstPixel(output)
    let baseline = try firstPixel(
      source.composited(
        over: CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
      )
    )

    XCTAssertEqual(output.extent, extent)
    XCTAssertEqual(pixel, baseline)
    XCTAssertEqual(pixel[3], 255)
  }

  func testImagePipelineV2CropAndQuarterTurnProduceDeclaredDimensions() throws {
    let pipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(
        crop: [0.2, 0.0, 0.8, 0.5],
        quarterTurns: 1
      ))
    )
    let extent = CGRect(x: 0, y: 0, width: 10, height: 6)
    let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4))
      .cropped(to: extent)

    let output = pipeline.applying(to: source, extent: extent)

    XCTAssertEqual(output.extent.origin, .zero)
    XCTAssertEqual(output.extent.width, 3)
    XCTAssertEqual(output.extent.height, 6)
  }

  func testImagePipelineV2CropTranslationKeepsPixelAlignedDimensions() throws {
    let first = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(crop: [0.11, 0.1, 0.69, 0.51]))
    )
    let shifted = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(crop: [0.21, 0.2, 0.79, 0.61]))
    )
    let extent = CGRect(x: 0, y: 0, width: 10, height: 6)
    let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4))
      .cropped(to: extent)

    XCTAssertEqual(
      first.applying(to: source, extent: extent).extent.size,
      CGSize(width: 6, height: 2)
    )
    XCTAssertEqual(
      shifted.applying(to: source, extent: extent).extent.size,
      CGSize(width: 6, height: 2)
    )
  }

  func testImagePipelineV2ExposureAndWarmthHaveDeclaredTrend() throws {
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2()))
    let adjusted = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(exposureEV: 0.5, warmth: 0.6))
    )
    let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
    let source = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3))
      .cropped(to: extent)

    let neutralPixel = try firstPixel(neutral.applying(to: source, extent: extent))
    let adjustedPixel = try firstPixel(adjusted.applying(to: source, extent: extent))

    XCTAssertGreaterThan(adjustedPixel[0], neutralPixel[0])
    XCTAssertGreaterThan(adjustedPixel[1], neutralPixel[1])
    XCTAssertGreaterThan(adjustedPixel[0], adjustedPixel[2])
  }

  func testImagePipelineV2StraightenUsesWhiteOutsideTheSource() throws {
    let pipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(straightenDegrees: 45))
    )
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let source = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
      .cropped(to: extent)

    let corner = try firstPixel(pipeline.applying(to: source, extent: extent))

    XCTAssertEqual(corner, [255, 255, 255, 255])
  }

  func testImagePipelineRejectsUnknownOrUnsafeV2Contracts() {
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV2(schemaVersion: 3)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV2(portraitStrength: 0.1)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV2(crop: [0.8, 0, 0.2, 1])))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV2(straightenDegrees: 46)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV2(schemaVersion: 1.9)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV2(quarterTurns: 1.9)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV2(portraitRecipeVersion: 1.9)))
    var booleanSchema = pipelineV2()
    booleanSchema["schemaVersion"] = true
    XCTAssertNil(IOSImagePipeline(arguments: booleanSchema))
    var booleanGeometry = pipelineV2()
    var geometry = booleanGeometry["geometry"] as! [String: Any]
    geometry["quarterTurns"] = false
    booleanGeometry["geometry"] = geometry
    XCTAssertNil(IOSImagePipeline(arguments: booleanGeometry))
    var booleanPortrait = pipelineV2()
    var portrait = booleanPortrait["portrait"] as! [String: Any]
    portrait["recipeVersion"] = true
    booleanPortrait["portrait"] = portrait
    XCTAssertNil(IOSImagePipeline(arguments: booleanPortrait))
    var booleanAdjustment = pipelineV2()
    var adjustments = booleanAdjustment["adjustments"] as! [String: Any]
    adjustments["exposureEv"] = true
    booleanAdjustment["adjustments"] = adjustments
    XCTAssertNil(IOSImagePipeline(arguments: booleanAdjustment))
    var booleanCrop = pipelineV2()
    geometry = booleanCrop["geometry"] as! [String: Any]
    geometry["normalizedCrop"] = [false, 0.0, 1.0, 1.0]
    booleanCrop["geometry"] = geometry
    XCTAssertNil(IOSImagePipeline(arguments: booleanCrop))
    var booleanStraighten = pipelineV2()
    geometry = booleanStraighten["geometry"] as! [String: Any]
    geometry["straightenDegrees"] = false
    booleanStraighten["geometry"] = geometry
    XCTAssertNil(IOSImagePipeline(arguments: booleanStraighten))
    var booleanStrength = pipelineV2()
    portrait = booleanStrength["portrait"] as! [String: Any]
    portrait["strength"] = false
    booleanStrength["portrait"] = portrait
    XCTAssertNil(IOSImagePipeline(arguments: booleanStrength))
  }

  func testLocalAnalysisUsesBoundedCategoriesForDarkCoolInput() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
      UIColor(red: 0.04, green: 0.08, blue: 0.28, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-analysis-\(UUID().uuidString).jpg")
    try XCTUnwrap(image.jpegData(compressionQuality: 1)).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let result = try AppDelegate.analyzePhoto(path: url.path)

    XCTAssertEqual(result["analysisVersion"] as? String, "local-pixels-v1")
    XCTAssertEqual(result["exposure"] as? String, "underexposed")
    XCTAssertEqual(result["whiteBalance"] as? String, "coolCast")
    XCTAssertEqual(result["clarity"] as? String, "blurred")
    XCTAssertEqual(result["scene"] as? String, "unknown")
    XCTAssertEqual(result["portrait"] as? String, "unavailable")
  }

  func testExportMetadataPreservesCaptureTimeAndRemovesSensitiveFields() throws {
    let source: [String: Any] = [
      kCGImagePropertyOrientation as String: 6,
      kCGImagePropertyGPSDictionary as String: [
        kCGImagePropertyGPSLatitude as String: 31.2
      ],
      kCGImagePropertyExifDictionary as String: [
        kCGImagePropertyExifDateTimeOriginal as String: "2026:08:04 13:14:15",
        kCGImagePropertyExifDateTimeDigitized as String: "2026:08:04 13:14:16",
        kCGImagePropertyExifMakerNote as String: Data([1, 2, 3]),
      ],
      kCGImagePropertyTIFFDictionary as String: [
        kCGImagePropertyTIFFDateTime as String: "2026:08:04 13:14:15",
        kCGImagePropertyTIFFMake as String: "Private camera make",
      ],
    ]

    let sanitized = ImageExportMetadata.sanitize(source)
    let exif = sanitized[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiff = sanitized[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

    XCTAssertEqual(sanitized[kCGImagePropertyOrientation as String] as? Int, 1)
    XCTAssertNil(sanitized[kCGImagePropertyGPSDictionary as String])
    XCTAssertEqual(
      exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String,
      "2026:08:04 13:14:15"
    )
    XCTAssertNil(exif?[kCGImagePropertyExifMakerNote as String])
    XCTAssertEqual(
      tiff?[kCGImagePropertyTIFFDateTime as String] as? String,
      "2026:08:04 13:14:15"
    )
    XCTAssertNil(tiff?[kCGImagePropertyTIFFMake as String])
    let captureDate = ImageExportMetadata.captureDate(from: sanitized)
    let components = Calendar(identifier: .gregorian).dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: try XCTUnwrap(captureDate)
    )
    XCTAssertEqual(components.year, 2026)
    XCTAssertEqual(components.month, 8)
    XCTAssertEqual(components.day, 4)
    XCTAssertEqual(components.hour, 13)
    XCTAssertEqual(components.minute, 14)
    XCTAssertEqual(components.second, 15)
  }

  private func pipelineV2(
    schemaVersion: NSNumber = 2,
    exposureEV: Double = 0,
    warmth: Double = 0,
    crop: [Double] = [0, 0, 1, 1],
    quarterTurns: NSNumber = 0,
    straightenDegrees: Double = 0,
    portraitStrength: Double = 0,
    portraitRecipeVersion: NSNumber = 1
  ) -> [String: Any] {
    [
      "schemaVersion": schemaVersion,
      "workingColorSpace": "srgb",
      "adjustments": [
        "exposureEv": exposureEV,
        "highlights": 0.0,
        "shadows": 0.0,
        "contrast": 0.0,
        "warmth": warmth,
        "tint": 0.0,
        "saturation": 0.0,
        "clarity": 0.0,
      ],
      "geometry": [
        "normalizedCrop": crop,
        "quarterTurns": quarterTurns,
        "straightenDegrees": straightenDegrees,
      ],
      "portrait": [
        "recipeVersion": portraitRecipeVersion,
        "strength": portraitStrength,
      ],
    ]
  }

  private func firstPixel(_ image: CIImage) throws -> [Int] {
    let bounds = image.extent.integral
    var bytes = [UInt8](repeating: 0, count: Int(bounds.width * bounds.height) * 4)
    bytes.withUnsafeMutableBytes { buffer in
      imageContext.render(
        image,
        toBitmap: buffer.baseAddress!,
        rowBytes: Int(bounds.width) * 4,
        bounds: bounds,
        format: .RGBA8,
        colorSpace: sRGB
      )
    }
    return bytes.prefix(4).map(Int.init)
  }

}
