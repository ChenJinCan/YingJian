import CoreFoundation
import CoreImage
import Flutter
import Foundation

struct IOSPhotoUpscaleRequest {
  let sourcePath: String
  let scaleFactor: Int

  init?(arguments: Any?) {
    guard
      let values = arguments as? [String: Any],
      let sourcePath = values["sourcePath"] as? String,
      !sourcePath.isEmpty,
      let scaleNumber = values["scaleFactor"] as? NSNumber,
      CFGetTypeID(scaleNumber) != CFBooleanGetTypeID(),
      scaleNumber.doubleValue.rounded(.towardZero) == scaleNumber.doubleValue,
      scaleNumber.intValue == 2 || scaleNumber.intValue == 4
    else {
      return nil
    }
    self.sourcePath = sourcePath
    scaleFactor = scaleNumber.intValue
  }
}

/// Owns the iOS bridge for deterministic Core Image high-quality scaling.
/// It intentionally does not describe this result as AI detail generation.
final class IOSPhotoUpscaleChannel {
  private let channel: FlutterMethodChannel
  private let renderer: IOSHighQualityPhotoScaler
  private let workQueue = DispatchQueue(
    label: "com.babycompany.yingjian.photo-upscale",
    qos: .userInitiated
  )

  init(
    messenger: FlutterBinaryMessenger,
    context: CIContext = CIContext(options: [.cacheIntermediates: false])
  ) {
    channel = FlutterMethodChannel(
      name: "yingjian/photo_upscale",
      binaryMessenger: messenger
    )
    renderer = IOSHighQualityPhotoScaler(context: context)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "generateHighQualityScale" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let request = IOSPhotoUpscaleRequest(arguments: call.arguments) else {
      result(FlutterError(
        code: "invalidArguments",
        message: "A source path and an explicit 2x or 4x scale are required",
        details: nil
      ))
      return
    }
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0].appendingPathComponent("upscale-results", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    } catch {
      result(FlutterError(
        code: "photoUpscaleUnavailable",
        message: "The high-quality scale result directory is unavailable",
        details: nil
      ))
      return
    }
    let outputURL = directory
      .appendingPathComponent("Yingjian_upscale_\(UUID().uuidString)")
      .appendingPathExtension("jpg")
    workQueue.async { [renderer] in
      do {
        let artifact = try renderer.render(
          sourcePath: request.sourcePath,
          scaleFactor: request.scaleFactor,
          destinationURL: outputURL
        )
        DispatchQueue.main.async {
          result([
            "outputPath": artifact.outputPath,
            "contentSha256": artifact.contentSha256,
            "scaleFactor": artifact.scaleFactor,
            "width": artifact.width,
            "height": artifact.height,
          ])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "photoUpscaleFailed",
            message: "The selected high-quality scale could not be rendered",
            details: nil
          ))
        }
      }
    }
  }
}
