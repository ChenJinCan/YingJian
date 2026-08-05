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
        "pipelineSchema": 2,
        "workingColorSpace": "srgb",
        "portraitStrength": 0,
        "outputFormat": "jpeg",
      ])
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

  private static func printJSON(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
