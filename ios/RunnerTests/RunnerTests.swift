import Flutter
import ImageIO
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testExportMetadataPreservesCaptureTimeAndRemovesSensitiveFields() throws {
    let source: [String: Any] = [
      kCGImagePropertyOrientation as String: 6,
      kCGImagePropertyGPSDictionary as String: [
        kCGImagePropertyGPSLatitude as String: 31.2
      ],
      kCGImagePropertyExifDictionary as String: [
        kCGImagePropertyExifDateTimeOriginal as String: "2026:08:04 13:14:15",
        kCGImagePropertyExifDateTimeDigitized as String: "2026:08:04 13:14:16",
        kCGImagePropertyExifMakerNote as String: Data([1, 2, 3]),
      ],
      kCGImagePropertyTIFFDictionary as String: [
        kCGImagePropertyTIFFDateTime as String: "2026:08:04 13:14:15",
        kCGImagePropertyTIFFMake as String: "Private camera make",
      ],
    ]

    let sanitized = ImageExportMetadata.sanitize(source)
    let exif = sanitized[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let tiff = sanitized[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

    XCTAssertEqual(sanitized[kCGImagePropertyOrientation as String] as? Int, 1)
    XCTAssertNil(sanitized[kCGImagePropertyGPSDictionary as String])
    XCTAssertEqual(
      exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String,
      "2026:08:04 13:14:15"
    )
    XCTAssertNil(exif?[kCGImagePropertyExifMakerNote as String])
    XCTAssertEqual(
      tiff?[kCGImagePropertyTIFFDateTime as String] as? String,
      "2026:08:04 13:14:15"
    )
    XCTAssertNil(tiff?[kCGImagePropertyTIFFMake as String])
    let captureDate = ImageExportMetadata.captureDate(from: sanitized)
    let components = Calendar(identifier: .gregorian).dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: try XCTUnwrap(captureDate)
    )
    XCTAssertEqual(components.year, 2026)
    XCTAssertEqual(components.month, 8)
    XCTAssertEqual(components.day, 4)
    XCTAssertEqual(components.hour, 13)
    XCTAssertEqual(components.minute, 14)
    XCTAssertEqual(components.second, 15)
  }

}
