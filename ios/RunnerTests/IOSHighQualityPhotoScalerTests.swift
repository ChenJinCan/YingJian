import CoreImage
import CryptoKit
import ImageIO
import XCTest
@testable import Runner

final class IOSHighQualityPhotoScalerTests: XCTestCase {
  private let context = CIContext(options: [.cacheIntermediates: false])
  private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  func testFourXWritesExactDimensionsToANewFileAndPreservesSourceBytes() throws {
    let source = temporaryURL(extension: "jpg")
    let output = temporaryURL(extension: "jpg")
    try writeJpeg(to: source, width: 40, height: 30)
    let sourceDigest = try sha256(source)
    defer { removeTemporaryFiles(source, output) }

    let artifact = try IOSHighQualityPhotoScaler(context: context).render(
      sourcePath: source.path,
      scaleFactor: 4,
      destinationURL: output
    )

    XCTAssertEqual(artifact.outputPath, output.path)
    XCTAssertEqual(artifact.scaleFactor, 4)
    XCTAssertEqual(artifact.width, 160)
    XCTAssertEqual(artifact.height, 120)
    XCTAssertEqual(try imageDimensions(output), CGSize(width: 160, height: 120))
    XCTAssertEqual(try sha256(source), sourceDigest)
  }

  func testRequestRequiresAnExplicitSupportedScaleFactor() {
    XCTAssertNil(IOSPhotoUpscaleRequest(arguments: [
      "sourcePath": "/private/project/source.heic"
    ]))
    XCTAssertNil(IOSPhotoUpscaleRequest(arguments: [
      "sourcePath": "/private/project/source.heic",
      "scaleFactor": 3,
    ]))
    XCTAssertEqual(
      IOSPhotoUpscaleRequest(arguments: [
        "sourcePath": "/private/project/source.heic",
        "scaleFactor": 2,
      ])?.scaleFactor,
      2
    )
  }

  private func writeJpeg(to url: URL, width: Int, height: Int) throws {
    let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.7))
      .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    try context.writeJPEGRepresentation(
      of: image,
      to: url,
      colorSpace: sRGB,
      options: [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95
      ]
    )
  }

  private func imageDimensions(_ url: URL) throws -> CGSize {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let properties = try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    )
    let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? NSNumber)
    let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? NSNumber)
    return CGSize(width: width.doubleValue, height: height.doubleValue)
  }

  private func sha256(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func temporaryURL(extension fileExtension: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-upscale-test-\(UUID().uuidString)")
      .appendingPathExtension(fileExtension)
  }

  private func removeTemporaryFiles(_ urls: URL...) {
    for url in urls {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
