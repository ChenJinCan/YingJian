import CoreImage
import CryptoKit
import Flutter
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum IOSGenerationUploadError: Error {
  case invalidArguments
  case unsupportedCapability
  case unreadableSource
  case dimensionsUnsupported
  case encodingFailed
  case mediaTooLarge
  case maskMismatch
}

struct IOSGenerationUploadPolicy {
  let minDimension: Int
  let maxDimension: Int
  let maxBytes: Int
  let maxAspectRatio: Double
  let requiresMask: Bool

  static let maxPixels = 40_000_000

  static func policy(for capability: String) throws -> Self {
    let mib = 1024 * 1024
    switch capability {
    case "optimize.aiRepair":
      // Baidu's 10 MiB request contract applies after base64 expansion.
      return Self(
        minDimension: 10,
        maxDimension: 5_000,
        maxBytes: 10 * mib * 3 / 4,
        maxAspectRatio: 4,
        requiresMask: false
      )
    case "optimize.oldPhoto":
      return Self(
        minDimension: 10,
        maxDimension: 8_000,
        maxBytes: 10 * mib,
        maxAspectRatio: 8,
        requiresMask: false
      )
    case "style.aiRedraw", "motion.aiNatural":
      return Self(
        minDimension: 240,
        maxDimension: 8_000,
        maxBytes: 20 * mib,
        maxAspectRatio: 8,
        requiresMask: false
      )
    case "cleanup.removePasserby", "cleanup.brushRemove":
      return Self(
        minDimension: 512,
        maxDimension: 4_096,
        maxBytes: 10 * mib,
        maxAspectRatio: 8,
        requiresMask: true
      )
    default:
      throw IOSGenerationUploadError.unsupportedCapability
    }
  }
}

private struct IOSGenerationUploadRequest {
  let clientRequestId: String
  let capability: String
  let sourcePath: String
  let maskPath: String?

  init(arguments: Any?) throws {
    guard
      let values = arguments as? [String: Any],
      let clientRequestId = values["clientRequestId"] as? String,
      !clientRequestId.isEmpty,
      let capability = values["capability"] as? String,
      !capability.isEmpty,
      let sourcePath = values["sourcePath"] as? String,
      !sourcePath.isEmpty
    else {
      throw IOSGenerationUploadError.invalidArguments
    }
    let policy = try IOSGenerationUploadPolicy.policy(for: capability)
    let maskPath = values["maskPath"] as? String
    let maskSha256 = values["maskSha256"] as? String
    if policy.requiresMask {
      guard
        let maskPath,
        !maskPath.isEmpty,
        let maskSha256,
        maskSha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
      else {
        throw IOSGenerationUploadError.invalidArguments
      }
    } else if maskPath != nil || maskSha256 != nil {
      throw IOSGenerationUploadError.invalidArguments
    }
    self.clientRequestId = clientRequestId
    self.capability = capability
    self.sourcePath = sourcePath
    self.maskPath = maskPath
  }
}

private struct IOSCanonicalSource {
  let data: Data
  let fileExtension: String
  let width: Int
  let height: Int
  let orientedWidth: CGFloat
  let orientedHeight: CGFloat
}

private struct IOSCanonicalUploadArtifact {
  let sourceURL: URL
  let sourceSha256: String
  let maskURL: URL?
  let maskSha256: String?
  let cleanupToken: String
}

/// Produces provider-bounded, orientation-normalized upload proxies without
/// touching the immutable application-owned source. It never chooses or
/// changes a capability; the caller supplies the user's confirmed capability.
private final class IOSGenerationUploadRenderer {
  private let context: CIContext
  private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

  init(context: CIContext) {
    self.context = context
  }

  func prepare(
    request: IOSGenerationUploadRequest,
    directory: URL,
    cleanupToken: String
  ) throws -> IOSCanonicalUploadArtifact {
    let policy = try IOSGenerationUploadPolicy.policy(for: request.capability)
    let source = try canonicalSource(
      at: URL(fileURLWithPath: request.sourcePath),
      policy: policy
    )
    let sourceURL = directory
      .appendingPathComponent("source", isDirectory: false)
      .appendingPathExtension(source.fileExtension)
    try source.data.write(to: sourceURL, options: .atomic)

    var maskURL: URL?
    var maskSha256: String?
    if let maskPath = request.maskPath {
      let data = try canonicalMask(
        at: URL(fileURLWithPath: maskPath),
        source: source,
        policy: policy
      )
      let output = directory
        .appendingPathComponent("mask", isDirectory: false)
        .appendingPathExtension("png")
      try data.write(to: output, options: .atomic)
      maskURL = output
      maskSha256 = Self.sha256(data)
    }

    return IOSCanonicalUploadArtifact(
      sourceURL: sourceURL,
      sourceSha256: Self.sha256(source.data),
      maskURL: maskURL,
      maskSha256: maskSha256,
      cleanupToken: cleanupToken
    )
  }

