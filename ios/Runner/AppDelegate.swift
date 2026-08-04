import Flutter
import CoreImage
import CryptoKit
import ImageIO
import Photos
import UIKit
import Vision

private enum PhotoInputInspectionError: Error {
  case unreadable
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var photoExportChannel: FlutterMethodChannel?
  private var photoInputChannel: FlutterMethodChannel?
  private var photoPreviewRenderer: IOSPhotoPreviewRenderer?
  private let photoExportContext = CIContext(options: [.cacheIntermediates: false])
#if DEBUG
  private var portraitMaskSpikeChannel: FlutterMethodChannel?
#endif

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "YingjianPhotoExporter"
    ) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "yingjian/photo_export",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "exportPhoto" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.exportPhoto(arguments: call.arguments, result: result)
    }
    photoExportChannel = channel
    configurePhotoInput(messenger: registrar.messenger())
    photoPreviewRenderer = IOSPhotoPreviewRenderer(
      messenger: registrar.messenger(),
      textureRegistry: registrar.textures()
    )
#if DEBUG
    configurePortraitMaskSpike(messenger: registrar.messenger())
#endif
  }

  private func configurePhotoInput(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "yingjian/photo_input",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "supportsHeif" {
        result(true)
        return
      }
      guard
        call.method == "inspectPhoto",
        let values = call.arguments as? [String: Any],
        let path = values["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let inspection = try Self.inspectPhoto(path: path)
          DispatchQueue.main.async { result(inspection) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "unreadable",
              message: "Photo could not be inspected",
              details: nil
            ))
          }
        }
      }
    }
    photoInputChannel = channel
  }

  private static func inspectPhoto(path: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(source) == 1,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
      width.intValue > 0,
      height.intValue > 0
    else {
      throw PhotoInputInspectionError.unreadable
    }
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: 2048,
      kCGImageSourceCreateThumbnailWithTransform: false,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let decoded = CGImageSourceCreateThumbnailAtIndex(
      source,
      0,
      thumbnailOptions as CFDictionary
    ) else {
      throw PhotoInputInspectionError.unreadable
    }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let normalizedOrientation = (1...8).contains(orientation) ? orientation : 1
    let type = (CGImageSourceGetType(source) as String?)?.lowercased() ?? ""
    let inputFormat: String
    if type.contains("jpeg") {
      inputFormat = "jpeg"
    } else if type.contains("png") {
      inputFormat = "png"
    } else if type.contains("heic") || type.contains("heif") {
      inputFormat = "heic"
    } else {
      throw PhotoInputInspectionError.unreadable
    }
    let colorName = (decoded.colorSpace?.name as String?)?.lowercased() ?? ""
    let colorSpace: String
    if colorName.contains("displayp3") || colorName.contains("display p3") {
      colorSpace = "displayP3"
    } else if colorName.contains("srgb") {
      colorSpace = "srgb"
    } else {
      colorSpace = "unknown"
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
      let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
      if chunk.isEmpty { break }
      hasher.update(data: chunk)
    }
    let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    return [
      "contentSha256": hash,
      "pixelWidth": width.intValue,
      "pixelHeight": height.intValue,
      "orientation": normalizedOrientation,
      "colorSpace": colorSpace,
      "inputFormat": inputFormat,
    ]
  }

#if DEBUG
  private func configurePortraitMaskSpike(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "yingjian/portrait_mask_spike",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "analyzePortrait" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let values = call.arguments as? [String: Any],
        let sourcePath = values["sourcePath"] as? String
      else {
        result(FlutterError(
          code: "invalidArguments",
          message: "Portrait spike requires a source path",
          details: nil
        ))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let output = try PortraitMaskSpike.analyze(sourcePath: sourcePath)
          DispatchQueue.main.async { result(output) }
        } catch let error as PortraitMaskSpikeError {
          DispatchQueue.main.async {
            result(FlutterError(code: error.code, message: error.message, details: nil))
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "analysisFailed",
              message: "Portrait analysis failed",
              details: nil
            ))
          }
        }
      }
    }
    portraitMaskSpikeChannel = channel
  }
