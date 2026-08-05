import Flutter
import PhotosUI
import UniformTypeIdentifiers
import UIKit

enum IOSPhotoPickerError: Error {
  case copyFailed
  case invalidSource
}

struct IOSPickedPhotoFileStore {
  static func copy(
    sourceURL: URL,
    suggestedName: String?,
    destinationDirectory: URL
  ) throws -> URL {
    let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
    guard values.isRegularFile == true else {
      throw IOSPhotoPickerError.invalidSource
    }
    try FileManager.default.createDirectory(
      at: destinationDirectory,
      withIntermediateDirectories: true
    )
    let safeName = URL(fileURLWithPath: suggestedName ?? "").lastPathComponent
    let suggestedExtension = URL(fileURLWithPath: safeName).pathExtension
    let fileExtension = suggestedExtension.isEmpty
      ? sourceURL.pathExtension
      : suggestedExtension
    guard !fileExtension.isEmpty else {
      throw IOSPhotoPickerError.invalidSource
    }
    let destination = destinationDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(fileExtension.lowercased())
    do {
      try FileManager.default.copyItem(at: sourceURL, to: destination)
      return destination
    } catch {
      throw IOSPhotoPickerError.copyFailed
    }
  }
}

final class IOSPhotoPicker: NSObject, PHPickerViewControllerDelegate {
  private var completion: FlutterResult?
  private var requestDirectory: URL?

  func pickPhotos(
    limit: Int,
    presenter: UIViewController,
    completion: @escaping FlutterResult
  ) {
    guard self.completion == nil else {
      completion(FlutterError(
        code: "pickerInProgress",
        message: "A photo picker is already open",
        details: nil
      ))
      return
    }
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = limit
    configuration.preferredAssetRepresentationMode = .current
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    self.completion = completion
    requestDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-photo-picker", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    presenter.present(picker, animated: true)
  }

  func discard(paths: [String]) throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("yingjian-photo-picker", isDirectory: true)
      .resolvingSymlinksInPath()
      .standardizedFileURL
    var requestDirectories = Set<URL>()
    for path in paths {
      let url = URL(fileURLWithPath: path)
        .resolvingSymlinksInPath()
        .standardizedFileURL
      let requestDirectory = url.deletingLastPathComponent()
      guard
        requestDirectory.deletingLastPathComponent() == root,
        (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true
      else {
        throw IOSPhotoPickerError.invalidSource
      }
      try FileManager.default.removeItem(at: url)
      requestDirectories.insert(requestDirectory)
    }
    for directory in requestDirectories {
      let remaining = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      )
      if remaining.isEmpty {
        try FileManager.default.removeItem(at: directory)
      }
    }
  }

  func picker(
    _ picker: PHPickerViewController,
    didFinishPicking results: [PHPickerResult]
  ) {
    picker.dismiss(animated: true)
    guard !results.isEmpty else {
      finish([])
      return
    }
    guard let requestDirectory else {
      finishWithError()
      return
    }
    let group = DispatchGroup()
    let lock = NSLock()
    var selected = Array<[String: String]?>(repeating: nil, count: results.count)
    var failed = false
    for (index, result) in results.enumerated() {
      guard let typeIdentifier = result.itemProvider.registeredTypeIdentifiers.first(where: {
        UTType($0)?.conforms(to: .image) == true
      }) else {
        lock.lock()
        failed = true
        lock.unlock()
        continue
      }
      group.enter()
      result.itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) {
        sourceURL,
        error in
        defer { group.leave() }
        guard error == nil, let sourceURL else {
          lock.lock()
          failed = true
          lock.unlock()
          return
        }
        do {
          let copy = try IOSPickedPhotoFileStore.copy(
            sourceURL: sourceURL,
            suggestedName: result.itemProvider.suggestedName,
            destinationDirectory: requestDirectory
          )
          let suggested = result.itemProvider.suggestedName ?? sourceURL.lastPathComponent
          let displayName = URL(fileURLWithPath: suggested).lastPathComponent
          lock.lock()
          selected[index] = [
            "path": copy.path,
            "name": displayName.isEmpty ? copy.lastPathComponent : displayName,
          ]
          lock.unlock()
        } catch {
          lock.lock()
          failed = true
          lock.unlock()
        }
      }
    }
    group.notify(queue: .main) { [weak self] in
      lock.lock()
      let didFail = failed || selected.contains(where: { $0 == nil })
      let completedSelection = selected.compactMap { $0 }
      lock.unlock()
      if didFail {
        self?.finishWithError()
      } else {
        self?.finish(completedSelection)
      }
    }
  }

  private func finish(_ value: [[String: String]]) {
    if value.isEmpty, let requestDirectory {
      try? FileManager.default.removeItem(at: requestDirectory)
    }
    let completion = completion
    self.completion = nil
    requestDirectory = nil
    completion?(value)
  }

  private func finishWithError() {
    if let requestDirectory {
      try? FileManager.default.removeItem(at: requestDirectory)
    }
    let completion = completion
    self.completion = nil
    requestDirectory = nil
    completion?(FlutterError(
      code: "pickerFailed",
      message: "Selected photos could not be copied without transcoding",
      details: nil
    ))
  }
}
