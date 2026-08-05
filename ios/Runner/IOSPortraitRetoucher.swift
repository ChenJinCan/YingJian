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
  static let minimumConfidence: Float = 0.5
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

/// Landmark-derived local deformation area. The mapping is inverse: every
/// destination pixel asks for a source coordinate, avoiding holes or seams.
struct IOSFaceSlimGeometry: Equatable {
  static let maximumShiftRatio: CGFloat = 0.24

  let centerX: CGFloat
  let halfWidth: CGFloat
  let lowerY: CGFloat
  let upperY: CGFloat

  var influenceRect: CGRect {
    CGRect(
      x: centerX - halfWidth,
      y: lowerY,
      width: halfWidth * 2,
      height: upperY - lowerY
    )
  }

  func sourcePoint(for destination: CGPoint, strength: Double) -> CGPoint {
    let bounded = CGFloat(max(0, min(1, strength)))
    guard bounded > 0, halfWidth > 0, upperY > lowerY else { return destination }
    let normalizedX = abs(destination.x - centerX) / halfWidth
    let verticalSpan = upperY - lowerY
    let horizontalGate = smoothstep(0.24, 0.48, normalizedX)
      * (1 - smoothstep(0.78, 1, normalizedX))
    let verticalGate = smoothstep(lowerY, lowerY + verticalSpan * 0.2, destination.y)
      * (1 - smoothstep(upperY - verticalSpan * 0.2, upperY, destination.y))
    let shift = (destination.x - centerX) * bounded * Self.maximumShiftRatio
      * horizontalGate * verticalGate
    return CGPoint(x: destination.x + shift, y: destination.y)
  }

  func scaled(x xScale: CGFloat, y yScale: CGFloat) -> IOSFaceSlimGeometry {
    IOSFaceSlimGeometry(
      centerX: centerX * xScale,
      halfWidth: halfWidth * xScale,
      lowerY: lowerY * yScale,
      upperY: upperY * yScale
    )
  }