#endif

  private func exportPhoto(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let sourcePath = values["sourcePath"] as? String,
      let pipeline = IOSImagePipeline(arguments: values["pipeline"])
    else {
      result(FlutterError(code: "invalidArguments", message: "Invalid export request", details: nil))
      return
    }

    PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "photoAccessDenied", message: "Photo access denied", details: nil))
        }
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        self?.renderAndSave(
          sourcePath: sourcePath,
          pipeline: pipeline,
          result: result
        )
      }
    }
  }

  private func renderAndSave(
    sourcePath: String,
    pipeline: IOSImagePipeline,
    result: @escaping FlutterResult
  ) {
    guard let input = CIImage(
      contentsOf: URL(fileURLWithPath: sourcePath),
      options: [.applyOrientationProperty: true]
    ) else {
      finishWithError(code: "decodeFailed", message: "Photo could not be decoded", result: result)
      return
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
      finishWithError(code: "renderFailed", message: "sRGB is unavailable", result: result)
      return
    }
    let temporaryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("Yingjian_\(UUID().uuidString).jpg")
    do {
      try photoExportContext.writeJPEGRepresentation(
        of: output,
        to: temporaryURL,
        colorSpace: colorSpace,
        options: [
          kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
        ]
      )
    } catch {
      finishWithError(code: "renderFailed", message: "Photo could not be rendered", result: result)
      return
    }

    var assetId: String?
    PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      request.creationDate = ImageExportMetadata.captureDate(from: metadata)
      let options = PHAssetResourceCreationOptions()
      options.originalFilename = "Yingjian_\(Int(Date().timeIntervalSince1970)).jpg"
      request.addResource(with: .photo, fileURL: temporaryURL, options: options)
      assetId = request.placeholderForCreatedAsset?.localIdentifier
    } completionHandler: { success, _ in
      try? FileManager.default.removeItem(at: temporaryURL)
      DispatchQueue.main.async {
        guard success, let assetId else {
          result(FlutterError(code: "saveFailed", message: "Photo could not be saved", details: nil))
          return
        }
        result([
          "assetId": assetId,
          "width": Int(outputExtent.width),
          "height": Int(outputExtent.height),
        ])
      }
    }
  }

  private func finishWithError(
    code: String,
    message: String,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      result(FlutterError(code: code, message: message, details: nil))
    }
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

private struct IOSImagePipeline {
  let exposureEV: Double
  let highlights: Double
  let shadows: Double
  let contrast: Double
  let warmth: Double
  let tint: Double
  let saturation: Double
  let clarity: Double
  let crop: CGRect
  let quarterTurns: Int
  let straightenDegrees: Double

  init?(arguments: Any?) {
    guard
      let pipeline = arguments as? [String: Any],
      let schemaVersion = (pipeline["schemaVersion"] as? NSNumber)?.intValue,
      schemaVersion == 1 || schemaVersion == 2,
      pipeline["workingColorSpace"] as? String == "srgb",
      let adjustments = pipeline["adjustments"] as? [String: Any],
      let exposureEV = (adjustments["exposureEv"] as? NSNumber)?.doubleValue,
      let contrast = (adjustments["contrast"] as? NSNumber)?.doubleValue,
      let warmth = (adjustments["warmth"] as? NSNumber)?.doubleValue,
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
      let normalizedCrop = geometry["normalizedCrop"] as? [NSNumber],
      normalizedCrop.count == 4,
      let quarterTurns = (geometry["quarterTurns"] as? NSNumber)?.intValue,
      (0...3).contains(quarterTurns),
      let straightenDegrees = (geometry["straightenDegrees"] as? NSNumber)?.doubleValue,
      straightenDegrees.isFinite,
      (-45.0...45.0).contains(straightenDegrees),
      let portrait = pipeline["portrait"] as? [String: Any],
      (portrait["recipeVersion"] as? NSNumber)?.intValue == 1,
      let portraitStrength = (portrait["strength"] as? NSNumber)?.doubleValue,
      portraitStrength == 0
    else {
      return nil
    }
    let values = normalizedCrop.map(\.doubleValue)
    guard
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
    crop = CGRect(
      x: values[0],
      y: values[1],
      width: values[2] - values[0],
      height: values[3] - values[1]
    )
    self.quarterTurns = quarterTurns
    self.straightenDegrees = straightenDegrees
  }

