import CoreImage
import CryptoKit
import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  private let imageContext = CIContext(options: [.cacheIntermediates: false])
  private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  func testPickedPhotoFileStorePreservesOriginalBytes() throws {
    let source = temporaryURL(extension: "jpg")
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-picker-test-\(UUID().uuidString)", isDirectory: true)
    let original = Data([0xff, 0xd8, 0xff, 0xe1, 0x00, 0x08, 0x59, 0x4a])
    try original.write(to: source, options: .atomic)
    defer {
      removeTemporaryFiles(source)
      try? FileManager.default.removeItem(at: directory)
    }

    let copy = try IOSPickedPhotoFileStore.copy(
      sourceURL: source,
      suggestedName: "original.jpg",
      destinationDirectory: directory
    )

    XCTAssertEqual(try Data(contentsOf: copy), original)
    XCTAssertEqual(try Data(contentsOf: source), original)
    XCTAssertEqual(copy.pathExtension.lowercased(), "jpg")
    XCTAssertTrue(copy.path.hasPrefix(directory.path + "/"))
  }

  func testPhotoPickerDiscardsOnlyItsTemporaryRequestFiles() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-photo-picker", isDirectory: true)
    let directory = root
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = temporaryURL(extension: "png")
    try Data([0x89, 0x50, 0x4e, 0x47]).write(to: source, options: .atomic)
    defer { removeTemporaryFiles(source) }
    let copy = try IOSPickedPhotoFileStore.copy(
      sourceURL: source,
      suggestedName: "original.png",
      destinationDirectory: directory
    )

    XCTAssertThrowsError(try IOSPhotoPicker().discard(paths: [source.path]))
    try IOSPhotoPicker().discard(paths: [copy.path])

    XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }

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

  func testImagePipelineV2WarmthHasOrderedRedBlueResponse() throws {
    let cool = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2(warmth: -0.4)))
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2()))
    let warm = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2(warmth: 0.4)))
    let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
    let source = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3))
      .cropped(to: extent)

    let coolPixel = try firstPixel(cool.applying(to: source, extent: extent))
    let neutralPixel = try firstPixel(neutral.applying(to: source, extent: extent))
    let warmPixel = try firstPixel(warm.applying(to: source, extent: extent))
    let coolIndex = Int(coolPixel[0]) - Int(coolPixel[2])
    let neutralIndex = Int(neutralPixel[0]) - Int(neutralPixel[2])
    let warmIndex = Int(warmPixel[0]) - Int(warmPixel[2])

    XCTAssertLessThan(coolIndex, neutralIndex)
    XCTAssertLessThan(neutralIndex, warmIndex)
  }

  func testImagePipelineV2HighlightsMoveBrightTonesInBothDirections() throws {
    let negative = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(highlights: -0.4))
    )
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2()))
    let positive = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(highlights: 0.4))
    )
    let pixels: [UInt8] = [38, 38, 38, 255, 204, 204, 204, 255]
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: 2 * 4,
      size: CGSize(width: 2, height: 1),
      format: .RGBA8,
      colorSpace: sRGB
    )

    let negativePixels = try rgbaBytes(
      negative.applying(to: source, extent: source.extent)
    )
    let neutralPixels = try rgbaBytes(
      neutral.applying(to: source, extent: source.extent)
    )
    let positivePixels = try rgbaBytes(
      positive.applying(to: source, extent: source.extent)
    )
    let brightOffset = 4

    XCTAssertLessThan(negativePixels[brightOffset], neutralPixels[brightOffset])
    XCTAssertGreaterThan(positivePixels[brightOffset], neutralPixels[brightOffset])
    XCTAssertLessThan(
      Int(positivePixels[0]) - Int(neutralPixels[0]),
      Int(positivePixels[brightOffset]) - Int(neutralPixels[brightOffset])
    )
  }

  func testImagePipelineV2ShadowsMoveDarkTonesWithoutMovingBrightTones() throws {
    let negative = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(shadows: -0.4))
    )
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2()))
    let positive = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(shadows: 0.4))
    )
    let pixels: [UInt8] = [51, 51, 51, 255, 204, 204, 204, 255]
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: 2 * 4,
      size: CGSize(width: 2, height: 1),
      format: .RGBA8,
      colorSpace: sRGB
    )

    let negativePixels = try rgbaBytes(
      negative.applying(to: source, extent: source.extent)
    )
    let neutralPixels = try rgbaBytes(
      neutral.applying(to: source, extent: source.extent)
    )
    let positivePixels = try rgbaBytes(
      positive.applying(to: source, extent: source.extent)
    )
    let brightOffset = 4

    XCTAssertLessThan(negativePixels[0], neutralPixels[0])
    XCTAssertGreaterThan(positivePixels[0], neutralPixels[0])
    XCTAssertLessThanOrEqual(
      abs(Int(positivePixels[brightOffset]) - Int(neutralPixels[brightOffset])),
      2
    )
  }

  func testImagePipelineV2SafeContrastHasOrderedToneResponseWithoutCrushing() throws {
    let positivePipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(contrast: 0.35))
    )
    let negativePipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(contrast: -0.35))
    )
    let pixels = (0...255).flatMap { value -> [UInt8] in
      let channel = UInt8(value)
      return [channel, channel, channel, 255]
    }
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: 256 * 4,
      size: CGSize(width: 256, height: 1),
      format: .RGBA8,
      colorSpace: sRGB
    )

    let positive = try rgbaBytes(
      positivePipeline.applying(to: source, extent: source.extent)
    )
    let negative = try rgbaBytes(
      negativePipeline.applying(to: source, extent: source.extent)
    )
    let crushedBlackPixels = stride(from: 0, to: positive.count, by: 4).count { offset in
      positive[offset] <= 1 && positive[offset + 1] <= 1 && positive[offset + 2] <= 1
    }

    XCTAssertLessThan(positive[64 * 4], 64)
    XCTAssertGreaterThan(positive[192 * 4], 192)
    XCTAssertGreaterThan(negative[64 * 4], 64)
    XCTAssertLessThan(negative[192 * 4], 192)
    XCTAssertEqual(positive[128 * 4], 128, accuracy: 2)
    XCTAssertEqual(negative[128 * 4], 128, accuracy: 2)
    XCTAssertLessThanOrEqual(
      crushedBlackPixels,
      26,
      "A safe positive contrast step must not crush more than 10% of the sRGB tone scale"
    )
  }

  func testPhotoPreviewTextureMatchesFinalJpegRecipeSemantics() throws {
    let sourceURL = temporaryURL(extension: "jpg")
    let outputURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    try writeAsymmetricJpeg(to: sourceURL, orientation: 1)
    let pipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(
        exposureEV: 0.25,
        highlights: 0.3,
        shadows: -0.2,
        contrast: 0.2,
        warmth: 0.2,
        crop: [0.1, 0.0, 0.9, 1.0],
        quarterTurns: 1
      ))
    )
    let session = try IOSPhotoPreviewSession(
      sourcePath: sourceURL.path,
      maxEdge: 2_048,
      pipeline: pipeline
    )
    defer { session.close() }
    let previewBuffer = try XCTUnwrap(session.copyPixelBuffer()).takeRetainedValue()
    let previewBytes = try rgbaBytes(CIImage(cvPixelBuffer: previewBuffer))

    _ = try IOSPhotoFileRenderer(context: imageContext).render(
      sourcePath: sourceURL.path,
      pipeline: pipeline,
      destinationURL: outputURL
    )
    let exported = try XCTUnwrap(
      CIImage(contentsOf: outputURL, options: [.applyOrientationProperty: true])
    )
    let exportedBytes = try rgbaBytes(normalized(exported))

    XCTAssertEqual(session.width, Int(exported.extent.width))
    XCTAssertEqual(session.height, Int(exported.extent.height))
    XCTAssertLessThanOrEqual(
      meanAbsoluteDifference(previewBytes, exportedBytes),
      4.0,
      "Texture preview and final JPEG must preserve the same recipe semantics"
    )
  }

  func testPhotoPreviewSessionReleasesItsBufferAndRejectsRenderingAfterClose() throws {
    let sourceURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL) }
    try writeAsymmetricJpeg(to: sourceURL, orientation: 1)
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2()))
    let adjusted = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(contrast: 0.35, warmth: 0.4))
    )
    let session = try IOSPhotoPreviewSession(
      sourcePath: sourceURL.path,
      maxEdge: 2_048,
      pipeline: pipeline
    )
    let neutralBuffer = try XCTUnwrap(session.copyPixelBuffer()).takeRetainedValue()
    let neutralBytes = try rgbaBytes(CIImage(cvPixelBuffer: neutralBuffer))

    try session.render(pipeline: adjusted)
    let adjustedBuffer = try XCTUnwrap(session.copyPixelBuffer()).takeRetainedValue()
    let adjustedBytes = try rgbaBytes(CIImage(cvPixelBuffer: adjustedBuffer))

    XCTAssertGreaterThan(meanAbsoluteDifference(neutralBytes, adjustedBytes), 0.25)

    session.close()

    XCTAssertNil(session.copyPixelBuffer())
    XCTAssertThrowsError(try session.render(pipeline: pipeline))
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

  func testImagePipelineAcceptsBoundedPortraitStrengthAndRejectsUnsafeV2Contracts() {
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV2(schemaVersion: 3)))
    XCTAssertEqual(
      IOSImagePipeline(arguments: pipelineV2(portraitStrength: 0.1))?.portraitStrength,
      0.1
    )
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV2(portraitStrength: -0.01)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV2(portraitStrength: 1.01)))
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
    XCTAssertTrue(
      ["noFace", "capabilityUnavailable"].contains(
        try XCTUnwrap(result["portraitReason"] as? String)
      )
    )
  }

  func testSelfBuiltPortraitCandidateIsReportedApplicableOnlyForSafeSingleFaces() {
    XCTAssertTrue(IOSPortraitCapabilityPolicy.productionEligible)
    XCTAssertEqual(
      IOSPortraitCapabilityPolicy.classify(
        IOSPortraitSafetyDecision(applicable: false, reason: .noFace)
      ),
      IOSPortraitCapabilityStatus(applicability: "unavailable", reason: "noFace")
    )
    XCTAssertEqual(
      IOSPortraitCapabilityPolicy.classify(
        IOSPortraitSafetyDecision(applicable: false, reason: .multipleFaces)
      ),
      IOSPortraitCapabilityStatus(applicability: "unsafe", reason: "multipleFaces")
    )
    XCTAssertEqual(
      IOSPortraitCapabilityPolicy.classify(
        IOSPortraitSafetyDecision(applicable: true, reason: .none)
      ),
      IOSPortraitCapabilityStatus(applicability: "applicable", reason: "none")
    )
  }

  func testProductionPipelineAppliesInjectedLocalPortraitContextAndKeepsZeroExact() throws {
    let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
    let source = CIImage(color: CIColor(red: 0.36, green: 0.24, blue: 0.18))
      .cropped(to: extent)
    let fullFaceMask = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
      .cropped(to: extent)
    let context = IOSPortraitRetouchContext(effectiveMask: fullFaceMask)
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2()))
    let portrait = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV2(portraitStrength: 0.35))
    )

    let sourceBytes = try rgbaBytes(source)
    let zeroBytes = try rgbaBytes(
      neutral.applying(to: source, extent: extent, portraitContext: context)
    )
    let portraitBytes = try rgbaBytes(
      portrait.applying(to: source, extent: extent, portraitContext: context)
    )

    XCTAssertEqual(zeroBytes, sourceBytes, "strength zero must remain exact")
    XCTAssertGreaterThan(
      meanAbsoluteDifference(sourceBytes, portraitBytes),
      0.25,
      "a safe local portrait context must visibly affect the production pipeline"
    )
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

  func testFileRendererNormalizesRealJpegOrientationAndMetadataWithoutChangingSource() throws {
    let sourceURL = temporaryURL(extension: "jpg")
    let outputURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    try writeJpeg(
      to: sourceURL,
      width: 6,
      height: 4,
      colorSpace: sRGB,
      properties: [
        kCGImagePropertyOrientation as String: 6,
        kCGImagePropertyGPSDictionary as String: [
          kCGImagePropertyGPSLatitude as String: 31.2
        ],
        kCGImagePropertyExifDictionary as String: [
          kCGImagePropertyExifDateTimeOriginal as String: "2026:08:04 13:14:15",
          kCGImagePropertyExifMakerNote as String: Data([1, 2, 3]),
        ],
        kCGImagePropertyTIFFDictionary as String: [
          kCGImagePropertyTIFFDateTime as String: "2026:08:04 13:14:15",
          kCGImagePropertyTIFFMake as String: "Private camera make",
        ],
      ]
    )
    let sourceHash = try sha256(sourceURL)

    let artifact = try render(sourceURL: sourceURL, outputURL: outputURL)
    let properties = try imageProperties(outputURL)
    let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

    XCTAssertEqual(artifact.width, 4)
    XCTAssertEqual(artifact.height, 6)
    XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 1)
    XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
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
    XCTAssertEqual(try sha256(sourceURL), sourceHash)
  }

  func testFileRendererNormalizesAllExifOrientationsWithAsymmetricPixels() throws {
    var temporaryFiles: [URL] = []
    defer { removeTemporaryFiles(temporaryFiles) }
    let baselineURL = temporaryURL(extension: "jpg")
    temporaryFiles.append(baselineURL)
    try writeAsymmetricJpeg(to: baselineURL, orientation: 1)
    let baseline = try XCTUnwrap(
      CIImage(
        contentsOf: baselineURL,
        options: [.applyOrientationProperty: false]
      )
    )

    for orientation in 1...8 {
      let sourceURL = temporaryURL(extension: "jpg")
      let outputURL = temporaryURL(extension: "jpg")
      temporaryFiles.append(contentsOf: [sourceURL, outputURL])
      try writeAsymmetricJpeg(to: sourceURL, orientation: orientation)
      let sourceHash = try sha256(sourceURL)

      let artifact = try render(sourceURL: sourceURL, outputURL: outputURL)
      let actual = try XCTUnwrap(
        CIImage(
          contentsOf: outputURL,
          options: [.applyOrientationProperty: true]
        )
      )
      let expected = normalized(
        baseline.oriented(forExifOrientation: Int32(orientation))
      )
      let actualBytes = try rgbaBytes(normalized(actual))
      let expectedBytes = try rgbaBytes(expected)
      let difference = meanAbsoluteDifference(actualBytes, expectedBytes)
      let properties = try imageProperties(outputURL)

      XCTAssertEqual(artifact.width, Int(expected.extent.width), "orientation \(orientation)")
      XCTAssertEqual(artifact.height, Int(expected.extent.height), "orientation \(orientation)")
      XCTAssertEqual(actualBytes.count, expectedBytes.count, "orientation \(orientation)")
      XCTAssertLessThan(difference, 8, "orientation \(orientation) changed asymmetric pixels")
      XCTAssertEqual(
        properties[kCGImagePropertyOrientation as String] as? Int,
        1,
        "orientation \(orientation)"
      )
      XCTAssertEqual(try sha256(sourceURL), sourceHash, "orientation \(orientation)")
    }
  }

  func testFileRendererCompositesTransparentPngOntoWhite() throws {
    let sourceURL = temporaryURL(extension: "png")
    let outputURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    let transparent = CIImage(
      color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
    ).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    try imageContext.writePNGRepresentation(
      of: transparent,
      to: sourceURL,
      format: .RGBA8,
      colorSpace: sRGB,
      options: [:]
    )

    _ = try render(sourceURL: sourceURL, outputURL: outputURL)
    let output = try XCTUnwrap(CIImage(contentsOf: outputURL))
    let pixel = try firstPixel(output)

    XCTAssertGreaterThanOrEqual(pixel[0], 250)
    XCTAssertGreaterThanOrEqual(pixel[1], 250)
    XCTAssertGreaterThanOrEqual(pixel[2], 250)
    XCTAssertEqual(pixel[3], 255)
  }

  func testFileRendererConvertsDisplayP3JpegToSrgb() throws {
    let sourceURL = temporaryURL(extension: "jpg")
    let outputURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    let displayP3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    try writeJpeg(
      to: sourceURL,
      width: 8,
      height: 8,
      colorSpace: displayP3
    )

    _ = try render(sourceURL: sourceURL, outputURL: outputURL)
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
    let output = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

    XCTAssertEqual(output.colorSpace?.name, CGColorSpace.sRGB)
  }

  func testFileRendererAcceptsRealHeicInputAndProducesJpeg() throws {
    let sourceURL = temporaryURL(extension: "heic")
    let outputURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
      .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 6))
    try imageContext.writeHEIFRepresentation(
      of: image,
      to: sourceURL,
      format: .RGBA8,
      colorSpace: sRGB,
      options: [:]
    )

    let artifact = try render(sourceURL: sourceURL, outputURL: outputURL)
    let outputSource = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
    let outputType = try XCTUnwrap(CGImageSourceGetType(outputSource))

    XCTAssertEqual(artifact.width, 8)
    XCTAssertEqual(artifact.height, 6)
    XCTAssertEqual(outputType as String, UTType.jpeg.identifier)
  }

  func testPortraitSpikeProducesReviewReadyFullResolutionArtifactsWithoutFace() throws {
    let sourceURL = temporaryURL(extension: "png")
    defer { removeTemporaryFiles(sourceURL) }
    let source = CIImage(color: CIColor(red: 0.1, green: 0.3, blue: 0.7))
      .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 64))
    try imageContext.writePNGRepresentation(
      of: source,
      to: sourceURL,
      format: .RGBA8,
      colorSpace: sRGB,
      options: [:]
    )
    let sourceHash = try sha256(sourceURL)

    let result = try PortraitMaskSpike.analyze(sourcePath: sourceURL.path)
    XCTAssertEqual(result["faceCount"] as? Int, 0)
    XCTAssertEqual(result["candidateApplicable"] as? Bool, false)
    XCTAssertEqual(result["degradationReason"] as? String, "no_face")
    XCTAssertEqual(result["sourceWidth"] as? Int, 96)
    XCTAssertEqual(result["sourceHeight"] as? Int, 64)
    XCTAssertEqual(result["productionEligible"] as? Bool, false)

    let baselinePath = try XCTUnwrap(result["baselineOriginalPath"] as? String)
    let offPath = try XCTUnwrap(result["offExportPath"] as? String)
    let defaultPath = try XCTUnwrap(result["defaultExportPath"] as? String)
    let highSafePath = try XCTUnwrap(result["highSafeExportPath"] as? String)
    let previewPath = try XCTUnwrap(result["defaultPreviewPath"] as? String)
    let manifestPath = try XCTUnwrap(result["captureManifestPath"] as? String)
    let captureRelativePath = try XCTUnwrap(result["captureRelativePath"] as? String)
    defer {
      removeTemporaryFiles(
        URL(fileURLWithPath: baselinePath).deletingLastPathComponent()
      )
    }

    for path in [baselinePath, offPath, defaultPath, highSafePath] {
      let url = URL(fileURLWithPath: path)
      let properties = try imageProperties(url)
      XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 96)
      XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 64)
      XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 1)
      let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
      XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      XCTAssertEqual(image.colorSpace?.name, CGColorSpace.sRGB)
    }
    XCTAssertEqual(try sha256(URL(fileURLWithPath: baselinePath)), try sha256(URL(fileURLWithPath: offPath)))
    XCTAssertEqual(try sha256(URL(fileURLWithPath: baselinePath)), try sha256(URL(fileURLWithPath: defaultPath)))
    XCTAssertEqual(try sha256(URL(fileURLWithPath: baselinePath)), try sha256(URL(fileURLWithPath: highSafePath)))
    let previewURL = URL(fileURLWithPath: previewPath)
    let previewProperties = try imageProperties(previewURL)
    XCTAssertEqual(previewProperties[kCGImagePropertyPixelWidth as String] as? Int, 96)
    XCTAssertEqual(previewProperties[kCGImagePropertyPixelHeight as String] as? Int, 64)
    XCTAssertEqual((previewProperties[kCGImagePropertyOrientation as String] as? Int) ?? 1, 1)
    let previewSource = try XCTUnwrap(CGImageSourceCreateWithURL(previewURL as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetType(previewSource) as String?, UTType.png.identifier)
    let previewImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(previewSource, 0, nil))
    XCTAssertEqual(previewImage.colorSpace?.name, CGColorSpace.sRGB)

    let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    let manifest = try XCTUnwrap(
      JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
    )
    XCTAssertEqual(manifest["schema"] as? Int, 2)
    XCTAssertEqual(manifest["candidateApplicable"] as? Bool, false)
    XCTAssertEqual(manifest["degradationReason"] as? String, "no_face")
    XCTAssertEqual(manifest["rawSourceSha256"] as? String, sourceHash)
    XCTAssertEqual(manifest["productionEligible"] as? Bool, false)
    XCTAssertTrue(captureRelativePath.hasPrefix("tmp/portrait-mask-spike/"))
    XCTAssertFalse((manifest["device"] as? String ?? "").isEmpty)
    XCTAssertFalse((manifest["appVersion"] as? String ?? "").isEmpty)
    XCTAssertFalse((manifest["appBuild"] as? String ?? "").isEmpty)
    let outputs = try XCTUnwrap(manifest["outputs"] as? [String: [String: Any]])
    let expectedOutputs = [
      "baselineOriginal": baselinePath,
      "offExport": offPath,
      "defaultExport": defaultPath,
      "highSafeExport": highSafePath,
      "defaultPreview": previewPath,
    ]
    for (name, path) in expectedOutputs {
      let entry = try XCTUnwrap(outputs[name])
      let url = URL(fileURLWithPath: path)
      XCTAssertEqual(entry["file"] as? String, url.lastPathComponent)
      XCTAssertEqual(entry["sha256"] as? String, try sha256(url))
    }
    XCTAssertEqual(try sha256(sourceURL), sourceHash)

    XCTAssertThrowsError(
      try PortraitMaskSpike.removeCaptureRoot { _ in
        throw NSError(domain: "fixture.cleanup", code: 1)
      }
    ) { error in
      XCTAssertEqual((error as? PortraitMaskSpikeError)?.code, "cleanupFailed")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: manifestPath))

    let replacement = try PortraitMaskSpike.analyze(sourcePath: sourceURL.path)
    let replacementManifest = try XCTUnwrap(replacement["captureManifestPath"] as? String)
    defer {
      removeTemporaryFiles(
        URL(fileURLWithPath: replacementManifest).deletingLastPathComponent()
      )
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: manifestPath))
    XCTAssertTrue(FileManager.default.fileExists(atPath: replacementManifest))
  }

  func testPortraitSpikeRejectsInputsOutsideTheFrozenResourceContract() throws {
    XCTAssertThrowsError(
      try PortraitMaskSpike.validateDimensions(
        width: 12_001,
        height: 1,
        fileBytes: 1,
        isSupportedFormat: true,
        imageCount: 1
      )
    )
    XCTAssertThrowsError(
      try PortraitMaskSpike.validateDimensions(
        width: 8_000,
        height: 6_001,
        fileBytes: 1,
        isSupportedFormat: true,
        imageCount: 1
      )
    )
    XCTAssertThrowsError(
      try PortraitMaskSpike.validateDimensions(
        width: 1,
        height: 1,
        fileBytes: 100 * 1024 * 1024 + 1,
        isSupportedFormat: true,
        imageCount: 1
      )
    )
    XCTAssertThrowsError(
      try PortraitMaskSpike.validateDimensions(
        width: 1,
        height: 1,
        fileBytes: 1,
        isSupportedFormat: false,
        imageCount: 1
      )
    )
    XCTAssertNoThrow(
      try PortraitMaskSpike.validateDimensions(
        width: 8_000,
        height: 6_000,
        fileBytes: 100 * 1024 * 1024,
        isSupportedFormat: true,
        imageCount: 1
      )
    )
  }

  func testPortraitSpikeFullResolutionCandidateUsesMaskAndMonotonicStrengths() throws {
    let sourceExtent = CGRect(x: 0, y: 0, width: 80, height: 60)
    let proxyExtent = CGRect(x: 0, y: 0, width: 40, height: 30)
    let source = CIImage(color: CIColor(red: 0.42, green: 0.31, blue: 0.24, alpha: 1))
      .cropped(to: sourceExtent)
    let whiteHalf = CIImage(color: .white)
      .cropped(to: CGRect(x: 0, y: 0, width: 20, height: 30))
    let black = CIImage(color: .black).cropped(to: proxyExtent)
    let proxyMask = whiteHalf.composited(over: black).cropped(to: proxyExtent)

    let candidates = PortraitMaskSpike.fullResolutionCandidates(
      source: source,
      effectiveProxyMask: proxyMask,
      proxyExtent: proxyExtent,
      sourceExtent: sourceExtent
    )
    let sourceBytes = try rgbaBytes(source)
    let defaultBytes = try rgbaBytes(candidates.defaultImage)
    let highSafeBytes = try rgbaBytes(candidates.highSafeImage)
    let defaultDifference = meanAbsoluteDifference(sourceBytes, defaultBytes)
    let highSafeDifference = meanAbsoluteDifference(sourceBytes, highSafeBytes)

    XCTAssertGreaterThan(defaultDifference, 0.1)
    XCTAssertGreaterThan(highSafeDifference, defaultDifference)
    XCTAssertGreaterThan(meanAbsoluteDifference(defaultBytes, highSafeBytes), 0.1)
    var largestBoundaryDifference = 0
    var largestOutsideDifference = 0
    for y in 0..<60 {
      for x in 40..<80 {
        let offset = (y * 80 + x) * 4
        for channel in 0..<3 {
          let difference = max(
            abs(Int(defaultBytes[offset + channel]) - Int(sourceBytes[offset + channel])),
            abs(Int(highSafeBytes[offset + channel]) - Int(sourceBytes[offset + channel]))
          )
          if x == 40 {
            largestBoundaryDifference = max(largestBoundaryDifference, difference)
          } else {
            largestOutsideDifference = max(largestOutsideDifference, difference)
          }
        }
        XCTAssertEqual(defaultBytes[offset + 3], sourceBytes[offset + 3])
        XCTAssertEqual(highSafeBytes[offset + 3], sourceBytes[offset + 3])
      }
    }
    XCTAssertLessThanOrEqual(
      largestBoundaryDifference,
      4,
      "The one-pixel scaled-mask boundary may differ only by byte-level interpolation"
    )
    XCTAssertLessThanOrEqual(largestOutsideDifference, 3)
  }

  func testPortraitCaptureAndRendererShareOneCandidateIdentity() throws {
    XCTAssertEqual(
      PortraitMaskSpike.effectVersion,
      IOSPortraitRetoucher.effectVersion
    )
    XCTAssertEqual(
      PortraitMaskSpike.candidateKind,
      IOSPortraitRetoucher.candidateKind
    )

    let extent = CGRect(x: 0, y: 0, width: 16, height: 12)
    let source = CIImage(
      color: CIColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 0.5)
    ).cropped(to: extent)
    let mask = CIImage(color: .white).cropped(to: extent)
    let capture = PortraitMaskSpike.candidate(
      source: source,
      mask: mask,
      strength: 0.35,
      extent: extent
    )
    let renderer = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0.35,
      extent: extent
    )

    let captureBytes = try rgbaBytes(capture)
    XCTAssertEqual(captureBytes, try rgbaBytes(renderer))
    XCTAssertTrue(
      stride(from: 3, to: captureBytes.count, by: 4).allSatisfy {
        captureBytes[$0] == 255
      },
      "The shared candidate must normalize transparent inputs onto white"
    )
  }

  func testProductionPortraitCandidateUsesMaskAndMonotonicStrengths() throws {
    let extent = CGRect(x: 0, y: 0, width: 80, height: 60)
    let source = CIImage(color: CIColor(red: 0.42, green: 0.31, blue: 0.24, alpha: 1))
      .cropped(to: extent)
    let whiteHalf = CIImage(color: .white)
      .cropped(to: CGRect(x: 0, y: 0, width: 40, height: 60))
    let mask = whiteHalf.composited(
      over: CIImage(color: .black).cropped(to: extent)
    ).cropped(to: extent)

    let neutral = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0,
      extent: extent
    )
    let defaultImage = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0.35,
      extent: extent
    )
    let highImage = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0.55,
      extent: extent
    )
    let sourceBytes = try rgbaBytes(source)
    let neutralBytes = try rgbaBytes(neutral)
    let defaultBytes = try rgbaBytes(defaultImage)
    let highBytes = try rgbaBytes(highImage)

    XCTAssertEqual(neutralBytes, sourceBytes)
    let defaultDifference = meanAbsoluteDifference(sourceBytes, defaultBytes)
    let highDifference = meanAbsoluteDifference(sourceBytes, highBytes)
    XCTAssertGreaterThan(defaultDifference, 0.1)
    XCTAssertGreaterThan(highDifference, defaultDifference)

    var largestOutsideDifference = 0
    for y in 0..<60 {
      for x in 40..<80 {
        let offset = (y * 80 + x) * 4
        for channel in 0..<3 {
          largestOutsideDifference = max(
            largestOutsideDifference,
            max(
              abs(Int(defaultBytes[offset + channel]) - Int(sourceBytes[offset + channel])),
              abs(Int(highBytes[offset + channel]) - Int(sourceBytes[offset + channel]))
            )
          )
        }
      }
    }
    XCTAssertLessThanOrEqual(largestOutsideDifference, 3)
  }

  func testProductionPortraitCandidateVisiblyReducesFineSkinTexture() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 96)
    let source = try XCTUnwrap(
      CIFilter(
        name: "CICheckerboardGenerator",
        parameters: [
          "inputCenter": CIVector(x: 0, y: 0),
          "inputColor0": CIColor(red: 0.62, green: 0.43, blue: 0.34),
          "inputColor1": CIColor(red: 0.68, green: 0.49, blue: 0.40),
          "inputWidth": 1.0,
          "inputSharpness": 1.0,
        ]
      )?.outputImage?.cropped(to: extent)
    )
    let mask = CIImage(color: .white).cropped(to: extent)
    let defaultImage = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0.35,
      extent: extent
    )
    let highImage = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0.55,
      extent: extent
    )
    let sourceBytes = try rgbaBytes(source)
    let defaultBytes = try rgbaBytes(defaultImage)
    let highBytes = try rgbaBytes(highImage)

    let defaultDifference = meanAbsoluteDifference(sourceBytes, defaultBytes)
    let highDifference = meanAbsoluteDifference(sourceBytes, highBytes)
    XCTAssertGreaterThanOrEqual(defaultDifference, 1.0)
    XCTAssertGreaterThan(highDifference, defaultDifference)
    let sourceTexture = neighborDifference(sourceBytes, width: 96, height: 96)
    let defaultTexture = neighborDifference(defaultBytes, width: 96, height: 96)
    let highTexture = neighborDifference(highBytes, width: 96, height: 96)
    XCTAssertLessThan(
      defaultTexture,
      sourceTexture * 0.8,
      "Default retouch must visibly soften low-contrast skin texture without relying on relighting"
    )
    XCTAssertLessThan(highTexture, defaultTexture)
  }

  func testProductionPortraitCandidatePreservesPermanentHighContrastEdges() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 96)
    let skin = CIImage(
      color: CIColor(red: 0.68, green: 0.48, blue: 0.38, alpha: 1)
    ).cropped(to: extent)
    let permanentEdge = CIImage(
      color: CIColor(red: 0.12, green: 0.08, blue: 0.06, alpha: 1)
    ).cropped(to: CGRect(x: 48, y: 0, width: 1, height: 96))
    let source = permanentEdge.composited(over: skin).cropped(to: extent)
    let mask = CIImage(color: .white).cropped(to: extent)

    let defaultImage = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0.35,
      extent: extent
    )
    let sourceEdge = strongestHorizontalEdge(
      try rgbaBytes(source),
      width: 96,
      height: 96
    )
    let defaultEdge = strongestHorizontalEdge(
      try rgbaBytes(defaultImage),
      width: 96,
      height: 96
    )

    XCTAssertGreaterThan(sourceEdge, 100)
    XCTAssertGreaterThanOrEqual(
      defaultEdge,
      sourceEdge * 0.9,
      "Natural retouch must not erase hair, beard, eye, lip, or permanent-feature edges; "
        + "source=\(sourceEdge), default=\(defaultEdge)"
    )
  }

  func testProductionPortraitRetoucherSafelyPreservesImageWithoutFace() throws {
    let extent = CGRect(x: 0, y: 0, width: 48, height: 32)
    let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
      .cropped(to: extent)

    let output = IOSPortraitRetoucher.applying(
      to: source,
      strength: 0.55,
      extent: extent
    )

    XCTAssertEqual(try rgbaBytes(output), try rgbaBytes(source))
  }

  func testPortraitCandidateSafetyRejectsAmbiguousOrLowQualityFaces() {
    let safeFace = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6)

    XCTAssertTrue(
      IOSPortraitSafetyPolicy.isEligible(
        faceCount: 1,
        confidence: 0.9,
        boundingBox: safeFace,
        hasLandmarks: true
      )
    )
    XCTAssertFalse(
      IOSPortraitSafetyPolicy.isEligible(
        faceCount: 2,
        confidence: 0.9,
        boundingBox: safeFace,
        hasLandmarks: true
      )
    )
    XCTAssertEqual(
      IOSPortraitSafetyPolicy.evaluate(
        faceCount: 0,
        confidence: 0,
        boundingBox: .zero,
        hasLandmarks: false
      ).reason,
      .noFace
    )
    XCTAssertEqual(
      IOSPortraitSafetyPolicy.evaluate(
        faceCount: 2,
        confidence: 0.9,
        boundingBox: safeFace,
        hasLandmarks: true
      ).reason,
      .multipleFaces
    )
    XCTAssertEqual(
      IOSPortraitSafetyPolicy.evaluate(
        faceCount: 1,
        confidence: 0.49,
        boundingBox: safeFace,
        hasLandmarks: true
      ).reason,
      .lowConfidence
    )
    XCTAssertEqual(
      IOSPortraitSafetyPolicy.evaluate(
        faceCount: 1,
        confidence: 0.9,
        boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.08, height: 0.08),
        hasLandmarks: true
      ).reason,
      .faceTooSmall
    )
    XCTAssertEqual(
      IOSPortraitSafetyPolicy.evaluate(
        faceCount: 1,
        confidence: 0.9,
        boundingBox: safeFace,
        hasLandmarks: false
      ).reason,
      .landmarksUnavailable
    )
    XCTAssertFalse(
      IOSPortraitSafetyPolicy.isEligible(
        faceCount: 1,
        confidence: 0.49,
        boundingBox: safeFace,
        hasLandmarks: true
      )
    )
    XCTAssertFalse(
      IOSPortraitSafetyPolicy.isEligible(
        faceCount: 1,
        confidence: 0.9,
        boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.08, height: 0.08),
        hasLandmarks: true
      )
    )
    XCTAssertFalse(
      IOSPortraitSafetyPolicy.isEligible(
        faceCount: 1,
        confidence: 0.9,
        boundingBox: safeFace,
        hasLandmarks: false
      )
    )
  }

  private func pipelineV2(
    schemaVersion: NSNumber = 2,
    exposureEV: Double = 0,
    highlights: Double = 0,
    shadows: Double = 0,
    contrast: Double = 0,
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
        "highlights": highlights,
        "shadows": shadows,
        "contrast": contrast,
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
    try Array(rgbaBytes(image).prefix(4)).map(Int.init)
  }

  private func rgbaBytes(_ image: CIImage) throws -> [UInt8] {
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
    return bytes
  }

  private func normalized(_ image: CIImage) -> CIImage {
    image.transformed(
      by: CGAffineTransform(
        translationX: -image.extent.minX,
        y: -image.extent.minY
      )
    )
  }

  private func meanAbsoluteDifference(_ left: [UInt8], _ right: [UInt8]) -> Double {
    guard left.count == right.count, !left.isEmpty else { return .infinity }
    let total = zip(left, right).reduce(0) { result, pair in
      result + abs(Int(pair.0) - Int(pair.1))
    }
    return Double(total) / Double(left.count)
  }

  private func neighborDifference(
    _ bytes: [UInt8],
    width: Int,
    height: Int
  ) -> Double {
    var total = 0
    var comparisons = 0
    for y in 0..<height {
      for x in 0..<width {
        let offset = (y * width + x) * 4
        if x + 1 < width {
          let right = offset + 4
          for channel in 0..<3 {
            total += abs(Int(bytes[offset + channel]) - Int(bytes[right + channel]))
            comparisons += 1
          }
        }
        if y + 1 < height {
          let below = offset + width * 4
          for channel in 0..<3 {
            total += abs(Int(bytes[offset + channel]) - Int(bytes[below + channel]))
            comparisons += 1
          }
        }
      }
    }
    return Double(total) / Double(comparisons)
  }

  private func strongestHorizontalEdge(
    _ bytes: [UInt8],
    width: Int,
    height: Int
  ) -> Double {
    var strongest = 0.0
    for y in 0..<height {
      for x in 0..<(width - 1) {
        let left = (y * width + x) * 4
        let right = left + 4
        var difference = 0
        for channel in 0..<3 {
          difference += abs(Int(bytes[left + channel]) - Int(bytes[right + channel]))
        }
        strongest = max(strongest, Double(difference) / 3.0)
      }
    }
    return strongest
  }

  private func render(sourceURL: URL, outputURL: URL) throws -> IOSPhotoRenderedFile {
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2()))
    return try IOSPhotoFileRenderer(context: imageContext).render(
      sourcePath: sourceURL.path,
      pipeline: pipeline,
      destinationURL: outputURL
    )
  }

  private func writeJpeg(
    to url: URL,
    width: Int,
    height: Int,
    colorSpace: CGColorSpace,
    properties: [String: Any] = [:]
  ) throws {
    let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
      .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
      .settingProperties(properties)
    try imageContext.writeJPEGRepresentation(
      of: image,
      to: url,
      colorSpace: colorSpace,
      options: [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
      ]
    )
  }

  private func writeAsymmetricJpeg(to url: URL, orientation: Int) throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 64)
    let halfWidth = extent.width / 2
    let halfHeight = extent.height / 2
    var image = CIImage(color: CIColor.black).cropped(to: extent)
    let quadrants: [(CGRect, CIColor)] = [
      (CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight), .red),
      (CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight), .green),
      (CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight), .blue),
      (CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight), .yellow),
    ]
    for (rectangle, color) in quadrants {
      image = CIImage(color: color).cropped(to: rectangle).composited(over: image)
    }
    try imageContext.writeJPEGRepresentation(
      of: image.settingProperties([
        kCGImagePropertyOrientation as String: orientation
      ]),
      to: url,
      colorSpace: sRGB,
      options: [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
      ]
    )
  }

  private func imageProperties(_ url: URL) throws -> [String: Any] {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    )
  }

  private func sha256(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
  }

  private func temporaryURL(extension fileExtension: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-test-\(UUID().uuidString)")
      .appendingPathExtension(fileExtension)
  }

  private func removeTemporaryFiles(_ urls: URL...) {
    for url in urls {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private func removeTemporaryFiles(_ urls: [URL]) {
    for url in urls {
      try? FileManager.default.removeItem(at: url)
    }
  }

}
