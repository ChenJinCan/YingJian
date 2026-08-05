import CoreGraphics
import CoreImage
import Foundation
import ImageIO

private enum FilePipelineProbeError: Error {
  case invalidArguments
  case invalidPipeline
  case unreadableOutput
}

@main
private enum IOSFilePipelineProbe {
  static func main() throws {
    if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "identity" {
      try printJSON([
        "pipelineSchema": 3,
        "workingColorSpace": "srgb",
        "portraitStrength": 0,
        "faceSlimStrength": 0,
        "bodySlimStrength": 0,
        "outputFormat": "jpeg",
      ])
      return
    }
    if CommandLine.arguments.count == 3,
       CommandLine.arguments[1] == "body-applicable"
    {
      let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
      guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
        throw FilePipelineProbeError.invalidArguments
      }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        // Keep this probe aligned with AppDelegate.analyzePhoto so engineering
        // evidence cannot pass at a resolution the product never uses.
        kCGImageSourceThumbnailMaxPixelSize: Int(IOSPortraitRetoucher.analysisMaxEdge),
        kCGImageSourceShouldCacheImmediately: true,
      ]
      guard let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      ) else {
        throw FilePipelineProbeError.invalidArguments
      }
      try printJSON([
        "body_applicable": IOSPortraitRetoucher.bodySlimApplicable(image: image),
      ])
      return
    }
    if CommandLine.arguments.count == 3,
       CommandLine.arguments[1] == "reshape-applicability"
    {
      guard let source = CIImage(
        contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]),
        options: [.applyOrientationProperty: true]
      ) else {
        throw FilePipelineProbeError.invalidArguments
      }
      let normalized = source.transformed(
        by: CGAffineTransform(
          translationX: -source.extent.minX,
          y: -source.extent.minY
        )
      )
      let extent = normalized.extent.integral
      let context = IOSPortraitRetoucher.prepare(source: normalized, extent: extent)
      var result: [String: Any] = [
        "face_slim_applicable": context.faceSlimGeometry != nil && context.faceMask != nil,
        "body_slim_applicable": context.bodySlimGeometry != nil && context.personMask != nil,
      ]
      if let geometry = context.faceSlimGeometry {
        result["face_center_x"] = geometry.centerX
        result["face_half_width"] = geometry.halfWidth
        result["face_lower_y"] = geometry.lowerY
        result["face_upper_y"] = geometry.upperY
        result["face_height"] = geometry.upperY - geometry.lowerY
        if let mask = context.faceMask {
          result["face_mask_roi_mean"] = sampledRedMean(
            mask.cropped(to: geometry.influenceRect)
          )
        }
      }
      if let mask = context.faceMask {
        result["face_mask_mean"] = sampledRedMean(mask)
      }
      if let geometry = context.bodySlimGeometry {
        result["body_center_x"] = geometry.centerX
        result["body_half_width"] = geometry.halfWidth
        result["body_lower_y"] = geometry.lowerY
        result["body_upper_y"] = geometry.upperY
        result["body_height"] = geometry.upperY - geometry.lowerY
        if let mask = context.personMask {
          result["person_mask_roi_mean"] = sampledRedMean(
            mask.cropped(to: geometry.influenceRect)
          )
        }
      }
      if let mask = context.personMask {
        result["person_mask_mean"] = sampledRedMean(mask)
      }
      try printJSON(result)
      return
    }
    guard CommandLine.arguments.count == 4 else {
      throw FilePipelineProbeError.invalidArguments
    }

    let sourcePath = CommandLine.arguments[1]
    let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let recipeURL = URL(fileURLWithPath: CommandLine.arguments[3])
    let recipeData = try Data(contentsOf: recipeURL)
    let recipe = try JSONSerialization.jsonObject(with: recipeData)
    guard let pipeline = IOSImagePipeline(arguments: recipe) else {
      throw FilePipelineProbeError.invalidPipeline
    }
    let artifact = try IOSPhotoFileRenderer(
      context: CIContext(options: [.cacheIntermediates: false])
    ).render(
      sourcePath: sourcePath,
      pipeline: pipeline,
      destinationURL: destinationURL
    )
    guard
      let source = CGImageSourceCreateWithURL(destinationURL as CFURL, nil),
      let type = CGImageSourceGetType(source) as String?,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw FilePipelineProbeError.unreadableOutput
    }

    try printJSON([
      "width": artifact.width,
      "height": artifact.height,
      "format": type == "public.jpeg" ? "jpeg" : type,
      "color_space": image.colorSpace?.name as String? ?? "unknown",
      "orientation": properties[kCGImagePropertyOrientation as String] as? Int ?? 1,
      "has_gps": properties[kCGImagePropertyGPSDictionary as String] != nil,
      "has_device_identity": containsDeviceIdentity(properties),
    ])
  }

  private static func containsDeviceIdentity(_ properties: [String: Any]) -> Bool {
    let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
    let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
    let tiffKeys = [
      kCGImagePropertyTIFFMake as String,
      kCGImagePropertyTIFFModel as String,
      kCGImagePropertyTIFFSoftware as String,
    ]
    let exifKeys = [
      kCGImagePropertyExifLensMake as String,
      kCGImagePropertyExifLensModel as String,
      kCGImagePropertyExifCameraOwnerName as String,
      kCGImagePropertyExifBodySerialNumber as String,
    ]
    return tiffKeys.contains { tiff[$0] != nil }
      || exifKeys.contains { exif[$0] != nil }
      || properties[kCGImagePropertyMakerAppleDictionary as String] != nil
  }

  private static func sampledRedMean(_ image: CIImage) -> Double {
    let values = sampledRedValues(image)
    guard !values.isEmpty else { return 0 }
    return Double(values.reduce(0, { $0 + Int($1) })) / Double(values.count) / 255
  }

  private static func sampledRedValues(_ image: CIImage) -> [UInt8] {
    let extent = image.extent.integral
    let normalized = image.transformed(
      by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
    )
    let scale = min(1, 128 / max(extent.width, extent.height))
    let sampled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let bounds = sampled.extent.integral
    let width = max(1, Int(bounds.width))
    let height = max(1, Int(bounds.height))
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    CIContext(options: [.cacheIntermediates: false]).render(
      sampled,
      toBitmap: &bytes,
      rowBytes: width * 4,
      bounds: bounds,
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    return stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] }
  }

  private static func printJSON(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
