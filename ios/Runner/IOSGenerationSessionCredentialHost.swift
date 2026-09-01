import CryptoKit
import Flutter
import Foundation
import Security

/// Supplies a short-lived first-party generation bearer after the current
/// installation proves possession of its Secure Enclave key. Provider keys
/// never cross this boundary and bearer credentials remain memory-only.
final class IOSGenerationSessionCredentialHost {
  private static let channelName = "yingjian/generation_session"
  private static let activationScheme = "yingjian"
  private static let activationHost = "generation-activate"

  private let channel: FlutterMethodChannel
  private let keyStore = IOSGenerationInstallationKeyStore()
  private let service: IOSGenerationSessionService
  private let coordinator = IOSGenerationCredentialCoordinator()
  private let pendingCodeLock = NSLock()
  private var pendingEnrollmentCode: String?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    service = IOSGenerationSessionService(keyStore: keyStore)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getShortLivedBearerCredential" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let baseURLString = arguments["baseUrl"] as? String
      else {
        result(FlutterError(
          code: "unavailable",
          message: "Generation session configuration is unavailable",
          details: nil
        ))
        return
      }
      self?.handleCredentialRequest(baseURLString: baseURLString, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  /// Accepts a deliberately opened, single-use internal-MVP activation link.
  /// The enrollment code is retained only in process memory until redemption.
  @discardableResult
  func acceptActivationURL(_ url: URL) -> Bool {
    guard let code = Self.activationCode(from: url) else { return false }
    guard (try? keyStore.installationID()) == nil else { return false }

    pendingCodeLock.lock()
    defer { pendingCodeLock.unlock() }
    guard pendingEnrollmentCode == nil else { return false }
    pendingEnrollmentCode = code
    return true
  }

  static func isActivationURL(_ url: URL) -> Bool {
    activationCode(from: url) != nil
  }

  private func handleCredentialRequest(
    baseURLString: String,
    result: @escaping FlutterResult
  ) {
    Task { [weak self] in
      guard let self else {
        await MainActor.run {
          result(FlutterError(code: "unavailable", message: nil, details: nil))
        }
        return
      }
      do {
        let response = try await coordinator.credential(
          baseURLString: baseURLString,
          service: service
        )
        if response.didEnroll || keyStore.hasInstallation() {
          clearEnrollmentCode()
        }
        await MainActor.run {
          result([
            "bearerToken": response.credential.bearerToken,
            "expiresAtEpochMilliseconds": response.credential.expiresAtMilliseconds,
          ])
        }
      } catch let error as IOSGenerationSessionError {
        if error.discardsEnrollmentCode {
          clearEnrollmentCode()
        }
        await MainActor.run {
          result(FlutterError(
            code: error.flutterCode,
            message: "Generation session is unavailable",
            details: nil
          ))
        }
      } catch {
        await MainActor.run {
          result(FlutterError(
            code: "unavailable",
            message: "Generation session is unavailable",
            details: nil
          ))
        }
      }
    }
  }

  private func clearEnrollmentCode() {
    pendingCodeLock.lock()
    defer { pendingCodeLock.unlock() }
    pendingEnrollmentCode = nil
  }

  private static func activationCode(from url: URL) -> String? {
    guard
      url.scheme?.lowercased() == activationScheme,
      url.host?.lowercased() == activationHost,
      (url.path.isEmpty || url.path == "/"),
      url.fragment == nil,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      queryItems.count == 1,
      queryItems[0].name == "code",
      let code = queryItems[0].value,
      code.range(of: #"^[A-Za-z0-9_-]{32,256}$"#, options: .regularExpression) != nil
    else {
      return nil
    }
    return code
  }

  static func installationRegistrationMessageV2(
    challengeID: String,
    challenge: String,
    keyID: String
  ) -> String {
    [
      "yingjian-installation-v2",
      challengeID,
      challenge,
      keyID,
      "",
    ].joined(separator: "\n")
  }
}

private struct IOSGenerationCredential: Sendable {
  let bearerToken: String
  let expiresAtMilliseconds: Int64

  func isUsable(nowMilliseconds: Int64) -> Bool {
    expiresAtMilliseconds - nowMilliseconds >= 30_000
  }
}

private struct IOSGenerationCredentialResponse: Sendable {
  let credential: IOSGenerationCredential
  let didEnroll: Bool
}

private actor IOSGenerationCredentialCoordinator {
  private var cachedCredential: IOSGenerationCredential?
  private var inFlight: Task<IOSGenerationCredentialResponse, Error>?

  func credential(
    baseURLString: String,
    service: IOSGenerationSessionService
  ) async throws -> IOSGenerationCredentialResponse {
    let nowMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
    if let cachedCredential, cachedCredential.isUsable(nowMilliseconds: nowMilliseconds) {
      return IOSGenerationCredentialResponse(
        credential: cachedCredential,
        didEnroll: false
      )
    }
    if let inFlight {
      return try await inFlight.value
    }

    let request = Task {
      try await service.obtainCredential(
        baseURLString: baseURLString
      )
    }
    inFlight = request
    do {
      let response = try await request.value
      cachedCredential = response.credential
      inFlight = nil
      return response
    } catch {
      inFlight = nil
      throw error
    }
  }
}

private final class IOSGenerationSessionService: @unchecked Sendable {
  private static let maximumResponseBytes = 64 * 1_024
  private static let maximumCredentialLifetimeMilliseconds: Int64 = 15 * 60 * 1_000

  private let keyStore: IOSGenerationInstallationKeyStore
  private let session: URLSession

  init(keyStore: IOSGenerationInstallationKeyStore) {
    self.keyStore = keyStore
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    session = URLSession(
      configuration: configuration,
      delegate: IOSGenerationNoRedirectDelegate(),
      delegateQueue: nil
    )
  }

  func obtainCredential(
    baseURLString: String
  ) async throws -> IOSGenerationCredentialResponse {
    let baseURL = try validatedBaseURL(baseURLString)
    let installationID = try keyStore.installationID()
    if let installationID {
      let privateKey = try keyStore.existingPrivateKey()
      return IOSGenerationCredentialResponse(
        credential: try await refreshCredential(
          baseURL: baseURL,
          installationID: installationID,
          privateKey: privateKey
        ),
        didEnroll: false
      )
    }

    let privateKey = try keyStore.existingOrCreatePrivateKey()
    let keyID = Self.keyID(for: privateKey)
    let challenge = try await requestChallenge(
      baseURL: baseURL,
      path: "/v1/installation-challenges",
      body: ["version": 2, "keyId": keyID]
    )
    let message = IOSGenerationSessionCredentialHost.installationRegistrationMessageV2(
      challengeID: challenge.id,
      challenge: challenge.value,
      keyID: keyID
    )
    let signature = try privateKey.signature(for: Data(message.utf8))
    let response = try await postJSON(
      baseURL: baseURL,
      path: "/v1/installations",
      body: [
        "version": 2,
        "challengeId": challenge.id,
        "challenge": challenge.value,
        "keyId": keyID,
        "publicKey": Self.base64URL(privateKey.publicKey.x963Representation),
        "signature": Self.base64URL(signature.rawRepresentation),
      ],
      activationRequest: true
    )
    let credentialEnvelope = try parseCredentialEnvelope(response)
    try keyStore.storeInstallationID(credentialEnvelope.installationID)
    return IOSGenerationCredentialResponse(
      credential: credentialEnvelope.credential,
      didEnroll: true
    )
  }

  private func refreshCredential(
    baseURL: URL,
    installationID: String,
    privateKey: SecureEnclave.P256.Signing.PrivateKey
  ) async throws -> IOSGenerationCredential {
    let keyID = Self.keyID(for: privateKey)
    let challenge = try await requestChallenge(
      baseURL: baseURL,
      path: "/v1/generation-session-challenges",
      body: [
        "version": 1,
        "installationId": installationID,
        "keyId": keyID,
      ]
    )
    let message = [
      "yingjian-generation-session-v1",
      challenge.id,
      challenge.value,
      installationID,
      keyID,
      "",
    ].joined(separator: "\n")
    let signature = try privateKey.signature(for: Data(message.utf8))
    let response = try await postJSON(
      baseURL: baseURL,
      path: "/v1/generation-sessions",
      body: [
        "version": 1,
        "installationId": installationID,
        "keyId": keyID,
        "challengeId": challenge.id,
        "challenge": challenge.value,
        "signature": Self.base64URL(signature.rawRepresentation),
      ],
      activationRequest: false
    )
    let envelope = try parseCredentialEnvelope(response)
    guard envelope.installationID == installationID else {
      throw IOSGenerationSessionError.invalidResponse
    }
    return envelope.credential
  }

  private func requestChallenge(
    baseURL: URL,
    path: String,
    body: [String: Any]
  ) async throws -> (id: String, value: String) {
    let response = try await postJSON(
      baseURL: baseURL,
      path: path,
      body: body,
      activationRequest: false
    )
    guard
      let challengeID = response["challengeId"] as? String,
      challengeID.count >= 8,
      challengeID.count <= 128,
      let challenge = response["challenge"] as? String,
      challenge.range(
        of: #"^[A-Za-z0-9_-]{32,128}$"#,
        options: .regularExpression
      ) != nil,
      let expiresNumber = response["expiresAtEpochMilliseconds"] as? NSNumber
    else {
      throw IOSGenerationSessionError.invalidResponse
    }
    let nowMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
    let remaining = expiresNumber.int64Value - nowMilliseconds
    guard remaining >= 5_000, remaining <= 5 * 60 * 1_000 else {
      throw IOSGenerationSessionError.invalidResponse
    }
    return (challengeID, challenge)
  }

  private func parseCredentialEnvelope(
    _ response: [String: Any]
  ) throws -> (installationID: String, credential: IOSGenerationCredential) {
    guard
      let installationID = response["installationId"] as? String,
      installationID.range(
        of: #"^[A-Za-z0-9:_-]{8,160}$"#,
        options: .regularExpression
      ) != nil,
      let bearerToken = response["bearerToken"] as? String,
      bearerToken.count >= 16,
      bearerToken.count <= 8_192,
      bearerToken.range(
        of: #"^[A-Za-z0-9._~+/-]+=*$"#,
        options: .regularExpression
      ) != nil,
      let expiresNumber = response["expiresAtEpochMilliseconds"] as? NSNumber
    else {
      throw IOSGenerationSessionError.invalidResponse
    }
    let expiresAtMilliseconds = expiresNumber.int64Value
    let nowMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
    let remaining = expiresAtMilliseconds - nowMilliseconds
    guard
      remaining >= 30_000,
      remaining <= Self.maximumCredentialLifetimeMilliseconds
    else {
      throw IOSGenerationSessionError.invalidResponse
    }
    return (
      installationID,
      IOSGenerationCredential(
        bearerToken: bearerToken,
        expiresAtMilliseconds: expiresAtMilliseconds
      )
    )
  }

  private func postJSON(
    baseURL: URL,
    path: String,
    body: [String: Any],
    activationRequest: Bool
  ) async throws -> [String: Any] {
    guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
      throw IOSGenerationSessionError.invalidConfiguration
    }
    var request = URLRequest(
      url: url,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 15
    )
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw IOSGenerationSessionError.network
    }
    guard
      let http = response as? HTTPURLResponse,
      data.count <= Self.maximumResponseBytes
    else {
      throw IOSGenerationSessionError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      if activationRequest && (400..<500).contains(http.statusCode) {
        throw IOSGenerationSessionError.activationRejected
      }
      if http.statusCode == 401 || http.statusCode == 403 {
        throw IOSGenerationSessionError.notActivated
      }
      throw IOSGenerationSessionError.network
    }
    guard
      http.value(forHTTPHeaderField: "Content-Type")?
        .lowercased().hasPrefix("application/json") == true,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw IOSGenerationSessionError.invalidResponse
    }
    return object
  }

  private func validatedBaseURL(_ rawValue: String) throws -> URL {
    guard
      rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
      let components = URLComponents(string: rawValue),
      let scheme = components.scheme?.lowercased(),
      let host = components.host?.lowercased(),
      !host.isEmpty,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      (scheme == "https" || (scheme == "http" && Self.isLoopback(host))),
      let url = components.url
    else {
      throw IOSGenerationSessionError.invalidConfiguration
    }
    return url
  }

  private static func isLoopback(_ host: String) -> Bool {
    host == "localhost" || host == "127.0.0.1" || host == "::1"
  }

  private static func keyID(
    for key: SecureEnclave.P256.Signing.PrivateKey
  ) -> String {
    sha256Hex(key.publicKey.x963Representation)
  }

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