  private static func normalized(_ value: Any?) -> Double? {
    guard let result = (value as? NSNumber)?.doubleValue,
          result.isFinite,
          (-1.0...1.0).contains(result)
    else { return nil }
    return result
  }

  var colorTransform: ColorTransform {
    let exposureScale = pow(2, exposureEV)
    let contrastScale = 1 + contrast * 0.75
    let redWarmthScale = 1 + warmth * 0.15
    let blueWarmthScale = 1 - warmth * 0.15
    let contrastBias = 0.5 * (1 - contrastScale)
    return ColorTransform(
      redScale: exposureScale * contrastScale * redWarmthScale,
      greenScale: exposureScale * contrastScale,
      blueScale: exposureScale * contrastScale * blueWarmthScale,
      redBias: contrastBias * redWarmthScale,
      greenBias: contrastBias,
      blueBias: contrastBias * blueWarmthScale
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
        "inputBiasVector": CIVector(
          x: transform.redBias,
          y: transform.greenBias,
          z: transform.blueBias,
          w: 0
        ),
      ]
    ).cropped(to: extent)

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
    return applyingGeometry(to: output, sourceExtent: extent)
  }

  private func applyingGeometry(to input: CIImage, sourceExtent: CGRect) -> CIImage {
    let cropRect = CGRect(
      x: sourceExtent.minX + crop.minX * sourceExtent.width,
      y: sourceExtent.minY + (1 - crop.maxY) * sourceExtent.height,
      width: crop.width * sourceExtent.width,
      height: crop.height * sourceExtent.height
    ).integral.intersection(sourceExtent)
    var output = input.cropped(to: cropRect)
    if straightenDegrees != 0 {
      let radians = CGFloat(-straightenDegrees * .pi / 180)
      let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
      let transform = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: radians)
        .translatedBy(x: -center.x, y: -center.y)
      output = output.clampedToExtent().transformed(by: transform).cropped(to: cropRect)
    }
    if quarterTurns != 0 {
      let center = CGPoint(x: output.extent.midX, y: output.extent.midY)
      let transform = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: CGFloat(-quarterTurns) * .pi / 2)
        .translatedBy(x: -center.x, y: -center.y)
      output = output.transformed(by: transform)
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
  let redBias: Double
  let greenBias: Double
  let blueBias: Double
}

/// Owns the iOS path-backed preview textures. Flutter only receives the
/// texture identifier, dimensions, and stable lifecycle errors.
private final class IOSPhotoPreviewRenderer {
  private static let channelName = "yingjian/photo_preview"

  private let channel: FlutterMethodChannel
  private let textureRegistry: FlutterTextureRegistry
  private let renderQueue = DispatchQueue(label: "com.babycompany.yingjian.photo-preview")
  private var sessions: [Int64: IOSPhotoPreviewSession] = [:]

  init(messenger: FlutterBinaryMessenger, textureRegistry: FlutterTextureRegistry) {
    self.textureRegistry = textureRegistry
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    for (textureId, session) in sessions {
      session.close()
      textureRegistry.unregisterTexture(textureId)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createPreview":
      createPreview(arguments: call.arguments, result: result)
    case "updatePreview":
      updatePreview(arguments: call.arguments, result: result)
    case "disposePreview":
      disposePreview(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func createPreview(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let sourcePath = values["sourcePath"] as? String,
      let maxEdge = (values["maxEdge"] as? NSNumber)?.intValue,
      (1...2_048).contains(maxEdge),
      let pipeline = IOSImagePipeline(arguments: values["pipeline"])
    else {
      result(FlutterError(
        code: "invalidArguments",
        message: "Invalid preview request",
        details: nil
      ))
      return
    }

    renderQueue.async { [weak self] in
      guard let self else { return }
      do {
        let session = try IOSPhotoPreviewSession(
          sourcePath: sourcePath,
          maxEdge: maxEdge,
          pipeline: pipeline
        )
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          let textureId = self.textureRegistry.register(session)
          guard textureId >= 0 else {
            session.close()
            result(FlutterError(
              code: "previewUnavailable",
              message: "Native preview could not be created",
              details: nil
            ))
            return
          }
          self.sessions[textureId] = session
          self.textureRegistry.textureFrameAvailable(textureId)
          result([
            "textureId": textureId,
            "width": session.width,
            "height": session.height,
            "backend": "ios-core-image",
          ])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "previewUnavailable",
            message: "Native preview could not be created",
            details: nil
          ))
        }
      }
    }
  }