  private func canonicalSource(
    at url: URL,
    policy: IOSGenerationUploadPolicy
  ) throws -> IOSCanonicalSource {
    guard
      let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(imageSource) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
        as? [CFString: Any],
      let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
      rawWidth.intValue > 0,
      rawHeight.intValue > 0,
      let input = CIImage(
        contentsOf: url,
        options: [.applyOrientationProperty: false]
      )
    else {
      throw IOSGenerationUploadError.unreadableSource
    }
    let declaredOrientation =
      (properties[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
    let orientation = (1...8).contains(Int(declaredOrientation))
      ? declaredOrientation
      : 1
    let oriented = normalized(input.oriented(forExifOrientation: orientation))
    let orientedWidth = oriented.extent.width
    let orientedHeight = oriented.extent.height
    guard
      orientedWidth.isFinite,
      orientedHeight.isFinite,
      orientedWidth > 0,
      orientedHeight > 0
    else {
      throw IOSGenerationUploadError.unreadableSource
    }
    let shortest = min(orientedWidth, orientedHeight)
    let longest = max(orientedWidth, orientedHeight)
    guard
      shortest >= CGFloat(policy.minDimension),
      longest / shortest <= policy.maxAspectRatio
    else {
      throw IOSGenerationUploadError.dimensionsUnsupported
    }

    var scale = min(1, CGFloat(policy.maxDimension) / longest)
    let rawPixels = orientedWidth * orientedHeight
    if rawPixels * scale * scale > CGFloat(IOSGenerationUploadPolicy.maxPixels) {
      scale = min(
        scale,
        sqrt(CGFloat(IOSGenerationUploadPolicy.maxPixels) / rawPixels)
      )
    }
    let hasAlpha = Self.hasAlpha(imageSource)
    for _ in 0..<12 {
      let width = max(1, Int((orientedWidth * scale).rounded()))
      let height = max(1, Int((orientedHeight * scale).rounded()))
      guard
        width >= policy.minDimension,
        height >= policy.minDimension,
        width <= policy.maxDimension,
        height <= policy.maxDimension,
        width * height <= IOSGenerationUploadPolicy.maxPixels
      else {
        throw IOSGenerationUploadError.dimensionsUnsupported
      }
      let scaled = oriented
        .transformed(by: CGAffineTransform(
          scaleX: CGFloat(width) / orientedWidth,
          y: CGFloat(height) / orientedHeight
        ))
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
      if hasAlpha {
        let data = try encode(scaled, width: width, height: height, asPng: true)
        if data.count <= policy.maxBytes {
          return IOSCanonicalSource(
            data: data,
            fileExtension: "png",
            width: width,
            height: height,
            orientedWidth: orientedWidth,
            orientedHeight: orientedHeight
          )
        }
        scale = reducedScale(scale, byteCount: data.count, limit: policy.maxBytes)
      } else {
        var smallestByteCount = Int.max
        for quality in [0.92, 0.84, 0.76, 0.68] {
          let data = try encode(
            scaled,
            width: width,
            height: height,
            asPng: false,
            quality: quality
          )
          smallestByteCount = min(smallestByteCount, data.count)
          if data.count <= policy.maxBytes {
            return IOSCanonicalSource(
              data: data,
              fileExtension: "jpg",
              width: width,
              height: height,
              orientedWidth: orientedWidth,
              orientedHeight: orientedHeight
            )
          }
        }
        scale = reducedScale(
          scale,
          byteCount: smallestByteCount,
          limit: policy.maxBytes
        )
      }
    }
    throw IOSGenerationUploadError.mediaTooLarge
  }

  private func canonicalMask(
    at url: URL,
    source: IOSCanonicalSource,
    policy: IOSGenerationUploadPolicy
  ) throws -> Data {
    guard
      let input = CIImage(
        contentsOf: url,
        options: [.applyOrientationProperty: false]
      )
    else {
      throw IOSGenerationUploadError.maskMismatch
    }
    // Flutter draws this user-confirmed mask in the already EXIF-oriented
    // display coordinate system. Applying the source orientation again would
    // rotate or mirror the selected region a second time.
    let orientedMask = normalized(input)
    let maskWidth = orientedMask.extent.width
    let maskHeight = orientedMask.extent.height
    let sourceIsLandscape = source.orientedWidth >= source.orientedHeight
    let maskIsLandscape = maskWidth >= maskHeight
    let sourceAspect = source.orientedWidth / source.orientedHeight
    let maskAspect = maskWidth / maskHeight
    let aspectTolerance = max(0.002, 2 / min(maskWidth, maskHeight))
    guard
      maskWidth.isFinite,
      maskHeight.isFinite,
      maskWidth > 0,
      maskHeight > 0,
      sourceIsLandscape == maskIsLandscape,
      abs(maskAspect - sourceAspect) / sourceAspect <= aspectTolerance
    else {
      throw IOSGenerationUploadError.maskMismatch
    }
    let scaled = orientedMask
      .transformed(by: CGAffineTransform(
        scaleX: CGFloat(source.width) / maskWidth,
        y: CGFloat(source.height) / maskHeight
      ))
      .cropped(to: CGRect(
        x: 0,
        y: 0,
        width: source.width,
        height: source.height
      ))
    var rgba = [UInt8](repeating: 0, count: source.width * source.height * 4)
    rgba.withUnsafeMutableBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      context.render(
        scaled,
        toBitmap: baseAddress,
        rowBytes: source.width * 4,
        bounds: CGRect(x: 0, y: 0, width: source.width, height: source.height),
        format: .RGBA8,
        colorSpace: colorSpace
      )
    }
    var grayscale = [UInt8](repeating: 0, count: source.width * source.height)
    for index in grayscale.indices {
      let offset = index * 4
      // Requiring fully white source samples is conservative: resampling may
      // shrink an edge by a pixel but can never expand the user's selection.
      grayscale[index] =
        rgba[offset] == 255 &&
        rgba[offset + 1] == 255 &&
        rgba[offset + 2] == 255 &&
        rgba[offset + 3] == 255
        ? 255
        : 0
    }
    let data = try encodeGrayscalePng(
      grayscale,
      width: source.width,
      height: source.height
    )
    guard data.count <= policy.maxBytes else {
      throw IOSGenerationUploadError.mediaTooLarge
    }
    return data
  }

  private func encode(
    _ image: CIImage,
    width: Int,
    height: Int,
    asPng: Bool,
    quality: Double = 1
  ) throws -> Data {
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    guard let rendered = context.createCGImage(
      image,
      from: bounds,
      format: .RGBA8,
      colorSpace: colorSpace
    ) else {
      throw IOSGenerationUploadError.encodingFailed
    }
    return try Self.encodeImage(rendered, asPng: asPng, quality: quality)
  }

  private func encodeGrayscalePng(
    _ pixels: [UInt8],
    width: Int,
    height: Int
  ) throws -> Data {
    guard
      let provider = CGDataProvider(data: Data(pixels) as CFData),
      let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    else {
      throw IOSGenerationUploadError.encodingFailed
    }
    return try Self.encodeImage(image, asPng: true, quality: 1)
  }

  private static func encodeImage(
    _ image: CGImage,
    asPng: Bool,
    quality: Double
  ) throws -> Data {
    let data = NSMutableData()
    let type = asPng ? UTType.png.identifier : UTType.jpeg.identifier
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        type as CFString,
        1,
        nil
      )
    else {
      throw IOSGenerationUploadError.encodingFailed
    }
    var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
    if !asPng {
      properties[kCGImageDestinationLossyCompressionQuality] = quality
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw IOSGenerationUploadError.encodingFailed
    }
    return data as Data
  }

