import CoreImage
import CoreGraphics
import Vision

enum IOSPortraitDegradationReason: String, Equatable {
  case none
  case noFace = "no_face"
  case multipleFaces = "multiple_faces"
  case lowConfidence = "low_confidence"
  case faceTooSmall = "face_too_small"
  case landmarksUnavailable = "landmarks_unavailable"
}

struct IOSPortraitSafetyDecision: Equatable {
  let applicable: Bool
  let reason: IOSPortraitDegradationReason
}

enum IOSPortraitSafetyPolicy {
  private static let minimumConfidence: Float = 0.5
  private static let minimumFaceDimension: CGFloat = 0.12
  private static let minimumFaceArea: CGFloat = 0.025

  static func isEligible(
    faceCount: Int,
    confidence: Float,
    boundingBox: CGRect,
    hasLandmarks: Bool
  ) -> Bool {
    evaluate(
      faceCount: faceCount,
      confidence: confidence,
      boundingBox: boundingBox,
      hasLandmarks: hasLandmarks
    ).applicable
  }

  static func evaluate(
    faceCount: Int,
    confidence: Float,
    boundingBox: CGRect,
    hasLandmarks: Bool
  ) -> IOSPortraitSafetyDecision {
    guard faceCount > 0 else {
      return IOSPortraitSafetyDecision(applicable: false, reason: .noFace)
    }
    guard faceCount == 1 else {
      return IOSPortraitSafetyDecision(applicable: false, reason: .multipleFaces)
    }
    guard confidence >= minimumConfidence else {
      return IOSPortraitSafetyDecision(applicable: false, reason: .lowConfidence)
    }
    guard
      boundingBox.width >= minimumFaceDimension,
      boundingBox.height >= minimumFaceDimension,
      boundingBox.width * boundingBox.height >= minimumFaceArea
    else {
      return IOSPortraitSafetyDecision(applicable: false, reason: .faceTooSmall)
    }
    guard hasLandmarks else {
      return IOSPortraitSafetyDecision(applicable: false, reason: .landmarksUnavailable)
    }
    return IOSPortraitSafetyDecision(applicable: true, reason: .none)
  }

  static func evaluate(_ observations: [VNFaceObservation]) -> IOSPortraitSafetyDecision {
    guard let face = observations.first else {
      return IOSPortraitSafetyDecision(applicable: false, reason: .noFace)
    }
    return evaluate(
      faceCount: observations.count,
      confidence: face.confidence,
      boundingBox: face.boundingBox,
      hasLandmarks: face.landmarks != nil
    )
  }

  static func isEligible(_ observations: [VNFaceObservation]) -> Bool {
    evaluate(observations).applicable
  }
}

struct IOSPortraitMasks {
  let candidate: CIImage
  let protection: CIImage
  let effective: CIImage
}

/// Deterministic, on-device portrait candidate reserved for corpus evaluation.
/// The production pipeline rejects nonzero strength until the eligibility gate
/// is frozen; Vision geometry never leaves this native boundary.
enum IOSPortraitRetoucher {
  static let candidateKind = "vision-landmarks-geometry-roi"
  static let effectVersion = "ios-geometry-retouch-candidate-v2"
  private static let analysisMaxEdge: CGFloat = 1_600
  private static let context = CIContext(options: [.cacheIntermediates: false])

  static func applying(
    to source: CIImage,
    strength: Double,
    extent: CGRect
  ) -> CIImage {
    let bounded = max(0, min(1, strength))
    let input = source.cropped(to: extent)
    guard bounded > 0 else { return input }

    let longestEdge = max(extent.width, extent.height)
    guard longestEdge > 0 else { return input }
    let scale = min(1, analysisMaxEdge / longestEdge)
    let proxy = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let proxyExtent = proxy.extent.integral
    guard
      proxyExtent.width >= 1,
      proxyExtent.height >= 1,
      let proxyImage = context.createCGImage(proxy, from: proxyExtent)
    else {
      return input
    }

    let request = VNDetectFaceLandmarksRequest()
#if targetEnvironment(simulator)
    request.usesCPUOnly = true
#endif
    let handler = VNImageRequestHandler(cgImage: proxyImage, orientation: .up)
    guard
      (try? handler.perform([request])) != nil,
      let observations = request.results,
      IOSPortraitSafetyPolicy.isEligible(observations),
      let proxyMasks = try? masks(
        observations: observations,
        extent: proxyExtent
      )
    else {
      return input
    }

    let mask = proxyMasks.effective
      .transformed(
        by: CGAffineTransform(
          scaleX: extent.width / proxyExtent.width,
          y: extent.height / proxyExtent.height
        )
      )
      .cropped(to: extent)
    return candidate(source: input, mask: mask, strength: bounded, extent: extent)
  }