  private func updatePreview(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let textureId = (values["textureId"] as? NSNumber)?.int64Value,
      let pipeline = IOSImagePipeline(arguments: values["pipeline"])
    else {
      result(FlutterError(
        code: "invalidArguments",
        message: "Invalid preview update",
        details: nil
      ))
      return
    }
    guard let session = sessions[textureId] else {
      result(FlutterError(
        code: "previewNotFound",
        message: "Native preview no longer exists",
        details: nil
      ))
      return
    }

    renderQueue.async { [weak self, weak session] in
      guard let self, let session else { return }
      do {
        try session.render(pipeline: pipeline)
        DispatchQueue.main.async { [weak self, weak session] in
          guard let self, let session else { return }
          guard self.sessions[textureId] === session else {
            result(FlutterError(
              code: "previewNotFound",
              message: "Native preview no longer exists",
              details: nil
            ))
            return
          }
          self.textureRegistry.textureFrameAvailable(textureId)
          result(nil)
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "previewRenderFailed",
            message: "Native preview could not be updated",
            details: nil
          ))
        }
      }
    }
  }

  private func disposePreview(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let textureId = (values["textureId"] as? NSNumber)?.int64Value
    else {
      result(FlutterError(
        code: "invalidArguments",
        message: "Missing preview texture",
        details: nil
      ))
      return
    }
    guard let session = sessions.removeValue(forKey: textureId) else {
      result(nil)
      return
    }
    session.close()
    textureRegistry.unregisterTexture(textureId)
    result(nil)
  }
}

private final class IOSPhotoPreviewSession: NSObject, FlutterTexture {
  private static let context = CIContext(options: [.cacheIntermediates: false])
  private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  let width: Int
  let height: Int

  private let source: CIImage
  private let extent: CGRect
  private let bufferLock = NSLock()
  private var pixelBuffer: CVPixelBuffer?
  private var isClosed = false

  init(sourcePath: String, maxEdge: Int, pipeline: IOSImagePipeline) throws {
    guard let input = CIImage(
      contentsOf: URL(fileURLWithPath: sourcePath),
      options: [.applyOrientationProperty: true]
    ) else {
      throw IOSPhotoPreviewError.decodeFailed
    }
    let normalized = input.transformed(
      by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY)
    )
    let longestEdge = max(normalized.extent.width, normalized.extent.height)
    guard longestEdge >= 1 else {
      throw IOSPhotoPreviewError.decodeFailed
    }
    let scale = min(1, CGFloat(maxEdge) / longestEdge)
    let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let normalizedScaled = scaled.transformed(
      by: CGAffineTransform(translationX: -scaled.extent.minX, y: -scaled.extent.minY)
    )
    let sourceExtent = CGRect(
      x: 0,
      y: 0,
      width: max(1, floor(normalizedScaled.extent.width)),
      height: max(1, floor(normalizedScaled.extent.height))
    )
    source = normalizedScaled.cropped(to: sourceExtent)
    let initialOutput = pipeline.applying(to: source, extent: sourceExtent)
    extent = initialOutput.extent.integral
    width = Int(extent.width)
    height = Int(extent.height)
    super.init()
    try render(pipeline: pipeline)
  }

  func render(pipeline: IOSImagePipeline) throws {
    let output = pipeline.applying(to: source, extent: source.extent.integral)
    guard output.extent.integral.size == extent.size else {
      throw IOSPhotoPreviewError.dimensionsChanged
    }
    var newBuffer: CVPixelBuffer?
    let attributes: CFDictionary = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferIOSurfacePropertiesKey: [:],
    ] as CFDictionary
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attributes,
      &newBuffer
    )
    guard status == kCVReturnSuccess, let newBuffer else {
      throw IOSPhotoPreviewError.renderFailed
    }
    Self.context.render(
      output,
      to: newBuffer,
      bounds: extent,
      colorSpace: Self.sRGB
    )
    bufferLock.lock()
    defer { bufferLock.unlock() }
    guard !isClosed else {
      throw IOSPhotoPreviewError.closed
    }
    pixelBuffer = newBuffer
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    bufferLock.lock()
    defer { bufferLock.unlock() }
    guard !isClosed, let pixelBuffer else { return nil }
    return Unmanaged.passRetained(pixelBuffer)
  }

  func close() {
    bufferLock.lock()
    isClosed = true
    pixelBuffer = nil
    bufferLock.unlock()
  }

}

