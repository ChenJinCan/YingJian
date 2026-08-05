import CoreGraphics
import CoreImage
import Foundation

private enum RenderSemanticMeasurementError: Error {
  case invalidArguments
  case unreadableImage
  case invalidDimensions
  case renderFailed
}

@main
private enum RenderSemanticMeasurement {
  static func main() throws {
    guard
      CommandLine.arguments.count == 3,
      let maxEdge = Int(CommandLine.arguments[2]),
      maxEdge > 0
    else {
      throw RenderSemanticMeasurementError.invalidArguments
    }
    guard
      let input = CIImage(
        contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]),
        options: [.applyOrientationProperty: true]
      )
    else {
      throw RenderSemanticMeasurementError.unreadableImage
    }
    let normalized = input.transformed(
      by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY)
    )
    let longest = max(normalized.extent.width, normalized.extent.height)
    guard longest > 0 else { throw RenderSemanticMeasurementError.invalidDimensions }
    let scale = min(1, CGFloat(maxEdge) / longest)
    let sampled = normalized
      .applyingFilter(
        "CILanczosScaleTransform",
        parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
      )
    let extent = sampled.extent.integral
    let width = Int(extent.width)
    let height = Int(extent.height)
    guard width > 0, height > 0 else {
      throw RenderSemanticMeasurementError.invalidDimensions
    }
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw RenderSemanticMeasurementError.renderFailed
    }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let context = CIContext(options: [.cacheIntermediates: false])
    context.render(
      sampled,
      toBitmap: &bytes,
      rowBytes: width * 4,
      bounds: extent,
      format: .RGBA8,
      colorSpace: colorSpace
    )

    let pixels = width * height
    var lumaSum = 0.0
    var lumaSquaredSum = 0.0
    var redSum = 0.0
    var greenSum = 0.0
    var blueSum = 0.0
    var chromaSum = 0.0
    var rgbMidpointDistanceSum = 0.0
    var blackClips = 0
    var whiteClips = 0
    var luma = [Double](repeating: 0, count: pixels)
    for pixel in 0..<pixels {
      let offset = pixel * 4
      let red = Double(bytes[offset]) / 255
      let green = Double(bytes[offset + 1]) / 255
      let blue = Double(bytes[offset + 2]) / 255
      let value = 0.2126 * red + 0.7152 * green + 0.0722 * blue
      luma[pixel] = value
      lumaSum += value
      lumaSquaredSum += value * value
      redSum += red
      greenSum += green
      blueSum += blue
      chromaSum += max(red, green, blue) - min(red, green, blue)
      rgbMidpointDistanceSum += (
        abs(red - 0.5) + abs(green - 0.5) + abs(blue - 0.5)
      ) / 3
      blackClips += max(red, green, blue) <= 1.0 / 255 ? 1 : 0
      whiteClips += min(red, green, blue) >= 254.0 / 255 ? 1 : 0
    }
    var edgeSum = 0.0
    var edgeCount = 0
    if width > 1 || height > 1 {
      for y in 0..<height {
        for x in 0..<width {
          let value = luma[y * width + x]
          if x + 1 < width {
            edgeSum += abs(value - luma[y * width + x + 1])
            edgeCount += 1
          }
          if y + 1 < height {
            edgeSum += abs(value - luma[(y + 1) * width + x])
            edgeCount += 1
          }
        }
      }
    }
    let count = Double(pixels)
    let meanLuma = lumaSum / count
    let variance = max(0, lumaSquaredSum / count - meanLuma * meanLuma)
    let result: [String: Any] = [
      "sample_width": width,
      "sample_height": height,
      "sample_pixels": pixels,
      "mean_luma": meanLuma,
      "luma_standard_deviation": sqrt(variance),
      "mean_rgb": [redSum / count, greenSum / count, blueSum / count],
      "mean_chroma": chromaSum / count,
      "mean_rgb_midpoint_distance": rgbMidpointDistanceSum / count,
      "mean_edge_energy": edgeCount == 0 ? 0 : edgeSum / Double(edgeCount),
      "black_clip_ratio": Double(blackClips) / count,
      "white_clip_ratio": Double(whiteClips) / count,
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
