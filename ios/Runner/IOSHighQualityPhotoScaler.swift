import CoreImage
import CryptoKit
import Foundation
import ImageIO

enum IOSHighQualityPhotoScalerError: Error {
  case invalidScaleFactor
  case sourceAndDestinationMatch
  case destinationAlreadyExists
  case decodeFailed
  case outputSizeUnsupported
  case renderFailed
}

struct IOSUpscaledPhotoFile {
  let outputPath: String
  let contentSha256: String
  let scaleFactor: Int
  let width: Int
  let height: Int
}

/// Deterministic high-quality resampling backed by Core Image Lanczos.
///
/// This implementation enlarges existing pixels; it does not claim to
/// synthesize AI detail. The supplier-neutral Dart interface allows a future
/// Core ML implementation to replace this adapter without changing callers.
struct IOSHighQualityPhotoScaler {
  let context: CIContext

  func render(
    sourcePath: String,
    scaleFactor: Int,
    destinationURL: URL
  ) throws -> IOSUpscaledPhotoFile {
    guard scaleFactor == 2 || scaleFactor == 4 else {
      throw IOSHighQualityPhotoScalerError.invalidScaleFactor
    }
    let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
    let outputURL = destinationURL.standardizedFileURL
    guard sourceURL != outputURL else {
      throw IOSHighQualityPhotoScalerError.sourceAndDestinationMatch
    }
    guard !FileManager.default.fileExists(atPath: outputURL.path) else {
      throw IOSHighQualityPhotoScalerError.destinationAlreadyExists
    }
    guard let input = CIImage(
      contentsOf: sourceURL,
      options: [.applyOrientationProperty: true]
    ) else {
      throw IOSHighQualityPhotoScalerError.decodeFailed
    }

    let normalizedInput = input.transformed(
      by: CGAffineTransform(
        translationX: -input.extent.minX,
        y: -input.extent.minY
      )
    )
    let sourceExtent = normalizedInput.extent.integral
    let sourceWidth = Int(sourceExtent.width)
    let sourceHeight = Int(sourceExtent.height)
    let (outputWidth, widthOverflow) = sourceWidth.multipliedReportingOverflow(
      by: scaleFactor
    )
    let (outputHeight, heightOverflow) = sourceHeight.multipliedReportingOverflow(
      by: scaleFactor
    )
    guard
      sourceWidth > 0,
      sourceHeight > 0,
      !widthOverflow,
      !heightOverflow,
      outputWidth > 0,
      outputHeight > 0
    else {
      throw IOSHighQualityPhotoScalerError.outputSizeUnsupported
    }
    let maximumSize = context.outputImageMaximumSize()
    if maximumSize.width > 0 && maximumSize.height > 0 {
      guard
        CGFloat(outputWidth) <= maximumSize.width,
        CGFloat(outputHeight) <= maximumSize.height
      else {
        throw IOSHighQualityPhotoScalerError.outputSizeUnsupported
      }
    }

    guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
      throw IOSHighQualityPhotoScalerError.renderFailed
    }
    filter.setValue(normalizedInput, forKey: kCIInputImageKey)
    filter.setValue(scaleFactor, forKey: kCIInputScaleKey)
    filter.setValue(1, forKey: kCIInputAspectRatioKey)
    guard let filteredImage = filter.outputImage else {
      throw IOSHighQualityPhotoScalerError.renderFailed
    }
    let targetExtent = CGRect(
      x: 0,
      y: 0,
      width: outputWidth,
      height: outputHeight
    )
    let output = filteredImage
      .cropped(to: targetExtent)
      .settingProperties(ImageExportMetadata.sanitize(input.properties))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw IOSHighQualityPhotoScalerError.renderFailed
    }

    do {
      try context.writeJPEGRepresentation(
        of: output,
        to: outputURL,
        colorSpace: colorSpace,
        options: [
          kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
        ]
      )
    } catch {
      try? FileManager.default.removeItem(at: outputURL)
      throw IOSHighQualityPhotoScalerError.renderFailed
    }
    let contentSha256: String
    do {
      contentSha256 = try Self.sha256(outputURL)
    } catch {
      try? FileManager.default.removeItem(at: outputURL)
      throw IOSHighQualityPhotoScalerError.renderFailed
    }
    return IOSUpscaledPhotoFile(
      outputPath: outputURL.path,
      contentSha256: contentSha256,
      scaleFactor: scaleFactor,
      width: outputWidth,
      height: outputHeight
    )
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
}