private enum IOSPhotoPreviewError: Error {
  case decodeFailed
  case renderFailed
  case closed
  case dimensionsChanged
}

#if DEBUG
/// THROWAWAY PROTOTYPE: validates Vision geometry and mask alignment only.
/// It deliberately does not claim to be a production skin-segmentation engine.
private enum PortraitMaskSpike {
  private static let maxEdge: CGFloat = 1_600
  private static let context = CIContext(options: [.cacheIntermediates: false])

  static func analyze(sourcePath: String) throws -> [String: Any] {
    guard let input = CIImage(
      contentsOf: URL(fileURLWithPath: sourcePath),
      options: [.applyOrientationProperty: true]
    ) else {
      throw PortraitMaskSpikeError(code: "decodeFailed", message: "Photo could not be decoded")
    }
    let normalized = input.transformed(
      by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY)
    )
    let longestEdge = max(normalized.extent.width, normalized.extent.height)
    guard longestEdge > 0 else {
      throw PortraitMaskSpikeError(code: "decodeFailed", message: "Photo dimensions are invalid")
    }
    let scale = min(1, maxEdge / longestEdge)
    let proxy = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let extent = proxy.extent.integral
    guard
      extent.width >= 1,
      extent.height >= 1,
      let proxyImage = context.createCGImage(proxy, from: extent)
    else {
      throw PortraitMaskSpikeError(code: "renderFailed", message: "Preview proxy could not be created")
    }

    let request = VNDetectFaceLandmarksRequest()
#if targetEnvironment(simulator)
    request.usesCPUOnly = true
#endif
    let handler = VNImageRequestHandler(cgImage: proxyImage, orientation: .up)
    do {
      try handler.perform([request])
    } catch {
      throw PortraitMaskSpikeError(
        code: "visionFailed",
        message: "Vision analysis failed: \(error.localizedDescription)"
      )
    }
    let observations = request.results ?? []
    let width = Int(extent.width)
    let height = Int(extent.height)
    let candidate = try makeMask(width: width, height: height) { graphics in
      graphics.setFillColor(gray: 1, alpha: 1)
      for face in observations {
        graphics.fillEllipse(in: candidateFaceRect(face.boundingBox, size: extent.size))
      }
    }
    let protection = try makeMask(width: width, height: height) { graphics in
      graphics.setFillColor(gray: 1, alpha: 1)
      graphics.setStrokeColor(gray: 1, alpha: 1)
      for face in observations {
        drawProtectionRegions(face: face, size: extent.size, graphics: graphics)
      }
    }

