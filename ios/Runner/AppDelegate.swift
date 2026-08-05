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

/// Production eligibility remains closed until the portrait candidate passes
/// the frozen corpus, competitor comparison, and blind-review gates in ADR 0002.
struct IOSPortraitCapabilityStatus: Equatable {
  let applicability: String
  let reason: String
}

enum IOSPortraitCapabilityPolicy {
  static let productionEligible = false

  static func classify(_ decision: IOSPortraitSafetyDecision) -> IOSPortraitCapabilityStatus {
    guard decision.applicable else {
      let applicability = decision.reason == .noFace ? "unavailable" : "unsafe"
      return IOSPortraitCapabilityStatus(
        applicability: applicability,
        reason: reasonName(decision.reason)
      )
    }
    guard productionEligible else {
      return IOSPortraitCapabilityStatus(
        applicability: "unsafe",
        reason: "capabilityLocked"
      )
    }
    return IOSPortraitCapabilityStatus(applicability: "applicable", reason: "none")
  }

  private static func reasonName(_ reason: IOSPortraitDegradationReason) -> String {
    switch reason {
    case .none: return "none"
    case .noFace: return "noFace"
    case .multipleFaces: return "multipleFaces"
    case .lowConfidence: return "lowConfidence"
    case .faceTooSmall: return "faceTooSmall"
    case .landmarksUnavailable: return "landmarksUnavailable"
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var photoExportChannel: FlutterMethodChannel?
  private var photoShareChannel: FlutterMethodChannel?
  private var photoInputChannel: FlutterMethodChannel?
  private var photoAnalysisChannel: FlutterMethodChannel?
  private var photoPreviewRenderer: IOSPhotoPreviewRenderer?
  private let photoExportContext = CIContext(options: [.cacheIntermediates: false])
  private var photoShareInProgress = false
#if DEBUG
  private var portraitMaskSpikeChannel: FlutterMethodChannel?
  private var portraitMaskSpikeStartupError: PortraitMaskSpikeError?
#endif

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    cleanupAbandonedShareFiles()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func cleanupAbandonedShareFiles() {
    let root = FileManager.default.temporaryDirectory
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil
    ) else {
      return
    }
    for file in files
      where file.lastPathComponent.hasPrefix("Yingjian_") &&
        file.pathExtension.lowercased() == "jpg"
    {
      try? FileManager.default.removeItem(at: file)
    }
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
    configurePhotoShare(messenger: registrar.messenger())
    configurePhotoInput(messenger: registrar.messenger())
    configurePhotoAnalysis(messenger: registrar.messenger())
    photoPreviewRenderer = IOSPhotoPreviewRenderer(
      messenger: registrar.messenger(),
      textureRegistry: registrar.textures()
    )
#if DEBUG
    configurePortraitMaskSpike(messenger: registrar.messenger())
#endif
  }

  private func configurePhotoShare(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "yingjian/photo_share",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "sharePhotos":
        self?.sharePhotos(arguments: call.arguments, result: result)
      case "discardPhotos":
        self?.discardPhotos(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    photoShareChannel = channel
  }

  private func sharePhotos(arguments: Any?, result: @escaping FlutterResult) {
    guard !photoShareInProgress else {
      result(FlutterError(code: "shareInProgress", message: "A share sheet is already open", details: nil))
      return
    }
    guard let urls = temporaryShareURLs(arguments: arguments, requireExisting: true) else {
      result(FlutterError(code: "invalidArguments", message: "Invalid share request", details: nil))
      return
    }
    guard
      let presenter = topViewController(),
      presenter.viewIfLoaded?.window != nil
    else {
      result(FlutterError(code: "shareUnavailable", message: "Share is unavailable", details: nil))
      return
    }

    let controller = UIActivityViewController(
      activityItems: urls,
      applicationActivities: nil
    )
    if let popover = controller.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(
        x: presenter.view.bounds.midX,
        y: presenter.view.bounds.maxY,
        width: 1,
        height: 1
      )
    }
    photoShareInProgress = true
    controller.completionWithItemsHandler = { [weak self] _, completed, _, error in
      DispatchQueue.main.async {
        self?.photoShareInProgress = false
        if completed {
          urls.forEach { try? FileManager.default.removeItem(at: $0) }
          result("completed")
        } else if error != nil {
          result(FlutterError(code: "shareFailed", message: "System sharing failed", details: nil))
        } else {
          result("canceled")
        }
      }
    }
    presenter.present(controller, animated: true)
  }

  private func discardPhotos(arguments: Any?, result: @escaping FlutterResult) {
    guard !photoShareInProgress else {
      result(FlutterError(code: "shareInProgress", message: "A share sheet is already open", details: nil))
      return
    }
    guard let urls = temporaryShareURLs(arguments: arguments, requireExisting: false) else {
      result(FlutterError(code: "invalidArguments", message: "Invalid discard request", details: nil))
      return
    }
    do {
      for url in urls where FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      result(nil)
    } catch {
      result(FlutterError(code: "discardFailed", message: "Temporary photo cleanup failed", details: nil))
    }
  }

  private func temporaryShareURLs(
    arguments: Any?,
    requireExisting: Bool
  ) -> [URL]? {
    guard
      let values = arguments as? [String: Any],
      let paths = values["localPaths"] as? [String],
      !paths.isEmpty,
      paths.count <= 6
    else {
      return nil
    }
    let temporaryRoot = FileManager.default.temporaryDirectory
      .resolvingSymlinksInPath().standardizedFileURL
    let urls = paths.compactMap { path -> URL? in
      let url = URL(fileURLWithPath: path)
        .resolvingSymlinksInPath().standardizedFileURL
      guard
        url.deletingLastPathComponent() == temporaryRoot,
        url.lastPathComponent.hasPrefix("Yingjian_"),
        url.pathExtension.lowercased() == "jpg"
      else {
        return nil
      }
      let exists = FileManager.default.fileExists(atPath: url.path)
      if requireExisting && !exists {
        return nil
      }
      if exists,
         (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != true {
        return nil
      }
      return url
    }
    return urls.count == paths.count ? urls : nil
  }

  private func topViewController() -> UIViewController? {
    let sceneWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    let activeLegacyWindow = window.flatMap { candidate in
      candidate.windowScene?.activationState == .foregroundActive
        ? candidate
        : nil
    }
    var current = (sceneWindow ?? activeLegacyWindow)?.rootViewController
    while current != nil {
      if let presented = current?.presentedViewController {
        current = presented
      } else if let navigation = current as? UINavigationController {
        guard let visible = navigation.visibleViewController else {
          return navigation
        }
        current = visible
      } else if let tabs = current as? UITabBarController {
        guard let selected = tabs.selectedViewController else {
          return tabs
        }
        current = selected
      } else {
        return current
      }
    }
    return nil
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

  private func configurePhotoAnalysis(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "yingjian/photo_analysis",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard
        call.method == "analyzePhoto",
        let values = call.arguments as? [String: Any],
        let sourcePath = values["sourcePath"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let analysis = try Self.analyzePhoto(path: sourcePath)
          DispatchQueue.main.async { result(analysis) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "analysisUnavailable",
              message: "Local photo analysis is unavailable",
              details: nil
            ))
          }
        }
      }
    }
    photoAnalysisChannel = channel
  }

  static func analyzePhoto(path: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw PhotoInputInspectionError.unreadable
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 128,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(
      source,
      0,
      options as CFDictionary
    ) else {
      throw PhotoInputInspectionError.unreadable
    }

    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CIContext(options: [.cacheIntermediates: false])
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw PhotoInputInspectionError.unreadable
    }
    context.render(
      CIImage(cgImage: image),
      toBitmap: &pixels,
      rowBytes: width * 4,
      bounds: CGRect(x: 0, y: 0, width: width, height: height),
      format: .RGBA8,
      colorSpace: colorSpace
    )

    var luminanceTotal = 0.0
    var redTotal = 0.0
    var blueTotal = 0.0
    var edgeTotal = 0.0
    var previousRow = [Double](repeating: 0, count: width)
    for y in 0..<height {
      var previous = 0.0
      for x in 0..<width {
        let offset = (y * width + x) * 4
        let red = Double(pixels[offset]) / 255.0
        let green = Double(pixels[offset + 1]) / 255.0
        let blue = Double(pixels[offset + 2]) / 255.0
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        luminanceTotal += luminance
        redTotal += red
        blueTotal += blue
        if x > 0 { edgeTotal += abs(luminance - previous) }
        if y > 0 { edgeTotal += abs(luminance - previousRow[x]) }
        previous = luminance
        previousRow[x] = luminance
      }
    }
    let count = Double(width * height)
    let meanLuminance = luminanceTotal / count
    let redBlueDelta = (redTotal - blueTotal) / count
    let edgeMean = edgeTotal / max(1.0, (count * 2.0) - Double(width + height))

    let exposure: String
    if meanLuminance < 0.34 {
      exposure = "underexposed"
    } else if meanLuminance > 0.72 {
      exposure = "overexposed"
    } else {
      exposure = "balanced"
    }
    let whiteBalance: String
    if redBlueDelta > 0.10 {
      whiteBalance = "warmCast"
    } else if redBlueDelta < -0.10 {
      whiteBalance = "coolCast"
    } else {
      whiteBalance = "balanced"
    }
    let clarity: String
    if edgeMean < 0.018 {
      clarity = "blurred"
    } else if edgeMean < 0.040 {
      clarity = "soft"
    } else {
      clarity = "clear"
    }

    let portraitStatus: IOSPortraitCapabilityStatus
    let faceCount: Int
    let landmarkRequest = VNDetectFaceLandmarksRequest()
    do {
      let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
      try handler.perform([landmarkRequest])
      let observations = landmarkRequest.results ?? []
      faceCount = observations.count
      portraitStatus = IOSPortraitCapabilityPolicy.classify(
        IOSPortraitSafetyPolicy.evaluate(observations)
      )
    } catch {
      // Vision landmarks can be unavailable for low-information inputs and in
      // some simulator runtimes. A rectangle pass can still distinguish a
      // confirmed no-face input from a face whose landmarks are unavailable.
      let rectangleRequest = VNDetectFaceRectanglesRequest()
      let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
      do {
        try handler.perform([rectangleRequest])
        let observations = rectangleRequest.results ?? []
        faceCount = observations.count
        if let face = observations.first {
          portraitStatus = IOSPortraitCapabilityPolicy.classify(
            IOSPortraitSafetyPolicy.evaluate(
              faceCount: observations.count,
              confidence: face.confidence,
              boundingBox: face.boundingBox,
              hasLandmarks: false
            )
          )
        } else {
          portraitStatus = IOSPortraitCapabilityPolicy.classify(
            IOSPortraitSafetyDecision(applicable: false, reason: .noFace)
          )
        }
      } catch {
        faceCount = 0
        portraitStatus = IOSPortraitCapabilityStatus(
          applicability: "unavailable",
          reason: "capabilityUnavailable"
        )
      }
    }
    return [
      "analysisVersion": "local-pixels-v1",
      "capabilityVersion": "ios-core-image-vision-v3-portrait-locked",
      "confidence": "medium",
      "exposure": exposure,
      "whiteBalance": whiteBalance,
      "clarity": clarity,
      "portrait": portraitStatus.applicability,
      "portraitReason": portraitStatus.reason,
      "scene": faceCount == 0 ? "unknown" : "people",
    ]
  }

