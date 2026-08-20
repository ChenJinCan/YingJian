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

final class IOSPhotoPickerLoadDeadline {
  init(
    timeout: TimeInterval,
    queue: DispatchQueue,
    onTimeout: @escaping () -> Void
  ) {
    self.timeout = timeout
    self.queue = queue
    self.onTimeout = onTimeout
  }

  private let timeout: TimeInterval
  private let queue: DispatchQueue
  private let onTimeout: () -> Void
  private let lock = NSLock()
  private var didFinish = false
  private var workItem: DispatchWorkItem?
  private var progresses: [Progress] = []

  func track(_ progress: Progress) {
    lock.lock()
    if didFinish {
      lock.unlock()
      progress.cancel()
      return
    }
    progresses.append(progress)
    lock.unlock()
  }

  func start() {
    let workItem = DispatchWorkItem { [weak self] in
      self?.fire()
    }
    lock.lock()
    guard !didFinish else {
      lock.unlock()
      return
    }
    self.workItem = workItem
    lock.unlock()
    queue.asyncAfter(deadline: .now() + timeout, execute: workItem)
  }

  @discardableResult
  func complete() -> Bool {
    lock.lock()
    guard !didFinish else {
      lock.unlock()
      return false
    }
    didFinish = true
    let workItem = workItem
    self.workItem = nil
    progresses.removeAll()
    lock.unlock()
    workItem?.cancel()
    return true
  }

  private func fire() {
    lock.lock()
    guard !didFinish else {
      lock.unlock()
      return
    }
    didFinish = true
    let progresses = progresses
    self.progresses.removeAll()
    workItem = nil
    lock.unlock()
    progresses.forEach { $0.cancel() }
    onTimeout()
  }
}

final class IOSPhotoPicker: NSObject, PHPickerViewControllerDelegate {
  private static let loadTimeout: TimeInterval = 90

  private var completion: FlutterResult?
  private var requestDirectory: URL?
  private var requestID: UUID?
  private var loadDeadline: IOSPhotoPickerLoadDeadline?

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
    requestID = UUID()
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
    guard let requestID else {
      finishWithErrorWithoutActiveRequest()
      return
    }
    guard !results.isEmpty else {
      finish([], requestID: requestID)
      return
    }
    guard let requestDirectory else {
      finishWithError(requestID: requestID)
      return
    }
    let deadline = IOSPhotoPickerLoadDeadline(
      timeout: Self.loadTimeout,
      queue: .main
    ) { [weak self] in
      self?.finishTimedOut(requestID: requestID)
    }
    loadDeadline = deadline
    deadline.start()
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
      let progress = result.itemProvider.loadFileRepresentation(
        forTypeIdentifier: typeIdentifier
      ) {
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
      deadline.track(progress)
    }
    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      guard self.requestID == requestID, deadline.complete() else {
        try? FileManager.default.removeItem(at: requestDirectory)
        return
      }
      self.loadDeadline = nil
      lock.lock()
      let didFail = failed || selected.contains(where: { $0 == nil })
      let completedSelection = selected.compactMap { $0 }
      lock.unlock()
      if didFail {
        self.finishWithError(requestID: requestID)
      } else {
        self.finish(completedSelection, requestID: requestID)
      }
    }
  }

  private func finish(_ value: [[String: String]], requestID: UUID) {
    guard self.requestID == requestID else { return }
    if value.isEmpty, let requestDirectory {
      try? FileManager.default.removeItem(at: requestDirectory)
    }
    resolve(value)
  }

  private func finishWithError(requestID: UUID) {
    guard self.requestID == requestID else { return }
    if let requestDirectory {
      try? FileManager.default.removeItem(at: requestDirectory)
    }
    resolve(FlutterError(
      code: "pickerFailed",
      message: "Selected photos could not be copied without transcoding",
      details: nil
    ))
  }

  private func finishTimedOut(requestID: UUID) {
    guard self.requestID == requestID else { return }
    if let requestDirectory {
      try? FileManager.default.removeItem(at: requestDirectory)
    }
    resolve(FlutterError(
      code: "pickerTimedOut",
      message: "Selected photos took too long to become available",
      details: nil
    ))
  }

  private func finishWithErrorWithoutActiveRequest() {
    if let requestDirectory {
      try? FileManager.default.removeItem(at: requestDirectory)
    }
    resolve(FlutterError(
      code: "pickerFailed",
      message: "The photo picker request is unavailable",
      details: nil
    ))
  }

  private func resolve(_ value: Any) {
    loadDeadline?.complete()
    loadDeadline = nil
    let completion = completion
    self.completion = nil
    requestID = nil
    requestDirectory = nil
    completion?(value)
  }
}
