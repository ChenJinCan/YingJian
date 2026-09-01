import AVFoundation
import Photos
import XCTest
@testable import Runner

final class IOSGeneratedMediaActionsChannelTests: XCTestCase {
  func testRequestRequiresMatchingImageOrMotionExtension() throws {
    let image = temporaryURL(extension: "jpg")
    let motion = temporaryURL(extension: "mp4")
    defer { removeTemporaryFiles(image, motion) }
    try Data([0x01]).write(to: image)
    try Data([0x02]).write(to: motion)

    let imageRequest = IOSGeneratedMediaRequest(arguments: [
      "path": image.path,
      "kind": "image",
    ])
    let motionRequest = IOSGeneratedMediaRequest(arguments: [
      "path": motion.path,
      "kind": "imageMotion",
    ])

    XCTAssertEqual(imageRequest?.kind, .image)
    XCTAssertEqual(
      imageRequest?.kind.photoLibraryResourceType,
      PHAssetResourceType.photo
    )
    XCTAssertEqual(motionRequest?.kind, .imageMotion)
    XCTAssertEqual(
      motionRequest?.kind.photoLibraryResourceType,
      PHAssetResourceType.video
    )
    XCTAssertNil(IOSGeneratedMediaRequest(arguments: [
      "path": image.path,
      "kind": "imageMotion",
    ]))
    XCTAssertNil(IOSGeneratedMediaRequest(arguments: [
      "path": motion.path,
      "kind": "image",
    ]))
  }

  func testRequestRejectsRelativeMissingAndUnsupportedPaths() throws {
    let text = temporaryURL(extension: "txt")
    defer { removeTemporaryFiles(text) }
    try Data([0x01]).write(to: text)

    XCTAssertNil(IOSGeneratedMediaRequest(arguments: [
      "path": "relative/result.mp4",
      "kind": "imageMotion",
    ]))
    XCTAssertNil(IOSGeneratedMediaRequest(arguments: [
      "path": temporaryURL(extension: "mp4").path,
      "kind": "imageMotion",
    ]))
    XCTAssertNil(IOSGeneratedMediaRequest(arguments: [
      "path": text.path,
      "kind": "image",
    ]))
  }

  func testMotionPreviewPlayerStartsPaused() {
    let player = IOSGeneratedMediaPreviewFactory.makePausedPlayer(
      url: temporaryURL(extension: "mp4")
    )

    XCTAssertEqual(player.rate, 0)
    XCTAssertEqual(player.timeControlStatus, .paused)
  }

  private func temporaryURL(extension fileExtension: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-generated-media-test-\(UUID().uuidString)")
      .appendingPathExtension(fileExtension)
  }

  private func removeTemporaryFiles(_ urls: URL...) {
    for url in urls {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
