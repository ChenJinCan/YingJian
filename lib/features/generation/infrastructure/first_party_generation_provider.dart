import 'dart:convert';
import 'dart:io';

import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/editor/domain/content_sha256.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';
import 'package:yingjian/features/generation/domain/generation_input.dart';
import 'package:yingjian/features/generation/infrastructure/generation_upload_preparer.dart';

typedef GenerationBearerTokenProvider = Future<String?> Function();
typedef GenerationResultDirectoryProvider = Future<Directory> Function();

final class GenerationBackendAuthenticationRequired implements Exception {
  const GenerationBackendAuthenticationRequired();

  @override
  String toString() => 'A short-lived first-party bearer token is required';
}

final class FirstPartyGenerationProvider
    implements GenerationProvider, GenerationRequestReconciler {
  static const _networkTimeout = Duration(seconds: 30);
  static const _maxResponseBytes = 26 * 1024 * 1024;
  static const _maxUploadBytes = 25 * 1024 * 1024;

  FirstPartyGenerationProvider._({
    required this._baseUri,
    required this._bearerTokenProvider,
    required this._resultDirectoryProvider,
    required this._uploadPreparer,
    required this._pollInterval,
  });

  final Uri _baseUri;
  final GenerationBearerTokenProvider _bearerTokenProvider;
  final GenerationResultDirectoryProvider _resultDirectoryProvider;
  final GenerationUploadPreparer _uploadPreparer;
  final Duration _pollInterval;
  final Map<CreationCapability, GenerationOffer> _offers = {};
  final Map<CreationCapability, _CapabilityContract> _contracts = {};
  final Map<String, _CreateBinding> _createsByRequestId = {};
  Future<void>? _capabilityRefresh;

  static Future<FirstPartyGenerationProvider> connect({
    required Uri baseUri,
    required GenerationBearerTokenProvider bearerTokenProvider,
    required GenerationResultDirectoryProvider resultDirectoryProvider,
    GenerationUploadPreparer? uploadPreparer,
    Duration pollInterval = const Duration(seconds: 1),
  }) async {
    if (pollInterval.isNegative) {
      throw ArgumentError.value(pollInterval, 'pollInterval');
    }
    _validateBaseUri(baseUri);
    final provider = FirstPartyGenerationProvider._(
      baseUri: baseUri,
      bearerTokenProvider: bearerTokenProvider,
      resultDirectoryProvider: resultDirectoryProvider,
      uploadPreparer: uploadPreparer ?? defaultGenerationUploadPreparer(),
      pollInterval: pollInterval,
    );
    await provider._loadCapabilities();
    return provider;
  }

  @override
  Set<CreationCapability> get availableCapabilities => Set.unmodifiable(
    _offers.entries
        .where((entry) => entry.value.expiresAt!.isAfter(DateTime.now()))
        .map((entry) => entry.key),
  );

  @override
  Future<void> refreshCapabilities() {
    final active = _capabilityRefresh;
    if (active != null) return active;
    final refresh = _loadCapabilities();
    _capabilityRefresh = refresh;
    return refresh.whenComplete(() {
      if (identical(_capabilityRefresh, refresh)) {
        _capabilityRefresh = null;
      }
    });
  }

  @override
  Future<GenerationJob> cancel(GenerationJob job) async {
    if (!job.canCancel) throw GenerationCannotCancel(job.id);
    final body = await _postJson(
      '/v1/generation-tasks/${Uri.encodeComponent(job.id)}/cancel',
      const {},
    );
    return _parseTask(
      body['task'],
      expectedTaskId: job.id,
      expectedRequestId: job.clientRequestId,
      expectedProjectId: job.projectId,
      expectedSourcePhotoId: job.sourcePhotoId,
      expectedSourceSha256: job.sourceSha256,
      expectedSourceUploadSha256: job.sourceUploadSha256,
      expectedMaskUploadSha256: job.maskUploadSha256,
      expectedInputIdentity: job.inputIdentity,
      expectedCapability: job.capability,
      expectedProvider: job.provider,
      expectedModel: job.model,
      expectedProviderCancelable: job.canCancel,
    );
  }

  @override
  Future<GenerationJob> reconcile(
    GenerationRequestReservation reservation,
  ) async {
    final capability = reservation.identity.capability;
    final path = Uri(
      path:
          '/v1/generation-tasks/by-creation/'
          '${Uri.encodeComponent(reservation.clientRequestId)}',
      queryParameters: {'capability': _backendId(capability)},
    ).toString();
    final body = await _getJson(path);
    return _parseTask(
      body['task'],
      expectedTaskId: null,
      expectedRequestId: reservation.clientRequestId,
      expectedProjectId: reservation.identity.projectId,
      expectedSourcePhotoId: reservation.identity.sourcePhotoId,
      expectedSourceSha256: reservation.identity.sourceSha256,
      expectedInputIdentity: reservation.identity.inputIdentity,
      expectedCapability: capability,
      expectedProvider: null,
      expectedModel: null,
    );
  }

  @override
  Future<GenerationJob> create({
    required GenerationSourceSnapshot snapshot,
    required String clientRequestId,
    required GenerationConsent? consent,
  }) async {
    final identity = [
      snapshot.projectId,
      snapshot.sourcePhotoId,
      snapshot.sourceSha256,
      snapshot.input?.identity ?? '',
      snapshot.capability.persistedId,
    ].join('\n');
    final existing = _createsByRequestId[clientRequestId];
    if (existing != null) {
      if (existing.identity != identity) {
        throw GenerationRequestConflict(clientRequestId);
      }
      return existing.future;
    }
    final future = _createOnce(
      snapshot: snapshot,
      clientRequestId: clientRequestId,
      consent: consent,
    );
    final binding = _CreateBinding(identity: identity, future: future);
    _createsByRequestId[clientRequestId] = binding;
    try {
      return await future;
    } catch (_) {
      if (identical(_createsByRequestId[clientRequestId], binding)) {
        _createsByRequestId.remove(clientRequestId);
      }
      rethrow;
    }
  }

  Future<GenerationJob> _createOnce({
    required GenerationSourceSnapshot snapshot,
    required String clientRequestId,
    required GenerationConsent? consent,
  }) async {
    final offer = _offers[snapshot.capability];
    final contract = _contracts[snapshot.capability];
    if (offer == null ||
        contract == null ||
        !offer.expiresAt!.isAfter(DateTime.now())) {
      throw GenerationCapabilityUnavailable(snapshot.capability);
    }
    if (consent == null || !consent.isComplete || consent.offerId != offer.id) {
      throw const GenerationConsentRequired();
    }
    File? confirmedMaskFile;
    List<int>? confirmedMaskBytes;
    switch (snapshot.input) {
      case StyleRedrawGenerationInput(
        :final confirmedDefinition,
        :final definitionFingerprint,
      ):
        if (ContentSha256.ofBytes(utf8.encode(confirmedDefinition)) !=
            definitionFingerprint) {
          throw const GenerationProtocolViolation(
            'style definition no longer matches its confirmed identity',
          );
        }
      case MaskRemovalGenerationInput(:final maskPath, :final maskSha256):
        confirmedMaskFile = File(maskPath);
        confirmedMaskBytes = await confirmedMaskFile.readAsBytes();
        if (ContentSha256.ofBytes(confirmedMaskBytes) != maskSha256) {
          throw const GenerationProtocolViolation(
            'mask file no longer matches the confirmed input',
          );
        }
      case OldPhotoGenerationInput() || null:
        break;
    }
    final sourceFile = File(snapshot.sourcePath);
    final sourceBytes = await sourceFile.readAsBytes();
    if (ContentSha256.ofBytes(sourceBytes) != snapshot.sourceSha256) {
      throw const GenerationProtocolViolation(
        'source file no longer matches the confirmed snapshot',
      );
    }
    final prepared = await _uploadPreparer.prepare(
      clientRequestId: clientRequestId,
      capability: snapshot.capability,
      sourcePath: sourceFile.path,
      sourceSha256: snapshot.sourceSha256,
      maskPath: confirmedMaskFile?.path,
      maskSha256: switch (snapshot.input) {
        MaskRemovalGenerationInput(:final maskSha256) => maskSha256,
        _ => null,
      },
    );
    try {
      final preparedSourceFile = File(prepared.sourcePath);
      final preparedSourceBytes = await preparedSourceFile.readAsBytes();
      if (ContentSha256.ofBytes(preparedSourceBytes) != prepared.sourceSha256) {
        throw const GenerationProtocolViolation(
          'prepared source file does not match its upload identity',
        );
      }
      final requiresMask = snapshot.input is MaskRemovalGenerationInput;
      if (requiresMask != (prepared.maskPath != null)) {
        throw const GenerationProtocolViolation(
          'prepared upload does not match the confirmed mask contract',
        );
      }
      final sourceMediaId = await _uploadMedia(
        file: preparedSourceFile,
        bytes: preparedSourceBytes,
        expectedSha256: prepared.sourceSha256,
      );
      final requestBody = <String, Object?>{
        'creationId': clientRequestId,
        'capability': _backendId(snapshot.capability),
        'sourceMediaId': sourceMediaId,
        'sourceOriginalSha256': snapshot.sourceSha256,
        'sourceUploadSha256': prepared.sourceSha256,
        'consent': {
          'offerId': consent.offerId,
          'uploadConfirmed': consent.uploadConfirmed,
          'costConfirmed': consent.costConfirmed,
          'policyVersion': consent.policyVersion,
        },
      };
      String? preparedMaskSha256;
      switch (snapshot.input) {
        case OldPhotoGenerationInput(:final colorMode):
          requestBody['colorMode'] = colorMode.name;
        case StyleRedrawGenerationInput(:final confirmedDefinition):
          requestBody
            ..['styleDefinition'] = confirmedDefinition
            ..['styleDefinitionConfirmed'] = true;
        case MaskRemovalGenerationInput(:final maskSha256):
          final preparedMaskFile = File(prepared.maskPath!);
          final preparedMaskBytes = await preparedMaskFile.readAsBytes();
          preparedMaskSha256 = prepared.maskSha256!;
          if (ContentSha256.ofBytes(preparedMaskBytes) != preparedMaskSha256) {
            throw const GenerationProtocolViolation(
              'prepared mask file does not match its upload identity',
            );
          }
          requestBody
            ..['maskMediaId'] = await _uploadMedia(
              file: preparedMaskFile,
              bytes: preparedMaskBytes,
              expectedSha256: preparedMaskSha256,
            )
            ..['maskOriginalSha256'] = maskSha256
            ..['maskUploadSha256'] = preparedMaskSha256;
        case null:
          break;
      }
      try {
        final body = await _postJson('/v1/generation-tasks', requestBody);
        return await _parseTask(
          body['task'],
          expectedTaskId: null,
          expectedRequestId: clientRequestId,
          expectedProjectId: snapshot.projectId,
          expectedSourcePhotoId: snapshot.sourcePhotoId,
          expectedSourceSha256: snapshot.sourceSha256,
          expectedSourceUploadSha256: prepared.sourceSha256,
          expectedMaskUploadSha256: preparedMaskSha256,
          expectedSourceMediaId: sourceMediaId,
          expectedInputIdentity: snapshot.input?.identity,
          expectedCapability: snapshot.capability,
          expectedOfferId: offer.id,
          expectedProvider: contract.provider,
          expectedModel: contract.model,
          expectedProviderCancelable: contract.providerCancelable,
        );
      } on Object {
        // Once the create request is sent, a local exception or non-2xx reply
        // cannot prove that the first-party gateway did not persist or dispatch
        // it. Recovery must query the stable request identity, never resubmit.
        throw GenerationCreateOutcomeUnknown(clientRequestId);
      }
    } finally {
      try {
        await _uploadPreparer.cleanup(prepared);
      } on Object {
        // The iOS bridge also sweeps abandoned private proxies. A cleanup
        // failure must not turn an already-created paid task into a retry.
      }
    }
  }

  @override
  Stream<GenerationJob> observe(GenerationJob job) async* {
    var current = job;
    while (!_isTerminal(current.state)) {
      final body = await _getJson(
        '/v1/generation-tasks/${Uri.encodeComponent(current.id)}',
      );
      current = await _parseTask(
        body['task'],
        expectedTaskId: current.id,
        expectedRequestId: current.clientRequestId,
        expectedProjectId: current.projectId,
        expectedSourcePhotoId: current.sourcePhotoId,
        expectedSourceSha256: current.sourceSha256,
        expectedSourceUploadSha256: current.sourceUploadSha256,
        expectedMaskUploadSha256: current.maskUploadSha256,
        expectedInputIdentity: current.inputIdentity,
        expectedCapability: current.capability,
        expectedProvider: current.provider,
        expectedModel: current.model,
        expectedProviderCancelable: current.canCancel,
      );
      yield current;
      if (!_isTerminal(current.state) && _pollInterval > Duration.zero) {
        await Future<void>.delayed(_pollInterval);
      }
    }
  }

  @override
  GenerationOffer offerFor(CreationCapability capability) {
    final offer = _offers[capability];
    if (offer == null || !offer.expiresAt!.isAfter(DateTime.now())) {
      throw GenerationCapabilityUnavailable(capability);
    }
    return offer;
  }

  Future<void> _loadCapabilities() async {
    final body = await _getJson('/v1/generation-capabilities');
    final mediaRetentionHours = body['mediaRetentionHours'];
    if (mediaRetentionHours != null &&
        (mediaRetentionHours is! int ||
            mediaRetentionHours < 1 ||
            mediaRetentionHours > 24)) {
      throw const GenerationProtocolViolation(
        'media retention must be between 1 and 24 hours',
      );
    }
    final values = body['capabilities'];
    if (values is! List) {
      throw const GenerationProtocolViolation(
        'capability catalog is missing capabilities',
      );
    }
    final offers = <CreationCapability, GenerationOffer>{};
    final contracts = <CreationCapability, _CapabilityContract>{};
    for (final value in values) {
      final item = _stringMap(value, 'capability catalog item');
      if (item['enabled'] != true) continue;
      final capability = _capabilityFromBackendId(item['capability']);
      final provider = _requiredString(item['provider'], 'capability.provider');
      final model = _requiredString(item['model'], 'capability.model');
      _requiredString(item['recipeVersion'], 'capability.recipeVersion');
      final providerCancelable = item['providerCancelable'];
      if (providerCancelable is! bool) {
        throw const GenerationProtocolViolation(
          'capability.providerCancelable must be a boolean',
        );
      }
      final cancelBoundary = _requiredString(
        item['cancelBoundary'],
        'capability.cancelBoundary',
      );
      final expectedCancelBoundary = providerCancelable
          ? 'provider_pending_only'
          : 'not_provider_cancelable';
      if (cancelBoundary != expectedCancelBoundary) {
        throw const GenerationProtocolViolation(
          'capability cancel boundary does not match provider contract',
        );
      }
      if (offers.containsKey(capability)) {
        throw const GenerationProtocolViolation(
          'capability catalog contains a duplicate capability',
        );
      }
      final offerValue = _stringMap(item['offer'], 'capability offer');
      final id = _requiredString(offerValue['id'], 'offer.id');
      final creditCost = offerValue['creditCost'];
      if (creditCost is! int || creditCost <= 0) {
        throw const GenerationProtocolViolation(
          'cloud offer creditCost must be a positive integer',
        );
      }
      final expiresAt = DateTime.tryParse(
        _requiredString(offerValue['expiresAt'], 'offer.expiresAt'),
      );
      if (expiresAt == null) {
        throw const GenerationProtocolViolation('offer expiry is invalid');
      }
      if (!expiresAt.isAfter(DateTime.now())) {
        throw const GenerationProtocolViolation('offer is already expired');
      }
      offers[capability] = GenerationOffer.cloud(
        id: id,
        capability: capability,
        creditCost: creditCost,
        expiresAt: expiresAt,
      );
      contracts[capability] = _CapabilityContract(
        provider: provider,
        model: model,
        providerCancelable: providerCancelable,
      );
    }
    _offers
      ..clear()
      ..addAll(offers);
    _contracts
      ..clear()
      ..addAll(contracts);
  }

  Future<Map<String, Object?>> _getJson(String path) async {
    final response = await _send(method: 'GET', path: path);
    return _decodeJsonResponse(response);
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _send(
      method: 'POST',
      path: path,
      contentType: ContentType.json.mimeType,
      body: utf8.encode(jsonEncode(body)),
    );
    return _decodeJsonResponse(response);
  }

  Future<String> _uploadMedia({
    required File file,
    required List<int> bytes,
    required String expectedSha256,
  }) async {
    if (bytes.isEmpty || bytes.length > _maxUploadBytes) {
      throw const GenerationProtocolViolation(
        'private media must be between 1 byte and 25 MB',
      );
    }
    final response = await _send(
      method: 'POST',
      path: '/v1/private-media',
      contentType: _imageContentType(file.path),
      contentSha256: expectedSha256,
      body: bytes,
    );
    final decoded = _decodeJsonResponse(response);
    final media = _stringMap(decoded['media'], 'uploaded media');
    final id = _requiredString(media['id'], 'media.id');
    final sha256 = _requiredSha256(media['sha256'], 'media.sha256');
    if (sha256 != expectedSha256) {
      throw const GenerationProtocolViolation(
        'uploaded media identity does not match local content',
      );
    }
    return id;
  }

  Future<_BackendResponse> _send({
    required String method,
    required String path,
    String? contentType,
    String? contentSha256,
    List<int>? body,
  }) async {
    final token = await _requireToken();
    final client = HttpClient();
    client.connectionTimeout = _networkTimeout;
    try {
      final request = await client.openUrl(method, _baseUri.resolve(path));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      if (contentType != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      if (contentSha256 != null) {
        request.headers.set('x-content-sha256', contentSha256);
      }
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(_networkTimeout);
      if (response.contentLength > _maxResponseBytes) {
        throw const GenerationProtocolViolation(
          'backend response exceeds the allowed size',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(_networkTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _maxResponseBytes) {
          throw const GenerationProtocolViolation(
            'backend response exceeds the allowed size',
          );
        }
      }
      return _BackendResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        bytes: bytes,
      );
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> _decodeJsonResponse(_BackendResponse response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bytes));
    } on FormatException {
      throw const GenerationProtocolViolation(
        'backend response is not valid JSON',
      );
    }
    final body = _stringMap(decoded, 'backend response');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'];
      final code = error is Map
          ? error['code']?.toString() ?? 'http_error'
          : 'http_error';
      throw GenerationRemoteFailure(response.statusCode, code);
    }
    return body;
  }

  Future<String> _requireToken() async {
    final token = (await _bearerTokenProvider())?.trim();
    if (token == null ||
        token.isEmpty ||
        token.contains('\r') ||
        token.contains('\n')) {
      throw const GenerationBackendAuthenticationRequired();
    }
    return token;
  }

  static void _validateBaseUri(Uri uri) {
    final isLoopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (!uri.hasAuthority || (uri.scheme != 'https' && !isLoopback)) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'The first-party generation backend must use HTTPS',
      );
    }
  }

  static Map<String, Object?> _stringMap(Object? value, String name) {
    if (value is! Map) {
      throw GenerationProtocolViolation('$name must be an object');
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _requiredString(Object? value, String name) {
    if (value is! String || value.trim().isEmpty || value != value.trim()) {
      throw GenerationProtocolViolation('$name must be a non-empty string');
    }
    return value;
  }

  static String _requiredSha256(Object? value, String name) {
    final sha256 = _requiredString(value, name);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw GenerationProtocolViolation('$name must be a lowercase SHA-256');
    }
    return sha256;
  }

  static String _imageContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    throw const GenerationProtocolViolation('media file type is unsupported');
  }

  Future<GenerationJob> _parseTask(
    Object? value, {
    required String? expectedTaskId,
    required String expectedRequestId,
    required String expectedProjectId,
    required String expectedSourcePhotoId,
    required String expectedSourceSha256,
    String? expectedSourceUploadSha256,
    String? expectedMaskUploadSha256,
    String? expectedSourceMediaId,
    required String? expectedInputIdentity,
    required CreationCapability expectedCapability,
    String? expectedOfferId,
    required String? expectedProvider,
    required String? expectedModel,
    bool? expectedProviderCancelable,
  }) async {
    final task = _stringMap(value, 'generation task');
    final taskId = _requiredString(task['id'], 'task.id');
    final taskOfferId = _requiredString(task['offerId'], 'task.offerId');
    final capability = _capabilityFromBackendId(task['capability']);
    final requestId = _requiredString(task['requestId'], 'task.requestId');
    final sourceMediaId = _requiredString(
      task['sourceMediaId'],
      'task.sourceMediaId',
    );
    final sourceSha256 = _requiredSha256(
      task['sourceSha256'],
      'task.sourceSha256',
    );
    final hasSourceUploadIdentity = task.containsKey('sourceUploadSha256');
    final sourceUploadSha256 = _requiredSha256(
      task['sourceUploadSha256'] ?? task['sourceSha256'],
      'task.sourceUploadSha256',
    );
    final maskUploadSha256 = task['maskUploadSha256'] == null
        ? null
        : _requiredSha256(task['maskUploadSha256'], 'task.maskUploadSha256');
    if (!task.containsKey('inputIdentity')) {
      throw const GenerationProtocolViolation('task.inputIdentity is missing');
    }
    final inputIdentity = task['inputIdentity'];
    if (inputIdentity != null && inputIdentity is! String) {
      throw const GenerationProtocolViolation('task.inputIdentity is invalid');
    }
    if (requestId != expectedRequestId ||
        task['creationId'] != expectedRequestId ||
        (expectedTaskId != null && taskId != expectedTaskId) ||
        capability != expectedCapability ||
        (expectedSourceMediaId != null &&
            sourceMediaId != expectedSourceMediaId) ||
        sourceSha256 != expectedSourceSha256 ||
        (expectedSourceUploadSha256 != null &&
            sourceUploadSha256 != expectedSourceUploadSha256) ||
        (expectedMaskUploadSha256 != null &&
            maskUploadSha256 != expectedMaskUploadSha256) ||
        inputIdentity != expectedInputIdentity ||
        (expectedOfferId != null && taskOfferId != expectedOfferId)) {
      throw const GenerationProtocolViolation(
        'task does not match the confirmed source and capability',
      );
    }
    final state = switch (task['state']) {
      'created' || 'pending' => GenerationJobState.queued,
      'running' => GenerationJobState.running,
      'succeeded' => GenerationJobState.succeeded,
      'failed' || 'rejected' => GenerationJobState.failed,
      'canceled' => GenerationJobState.cancelled,
      _ => throw GenerationProtocolViolation(
        'unsupported task state ${task['state']}',
      ),
    };
    final canCancel = task['providerCancelable'];
    if (canCancel is! bool) {
      throw const GenerationProtocolViolation(
        'task.providerCancelable must be a boolean',
      );
    }
    final cancellationDisposition = switch (_requiredString(
      task['providerCancellation'],
      'task.providerCancellation',
    )) {
      'not_available' => GenerationCancellationDisposition.unavailable,
      'available_while_pending' =>
        GenerationCancellationDisposition.availableWhilePending,
      'local_before_dispatch' =>
        GenerationCancellationDisposition.localBeforeDispatch,
      'provider_confirmed' =>
        GenerationCancellationDisposition.providerConfirmed,
      'local_only' => GenerationCancellationDisposition.localOnly,
      final value => throw GenerationProtocolViolation(
        'unsupported provider cancellation disposition $value',
      ),
    };
    final usageState = switch (_requiredString(
      task['usageState'],
      'task.usageState',
    )) {
      'unreserved' => GenerationUsageState.unreserved,
      'reserved' => GenerationUsageState.reserved,
      'settled' => GenerationUsageState.settled,
      'released' => GenerationUsageState.released,
      final value => throw GenerationProtocolViolation(
        'unsupported task usage state $value',
      ),
    };
    final usageDisposition = switch (_requiredString(
      task['usageDisposition'],
      'task.usageDisposition',
    )) {
      'hold' => GenerationUsageDisposition.hold,
      'settle' => GenerationUsageDisposition.settle,
      'release' => GenerationUsageDisposition.release,
      final value => throw GenerationProtocolViolation(
        'unsupported task usage disposition $value',
      ),
    };
    final errorCode = switch (task['errorCode']) {
      null => null,
      final String value
          when RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(value) =>
        value,
      _ => throw const GenerationProtocolViolation('task.errorCode is invalid'),
    };
    final provider = _requiredString(task['provider'], 'task.provider');
    final model = _requiredString(task['model'], 'task.model');
    if ((expectedProvider != null && provider != expectedProvider) ||
        (expectedModel != null && model != expectedModel) ||
        (canCancel && expectedProviderCancelable == false)) {
      throw const GenerationProtocolViolation(
        'task provider contract does not match the confirmed task contract',
      );
    }
    final createdAt = DateTime.tryParse(
      _requiredString(task['createdAt'], 'task.createdAt'),
    );
    final updatedAt = DateTime.tryParse(
      _requiredString(task['updatedAt'], 'task.updatedAt'),
    );
    if (createdAt == null || updatedAt == null) {
      throw const GenerationProtocolViolation('task timestamps are invalid');
    }
    GeneratedMedia? output;
    if (state == GenerationJobState.succeeded) {
      output = await _downloadResult(
        _requiredString(task['resultMediaId'], 'task.resultMediaId'),
      );
    } else if (task['resultMediaId'] != null) {
      throw const GenerationProtocolViolation(
        'non-succeeded task must not expose result media',
      );
    }
    return GenerationJob(
      id: taskId,
      clientRequestId: requestId,
      projectId: expectedProjectId,
      sourcePhotoId: expectedSourcePhotoId,
      sourceSha256: sourceSha256,
      sourceUploadSha256:
          hasSourceUploadIdentity || expectedSourceUploadSha256 != null
          ? sourceUploadSha256
          : null,
      maskUploadSha256: maskUploadSha256,
      inputIdentity: inputIdentity as String?,
      capability: capability,
      state: state,
      provider: provider,
      model: model,
      canCancel: canCancel,
      createdAt: createdAt,
      updatedAt: updatedAt,
      cancellationDisposition: cancellationDisposition,
      usageState: usageState,
      usageDisposition: usageDisposition,
      errorCode: errorCode,
      output: output,
    );
  }

  Future<GeneratedMedia> _downloadResult(String mediaId) async {
    final response = await _send(
      method: 'GET',
      path: '/v1/private-media/${Uri.encodeComponent(mediaId)}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decodeJsonResponse(response);
      throw StateError('unreachable');
    }
    final declaredSha = _requiredSha256(
      response.headers.value('x-content-sha256'),
      'x-content-sha256',
    );
    final actualSha = ContentSha256.ofBytes(response.bytes);
    if (actualSha != declaredSha) {
      throw const GenerationProtocolViolation(
        'downloaded result failed SHA-256 verification',
      );
    }
    final mimeType = response.headers.contentType?.mimeType;
    final declaredKind = response.headers.value('x-media-kind');
    final GeneratedMediaKind kind;
    final (int, int) dimensions;
    Duration? duration;
    if (declaredKind == null || declaredKind == 'image') {
      kind = GeneratedMediaKind.image;
      dimensions = _imageDimensions(response.bytes, mimeType);
      final declaredWidth = _optionalPositiveHeaderInt(
        response.headers,
        'x-media-width',
      );
      final declaredHeight = _optionalPositiveHeaderInt(
        response.headers,
        'x-media-height',
      );
      if ((declaredWidth != null && declaredWidth != dimensions.$1) ||
          (declaredHeight != null && declaredHeight != dimensions.$2)) {
        throw const GenerationProtocolViolation(
          'result media dimensions do not match the downloaded image',
        );
      }
    } else if (declaredKind == 'imageMotion') {
      if (mimeType != 'video/mp4' ||
          response.headers.value('x-media-codec') != 'h264') {
        throw const GenerationProtocolViolation(
          'unsupported generated motion media contract',
        );
      }
      kind = GeneratedMediaKind.imageMotion;
      dimensions = (
        _requiredPositiveHeaderInt(response.headers, 'x-media-width'),
        _requiredPositiveHeaderInt(response.headers, 'x-media-height'),
      );
      final durationMilliseconds = _requiredPositiveHeaderInt(
        response.headers,
        'x-media-duration-ms',
      );
      if (durationMilliseconds > const Duration(seconds: 30).inMilliseconds) {
        throw const GenerationProtocolViolation(
          'generated motion duration exceeds the supported limit',
        );
      }
      duration = Duration(milliseconds: durationMilliseconds);
    } else {
      throw GenerationProtocolViolation(
        'unsupported generated media kind $declaredKind',
      );
    }
    final directory = Directory(
      '${(await _resultDirectoryProvider()).path}/generation-results',
    );
    await directory.create(recursive: true);
    final extension = switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/bmp' => 'bmp',
      'image/webp' => 'webp',
      'video/mp4' when kind == GeneratedMediaKind.imageMotion => 'mp4',
      _ => throw GenerationProtocolViolation(
        'unsupported result media type $mimeType',
      ),
    };
    final destination = File('${directory.path}/$actualSha.$extension');
    if (await destination.exists()) {
      final existingSha = ContentSha256.ofBytes(
        await destination.readAsBytes(),
      );
      if (existingSha != actualSha) {
        throw const GenerationProtocolViolation(
          'existing generated result failed integrity verification',
        );
      }
    } else {
      final temporary = File(
        '${directory.path}/.$actualSha.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      try {
        await temporary.writeAsBytes(response.bytes, flush: true);
        await temporary.rename(destination.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
    return GeneratedMedia(
      id: mediaId,
      kind: kind,
      localPath: destination.path,
      contentSha256: actualSha,
      width: dimensions.$1,
      height: dimensions.$2,
      duration: duration,
    );
  }

  static int? _optionalPositiveHeaderInt(HttpHeaders headers, String name) {
    final rawValue = headers.value(name);
    if (rawValue == null) return null;
    final value = int.tryParse(rawValue);
    if (value == null || value <= 0) {
      throw GenerationProtocolViolation('invalid $name response header');
    }
    return value;
  }

  static int _requiredPositiveHeaderInt(HttpHeaders headers, String name) =>
      _optionalPositiveHeaderInt(headers, name) ??
      (throw GenerationProtocolViolation('missing $name response header'));

  static (int, int) _imageDimensions(List<int> bytes, String? mimeType) {
    int uint16Be(int offset) => (bytes[offset] << 8) | bytes[offset + 1];
    int uint32Be(int offset) =>
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    int uint32Le(int offset) =>
        bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);

    if (mimeType == 'image/png' &&
        bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      final width = uint32Be(16);
      final height = uint32Be(20);
      if (width > 0 && height > 0) return (width, height);
    }
    if (mimeType == 'image/jpeg' &&
        bytes.length >= 4 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8) {
      var offset = 2;
      while (offset + 8 < bytes.length) {
        if (bytes[offset] != 0xff) {
          offset += 1;
          continue;
        }
        final marker = bytes[offset + 1];
        if (marker == 0xd8 || marker == 0xd9) {
          offset += 2;
          continue;
        }
        final length = uint16Be(offset + 2);
        if (length < 2 || offset + 2 + length > bytes.length) break;
        const startOfFrameMarkers = {
          0xc0,
          0xc1,
          0xc2,
          0xc3,
          0xc5,
          0xc6,
          0xc7,
          0xc9,
          0xca,
          0xcb,
          0xcd,
          0xce,
          0xcf,
        };
        if (startOfFrameMarkers.contains(marker) && length >= 7) {
          final height = uint16Be(offset + 5);
          final width = uint16Be(offset + 7);
          if (width > 0 && height > 0) return (width, height);
        }
        offset += 2 + length;
      }
    }
    if (mimeType == 'image/bmp' &&
        bytes.length >= 26 &&
        bytes[0] == 0x42 &&
        bytes[1] == 0x4d) {
      final width = uint32Le(18);
      final rawHeight = uint32Le(22);
      final height = rawHeight & 0x80000000 == 0
          ? rawHeight
          : ((~rawHeight + 1) & 0xffffffff);
      if (width > 0 && height > 0) return (width, height);
    }
    if (mimeType == 'image/webp' &&
        bytes.length >= 30 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP' &&
        ascii.decode(bytes.sublist(12, 16), allowInvalid: true) == 'VP8X') {
      final width = 1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16);
      final height = 1 + bytes[27] + (bytes[28] << 8) + (bytes[29] << 16);
      if (width > 0 && height > 0) return (width, height);
    }
    throw const GenerationProtocolViolation(
      'result media dimensions could not be verified',
    );
  }

  static String _backendId(CreationCapability capability) =>
      switch (capability) {
        CreationCapability.optimizeAiRepair => 'optimizeAiRepair',
        CreationCapability.optimizeOldPhoto => 'optimizeOldPhoto',
        CreationCapability.styleAiRedraw => 'styleAiRedraw',
        CreationCapability.cleanupRemovePasserby => 'cleanupRemovePasserby',
        CreationCapability.cleanupBrushRemove => 'cleanupBrushRemove',
        CreationCapability.motionAiNatural => 'motionAiNatural',
        _ => throw GenerationCapabilityUnavailable(capability),
      };

  static bool _isTerminal(GenerationJobState state) =>
      state == GenerationJobState.succeeded ||
      state == GenerationJobState.failed ||
      state == GenerationJobState.cancelled;

  static CreationCapability _capabilityFromBackendId(Object? value) =>
      switch (value) {
        'optimizeAiRepair' => CreationCapability.optimizeAiRepair,
        'optimizeOldPhoto' => CreationCapability.optimizeOldPhoto,
        'styleAiRedraw' => CreationCapability.styleAiRedraw,
        'cleanupRemovePasserby' => CreationCapability.cleanupRemovePasserby,
        'cleanupBrushRemove' => CreationCapability.cleanupBrushRemove,
        'motionAiNatural' => CreationCapability.motionAiNatural,
        _ => throw GenerationProtocolViolation(
          'unsupported backend capability $value',
        ),
      };
}

final class _BackendResponse {
  const _BackendResponse({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  final int statusCode;
  final HttpHeaders headers;
  final List<int> bytes;
}

final class _CreateBinding {
  const _CreateBinding({required this.identity, required this.future});

  final String identity;
  final Future<GenerationJob> future;
}

final class _CapabilityContract {
  const _CapabilityContract({
    required this.provider,
    required this.model,
    required this.providerCancelable,
  });

  final String provider;
  final String model;
  final bool providerCancelable;
}
