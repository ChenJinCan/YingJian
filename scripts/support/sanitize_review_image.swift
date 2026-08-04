import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SanitizerError: Error {
  case invalidArguments
  case decodeFailed
  case encodeFailed
  case unsafeMetadata(String)
}

func normalizedPixelSHA256(_ image: CGImage) throws -> String {
  let width = image.width
  let height = image.height
  let bytesPerRow = width * 4
  var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
  let rendered = rgba.withUnsafeMutableBytes { buffer -> Bool in
    guard
      let address = buffer.baseAddress,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: address,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
          CGBitmapInfo.byteOrder32Big.rawValue
      )
    else { return false }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
  }
  guard rendered else { throw SanitizerError.decodeFailed }
  var widthValue = UInt64(width).bigEndian
  var heightValue = UInt64(height).bigEndian
  var canonical = Data(bytes: &widthValue, count: MemoryLayout<UInt64>.size)
  canonical.append(Data(bytes: &heightValue, count: MemoryLayout<UInt64>.size))
  canonical.append(contentsOf: rgba)
  return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
}

func run() throws {
  guard CommandLine.arguments.count == 3 else { throw SanitizerError.invalidArguments }
  let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
  let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
  guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    CGImageSourceGetCount(source) == 1,
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as? [CFString: Any],
    let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
    let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
    width.intValue > 0,
    height.intValue > 0
  else { throw SanitizerError.decodeFailed }

  let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue),
    kCGImageSourceShouldCacheImmediately: true,
  ]
  guard
    let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
    let destination = CGImageDestinationCreateWithURL(
      outputURL as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else { throw SanitizerError.decodeFailed }
  let pixelSHA256 = try normalizedPixelSHA256(pixels)
  CGImageDestinationAddImage(destination, pixels, nil)
  guard CGImageDestinationFinalize(destination) else { throw SanitizerError.encodeFailed }

  guard
    let sanitizedSource = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
    let sanitized = CGImageSourceCopyPropertiesAtIndex(sanitizedSource, 0, nil)
      as? [CFString: Any]
  else { throw SanitizerError.encodeFailed }
  let allowed: Set<String> = [
    kCGImagePropertyPixelWidth as String,
    kCGImagePropertyPixelHeight as String,
    kCGImagePropertyDepth as String,
    kCGImagePropertyColorModel as String,
    kCGImagePropertyHasAlpha as String,
    kCGImagePropertyProfileName as String,
    kCGImagePropertyOrientation as String,
    kCGImagePropertyExifDictionary as String,
    kCGImagePropertyPNGDictionary as String,
  ]
  let unsafeKeys = sanitized.keys.map { $0 as String }.filter { !allowed.contains($0) }
  guard unsafeKeys.isEmpty else {
    throw SanitizerError.unsafeMetadata(unsafeKeys.sorted().joined(separator: ","))
  }
  for dictionaryKey in [kCGImagePropertyExifDictionary, kCGImagePropertyPNGDictionary] {
    if let dictionary = sanitized[dictionaryKey] as? [CFString: Any],
       dictionary.values.contains(where: { $0 is String || $0 is NSString }) {
      throw SanitizerError.unsafeMetadata("text metadata in \(dictionaryKey)")
    }
  }
  print(pixelSHA256)
}

do {
  try run()
} catch {
  FileHandle.standardError.write(Data("review image sanitization failed: \(error)\n".utf8))
  exit(1)
}