  private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
    guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
    let t = max(0, min(1, (value - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
  }
}

struct IOSBodySlimGeometry: Equatable {
  static let maximumShiftRatio: CGFloat = 0.22

  let centerX: CGFloat
  let halfWidth: CGFloat
  let lowerY: CGFloat
  let upperY: CGFloat

  var influenceRect: CGRect {
    CGRect(
      x: centerX - halfWidth,
      y: lowerY,
      width: halfWidth * 2,
      height: upperY - lowerY
    )
  }

  func sourcePoint(for destination: CGPoint, strength: Double) -> CGPoint {
    let bounded = CGFloat(max(0, min(1, strength)))
    guard bounded > 0, halfWidth > 0, upperY > lowerY else { return destination }
    let normalizedX = abs(destination.x - centerX) / halfWidth
    let verticalSpan = upperY - lowerY
    let horizontalGate = smoothstep(0.22, 0.46, normalizedX)
      * (1 - smoothstep(0.82, 1, normalizedX))
    let verticalGate = smoothstep(lowerY, lowerY + verticalSpan * 0.12, destination.y)
      * (1 - smoothstep(upperY - verticalSpan * 0.12, upperY, destination.y))
    let shift = (destination.x - centerX) * bounded * Self.maximumShiftRatio
      * horizontalGate * verticalGate
    return CGPoint(x: destination.x + shift, y: destination.y)
  }

  func scaled(x xScale: CGFloat, y yScale: CGFloat) -> IOSBodySlimGeometry {
    IOSBodySlimGeometry(
      centerX: centerX * xScale,
      halfWidth: halfWidth * xScale,
      lowerY: lowerY * yScale,
      upperY: upperY * yScale
    )
  }

  private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
    guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
    let t = max(0, min(1, (value - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
  }
}

enum IOSBodySlimSafetyPolicy {
  private static let minimumJointConfidence: Float = 0.5
  private static let minimumTorsoHeightRatio: CGFloat = 0.12

  static func isEligible(
    personCount: Int,
    leftShoulderConfidence: Float,
    rightShoulderConfidence: Float,
    leftHipConfidence: Float,
    rightHipConfidence: Float,
    torsoHeightRatio: CGFloat,
    segmentationAvailable: Bool
  ) -> Bool {
    personCount == 1
      && leftShoulderConfidence >= minimumJointConfidence
      && rightShoulderConfidence >= minimumJointConfidence
      && leftHipConfidence >= minimumJointConfidence
      && rightHipConfidence >= minimumJointConfidence
      && torsoHeightRatio >= minimumTorsoHeightRatio
      && segmentationAvailable
  }
}

/// Rejects reshape when long/high-contrast background structure is dense near
/// the deformation ROI. The mask is dilated first so the subject silhouette
/// itself is not mistaken for a risky background line.
enum IOSReshapeBackgroundSafetyPolicy {
  private static let maximumOutsideEdgeMean = 0.18
  private static let analysisContext = CIContext(options: [.cacheIntermediates: false])

  static func isEligible(
    source: CIImage,
    subjectMask: CIImage,
    influenceRect: CGRect
  ) -> Bool {
    guard let risk = outsideEdgeMean(
      source: source,
      subjectMask: subjectMask,
      influenceRect: influenceRect
    ) else {
      return false
    }
    return risk <= maximumOutsideEdgeMean
  }

  static func outsideEdgeMean(
    source: CIImage,
    subjectMask: CIImage,
    influenceRect: CGRect
  ) -> Double? {
    let extent = influenceRect.intersection(source.extent).integral
    guard extent.width >= 2, extent.height >= 2 else { return nil }
    let radius = max(2, min(12, min(source.extent.width, source.extent.height) * 0.01))
    let dilatedMask = subjectMask
      .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
      .cropped(to: source.extent)
    let outsideMask = dilatedMask
      .applyingFilter("CIColorInvert")
      .cropped(to: source.extent)
    let edges = source
      .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 2.5])
      .cropped(to: source.extent)
    let outsideEdges = edges.applyingFilter(
      "CIMultiplyCompositing",
      parameters: [kCIInputBackgroundImageKey: outsideMask]
    ).cropped(to: source.extent)
    guard
      let edgeMean = areaAverage(outsideEdges, extent: extent),
      let outsideCoverage = areaAverage(outsideMask, extent: extent),
      outsideCoverage > 0.01
    else {
      return nil
    }
    return min(1, edgeMean / outsideCoverage)
  }

  private static func areaAverage(_ image: CIImage, extent: CGRect) -> Double? {
    guard let average = CIFilter(
      name: "CIAreaAverage",
      parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: extent)]
    )?.outputImage else {
      return nil
    }
    var pixel = [UInt8](repeating: 0, count: 4)
    analysisContext.render(
      average,
      toBitmap: &pixel,
      rowBytes: 4,
      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    return Double(max(pixel[0], pixel[1], pixel[2])) / 255
  }
}

/// Reusable, native-only portrait geometry for one decoded source image.
/// A missing mask is an intentional safe no-op for ineligible or failed analysis.
struct IOSPortraitRetouchContext {
  let effectiveMask: CIImage?
  let faceSlimGeometry: IOSFaceSlimGeometry?
  let faceMask: CIImage?
  let bodySlimGeometry: IOSBodySlimGeometry?
  let personMask: CIImage?

  init(
    effectiveMask: CIImage?,
    faceSlimGeometry: IOSFaceSlimGeometry? = nil,
    faceMask: CIImage? = nil,
    bodySlimGeometry: IOSBodySlimGeometry? = nil,
    personMask: CIImage? = nil
  ) {
    self.effectiveMask = effectiveMask
    self.faceSlimGeometry = faceSlimGeometry
    self.faceMask = faceMask
    self.bodySlimGeometry = bodySlimGeometry
    self.personMask = personMask
  }

