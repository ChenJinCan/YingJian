import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

private enum MultiFaceSpikeError: Error {
  case invalidArguments
  case unreadableImage
  case outputUnavailable
}

@main
private enum IOSMultiFaceNonGeometricSpike {
  static func main() throws {
    guard CommandLine.arguments.count == 3 else {
      throw MultiFaceSpikeError.invalidArguments
    }
    let sourcePath = CommandLine.arguments[1]
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )

    let image = try thumbnail(path: sourcePath)
    let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let source = CIImage(cgImage: image).cropped(to: extent)
    let request = VNDetectFaceLandmarksRequest()
    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
    let observations = request.results ?? []
    let descriptors = observations.map {
      IOSNonGeometricFaceDescriptor(
        confidence: $0.confidence,
        boundingBox: $0.boundingBox,
        hasLandmarks: $0.landmarks != nil
      )
    }
    let decision = IOSMultiFaceNonGeometricSafetyPolicy.evaluate(
      faces: descriptors,
      imageSize: extent.size
    )
    let eligible = decision.applicableFaceIndices.map { observations[$0] }

    let baselineURL = outputDirectory.appendingPathComponent("baseline.jpg")
    let appleURL = outputDirectory.appendingPathComponent("apple-system.jpg")
    let selfBuiltURL = outputDirectory.appendingPathComponent("yingjian-self-built.jpg")
    let smoothingURL = outputDirectory.appendingPathComponent("texture-smoothing-v2.jpg")
    let skinLightURL = outputDirectory.appendingPathComponent("skin-tone-lighting-v2.jpg")
    let combinedURL = outputDirectory.appendingPathComponent("portrait-v2-combined.jpg")
    let baseline = opaque(source, extent: extent)
    let appleCandidate: CIImage
    let selfBuiltCandidate: CIImage
    let smoothingCandidate: CIImage
    let skinLightCandidate: CIImage
    let combinedCandidate: CIImage
    if
      !eligible.isEmpty,
      let masks = try? IOSPortraitRetoucher.masks(observations: eligible, extent: extent)
    {
      let denoised = baseline.applyingFilter(
        "CINoiseReduction",
        parameters: ["inputNoiseLevel": 0.025, "inputSharpness": 0.0]
      ).cropped(to: extent)
      appleCandidate = denoised.applyingFilter(
        "CIBlendWithMask",
        parameters: [
          kCIInputBackgroundImageKey: baseline,
          kCIInputMaskImageKey: masks.effective,
        ]
      ).cropped(to: extent)
      selfBuiltCandidate = IOSPortraitRetoucher.candidate(
        source: baseline,
        mask: masks.effective,
        strength: 0.5,
        extent: extent
      )
      smoothingCandidate = IOSPortraitRetoucher.applyingTextureSmoothing(
        to: baseline, strength: 0.45, mask: masks.effective, extent: extent
      )
      skinLightCandidate = IOSPortraitRetoucher.applyingSkinToneLighting(
        to: baseline, strength: 0.4, mask: masks.effective, extent: extent
      )
      let relitFirst = IOSPortraitRetoucher.applyingSkinToneLighting(
        to: baseline, strength: 0.4, mask: masks.effective, extent: extent
      )
      combinedCandidate = IOSPortraitRetoucher.applyingTextureSmoothing(
        to: relitFirst, strength: 0.45, mask: masks.effective, extent: extent
      )
    } else {
      appleCandidate = baseline
      selfBuiltCandidate = baseline
      smoothingCandidate = baseline
      skinLightCandidate = baseline
      combinedCandidate = baseline
    }

    let context = CIContext(options: [.cacheIntermediates: false])
    try writeJPEG(baseline, to: baselineURL, context: context)
    try writeJPEG(appleCandidate, to: appleURL, context: context)
    try writeJPEG(selfBuiltCandidate, to: selfBuiltURL, context: context)
    try writeJPEG(smoothingCandidate, to: smoothingURL, context: context)
    try writeJPEG(skinLightCandidate, to: skinLightURL, context: context)
    try writeJPEG(combinedCandidate, to: combinedURL, context: context)
    let rejected = decision.rejectedFaces.keys.sorted().map { index in
      [
        "index": index,
        "reason": decision.rejectedFaces[index]!.rawValue,
      ] as [String: Any]
    }
    let detectedFaces = observations.enumerated().map { index, observation in
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
    }
    try printJSON([
      "schema": 1,
      "source": sourcePath,
      "sample_width": image.width,
      "sample_height": image.height,
      "detected_face_count": observations.count,
      "detected_faces": detectedFaces,
      "applicable_face_indices": decision.applicableFaceIndices,
      "rejected_faces": rejected,
      "scene_reason": decision.sceneReason.rawValue,
      "candidates": [
        "apple_system": appleURL.path,
        "yingjian_self_built": selfBuiltURL.path,
        "texture_smoothing_v2": smoothingURL.path,
        "skin_tone_lighting_v2": skinLightURL.path,
        "portrait_v2_combined": combinedURL.path,
      ],
      "baseline": baselineURL.path,
      "engineering_only": true,
      "quality_passed": false,
    ])
  }

  private static func thumbnail(path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw MultiFaceSpikeError.unreadableImage
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 1_200,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
      throw MultiFaceSpikeError.unreadableImage
    }
    return image
  }

  private static func opaque(_ source: CIImage, extent: CGRect) -> CIImage {
    source.composited(
      over: CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
    ).cropped(to: extent)
  }

  private static func writeJPEG(
    _ image: CIImage,
    to url: URL,
    context: CIContext
  ) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    try context.writeJPEGRepresentation(
      of: image,
      to: url,
      colorSpace: colorSpace,
      options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
    )
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw MultiFaceSpikeError.outputUnavailable
    }
  }

  private static func printJSON(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
