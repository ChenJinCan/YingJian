import CoreImage
import CoreGraphics
import Vision

// Shared, renderer-independent portrait geometry contracts. These live next
// to the retoucher because the offline engineering corpus compiles this file
// directly and must exercise the same production implementation as the app.
struct IOSFaceGeometryParameters: Equatable {
  let faceSlim: Int
  let headSize: Int
  let jaw: Int
  let chin: Int
  let eyes: Int
  let nose: Int
  let mouth: Int
}

struct IOSBodyGeometryParameters: Equatable {
  let slimming: Int
  let height: Int
  let shoulders: Int
  let waist: Int
  let legs: Int
}

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
  private static let minimumFacePixelDimension: CGFloat = 48
  private static let minimumFacePixelArea: CGFloat = 48 * 48

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

  static func evaluate(
    faceCount: Int,
    confidence: Float,
    boundingBox: CGRect,
    hasLandmarks: Bool,
    imageSize: CGSize
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
    let faceWidth = boundingBox.width * imageSize.width
    let faceHeight = boundingBox.height * imageSize.height
    guard
      faceWidth >= minimumFacePixelDimension,
      faceHeight >= minimumFacePixelDimension,
      faceWidth * faceHeight >= minimumFacePixelArea
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

  static func evaluate(
    _ observations: [VNFaceObservation],
    imageSize: CGSize
  ) -> IOSPortraitSafetyDecision {
    guard let face = observations.first else {
      return IOSPortraitSafetyDecision(applicable: false, reason: .noFace)
    }
    return evaluate(
      faceCount: observations.count,
      confidence: face.confidence,
      boundingBox: face.boundingBox,
      hasLandmarks: face.landmarks != nil,
      imageSize: imageSize
    )
  }

  static func isEligible(_ observations: [VNFaceObservation]) -> Bool {
    evaluate(observations).applicable
  }

  static func isEligible(
    _ observations: [VNFaceObservation],
    imageSize: CGSize
  ) -> Bool {
    evaluate(observations, imageSize: imageSize).applicable
  }
}

/// Spike seam for non-geometric retouching only. Unlike the legacy single-face
/// policy above, this evaluates each detected face independently while keeping
/// a hard scene limit. It is not used by production rendering until Ticket 20
/// supplies fixed-image outcome evidence.
struct IOSNonGeometricFaceDescriptor: Equatable {
  let confidence: Float
  let boundingBox: CGRect
  let hasLandmarks: Bool
}

enum IOSNonGeometricFaceRejectionReason: String, Equatable {
  case lowConfidence = "low_confidence"
  case faceTooSmall = "face_too_small"
  case landmarksUnavailable = "landmarks_unavailable"
}

enum IOSMultiFaceNonGeometricSceneReason: String, Equatable {
  case none
  case noFace = "no_face"
  case tooManyFaces = "too_many_faces"
  case noEligibleFace = "no_eligible_face"
}

struct IOSMultiFaceNonGeometricSafetyDecision: Equatable {
  let applicableFaceIndices: [Int]
  let rejectedFaces: [Int: IOSNonGeometricFaceRejectionReason]
  let sceneReason: IOSMultiFaceNonGeometricSceneReason
}

enum IOSMultiFaceNonGeometricSafetyPolicy {
  static let maximumFaceCount = 3
  private static let minimumFacePixelDimension: CGFloat = 48
  private static let minimumFacePixelArea: CGFloat = 48 * 48