#if DEBUG
  private func configurePortraitMaskSpike(messenger: FlutterBinaryMessenger) {
    portraitMaskSpikeStartupError = nil
    do {
      try PortraitMaskSpike.discardAllCaptures()
    } catch let error as PortraitMaskSpikeError {
      portraitMaskSpikeStartupError = error
    } catch {
      portraitMaskSpikeStartupError = PortraitMaskSpikeError.cleanupFailed
    }
    let channel = FlutterMethodChannel(
      name: "yingjian/portrait_mask_spike",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "analyzePortrait" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if let error = self?.portraitMaskSpikeStartupError {
        result(FlutterError(code: error.code, message: error.message, details: nil))
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
    let temporaryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("Yingjian_\(UUID().uuidString).jpg")
    let artifact: IOSPhotoRenderedFile
    do {
      artifact = try IOSPhotoFileRenderer(context: photoExportContext).render(
        sourcePath: sourcePath,
        pipeline: pipeline,
        destinationURL: temporaryURL
      )
    } catch IOSPhotoFileRenderError.decodeFailed {
      finishWithError(code: "decodeFailed", message: "Photo could not be decoded", result: result)
      return
    } catch {
      finishWithError(code: "renderFailed", message: "Photo could not be rendered", result: result)
      return
    }

    var assetId: String?
    PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      request.creationDate = ImageExportMetadata.captureDate(from: artifact.metadata)
      let options = PHAssetResourceCreationOptions()
      options.originalFilename = "Yingjian_\(Int(Date().timeIntervalSince1970)).jpg"
      request.addResource(with: .photo, fileURL: temporaryURL, options: options)
      assetId = request.placeholderForCreatedAsset?.localIdentifier
    } completionHandler: { success, _ in
      DispatchQueue.main.async {
        guard success, let assetId else {
          try? FileManager.default.removeItem(at: temporaryURL)
          result(FlutterError(code: "saveFailed", message: "Photo could not be saved", details: nil))
          return
        }
        result([
          "assetId": assetId,
          "width": artifact.width,
          "height": artifact.height,
          "sharePath": temporaryURL.path,
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
enum PortraitMaskSpike {
  static let candidateKind = IOSPortraitRetoucher.candidateKind
  static let effectVersion = IOSPortraitRetoucher.effectVersion
  private static let maxEdge: CGFloat = 1_600
  private static let maxPixels = 48_000_000
  private static let maxSourceEdge = 12_000
  private static let maxFileBytes = 100 * 1024 * 1024
  private static let context = CIContext(options: [.cacheIntermediates: false])
  private static let captureLock = NSLock()

  private static var captureRoot: URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("portrait-mask-spike", isDirectory: true)
  }

  static func discardAllCaptures() throws {
    captureLock.lock()
    defer { captureLock.unlock() }
    try removeCaptureRoot()
  }

  static func analyze(sourcePath: String) throws -> [String: Any] {
    captureLock.lock()
    defer { captureLock.unlock() }
    let sourceURL = URL(fileURLWithPath: sourcePath)
    try validateInput(sourceURL)
    try removeCaptureRoot()
    guard let input = CIImage(
      contentsOf: sourceURL,
      options: [.applyOrientationProperty: true]
    ) else {
      throw PortraitMaskSpikeError(code: "decodeFailed", message: "Photo could not be decoded")
    }
    let normalized = input.transformed(
      by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY)
    )
    let sourceExtent = normalized.extent.integral
    let source = normalized.cropped(to: sourceExtent)
    let longestEdge = max(normalized.extent.width, normalized.extent.height)
    guard longestEdge > 0 else {
      throw PortraitMaskSpikeError(code: "decodeFailed", message: "Photo dimensions are invalid")
    }
    let scale = min(1, maxEdge / longestEdge)
    let proxy = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
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
    let masks = try IOSPortraitRetoucher.masks(
      observations: observations,
      extent: extent
    )
    let candidateImage = masks.candidate
    let protectionImage = masks.protection
    let effectiveImage = masks.effective
    let safetyDecision = IOSPortraitSafetyPolicy.evaluate(observations)

    let directory = captureRoot
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    do {
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
      let defaultPreview = IOSPortraitRetoucher.candidate(
        source: proxy,
        mask: effectiveImage,
        strength: safetyDecision.applicable ? 0.35 : 0,
        extent: extent
      )
      let defaultPreviewPath = try writePNG(
        defaultPreview,
        extent: extent,
        to: directory.appendingPathComponent("candidate-default-preview.png")
      )

      let exportMetadata = ImageExportMetadata.sanitize(input.properties)
      let baselineURL = directory.appendingPathComponent("baseline-original.jpg")
      let offExportURL = directory.appendingPathComponent("yingjian-off-export.jpg")
      let defaultExportURL = directory.appendingPathComponent("yingjian-default-export.jpg")
      let highSafeExportURL = directory.appendingPathComponent("yingjian-high-safe-export.jpg")
      try writeJPEG(
        source.settingProperties(exportMetadata),
        extent: sourceExtent,
        to: baselineURL
      )
      try FileManager.default.copyItem(at: baselineURL, to: offExportURL)

      if !safetyDecision.applicable {
        try FileManager.default.copyItem(at: baselineURL, to: defaultExportURL)
        try FileManager.default.copyItem(at: baselineURL, to: highSafeExportURL)
      } else {
        let candidates = fullResolutionCandidates(
          source: source,
          effectiveProxyMask: effectiveImage,
          proxyExtent: extent,
          sourceExtent: sourceExtent
        )
        try writeJPEG(
          candidates.defaultImage.settingProperties(exportMetadata),
          extent: sourceExtent,
          to: defaultExportURL
        )
        try writeJPEG(
          candidates.highSafeImage.settingProperties(exportMetadata),
          extent: sourceExtent,
          to: highSafeExportURL
        )
      }

      let manifestURL = directory.appendingPathComponent("capture-manifest.json")
      let rawSourceSha256 = try sha256(sourceURL)
      let captureRelativePath = "tmp/portrait-mask-spike/\(directory.lastPathComponent)"
      let result: [String: Any] = [
        "faceCount": observations.count,
        "candidateApplicable": safetyDecision.applicable,
        "degradationReason": safetyDecision.reason.rawValue,
        "width": width,
        "height": height,
        "sourceWidth": Int(sourceExtent.width),
        "sourceHeight": Int(sourceExtent.height),
        "sourceProxyPath": sourceProxyPath,
        "candidateMaskPath": candidatePath,
        "protectionMaskPath": protectionPath,
        "effectiveMaskPath": effectivePath,
        "overlayPath": overlayPath,
        "offPath": offExportURL.path,
        "defaultPath": defaultPreviewPath,
        "highSafePath": highSafeExportURL.path,
        "baselineOriginalPath": baselineURL.path,
        "offExportPath": offExportURL.path,
        "defaultExportPath": defaultExportURL.path,
        "highSafeExportPath": highSafeExportURL.path,
        "defaultPreviewPath": defaultPreviewPath,
        "captureManifestPath": manifestURL.path,
        "captureRelativePath": captureRelativePath,
        "candidateKind": candidateKind,
        "geometryOnly": true,
        "effectVersion": effectVersion,
        "defaultStrength": 0.35,
        "highSafeStrength": 0.55,
        "productionEligible": false,
        "executionEnvironment": executionEnvironment,
        "landmarkSummary": landmarkSummary(observations.first?.landmarks),
        "landmarkBoundsSummary": landmarkBoundsSummary(observations.first?.landmarks),
      ]
      try writeCaptureManifest(
        to: manifestURL,
        rawSourceSha256: rawSourceSha256,
        sourceWidth: Int(sourceExtent.width),
        sourceHeight: Int(sourceExtent.height),
        faceCount: observations.count,
        safetyDecision: safetyDecision,
        baselineURL: baselineURL,
        offExportURL: offExportURL,
        defaultExportURL: defaultExportURL,
        highSafeExportURL: highSafeExportURL,
        defaultPreviewURL: URL(fileURLWithPath: defaultPreviewPath)
      )
      return result
    } catch {
      do {
        try removeItemIfPresent(directory)
      } catch {
        throw PortraitMaskSpikeError.cleanupFailed
      }
      throw error
    }
  }

  static func removeCaptureRoot(
    removeItem: (URL) throws -> Void
  ) throws {
    guard FileManager.default.fileExists(atPath: captureRoot.path) else { return }
    do {
      try removeItem(captureRoot)
    } catch {
      throw PortraitMaskSpikeError.cleanupFailed
    }
  }

  private static func removeCaptureRoot() throws {
    try removeCaptureRoot { url in
      try FileManager.default.removeItem(at: url)
    }
  }

  private static func removeItemIfPresent(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  static func validateDimensions(
    width: Int,
    height: Int,
    fileBytes: Int,
    isSupportedFormat: Bool,
    imageCount: Int
  ) throws {
    guard fileBytes > 0, fileBytes <= maxFileBytes else {
      throw PortraitMaskSpikeError(code: "inputTooLarge", message: "Photo exceeds 100 MB")
    }
    guard isSupportedFormat, imageCount == 1 else {
      throw PortraitMaskSpikeError(
        code: "unsupportedInput",
        message: "Portrait spike supports one JPEG, PNG, HEIC, or HEIF image"
      )
    }
    guard width > 0, height > 0 else {
      throw PortraitMaskSpikeError(code: "decodeFailed", message: "Photo dimensions are invalid")
    }
    guard width <= maxSourceEdge, height <= maxSourceEdge else {
      throw PortraitMaskSpikeError(code: "inputTooLarge", message: "Photo edge exceeds 12,000 px")
    }
    guard width <= maxPixels / height else {
      throw PortraitMaskSpikeError(code: "inputTooLarge", message: "Photo exceeds 48 MP")
    }
  }

  private static func validateInput(_ url: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let fileBytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
    guard fileBytes > 0, fileBytes <= maxFileBytes else {
      throw PortraitMaskSpikeError(code: "inputTooLarge", message: "Photo exceeds 100 MB")
    }
    guard
      let source = CGImageSourceCreateWithURL(
        url as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary
      ),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
    else {
      throw PortraitMaskSpikeError(code: "decodeFailed", message: "Photo could not be inspected")
    }
    let type = (CGImageSourceGetType(source) as String?)?.lowercased() ?? ""
    let supported = type.contains("jpeg") || type.contains("png") ||
      type.contains("heic") || type.contains("heif")
    try validateDimensions(
      width: width,
      height: height,
      fileBytes: fileBytes,
      isSupportedFormat: supported,
      imageCount: CGImageSourceGetCount(source)
    )
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

  /// Debug candidate only. The geometry ROI is intentionally conservative and
  /// must pass the frozen portrait corpus before any production integration.
  static func candidate(
    source: CIImage,
    mask: CIImage,
    strength: Double,
    extent: CGRect
  ) -> CIImage {
    IOSPortraitRetoucher.candidate(
      source: source,
      mask: mask,
      strength: strength,
      extent: extent
    )
  }

  static func fullResolutionCandidates(
    source: CIImage,
    effectiveProxyMask: CIImage,
    proxyExtent: CGRect,
    sourceExtent: CGRect
  ) -> (defaultImage: CIImage, highSafeImage: CIImage) {
    let fullMask = effectiveProxyMask.transformed(
      by: CGAffineTransform(
        scaleX: sourceExtent.width / proxyExtent.width,
        y: sourceExtent.height / proxyExtent.height
      )
    ).cropped(to: sourceExtent)
    return (
      candidate(source: source, mask: fullMask, strength: 0.35, extent: sourceExtent),
      candidate(source: source, mask: fullMask, strength: 0.55, extent: sourceExtent)
    )
  }

  private static func writePNG(_ image: CIImage, extent: CGRect, to url: URL) throws -> String {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw PortraitMaskSpikeError(code: "renderFailed", message: "sRGB is unavailable")
    }
    do {
      try context.writePNGRepresentation(
        of: image.cropped(to: extent),
        to: url,
        format: .RGBA8,
        colorSpace: colorSpace,
        options: [:]
      )
    } catch {
      throw PortraitMaskSpikeError(code: "writeFailed", message: "Debug image could not be written")
    }
    return url.path
  }

  private static func writeJPEG(_ image: CIImage, extent: CGRect, to url: URL) throws {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw PortraitMaskSpikeError(code: "renderFailed", message: "sRGB is unavailable")
    }
    do {
      try context.writeJPEGRepresentation(
        of: image.cropped(to: extent),
        to: url,
        colorSpace: colorSpace,
        options: [
          kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
        ]
      )
    } catch {
      throw PortraitMaskSpikeError(
        code: "writeFailed",
        message: "Full-resolution candidate could not be written"
      )
    }
  }

  private static func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
      if data.isEmpty { break }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func writeCaptureManifest(
    to url: URL,
    rawSourceSha256: String,
    sourceWidth: Int,
    sourceHeight: Int,
    faceCount: Int,
    safetyDecision: IOSPortraitSafetyDecision,
    baselineURL: URL,
    offExportURL: URL,
    defaultExportURL: URL,
    highSafeExportURL: URL,
    defaultPreviewURL: URL
  ) throws {
    func output(_ outputURL: URL, variant: String, renderKind: String) throws -> [String: Any] {
      [
        "file": outputURL.lastPathComponent,
        "sha256": try sha256(outputURL),
        "variant": variant,
        "renderKind": renderKind,
      ]
    }
    let manifest: [String: Any] = [
      "schema": 2,
      "candidateKind": candidateKind,
      "effectVersion": effectVersion,
      "productionEligible": false,
      "executionEnvironment": executionEnvironment,
      "device": hardwareIdentifier,
      "os": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
      "appVersion": Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "unknown",
      "appBuild": Bundle.main.object(
        forInfoDictionaryKey: kCFBundleVersionKey as String
      ) as? String ?? "unknown",
      "capturedAtUtc": ISO8601DateFormatter().string(from: Date()),
      "rawSourceSha256": rawSourceSha256,
      "sourceWidth": sourceWidth,
      "sourceHeight": sourceHeight,
      "faceCount": faceCount,
      "candidateApplicable": safetyDecision.applicable,
      "degradationReason": safetyDecision.reason.rawValue,
      "defaultStrength": 0.35,
      "highSafeStrength": 0.55,
      "outputs": [
        "baselineOriginal": try output(
          baselineURL,
          variant: "original",
          renderKind: "source"
        ),
        "offExport": try output(offExportURL, variant: "off", renderKind: "export"),
        "defaultExport": try output(
          defaultExportURL,
          variant: "default",
          renderKind: "export"
        ),
        "highSafeExport": try output(
          highSafeExportURL,
          variant: "high_safe",
          renderKind: "export"
        ),
        "defaultPreview": try output(
          defaultPreviewURL,
          variant: "default",
          renderKind: "preview"
        ),
      ],
    ]
    do {
      let data = try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys]
      )
      try data.write(to: url, options: .atomic)
    } catch {
      throw PortraitMaskSpikeError(
        code: "writeFailed",
        message: "Candidate capture manifest could not be written"
      )
    }
  }

  private static var hardwareIdentifier: String {
#if targetEnvironment(simulator)
    if let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
       !identifier.isEmpty {
      return identifier
    }
#endif
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafeBytes(of: &systemInfo.machine) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
  }
}

struct PortraitMaskSpikeError: Error {
  let code: String
  let message: String

  static let cleanupFailed = PortraitMaskSpikeError(
    code: "cleanupFailed",
    message: "Previous portrait capture could not be removed"
  )
}
#endif
