import AVFoundation
import CoreImage
import CryptoKit
import Foundation

enum IOSMotionPhotoEffect: String, CaseIterable {
  case subtle
  case cameraPush
  case lightFlow
}

struct IOSMotionPhotoRenderedFile {
  let effect: IOSMotionPhotoEffect
  let contentSha256: String
  let width: Int
  let height: Int
  let durationMilliseconds: Int
}

enum IOSMotionPhotoRenderError: Error {
  case invalidSource
  case invalidDestination
  case destinationExists
  case writerSetupFailed
  case pixelBufferCreationFailed
  case frameAppendFailed
  case renderFailed
}

/// Turns one app-owned static source into a deterministic local MP4 for the
/// single effect explicitly selected by the caller.
struct IOSMotionPhotoRenderer {
  static let durationMilliseconds = 2_000
  static let frameRate = 30
  static let maximumLongEdge = 720

  let context: CIContext

  func render(
    sourcePath: String,
    effect: IOSMotionPhotoEffect,
    destinationURL: URL,
    completion: @escaping (Result<IOSMotionPhotoRenderedFile, Error>) -> Void
  ) {
    guard
      !sourcePath.isEmpty,
      let source = CIImage(
        contentsOf: URL(fileURLWithPath: sourcePath),
        options: [.applyOrientationProperty: true]
      )
    else {
      completion(.failure(IOSMotionPhotoRenderError.invalidSource))
      return
    }
    guard destinationURL.pathExtension.lowercased() == "mp4" else {
      completion(.failure(IOSMotionPhotoRenderError.invalidDestination))
      return
    }
    guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
      completion(.failure(IOSMotionPhotoRenderError.destinationExists))
      return
    }
    let normalizedSource = source.transformed(
      by: CGAffineTransform(
        translationX: -source.extent.minX,
        y: -source.extent.minY
      )
    )
    let sourceExtent = normalizedSource.extent.integral
    guard
      sourceExtent.width.isFinite,
      sourceExtent.height.isFinite,
      sourceExtent.width >= 2,
      sourceExtent.height >= 2
    else {
      completion(.failure(IOSMotionPhotoRenderError.invalidSource))
      return
    }
    let outputSize = Self.outputSize(for: sourceExtent.size)
    let outputExtent = CGRect(origin: .zero, size: outputSize)
    let baseImage =
      normalizedSource
      .transformed(
        by: CGAffineTransform(
          scaleX: outputSize.width / sourceExtent.width,
          y: outputSize.height / sourceExtent.height
        )
      )
      .cropped(to: outputExtent)
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)
    } catch {
      completion(.failure(IOSMotionPhotoRenderError.writerSetupFailed))
      return
    }
    let width = Int(outputSize.width)
    let height = Int(outputSize.height)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: 1_800_000,
          AVVideoExpectedSourceFrameRateKey: Self.frameRate,
          AVVideoMaxKeyFrameIntervalKey: Self.frameRate,
        ],
      ]
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ]
    )
    guard writer.canAdd(input) else {
      completion(.failure(IOSMotionPhotoRenderError.writerSetupFailed))
      return
    }
    writer.add(input)
    guard writer.startWriting() else {
      try? FileManager.default.removeItem(at: destinationURL)
      completion(.failure(IOSMotionPhotoRenderError.writerSetupFailed))
      return
    }
    writer.startSession(atSourceTime: .zero)
    guard let pixelBufferPool = adaptor.pixelBufferPool else {
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: destinationURL)
      completion(.failure(IOSMotionPhotoRenderError.writerSetupFailed))
      return
    }

    let frameCount = Self.frameRate * Self.durationMilliseconds / 1_000
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    let renderQueue = DispatchQueue(
      label: "com.babycompany.yingjian.motion-photo-render",
      qos: .userInitiated
    )
    var frameIndex = 0
    var completed = false

    func fail(_ error: IOSMotionPhotoRenderError) {
      guard !completed else { return }
      completed = true
      input.markAsFinished()
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: destinationURL)
      completion(.failure(error))
    }

    input.requestMediaDataWhenReady(on: renderQueue) {
      while input.isReadyForMoreMediaData && !completed {
        if frameIndex == frameCount {
          completed = true
          input.markAsFinished()
          writer.endSession(
            atSourceTime: CMTime(
              value: Int64(frameCount),
              timescale: Int32(Self.frameRate)
            )
          )
          writer.finishWriting {
            guard writer.status == .completed else {
              try? FileManager.default.removeItem(at: destinationURL)
              completion(.failure(IOSMotionPhotoRenderError.renderFailed))
              return
            }
            let contentSha256: String
            do {
              contentSha256 = try Self.sha256(destinationURL)
            } catch {
              try? FileManager.default.removeItem(at: destinationURL)
              completion(.failure(IOSMotionPhotoRenderError.renderFailed))
              return
            }
            completion(
              .success(
                IOSMotionPhotoRenderedFile(
                  effect: effect,
                  contentSha256: contentSha256,
                  width: width,
                  height: height,
                  durationMilliseconds: Self.durationMilliseconds
                )))
          }
          return
        }
        var pixelBuffer: CVPixelBuffer?
        guard
          CVPixelBufferPoolCreatePixelBuffer(
            nil,
            pixelBufferPool,
            &pixelBuffer
          ) == kCVReturnSuccess,
          let pixelBuffer
        else {
          fail(.pixelBufferCreationFailed)
          return
        }
        let progress =
          frameCount > 1
          ? Double(frameIndex) / Double(frameCount - 1)
          : 0
        let frame = Self.frame(
          baseImage,
          effect: effect,
          progress: progress,
          extent: outputExtent
        )
        context.render(
          frame,
          to: pixelBuffer,
          bounds: outputExtent,
          colorSpace: colorSpace
        )
        let presentationTime = CMTime(
          value: Int64(frameIndex),
          timescale: Int32(Self.frameRate)
        )
        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
          fail(.frameAppendFailed)
          return
        }
        frameIndex += 1
      }
    }
  }

  private static func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
      if data.isEmpty { break }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func outputSize(for sourceSize: CGSize) -> CGSize {
    let scale = min(
      1,
      CGFloat(maximumLongEdge) / max(sourceSize.width, sourceSize.height)
    )
    return CGSize(
      width: evenPixelCount(sourceSize.width * scale),
      height: evenPixelCount(sourceSize.height * scale)
    )
  }

  private static func evenPixelCount(_ value: CGFloat) -> CGFloat {
    CGFloat(max(2, Int((value / 2).rounded()) * 2))
  }

  private static func frame(
    _ baseImage: CIImage,
    effect: IOSMotionPhotoEffect,
    progress: Double,
    extent: CGRect
  ) -> CIImage {
    switch effect {
    case .subtle:
      let phase = progress * .pi * 2
      let scale = 1.04 + sin(phase) * 0.008
      return transformed(
        baseImage,
        scale: scale,
        translation: CGPoint(
          x: sin(phase) * extent.width * 0.008,
          y: cos(phase) * extent.height * 0.006
        ),
        extent: extent
      )
    case .cameraPush:
      let eased = progress * progress * (3 - 2 * progress)
      return transformed(
        baseImage,
        scale: 1 + eased * 0.12,
        translation: .zero,
        extent: extent
      )
    case .lightFlow:
      let image = transformed(
        baseImage,
        scale: 1.02,
        translation: .zero,
        extent: extent
      )
      let radius = max(extent.width, extent.height) * 0.42
      let center = CIVector(
        x: extent.minX - radius + (extent.width + radius * 2) * progress,
        y: extent.midY * 1.1
      )
      guard
        let light = CIFilter(
          name: "CIRadialGradient",
          parameters: [
            "inputCenter": center,
            "inputRadius0": radius * 0.08,
            "inputRadius1": radius,
            "inputColor0": CIColor(red: 1, green: 0.94, blue: 0.78, alpha: 0.22),
            "inputColor1": CIColor(red: 1, green: 0.94, blue: 0.78, alpha: 0),
          ]
        )?.outputImage
      else {
        return image
      }
      return light.cropped(to: extent).composited(over: image).cropped(to: extent)
    }
  }

  private static func transformed(
    _ image: CIImage,
    scale: Double,
    translation: CGPoint,
    extent: CGRect
  ) -> CIImage {
    let scaled = image.transformed(
      by: CGAffineTransform(scaleX: scale, y: scale)
    )
    let centeredTranslation = CGAffineTransform(
      translationX: (extent.width - extent.width * scale) / 2 + translation.x,
      y: (extent.height - extent.height * scale) / 2 + translation.y
    )
    return scaled.transformed(by: centeredTranslation).cropped(to: extent)
  }
}
