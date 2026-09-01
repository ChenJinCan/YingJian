import AVFoundation
import CoreImage
import XCTest

@testable import Runner

final class IOSMotionPhotoRendererTests: XCTestCase {
  private let imageContext = CIContext(options: [.cacheIntermediates: false])
  private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  func testEachExplicitEffectWritesItsOwnReadableMovingMP4() throws {
    let source = temporaryURL(extension: "jpg")
    try writeStripedJpeg(to: source, width: 96, height: 64)
    var outputs = [URL]()
    defer { removeTemporaryFiles([source] + outputs) }

    for effect in IOSMotionPhotoEffect.allCases {
      let output = temporaryURL(extension: "mp4")
      outputs.append(output)
      let completed = expectation(description: "\(effect.rawValue) render")
      var renderResult: Result<IOSMotionPhotoRenderedFile, Error>?

      IOSMotionPhotoRenderer(context: imageContext).render(
        sourcePath: source.path,
        effect: effect,
        destinationURL: output
      ) { result in
        renderResult = result
        completed.fulfill()
      }
      wait(for: [completed], timeout: 10)

      let artifact = try XCTUnwrap(renderResult).get()
      XCTAssertEqual(artifact.effect, effect)
      XCTAssertEqual(artifact.width, 96)
      XCTAssertEqual(artifact.height, 64)
      XCTAssertEqual(artifact.durationMilliseconds, 2_000)
      XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))

      let asset = AVURLAsset(url: output)
      let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
      XCTAssertEqual(track.naturalSize, CGSize(width: 96, height: 64))
      XCTAssertEqual(CMTimeGetSeconds(asset.duration), 2, accuracy: 0.05)
      let imageGenerator = AVAssetImageGenerator(asset: asset)
      imageGenerator.appliesPreferredTrackTransform = true
      let earlyFrame = try imageGenerator.copyCGImage(
        at: CMTime(seconds: 0.1, preferredTimescale: 600),
        actualTime: nil
      )
      let lateFrame = try imageGenerator.copyCGImage(
        at: CMTime(seconds: 1.8, preferredTimescale: 600),
        actualTime: nil
      )
      XCTAssertGreaterThan(
        meanAbsoluteDifference(
          try rgbaBytes(CIImage(cgImage: earlyFrame)),
          try rgbaBytes(CIImage(cgImage: lateFrame))
        ),
        1,
        "\(effect.rawValue) must produce temporal image changes"
      )
    }
  }

  func testUnknownEffectIsNotSubstituted() {
    XCTAssertNil(IOSMotionPhotoEffect(rawValue: "automatic"))
  }

  private func writeStripedJpeg(to url: URL, width: Int, height: Int) throws {
    let extent = CGRect(x: 0, y: 0, width: width, height: height)
    var image = CIImage(color: .black).cropped(to: extent)
    for x in stride(from: 0, to: width, by: 4) {
      let color = (x / 4).isMultiple(of: 2) ? CIColor.white : CIColor.red
      let stripe = CGRect(x: x, y: 0, width: 4, height: height)
      image = CIImage(color: color).cropped(to: stripe).composited(over: image)
    }
    try imageContext.writeJPEGRepresentation(
      of: image,
      to: url,
      colorSpace: sRGB,
      options: [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
      ]
    )
  }

  private func rgbaBytes(_ image: CIImage) throws -> [UInt8] {
    let bounds = image.extent.integral
    var bytes = [UInt8](repeating: 0, count: Int(bounds.width * bounds.height) * 4)
    bytes.withUnsafeMutableBytes { buffer in
      imageContext.render(
        image,
        toBitmap: buffer.baseAddress!,
        rowBytes: Int(bounds.width) * 4,
        bounds: bounds,
        format: .RGBA8,
        colorSpace: sRGB
      )
    }
    return bytes
  }

  private func meanAbsoluteDifference(_ left: [UInt8], _ right: [UInt8]) -> Double {
    guard left.count == right.count, !left.isEmpty else { return .infinity }
    let total = zip(left, right).reduce(0) { result, pair in
      result + abs(Int(pair.0) - Int(pair.1))
    }
    return Double(total) / Double(left.count)
  }

  private func temporaryURL(extension fileExtension: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-motion-test-\(UUID().uuidString)")
      .appendingPathExtension(fileExtension)
  }

  private func removeTemporaryFiles(_ urls: [URL]) {
    for url in urls {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
