import CoreGraphics
import Foundation
import ImageIO
import Vision

// Engineering-only contour probe for before/after files produced by the native
// renderer. Usage: measure-ios-reshape-contours face|body BEFORE AFTER.
// This produces deterministic JSON for candidate calibration; it does not
// replace the frozen corpus, physical-device, or blind-review quality gates.
private enum ReshapeContourMetricError: Error {
  case invalidArguments
  case unreadableImage
  case ineligibleFace
  case ineligibleBody
  case segmentationUnavailable
}

@main
private enum IOSReshapeContourMetric {
  static func main() throws {
    guard CommandLine.arguments.count == 4 else {
      throw ReshapeContourMetricError.invalidArguments
    }
    let kind = CommandLine.arguments[1]
    let before = try thumbnail(path: CommandLine.arguments[2])
    let after = try thumbnail(path: CommandLine.arguments[3])
    guard before.width == after.width, before.height == after.height else {
      throw ReshapeContourMetricError.invalidArguments
    }

    let beforeWidth: Double
    let afterWidth: Double
    switch kind {
    case "face":
      beforeWidth = try faceContourWidth(before)
      afterWidth = try faceContourWidth(after)
    case "body":
      beforeWidth = try torsoContourWidth(before)
      afterWidth = try torsoContourWidth(after)
    default:
      throw ReshapeContourMetricError.invalidArguments
    }
    let change = afterWidth / beforeWidth - 1
    try printJSON([
      "kind": kind,
      "before_width_ratio": beforeWidth,
      "after_width_ratio": afterWidth,
      "relative_change": change,
      "narrowed": change < 0,
      "sample_width": before.width,
      "sample_height": before.height,
    ])
  }

  private static func thumbnail(path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw ReshapeContourMetricError.unreadableImage
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 768,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
      throw ReshapeContourMetricError.unreadableImage
    }
    return image
  }

  private static func faceContourWidth(_ image: CGImage) throws -> Double {
    let request = VNDetectFaceLandmarksRequest()
    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
    guard
      let results = request.results,
      results.count == 1,
      let observation = results.first,
      observation.confidence >= 0.5,
      let contour = observation.landmarks?.faceContour,
      contour.pointCount >= 2
    else {
      throw ReshapeContourMetricError.ineligibleFace
    }
    let points = contour.normalizedPoints.map { point in
      VNImagePointForFaceLandmarkPoint(
        vector_float2(Float(point.x), Float(point.y)),
        observation.boundingBox,
        image.width,
        image.height
      )
    }
    let lowerFaceThreshold = (
      observation.boundingBox.minY + observation.boundingBox.height * 0.6
    ) * CGFloat(image.height)
    let lowerContour = points.filter { $0.y <= lowerFaceThreshold }
    guard
      lowerContour.count >= 2,
      let minimum = lowerContour.map(\.x).min(),
      let maximum = lowerContour.map(\.x).max(),
      maximum > minimum
    else {
      throw ReshapeContourMetricError.ineligibleFace
    }
    return Double(maximum - minimum) / Double(image.width)
  }

  private static func torsoContourWidth(_ image: CGImage) throws -> Double {
    let poseRequest = VNDetectHumanBodyPoseRequest()
    let segmentationRequest = VNGeneratePersonSegmentationRequest()
    segmentationRequest.qualityLevel = .accurate
    segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([
      poseRequest,
      segmentationRequest,
    ])
    guard
      let poses = poseRequest.results,
      poses.count == 1,
      let pose = poses.first,
      let segmentation = segmentationRequest.results?.first
    else {
      throw ReshapeContourMetricError.ineligibleBody
    }
    let leftShoulder = try pose.recognizedPoint(.leftShoulder)
    let rightShoulder = try pose.recognizedPoint(.rightShoulder)
    let leftHip = try pose.recognizedPoint(.leftHip)
    let rightHip = try pose.recognizedPoint(.rightHip)
    guard [leftShoulder, rightShoulder, leftHip, rightHip].allSatisfy({ $0.confidence >= 0.5 })
    else {
      throw ReshapeContourMetricError.ineligibleBody
    }
    let shoulderY = (leftShoulder.location.y + rightShoulder.location.y) / 2
    let hipY = (leftHip.location.y + rightHip.location.y) / 2
    let centerX = (
      leftShoulder.location.x + rightShoulder.location.x
        + leftHip.location.x + rightHip.location.x
    ) / 4
    guard shoulderY - hipY >= 0.12 else {
      throw ReshapeContourMetricError.ineligibleBody
    }

    let buffer = segmentation.pixelBuffer
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard
      CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8,
      let baseAddress = CVPixelBufferGetBaseAddress(buffer)
    else {
      throw ReshapeContourMetricError.segmentationUnavailable
    }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
    let widths = [0.35, 0.5, 0.65].compactMap { fraction in
      foregroundRunWidth(
        bytes: bytes,
        bytesPerRow: bytesPerRow,
        width: width,
        height: height,
        normalizedX: centerX,
        normalizedY: hipY + (shoulderY - hipY) * fraction
      )
    }.sorted()
    guard !widths.isEmpty else {
      throw ReshapeContourMetricError.segmentationUnavailable
    }
    return Double(widths[widths.count / 2]) / Double(width)
  }

  private static func foregroundRunWidth(
    bytes: UnsafePointer<UInt8>,
    bytesPerRow: Int,
    width: Int,
    height: Int,
    normalizedX: CGFloat,
    normalizedY: CGFloat
  ) -> Int? {
    let row = max(0, min(height - 1, Int((1 - normalizedY) * CGFloat(height - 1))))
    let expectedCenter = max(0, min(width - 1, Int(normalizedX * CGFloat(width - 1))))
    let rowStart = bytes.advanced(by: row * bytesPerRow)
    let searchRadius = max(2, width / 12)
    let candidates = (max(0, expectedCenter - searchRadius)...min(
      width - 1,
      expectedCenter + searchRadius
    ))
    guard let center = candidates
      .filter({ rowStart[$0] >= 128 })
      .min(by: { abs($0 - expectedCenter) < abs($1 - expectedCenter) })
    else {
      return nil
    }
    var left = center
    var right = center
    while left > 0, rowStart[left - 1] >= 128 { left -= 1 }
    while right + 1 < width, rowStart[right + 1] >= 128 { right += 1 }
    return right - left + 1
  }

  private static func printJSON(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
