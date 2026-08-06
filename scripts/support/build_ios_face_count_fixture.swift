import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

private enum FaceCountFixtureError: Error {
  case invalidArguments
  case invalidScales
  case unreadableImage
  case faceUnavailable
}

@main
private enum IOSFaceCountFixtureBuilder {
  static func main() throws {
    guard CommandLine.arguments.count >= 4 else { throw FaceCountFixtureError.invalidArguments }
    let destination = URL(fileURLWithPath: CommandLine.arguments[1])
    var inputs = Array(CommandLine.arguments.dropFirst(2))
    var scales: [CGFloat] = []
    if let scaleArgument = inputs.first, scaleArgument.hasPrefix("--scales=") {
      scales = scaleArgument
        .dropFirst("--scales=".count)
        .split(separator: ",")
        .compactMap { value -> CGFloat? in
          guard let parsed = Double(value) else { return nil }
          return CGFloat(parsed)
        }
      inputs.removeFirst()
    }
    guard inputs.count >= 2 else { throw FaceCountFixtureError.invalidArguments }
    if scales.isEmpty {
      scales = Array(repeating: 1, count: inputs.count)
    }
    guard
      scales.count == inputs.count,
      scales.allSatisfy({ $0 > 0 && $0 <= 1 })
    else { throw FaceCountFixtureError.invalidScales }
    let slotWidth: CGFloat = 600
    let slotHeight: CGFloat = 800
    let extent = CGRect(x: 0, y: 0, width: slotWidth * CGFloat(inputs.count), height: slotHeight)
    var canvas = CIImage(color: .white).cropped(to: extent)
    for (index, path) in inputs.enumerated() {
      let image = try thumbnail(path: path)
      let source = CIImage(cgImage: image)
      let request = VNDetectFaceRectanglesRequest()
      try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
      guard let face = request.results?.first else { throw FaceCountFixtureError.faceUnavailable }
      let faceRect = CGRect(
        x: face.boundingBox.minX * CGFloat(image.width),
        y: face.boundingBox.minY * CGFloat(image.height),
        width: face.boundingBox.width * CGFloat(image.width),
        height: face.boundingBox.height * CGFloat(image.height)
      )
      var crop = faceRect.insetBy(dx: -faceRect.width * 0.75, dy: -faceRect.height * 0.55)
      crop = crop.intersection(source.extent).integral
      let scale = min(slotWidth / crop.width, slotHeight / crop.height) * scales[index]
      let normalized = source
        .cropped(to: crop)
        .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      let translated = normalized.transformed(by: CGAffineTransform(
        translationX: CGFloat(index) * slotWidth + (slotWidth - normalized.extent.width) / 2,
        y: (slotHeight - normalized.extent.height) / 2
      ))
      canvas = translated.composited(over: canvas).cropped(to: extent)
    }
    try CIContext(options: [.cacheIntermediates: false]).writeJPEGRepresentation(
      of: canvas,
      to: destination,
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
      options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
    )
  }

  private static func thumbnail(path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { throw FaceCountFixtureError.unreadableImage }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 1_200,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw FaceCountFixtureError.unreadableImage }
    return image
  }
}