  static func evaluate(
    faces: [IOSNonGeometricFaceDescriptor],
    imageSize: CGSize
  ) -> IOSMultiFaceNonGeometricSafetyDecision {
    guard !faces.isEmpty else {
      return IOSMultiFaceNonGeometricSafetyDecision(
        applicableFaceIndices: [],
        rejectedFaces: [:],
        sceneReason: .noFace
      )
    }
    guard faces.count <= maximumFaceCount else {
      return IOSMultiFaceNonGeometricSafetyDecision(
        applicableFaceIndices: [],
        rejectedFaces: [:],
        sceneReason: .tooManyFaces
      )
    }

    var applicable: [Int] = []
    var rejected: [Int: IOSNonGeometricFaceRejectionReason] = [:]
    for (index, face) in faces.enumerated() {
      if face.confidence < IOSPortraitSafetyPolicy.minimumConfidence {
        rejected[index] = .lowConfidence
        continue
      }
      let width = face.boundingBox.width * imageSize.width
      let height = face.boundingBox.height * imageSize.height
      if width < minimumFacePixelDimension
          || height < minimumFacePixelDimension
          || width * height < minimumFacePixelArea
      {
        rejected[index] = .faceTooSmall
        continue
      }
      guard face.hasLandmarks else {
        rejected[index] = .landmarksUnavailable
        continue
      }
      applicable.append(index)
    }
    return IOSMultiFaceNonGeometricSafetyDecision(
      applicableFaceIndices: applicable,
      rejectedFaces: rejected,
      sceneReason: applicable.isEmpty ? .noEligibleFace : .none
    )
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
  // Preserve CainCamera's stronger lower-face shave and softer upper-face
  // transition, then calibrate the pair against our protected real fixture.
  // The product slider is capped at 0.5, so these kernel ratios produce a
  // visible but identity-safe maximum instead of exposing the kernel's full
  // range directly.
  static let lowerFaceShiftRatio: CGFloat = 0.36
  static let upperFaceShiftRatio: CGFloat = 0.21

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
    let verticalPosition = max(0, min(1, (destination.y - lowerY) / verticalSpan))
    let shiftRatio = Self.lowerFaceShiftRatio
      + (Self.upperFaceShiftRatio - Self.lowerFaceShiftRatio) * verticalPosition
    let shift = (destination.x - centerX) * bounded * shiftRatio
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
  static let maximumShiftRatio: CGFloat = 0.175

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
  private static let minimumJointConfidence: Float = 0.4
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
    (1...3).contains(personCount)
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

struct IOSFaceFeatureGeometry {
  let faceBounds: CGRect
  let leftEye: CGPoint
  let rightEye: CGPoint
  let nose: CGPoint
  let mouth: CGPoint

  func scaled(x xScale: CGFloat, y yScale: CGFloat) -> IOSFaceFeatureGeometry {
    func point(_ value: CGPoint) -> CGPoint {
      CGPoint(x: value.x * xScale, y: value.y * yScale)
    }
    return IOSFaceFeatureGeometry(
      faceBounds: CGRect(
        x: faceBounds.minX * xScale,
        y: faceBounds.minY * yScale,
        width: faceBounds.width * xScale,
        height: faceBounds.height * yScale
      ),
      leftEye: point(leftEye),
      rightEye: point(rightEye),
      nose: point(nose),
      mouth: point(mouth)
    )
  }
}

struct IOSFaceSlimTargetContext {
  let geometry: IOSFaceSlimGeometry
  let mask: CIImage
  let features: IOSFaceFeatureGeometry

  init(
    geometry: IOSFaceSlimGeometry,
    mask: CIImage,
    features: IOSFaceFeatureGeometry? = nil
  ) {
    self.geometry = geometry
    self.mask = mask
    self.features = features ?? IOSFaceFeatureGeometry(
      faceBounds: CGRect(
        x: geometry.centerX - geometry.halfWidth,
        y: geometry.lowerY,
        width: geometry.halfWidth * 2,
        height: max(1, (geometry.upperY - geometry.lowerY) / 0.58)
      ),
      leftEye: CGPoint(x: geometry.centerX - geometry.halfWidth * 0.35, y: geometry.upperY),
      rightEye: CGPoint(x: geometry.centerX + geometry.halfWidth * 0.35, y: geometry.upperY),
      nose: CGPoint(x: geometry.centerX, y: geometry.lowerY + (geometry.upperY - geometry.lowerY) * 0.7),
      mouth: CGPoint(x: geometry.centerX, y: geometry.lowerY + (geometry.upperY - geometry.lowerY) * 0.35)
    )
  }
}

struct IOSBodyReshapeTargetContext {
  let geometry: IOSBodySlimGeometry
  let personMask: CIImage
}

/// Reusable, native-only portrait geometry for one decoded source image.
/// A missing mask is an intentional safe no-op for ineligible or failed analysis.
struct IOSPortraitRetouchContext {
  let effectiveMask: CIImage?
  let faceSlimTargets: [IOSFaceSlimTargetContext]
  let bodyReshapeTargets: [IOSBodyReshapeTargetContext]
  let semanticSubjectMask: CIImage?

  var faceSlimGeometry: IOSFaceSlimGeometry? { faceSlimTargets.first?.geometry }
  var faceMask: CIImage? { faceSlimTargets.first?.mask }
  var bodySlimGeometry: IOSBodySlimGeometry? { bodyReshapeTargets.first?.geometry }
  var personMask: CIImage? { bodyReshapeTargets.first?.personMask }
  var combinedPersonMask: CIImage? {
    if let semanticSubjectMask { return semanticSubjectMask }
    return bodyReshapeTargets.map(\.personMask).reduce(Optional<CIImage>.none) {
      (current: CIImage?, mask: CIImage) -> CIImage? in
      guard let current else { return mask }
      return mask.applyingFilter(
        "CIAdditionCompositing",
        parameters: [kCIInputBackgroundImageKey: current]
      ).cropped(to: current.extent.union(mask.extent))
    }
  }

  init(
    effectiveMask: CIImage?,
    faceSlimGeometry: IOSFaceSlimGeometry? = nil,
    faceMask: CIImage? = nil,
    faceSlimTargets: [IOSFaceSlimTargetContext]? = nil,
    bodyReshapeTargets: [IOSBodyReshapeTargetContext]? = nil,
    semanticSubjectMask: CIImage? = nil,
    bodySlimGeometry: IOSBodySlimGeometry? = nil,
    personMask: CIImage? = nil
  ) {
    self.effectiveMask = effectiveMask
    if let faceSlimTargets {
      self.faceSlimTargets = faceSlimTargets
    } else if let faceSlimGeometry, let faceMask {
      self.faceSlimTargets = [
        IOSFaceSlimTargetContext(geometry: faceSlimGeometry, mask: faceMask)
      ]
    } else {
      self.faceSlimTargets = []
    }
    if let bodyReshapeTargets {
      self.bodyReshapeTargets = bodyReshapeTargets
    } else if let bodySlimGeometry, let personMask {
      self.bodyReshapeTargets = [
        IOSBodyReshapeTargetContext(geometry: bodySlimGeometry, personMask: personMask)
      ]
    } else {
      self.bodyReshapeTargets = []
    }
    self.semanticSubjectMask = semanticSubjectMask
  }

  static let unavailable = IOSPortraitRetouchContext(
    effectiveMask: nil,
    faceSlimTargets: [],
    bodyReshapeTargets: [],
    semanticSubjectMask: nil
  )
}

/// Isolated Ticket 18 candidate. It only weakens compact, locally dark red
/// variation inside an already protected face mask. Brown details whose red
/// channel also falls with local luminance are deliberately rejected. The
/// candidate remains outside the production recipe until fixed crops pass.
enum IOSBlemishReductionCandidate {
  static let effectVersion = "ios-local-red-blemish-candidate-v3"
  private static let evidenceKernel: CIColorKernel? = {
    let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    [[stitchable]] half4 blemishEvidence(
      coreimage::sample_h pixel,
      coreimage::sample_h local
    ) {
      half redExcess = pixel.r - (pixel.g + pixel.b) * 0.5;
      half localRedExcess = local.r - (local.g + local.b) * 0.5;
      half redLoss = local.r - pixel.r;
      half redSupport = 1.0 - smoothstep(half(0.03), half(0.09), redLoss);
      half redness = smoothstep(half(0.015), half(0.06), redExcess - localRedExcess);
      half evidence = redSupport * redness;
      return half4(evidence, evidence, evidence, evidence);
    }
    """
    return try? CIKernel.kernels(withMetalString: source)
      .first(where: { $0.name == "blemishEvidence" }) as? CIColorKernel
  }()

  static var isAvailable: Bool { evidenceKernel != nil }

  static func applying(
    to source: CIImage,
    strength: Double,
    effectiveFaceMask: CIImage,
    extent: CGRect
  ) -> CIImage {
    let bounded = max(0, min(1, strength))
    let input = IOSPortraitRetoucher.materialized(
      source.cropped(to: extent),
      extent: extent
    )
    guard bounded > 0, let evidenceKernel else { return input }
    let local = input.clampedToExtent().applyingFilter(
      "CIGaussianBlur",
      parameters: [kCIInputRadiusKey: 7]
    ).cropped(to: extent)
    guard let rawEvidence = evidenceKernel.apply(
      extent: extent,
      arguments: [input, local]
    ) else {
      return input
    }
    let compactEvidence = rawEvidence
      .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1.5])
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.6])
      .cropped(to: extent)
    let weakened = input.applyingFilter(
      "CIDissolveTransition",
      parameters: [
        kCIInputTargetImageKey: local,
        kCIInputTimeKey: 0.55 + bounded * 0.45,
      ]
    ).cropped(to: extent)
    let repairedEvidence = weakened.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: compactEvidence,
      ]
    ).cropped(to: extent)
    return repairedEvidence.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: effectiveFaceMask.cropped(to: extent),
      ]
    ).cropped(to: extent)
  }
}

/// Deterministic, on-device portrait retouching. Vision geometry and masks
/// remain inside this native boundary and never cross the Flutter channel.
enum IOSPortraitRetoucher {
  static let candidateKind = "vision-landmarks-geometry-roi"
  static let effectVersion = "ios-metal-warp-retouch-candidate-v12"
  static let analysisMaxEdge: CGFloat = 768
  private static let context = CIContext(options: [.cacheIntermediates: false])
  /// GPUPixel's mature beauty blend expressed as a Core Image stitchable
  /// kernel. Its fixed radius/delta/theta calibration is intentionally kept
  /// inside the native renderer so the existing recipe remains vendor-free.
  private static let textureSmoothingKernel: CIColorKernel? = {
    let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    [[stitchable]] half4 textureSmoothingBlend(
      coreimage::sample_h original,
      coreimage::sample_h mean,
      float blurAlpha
    ) {
      half3 difference = (original.rgb - mean.rgb) * half(7.07);
      half3 variance = min(difference * difference, half3(1.0));
      half meanVariance = (variance.r + variance.g + variance.b) / half(3.0);
      half skinSupport = clamp(
        (min(original.r, mean.r - half(0.1)) - half(0.2)) * half(4.0),
        half(0.0),
        half(1.0)
      );
      half theta = half(0.1);
      half smoothing = (half(1.0) - meanVariance / (meanVariance + theta))
        * skinSupport * half(blurAlpha);
      half3 result = mix(original.rgb, mean.rgb, clamp(smoothing, half(0.0), half(1.0)));
      return half4(result, original.a);
    }
    """
    return try? CIKernel.kernels(withMetalString: source)
      .first(where: { $0.name == "textureSmoothingBlend" }) as? CIColorKernel
  }()
  /// CainCamera's complexion black/range levels, with a bounded midtone lift
  /// in place of its bundled LUT. The published calibration is preserved in
  /// gamma-encoded sRGB so black and highlight anchors remain stable.
  private static let complexionLevelsKernel: CIColorKernel? = {
    let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    [[stitchable]] half4 complexionLevels(
      coreimage::sample_h original,
      float strength
    ) {
      half levelBlack = half(0.01960784);
      half levelRangeInv = half(1.040816);
      half3 leveled = clamp(
        (original.rgb - half3(levelBlack)) * levelRangeInv,
        half3(0.0),
        half3(1.0)
      );
      half luma = dot(leveled, half3(0.2126, 0.7152, 0.0722));
      half midtoneGate = smoothstep(half(0.02), half(0.18), luma)
        * (half(1.0) - smoothstep(half(0.72), half(1.0), luma));
      half3 relit = leveled + (half3(1.0) - leveled)
        * half(0.08 * strength) * midtoneGate;
      half3 result = mix(original.rgb, relit, half(strength));
      return half4(clamp(result, half3(0.0), half3(1.0)), original.a);
    }
    """
    return try? CIKernel.kernels(withMetalString: source)
      .first(where: { $0.name == "complexionLevels" }) as? CIColorKernel
  }()
  private static let localSlimWarpKernel: CIWarpKernel? = {
    let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    [[stitchable]] float2 localSlimWarp(
      float4 region,
      float strength,
      float2 shiftRatios,
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
      float verticalPosition = clamp((destination.y - lowerY) / verticalSpan, 0.0, 1.0);
      float shiftRatio = mix(shiftRatios.x, shiftRatios.y, verticalPosition);
      float shift = (destination.x - centerX) * strength * shiftRatio
        * horizontalGate * verticalGate;
      return float2(destination.x + shift, destination.y);
    }
    """
    return try? CIKernel.kernels(withMetalString: source)
      .first(where: { $0.name == "localSlimWarp" }) as? CIWarpKernel
  }()
  private static let localScaleWarpKernel: CIWarpKernel? = {
    let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    [[stitchable]] float2 localScaleWarp(
      float4 region,
      float2 amount,
      coreimage::destination destinationPixel
    ) {
      float2 destination = destinationPixel.coord();
      float2 center = region.xy;
      float2 radius = max(region.zw, float2(1.0));
      float2 delta = destination - center;
      float distance = length(delta / radius);
      // CainCamera's eye warp and Harbeth's bulge both use a radial squared
      // falloff. Core Image supplies interpolated sampling for the result.
      float gate = max(0.0, 1.0 - distance * distance);
      return center + delta * (1.0 + amount * gate);
    }
    """
    return try? CIKernel.kernels(withMetalString: source)
      .first(where: { $0.name == "localScaleWarp" }) as? CIWarpKernel
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
    // The product slider intentionally exposes only 0...0.5. Expand that
    // product range into the kernel's useful range so low values remain
    // subtle while the explicit maximum is visually distinguishable.
    let effectiveStrength = min(1, bounded * 1.6)
    let input = source.cropped(to: extent)
    guard
      effectiveStrength > 0,
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
        strength: effectiveStrength,
        lowerShiftRatio: IOSFaceSlimGeometry.lowerFaceShiftRatio,
        upperShiftRatio: IOSFaceSlimGeometry.upperFaceShiftRatio
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

  static func applyingFaceSlim(
    to source: CIImage,
    strengths: [Double],
    extent: CGRect,
    context: IOSPortraitRetouchContext
  ) -> CIImage {
    var output = source.cropped(to: extent)
    for (index, target) in context.faceSlimTargets.enumerated()
      where strengths.indices.contains(index) && strengths[index] > 0
    {
      output = applyingFaceSlim(
        to: output,
        strength: strengths[index],
        extent: extent,
        context: IOSPortraitRetouchContext(
          effectiveMask: context.effectiveMask,
          faceSlimTargets: [target]
        )
      )
    }
    return output
  }

  static func applyingFaceGeometry(
    to source: CIImage,
    parameters: [IOSFaceGeometryParameters],
    extent: CGRect,
    context: IOSPortraitRetouchContext
  ) -> CIImage {
    var output = source.cropped(to: extent)
    for (index, target) in context.faceSlimTargets.enumerated()
      where parameters.indices.contains(index)
    {
      let values = parameters[index]
      if values.faceSlim > 0 {
        output = applyingFaceSlim(
          to: output,
          strength: Double(values.faceSlim) / 100,
          extent: extent,
          context: IOSPortraitRetouchContext(
            effectiveMask: context.effectiveMask,
            faceSlimTargets: [target]
          )
        )
      }
      let features = target.features
      let bounds = features.faceBounds
      let faceRadius = CGPoint(x: bounds.width * 0.58, y: bounds.height * 0.58)
      output = applyingLocalScale(
        to: output, center: CGPoint(x: bounds.midX, y: bounds.midY),
        radius: faceRadius,
        amountX: Double(values.headSize) / 100 * 0.12,
        amountY: Double(values.headSize) / 100 * 0.12,
        mask: target.mask, extent: extent
      )
      output = applyingLocalScale(
        to: output,
        center: CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.28),
        radius: CGPoint(x: bounds.width * 0.48, y: bounds.height * 0.30),
        amountX: -Double(values.jaw) / 100 * 0.12,
        amountY: 0,
        mask: target.mask, extent: extent
      )
      output = applyingLocalScale(
        to: output,
        center: CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.12),
        radius: CGPoint(x: bounds.width * 0.30, y: bounds.height * 0.24),
        amountX: 0,
        amountY: -Double(values.chin) / 100 * 0.08,
        mask: target.mask, extent: extent
      )
      for eye in [features.leftEye, features.rightEye] {
        output = applyingLocalScale(
          to: output, center: eye,
          radius: CGPoint(x: bounds.width * 0.17, y: bounds.height * 0.12),
          amountX: -Double(values.eyes) / 100 * 0.12,
          amountY: -Double(values.eyes) / 100 * 0.12,
          mask: target.mask, extent: extent
        )
      }
      output = applyingLocalScale(
        to: output, center: features.nose,
        radius: CGPoint(x: bounds.width * 0.16, y: bounds.height * 0.20),
        amountX: -Double(values.nose) / 100 * 0.10,
        amountY: -Double(values.nose) / 100 * 0.10,
        mask: target.mask, extent: extent
      )
      output = applyingLocalScale(
        to: output, center: features.mouth,
        radius: CGPoint(x: bounds.width * 0.25, y: bounds.height * 0.13),
        amountX: -Double(values.mouth) / 100 * 0.10,
        amountY: -Double(values.mouth) / 100 * 0.08,
        mask: target.mask, extent: extent
      )
    }
    return output
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
        lowerShiftRatio: IOSBodySlimGeometry.maximumShiftRatio,
        upperShiftRatio: IOSBodySlimGeometry.maximumShiftRatio
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

  static func applyingBodyGeometry(
    to source: CIImage,
    parameters: [IOSBodyGeometryParameters],
    extent: CGRect,
    context: IOSPortraitRetouchContext
  ) -> CIImage {
    var output = source.cropped(to: extent)
    for (index, target) in context.bodyReshapeTargets.enumerated()
      where parameters.indices.contains(index)
    {
      let values = parameters[index]
      let geometry = target.geometry
      output = applyingSignedSlim(
        to: output, geometry: geometry,
        strength: Double(values.slimming) / 100,
        lowerY: geometry.lowerY, upperY: geometry.upperY,
        mask: target.personMask, extent: extent
      )
      let span = geometry.upperY - geometry.lowerY
      output = applyingSignedSlim(
        to: output, geometry: geometry,
        strength: -Double(values.shoulders) / 100,
        lowerY: geometry.lowerY + span * 0.58,
        upperY: geometry.upperY,
        mask: target.personMask, extent: extent
      )
      output = applyingSignedSlim(
        to: output, geometry: geometry,
        strength: -Double(values.waist) / 100,
        lowerY: geometry.lowerY,
        upperY: geometry.lowerY + span * 0.58,
        mask: target.personMask, extent: extent
      )
      output = applyingLocalScale(
        to: output,
        center: CGPoint(x: geometry.centerX, y: geometry.lowerY + span * 0.5),
        radius: CGPoint(x: geometry.halfWidth, y: span * 0.62),
        amountX: 0,
        amountY: -Double(values.height) / 100 * 0.16,
        mask: target.personMask, extent: extent
      )
      output = applyingLocalScale(
        to: output,
        center: CGPoint(x: geometry.centerX, y: geometry.lowerY - span * 0.55),
        radius: CGPoint(x: geometry.halfWidth * 0.9, y: span * 0.85),
        amountX: 0,
        amountY: -Double(values.legs) / 100 * 0.18,
        mask: target.personMask, extent: extent
      )
    }
    return output
  }

  private static func applyingSignedSlim(
    to input: CIImage,
    geometry: IOSBodySlimGeometry,
    strength: Double,
    lowerY: CGFloat,
    upperY: CGFloat,
    mask: CIImage,
    extent: CGRect
  ) -> CIImage {
    guard abs(strength) > 0.0001,
          let warped = localSlimWarp(
            input, extent: extent,
            centerX: geometry.centerX, halfWidth: geometry.halfWidth,
            lowerY: lowerY, upperY: upperY,
            strength: strength,
            lowerShiftRatio: IOSBodySlimGeometry.maximumShiftRatio,
            upperShiftRatio: IOSBodySlimGeometry.maximumShiftRatio
          )
    else { return input }
    return warped.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: mask.cropped(to: extent),
      ]
    ).cropped(to: extent)
  }

  private static func applyingLocalScale(
    to input: CIImage,
    center: CGPoint,
    radius: CGPoint,
    amountX: Double,
    amountY: Double,
    mask: CIImage,
    extent: CGRect
  ) -> CIImage {
    guard abs(amountX) > 0.0001 || abs(amountY) > 0.0001 else { return input }
    let maximumShift = max(radius.x * abs(amountX), radius.y * abs(amountY)) + 2
    guard let warped = localScaleWarpKernel?.apply(
      extent: extent,
      roiCallback: { _, rectangle in rectangle.insetBy(dx: -maximumShift, dy: -maximumShift) },
      image: input.clampedToExtent(),
      arguments: [
        CIVector(x: center.x, y: center.y, z: radius.x, w: radius.y),
        CIVector(x: amountX, y: amountY),
      ]
    )?.cropped(to: extent) else { return input }
    return warped.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: mask.cropped(to: extent),
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
    lowerShiftRatio: CGFloat,
    upperShiftRatio: CGFloat
  ) -> CIImage? {
    let maximumShift = halfWidth * max(abs(lowerShiftRatio), abs(upperShiftRatio))
      * abs(CGFloat(strength))
    return localSlimWarpKernel?.apply(
      extent: extent,
      roiCallback: { _, rectangle in
        rectangle.insetBy(dx: -maximumShift - 2, dy: -2)
      },
      image: input.clampedToExtent(),
      arguments: [
        CIVector(x: centerX, y: halfWidth, z: lowerY, w: upperY),
        NSNumber(value: strength),
        CIVector(x: lowerShiftRatio, y: upperShiftRatio),
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
    var faceSlimTargets: [IOSFaceSlimTargetContext] = []

    let request = VNDetectFaceLandmarksRequest()
#if targetEnvironment(simulator)
    request.usesCPUOnly = true
#endif
    let handler = VNImageRequestHandler(cgImage: proxyImage, orientation: .up)
    if (try? handler.perform([request])) != nil, let observations = request.results {
      let descriptors = observations.map {
        IOSNonGeometricFaceDescriptor(
          confidence: $0.confidence,
          boundingBox: $0.boundingBox,
          hasLandmarks: $0.landmarks != nil
        )
      }
      let decision = IOSMultiFaceNonGeometricSafetyPolicy.evaluate(
        faces: descriptors,
        imageSize: proxyExtent.size
      )
      let eligible = decision.applicableFaceIndices
        .map { observations[$0] }
        .sorted { lhs, rhs in
          let horizontalDelta = lhs.boundingBox.midX - rhs.boundingBox.midX
          if abs(horizontalDelta) > 0.001 {
            return horizontalDelta < 0
          }
          return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
      if !eligible.isEmpty,
         let proxyMasks = try? masks(observations: eligible, extent: proxyExtent)
      {
        effectiveMask = proxyMasks.effective
          .transformed(
            by: CGAffineTransform(
              scaleX: extent.width / proxyExtent.width,
              y: extent.height / proxyExtent.height
            )
          )
          .cropped(to: extent)
      }

      let scaleX = extent.width / proxyExtent.width
      let scaleY = extent.height / proxyExtent.height
      for face in eligible.prefix(IOSMultiFaceNonGeometricSafetyPolicy.maximumFaceCount) {
        guard
          let singleFaceMasks = try? masks(observations: [face], extent: proxyExtent),
          let proxyGeometry = faceSlimGeometry(face: face, size: proxyExtent.size),
          IOSReshapeBackgroundSafetyPolicy.isEligible(
            source: CIImage(cgImage: proxyImage),
            subjectMask: singleFaceMasks.candidate,
            influenceRect: proxyGeometry.influenceRect
          )
        else {
          continue
        }
        faceSlimTargets.append(
          IOSFaceSlimTargetContext(
            geometry: proxyGeometry.scaled(x: scaleX, y: scaleY),
            mask: singleFaceMasks.candidate
              .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
              .cropped(to: extent),
            features: faceFeatureGeometry(face: face, size: proxyExtent.size)
              .scaled(x: scaleX, y: scaleY)
          )
        )
      }
    }

    let bodies = prepareBodies(
      proxyImage: proxyImage,
      proxyExtent: proxyExtent,
      targetExtent: extent
    )
#if targetEnvironment(simulator)
    let semanticSubjectMask = bodies.first?.personMask ?? faceSlimTargets.first?.mask
#else
    let semanticSubjectMask = preparePersonSegmentationMask(
      proxyImage: proxyImage,
      proxyExtent: proxyExtent,
      targetExtent: extent
    )
#endif
    return IOSPortraitRetouchContext(
      effectiveMask: effectiveMask,
      faceSlimTargets: faceSlimTargets,
      bodyReshapeTargets: bodies,
      semanticSubjectMask: semanticSubjectMask
    )
  }

  private static func preparePersonSegmentationMask(
    proxyImage: CGImage,
    proxyExtent: CGRect,
    targetExtent: CGRect
  ) -> CIImage? {
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .balanced
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    let handler = VNImageRequestHandler(cgImage: proxyImage, orientation: .up)
    guard
      (try? handler.perform([request])) != nil,
      let segmentation = request.results?.first
    else { return nil }
    let raw = CIImage(cvPixelBuffer: segmentation.pixelBuffer)
    let normalized = raw.transformed(by: CGAffineTransform(
      translationX: -raw.extent.minX,
      y: -raw.extent.minY
    ))
    return normalized.transformed(by: CGAffineTransform(
      scaleX: targetExtent.width / normalized.extent.width,
      y: targetExtent.height / normalized.extent.height
    )).cropped(to: targetExtent)
  }

  private static func prepareBody(
    proxyImage: CGImage,
    proxyExtent: CGRect,
    targetExtent: CGRect
  ) -> (
    geometry: IOSBodySlimGeometry,
    personMask: CIImage
  )? {
    prepareBodies(
      proxyImage: proxyImage,
      proxyExtent: proxyExtent,
      targetExtent: targetExtent
    ).first.map { ($0.geometry, $0.personMask) }
  }

  private static func prepareBodies(
    proxyImage: CGImage,
    proxyExtent: CGRect,
    targetExtent: CGRect
  ) -> [IOSBodyReshapeTargetContext] {
#if targetEnvironment(simulator)
    // Human pose and person segmentation can both report no result on iOS
    // Simulator and can stall every preview while doing so. Do not start those
    // known-unavailable requests here. Keep the production UI testable without
    // pretending this is hardware evidence: infer one conservative torso only
    // from a confirmed single face, and confine the mask to that torso. Device
    // builds never compile this fallback and still require pose + segmentation.
    guard let body = prepareSimulatorBody(
      proxyImage: proxyImage,
      proxyExtent: proxyExtent,
      targetExtent: targetExtent
    ) else { return [] }
    return [IOSBodyReshapeTargetContext(
      geometry: body.geometry,
      personMask: body.personMask
    )]
#else
    return prepareVisionBodies(
      proxyImage: proxyImage,
      proxyExtent: proxyExtent,
      targetExtent: targetExtent
    )
#endif
  }

  private static func prepareVisionBodies(
    proxyImage: CGImage,
    proxyExtent: CGRect,
    targetExtent: CGRect
  ) -> [IOSBodyReshapeTargetContext] {
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
      (1...3).contains(observations.count),
      let segmentation = segmentationRequest.results?.first
    else {
      return []
    }
    let xScale = targetExtent.width / proxyExtent.width
    let yScale = targetExtent.height / proxyExtent.height
    let rawMask = CIImage(cvPixelBuffer: segmentation.pixelBuffer)
    let normalizedMask = rawMask.transformed(
      by: CGAffineTransform(
        translationX: -rawMask.extent.minX,
        y: -rawMask.extent.minY
      )
    )
    let proxyPersonMask = normalizedMask
      .transformed(
        by: CGAffineTransform(
          scaleX: proxyExtent.width / normalizedMask.extent.width,
          y: proxyExtent.height / normalizedMask.extent.height
        )
      )
      .cropped(to: proxyExtent)
    let black = CIImage(color: .black).cropped(to: proxyExtent)
    let source = CIImage(cgImage: proxyImage)

    var targets: [IOSBodyReshapeTargetContext] = []
    for observation in observations {
      guard
        let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
        let rightShoulder = try? observation.recognizedPoint(.rightShoulder),
        let leftHip = try? observation.recognizedPoint(.leftHip),
        let rightHip = try? observation.recognizedPoint(.rightHip),
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
      else { continue }

      func imagePoint(_ point: VNRecognizedPoint) -> CGPoint {
        CGPoint(x: point.x * proxyExtent.width, y: point.y * proxyExtent.height)
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
        halfWidth: max(shoulderWidth * 0.90, hipWidth * 1.04),
        lowerY: min(shoulderY, hipY) - torsoHeight * 0.04,
        upperY: max(shoulderY, hipY) + torsoHeight * 0.04
      )
      let localRect = CGRect(
        x: proxyGeometry.centerX - proxyGeometry.halfWidth * 1.45,
        y: 0,
        width: proxyGeometry.halfWidth * 2.9,
        height: min(proxyExtent.height, proxyGeometry.upperY + torsoHeight * 1.25)
      ).intersection(proxyExtent)
      let localShape = CIImage(color: .white)
        .cropped(to: localRect)
        .composited(over: black)
        .cropped(to: proxyExtent)
      let localPersonMask = proxyPersonMask.applyingFilter(
        "CIMultiplyCompositing",
        parameters: [kCIInputBackgroundImageKey: localShape]
      ).cropped(to: proxyExtent)
      guard IOSReshapeBackgroundSafetyPolicy.isEligible(
        source: source,
        subjectMask: localPersonMask,
        influenceRect: proxyGeometry.influenceRect
      ) else { continue }
      targets.append(IOSBodyReshapeTargetContext(
        geometry: proxyGeometry.scaled(x: xScale, y: yScale),
        personMask: localPersonMask
          .transformed(by: CGAffineTransform(scaleX: xScale, y: yScale))
          .cropped(to: targetExtent)
      ))
    }
    return targets.sorted { $0.geometry.centerX < $1.geometry.centerX }
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

  private static func faceFeatureGeometry(
    face: VNFaceObservation,
    size: CGSize
  ) -> IOSFaceFeatureGeometry {
    let bounds = CGRect(
      x: face.boundingBox.minX * size.width,
      y: face.boundingBox.minY * size.height,
      width: face.boundingBox.width * size.width,
      height: face.boundingBox.height * size.height
    )
    func center(
      _ region: VNFaceLandmarkRegion2D?,
      fallback: CGPoint
    ) -> CGPoint {
      let values = points(for: region, face: face, size: size)
      guard !values.isEmpty else { return fallback }
      return CGPoint(
        x: values.map(\.x).reduce(0, +) / CGFloat(values.count),
        y: values.map(\.y).reduce(0, +) / CGFloat(values.count)
      )
    }
    return IOSFaceFeatureGeometry(
      faceBounds: bounds,
      leftEye: center(
        face.landmarks?.leftEye,
        fallback: CGPoint(x: bounds.minX + bounds.width * 0.34, y: bounds.minY + bounds.height * 0.62)
      ),
      rightEye: center(
        face.landmarks?.rightEye,
        fallback: CGPoint(x: bounds.minX + bounds.width * 0.66, y: bounds.minY + bounds.height * 0.62)
      ),
      nose: center(
        face.landmarks?.nose,
        fallback: CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.45)
      ),
      mouth: center(
        face.landmarks?.outerLips,
        fallback: CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.27)
      )
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
          "inputRVector": CIVector(x: 2, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 2, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 2, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: -0.12, y: -0.12, z: -0.12, w: 0),
        ]
      )
      // Open the binary-like edge map before expanding it. This removes
      // compact pore/wrinkle responses that otherwise survive as isolated
      // dark speckles after the surrounding skin is softened, while keeping
      // wider structural edges for the following protection blend.
      .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 0.75])
      .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1.25])
      .clampedToExtent()
      .applyingFilter(
        "CIGaussianBlur",
        parameters: [kCIInputRadiusKey: 1.2]
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

  static func applyingTextureSmoothing(
    to source: CIImage,
    strength: Double,
    mask: CIImage,
    extent: CGRect
  ) -> CIImage {
    let bounded = max(0, min(1, strength))
    let input = materialized(source.cropped(to: extent), extent: extent)
    guard bounded > 0, let textureSmoothingKernel else { return input }
    // GPUPixel's published thresholds operate on gamma-encoded RGB samples.
    // Core Image's working space is linear, so preserve those exact constants
    // by entering and leaving sRGB around only this calibrated blend.
    let encodedInput = input.applyingFilter("CILinearToSRGBToneCurve").cropped(to: extent)
    let mean = encodedInput.clampedToExtent().applyingFilter(
      "CIGaussianBlur",
      parameters: [kCIInputRadiusKey: 4.0]
    ).cropped(to: extent)
    guard let encodedSmoothed = textureSmoothingKernel.apply(
      extent: extent,
      arguments: [encodedInput, mean, bounded]
    ) else { return input }
    let smoothed = encodedSmoothed
      .applyingFilter("CISRGBToneCurveToLinear")
      .cropped(to: extent)
    return smoothed.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: mask.cropped(to: extent),
      ]
    ).cropped(to: extent)
  }

  static func applyingSkinToneLighting(
    to source: CIImage,
    strength: Double,
    mask: CIImage,
    extent: CGRect
  ) -> CIImage {
    let bounded = max(0, min(1, strength))
    let input = materialized(source.cropped(to: extent), extent: extent)
    guard bounded > 0, let complexionLevelsKernel else { return input }
    let encoded = input.applyingFilter("CILinearToSRGBToneCurve").cropped(to: extent)
    guard let correctedEncoded = complexionLevelsKernel.apply(
      extent: extent,
      arguments: [encoded, bounded]
    ) else { return input }
    let corrected = correctedEncoded
      .applyingFilter("CISRGBToneCurveToLinear")
      .cropped(to: extent)
    return corrected.applyingFilter(
      "CIBlendWithMask",
      parameters: [
        kCIInputBackgroundImageKey: input,
        kCIInputMaskImageKey: mask.cropped(to: extent),
      ]
    ).cropped(to: extent)
  }

  private static func permanentEdgeMask(source: CIImage, extent: CGRect) -> CIImage {
    source
      .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
      .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 4])
      .applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: 2, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 2, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 2, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: -0.12, y: -0.12, z: -0.12, w: 0),
        ]
      )
      .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 0.75])
      .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1.25])
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.2])
      .cropped(to: extent)
  }

  /// Core Image's neighborhood filters may request an expanded region from a
  /// preceding color-blend graph. Freezing that boundary prevents a second
  /// independent portrait effect from changing image coordinates.
  static func materialized(_ image: CIImage, extent: CGRect) -> CIImage {
    guard let rendered = context.createCGImage(image.cropped(to: extent), from: extent) else {
      return image.cropped(to: extent)
    }
    return CIImage(cgImage: rendered).cropped(to: extent)
  }
}

private enum PortraitRetouchError: Error {
  case maskUnavailable
}