    let candidateImage = CIImage(cgImage: candidate)
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 8])
      .cropped(to: extent)
    let protectionImage = CIImage(cgImage: protection)
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3])
      .cropped(to: extent)
    let inverseProtection = protectionImage
      .applyingFilter("CIColorInvert")
      .cropped(to: extent)
    let effectiveImage = candidateImage
      .applyingFilter(
        "CIMultiplyBlendMode",
        parameters: [kCIInputBackgroundImageKey: inverseProtection]
      )
      .cropped(to: extent)

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("portrait-mask-spike", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let sourceProxyPath = try writePNG(
      proxy,
      extent: extent,
      to: directory.appendingPathComponent("source-proxy.png")
    )
    let candidatePath = try writePNG(
      candidateImage,
      extent: extent,
      to: directory.appendingPathComponent("candidate-face-region.png")
    )
    let protectionPath = try writePNG(
      protectionImage,
      extent: extent,
      to: directory.appendingPathComponent("protected-features.png")
    )
    let effectivePath = try writePNG(
      effectiveImage,
      extent: extent,
      to: directory.appendingPathComponent("effective-region.png")
    )
    let overlayPath = try writePNG(
      overlay(mask: effectiveImage, source: proxy, extent: extent),
      extent: extent,
      to: directory.appendingPathComponent("effective-region-overlay.png")
    )

    return [
      "faceCount": observations.count,
      "width": width,
      "height": height,
      "sourceProxyPath": sourceProxyPath,
      "candidateMaskPath": candidatePath,
      "protectionMaskPath": protectionPath,
      "effectiveMaskPath": effectivePath,
      "overlayPath": overlayPath,
      "candidateKind": "vision-landmarks-geometry-roi",
      "geometryOnly": true,
      "executionEnvironment": executionEnvironment,
      "landmarkSummary": landmarkSummary(observations.first?.landmarks),
      "landmarkBoundsSummary": landmarkBoundsSummary(observations.first?.landmarks),
    ]
  }

  private static var executionEnvironment: String {
#if targetEnvironment(simulator)
    return "simulator-cpu-only"
#else
    return "physical-device"
#endif
  }

  private static func landmarkSummary(_ landmarks: VNFaceLandmarks2D?) -> String {
    guard let landmarks else { return "unavailable" }
    return [
      "leftEye=\(landmarks.leftEye?.pointCount ?? 0)",
      "rightEye=\(landmarks.rightEye?.pointCount ?? 0)",
      "leftEyebrow=\(landmarks.leftEyebrow?.pointCount ?? 0)",
      "rightEyebrow=\(landmarks.rightEyebrow?.pointCount ?? 0)",
      "outerLips=\(landmarks.outerLips?.pointCount ?? 0)",
      "nose=\(landmarks.nose?.pointCount ?? 0)",
    ].joined(separator: ", ")
  }

  private static func landmarkBoundsSummary(_ landmarks: VNFaceLandmarks2D?) -> String {
    guard let landmarks else { return "unavailable" }
    return [
      boundsSummary("leftEye", landmarks.leftEye),
      boundsSummary("rightEye", landmarks.rightEye),
      boundsSummary("outerLips", landmarks.outerLips),
    ].joined(separator: "; ")
  }

  private static func boundsSummary(
    _ name: String,
    _ region: VNFaceLandmarkRegion2D?
  ) -> String {
    guard let region, let first = region.normalizedPoints.first else {
      return "\(name)=none"
    }
    var minX = first.x
    var minY = first.y
    var maxX = first.x
    var maxY = first.y
    for point in region.normalizedPoints.dropFirst() {
      minX = min(minX, point.x)
      minY = min(minY, point.y)
      maxX = max(maxX, point.x)
      maxY = max(maxY, point.y)
    }
    return String(
      format: "%@=(%.2f,%.2f)-(%.2f,%.2f)",
      name,
      minX,
      minY,
      maxX,
      maxY
    )
  }

  private static func makeMask(
    width: Int,
    height: Int,
    drawing: (CGContext) -> Void
  ) throws -> CGImage {
    guard let graphics = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else {
      throw PortraitMaskSpikeError(code: "maskFailed", message: "Mask buffer could not be created")
    }
    graphics.setAllowsAntialiasing(true)
    graphics.setShouldAntialias(true)
    graphics.setFillColor(gray: 0, alpha: 1)
    graphics.fill(CGRect(x: 0, y: 0, width: width, height: height))
    drawing(graphics)
    guard let image = graphics.makeImage() else {
      throw PortraitMaskSpikeError(code: "maskFailed", message: "Mask image could not be created")
    }
    return image
  }

  private static func candidateFaceRect(_ box: CGRect, size: CGSize) -> CGRect {
    let base = CGRect(
      x: box.minX * size.width,
      y: box.minY * size.height,
      width: box.width * size.width,
      height: box.height * size.height
    )
    return CGRect(
      x: base.minX - base.width * 0.04,
      y: base.minY + base.height * 0.02,
      width: base.width * 1.08,
      height: base.height * 1.08
    ).intersection(CGRect(origin: .zero, size: size))
  }

  private static func drawProtectionRegions(
    face: VNFaceObservation,
    size: CGSize,
    graphics: CGContext
  ) {
    guard let landmarks = face.landmarks else { return }
    let faceWidth = face.boundingBox.width * size.width
    let closedPadding = max(4, faceWidth * 0.025)
    let linePadding = max(3, faceWidth * 0.018)

    fillRegion(landmarks.leftEye, face: face, size: size, padding: closedPadding, in: graphics)
    fillRegion(landmarks.rightEye, face: face, size: size, padding: closedPadding, in: graphics)
    fillRegion(landmarks.outerLips, face: face, size: size, padding: closedPadding, in: graphics)
    fillRegion(landmarks.innerLips, face: face, size: size, padding: closedPadding, in: graphics)
    strokeRegion(landmarks.leftEyebrow, face: face, size: size, width: linePadding * 2, in: graphics)
    strokeRegion(landmarks.rightEyebrow, face: face, size: size, width: linePadding * 2, in: graphics)
    strokeRegion(landmarks.nose, face: face, size: size, width: linePadding, in: graphics)
    strokeRegion(landmarks.noseCrest, face: face, size: size, width: linePadding, in: graphics)
    fillRegion(landmarks.leftPupil, face: face, size: size, padding: closedPadding, in: graphics)
    fillRegion(landmarks.rightPupil, face: face, size: size, padding: closedPadding, in: graphics)
  }

  private static func points(
    for region: VNFaceLandmarkRegion2D?,
    face: VNFaceObservation,
    size: CGSize
  ) -> [CGPoint] {
    guard let region else { return [] }
    return region.normalizedPoints.map { point in
      VNImagePointForFaceLandmarkPoint(
        vector_float2(Float(point.x), Float(point.y)),
        face.boundingBox,
        Int(size.width),
        Int(size.height)
      )
    }
  }

  private static func fillRegion(
    _ region: VNFaceLandmarkRegion2D?,
    face: VNFaceObservation,
    size: CGSize,
    padding: CGFloat,
    in graphics: CGContext
  ) {
    let values = points(for: region, face: face, size: size)
    guard values.count >= 2 else { return }
    var minX = values[0].x
    var minY = values[0].y
    var maxX = values[0].x
    var maxY = values[0].y
    for point in values.dropFirst() {
      minX = min(minX, point.x)
      minY = min(minY, point.y)
      maxX = max(maxX, point.x)
      maxY = max(maxY, point.y)
    }
    let bounds = CGRect(
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY
    ).insetBy(dx: -padding, dy: -padding)
    graphics.fillEllipse(in: bounds)
  }

  private static func strokeRegion(
    _ region: VNFaceLandmarkRegion2D?,
    face: VNFaceObservation,
    size: CGSize,
    width: CGFloat,
    in graphics: CGContext
  ) {
    let values = points(for: region, face: face, size: size)
    guard let first = values.first else { return }
    graphics.setLineWidth(width)
    graphics.setLineCap(.round)
    graphics.setLineJoin(.round)
    graphics.beginPath()
    graphics.move(to: first)
    for point in values.dropFirst() {
      graphics.addLine(to: point)
    }
    graphics.strokePath()
  }

  private static func overlay(mask: CIImage, source: CIImage, extent: CGRect) -> CIImage {
    let green = CIImage(color: CIColor(red: 0.05, green: 0.92, blue: 0.45, alpha: 0.55))
      .cropped(to: extent)
    let tinted = green.composited(over: source)
    return tinted.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: source,
        kCIInputMaskImageKey: mask,
      ]
    ).cropped(to: extent)
  }

  private static func writePNG(_ image: CIImage, extent: CGRect, to url: URL) throws -> String {
    guard
      let cgImage = context.createCGImage(image, from: extent),
      let data = UIImage(cgImage: cgImage).pngData()
    else {
      throw PortraitMaskSpikeError(code: "renderFailed", message: "Debug image could not be rendered")
    }
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw PortraitMaskSpikeError(code: "writeFailed", message: "Debug image could not be written")
    }
    return url.path
  }
}

private struct PortraitMaskSpikeError: Error {
  let code: String
  let message: String
}
#endif