  private static func hasAlpha(_ source: CGImageSource) -> Bool {
    if
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let hasAlpha = properties[kCGImagePropertyHasAlpha] as? NSNumber
    {
      return hasAlpha.boolValue
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: 1,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
      source,
      0,
      options as CFDictionary
    ) else {
      return false
    }
    switch thumbnail.alphaInfo {
    case .first, .last, .premultipliedFirst, .premultipliedLast:
      return true
    case .none, .noneSkipFirst, .noneSkipLast, .alphaOnly:
      return false
    @unknown default:
      return false
    }
  }

  private func normalized(_ image: CIImage) -> CIImage {
    image.transformed(by: CGAffineTransform(
      translationX: -image.extent.minX,
      y: -image.extent.minY
    ))
  }

  private func reducedScale(_ scale: CGFloat, byteCount: Int, limit: Int) -> CGFloat {
    let ratio = sqrt(CGFloat(limit) / CGFloat(max(1, byteCount))) * 0.94
    return scale * min(0.90, max(0.50, ratio))
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

final class IOSGenerationUploadPreparerChannel {
  private static let retentionInterval: TimeInterval = 24 * 60 * 60

  private let channel: FlutterMethodChannel
  private let renderer: IOSGenerationUploadRenderer
  private let workQueue = DispatchQueue(
    label: "com.babycompany.yingjian.generation-upload",
    qos: .userInitiated
  )
  private let rootDirectory: URL

  init(
    messenger: FlutterBinaryMessenger,
    context: CIContext = CIContext(options: [.cacheIntermediates: false])
  ) {
    channel = FlutterMethodChannel(
      name: "yingjian/generation_upload",
      binaryMessenger: messenger
    )
    renderer = IOSGenerationUploadRenderer(context: context)
    rootDirectory = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    )[0].appendingPathComponent("generation-upload-proxies", isDirectory: true)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    workQueue.async { [weak self] in
      self?.cleanupExpiredDirectories()
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepareCanonicalUpload":
      workQueue.async { [weak self] in
        guard let self else { return }
        do {
          let request = try IOSGenerationUploadRequest(arguments: call.arguments)
          let artifact = try self.prepare(request)
          DispatchQueue.main.async {
            var response: [String: Any] = [
              "sourcePath": artifact.sourceURL.path,
              "sourceSha256": artifact.sourceSha256,
              "cleanupToken": artifact.cleanupToken,
            ]
            if let maskURL = artifact.maskURL, let maskSha256 = artifact.maskSha256 {
              response["maskPath"] = maskURL.path
              response["maskSha256"] = maskSha256
            }
            result(response)
          }
        } catch {
          DispatchQueue.main.async {
            result(Self.flutterError(error))
          }
        }
      }
    case "cleanupCanonicalUpload":
      guard
        let arguments = call.arguments as? [String: Any],
        let token = arguments["cleanupToken"] as? String,
        token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
      else {
        result(Self.flutterError(IOSGenerationUploadError.invalidArguments))
        return
      }
      workQueue.async { [weak self] in
        guard let self else { return }
        try? FileManager.default.removeItem(
          at: self.rootDirectory.appendingPathComponent(token, isDirectory: true)
        )
        DispatchQueue.main.async { result(nil) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func prepare(
    _ request: IOSGenerationUploadRequest
  ) throws -> IOSCanonicalUploadArtifact {
    let token = SHA256.hash(data: Data(request.clientRequestId.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    try FileManager.default.createDirectory(
      at: rootDirectory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )
    let directory = rootDirectory.appendingPathComponent(token, isDirectory: true)
    try? FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )
    do {
      return try renderer.prepare(
        request: request,
        directory: directory,
        cleanupToken: token
      )
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  private func cleanupExpiredDirectories() {
    guard let values = try? FileManager.default.contentsOfDirectory(
      at: rootDirectory,
      includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return
    }
    let cutoff = Date().addingTimeInterval(-Self.retentionInterval)
    for url in values {
      guard
        let resourceValues = try? url.resourceValues(
          forKeys: [.contentModificationDateKey, .isDirectoryKey]
        ),
        resourceValues.isDirectory == true,
        (resourceValues.contentModificationDate ?? .distantPast) < cutoff
      else {
        continue
      }
      try? FileManager.default.removeItem(at: url)
    }
  }

  private static func flutterError(_ error: Error) -> FlutterError {
    let code: String
    switch error {
    case IOSGenerationUploadError.invalidArguments:
      code = "invalidArguments"
    case IOSGenerationUploadError.unsupportedCapability:
      code = "capabilityUnsupported"
    case IOSGenerationUploadError.dimensionsUnsupported:
      code = "dimensionsUnsupported"
    case IOSGenerationUploadError.mediaTooLarge:
      code = "mediaTooLarge"
    case IOSGenerationUploadError.maskMismatch:
      code = "maskMismatch"
    case IOSGenerationUploadError.unreadableSource,
         IOSGenerationUploadError.encodingFailed:
      code = "canonicalUploadFailed"
    default:
      code = "canonicalUploadFailed"
    }
    return FlutterError(
      code: code,
      message: "The selected cloud capability upload could not be prepared",
      details: nil
    )
  }
}