  static func masks(
    observations: [VNFaceObservation],
    extent: CGRect
  ) throws -> IOSPortraitMasks {
    let width = Int(extent.width)
    let height = Int(extent.height)
    let candidateMask = try makeMask(width: width, height: height) { graphics in
      graphics.setFillColor(gray: 1, alpha: 1)
      for face in observations {
        graphics.fillEllipse(in: candidateFaceRect(face.boundingBox, size: extent.size))
      }
    }
    let protectionMask = try makeMask(width: width, height: height) { graphics in
      graphics.setFillColor(gray: 1, alpha: 1)
      graphics.setStrokeColor(gray: 1, alpha: 1)
      for face in observations {
        drawProtectionRegions(face: face, size: extent.size, graphics: graphics)
      }
    }
    let candidate = CIImage(cgImage: candidateMask)
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 8])
      .cropped(to: extent)
    let protection = CIImage(cgImage: protectionMask)
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3])
      .cropped(to: extent)
    let effective = candidate.applyingFilter(
      "CIMultiplyBlendMode",
      parameters: [
        kCIInputBackgroundImageKey: protection
          .applyingFilter("CIColorInvert")
          .cropped(to: extent),
      ]
    ).cropped(to: extent)
    return IOSPortraitMasks(
      candidate: candidate,
      protection: protection,
      effective: effective
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
      throw PortraitRetouchError.maskUnavailable
    }
    graphics.setAllowsAntialiasing(true)
    graphics.setShouldAntialias(true)
    graphics.setFillColor(gray: 0, alpha: 1)
    graphics.fill(CGRect(x: 0, y: 0, width: width, height: height))
    drawing(graphics)
    guard let image = graphics.makeImage() else {
      throw PortraitRetouchError.maskUnavailable
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
    fillRegion(landmarks.leftPupil, face: face, size: size, padding: closedPadding, in: graphics)
    fillRegion(landmarks.rightPupil, face: face, size: size, padding: closedPadding, in: graphics)
    strokeRegion(landmarks.leftEyebrow, face: face, size: size, width: linePadding * 2, in: graphics)
    strokeRegion(landmarks.rightEyebrow, face: face, size: size, width: linePadding * 2, in: graphics)
    strokeRegion(landmarks.nose, face: face, size: size, width: linePadding, in: graphics)
    strokeRegion(landmarks.noseCrest, face: face, size: size, width: linePadding, in: graphics)
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
    guard let first = values.first else { return }
    var minX = first.x
    var minY = first.y
    var maxX = first.x
    var maxY = first.y
    for point in values.dropFirst() {
      minX = min(minX, point.x)
      minY = min(minY, point.y)
      maxX = max(maxX, point.x)
      maxY = max(maxY, point.y)
    }
    graphics.fillEllipse(
      in: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        .insetBy(dx: -padding, dy: -padding)
    )
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
    for point in values.dropFirst() { graphics.addLine(to: point) }
    graphics.strokePath()
  }

  static func candidate(
    source: CIImage,
    mask: CIImage,
    strength: Double,
    extent: CGRect
  ) -> CIImage {
    let bounded = max(0, min(1, strength))
    let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
      .cropped(to: extent)
    let opaqueSource = source.composited(over: white).cropped(to: extent)
    guard bounded > 0 else { return opaqueSource }
    let denoised = opaqueSource.applyingFilter(
      "CINoiseReduction",
      parameters: [
        "inputNoiseLevel": 0.008 + bounded * 0.018,
        "inputSharpness": 0.55,
      ]
    ).cropped(to: extent)
    let relit = denoised.applyingFilter(
      "CIHighlightShadowAdjust",
      parameters: [
        "inputHighlightAmount": 1 - bounded * 0.08,
        "inputShadowAmount": bounded * 0.22,
      ]
    ).cropped(to: extent)
    let balanced = relit.applyingFilter(
      "CIColorControls",
      parameters: [
        kCIInputBrightnessKey: bounded * 0.018,
        kCIInputContrastKey: 1 - bounded * 0.025,
        kCIInputSaturationKey: 1 - bounded * 0.025,
      ]
    ).cropped(to: extent)
    let detailed = balanced.applyingFilter(
      "CISharpenLuminance",
      parameters: [kCIInputSharpnessKey: 0.12 + bounded * 0.08]
    ).cropped(to: extent)
    return detailed.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: opaqueSource,
        kCIInputMaskImageKey: mask,
      ]
    ).cropped(to: extent)
  }
}

private enum PortraitRetouchError: Error {
  case maskUnavailable
}
