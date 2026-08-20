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

  func testPhotoPickerDeadlineCancelsPendingProviderAfterTimeout() {
    let timedOut = expectation(description: "photo picker deadline")
    let progress = Progress(totalUnitCount: 1)
    let deadline = IOSPhotoPickerLoadDeadline(
      timeout: 0.01,
      queue: .main
    ) {
      timedOut.fulfill()
    }

    deadline.track(progress)
    deadline.start()
    wait(for: [timedOut], timeout: 1)

    XCTAssertTrue(progress.isCancelled)
    XCTAssertFalse(deadline.complete())
  }

  func testPhotoPickerDeadlineDoesNotFireAfterCompletion() {
    let timedOut = expectation(description: "photo picker deadline")
    timedOut.isInverted = true
    let progress = Progress(totalUnitCount: 1)
    let deadline = IOSPhotoPickerLoadDeadline(
      timeout: 0.01,
      queue: .main
    ) {
      timedOut.fulfill()
    }

    deadline.track(progress)
    deadline.start()
    XCTAssertTrue(deadline.complete())
    wait(for: [timedOut], timeout: 0.05)

    XCTAssertFalse(progress.isCancelled)
    XCTAssertFalse(deadline.complete())
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

  func testImagePipelineV2ClarityFadesAtBlackAndWhiteEndpoints() throws {
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2()))
    let clarity = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV2(clarity: 0.25)))
    let values: [UInt8] = [0, 0, 32, 32, 96, 96, 160, 160, 224, 224, 255, 255]
    let pixels = values.flatMap { [$0, $0, $0, UInt8(255)] }
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: values.count * 4,
      size: CGSize(width: values.count, height: 1),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let neutralPixels = try rgbaBytes(neutral.applying(to: source, extent: source.extent))
    let clarityPixels = try rgbaBytes(clarity.applying(to: source, extent: source.extent))

    XCTAssertEqual(Array(clarityPixels.prefix(4)), Array(neutralPixels.prefix(4)))
    XCTAssertEqual(Array(clarityPixels.suffix(4)), Array(neutralPixels.suffix(4)))
    XCTAssertGreaterThan(meanAbsoluteDifference(neutralPixels, clarityPixels), 0)
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
        tint: 0.15,
        saturation: 0.2,
        clarity: 0.1,
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

  func testPhotoPreviewTextureMatchesFinalJpegCompleteCompositionSemantics() throws {
    let sourceURL = temporaryURL(extension: "jpg")
    let outputURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    try writeAsymmetricJpeg(to: sourceURL, orientation: 1)
    var arguments = pipelineV7(
      flipHorizontal: true,
      perspectiveHorizontal: 8,
      perspectiveVertical: -6
    )
    var geometry = arguments["geometry"] as! [String: Any]
    geometry["normalizedCrop"] = [0.1, 0.12, 0.9, 0.88]
    geometry["quarterTurns"] = 3
    geometry["straightenDegrees"] = 3.0
    arguments["geometry"] = geometry
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: arguments))
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
      "Texture preview and final JPEG must share crop, rotate, flip, straighten, and perspective semantics"
    )
  }

  func testPhotoPreviewTextureMatchesFinalJpegLocalSemanticSemantics() throws {
    let sourceURL = temporaryURL(extension: "jpg")
    let outputURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    try writeAsymmetricJpeg(to: sourceURL, orientation: 1)
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV10(
      localExposure: 35,
      localSaturation: 20,
      localAdjustmentStrokes: [[
        "operation": "paint", "radius": 0.08,
        "points": [[0.25, 0.35], [0.3, 0.4]],
      ]],
      eraseStrokes: [[
        "radius": 0.06, "points": [[0.72, 0.28]],
      ]]
    )))
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
      "Texture preview and final JPEG must share local mask and erase semantics"
    )
  }

  func testPhotoPreviewTextureMatchesFinalJpegFaceAndBodySlimSemantics() throws {
    let sourceURL = temporaryURL(extension: "jpg")
    let outputURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    try writeStripedJpeg(to: sourceURL, width: 96, height: 64)
    let extent = CGRect(x: 0, y: 0, width: 96, height: 64)
    let portraitContext = IOSPortraitRetouchContext(
      effectiveMask: nil,
      faceSlimGeometry: IOSFaceSlimGeometry(
        centerX: 48,
        halfWidth: 28,
        lowerY: 20,
        upperY: 58
      ),
      faceMask: CIImage(color: .white).cropped(to: extent),
      bodySlimGeometry: IOSBodySlimGeometry(
        centerX: 48,
        halfWidth: 38,
        lowerY: 4,
        upperY: 60
      ),
      personMask: CIImage(color: .white).cropped(to: extent)
    )
    let pipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV3(
        faceSlimStrength: 0.5,
        bodySlimStrength: 0.35
      ))
    )
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV3()))
    let neutralBytes = try rgbaBytes(
      neutral.applying(to: try XCTUnwrap(CIImage(contentsOf: sourceURL)), extent: extent)
    )

    let session = try IOSPhotoPreviewSession(
      sourcePath: sourceURL.path,
      maxEdge: 2_048,
      pipeline: pipeline,
      preparedPortraitContext: portraitContext
    )
    defer { session.close() }
    let previewBuffer = try XCTUnwrap(session.copyPixelBuffer()).takeRetainedValue()
    let previewBytes = try rgbaBytes(CIImage(cvPixelBuffer: previewBuffer))

    _ = try IOSPhotoFileRenderer(context: imageContext).render(
      sourcePath: sourceURL.path,
      pipeline: pipeline,
      destinationURL: outputURL,
      preparedPortraitContext: portraitContext
    )
    let exported = try XCTUnwrap(
      CIImage(contentsOf: outputURL, options: [.applyOrientationProperty: true])
    )
    let exportedBytes = try rgbaBytes(normalized(exported))

    XCTAssertGreaterThan(
      meanAbsoluteDifference(neutralBytes, previewBytes),
      0.25,
      "non-zero face and body slim must reach the texture preview"
    )
    XCTAssertEqual(session.width, Int(exported.extent.width))
    XCTAssertEqual(session.height, Int(exported.extent.height))
    XCTAssertLessThanOrEqual(
      meanAbsoluteDifference(previewBytes, exportedBytes),
      7.0,
      "Texture preview and final JPEG must preserve face and body slim semantics "
        + "within the striped fixture's JPEG recompression tolerance at the product maxima"
    )
  }

  func testPhotoPreviewTextureMatchesFinalJpegFiveParameterPortraitSemantics() throws {
    let sourceURL = temporaryURL(extension: "jpg")
    let outputURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    try writeStripedJpeg(to: sourceURL, width: 96, height: 64)
    let extent = CGRect(x: 0, y: 0, width: 96, height: 64)
    let fullMask = CIImage(color: .white).cropped(to: extent)
    let portraitContext = IOSPortraitRetouchContext(
      effectiveMask: fullMask,
      faceSlimGeometry: IOSFaceSlimGeometry(
        centerX: 48,
        halfWidth: 28,
        lowerY: 20,
        upperY: 58
      ),
      faceMask: fullMask,
      bodySlimGeometry: IOSBodySlimGeometry(
        centerX: 48,
        halfWidth: 38,
        lowerY: 4,
        upperY: 60
      ),
      personMask: fullMask
    )
    let pipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV4(
        textureSmoothing: 45,
        skinToneLighting: 40,
        blemishReduction: 20,
        faceSlimming: 30,
        torsoSlimming: 20
      ))
    )
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV4()))
    let source = try XCTUnwrap(CIImage(contentsOf: sourceURL))
    let neutralBytes = try rgbaBytes(neutral.applying(to: source, extent: extent))

    let session = try IOSPhotoPreviewSession(
      sourcePath: sourceURL.path,
      maxEdge: 2_048,
      pipeline: pipeline,
      preparedPortraitContext: portraitContext
    )
    defer { session.close() }
    let previewBuffer = try XCTUnwrap(session.copyPixelBuffer()).takeRetainedValue()
    let previewBytes = try rgbaBytes(CIImage(cvPixelBuffer: previewBuffer))

    _ = try IOSPhotoFileRenderer(context: imageContext).render(
      sourcePath: sourceURL.path,
      pipeline: pipeline,
      destinationURL: outputURL,
      preparedPortraitContext: portraitContext
    )
    let exported = try XCTUnwrap(
      CIImage(contentsOf: outputURL, options: [.applyOrientationProperty: true])
    )
    let exportedBytes = try rgbaBytes(normalized(exported))

    XCTAssertGreaterThan(meanAbsoluteDifference(neutralBytes, previewBytes), 0.25)
    XCTAssertEqual(session.width, Int(exported.extent.width))
    XCTAssertEqual(session.height, Int(exported.extent.height))
    XCTAssertLessThanOrEqual(
      meanAbsoluteDifference(previewBytes, exportedBytes),
      7.5,
      "The uncompressed preview and JPEG 95 export may differ slightly after "
        + "five stacked portrait operations, but must retain the same geometry and semantics"
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

  func testImagePipelineConsumesAndValidatesRenderPlanEnvelope() {
    let valid: [String: Any] = ["renderPlanV1": [
      "protocolVersion": 1,
      "planId": "rp1-1234abcd",
      "sourceId": "photo-1",
      "stateRevision": 3,
      "stages": [],
      "requiredCapabilities": [],
      "outputRequirements": [
        "purpose": "preview",
        "colorSpace": "srgb",
        "format": "display",
        "quality": "interactive",
      ],
      "backendPayload": pipelineV2(),
    ]]
    XCTAssertNotNil(IOSImagePipeline(arguments: valid))

    var invalid = valid
    var renderPlan = invalid["renderPlanV1"] as! [String: Any]
    renderPlan["planId"] = "not-a-plan"
    invalid["renderPlanV1"] = renderPlan
    XCTAssertNil(IOSImagePipeline(arguments: invalid))
  }

  func testImagePipelineV3AcceptsBoundedFaceAndBodySlimStrengths() {
    let neutral = IOSImagePipeline(arguments: pipelineV3())
    XCTAssertEqual(neutral?.faceSlimStrength, 0)
    XCTAssertEqual(neutral?.bodySlimStrength, 0)
    XCTAssertEqual(
      IOSImagePipeline(arguments: pipelineV3(faceSlimStrength: 0.1))?.faceSlimStrength,
      0.1
    )
    XCTAssertEqual(
      IOSImagePipeline(arguments: pipelineV3(bodySlimStrength: 0.1))?.bodySlimStrength,
      0.1
    )
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV3(faceSlimStrength: -0.01)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV3(bodySlimStrength: 1.01)))

    var booleanReshape = pipelineV3()
    var reshape = booleanReshape["reshape"] as! [String: Any]
    reshape["faceSlimStrength"] = true
    booleanReshape["reshape"] = reshape
    XCTAssertNil(IOSImagePipeline(arguments: booleanReshape))
  }

  func testImagePipelineV4ValidatesFiveParameterPortraitIdentity() {
    let pipeline = IOSImagePipeline(arguments: pipelineV4(
      textureSmoothing: 40,
      skinToneLighting: 30,
      blemishReduction: 20,
      faceSlimming: 10,
      torsoSlimming: 5
    ))
    XCTAssertEqual(pipeline?.textureSmoothing, 40)
    XCTAssertEqual(pipeline?.skinToneLighting, 30)
    XCTAssertEqual(pipeline?.blemishReduction, 20)
    XCTAssertEqual(pipeline?.faceSlimming, 10)
    XCTAssertEqual(pipeline?.torsoSlimming, 5)

    XCTAssertNil(IOSImagePipeline(arguments: pipelineV4(textureSmoothing: 101)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV4(faceSlimming: 10.5)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV4(recipeVersion: 99)))
    var unknown = pipelineV4()
    var portrait = unknown["portraitRecipeV2"] as! [String: Any]
    portrait["futureField"] = 1
    unknown["portraitRecipeV2"] = portrait
    XCTAssertNil(IOSImagePipeline(arguments: unknown))
    var legacyComposite = pipelineV4()
    legacyComposite["portrait"] = ["recipeVersion": 1, "strength": 0.4]
    XCTAssertNil(IOSImagePipeline(arguments: legacyComposite))
    var legacyReshape = pipelineV4()
    legacyReshape["reshape"] = [
      "recipeVersion": 1,
      "faceSlimStrength": 0.2,
      "bodySlimStrength": 0.1,
    ]
    XCTAssertNil(IOSImagePipeline(arguments: legacyReshape))
  }

  func testImagePipelineV5ValidatesIndependentFaceSlimTargets() {
    let pipeline = IOSImagePipeline(arguments: pipelineV5(
      selectedTargetIndex: 1,
      targetStrengths: [0.2, 0.45]
    ))
    XCTAssertEqual(pipeline?.faceSlimStrengths, [0.2, 0.45])
    XCTAssertEqual(pipeline?.faceSlimStrength, 0.45)

    XCTAssertNil(IOSImagePipeline(arguments: pipelineV5(targetStrengths: [])))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV5(targetStrengths: [0, 0, 0, 0])))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV5(
      selectedTargetIndex: 2,
      targetStrengths: [0, 0]
    )))
    var booleanStrength = pipelineV5(targetStrengths: [0.2])
    var recipe = booleanStrength["faceSlimRecipeV1"] as! [String: Any]
    recipe["targetStrengths"] = [true]
    booleanStrength["faceSlimRecipeV1"] = recipe
    XCTAssertNil(IOSImagePipeline(arguments: booleanStrength))
  }

  func testImagePipelineV6ValidatesIndependentQualityEnhancementParameters() {
    let pipeline = IOSImagePipeline(arguments: pipelineV6(
      noiseReduction: 30,
      lowLightRecovery: 40,
      hazeRemoval: 25,
      detailSharpening: 20
    ))
    XCTAssertEqual(pipeline?.noiseReduction, 30)
    XCTAssertEqual(pipeline?.lowLightRecovery, 40)
    XCTAssertEqual(pipeline?.hazeRemoval, 25)
    XCTAssertEqual(pipeline?.detailSharpening, 20)

    XCTAssertNil(IOSImagePipeline(arguments: pipelineV6(noiseReduction: 101)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV6(lowLightRecovery: 20.5)))
    var unknown = pipelineV6()
    var recipe = unknown["qualityEnhancementRecipeV1"] as! [String: Any]
    recipe["futureField"] = 1
    unknown["qualityEnhancementRecipeV1"] = recipe
    XCTAssertNil(IOSImagePipeline(arguments: unknown))
  }

  func testImagePipelineV7ValidatesBasicEditingAndKeepsNeutralPixels() throws {
    let v6 = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6()))
    let v7 = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV7()))
    let source = stripedImage(extent: CGRect(x: 0, y: 0, width: 64, height: 64))
    XCTAssertEqual(
      try rgbaBytes(v7.applying(to: source, extent: source.extent)),
      try rgbaBytes(v6.applying(to: source, extent: source.extent))
    )

    let edited = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV7(
      flipHorizontal: true,
      filter: "cinematic",
      filterStrength: 60,
      hsl: ["blue": ["hue": 12, "saturation": 20, "lightness": -5]]
    )))
    XCTAssertTrue(edited.flipHorizontal)
    XCTAssertEqual(edited.photoFilter, "cinematic")
    XCTAssertEqual(edited.filterStrength, 60)
    XCTAssertGreaterThan(
      meanAbsoluteDifference(
        try rgbaBytes(v7.applying(to: source, extent: source.extent)),
        try rgbaBytes(edited.applying(to: source, extent: source.extent))
      ),
      0.01
    )

    XCTAssertNil(IOSImagePipeline(arguments: pipelineV7(filter: "unknown")))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV7(filterStrength: 101)))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV7(
      hsl: ["blue": ["hue": 101, "saturation": 0, "lightness": 0]]
    )))
  }

  func testImagePipelineV7CinematicFilterPreservesNonzeroShadowDetail() throws {
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV7()))
    let cinematic = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV7(filter: "cinematic", filterStrength: 60))
    )
    let pixels: [UInt8] = [4, 6, 8, 255, 12, 14, 16, 255]
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: 8,
      size: CGSize(width: 2, height: 1),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let baseline = try rgbaBytes(neutral.applying(to: source, extent: source.extent))
    let output = try rgbaBytes(cinematic.applying(to: source, extent: source.extent))

    XCTAssertTrue(output.prefix(3).allSatisfy { $0 > 0 })
    XCTAssertNotEqual(output, baseline)
  }

  func testImagePipelineV8ValidatesIndependentPortraitGeometry() throws {
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV8(
      selectedFaceIndex: 1,
      faceTargets: [
        ["faceSlim": 32, "headSize": 18, "jaw": -12, "chin": 9,
         "eyes": 14, "nose": -8, "mouth": 7],
        ["faceSlim": 10, "headSize": 0, "jaw": 0, "chin": 0,
         "eyes": 0, "nose": 0, "mouth": 0],
      ],
      bodyTargets: [[
        "slimming": 25, "height": 16, "shoulders": 12, "waist": -20, "legs": 18,
      ]]
    )))
    XCTAssertEqual(pipeline.selectedFaceGeometryIndex, 1)
    XCTAssertEqual(pipeline.faceGeometryTargets[0].headSize, 18)
    XCTAssertEqual(pipeline.faceGeometryTargets[0].jaw, -12)
    XCTAssertEqual(pipeline.bodyGeometryTargets[0].height, 16)
    XCTAssertEqual(pipeline.bodyGeometryTargets[0].waist, -20)

    let fractional = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV8(
      faceTargets: [[
        "faceSlim": 42.5, "headSize": 18.4, "jaw": -12.6, "chin": 0,
        "eyes": 0, "nose": 0, "mouth": 0,
      ]],
      bodyTargets: [[
        "slimming": 34.65, "height": 0, "shoulders": 0, "waist": 0, "legs": 0,
      ]]
    )))
    XCTAssertEqual(fractional.faceGeometryTargets[0].faceSlim, 43)
    XCTAssertEqual(fractional.faceGeometryTargets[0].headSize, 18)
    XCTAssertEqual(fractional.faceGeometryTargets[0].jaw, -13)
    XCTAssertEqual(fractional.bodyGeometryTargets[0].slimming, 35)

    var tooMany = pipelineV8()
    var recipe = tooMany["portraitGeometryRecipeV1"] as! [String: Any]
    let target = recipe["faceTargets"] as! [[String: Any]]
    recipe["faceTargets"] = [target[0], target[0], target[0], target[0]]
    tooMany["portraitGeometryRecipeV1"] = recipe
    XCTAssertNil(IOSImagePipeline(arguments: tooMany))

    var outOfRange = pipelineV8()
    recipe = outOfRange["portraitGeometryRecipeV1"] as! [String: Any]
    var faces = recipe["faceTargets"] as! [[String: Any]]
    faces[0]["eyes"] = 101
    recipe["faceTargets"] = faces
    outOfRange["portraitGeometryRecipeV1"] = recipe
    XCTAssertNil(IOSImagePipeline(arguments: outOfRange))
  }

  func testImagePipelineV8AppliesFaceAndBodyGeometryInsideProtectedMasks() throws {
    let extent = CGRect(x: 0, y: 0, width: 160, height: 160)
    let source = stripedImage(extent: extent)
    let black = CIImage(color: .black).cropped(to: extent)
    func mask(_ rect: CGRect) -> CIImage {
      CIImage(color: .white).cropped(to: rect).composited(over: black)
    }
    let faceRect = CGRect(x: 18, y: 72, width: 52, height: 68)
    let bodyRect = CGRect(x: 88, y: 12, width: 58, height: 124)
    let context = IOSPortraitRetouchContext(
      effectiveMask: nil,
      faceSlimTargets: [IOSFaceSlimTargetContext(
        geometry: IOSFaceSlimGeometry(
          centerX: faceRect.midX, halfWidth: 24,
          lowerY: faceRect.minY, upperY: faceRect.minY + 40
        ),
        mask: mask(faceRect),
        features: IOSFaceFeatureGeometry(
          faceBounds: faceRect,
          leftEye: CGPoint(x: 35, y: 112),
          rightEye: CGPoint(x: 54, y: 112),
          nose: CGPoint(x: 44, y: 98),
          mouth: CGPoint(x: 44, y: 86)
        )
      )],
      bodyReshapeTargets: [IOSBodyReshapeTargetContext(
        geometry: IOSBodySlimGeometry(
          centerX: bodyRect.midX, halfWidth: 25,
          lowerY: 48, upperY: 124
        ),
        personMask: mask(bodyRect)
      )]
    )
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV8()))
    let edited = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV8(
      faceTargets: [[
        "faceSlim": 35, "headSize": 30, "jaw": -20, "chin": 18,
        "eyes": 24, "nose": -14, "mouth": 16,
      ]],
      bodyTargets: [[
        "slimming": 30, "height": 22, "shoulders": 16, "waist": -24, "legs": 20,
      ]]
    )))
    let sourceBytes = try rgbaBytes(source)
    XCTAssertEqual(
      try rgbaBytes(neutral.applying(to: source, extent: extent, portraitContext: context)),
      sourceBytes
    )
    let editedBytes = try rgbaBytes(
      edited.applying(to: source, extent: extent, portraitContext: context)
    )
    XCTAssertGreaterThan(meanAbsoluteDifference(sourceBytes, editedBytes), 0.15)
    for y in 0..<160 {
      for x in 72..<84 {
        let offset = (y * 160 + x) * 4
        XCTAssertEqual(
          Array(editedBytes[offset..<(offset + 4)]),
          Array(sourceBytes[offset..<(offset + 4)])
        )
      }
    }
  }

  func testImagePipelineV9ValidatesSemanticEditingContract() throws {
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV9(
      background: "blur",
      backgroundBlur: 45,
      subjectExposure: 18,
      backgroundSaturation: -20,
      eraseStrokes: [[
        "radius": 0.03,
        "points": [[0.25, 0.35], [0.28, 0.38]],
      ]]
    )))
    XCTAssertEqual(pipeline.semanticEditing.background, "blur")
    XCTAssertEqual(pipeline.semanticEditing.backgroundBlur, 45)
    XCTAssertEqual(pipeline.semanticEditing.subjectExposure, 18)
    XCTAssertEqual(pipeline.semanticEditing.backgroundSaturation, -20)
    XCTAssertEqual(pipeline.semanticEditing.eraseStrokes.first?.points.count, 2)

    XCTAssertNil(IOSImagePipeline(arguments: pipelineV9(background: "replace-url")))
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV9(
      eraseStrokes: [["radius": 0.2, "points": [[0.5, 0.5]]]]
    )))
  }

  func testImagePipelineV9AppliesProtectedBackgroundLocalColorAndErase() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 96)
    let source = CIImage(
      color: CIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    ).cropped(to: extent)
    let black = CIImage(color: .black).cropped(to: extent)
    let subjectMask = CIImage(color: .white)
      .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 96))
      .composited(over: black)
    let context = IOSPortraitRetouchContext(
      effectiveMask: nil,
      bodyReshapeTargets: [IOSBodyReshapeTargetContext(
        geometry: IOSBodySlimGeometry(
          centerX: 24, halfWidth: 22, lowerY: 10, upperY: 86
        ),
        personMask: subjectMask
      )]
    )
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV9(
      background: "white",
      subjectExposure: 20
    )))
    let bytes = try rgbaBytes(
      pipeline.applying(to: source, extent: extent, portraitContext: context)
    )
    let left = (48 * 96 + 24) * 4
    let right = (48 * 96 + 72) * 4
    XCTAssertGreaterThan(bytes[left], 51)
    XCTAssertEqual(Array(bytes[right..<(right + 3)]), [255, 255, 255])

    let texture = stripedImage(extent: extent)
    let erased = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV9(
      eraseStrokes: [["radius": 0.06, "points": [[0.5, 0.5]]]]
    )))
    XCTAssertGreaterThan(
      meanAbsoluteDifference(
        try rgbaBytes(texture),
        try rgbaBytes(erased.applying(
          to: texture,
          extent: extent,
          portraitContext: .unavailable
        ))
      ),
      0.05
    )
  }

  func testImagePipelineV10ValidatesAndAppliesEditableMasks() throws {
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV10(
      localExposure: 40,
      subjectMaskStrokes: [[
        "operation": "erase", "radius": 0.08, "points": [[0.5, 0.5]],
      ]],
      localAdjustmentStrokes: [[
        "operation": "paint", "radius": 0.08, "points": [[0.25, 0.5]],
      ]]
    )))
    XCTAssertEqual(pipeline.semanticEditing.localExposure, 40)
    XCTAssertEqual(pipeline.semanticEditing.subjectMaskStrokes.first?.operation, "erase")
    XCTAssertEqual(pipeline.semanticEditing.localAdjustmentStrokes.first?.operation, "paint")
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV10(
      subjectMaskStrokes: [[
        "operation": "replace", "radius": 0.08, "points": [[0.5, 0.5]],
      ]]
    )))

    let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
    let source = CIImage(
      color: CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
    ).cropped(to: extent)
    let bytes = try rgbaBytes(pipeline.applying(
      to: source,
      extent: extent,
      portraitContext: .unavailable
    ))
    let painted = (50 * 100 + 25) * 4
    let untouched = (50 * 100 + 85) * 4
    XCTAssertGreaterThan(bytes[painted], bytes[untouched])
    XCTAssertEqual(Array(bytes[untouched..<(untouched + 3)]), [51, 51, 51])

    let backgroundURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-v10-background.png")
    defer { try? FileManager.default.removeItem(at: backgroundURL) }
    try writePNG(
      CIImage(color: CIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: 40, height: 80)),
      to: backgroundURL
    )
    let backgroundPipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV10(
      background: "image",
      backgroundImagePath: backgroundURL.path,
      backgroundImageResourceId: "resource-v1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    )))
    let black = CIImage(color: .black).cropped(to: extent)
    let subjectMask = CIImage(color: .white)
      .cropped(to: CGRect(x: 0, y: 0, width: 50, height: 100))
      .composited(over: black)
    let context = IOSPortraitRetouchContext(
      effectiveMask: nil,
      bodyReshapeTargets: [IOSBodyReshapeTargetContext(
        geometry: IOSBodySlimGeometry(centerX: 25, halfWidth: 24, lowerY: 0, upperY: 100),
        personMask: subjectMask
      )]
    )
    let backgroundBytes = try rgbaBytes(backgroundPipeline.applying(
      to: source,
      extent: extent,
      portraitContext: context
    ))
    let backgroundPixel = (50 * 100 + 75) * 4
    XCTAssertGreaterThan(backgroundBytes[backgroundPixel], backgroundBytes[backgroundPixel + 1])
  }

  func testImagePipelineV10AcceptsVersionFourContentResourceIdentities() throws {
    let resourceId =
      "resource-v1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    var arguments = pipelineV10(localAdjustmentStrokes: [[
      "operation": "paint", "radius": 0.08, "points": [[0.25, 0.5]],
    ]])
    var semantic = try XCTUnwrap(
      arguments["semanticEditingRecipeV2"] as? [String: Any]
    )
    semantic["recipeVersion"] = 4
    semantic["subjectMaskResourceId"] = ""
    semantic["localMaskResourceId"] = resourceId
    semantic["eraseMaskResourceId"] = ""
    arguments["semanticEditingRecipeV2"] = semantic

    XCTAssertNotNil(IOSImagePipeline(arguments: arguments))

    semantic["localMaskResourceId"] = "unsafe-path"
    arguments["semanticEditingRecipeV2"] = semantic
    XCTAssertNil(IOSImagePipeline(arguments: arguments))
  }

  func testImagePipelineV11ValidatesStableTargetPortraitContract() throws {
    let adjustment: [String: Any] = [
      "targetId": "target-v1-1234abcd",
      "region": ["left": 0.1, "top": 0.3, "right": 0.4, "bottom": 0.8],
      "textureSmoothing": 42,
      "skinToneLighting": 25,
      "blemishReduction": 18,
    ]
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV11(
      adjustments: [adjustment]
    )))
    XCTAssertEqual(pipeline.targetedPortraitAdjustments.count, 1)
    XCTAssertEqual(pipeline.targetedPortraitAdjustments.first?.targetId, "target-v1-1234abcd")
    XCTAssertEqual(pipeline.targetedPortraitAdjustments.first?.textureSmoothing, 42)
    XCTAssertEqual(pipeline.targetedPortraitAdjustments.first?.skinToneLighting, 25)
    XCTAssertEqual(pipeline.targetedPortraitAdjustments.first?.blemishReduction, 18)

    XCTAssertNil(IOSImagePipeline(arguments: pipelineV11(
      adjustments: [adjustment, adjustment]
    )))
    var invalidId = adjustment
    invalidId["targetId"] = "face-0"
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV11(adjustments: [invalidId])))
    var fractional = adjustment
    fractional["textureSmoothing"] = 10.5
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV11(adjustments: [fractional])))
    var invalidRegion = adjustment
    invalidRegion["region"] = ["left": 0.7, "top": 0.3, "right": 0.4, "bottom": 0.8]
    XCTAssertNil(IOSImagePipeline(arguments: pipelineV11(adjustments: [invalidRegion])))
  }

  func testImagePipelineV11AppliesPortraitOnlyToMatchedStableTarget() throws {
    let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
    let source = CIImage(
      color: CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
    ).cropped(to: extent)
    let black = CIImage(color: .black).cropped(to: extent)
    func mask(_ rect: CGRect) -> CIImage {
      CIImage(color: .white).cropped(to: rect).composited(over: black)
    }
    func target(_ rect: CGRect) -> IOSFaceSlimTargetContext {
      IOSFaceSlimTargetContext(
        geometry: IOSFaceSlimGeometry(
          centerX: rect.midX, halfWidth: rect.width / 2,
          lowerY: rect.minY, upperY: rect.maxY
        ),
        mask: mask(rect),
        features: IOSFaceFeatureGeometry(
          faceBounds: rect,
          leftEye: CGPoint(x: rect.minX + 8, y: rect.maxY - 12),
          rightEye: CGPoint(x: rect.maxX - 8, y: rect.maxY - 12),
          nose: CGPoint(x: rect.midX, y: rect.midY),
          mouth: CGPoint(x: rect.midX, y: rect.minY + 10)
        )
      )
    }
    let left = CGRect(x: 10, y: 20, width: 30, height: 50)
    let right = CGRect(x: 60, y: 20, width: 30, height: 50)
    let context = IOSPortraitRetouchContext(
      effectiveMask: nil,
      faceSlimTargets: [target(left), target(right)]
    )
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV11(
      adjustments: [[
        "targetId": "target-v1-1234abcd",
        "region": ["left": 0.1, "top": 0.3, "right": 0.4, "bottom": 0.8],
        "textureSmoothing": 0,
        "skinToneLighting": 60,
        "blemishReduction": 0,
      ]]
    )))
    let bytes = try rgbaBytes(
      pipeline.applying(to: source, extent: extent, portraitContext: context)
    )
    let leftPixel = (45 * 100 + 25) * 4
    let rightPixel = (45 * 100 + 75) * 4
    XCTAssertGreaterThan(bytes[leftPixel], 51)
    XCTAssertEqual(Array(bytes[rightPixel..<(rightPixel + 3)]), [51, 51, 51])
  }

  func testPhotoExportOptionsValidateFormatSizeAndQuality() {
    let original = IOSPhotoExportOptions(arguments: [
      "format": "jpeg", "size": "original", "quality": "high", "colorSpace": "srgb",
    ])
    XCTAssertEqual(original?.format, "jpeg")
    XCTAssertNil(original?.longEdgePixels)

    let resized = IOSPhotoExportOptions(arguments: [
      "format": "heif", "size": "longEdge", "longEdgePixels": 2048,
      "quality": "standard", "colorSpace": "srgb",
    ])
    XCTAssertEqual(resized?.format, "heif")
    XCTAssertEqual(resized?.longEdgePixels, 2048)
    XCTAssertNil(IOSPhotoExportOptions(arguments: [
      "format": "png", "size": "original", "quality": "high", "colorSpace": "srgb",
    ]))
  }

  func testImagePipelineV6NeutralIsPixelEquivalentToV5() throws {
    let v5 = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV5()))
    let v6 = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6()))
    let source = stripedImage(extent: CGRect(x: 0, y: 0, width: 64, height: 64))

    XCTAssertEqual(
      try rgbaBytes(v6.applying(to: source, extent: source.extent)),
      try rgbaBytes(v5.applying(to: source, extent: source.extent))
    )
  }

  func testImagePipelineV6LowLightRecoveryLiftsDarkTonesConservatively() throws {
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6()))
    let improved = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV6(lowLightRecovery: 60))
    )
    let pixels: [UInt8] = [31, 31, 31, 255, 220, 220, 220, 255]
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: 8,
      size: CGSize(width: 2, height: 1),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let baseline = try rgbaBytes(neutral.applying(to: source, extent: source.extent))
    let output = try rgbaBytes(improved.applying(to: source, extent: source.extent))

    XCTAssertGreaterThan(output[0], baseline[0])
    XCTAssertLessThanOrEqual(abs(Int(output[4]) - Int(baseline[4])), 4)
  }

  func testImagePipelineV6HazeRemovalIncreasesLowContrastSeparation() throws {
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6()))
    let improved = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6(hazeRemoval: 60)))
    let pixels: [UInt8] = [105, 110, 115, 255, 155, 160, 165, 255]
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: 8,
      size: CGSize(width: 2, height: 1),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let baseline = try rgbaBytes(neutral.applying(to: source, extent: source.extent))
    let output = try rgbaBytes(improved.applying(to: source, extent: source.extent))

    XCTAssertGreaterThan(Int(output[4]) - Int(output[0]), Int(baseline[4]) - Int(baseline[0]))
  }

  func testImagePipelineV6HazeRemovalPreservesNonzeroShadowDetail() throws {
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6()))
    let improved = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6(hazeRemoval: 60)))
    let pixels: [UInt8] = [4, 6, 8, 255, 12, 14, 16, 255]
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: 8,
      size: CGSize(width: 2, height: 1),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let baseline = try rgbaBytes(neutral.applying(to: source, extent: source.extent))
    let output = try rgbaBytes(improved.applying(to: source, extent: source.extent))

    XCTAssertTrue(output.prefix(3).allSatisfy { $0 > 0 })
    XCTAssertLessThanOrEqual(abs(Int(output[0]) - Int(baseline[0])), 3)
  }

  func testImagePipelineV6NoiseReductionSuppressesAlternatingLumaNoise() throws {
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6()))
    let improved = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6(noiseReduction: 70)))
    let pixels = (0..<(64 * 64)).flatMap { index -> [UInt8] in
      let value: UInt8 = index % 2 == 0 ? 95 : 145
      return [value, value, value, 255]
    }
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: 64 * 4,
      size: CGSize(width: 64, height: 64),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let baseline = try rgbaBytes(neutral.applying(to: source, extent: source.extent))
    let output = try rgbaBytes(improved.applying(to: source, extent: source.extent))

    XCTAssertLessThan(meanHorizontalLumaDifference(output, width: 64),
                      meanHorizontalLumaDifference(baseline, width: 64))
  }

  func testImagePipelineV6DetailSharpeningChangesASoftEdgeWithoutResizing() throws {
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6()))
    let improved = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV6(detailSharpening: 60))
    )
    let width = 64
    let pixels = (0..<(width * width)).flatMap { index -> [UInt8] in
      let x = index % width
      let value = UInt8(80 + min(96, max(0, (x - 20) * 4)))
      return [value, value, value, 255]
    }
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: width * 4,
      size: CGSize(width: width, height: width),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let baseline = try rgbaBytes(neutral.applying(to: source, extent: source.extent))
    let outputImage = improved.applying(to: source, extent: source.extent)
    let output = try rgbaBytes(outputImage)

    XCTAssertEqual(outputImage.extent, source.extent)
    XCTAssertGreaterThan(meanAbsoluteDifference(baseline, output), 0.01)
  }

  func testImagePipelineV6PreviewAndFinalJpegShareQualitySemantics() throws {
    let sourceURL = temporaryURL(extension: "jpg")
    let outputURL = temporaryURL(extension: "jpg")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    try writeStripedJpeg(to: sourceURL, width: 96, height: 64)
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV6(
      noiseReduction: 28,
      lowLightRecovery: 32,
      hazeRemoval: 18,
      detailSharpening: 16
    )))
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
    XCTAssertLessThanOrEqual(meanAbsoluteDifference(previewBytes, exportedBytes), 7.0)
  }

  func testImagePipelineV4AppliesExplicitEffectsOnceAndIgnoresLegacyComposite() throws {
    let extent = CGRect(x: 0, y: 0, width: 48, height: 48)
    let source = CIImage(color: CIColor(red: 0.62, green: 0.42, blue: 0.34))
      .cropped(to: extent)
    let mask = CIImage(color: .white).cropped(to: extent)
    let context = IOSPortraitRetouchContext(effectiveMask: mask)
    let expanded = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV4(
        textureSmoothing: 40,
        skinToneLighting: 40
      ))
    )
    let relit = IOSPortraitRetoucher.applyingSkinToneLighting(
      to: source, strength: 0.4, mask: mask, extent: extent
    )
    let expected = IOSPortraitRetoucher.applyingTextureSmoothing(
      to: relit, strength: 0.4, mask: mask, extent: extent
    )

    XCTAssertEqual(
      try rgbaBytes(expanded.applying(to: source, extent: extent, portraitContext: context)),
      try rgbaBytes(expected)
    )
  }

  func testImagePipelineV4UsesOnlyExplicitNonGeometricParameters() throws {
    let extent = CGRect(x: 0, y: 0, width: 48, height: 48)
    let base = CIImage(color: CIColor(red: 0.62, green: 0.42, blue: 0.34))
      .cropped(to: extent)
    let texture = CIImage(color: CIColor(red: 0.78, green: 0.55, blue: 0.46))
      .cropped(to: CGRect(x: 18, y: 18, width: 4, height: 4))
    let source = texture.composited(over: base).cropped(to: extent)
    let mask = CIImage(color: .white).cropped(to: extent)
    let context = IOSPortraitRetouchContext(effectiveMask: mask)
    let allExplicitEffectsOff = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV4())
    )
    let smoothingOn = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV4(textureSmoothing: 60))
    )

    XCTAssertEqual(
      try rgbaBytes(allExplicitEffectsOff.applying(
        to: source, extent: extent, portraitContext: context
      )),
      try rgbaBytes(source),
      "schema 4 must not retain a hidden legacy portrait result"
    )
    XCTAssertNotEqual(
      try rgbaBytes(smoothingOn.applying(
        to: source, extent: extent, portraitContext: context
      )),
      try rgbaBytes(source)
    )
  }

  func testTextureSmoothingUsesMatureDefaultToReduceMicrotextureAndKeepFaceEdge() throws {
    let width = 96
    let height = 64
    let pixels = (0..<(width * height)).flatMap { index -> [UInt8] in
      let x = index % width
      let checker = ((index / width) + x).isMultiple(of: 2) ? 18 : -18
      let base = x < width / 2 ? 112 : 188
      let value = UInt8(clamping: base + checker)
      return [value, value, value, 255]
    }
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: width * 4,
      size: CGSize(width: width, height: height),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let mask = CIImage(color: .white).cropped(to: source.extent)
    let context = IOSPortraitRetouchContext(effectiveMask: mask)
    let matureDefault = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV4(textureSmoothing: 50))
    )
    let output = try rgbaBytes(
      matureDefault.applying(to: source, extent: source.extent, portraitContext: context)
    )
    let baseline = try rgbaBytes(source)

    let baselineMicrotexture = meanHorizontalLumaDifference(
      baseline,
      width: width,
      xRange: 4..<(width / 2 - 4)
    )
    let outputMicrotexture = meanHorizontalLumaDifference(
      output,
      width: width,
      xRange: 4..<(width / 2 - 4)
    )
    XCTAssertLessThanOrEqual(
      outputMicrotexture,
      baselineMicrotexture * 0.94,
      "the open-source 0.5 beauty default must visibly reduce fine skin variation"
    )

    let baselineEdge = meanVerticalEdgeContrast(baseline, width: width, edgeX: width / 2)
    let outputEdge = meanVerticalEdgeContrast(output, width: width, edgeX: width / 2)
    XCTAssertGreaterThanOrEqual(
      outputEdge,
      baselineEdge * 0.82,
      "smoothing must retain the stable face boundary instead of blurring through it"
    )
  }

  func testIndependentSkinToneLightingIsMaskedAndRaisesDarkSkinWithoutClipping() throws {
    let extent = CGRect(x: 0, y: 0, width: 64, height: 32)
    let source = CIImage(color: CIColor(red: 0.34, green: 0.24, blue: 0.20))
      .cropped(to: extent)
    let mask = CIImage(color: .white)
      .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
      .composited(over: CIImage(color: .black).cropped(to: extent))
    let output = IOSPortraitRetoucher.applyingSkinToneLighting(
      to: source,
      strength: 0.6,
      mask: mask,
      extent: extent
    )
    let inputBytes = try rgbaBytes(source)
    let outputBytes = try rgbaBytes(output)

    XCTAssertGreaterThan(outputBytes[(16 * 64 + 16) * 4], inputBytes[(16 * 64 + 16) * 4])
    XCTAssertLessThan(outputBytes[(16 * 64 + 16) * 4], 250)
    for y in 0..<32 {
      for x in 32..<64 {
        let offset = (y * 64 + x) * 4
        XCTAssertEqual(
          Array(outputBytes[offset..<(offset + 4)]),
          Array(inputBytes[offset..<(offset + 4)])
        )
      }
    }
  }

  func testSkinToneLightingUsesComplexionLevelsWithoutLiftingTheBlackPoint() throws {
    let pixels: [UInt8] = [
      5, 5, 5, 255,
      64, 52, 44, 255,
      220, 205, 196, 255,
    ]
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: pixels.count,
      size: CGSize(width: 3, height: 1),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let output = IOSPortraitRetoucher.applyingSkinToneLighting(
      to: source,
      strength: 0.5,
      mask: CIImage(color: .white).cropped(to: source.extent),
      extent: source.extent
    )
    let outputBytes = try rgbaBytes(output)

    XCTAssertLessThanOrEqual(
      outputBytes[0],
      8,
      "complexion normalization must keep the calibrated near-black anchor dark"
    )
    XCTAssertGreaterThan(
      outputBytes[4],
      pixels[4],
      "the mature 0.5 complexion default must still lift a dim face midtone"
    )
    XCTAssertLessThanOrEqual(
      outputBytes[8],
      235,
      "face lighting must retain highlight headroom"
    )
  }

  func testFaceSlimInverseMappingIsLocalProtectedAndMonotonic() {
    let geometry = IOSFaceSlimGeometry(
      centerX: 50,
      halfWidth: 30,
      lowerY: 20,
      upperY: 60
    )

    XCTAssertEqual(
      geometry.sourcePoint(for: CGPoint(x: 50, y: 40), strength: 1),
      CGPoint(x: 50, y: 40),
      "the central feature corridor must remain fixed"
    )
    XCTAssertEqual(
      geometry.sourcePoint(for: CGPoint(x: 10, y: 40), strength: 1),
      CGPoint(x: 10, y: 40),
      "pixels outside the face ROI must remain fixed"
    )

    let target = CGPoint(x: 68, y: 40)
    let neutral = geometry.sourcePoint(for: target, strength: 0)
    let medium = geometry.sourcePoint(for: target, strength: 0.5)
    let strong = geometry.sourcePoint(for: target, strength: 1)
    XCTAssertEqual(neutral, target)
    XCTAssertGreaterThan(medium.x, neutral.x)
    XCTAssertGreaterThan(strong.x, medium.x)
    XCTAssertEqual(strong.y, target.y)

    let lowerCheek = CGPoint(x: 68, y: 32)
    let upperCheek = CGPoint(x: 68, y: 48)
    let lowerShift = geometry.sourcePoint(for: lowerCheek, strength: 1).x - lowerCheek.x
    let upperShift = geometry.sourcePoint(for: upperCheek, strength: 1).x - upperCheek.x
    XCTAssertGreaterThan(
      lowerShift,
      upperShift,
      "CainCamera's 0.12 jaw calibration must remain stronger than its 0.05 upper-face lift"
    )
  }

  func testProductionPipelineAppliesInjectedFaceSlimGeometryAndKeepsZeroExact() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 96)
    let source = stripedImage(extent: extent)
    let geometry = IOSFaceSlimGeometry(
      centerX: 48,
      halfWidth: 34,
      lowerY: 18,
      upperY: 66
    )
    let context = IOSPortraitRetouchContext(
      effectiveMask: nil,
      faceSlimGeometry: geometry,
      faceMask: CIImage(color: .white).cropped(to: extent)
    )
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV3()))
    let faceSlim = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV3(faceSlimStrength: 0.5))
    )

    let sourceBytes = try rgbaBytes(source)
    let zeroBytes = try rgbaBytes(
      neutral.applying(to: source, extent: extent, portraitContext: context)
    )
    let faceSlimBytes = try rgbaBytes(
      faceSlim.applying(to: source, extent: extent, portraitContext: context)
    )

    XCTAssertEqual(zeroBytes, sourceBytes, "strength zero must remain exact")
    XCTAssertGreaterThan(
      meanAbsoluteDifference(sourceBytes, faceSlimBytes),
      0.25,
      "a safe injected face geometry must visibly affect the production pipeline"
    )
  }

  func testPerFaceSlimChangesOnlyTargetsWithNonzeroStrength() throws {
    let extent = CGRect(x: 0, y: 0, width: 160, height: 80)
    let source = stripedImage(extent: extent)
    let leftRect = CGRect(x: 8, y: 0, width: 64, height: 80)
    let rightRect = CGRect(x: 88, y: 0, width: 64, height: 80)
    let black = CIImage(color: .black).cropped(to: extent)
    func mask(_ rect: CGRect) -> CIImage {
      CIImage(color: .white).cropped(to: rect).composited(over: black)
    }
    let context = IOSPortraitRetouchContext(
      effectiveMask: nil,
      faceSlimTargets: [
        IOSFaceSlimTargetContext(
          geometry: IOSFaceSlimGeometry(
            centerX: 40,
            halfWidth: 30,
            lowerY: 4,
            upperY: 76
          ),
          mask: mask(leftRect)
        ),
        IOSFaceSlimTargetContext(
          geometry: IOSFaceSlimGeometry(
            centerX: 120,
            halfWidth: 30,
            lowerY: 4,
            upperY: 76
          ),
          mask: mask(rightRect)
        ),
      ]
    )

    let output = IOSPortraitRetoucher.applyingFaceSlim(
      to: source,
      strengths: [0.5, 0],
      extent: extent,
      context: context
    )

    XCTAssertGreaterThan(
      meanAbsoluteDifference(
        try rgbaBytes(source.cropped(to: leftRect)),
        try rgbaBytes(output.cropped(to: leftRect))
      ),
      0.1
    )
    XCTAssertEqual(
      try rgbaBytes(source.cropped(to: rightRect)),
      try rgbaBytes(output.cropped(to: rightRect))
    )
  }

  func testFaceSlimMaskKeepsBackgroundPixelsExact() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 96)
    let source = stripedImage(extent: extent)
    let protectedBackground = CGRect(x: 48, y: 0, width: 48, height: 96)
    let faceMask = CIImage(color: .white)
      .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 96))
      .composited(over: CIImage(color: .black).cropped(to: extent))
      .cropped(to: extent)
    let context = IOSPortraitRetouchContext(
      effectiveMask: nil,
      faceSlimGeometry: IOSFaceSlimGeometry(
        centerX: 48,
        halfWidth: 40,
        lowerY: 10,
        upperY: 84
      ),
      faceMask: faceMask
    )
    let pipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV3(faceSlimStrength: 0.5))
    )
    let output = pipeline.applying(
      to: source,
      extent: extent,
      portraitContext: context
    )

    XCTAssertEqual(
      try rgbaBytes(source.cropped(to: protectedBackground)),
      try rgbaBytes(output.cropped(to: protectedBackground)),
      "pixels outside the face mask must remain exact"
    )
    XCTAssertGreaterThan(
      meanAbsoluteDifference(
        try rgbaBytes(source.cropped(to: CGRect(x: 0, y: 0, width: 48, height: 96))),
        try rgbaBytes(output.cropped(to: CGRect(x: 0, y: 0, width: 48, height: 96)))
      ),
      0.1,
      "the permitted face region must still deform"
    )
  }

  func testLocalSlimWarpStaysInItsBottomOriginVerticalRegion() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 96)
    let source = stripedImage(extent: extent)
    let intendedRegion = CGRect(x: 0, y: 4, width: 96, height: 32)
    let mirroredRegion = CGRect(x: 0, y: 60, width: 96, height: 32)
    let facePipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV3(faceSlimStrength: 1))
    )
    let bodyPipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV3(bodySlimStrength: 1))
    )
    let faceContext = IOSPortraitRetouchContext(
      effectiveMask: nil,
      faceSlimGeometry: IOSFaceSlimGeometry(
        centerX: 48,
        halfWidth: 38,
        lowerY: 4,
        upperY: 36
      ),
      faceMask: CIImage(color: .white).cropped(to: extent)
    )
    let bodyContext = IOSPortraitRetouchContext(
      effectiveMask: nil,
      bodySlimGeometry: IOSBodySlimGeometry(
        centerX: 48,
        halfWidth: 38,
        lowerY: 4,
        upperY: 36
      ),
      personMask: CIImage(color: .white).cropped(to: extent)
    )

    for (name, output) in [
      (
        "face",
        facePipeline.applying(
          to: source,
          extent: extent,
          portraitContext: faceContext
        )
      ),
      (
        "body",
        bodyPipeline.applying(
          to: source,
          extent: extent,
          portraitContext: bodyContext
        )
      ),
    ] {
      XCTAssertGreaterThan(
        meanAbsoluteDifference(
          try rgbaBytes(source.cropped(to: intendedRegion)),
          try rgbaBytes(output.cropped(to: intendedRegion))
        ),
        0.1,
        "the \(name) warp must affect its declared bottom-origin ROI"
      )
      XCTAssertEqual(
        try rgbaBytes(source.cropped(to: mirroredRegion)),
        try rgbaBytes(output.cropped(to: mirroredRegion)),
        "the \(name) warp must not move the vertically mirrored ROI"
      )
    }
  }

  func testFaceAndBodySlimWarpNarrowsRenderedSubjectContours() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 96)
    let subject = CIImage(color: .white)
      .cropped(to: CGRect(x: 24, y: 8, width: 48, height: 80))
      .composited(over: CIImage(color: .black).cropped(to: extent))
      .cropped(to: extent)
    let mask = CIImage(color: .white).cropped(to: extent)
    let geometry = IOSFaceSlimGeometry(
      centerX: 48,
      halfWidth: 38,
      lowerY: 8,
      upperY: 88
    )
    let bodyGeometry = IOSBodySlimGeometry(
      centerX: 48,
      halfWidth: 38,
      lowerY: 8,
      upperY: 88
    )
    let facePipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV3(faceSlimStrength: 0.5))
    )
    let bodyPipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV3(bodySlimStrength: 0.35))
    )
    let sourceBounds = brightPixelBounds(try rgbaBytes(subject), width: 96, row: 48)
    let faceBounds = brightPixelBounds(
      try rgbaBytes(
        facePipeline.applying(
          to: subject,
          extent: extent,
          portraitContext: IOSPortraitRetouchContext(
            effectiveMask: nil,
            faceSlimGeometry: geometry,
            faceMask: mask
          )
        )
      ),
      width: 96,
      row: 48
    )
    let bodyBounds = brightPixelBounds(
      try rgbaBytes(
        bodyPipeline.applying(
          to: subject,
          extent: extent,
          portraitContext: IOSPortraitRetouchContext(
            effectiveMask: nil,
            bodySlimGeometry: bodyGeometry,
            personMask: mask
          )
        )
      ),
      width: 96,
      row: 48
    )

    XCTAssertLessThan(
      Double(faceBounds.width),
      Double(sourceBounds.width) * 0.97,
      "face slim must narrow the rendered contour: \(sourceBounds) -> \(faceBounds)"
    )
    XCTAssertLessThan(
      Double(bodyBounds.width),
      Double(sourceBounds.width) * 0.98,
      "body slim must narrow the rendered contour: \(sourceBounds) -> \(bodyBounds)"
    )
  }

  func testBodySlimInverseMappingIsLocalProtectedAndMonotonic() {
    let geometry = IOSBodySlimGeometry(
      centerX: 50,
      halfWidth: 28,
      lowerY: 18,
      upperY: 72
    )

    XCTAssertEqual(
      geometry.sourcePoint(for: CGPoint(x: 50, y: 45), strength: 1),
      CGPoint(x: 50, y: 45),
      "the body center line must remain fixed"
    )
    XCTAssertEqual(
      geometry.sourcePoint(for: CGPoint(x: 10, y: 45), strength: 1),
      CGPoint(x: 10, y: 45),
      "pixels outside the torso ROI must remain fixed"
    )

    let target = CGPoint(x: 67, y: 45)
    let neutral = geometry.sourcePoint(for: target, strength: 0)
    let medium = geometry.sourcePoint(for: target, strength: 0.175)
    let strong = geometry.sourcePoint(for: target, strength: 0.35)
    XCTAssertEqual(neutral, target)
    XCTAssertGreaterThan(medium.x, neutral.x)
    XCTAssertGreaterThan(strong.x, medium.x)
    XCTAssertEqual(strong.y, target.y)
  }

  func testBodySafetyAllowsUpToThreeConfidentPeopleWithSegmentation() {
    XCTAssertTrue(
      IOSBodySlimSafetyPolicy.isEligible(
        personCount: 1,
        leftShoulderConfidence: 0.9,
        rightShoulderConfidence: 0.9,
        leftHipConfidence: 0.9,
        rightHipConfidence: 0.9,
        torsoHeightRatio: 0.3,
        segmentationAvailable: true
      )
    )
    XCTAssertTrue(
      IOSBodySlimSafetyPolicy.isEligible(
        personCount: 2,
        leftShoulderConfidence: 0.9,
        rightShoulderConfidence: 0.9,
        leftHipConfidence: 0.9,
        rightHipConfidence: 0.9,
        torsoHeightRatio: 0.3,
        segmentationAvailable: true
      )
    )
    XCTAssertFalse(
      IOSBodySlimSafetyPolicy.isEligible(
        personCount: 4,
        leftShoulderConfidence: 0.9,
        rightShoulderConfidence: 0.9,
        leftHipConfidence: 0.9,
        rightHipConfidence: 0.9,
        torsoHeightRatio: 0.3,
        segmentationAvailable: true
      )
    )
    XCTAssertFalse(
      IOSBodySlimSafetyPolicy.isEligible(
        personCount: 1,
        leftShoulderConfidence: 0.9,
        rightShoulderConfidence: 0.9,
        leftHipConfidence: 0.9,
        rightHipConfidence: 0.2,
        torsoHeightRatio: 0.3,
        segmentationAvailable: true
      )
    )
    XCTAssertFalse(
      IOSBodySlimSafetyPolicy.isEligible(
        personCount: 1,
        leftShoulderConfidence: 0.9,
        rightShoulderConfidence: 0.9,
        leftHipConfidence: 0.9,
        rightHipConfidence: 0.9,
        torsoHeightRatio: 0.3,
        segmentationAvailable: false
      )
    )
    XCTAssertTrue(
      IOSBodySlimSafetyPolicy.isEligible(
        personCount: 1,
        leftShoulderConfidence: 0.74,
        rightShoulderConfidence: 0.51,
        leftHipConfidence: 0.57,
        rightHipConfidence: 0.44,
        torsoHeightRatio: 0.21,
        segmentationAvailable: true
      ),
      "moderate pose confidence remains bounded by segmentation and background gates"
    )
  }

  func testReshapeBackgroundSafetyRejectsDenseHighContrastLines() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 112)
    let subjectMask = CIImage(color: .white)
      .cropped(to: CGRect(x: 32, y: 0, width: 32, height: 112))
      .composited(over: CIImage(color: .black).cropped(to: extent))
      .cropped(to: extent)
    let quiet = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
      .cropped(to: extent)
    let risky = stripedImage(extent: extent)

    XCTAssertTrue(
      IOSReshapeBackgroundSafetyPolicy.isEligible(
        source: quiet,
        subjectMask: subjectMask,
        influenceRect: extent
      )
    )
    XCTAssertFalse(
      IOSReshapeBackgroundSafetyPolicy.isEligible(
        source: risky,
        subjectMask: subjectMask,
        influenceRect: extent
      )
    )
    XCTAssertGreaterThan(
      try XCTUnwrap(
        IOSReshapeBackgroundSafetyPolicy.outsideEdgeMean(
          source: risky,
          subjectMask: subjectMask,
          influenceRect: extent
        )
      ),
      0.18
    )
  }

  func testProductionPipelineAppliesInjectedBodySlimGeometryAndKeepsZeroExact() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 112)
    let source = stripedImage(extent: extent)
    let geometry = IOSBodySlimGeometry(
      centerX: 48,
      halfWidth: 34,
      lowerY: 18,
      upperY: 88
    )
    let context = IOSPortraitRetouchContext(
      effectiveMask: nil,
      bodySlimGeometry: geometry,
      personMask: CIImage(color: .white).cropped(to: extent)
    )
    let neutral = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV3()))
    let bodySlim = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV3(bodySlimStrength: 0.25))
    )

    let sourceBytes = try rgbaBytes(source)
    let zeroBytes = try rgbaBytes(
      neutral.applying(to: source, extent: extent, portraitContext: context)
    )
    let bodySlimBytes = try rgbaBytes(
      bodySlim.applying(to: source, extent: extent, portraitContext: context)
    )

    XCTAssertEqual(zeroBytes, sourceBytes, "strength zero must remain exact")
    XCTAssertGreaterThan(
      meanAbsoluteDifference(sourceBytes, bodySlimBytes),
      0.25,
      "safe torso geometry and a person mask must affect the production pipeline"
    )
  }

  func testFaceAndBodySlimFailClosedWhenPortraitContextIsUnavailable() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 112)
    let source = stripedImage(extent: extent)
    let pipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV3(
        faceSlimStrength: 0.5,
        bodySlimStrength: 0.35
      ))
    )

    XCTAssertEqual(
      try rgbaBytes(
        pipeline.applying(
          to: source,
          extent: extent,
          portraitContext: .unavailable
        )
      ),
      try rgbaBytes(source),
      "unavailable Vision geometry and masks must disable all reshaping"
    )
  }

  func testBodySlimPersonMaskKeepsBackgroundPixelsExact() throws {
    let extent = CGRect(x: 0, y: 0, width: 96, height: 112)
    let source = stripedImage(extent: extent)
    let protectedBackground = CGRect(x: 48, y: 0, width: 48, height: 112)
    let personMask = CIImage(color: .white)
      .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 112))
      .composited(over: CIImage(color: .black).cropped(to: extent))
      .cropped(to: extent)
    let context = IOSPortraitRetouchContext(
      effectiveMask: nil,
      bodySlimGeometry: IOSBodySlimGeometry(
        centerX: 48,
        halfWidth: 40,
        lowerY: 10,
        upperY: 102
      ),
      personMask: personMask
    )
    let pipeline = try XCTUnwrap(
      IOSImagePipeline(arguments: pipelineV3(bodySlimStrength: 0.35))
    )
    let output = pipeline.applying(
      to: source,
      extent: extent,
      portraitContext: context
    )

    XCTAssertEqual(
      try rgbaBytes(source.cropped(to: protectedBackground)),
      try rgbaBytes(output.cropped(to: protectedBackground)),
      "pixels outside the person mask must remain exact"
    )
    XCTAssertGreaterThan(
      meanAbsoluteDifference(
        try rgbaBytes(source.cropped(to: CGRect(x: 0, y: 0, width: 48, height: 112))),
        try rgbaBytes(output.cropped(to: CGRect(x: 0, y: 0, width: 48, height: 112)))
      ),
      0.1,
      "the permitted torso region must still deform"
    )
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
    XCTAssertEqual(result["faceSlim"] as? String, "unavailable")
    XCTAssertEqual(result["faceSlimTargetCount"] as? Int, 0)
    XCTAssertEqual(result["body"] as? String, "unavailable")
    XCTAssertEqual(result["bodyTargetCount"] as? Int, 0)
    XCTAssertTrue(
      ["noFace", "capabilityUnavailable"].contains(
        try XCTUnwrap(result["portraitReason"] as? String)
      )
    )
  }

  func testLocalAnalysisExposesPortraitCapabilityForARealFrontFacingPhoto() throws {
    let fixture = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/portrait-front-cc-by-sa.jpg")
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))

    let result = try AppDelegate.analyzePhoto(path: fixture.path)

    XCTAssertEqual(
      result["capabilityVersion"] as? String,
      "ios-core-image-vision-v14-target-regions"
    )
    XCTAssertEqual(result["portrait"] as? String, "applicable")
    XCTAssertEqual(result["portraitReason"] as? String, "none")
    XCTAssertEqual(result["faceSlim"] as? String, "applicable")
    XCTAssertEqual(result["faceSlimReason"] as? String, "none")
    XCTAssertEqual(result["faceSlimTargetCount"] as? Int, 1)
    let faceRegions = try XCTUnwrap(
      result["faceTargetRegions"] as? [[String: Double]]
    )
    XCTAssertEqual(faceRegions.count, 1)
    XCTAssertGreaterThan(try XCTUnwrap(faceRegions.first?["right"]), 0)
    XCTAssertGreaterThan(try XCTUnwrap(faceRegions.first?["bottom"]), 0)
    XCTAssertEqual(result["scene"] as? String, "people")
  }

  func testLocalAnalysisOrdersAndExposesTwoIndependentFaceSlimTargets() throws {
    let fixture = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/portrait-front-cc-by-sa.jpg")
    let portrait = try XCTUnwrap(UIImage(contentsOfFile: fixture.path))
    let size = CGSize(width: portrait.size.width * 2, height: portrait.size.height)
    let image = UIGraphicsImageRenderer(size: size).image { _ in
      portrait.draw(in: CGRect(origin: .zero, size: portrait.size))
      portrait.draw(
        in: CGRect(
          x: portrait.size.width,
          y: 0,
          width: portrait.size.width,
          height: portrait.size.height
        )
      )
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-multiface-analysis-\(UUID().uuidString).jpg")
    try XCTUnwrap(image.jpegData(compressionQuality: 0.96)).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let result = try AppDelegate.analyzePhoto(path: url.path)
    XCTAssertEqual(result["portrait"] as? String, "applicable")
    XCTAssertEqual(result["faceSlim"] as? String, "applicable")
    XCTAssertEqual(result["faceSlimTargetCount"] as? Int, 2)
    let faceRegions = try XCTUnwrap(
      result["faceTargetRegions"] as? [[String: Double]]
    )
    XCTAssertEqual(faceRegions.count, 2)
    XCTAssertLessThan(
      try XCTUnwrap(faceRegions[0]["left"]),
      try XCTUnwrap(faceRegions[1]["left"])
    )

    let source = try XCTUnwrap(CIImage(contentsOf: url))
    let context = IOSPortraitRetoucher.prepare(source: source, extent: source.extent)
    XCTAssertEqual(context.faceSlimTargets.count, 2)
    XCTAssertLessThan(
      context.faceSlimTargets[0].geometry.centerX,
      context.faceSlimTargets[1].geometry.centerX
    )
  }

#if targetEnvironment(simulator)
  func testLocalAnalysisExposesBodyCapabilityForARealStandingPhoto() throws {
    let fixture = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/body-standing-cc-by-sa.jpg")
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))

    let result = try AppDelegate.analyzePhoto(path: fixture.path)

    XCTAssertEqual(
      result["capabilityVersion"] as? String,
      "ios-core-image-vision-v14-target-regions"
    )
    XCTAssertEqual(result["body"] as? String, "applicable")
    let bodyRegions = try XCTUnwrap(
      result["bodyTargetRegions"] as? [[String: Double]]
    )
    XCTAssertEqual(bodyRegions.count, result["bodyTargetCount"] as? Int)
    XCTAssertFalse(bodyRegions.isEmpty)
    XCTAssertEqual(result["scene"] as? String, "people")
  }

  func testSimulatorBodyFallbackRequiresConservativeFullBodyGeometry() throws {
    let extent = CGRect(x: 0, y: 0, width: 500, height: 752)
    let geometry = try XCTUnwrap(
      IOSPortraitRetoucher.simulatorBodyFallbackGeometry(
        faceBoundingBox: CGRect(x: 0.43, y: 0.72, width: 0.12, height: 0.09),
        proxyExtent: extent
      )
    )
    XCTAssertEqual(geometry.centerX, 245, accuracy: 0.001)
    XCTAssertGreaterThan(geometry.upperY, geometry.lowerY)
    XCTAssertGreaterThan(geometry.halfWidth, 0)
    XCTAssertNil(
      IOSPortraitRetoucher.simulatorBodyFallbackGeometry(
        faceBoundingBox: CGRect(x: 0.43, y: 0.35, width: 0.12, height: 0.09),
        proxyExtent: extent
      ),
      "a low face cannot infer a safe upright torso"
    )
    XCTAssertNil(
      IOSPortraitRetoucher.simulatorBodyFallbackGeometry(
        faceBoundingBox: CGRect(x: 0.43, y: 0.72, width: 0.12, height: 0.09),
        proxyExtent: CGRect(x: 0, y: 0, width: 752, height: 500)
      ),
      "landscape inputs cannot use the simulator-only torso fallback"
    )
  }