  static let unavailable = IOSPortraitRetouchContext(
    effectiveMask: nil,
    faceSlimGeometry: nil,
    faceMask: nil,
    bodySlimGeometry: nil,
    personMask: nil
  )
}

/// Deterministic, on-device portrait retouching. Vision geometry and masks
/// remain inside this native boundary and never cross the Flutter channel.
enum IOSPortraitRetoucher {
  static let candidateKind = "vision-landmarks-geometry-roi"
  static let effectVersion = "ios-metal-warp-retouch-candidate-v6"
  static let analysisMaxEdge: CGFloat = 768
  private static let context = CIContext(options: [.cacheIntermediates: false])
  private static let localSlimWarpKernel: CIWarpKernel? = {
    let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    [[stitchable]] float2 localSlimWarp(
      float4 region,
      float strength,
      float shiftRatio,
      coreimage::destination destinationPixel
    ) {
      float2 destination = destinationPixel.coord();
      float centerX = region.x;
      float halfWidth = region.y;
      float lowerY = region.z;
      float upperY = region.w;
      float normalizedX = abs(destination.x - centerX) / halfWidth;
      float verticalSpan = upperY - lowerY;
      float horizontalGate = smoothstep(0.24, 0.48, normalizedX)
        * (1.0 - smoothstep(0.78, 1.0, normalizedX));
      float verticalGate = smoothstep(lowerY, lowerY + verticalSpan * 0.16, destination.y)
        * (1.0 - smoothstep(upperY - verticalSpan * 0.16, upperY, destination.y));
      float shift = (destination.x - centerX) * strength * shiftRatio
        * horizontalGate * verticalGate;
      return float2(destination.x + shift, destination.y);
    }
    """
    return try? CIKernel.kernels(withMetalString: source)
      .first(where: { $0.name == "localSlimWarp" }) as? CIWarpKernel
  }()

  static func bodySlimApplicable(image: CGImage) -> Bool {
    let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    return prepareBody(
      proxyImage: image,
      proxyExtent: extent,
      targetExtent: extent
    ) != nil
  }

  static func applying(
    to source: CIImage,
    strength: Double,
    extent: CGRect
  ) -> CIImage {
    let bounded = max(0, min(1, strength))
    let input = source.cropped(to: extent)
    guard bounded > 0 else { return input }

    return applying(
      to: input,
      strength: bounded,
      extent: extent,
      context: prepare(source: input, extent: extent)
    )
  }

  static func applyingFaceSlim(
    to source: CIImage,
    strength: Double,
    extent: CGRect,
    context: IOSPortraitRetouchContext
  ) -> CIImage {
    let bounded = max(0, min(1, strength))
    let input = source.cropped(to: extent)
    guard
      bounded > 0,
      let geometry = context.faceSlimGeometry,
      geometry.halfWidth > 0,
      geometry.upperY > geometry.lowerY,
      let faceMask = context.faceMask,
      let warped = localSlimWarp(
        input,
        extent: extent,
        centerX: geometry.centerX,
        halfWidth: geometry.halfWidth,
        lowerY: geometry.lowerY,
        upperY: geometry.upperY,
        strength: bounded,
        shiftRatio: IOSFaceSlimGeometry.maximumShiftRatio
      )
    else {
      return input
    }
    return warped.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: faceMask.cropped(to: extent),
      ]
    ).cropped(to: extent)
  }

  static func applyingBodySlim(
    to source: CIImage,
    strength: Double,
    extent: CGRect,
    context: IOSPortraitRetouchContext
  ) -> CIImage {
    let bounded = max(0, min(1, strength))
    let input = source.cropped(to: extent)
    guard
      bounded > 0,
      let geometry = context.bodySlimGeometry,
      geometry.halfWidth > 0,
      geometry.upperY > geometry.lowerY,
      let personMask = context.personMask,
      let warped = localSlimWarp(
        input,
        extent: extent,
        centerX: geometry.centerX,
        halfWidth: geometry.halfWidth,
        lowerY: geometry.lowerY,
        upperY: geometry.upperY,
        strength: bounded,
        shiftRatio: IOSBodySlimGeometry.maximumShiftRatio
      )
    else {
      return input
    }
    return warped.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: personMask.cropped(to: extent),
      ]
    ).cropped(to: extent)
  }

  private static func localSlimWarp(
    _ input: CIImage,
    extent: CGRect,
    centerX: CGFloat,
    halfWidth: CGFloat,
    lowerY: CGFloat,
    upperY: CGFloat,
    strength: Double,
    shiftRatio: CGFloat
  ) -> CIImage? {
    let maximumShift = halfWidth * shiftRatio * CGFloat(strength)
    return localSlimWarpKernel?.apply(
      extent: extent,
      roiCallback: { _, rectangle in
        rectangle.insetBy(dx: -maximumShift - 2, dy: -2)
      },
      image: input.clampedToExtent(),
      arguments: [
        CIVector(x: centerX, y: halfWidth, z: lowerY, w: upperY),
        NSNumber(value: strength),
        NSNumber(value: Double(shiftRatio)),
      ]
    )?.cropped(to: extent)
  }

  static func applying(
    to source: CIImage,
    strength: Double,
    extent: CGRect,
    context: IOSPortraitRetouchContext
  ) -> CIImage {
    let bounded = max(0, min(1, strength))
    let input = source.cropped(to: extent)
    guard bounded > 0, let mask = context.effectiveMask else { return input }
    return candidate(source: input, mask: mask, strength: bounded, extent: extent)
  }

  static func prepare(source: CIImage, extent: CGRect) -> IOSPortraitRetouchContext {
    let input = source.cropped(to: extent)

    let longestEdge = max(extent.width, extent.height)
    guard longestEdge > 0 else { return .unavailable }
    let scale = min(1, analysisMaxEdge / longestEdge)
    let proxy = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let proxyExtent = proxy.extent.integral
    guard
      proxyExtent.width >= 1,
      proxyExtent.height >= 1,
      let proxyImage = context.createCGImage(proxy, from: proxyExtent)
    else {
      return .unavailable
    }

    var effectiveMask: CIImage?
    var faceGeometry: IOSFaceSlimGeometry?
    var faceMask: CIImage?

    let request = VNDetectFaceLandmarksRequest()
#if targetEnvironment(simulator)
    request.usesCPUOnly = true
#endif
    let handler = VNImageRequestHandler(cgImage: proxyImage, orientation: .up)
    if
      (try? handler.perform([request])) != nil,
      let observations = request.results,
      IOSPortraitSafetyPolicy.isEligible(observations),
      let proxyMasks = try? masks(observations: observations, extent: proxyExtent)
    {
      effectiveMask = proxyMasks.effective
        .transformed(
          by: CGAffineTransform(
            scaleX: extent.width / proxyExtent.width,
            y: extent.height / proxyExtent.height
          )
        )
        .cropped(to: extent)
      faceMask = proxyMasks.candidate
        .transformed(
          by: CGAffineTransform(
            scaleX: extent.width / proxyExtent.width,
            y: extent.height / proxyExtent.height
          )
        )
        .cropped(to: extent)
      if
        let face = observations.first,
        let proxyGeometry = faceSlimGeometry(face: face, size: proxyExtent.size),
        IOSReshapeBackgroundSafetyPolicy.isEligible(
          source: CIImage(cgImage: proxyImage),
          subjectMask: proxyMasks.candidate,
          influenceRect: proxyGeometry.influenceRect
        )
      {
        let geometry = proxyGeometry.scaled(
          x: extent.width / proxyExtent.width,
          y: extent.height / proxyExtent.height
        )
        faceGeometry = geometry
      }
    }

    let body = prepareBody(
      proxyImage: proxyImage,
      proxyExtent: proxyExtent,
      targetExtent: extent
    )
    return IOSPortraitRetouchContext(
      effectiveMask: effectiveMask,
      faceSlimGeometry: faceGeometry,
      faceMask: faceMask,
      bodySlimGeometry: body?.geometry,
      personMask: body?.personMask
    )
  }

  private static func prepareBody(
    proxyImage: CGImage,
    proxyExtent: CGRect,
    targetExtent: CGRect
  ) -> (
    geometry: IOSBodySlimGeometry,
    personMask: CIImage
  )? {
#if targetEnvironment(simulator)
    // Human pose and person segmentation can both report no result on iOS
    // Simulator and can stall every preview while doing so. Do not start those
    // known-unavailable requests here. Keep the production UI testable without
    // pretending this is hardware evidence: infer one conservative torso only
    // from a confirmed single face, and confine the mask to that torso. Device
    // builds never compile this fallback and still require pose + segmentation.
    return prepareSimulatorBody(
      proxyImage: proxyImage,
      proxyExtent: proxyExtent,
      targetExtent: targetExtent
    )
#else
    return prepareVisionBody(
      proxyImage: proxyImage,
      proxyExtent: proxyExtent,
      targetExtent: targetExtent
    )
#endif
  }

  private static func prepareVisionBody(
    proxyImage: CGImage,
    proxyExtent: CGRect,
    targetExtent: CGRect
  ) -> (
    geometry: IOSBodySlimGeometry,
    personMask: CIImage
  )? {
    let poseRequest = VNDetectHumanBodyPoseRequest()
    let segmentationRequest = VNGeneratePersonSegmentationRequest()
    segmentationRequest.qualityLevel = .balanced
    segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
#if targetEnvironment(simulator)
    poseRequest.usesCPUOnly = true
    segmentationRequest.usesCPUOnly = true
#endif
    let handler = VNImageRequestHandler(cgImage: proxyImage, orientation: .up)
    guard
      (try? handler.perform([poseRequest, segmentationRequest])) != nil,
      let observations = poseRequest.results,
      observations.count == 1,
      let observation = observations.first,
      let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
      let rightShoulder = try? observation.recognizedPoint(.rightShoulder),
      let leftHip = try? observation.recognizedPoint(.leftHip),
      let rightHip = try? observation.recognizedPoint(.rightHip),
      let segmentation = segmentationRequest.results?.first,
      IOSBodySlimSafetyPolicy.isEligible(
        personCount: observations.count,
        leftShoulderConfidence: leftShoulder.confidence,
        rightShoulderConfidence: rightShoulder.confidence,
        leftHipConfidence: leftHip.confidence,
        rightHipConfidence: rightHip.confidence,
        torsoHeightRatio: abs(
          ((leftShoulder.y + rightShoulder.y) / 2)
            - ((leftHip.y + rightHip.y) / 2)
        ),
        segmentationAvailable: true
      )
    else {
      return nil
    }

    func imagePoint(_ point: VNRecognizedPoint) -> CGPoint {
      CGPoint(
        x: point.x * proxyExtent.width,
        y: point.y * proxyExtent.height
      )
    }
    let shoulders = [imagePoint(leftShoulder), imagePoint(rightShoulder)]
    let hips = [imagePoint(leftHip), imagePoint(rightHip)]
    let shoulderWidth = abs(shoulders[0].x - shoulders[1].x)
    let hipWidth = abs(hips[0].x - hips[1].x)
    let shoulderY = (shoulders[0].y + shoulders[1].y) / 2
    let hipY = (hips[0].y + hips[1].y) / 2
    let torsoHeight = abs(shoulderY - hipY)
    let proxyGeometry = IOSBodySlimGeometry(
      centerX: (shoulders[0].x + shoulders[1].x + hips[0].x + hips[1].x) / 4,
      halfWidth: max(shoulderWidth * 0.62, hipWidth * 0.72),
      lowerY: min(shoulderY, hipY) - torsoHeight * 0.04,
      upperY: max(shoulderY, hipY) + torsoHeight * 0.04
    )
    let xScale = targetExtent.width / proxyExtent.width
    let yScale = targetExtent.height / proxyExtent.height
    let geometry = proxyGeometry.scaled(x: xScale, y: yScale)
    let rawMask = CIImage(cvPixelBuffer: segmentation.pixelBuffer)
    let normalizedMask = rawMask.transformed(
      by: CGAffineTransform(
        translationX: -rawMask.extent.minX,
        y: -rawMask.extent.minY
      )
    )
    let personMask = normalizedMask
      .transformed(
        by: CGAffineTransform(
          scaleX: targetExtent.width / normalizedMask.extent.width,
          y: targetExtent.height / normalizedMask.extent.height
        )
      )
      .cropped(to: targetExtent)
    guard IOSReshapeBackgroundSafetyPolicy.isEligible(
      source: CIImage(cgImage: proxyImage),
      subjectMask: normalizedMask
        .transformed(
          by: CGAffineTransform(
            scaleX: proxyExtent.width / normalizedMask.extent.width,
            y: proxyExtent.height / normalizedMask.extent.height
          )
        )
        .cropped(to: proxyExtent),
      influenceRect: proxyGeometry.influenceRect
    ) else {
      return nil
    }
    return (geometry, personMask)
  }

#if targetEnvironment(simulator)
  private static func prepareSimulatorBody(
    proxyImage: CGImage,
    proxyExtent: CGRect,
    targetExtent: CGRect
  ) -> (
    geometry: IOSBodySlimGeometry,
    personMask: CIImage
  )? {
    guard
      proxyExtent.height >= proxyExtent.width * 1.15,
      proxyExtent.width >= 1,
      proxyExtent.height >= 1
    else {
      return nil
    }
    let request = VNDetectFaceRectanglesRequest()
    request.usesCPUOnly = true
    let handler = VNImageRequestHandler(cgImage: proxyImage, orientation: .up)
    guard
      (try? handler.perform([request])) != nil,
      let faces = request.results,
      faces.count == 1,
      let face = faces.first,
      face.confidence >= IOSPortraitSafetyPolicy.minimumConfidence,
      let proxyGeometry = simulatorBodyFallbackGeometry(
        faceBoundingBox: face.boundingBox,
        proxyExtent: proxyExtent
      )
    else {
      return nil
    }
    let proxyMaskImage: CGImage
    do {
      proxyMaskImage = try makeMask(
        width: Int(proxyExtent.width),
        height: Int(proxyExtent.height)
      ) { graphics in
        graphics.setFillColor(gray: 1, alpha: 1)
        graphics.fillEllipse(in: CGRect(
          x: proxyGeometry.centerX - proxyGeometry.halfWidth,
          y: proxyGeometry.lowerY,
          width: proxyGeometry.halfWidth * 2,
          height: proxyGeometry.upperY - proxyGeometry.lowerY
        ))
      }
    } catch {
      return nil
    }
    let proxyMask = CIImage(cgImage: proxyMaskImage).cropped(to: proxyExtent)
    guard IOSReshapeBackgroundSafetyPolicy.isEligible(
      source: CIImage(cgImage: proxyImage),
      subjectMask: proxyMask,
      influenceRect: proxyGeometry.influenceRect
    ) else {
      return nil
    }
    let xScale = targetExtent.width / proxyExtent.width
    let yScale = targetExtent.height / proxyExtent.height
    return (
      proxyGeometry.scaled(x: xScale, y: yScale),
      proxyMask
        .transformed(by: CGAffineTransform(scaleX: xScale, y: yScale))
        .cropped(to: targetExtent)
    )
  }

  static func simulatorBodyFallbackGeometry(
    faceBoundingBox: CGRect,
    proxyExtent: CGRect
  ) -> IOSBodySlimGeometry? {
    guard
      proxyExtent.height >= proxyExtent.width * 1.15,
      faceBoundingBox.midY >= 0.58,
      faceBoundingBox.width >= 0.035,
      faceBoundingBox.width <= 0.22
    else {
      return nil
    }
    let faceRect = CGRect(
      x: faceBoundingBox.minX * proxyExtent.width,
      y: faceBoundingBox.minY * proxyExtent.height,
      width: faceBoundingBox.width * proxyExtent.width,
      height: faceBoundingBox.height * proxyExtent.height
    )
    let upperY = faceRect.minY - faceRect.height * 0.18
    let torsoHeight = min(proxyExtent.height * 0.43, faceRect.height * 6.0)
    let lowerY = max(proxyExtent.height * 0.14, upperY - torsoHeight)
    let halfWidth = min(
      proxyExtent.width * 0.30,
      max(proxyExtent.width * 0.17, faceRect.width * 1.65)
    )
    guard upperY > lowerY, halfWidth > 0 else { return nil }
    return IOSBodySlimGeometry(
      centerX: faceRect.midX,
      halfWidth: halfWidth,
      lowerY: lowerY,
      upperY: upperY
    )
  }
#endif

  private static func faceSlimGeometry(
    face: VNFaceObservation,
    size: CGSize
  ) -> IOSFaceSlimGeometry? {
    let faceRect = CGRect(
      x: face.boundingBox.minX * size.width,
      y: face.boundingBox.minY * size.height,
      width: face.boundingBox.width * size.width,
      height: face.boundingBox.height * size.height
    )
    guard faceRect.width > 0, faceRect.height > 0 else { return nil }
    let contour = points(for: face.landmarks?.faceContour, face: face, size: size)
    let minX = contour.map(\.x).min() ?? faceRect.minX
    let maxX = contour.map(\.x).max() ?? faceRect.maxX
    let contourWidth = maxX - minX
    let centerX = contourWidth > 0 ? (minX + maxX) / 2 : faceRect.midX
    let halfWidth = max(faceRect.width * 0.35, contourWidth * 0.52)
    return IOSFaceSlimGeometry(
      centerX: centerX,
      halfWidth: halfWidth,
      lowerY: faceRect.minY + faceRect.height * 0.04,
      upperY: faceRect.minY + faceRect.height * 0.62
    )
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
    let softened = opaqueSource.clampedToExtent().applyingFilter(
      "CIGaussianBlur",
      parameters: [kCIInputRadiusKey: 0.8 + bounded * 0.9]
    ).cropped(to: extent)
    let textureSmoothed = opaqueSource.applyingFilter(
      "CIDissolveTransition",
      parameters: [
        kCIInputTargetImageKey: softened,
        kCIInputTimeKey: 0.15 + bounded * 0.45,
      ]
    ).cropped(to: extent)
    let denoised = textureSmoothed.applyingFilter(
      "CINoiseReduction",
      parameters: [
        "inputNoiseLevel": 0.012 + bounded * 0.032,
        "inputSharpness": 0.0,
      ]
    ).cropped(to: extent)
    let toneRadius = min(24, max(6, min(extent.width, extent.height) * 0.015))
    let lowFrequencyColor = opaqueSource.clampedToExtent().applyingFilter(
      "CIGaussianBlur",
      parameters: [kCIInputRadiusKey: toneRadius]
    ).cropped(to: extent)
    let luminancePreservingTone = lowFrequencyColor.applyingFilter(
      "CIColorBlendMode",
      parameters: [kCIInputBackgroundImageKey: denoised]
    ).cropped(to: extent)
    let toneBalanced = denoised.applyingFilter(
      "CIDissolveTransition",
      parameters: [
        kCIInputTargetImageKey: luminancePreservingTone,
        kCIInputTimeKey: 0.18 + bounded * 0.45,
      ]
    )
      .composited(over: opaqueSource)
      .cropped(to: extent)
    let relit = toneBalanced.applyingFilter(
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
    let permanentEdgeMask = opaqueSource
      .applyingFilter(
        "CIColorControls",
        parameters: [kCIInputSaturationKey: 0]
      )
      .applyingFilter(
        "CIEdges",
        parameters: [kCIInputIntensityKey: 4]
      )
      .applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: 8, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 8, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 8, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: -0.25, y: -0.25, z: -0.25, w: 0),
        ]
      )
      .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1])
      .clampedToExtent()
      .applyingFilter(
        "CIGaussianBlur",
        parameters: [kCIInputRadiusKey: 0.35]
      )
      .cropped(to: extent)
    let detailProtected = opaqueSource.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: balanced,
        kCIInputMaskImageKey: permanentEdgeMask,
      ]
    ).cropped(to: extent)
    return detailProtected.applyingFilter(
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
