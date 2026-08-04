import Flutter
import CoreImage
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var photoExportChannel: FlutterMethodChannel?
  private let photoExportContext = CIContext(options: [.cacheIntermediates: false])

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "YingjianPhotoExporter"
    ) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "yingjian/photo_export",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "exportPhoto" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.exportPhoto(arguments: call.arguments, result: result)
    }
    photoExportChannel = channel
  }

  private func exportPhoto(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let values = arguments as? [String: Any],
      let sourcePath = values["sourcePath"] as? String,
      let redScale = (values["redScale"] as? NSNumber)?.doubleValue,
      let greenScale = (values["greenScale"] as? NSNumber)?.doubleValue,
      let blueScale = (values["blueScale"] as? NSNumber)?.doubleValue,
      let redBias = (values["redBias"] as? NSNumber)?.doubleValue,
      let greenBias = (values["greenBias"] as? NSNumber)?.doubleValue,
      let blueBias = (values["blueBias"] as? NSNumber)?.doubleValue
    else {
      result(FlutterError(code: "invalidArguments", message: "Invalid export request", details: nil))
      return
    }

    PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "photoAccessDenied", message: "Photo access denied", details: nil))
        }
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        self?.renderAndSave(
          sourcePath: sourcePath,
          redScale: redScale,
          greenScale: greenScale,
          blueScale: blueScale,
          redBias: redBias,
          greenBias: greenBias,
          blueBias: blueBias,
          result: result
        )
      }
    }
  }

  private func renderAndSave(
    sourcePath: String,
    redScale: Double,
    greenScale: Double,
    blueScale: Double,
    redBias: Double,
    greenBias: Double,
    blueBias: Double,
    result: @escaping FlutterResult
  ) {
    guard let input = CIImage(
      contentsOf: URL(fileURLWithPath: sourcePath),
      options: [.applyOrientationProperty: true]
    ) else {
      finishWithError(code: "decodeFailed", message: "Photo could not be decoded", result: result)
      return
    }
    let filter = CIFilter(name: "CIColorMatrix")
    filter?.setValue(input, forKey: kCIInputImageKey)
    filter?.setValue(CIVector(x: redScale, y: 0, z: 0, w: 0), forKey: "inputRVector")
    filter?.setValue(CIVector(x: 0, y: greenScale, z: 0, w: 0), forKey: "inputGVector")
    filter?.setValue(CIVector(x: 0, y: 0, z: blueScale, w: 0), forKey: "inputBVector")
    filter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
    filter?.setValue(
      CIVector(x: redBias, y: greenBias, z: blueBias, w: 0),
      forKey: "inputBiasVector"
    )
    guard
      let output = filter?.outputImage,
      let image = photoExportContext.createCGImage(output, from: output.extent),
      let data = UIImage(cgImage: image).jpegData(compressionQuality: 1)
    else {
      finishWithError(code: "renderFailed", message: "Photo could not be rendered", result: result)
      return
    }

    var assetId: String?
    PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions()
      options.originalFilename = "Yingjian_\(Int(Date().timeIntervalSince1970)).jpg"
      request.addResource(with: .photo, data: data, options: options)
      assetId = request.placeholderForCreatedAsset?.localIdentifier
    } completionHandler: { success, _ in
      DispatchQueue.main.async {
        guard success, let assetId else {
          result(FlutterError(code: "saveFailed", message: "Photo could not be saved", details: nil))
          return
        }
        result(["assetId": assetId, "width": image.width, "height": image.height])
      }
    }
  }

  private func finishWithError(
    code: String,
    message: String,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      result(FlutterError(code: code, message: message, details: nil))
    }
  }
}
