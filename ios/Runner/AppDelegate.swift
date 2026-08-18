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

/// Reports whether the deterministic local portrait implementation can be used
/// for this input. Quality acceptance remains a separate release gate.
struct IOSPortraitCapabilityStatus: Equatable {
  let applicability: String
  let reason: String
}

enum IOSPortraitCapabilityPolicy {
  static let productionEligible = true

  static func classify(_ decision: IOSPortraitSafetyDecision) -> IOSPortraitCapabilityStatus {
    guard decision.applicable else {
      let applicability = decision.reason == .noFace ? "unavailable" : "unsafe"
      return IOSPortraitCapabilityStatus(
        applicability: applicability,
        reason: reasonName(decision.reason)
      )
    }
    return IOSPortraitCapabilityStatus(applicability: "applicable", reason: "none")
  }

  static func classify(
    _ decision: IOSMultiFaceNonGeometricSafetyDecision
  ) -> IOSPortraitCapabilityStatus {
    if !decision.applicableFaceIndices.isEmpty {
      return IOSPortraitCapabilityStatus(applicability: "applicable", reason: "none")
    }
    switch decision.sceneReason {
    case .noFace:
      return IOSPortraitCapabilityStatus(applicability: "unavailable", reason: "noFace")
    case .tooManyFaces:
      return IOSPortraitCapabilityStatus(applicability: "unsafe", reason: "multipleFaces")
    case .noEligibleFace:
      let reasons = Set(decision.rejectedFaces.values)
      let reason: String
      if reasons.contains(.lowConfidence) {
        reason = "lowConfidence"
      } else if reasons.contains(.faceTooSmall) {
        reason = "faceTooSmall"
      } else {
        reason = "landmarksUnavailable"
      }
      return IOSPortraitCapabilityStatus(applicability: "unsafe", reason: reason)
    case .none:
      return IOSPortraitCapabilityStatus(applicability: "unsafe", reason: "capabilityUnavailable")
    }
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
  private var photoPickerChannel: FlutterMethodChannel?
  private var photoInputChannel: FlutterMethodChannel?
  private var photoAnalysisChannel: FlutterMethodChannel?
  private var speechTranscriptionChannel: FlutterMethodChannel?
  private var photoPreviewRenderer: IOSPhotoPreviewRenderer?
  private let photoExportContext = CIContext(options: [.cacheIntermediates: false])
  private var photoShareInProgress = false
  private let photoPicker = IOSPhotoPicker()
  private let speechTranscriber = IOSSpeechTranscriber()
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
    configurePhotoPicker(messenger: registrar.messenger())
    configurePhotoShare(messenger: registrar.messenger())
    configurePhotoInput(messenger: registrar.messenger())
    configurePhotoAnalysis(messenger: registrar.messenger())
    configureSpeechTranscription(messenger: registrar.messenger())
    photoPreviewRenderer = IOSPhotoPreviewRenderer(
      messenger: registrar.messenger(),
      textureRegistry: registrar.textures()
    )
#if DEBUG
    configurePortraitMaskSpike(messenger: registrar.messenger())
#endif
  }

