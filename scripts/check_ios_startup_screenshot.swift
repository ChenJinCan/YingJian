import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(
    Data("usage: check_ios_startup_screenshot.swift SCREENSHOT.png\n".utf8)
  )
  exit(64)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
guard
  let source = CGImageSourceCreateWithURL(url, nil),
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
  FileHandle.standardError.write(Data("Unable to decode startup screenshot\n".utf8))
  exit(65)
}

let width = image.width
let height = image.height
guard width >= 100, height >= 200 else {
  FileHandle.standardError.write(Data("Startup screenshot is unexpectedly small\n".utf8))
  exit(65)
}

var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard
  let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )
else {
  FileHandle.standardError.write(Data("Unable to inspect startup screenshot\n".utf8))
  exit(70)
}
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

// Exclude the status bar, Dynamic Island, home indicator and screen edges.
// The remaining region must contain visible app UI, not only a white launch view.
let xStart = width / 20
let xEnd = width - xStart
let yStart = height / 5
let yEnd = height * 9 / 10
var inspected = 0
var darkOrColored = 0
for y in yStart..<yEnd {
  for x in xStart..<xEnd {
    let offset = (y * width + x) * 4
    let red = Int(pixels[offset])
    let green = Int(pixels[offset + 1])
    let blue = Int(pixels[offset + 2])
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let luminance = (red * 54 + green * 183 + blue * 19) / 256
    inspected += 1
    if luminance < 205 || maximum - minimum > 24 {
      darkOrColored += 1
    }
  }
}

let visibleRatio = Double(darkOrColored) / Double(inspected)
guard visibleRatio >= 0.005 else {
  FileHandle.standardError.write(
    Data(
      String(
        format: "Startup content remained blank (visible ratio %.4f)\n",
        visibleRatio
      ).utf8
    )
  )
  exit(1)
}

print(String(format: "iOS startup screenshot is nonblank (visible ratio %.4f)", visibleRatio))
