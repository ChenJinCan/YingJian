import AVFoundation
import AVKit
import Flutter
import Foundation
import Photos
import UIKit

enum IOSGeneratedMediaKind: String {
  case image
  case imageMotion

  var allowedExtensions: Set<String> {
    switch self {
    case .image:
      return ["jpg", "jpeg", "png", "heic", "heif"]
    case .imageMotion:
      return ["mp4"]
    }
  }

  var photoLibraryResourceType: PHAssetResourceType {
    switch self {
    case .image:
      return .photo
    case .imageMotion:
      return .video
    }
  }
}

struct IOSGeneratedMediaRequest {
  let url: URL
  let kind: IOSGeneratedMediaKind

  init?(arguments: Any?, requireExistingFile: Bool = true) {
    guard
      let values = arguments as? [String: Any],
      let path = values["path"] as? String,
      !path.isEmpty,
      path.first == "/",
      !path.contains("\0"),
      let kindName = values["kind"] as? String,
      let kind = IOSGeneratedMediaKind(rawValue: kindName)
    else {
      return nil
    }
    let url = URL(fileURLWithPath: path)
      .resolvingSymlinksInPath()
      .standardizedFileURL
    guard kind.allowedExtensions.contains(url.pathExtension.lowercased()) else {
      return nil
    }
    if requireExistingFile {
      var isDirectory = ObjCBool(false)
      guard
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        !isDirectory.boolValue,
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      else {
        return nil
      }
    }
    self.url = url
    self.kind = kind
  }
}

enum IOSGeneratedMediaPreviewFactory {
  static func makePausedPlayer(url: URL) -> AVPlayer {
    let player = AVPlayer(url: url)
    player.pause()
    return player
  }
}

/// Bridges explicit completed-media actions without exposing a provider SDK to
/// Flutter. Generation alone never invokes this channel.
final class IOSGeneratedMediaActionsChannel {
  private let channel: FlutterMethodChannel
  private let presenterProvider: () -> UIViewController?
  private weak var activePlayerController: AVPlayerViewController?

  init(
    messenger: FlutterBinaryMessenger,
    presenterProvider: @escaping () -> UIViewController?
  ) {
    self.presenterProvider = presenterProvider
    channel = FlutterMethodChannel(
      name: "yingjian/generated_media_actions",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let request = IOSGeneratedMediaRequest(arguments: call.arguments) else {
      result(FlutterError(
        code: "invalidArguments",
        message: "A matching generated-media path and kind are required",
        details: nil
      ))
      return
    }
    switch call.method {
    case "saveToPhotoLibrary":
      save(request: request, result: result)
    case "previewMotion":
      guard request.kind == .imageMotion else {
        result(FlutterError(
          code: "invalidMediaKind",
          message: "Only generated MP4 motion media can be previewed",
          details: nil
        ))
        return
      }
      preview(request: request, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func save(
    request: IOSGeneratedMediaRequest,
    result: @escaping FlutterResult
  ) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "photoAccessDenied",
            message: "Photo library add access was denied",
            details: nil
          ))
        }
        return
      }
      var assetId: String?
      PHPhotoLibrary.shared().performChanges {
        let creation = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = request.url.lastPathComponent
        creation.addResource(
          with: request.kind.photoLibraryResourceType,
          fileURL: request.url,
          options: options
        )
        assetId = creation.placeholderForCreatedAsset?.localIdentifier
      } completionHandler: { success, _ in
        DispatchQueue.main.async {
          guard success, let assetId, !assetId.isEmpty else {
            result(FlutterError(
              code: "saveFailed",
              message: "Generated media could not be saved",
              details: nil
            ))
            return
          }
          result(["assetId": assetId])
        }
      }
    }
  }

  private func preview(
    request: IOSGeneratedMediaRequest,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async { [weak self] in
      guard
        let self,
        self.activePlayerController?.presentingViewController == nil,
        let presenter = self.presenterProvider()
      else {
        result(FlutterError(
          code: "previewUnavailable",
          message: "Motion preview is currently unavailable",
          details: nil
        ))
        return
      }
      let controller = AVPlayerViewController()
      controller.showsPlaybackControls = true
      controller.player = IOSGeneratedMediaPreviewFactory.makePausedPlayer(
        url: request.url
      )
      self.activePlayerController = controller
      presenter.present(controller, animated: true) {
        // The player remains paused until the user presses the native play
        // control. Presenting the preview itself never starts playback.
        controller.player?.pause()
        result(nil)
      }
    }
  }
}
