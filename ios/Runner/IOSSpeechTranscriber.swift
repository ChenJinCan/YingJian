import AVFoundation
import Flutter
import Speech

enum IOSSpeechRecognitionAvailability: Equatable {
  case available
  case recognizerUnavailable
  case onDeviceRecognitionUnavailable
}

enum IOSSpeechRecognitionPolicy {
  static let requiresOnDeviceRecognition = true

  static func evaluate(
    isRecognizerAvailable: Bool,
    supportsOnDeviceRecognition: Bool
  ) -> IOSSpeechRecognitionAvailability {
    guard isRecognizerAvailable else {
      return .recognizerUnavailable
    }
    guard supportsOnDeviceRecognition else {
      return .onDeviceRecognitionUnavailable
    }
    return .available
  }
}

final class IOSSpeechTranscriber {
  private let audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var pendingResult: FlutterResult?
  private var latestTranscript = ""

  func start(localeIdentifier: String, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(
        code: "speechInProgress",
        message: "Speech transcription is already active",
        details: nil
      ))
      return
    }
    pendingResult = result
    latestTranscript = ""
    requestPermissions { [weak self] granted in
      guard let self else { return }
      guard granted else {
        self.finish(error: FlutterError(
          code: "speechPermissionDenied",
          message: "Speech recognition or microphone permission was denied",
          details: nil
        ))
        return
      }
      self.beginRecognition(localeIdentifier: localeIdentifier)
    }
  }

  func stop(result: @escaping FlutterResult) {
    guard pendingResult != nil else {
      result(nil)
      return
    }
    stopAudioCapture()
    recognitionRequest?.endAudio()
    result(nil)
  }

  func cancel() {
    stopAudioCapture()
    recognitionTask?.cancel()
    finish(error: FlutterError(
      code: "speechCancelled",
      message: "Speech transcription was cancelled",
      details: nil
    ))
  }

  private func requestPermissions(completion: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { speechStatus in
      guard speechStatus == .authorized else {
        DispatchQueue.main.async { completion(false) }
        return
      }
      if #available(iOS 17.0, *) {
        AVAudioApplication.requestRecordPermission { microphoneGranted in
          DispatchQueue.main.async { completion(microphoneGranted) }
        }
      } else {
        AVAudioSession.sharedInstance().requestRecordPermission {
          microphoneGranted in
          DispatchQueue.main.async { completion(microphoneGranted) }
        }
      }
    }
  }

  private func beginRecognition(localeIdentifier: String) {
    let locale = Locale(identifier: localeIdentifier)
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      finish(error: FlutterError(
        code: "speechUnavailable",
        message: "Speech recognition is unavailable for the current locale",
        details: nil
      ))
      return
    }

    switch IOSSpeechRecognitionPolicy.evaluate(
      isRecognizerAvailable: recognizer.isAvailable,
      supportsOnDeviceRecognition: recognizer.supportsOnDeviceRecognition
    ) {
    case .available:
      break
    case .recognizerUnavailable:
      finish(error: FlutterError(
        code: "speechUnavailable",
        message: "Speech recognition is unavailable for the current locale",
        details: nil
      ))
      return
    case .onDeviceRecognitionUnavailable:
      finish(error: FlutterError(
        code: "speechOnDeviceUnavailable",
        message: "On-device speech recognition is unavailable for the current locale",
        details: nil
      ))
      return
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition =
      IOSSpeechRecognitionPolicy.requiresOnDeviceRecognition
    recognitionRequest = request

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      let input = audioEngine.inputNode
      let format = input.outputFormat(forBus: 0)
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 1_024, format: format) {
        [weak request] buffer, _ in
        request?.append(buffer)
      }
      audioEngine.prepare()
      try audioEngine.start()
    } catch {
      finish(error: FlutterError(
        code: "speechAudioFailed",
        message: "Microphone capture could not start",
        details: nil
      ))
      return
    }

    recognitionTask = recognizer.recognitionTask(with: request) {
      [weak self] response, error in
      guard let self else { return }
      if let response {
        self.latestTranscript = response.bestTranscription.formattedString
        if response.isFinal {
          self.finish(transcript: self.latestTranscript)
        }
      } else if error != nil {
        self.finish(error: FlutterError(
          code: "speechRecognitionFailed",
          message: "Speech could not be transcribed",
          details: nil
        ))
      }
    }
  }

  private func stopAudioCapture() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    audioEngine.inputNode.removeTap(onBus: 0)
  }

  private func finish(transcript: String? = nil, error: FlutterError? = nil) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let result = self.pendingResult else { return }
      self.pendingResult = nil
      self.stopAudioCapture()
      self.recognitionRequest = nil
      self.recognitionTask = nil
      try? AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
      if let error {
        result(error)
      } else {
        let value = (transcript ?? self.latestTranscript)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
          result(FlutterError(
            code: "speechEmpty",
            message: "No speech was recognized",
            details: nil
          ))
        } else {
          result(value)
        }
      }
    }
  }
}