#endif

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

  func testNonGeometricPortraitCapabilityAllowsUpToThreeEligibleFaces() {
    XCTAssertEqual(
      IOSPortraitCapabilityPolicy.classify(
        IOSMultiFaceNonGeometricSafetyDecision(
          applicableFaceIndices: [0, 1],
          rejectedFaces: [:],
          sceneReason: .none
        )
      ),
      IOSPortraitCapabilityStatus(applicability: "applicable", reason: "none")
    )
    XCTAssertEqual(
      IOSPortraitCapabilityPolicy.classify(
        IOSMultiFaceNonGeometricSafetyDecision(
          applicableFaceIndices: [],
          rejectedFaces: [:],
          sceneReason: .tooManyFaces
        )
      ),
      IOSPortraitCapabilityStatus(applicability: "unsafe", reason: "multipleFaces")
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

  func testFileRendererProducesConfiguredResizedHeif() throws {
    let sourceURL = temporaryURL(extension: "jpg")
    let outputURL = temporaryURL(extension: "heic")
    defer { removeTemporaryFiles(sourceURL, outputURL) }
    try writeJpeg(to: sourceURL, width: 1_200, height: 800, colorSpace: sRGB)
    let pipeline = try XCTUnwrap(IOSImagePipeline(arguments: pipelineV7()))
    let options = try XCTUnwrap(IOSPhotoExportOptions(arguments: [
      "format": "heif", "size": "longEdge", "longEdgePixels": 640,
      "quality": "standard", "colorSpace": "srgb",
    ]))

    let artifact = try IOSPhotoFileRenderer(context: imageContext).render(
      sourcePath: sourceURL.path,
      pipeline: pipeline,
      destinationURL: outputURL,
      options: options
    )
    let outputSource = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
    let outputType = try XCTUnwrap(CGImageSourceGetType(outputSource))

    XCTAssertEqual(max(artifact.width, artifact.height), 640)
    XCTAssertEqual(outputType as String, UTType.heic.identifier)
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

  func testProductionPortraitCandidateDoesNotTurnCompactTextureIntoDarkSpeckles() throws {
    let width = 96
    let height = 96
    let skin: [UInt8] = [174, 122, 96, 255]
    let compactTexture: [UInt8] = [112, 78, 62, 255]
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in 0..<(width * height) {
      pixels.replaceSubrange(index * 4..<(index + 1) * 4, with: skin)
    }
    var centers: [(x: Int, y: Int)] = []
    for y in stride(from: 8, to: height - 8, by: 8) {
      for x in stride(from: 8, to: width - 8, by: 8) {
        centers.append((x, y))
        let offset = (y * width + x) * 4
        pixels.replaceSubrange(offset..<(offset + 4), with: compactTexture)
      }
    }
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: width * 4,
      size: CGSize(width: width, height: height),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let mask = CIImage(color: .white).cropped(to: source.extent)
    let defaultImage = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0.35,
      extent: source.extent
    )
    let highImage = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0.55,
      extent: source.extent
    )

    let sourceContrast = compactSpotContrast(
      try rgbaBytes(source),
      width: width,
      centers: centers
    )
    let defaultContrast = compactSpotContrast(
      try rgbaBytes(defaultImage),
      width: width,
      centers: centers
    )
    let highContrast = compactSpotContrast(
      try rgbaBytes(highImage),
      width: width,
      centers: centers
    )

    XCTAssertLessThan(
      defaultContrast,
      sourceContrast,
      "Default retouch must soften compact skin texture instead of isolating it as dark dots"
    )
    XCTAssertLessThanOrEqual(
      highContrast,
      defaultContrast,
      "Higher safe strength must not make compact texture more speckled"
    )
  }

  func testProductionPortraitCandidateRelightsFaceShadowsWithoutLiftingHighlightsOrBackground()
    throws
  {
    let extent = CGRect(x: 0, y: 0, width: 120, height: 80)
    let background = CIImage(
      color: CIColor(red: 0.16, green: 0.18, blue: 0.20, alpha: 1)
    ).cropped(to: extent)
    let shadowSkin = CIImage(
      color: CIColor(red: 0.31, green: 0.20, blue: 0.16, alpha: 1)
    ).cropped(to: CGRect(x: 20, y: 10, width: 40, height: 60))
    let highlightSkin = CIImage(
      color: CIColor(red: 0.84, green: 0.68, blue: 0.58, alpha: 1)
    ).cropped(to: CGRect(x: 60, y: 10, width: 40, height: 60))
    let source = highlightSkin
      .composited(over: shadowSkin)
      .composited(over: background)
      .cropped(to: extent)
    let mask = CIImage(color: .white)
      .cropped(to: CGRect(x: 20, y: 10, width: 80, height: 60))
      .composited(over: CIImage(color: .black).cropped(to: extent))
      .cropped(to: extent)

    let output = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0.35,
      extent: extent
    )
    let sourceBytes = try rgbaBytes(source)
    let outputBytes = try rgbaBytes(output)
    let shadowLift = meanLuminance(outputBytes, width: 120, rect: CGRect(x: 30, y: 20, width: 20, height: 40))
      - meanLuminance(sourceBytes, width: 120, rect: CGRect(x: 30, y: 20, width: 20, height: 40))
    let highlightLift = meanLuminance(outputBytes, width: 120, rect: CGRect(x: 70, y: 20, width: 20, height: 40))
      - meanLuminance(sourceBytes, width: 120, rect: CGRect(x: 70, y: 20, width: 20, height: 40))
    let backgroundDifference = meanRegionAbsoluteDifference(
      sourceBytes,
      outputBytes,
      width: 120,
      rect: CGRect(x: 2, y: 2, width: 12, height: 72)
    )

    XCTAssertGreaterThanOrEqual(
      shadowLift,
      5,
      "Default natural retouch must visibly lift face shadows"
    )
    XCTAssertLessThanOrEqual(
      abs(highlightLift),
      shadowLift * 0.4,
      "Existing facial highlights must be protected from the shadow lift"
    )
    XCTAssertLessThanOrEqual(
      backgroundDifference,
      1,
      "Face relighting must not brighten the background"
    )
  }

  func testProductionPortraitCandidateEvensLowFrequencySkinColorWithoutChangingOverallTone()
    throws
  {
    let extent = CGRect(x: 0, y: 0, width: 120, height: 80)
    let warmPatch = CIImage(
      color: CIColor(red: 0.72, green: 0.38, blue: 0.32, alpha: 1)
    ).cropped(to: CGRect(x: 20, y: 10, width: 40, height: 60))
    let yellowPatch = CIImage(
      color: CIColor(red: 0.65, green: 0.50, blue: 0.27, alpha: 1)
    ).cropped(to: CGRect(x: 60, y: 10, width: 40, height: 60))
    let background = CIImage(
      color: CIColor(red: 0.18, green: 0.20, blue: 0.22, alpha: 1)
    ).cropped(to: extent)
    let source = yellowPatch
      .composited(over: warmPatch)
      .composited(over: background)
      .cropped(to: extent)
    let mask = CIImage(color: .white)
      .cropped(to: CGRect(x: 20, y: 10, width: 80, height: 60))
      .composited(over: CIImage(color: .black).cropped(to: extent))
      .cropped(to: extent)

    let output = IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: 0.35,
      extent: extent
    )
    let sourceBytes = try rgbaBytes(source)
    let outputBytes = try rgbaBytes(output)
    let leftRect = CGRect(x: 46, y: 20, width: 12, height: 40)
    let rightRect = CGRect(x: 62, y: 20, width: 12, height: 40)
    let sourceLeft = meanChroma(sourceBytes, width: 120, rect: leftRect)
    let sourceRight = meanChroma(sourceBytes, width: 120, rect: rightRect)
    let outputLeft = meanChroma(outputBytes, width: 120, rect: leftRect)
    let outputRight = meanChroma(outputBytes, width: 120, rect: rightRect)
    let sourceGap = chromaDistance(sourceLeft, sourceRight)
    let outputGap = chromaDistance(outputLeft, outputRight)
    let sourceAverage = (
      (sourceLeft.redMinusGreen + sourceRight.redMinusGreen) / 2,
      (sourceLeft.blueMinusGreen + sourceRight.blueMinusGreen) / 2
    )
    let outputAverage = (
      (outputLeft.redMinusGreen + outputRight.redMinusGreen) / 2,
      (outputLeft.blueMinusGreen + outputRight.blueMinusGreen) / 2
    )

    XCTAssertLessThanOrEqual(
      outputGap,
      sourceGap * 0.85,
      "Default natural retouch must reduce local red/yellow skin-color patches"
    )
    XCTAssertLessThanOrEqual(
      hypot(outputAverage.0 - sourceAverage.0, outputAverage.1 - sourceAverage.1),
      8,
      "Skin-color equalization must preserve the person's overall tone"
    )
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
      sourceEdge * 0.82,
      "Natural retouch must retain a clearly dominant hair, beard, eye, lip, or permanent-feature edge without restoring compact skin speckles; "
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

  func testPortraitPixelSafetyDoesNotPenalizePortraitAspectRatio() {
    let readableFace = CGRect(
      x: 0.47,
      y: 0.73,
      width: 61.0 / 461.0,
      height: 61.0 / 768.0
    )

    XCTAssertTrue(
      IOSPortraitSafetyPolicy.evaluate(
        faceCount: 1,
        confidence: 1,
        boundingBox: readableFace,
        hasLandmarks: true,
        imageSize: CGSize(width: 461, height: 768)
      ).applicable
    )
    XCTAssertEqual(
      IOSPortraitSafetyPolicy.evaluate(
        faceCount: 1,
        confidence: 1,
        boundingBox: readableFace,
        hasLandmarks: true,
        imageSize: CGSize(width: 300, height: 500)
      ).reason,
      .faceTooSmall
    )
  }

  func testMultiFaceNonGeometricPolicyKeepsEligibleFacesIndependently() {
    let result = IOSMultiFaceNonGeometricSafetyPolicy.evaluate(
      faces: [
        IOSNonGeometricFaceDescriptor(
          confidence: 0.96,
          boundingBox: CGRect(x: 0.08, y: 0.25, width: 0.28, height: 0.42),
          hasLandmarks: true
        ),
        IOSNonGeometricFaceDescriptor(
          confidence: 0.31,
          boundingBox: CGRect(x: 0.39, y: 0.28, width: 0.24, height: 0.38),
          hasLandmarks: true
        ),
        IOSNonGeometricFaceDescriptor(
          confidence: 0.91,
          boundingBox: CGRect(x: 0.68, y: 0.32, width: 0.18, height: 0.29),
          hasLandmarks: true
        ),
      ],
      imageSize: CGSize(width: 1_200, height: 800)
    )

    XCTAssertEqual(result.applicableFaceIndices, [0, 2])
    XCTAssertEqual(result.rejectedFaces, [1: .lowConfidence])
    XCTAssertEqual(result.sceneReason, .none)
  }

  func testMultiFaceNonGeometricPolicyFailsClosedForUnsupportedSceneCounts() {
    let noFaces = IOSMultiFaceNonGeometricSafetyPolicy.evaluate(
      faces: [],
      imageSize: CGSize(width: 1_200, height: 800)
    )
    XCTAssertEqual(noFaces.sceneReason, .noFace)
    XCTAssertTrue(noFaces.applicableFaceIndices.isEmpty)

    let face = IOSNonGeometricFaceDescriptor(
      confidence: 0.99,
      boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3),
      hasLandmarks: true
    )
    let crowd = IOSMultiFaceNonGeometricSafetyPolicy.evaluate(
      faces: [face, face, face, face],
      imageSize: CGSize(width: 1_200, height: 800)
    )
    XCTAssertEqual(crowd.sceneReason, .tooManyFaces)
    XCTAssertTrue(crowd.applicableFaceIndices.isEmpty)
    XCTAssertTrue(crowd.rejectedFaces.isEmpty)
  }

  func testConservativeBlemishCandidateReducesInflamedSpotButPreservesBrownDetail() throws {
    XCTAssertTrue(IOSBlemishReductionCandidate.isAvailable)
    let width = 40
    let height = 20
    let skin: [UInt8] = [190, 145, 125, 255]
    let inflamed: [UInt8] = [188, 82, 72, 255]
    let brownDetail: [UInt8] = [78, 52, 42, 255]
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in 0..<(width * height) {
      pixels.replaceSubrange(index * 4..<(index + 1) * 4, with: skin)
    }
    for y in 8...10 {
      for x in 9...11 {
        pixels.replaceSubrange((y * width + x) * 4..<(y * width + x + 1) * 4, with: inflamed)
      }
      for x in 28...30 {
        pixels.replaceSubrange((y * width + x) * 4..<(y * width + x + 1) * 4, with: brownDetail)
      }
    }
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: width * 4,
      size: CGSize(width: width, height: height),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let mask = CIImage(color: .white).cropped(to: source.extent)
    let output = IOSBlemishReductionCandidate.applying(
      to: source,
      strength: 0.6,
      effectiveFaceMask: mask,
      extent: source.extent
    )
    let outputPixels = try rgbaBytes(output)
    let inflamedOffset = (9 * width + 10) * 4
    let detailOffset = (9 * width + 29) * 4
    let originalInflamedDistance = zip(inflamed.prefix(3), skin.prefix(3))
      .reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
    let outputInflamedDistance = (0..<3).reduce(0) {
      $0 + abs(Int(outputPixels[inflamedOffset + $1]) - Int(skin[$1]))
    }
    let detailChange = (0..<3).reduce(0) {
      $0 + abs(Int(outputPixels[detailOffset + $1]) - Int(brownDetail[$1]))
    }

    XCTAssertLessThan(outputInflamedDistance, originalInflamedDistance * 4 / 5)
    XCTAssertLessThanOrEqual(detailChange, 3)
  }

  func testConservativeBlemishCandidateDoesNotChangePixelsOutsideFaceMask() throws {
    let width = 40
    let height = 20
    let pixels = (0..<(width * height)).flatMap { index -> [UInt8] in
      let x = index % width
      return x < width / 2 ? [188, 82, 72, 255] : [190, 145, 125, 255]
    }
    let source = CIImage(
      bitmapData: Data(pixels),
      bytesPerRow: width * 4,
      size: CGSize(width: width, height: height),
      format: .RGBA8,
      colorSpace: sRGB
    )
    let mask = CIImage(color: .white)
      .cropped(to: CGRect(x: 0, y: 0, width: width / 2, height: height))
      .composited(over: CIImage(color: .black).cropped(to: source.extent))
      .cropped(to: source.extent)
    let output = IOSBlemishReductionCandidate.applying(
      to: source,
      strength: 1,
      effectiveFaceMask: mask,
      extent: source.extent
    )
    let outputPixels = try rgbaBytes(output)

    for y in 0..<height {
      for x in (width / 2)..<width {
        let offset = (y * width + x) * 4
        XCTAssertEqual(Array(outputPixels[offset..<(offset + 4)]), Array(pixels[offset..<(offset + 4)]))
      }
    }
  }

  private func pipelineV2(
    schemaVersion: NSNumber = 2,
    exposureEV: Double = 0,
    highlights: Double = 0,
    shadows: Double = 0,
    contrast: Double = 0,
    warmth: Double = 0,
    tint: Double = 0,
    saturation: Double = 0,
    clarity: Double = 0,
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
        "tint": tint,
        "saturation": saturation,
        "clarity": clarity,
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

  private func pipelineV3(
    portraitStrength: Double = 0,
    faceSlimStrength: Double = 0,
    bodySlimStrength: Double = 0
  ) -> [String: Any] {
    var pipeline = pipelineV2(schemaVersion: 3, portraitStrength: portraitStrength)
    pipeline["reshape"] = [
      "recipeVersion": 1,
      "faceSlimStrength": faceSlimStrength,
      "bodySlimStrength": bodySlimStrength,
    ]
    return pipeline
  }

  private func pipelineV4(
    recipeVersion: NSNumber = 2,
    textureSmoothing: NSNumber = 0,
    skinToneLighting: NSNumber = 0,
    blemishReduction: NSNumber = 0,
    faceSlimming: NSNumber = 0,
    torsoSlimming: NSNumber = 0
  ) -> [String: Any] {
    var pipeline = pipelineV2()
    pipeline["schemaVersion"] = 4
    pipeline.removeValue(forKey: "portrait")
    pipeline["portraitRecipeV2"] = [
      "recipeVersion": recipeVersion,
      "analysisVersion": "vision-multiface-v1",
      "effectVersion": "portrait-core-contract-v2",
      "textureSmoothing": textureSmoothing,
      "skinToneLighting": skinToneLighting,
      "blemishReduction": blemishReduction,
      "faceSlimming": faceSlimming,
      "torsoSlimming": torsoSlimming,
    ]
    return pipeline
  }

  private func pipelineV5(
    selectedTargetIndex: NSNumber = 0,
    targetStrengths: [Any] = [0.0]
  ) -> [String: Any] {
    var pipeline = pipelineV4()
    pipeline["schemaVersion"] = 5
    pipeline["faceSlimRecipeV1"] = [
      "recipeVersion": 1,
      "selectedTargetIndex": selectedTargetIndex,
      "targetStrengths": targetStrengths,
    ]
    return pipeline
  }

  private func pipelineV6(
    noiseReduction: NSNumber = 0,
    lowLightRecovery: NSNumber = 0,
    hazeRemoval: NSNumber = 0,
    detailSharpening: NSNumber = 0
  ) -> [String: Any] {
    var pipeline = pipelineV5()
    pipeline["schemaVersion"] = 6
    pipeline["qualityEnhancementRecipeV1"] = [
      "recipeVersion": 1,
      "noiseReduction": noiseReduction,
      "lowLightRecovery": lowLightRecovery,
      "hazeRemoval": hazeRemoval,
      "detailSharpening": detailSharpening,
    ]
    return pipeline
  }

  private func pipelineV7(
    flipHorizontal: Bool = false,
    flipVertical: Bool = false,
    perspectiveHorizontal: NSNumber = 0,
    perspectiveVertical: NSNumber = 0,
    filter: String = "none",
    filterStrength: NSNumber = 0,
    hsl: [String: [String: NSNumber]] = [:]
  ) -> [String: Any] {
    var pipeline = pipelineV6()
    pipeline["schemaVersion"] = 7
    pipeline["basicEditingRecipeV1"] = [
      "recipeVersion": 1,
      "flipHorizontal": flipHorizontal,
      "flipVertical": flipVertical,
      "perspectiveHorizontal": perspectiveHorizontal,
      "perspectiveVertical": perspectiveVertical,
      "filter": filter,
      "filterStrength": filterStrength,
      "hsl": hsl,
    ]
    return pipeline
  }

  private func pipelineV8(
    selectedFaceIndex: Int = 0,
    faceTargets: [[String: Any]] = [[
      "faceSlim": 0, "headSize": 0, "jaw": 0, "chin": 0,
      "eyes": 0, "nose": 0, "mouth": 0,
    ]],
    selectedBodyIndex: Int = 0,
    bodyTargets: [[String: Any]] = [[
      "slimming": 0, "height": 0, "shoulders": 0, "waist": 0, "legs": 0,
    ]]
  ) -> [String: Any] {
    var pipeline = pipelineV7()
    pipeline["schemaVersion"] = 8
    pipeline["portraitGeometryRecipeV1"] = [
      "recipeVersion": 1,
      "selectedFaceIndex": selectedFaceIndex,
      "faceTargets": faceTargets,
      "selectedBodyIndex": selectedBodyIndex,
      "bodyTargets": bodyTargets,
    ]
    return pipeline
  }

  private func pipelineV9(
    background: String = "original",
    backgroundBlur: NSNumber = 0,
    subjectExposure: NSNumber = 0,
    subjectSaturation: NSNumber = 0,
    backgroundExposure: NSNumber = 0,
    backgroundSaturation: NSNumber = 0,
    eraseStrokes: [[String: Any]] = []
  ) -> [String: Any] {
    var pipeline = pipelineV8()
    pipeline["schemaVersion"] = 9
    pipeline["semanticEditingRecipeV1"] = [
      "recipeVersion": 1,
      "background": background,
      "backgroundBlur": backgroundBlur,
      "subjectExposure": subjectExposure,
      "subjectSaturation": subjectSaturation,
      "backgroundExposure": backgroundExposure,
      "backgroundSaturation": backgroundSaturation,
      "eraseStrokes": eraseStrokes,
    ]
    return pipeline
  }

  private func pipelineV10(
    background: String = "original",
    backgroundImagePath: String = "",
    backgroundImageResourceId: String = "",
    backgroundBlur: NSNumber = 0,
    subjectExposure: NSNumber = 0,
    subjectSaturation: NSNumber = 0,
    backgroundExposure: NSNumber = 0,
    backgroundSaturation: NSNumber = 0,
    localExposure: NSNumber = 0,
    localSaturation: NSNumber = 0,
    subjectMaskStrokes: [[String: Any]] = [],
    localAdjustmentStrokes: [[String: Any]] = [],
    eraseStrokes: [[String: Any]] = []
  ) -> [String: Any] {
    var pipeline = pipelineV8()
    pipeline["schemaVersion"] = 10
    pipeline["semanticEditingRecipeV2"] = [
      "recipeVersion": 3,
      "background": background,
      "backgroundImagePath": backgroundImagePath,
      "backgroundImageResourceId": backgroundImageResourceId,
      "backgroundBlur": backgroundBlur,
      "subjectExposure": subjectExposure,
      "subjectSaturation": subjectSaturation,
      "backgroundExposure": backgroundExposure,
      "backgroundSaturation": backgroundSaturation,
      "localExposure": localExposure,
      "localSaturation": localSaturation,
      "subjectMaskStrokes": subjectMaskStrokes,
      "localAdjustmentStrokes": localAdjustmentStrokes,
      "eraseStrokes": eraseStrokes,
    ]
    return pipeline
  }

  private func pipelineV11(
    adjustments: [[String: Any]] = []
  ) -> [String: Any] {
    var pipeline = pipelineV10()
    pipeline["schemaVersion"] = 11
    pipeline["targetedPortraitRecipeV1"] = [
      "schemaVersion": 1,
      "adjustments": adjustments,
    ]
    return pipeline
  }

  private func meanHorizontalLumaDifference(_ bytes: [UInt8], width: Int) -> Double {
    var total = 0
    var count = 0
    for offset in stride(from: 4, to: bytes.count, by: 4) where (offset / 4) % width != 0 {
      total += abs(Int(bytes[offset]) - Int(bytes[offset - 4]))
      count += 1
    }
    return Double(total) / Double(count)
  }

  private func meanHorizontalLumaDifference(
    _ bytes: [UInt8],
    width: Int,
    xRange: Range<Int>
  ) -> Double {
    let height = bytes.count / 4 / width
    var total = 0
    var count = 0
    for y in 0..<height {
      for x in xRange where x > 0 {
        let offset = (y * width + x) * 4
        total += abs(Int(bytes[offset]) - Int(bytes[offset - 4]))
        count += 1
      }
    }
    return Double(total) / Double(count)
  }

  private func meanVerticalEdgeContrast(
    _ bytes: [UInt8],
    width: Int,
    edgeX: Int
  ) -> Double {
    let height = bytes.count / 4 / width
    let total = (0..<height).reduce(0) { result, y in
      let left = (y * width + edgeX - 1) * 4
      let right = (y * width + edgeX) * 4
      return result + abs(Int(bytes[right]) - Int(bytes[left]))
    }
    return Double(total) / Double(height)
  }

  private func firstPixel(_ image: CIImage) throws -> [Int] {
    try Array(rgbaBytes(image).prefix(4)).map(Int.init)
  }

  private func writePNG(_ image: CIImage, to url: URL) throws {
    let data = try XCTUnwrap(imageContext.pngRepresentation(
      of: image,
      format: .RGBA8,
      colorSpace: sRGB
    ))
    try data.write(to: url, options: .atomic)
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

  private func stripedImage(extent: CGRect) -> CIImage {
    var image = CIImage(color: .black).cropped(to: extent)
    for x in stride(from: Int(extent.minX), to: Int(extent.maxX), by: 4) {
      let color = (x / 4).isMultiple(of: 2) ? CIColor.white : CIColor.red
      let stripe = CGRect(x: x, y: Int(extent.minY), width: 4, height: Int(extent.height))
      image = CIImage(color: color).cropped(to: stripe).composited(over: image)
    }
    return image.cropped(to: extent)
  }

  private func meanAbsoluteDifference(_ left: [UInt8], _ right: [UInt8]) -> Double {
    guard left.count == right.count, !left.isEmpty else { return .infinity }
    let total = zip(left, right).reduce(0) { result, pair in
      result + abs(Int(pair.0) - Int(pair.1))
    }
    return Double(total) / Double(left.count)
  }

  private func brightPixelBounds(
    _ bytes: [UInt8],
    width: Int,
    row: Int
  ) -> (minimum: Int, maximum: Int, width: Int) {
    let values = (0..<width).filter { x in
      bytes[(row * width + x) * 4] >= 128
    }
    return (
      values.min() ?? -1,
      values.max() ?? -1,
      values.count
    )
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

  private func compactSpotContrast(
    _ bytes: [UInt8],
    width: Int,
    centers: [(x: Int, y: Int)]
  ) -> Double {
    let neighborOffsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    var total = 0.0
    var comparisons = 0
    for center in centers {
      let centerOffset = (center.y * width + center.x) * 4
      for neighbor in neighborOffsets {
        let neighborOffset = ((center.y + neighbor.1) * width + center.x + neighbor.0) * 4
        for channel in 0..<3 {
          total += abs(Double(bytes[centerOffset + channel]) - Double(bytes[neighborOffset + channel]))
          comparisons += 1
        }
      }
    }
    return total / Double(comparisons)
  }

  private func meanLuminance(
    _ bytes: [UInt8],
    width: Int,
    rect: CGRect
  ) -> Double {
    var total = 0.0
    var pixels = 0
    for y in Int(rect.minY)..<Int(rect.maxY) {
      for x in Int(rect.minX)..<Int(rect.maxX) {
        let offset = (y * width + x) * 4
        total += 0.2126 * Double(bytes[offset])
          + 0.7152 * Double(bytes[offset + 1])
          + 0.0722 * Double(bytes[offset + 2])
        pixels += 1
      }
    }
    return total / Double(pixels)
  }

  private func meanRegionAbsoluteDifference(
    _ left: [UInt8],
    _ right: [UInt8],
    width: Int,
    rect: CGRect
  ) -> Double {
    var total = 0
    var channels = 0
    for y in Int(rect.minY)..<Int(rect.maxY) {
      for x in Int(rect.minX)..<Int(rect.maxX) {
        let offset = (y * width + x) * 4
        for channel in 0..<3 {
          total += abs(Int(left[offset + channel]) - Int(right[offset + channel]))
          channels += 1
        }
      }
    }
    return Double(total) / Double(channels)
  }

  private func meanChroma(
    _ bytes: [UInt8],
    width: Int,
    rect: CGRect
  ) -> (redMinusGreen: Double, blueMinusGreen: Double) {
    var redMinusGreen = 0.0
    var blueMinusGreen = 0.0
    var pixels = 0
    for y in Int(rect.minY)..<Int(rect.maxY) {
      for x in Int(rect.minX)..<Int(rect.maxX) {
        let offset = (y * width + x) * 4
        redMinusGreen += Double(bytes[offset]) - Double(bytes[offset + 1])
        blueMinusGreen += Double(bytes[offset + 2]) - Double(bytes[offset + 1])
        pixels += 1
      }
    }
    return (redMinusGreen / Double(pixels), blueMinusGreen / Double(pixels))
  }

  private func chromaDistance(
    _ left: (redMinusGreen: Double, blueMinusGreen: Double),
    _ right: (redMinusGreen: Double, blueMinusGreen: Double)
  ) -> Double {
    hypot(
      left.redMinusGreen - right.redMinusGreen,
      left.blueMinusGreen - right.blueMinusGreen
    )
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

  private func writeStripedJpeg(to url: URL, width: Int, height: Int) throws {
    let image = stripedImage(
      extent: CGRect(x: 0, y: 0, width: width, height: height)
    )
    try imageContext.writeJPEGRepresentation(
      of: image,
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