  private func configureSpeechTranscription(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "yingjian/speech_transcription",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "speechUnavailable",
          message: "Speech transcription is unavailable",
          details: nil
        ))
        return
      }
      switch call.method {
      case "startTranscription":
        guard
          let arguments = call.arguments as? [String: Any],
          let localeIdentifier = arguments["localeIdentifier"] as? String,
          !localeIdentifier.isEmpty
        else {
          result(FlutterError(
            code: "invalidArguments",
            message: "A locale identifier is required",
            details: nil
          ))
          return
        }
        self.speechTranscriber.start(
          localeIdentifier: localeIdentifier,
          result: result
        )
      case "stopTranscription":
        self.speechTranscriber.stop(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    speechTranscriptionChannel = channel
  }

  private func configurePhotoPicker(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "yingjian/photo_picker",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "pickPhotos":
        guard
          let values = call.arguments as? [String: Any],
          let limit = values["limit"] as? Int,
          (1...6).contains(limit),
          let presenter = self?.topViewController()
        else {
          result(FlutterError(
            code: "invalidArguments",
            message: "Photo picker requires a visible presenter and a 1...6 limit",
            details: nil
          ))
          return
        }
        self?.photoPicker.pickPhotos(
          limit: limit,
          presenter: presenter,
          completion: result
        )
      case "discardPhotos":
        guard
          let values = call.arguments as? [String: Any],
          let paths = values["paths"] as? [String],
          !paths.isEmpty,
          paths.count <= 6
        else {
          result(FlutterError(
            code: "invalidArguments",
            message: "Photo picker cleanup requires 1...6 paths",
            details: nil
          ))
          return
        }
        guard let self else {
          result(FlutterError(
            code: "pickerUnavailable",
            message: "Photo picker is no longer available",
            details: nil
          ))
          return
        }
        do {
          try self.photoPicker.discard(paths: paths)
          result(nil)
        } catch {
          result(FlutterError(
            code: "discardFailed",
            message: "Temporary picker files could not be removed",
            details: nil
          ))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    photoPickerChannel = channel
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
    let pixelOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 128,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(
      source,
      0,
      pixelOptions as CFDictionary
    ) else {
      throw PhotoInputInspectionError.unreadable
    }
    // Pixel statistics stay deliberately small, while Vision receives enough
    // detail for face landmarks and shoulder/hip pose on full-body photos.
    let visionOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(IOSPortraitRetoucher.analysisMaxEdge),
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let visionImage = CGImageSourceCreateThumbnailAtIndex(
      source,
      0,
      visionOptions as CFDictionary
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
#if targetEnvironment(simulator)
    // Vision's default compute-device selection can reject face requests on
    // some simulator runtimes even though the same image is supported on
    // hardware. Keep Simulator production journeys on the CPU so local
    // applicability is observable instead of silently cached as unavailable.
    landmarkRequest.usesCPUOnly = true
#endif
    do {
      let handler = VNImageRequestHandler(cgImage: visionImage, orientation: .up)
      try handler.perform([landmarkRequest])
      let observations = landmarkRequest.results ?? []
      faceCount = observations.count
      let descriptors = observations.map {
        IOSNonGeometricFaceDescriptor(
          confidence: $0.confidence,
          boundingBox: $0.boundingBox,
          hasLandmarks: $0.landmarks != nil
        )
      }
      portraitStatus = IOSPortraitCapabilityPolicy.classify(
        IOSMultiFaceNonGeometricSafetyPolicy.evaluate(
          faces: descriptors,
          imageSize: CGSize(width: visionImage.width, height: visionImage.height)
        )
      )
    } catch {
      // Vision landmarks can be unavailable for low-information inputs and in
      // some simulator runtimes. A rectangle pass can still distinguish a
      // confirmed no-face input from a face whose landmarks are unavailable.
      let rectangleRequest = VNDetectFaceRectanglesRequest()
#if targetEnvironment(simulator)
      rectangleRequest.usesCPUOnly = true
#endif
      let handler = VNImageRequestHandler(cgImage: visionImage, orientation: .up)
      do {
        try handler.perform([rectangleRequest])
        let observations = rectangleRequest.results ?? []
        faceCount = observations.count
        if !observations.isEmpty {
          let descriptors = observations.map {
            IOSNonGeometricFaceDescriptor(
              confidence: $0.confidence,
              boundingBox: $0.boundingBox,
              hasLandmarks: false
            )
          }
          portraitStatus = IOSPortraitCapabilityPolicy.classify(
            IOSMultiFaceNonGeometricSafetyPolicy.evaluate(
              faces: descriptors,
              imageSize: CGSize(width: visionImage.width, height: visionImage.height)
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
    let imageExtent = CGRect(
      x: 0,
      y: 0,
      width: visionImage.width,
      height: visionImage.height
    )
    let reshapeContext = IOSPortraitRetoucher.prepare(
      source: CIImage(cgImage: visionImage),
      extent: imageExtent
    )
    let faceSlimTargetCount = reshapeContext.faceSlimTargets.count
    let faceSlimApplicable = faceSlimTargetCount > 0
    let faceSlimReason: String
    if faceSlimApplicable {
      faceSlimReason = "none"
    } else if portraitStatus.applicability != "applicable" {
      faceSlimReason = portraitStatus.reason
    } else {
      faceSlimReason = "backgroundRisk"
    }
    let bodyTargetCount = reshapeContext.bodyReshapeTargets.count
    let bodyApplicable = bodyTargetCount > 0
    func normalizedTargetRegion(_ rawRect: CGRect) -> [String: Double]? {
      let rect = rawRect.intersection(imageExtent)
      guard rect.width > 0, rect.height > 0 else { return nil }
      return [
        "left": Double(rect.minX / imageExtent.width),
        "top": Double(1 - (rect.maxY / imageExtent.height)),
        "right": Double(rect.maxX / imageExtent.width),
        "bottom": Double(1 - (rect.minY / imageExtent.height)),
      ]
    }
    let faceTargetRegions = reshapeContext.faceSlimTargets.compactMap {
      normalizedTargetRegion($0.features.faceBounds)
    }
    let bodyTargetRegions = reshapeContext.bodyReshapeTargets.compactMap { target in
      let influence = target.geometry.influenceRect
      return normalizedTargetRegion(
        influence.insetBy(
          dx: -influence.width * 0.15,
          dy: -influence.height * 0.12
        )
      )
    }
    return [
      "analysisVersion": "local-pixels-v1",
      "capabilityVersion": "ios-core-image-vision-v14-target-regions",
      "confidence": "medium",
      "exposure": exposure,
      "whiteBalance": whiteBalance,
      "clarity": clarity,
      "portrait": portraitStatus.applicability,
      "portraitReason": portraitStatus.reason,
      "faceSlim": faceSlimApplicable ? "applicable" :
        (portraitStatus.applicability == "unavailable" ? "unavailable" : "unsafe"),
      "faceSlimReason": faceSlimReason,
      "faceSlimTargetCount": faceSlimTargetCount,
      "faceTargetRegions": faceTargetRegions,
      "body": bodyApplicable ? "applicable" : "unavailable",
      "bodyTargetCount": bodyTargetCount,
      "bodyTargetRegions": bodyTargetRegions,
      "scene": faceCount == 0 && !bodyApplicable ? "unknown" : "people",
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
      let pipeline = IOSImagePipeline(arguments: values["pipeline"]),
      let options = IOSPhotoExportOptions(arguments: values["options"])
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
          options: options,
          result: result
        )
      }
    }
  }

  private func renderAndSave(
    sourcePath: String,
    pipeline: IOSImagePipeline,
    options: IOSPhotoExportOptions,
    result: @escaping FlutterResult
  ) {
    let fileExtension = options.format == "heif" ? "heic" : "jpg"
    let temporaryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("Yingjian_\(UUID().uuidString).\(fileExtension)")
    let artifact: IOSPhotoRenderedFile
    do {
      artifact = try IOSPhotoFileRenderer(context: photoExportContext).render(
        sourcePath: sourcePath,
        pipeline: pipeline,
        destinationURL: temporaryURL,
        options: options
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
      options.originalFilename = "Yingjian_\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
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

final class IOSPhotoPreviewSession: NSObject, FlutterTexture {
  private static let context = CIContext(options: [.cacheIntermediates: false])
  private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  let width: Int
  let height: Int

  private let source: CIImage
  private let extent: CGRect
  private let portraitContext: IOSPortraitRetouchContext
  private let bufferLock = NSLock()
  private var pixelBuffer: CVPixelBuffer?
  private var isClosed = false

  init(
    sourcePath: String,
    maxEdge: Int,
    pipeline: IOSImagePipeline,
    preparedPortraitContext: IOSPortraitRetouchContext? = nil
  ) throws {
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
    portraitContext = preparedPortraitContext ?? IOSPortraitRetoucher.prepare(
      source: source,
      extent: sourceExtent
    )
    let initialOutput = pipeline.applying(
      to: source,
      extent: sourceExtent,
      portraitContext: portraitContext
    )
    extent = initialOutput.extent.integral
    width = Int(extent.width)
    height = Int(extent.height)
    super.init()
    try render(pipeline: pipeline)
  }

  func render(pipeline: IOSImagePipeline) throws {
    let output = pipeline.applying(
      to: source,
      extent: source.extent.integral,
      portraitContext: portraitContext
    )
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
    let safetyDecision = IOSPortraitSafetyPolicy.evaluate(
      observations,
      imageSize: extent.size
    )

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
