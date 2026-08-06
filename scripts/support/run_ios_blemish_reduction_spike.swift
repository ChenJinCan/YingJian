import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

private enum BlemishSpikeError: Error {
  case invalidArguments
  case unreadableImage
}

@main
private enum IOSBlemishReductionSpike {
  static func main() throws {
    guard CommandLine.arguments.count == 3 else { throw BlemishSpikeError.invalidArguments }
    let sourcePath = CommandLine.arguments[1]
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let image = try thumbnail(path: sourcePath)
    let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let source = CIImage(cgImage: image).cropped(to: extent)
    let request = VNDetectFaceLandmarksRequest()
    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
    let observations = request.results ?? []
    let decision = IOSPortraitSafetyPolicy.evaluate(observations, imageSize: extent.size)
    let effectiveMask: CIImage?
    if
      decision.applicable,
      let masks = try? IOSPortraitRetoucher.masks(observations: observations, extent: extent)
    {
      effectiveMask = masks.effective
    } else {
      effectiveMask = nil
    }
    let off = source
    let recommended = effectiveMask.map {
      IOSBlemishReductionCandidate.applying(
        to: source, strength: 0.55, effectiveFaceMask: $0, extent: extent
      )
    } ?? source
    let highSafe = effectiveMask.map {
      IOSBlemishReductionCandidate.applying(
        to: source, strength: 0.85, effectiveFaceMask: $0, extent: extent
      )
    } ?? source
    let productionCombined = effectiveMask.map { mask -> CIImage in
      let repaired = IOSBlemishReductionCandidate.applying(
        to: source, strength: 0.55, effectiveFaceMask: mask, extent: extent
      )
      let relit = IOSPortraitRetoucher.applyingSkinToneLighting(
        to: repaired, strength: 0.4, mask: mask, extent: extent
      )
      return IOSPortraitRetoucher.applyingTextureSmoothing(
        to: relit, strength: 0.45, mask: mask, extent: extent
      )
    } ?? source
    let context = CIContext(options: [.cacheIntermediates: false])
    let outputs = [
      "off": off,
      "recommended": recommended,
      "high_safe": highSafe,
      "production_combined": productionCombined,
    ]
    var paths: [String: String] = [:]
    var cropPaths: [String: String] = [:]
    let faceCrop = observations.first.map { face -> CGRect in
      let faceRect = CGRect(
        x: face.boundingBox.minX * extent.width,
        y: face.boundingBox.minY * extent.height,
        width: face.boundingBox.width * extent.width,
        height: face.boundingBox.height * extent.height
      )
      return faceRect.insetBy(
        dx: -faceRect.width * 0.18,
        dy: -faceRect.height * 0.18
      ).intersection(extent).integral
    }
    for (name, candidate) in outputs {
      let url = outputDirectory.appendingPathComponent("\(name).jpg")
      try context.writeJPEGRepresentation(
        of: candidate,
        to: url,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
      )
      paths[name] = url.path
      if let faceCrop {
        let cropURL = outputDirectory.appendingPathComponent("\(name)-face.jpg")
        try context.writeJPEGRepresentation(
          of: candidate.cropped(to: faceCrop),
          to: cropURL,
          colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
        )
        cropPaths[name] = cropURL.path
      }
    }
    let data = try JSONSerialization.data(withJSONObject: [
      "schema": 1,
      "source": sourcePath,
      "sample_width": image.width,
      "sample_height": image.height,
      "detected_face_count": observations.count,
      "detected_faces": observations.enumerated().map { index, observation in
        [
          "index": index,
          "confidence": observation.confidence,
          "bounding_box": [
            observation.boundingBox.minX,
            observation.boundingBox.minY,
            observation.boundingBox.width,
            observation.boundingBox.height,
          ],
          "has_landmarks": observation.landmarks != nil,
        ] as [String: Any]
      },
      "applicable": decision.applicable,
      "degradation_reason": decision.reason.rawValue,
      "effect_version": IOSBlemishReductionCandidate.effectVersion,
      "outputs": paths,
      "face_crops": cropPaths,
      "engineering_only": true,
      "quality_passed": false,
    ], options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }

  private static func thumbnail(path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { throw BlemishSpikeError.unreadableImage }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 1_200,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw BlemishSpikeError.unreadableImage }
    return image
  }
}