private final class IOSGenerationNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

private final class IOSGenerationInstallationKeyStore: @unchecked Sendable {
  private static let service = "com.babycompany.yingjian.generation-session"
  private static let keyAccount = "secure-enclave-signing-key-v1"
  private static let installationAccount = "installation-id-v1"

  func hasInstallation() -> Bool {
    (try? installationID()) != nil
  }

  func installationID() throws -> String? {
    guard let data = try read(account: Self.installationAccount) else {
      return nil
    }
    guard
      let value = String(data: data, encoding: .utf8),
      value.range(
        of: #"^[A-Za-z0-9:_-]{8,160}$"#,
        options: .regularExpression
      ) != nil
    else {
      throw IOSGenerationSessionError.keyStore
    }
    return value
  }

  func storeInstallationID(_ value: String) throws {
    try write(Data(value.utf8), account: Self.installationAccount)
  }

  func existingPrivateKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
    guard let representation = try read(account: Self.keyAccount) else {
      throw IOSGenerationSessionError.keyStore
    }
    do {
      return try SecureEnclave.P256.Signing.PrivateKey(
        dataRepresentation: representation
      )
    } catch {
      throw IOSGenerationSessionError.keyStore
    }
  }

  func existingOrCreatePrivateKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
    if let representation = try read(account: Self.keyAccount) {
      do {
        return try SecureEnclave.P256.Signing.PrivateKey(
          dataRepresentation: representation
        )
      } catch {
        throw IOSGenerationSessionError.keyStore
      }
    }
    guard SecureEnclave.isAvailable else {
      throw IOSGenerationSessionError.secureEnclaveUnavailable
    }
    do {
      let key = try SecureEnclave.P256.Signing.PrivateKey()
      try write(key.dataRepresentation, account: Self.keyAccount)
      return key
    } catch let error as IOSGenerationSessionError {
      throw error
    } catch {
      throw IOSGenerationSessionError.keyStore
    }
  }

  private func read(account: String) throws -> Data? {
    var result: CFTypeRef?
    let status = SecItemCopyMatching([
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.service,
      kSecAttrAccount: account,
      kSecMatchLimit: kSecMatchLimitOne,
      kSecReturnData: true,
    ] as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw IOSGenerationSessionError.keyStore
    }
    return data
  }

  private func write(_ data: Data, account: String) throws {
    let lookup: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.service,
      kSecAttrAccount: account,
    ]
    let updateStatus = SecItemUpdate(
      lookup as CFDictionary,
      [kSecValueData: data] as CFDictionary
    )
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw IOSGenerationSessionError.keyStore
    }
    var insert = lookup
    insert[kSecValueData] = data
    insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
      throw IOSGenerationSessionError.keyStore
    }
  }
}

private enum IOSGenerationSessionError: Error, Equatable {
  case notActivated
  case activationRejected
  case invalidConfiguration
  case invalidResponse
  case keyStore
  case network
  case secureEnclaveUnavailable

  var flutterCode: String {
    switch self {
    case .notActivated:
      return "not_authenticated"
    case .activationRejected, .invalidConfiguration, .invalidResponse,
         .keyStore, .network, .secureEnclaveUnavailable:
      return "unavailable"
    }
  }

  var discardsEnrollmentCode: Bool {
    self == .activationRejected
  }
}
