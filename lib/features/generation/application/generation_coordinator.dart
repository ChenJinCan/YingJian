import 'package:flutter/foundation.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/generation/domain/generation_input.dart';

enum GenerationJobState { queued, running, succeeded, failed, cancelled }

enum GenerationExecutionLocation { local, cloud }

enum GeneratedMediaKind { image, imageMotion }

enum GenerationCancellationDisposition {
  unavailable,
  availableWhilePending,
  localBeforeDispatch,
  providerConfirmed,
  localOnly,
}

enum GenerationUsageState { unreserved, reserved, settled, released }

enum GenerationUsageDisposition { hold, settle, release }

extension on GenerationJobState {
  bool get isTerminal =>
      this == GenerationJobState.succeeded ||
      this == GenerationJobState.failed ||
      this == GenerationJobState.cancelled;
}

@immutable
class GeneratedMedia {
  GeneratedMedia({
    required this.id,
    required this.kind,
    required this.localPath,
    required this.contentSha256,
    required this.width,
    required this.height,
    this.duration,
    this.savedAssetId,
  }) {
    if (id.trim().isEmpty || localPath.trim().isEmpty) {
      throw ArgumentError(
        'Generated media identity and path must not be empty',
      );
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(contentSha256)) {
      throw ArgumentError.value(
        contentSha256,
        'contentSha256',
        'Generated media requires a lowercase SHA-256 identity',
      );
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Generated media dimensions must be positive');
    }
    if (kind == GeneratedMediaKind.imageMotion &&
        (duration == null || duration! <= Duration.zero)) {
      throw ArgumentError('Motion media must have a positive duration');
    }
    if (kind == GeneratedMediaKind.image && duration != null) {
      throw ArgumentError('Static image media cannot have a duration');
    }
    if (savedAssetId != null && savedAssetId!.trim().isEmpty) {
      throw ArgumentError.value(
        savedAssetId,
        'savedAssetId',
        'Saved photo-library identity must not be empty',
      );
    }
  }

  final String id;
  final GeneratedMediaKind kind;
  final String localPath;
  final String contentSha256;
  final int width;
  final int height;
  final Duration? duration;
  final String? savedAssetId;

  GeneratedMedia markSaved(String assetId) => GeneratedMedia(
    id: id,
    kind: kind,
    localPath: localPath,
    contentSha256: contentSha256,
    width: width,
    height: height,
    duration: duration,
    savedAssetId: assetId,
  );

  @override
  bool operator ==(Object other) =>
      other is GeneratedMedia &&
      other.id == id &&
      other.kind == kind &&
      other.localPath == localPath &&
      other.contentSha256 == contentSha256 &&
      other.width == width &&
      other.height == height &&
      other.duration == duration &&
      other.savedAssetId == savedAssetId;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    localPath,
    contentSha256,
    width,
    height,
    duration,
    savedAssetId,
  );
}

@immutable
class GenerationSourceSnapshot {
  GenerationSourceSnapshot({
    required this.projectId,
    required this.sourcePhotoId,
    required this.sourcePath,
    required this.sourceSha256,
    required this.capability,
    required this.createdAt,
    this.input,
  }) {
    if (projectId.trim().isEmpty || sourcePhotoId.trim().isEmpty) {
      throw ArgumentError('Generation source identity must not be empty');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceSha256)) {
      throw ArgumentError.value(
        sourceSha256,
        'sourceSha256',
        'Generation sources require a lowercase SHA-256 identity',
      );
    }
    final validInput = switch (capability) {
      CreationCapability.optimizeOldPhoto => input is OldPhotoGenerationInput,
      CreationCapability.styleAiRedraw => input is StyleRedrawGenerationInput,
      CreationCapability.cleanupRemovePasserby ||
      CreationCapability.cleanupBrushRemove =>
        input is MaskRemovalGenerationInput,
      _ => input == null,
    };
    if (!validInput) {
      throw ArgumentError.value(
        input,
        'input',
        'The selected capability requires its own explicit bounded input',
      );
    }
  }

  final String projectId;
  final String sourcePhotoId;
  final String sourcePath;
  final String sourceSha256;
  final CreationCapability capability;
  final DateTime createdAt;
  final GenerationInput? input;
}

@immutable
class GenerationConsent {
  const GenerationConsent({
    required this.offerId,
    required this.uploadConfirmed,
    required this.costConfirmed,
    required this.policyVersion,
    required this.confirmedAt,
  });

  final String offerId;
  final bool uploadConfirmed;
  final bool costConfirmed;
  final int policyVersion;
  final DateTime confirmedAt;

  bool get isComplete =>
      offerId.trim().isNotEmpty &&
      uploadConfirmed &&
      costConfirmed &&
      policyVersion > 0;
}

@immutable
class GenerationOffer {
  const GenerationOffer._({
    required this.id,
    required this.capability,
    required this.location,
    required this.creditCost,
    this.expiresAt,
  });

  factory GenerationOffer.local({
    required String id,
    required CreationCapability capability,
  }) => GenerationOffer._(
    id: id,
    capability: capability,
    location: GenerationExecutionLocation.local,
    creditCost: 0,
  );

  factory GenerationOffer.cloud({
    required String id,
    required CreationCapability capability,
    required int creditCost,
    required DateTime expiresAt,
  }) {
    if (creditCost <= 0) {
      throw ArgumentError.value(
        creditCost,
        'creditCost',
        'Cloud generation must have a positive bounded credit cost',
      );
    }
    return GenerationOffer._(
      id: id,
      capability: capability,
      location: GenerationExecutionLocation.cloud,
      creditCost: creditCost,
      expiresAt: expiresAt,
    );
  }

  final String id;
  final CreationCapability capability;
  final GenerationExecutionLocation location;
  final int creditCost;
  final DateTime? expiresAt;

  bool get requiresConsent => location == GenerationExecutionLocation.cloud;
}

@immutable
class GenerationJob {
  const GenerationJob({
    required this.id,
    required this.clientRequestId,
    required this.projectId,
    required this.sourcePhotoId,
    required this.sourceSha256,
    this.sourceUploadSha256,
    this.maskUploadSha256,
    this.inputIdentity,
    required this.capability,
    required this.state,
    required this.provider,
    required this.model,
    required this.canCancel,
    required this.createdAt,
    required this.updatedAt,
    this.cancellationDisposition,
    this.usageState,
    this.usageDisposition,
    this.errorCode,
    this.output,
  });

  final String id;
  final String clientRequestId;
  final String projectId;
  final String sourcePhotoId;

  /// Immutable content identity of the original app-owned [ProjectPhoto].
  final String sourceSha256;

  /// Actual canonical proxy bytes uploaded to the first-party gateway.
  final String? sourceUploadSha256;

  /// Actual transformed black/white mask proxy uploaded alongside a canonical
  /// source. The user-confirmed mask identity remains in [inputIdentity].
  final String? maskUploadSha256;
  final String? inputIdentity;
  final CreationCapability capability;
  final GenerationJobState state;
  final String provider;
  final String model;
  final bool canCancel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final GenerationCancellationDisposition? cancellationDisposition;
  final GenerationUsageState? usageState;
  final GenerationUsageDisposition? usageDisposition;
  final String? errorCode;
  final GeneratedMedia? output;

  bool get requiresReconciliation =>
      errorCode == 'dispatch_reconciliation_required' &&
      usageState == GenerationUsageState.reserved &&
      usageDisposition == GenerationUsageDisposition.hold;

  GenerationJob copyWith({
    GenerationJobState? state,
    bool? canCancel,
    DateTime? updatedAt,
    GenerationCancellationDisposition? cancellationDisposition,
    GenerationUsageState? usageState,
    GenerationUsageDisposition? usageDisposition,
    String? errorCode,
    GeneratedMedia? output,
  }) => GenerationJob(
    id: id,
    clientRequestId: clientRequestId,
    projectId: projectId,
    sourcePhotoId: sourcePhotoId,
    sourceSha256: sourceSha256,
    sourceUploadSha256: sourceUploadSha256,
    maskUploadSha256: maskUploadSha256,
    inputIdentity: inputIdentity,
    capability: capability,
    state: state ?? this.state,
    provider: provider,
    model: model,
    canCancel: canCancel ?? this.canCancel,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cancellationDisposition:
        cancellationDisposition ?? this.cancellationDisposition,
    usageState: usageState ?? this.usageState,
    usageDisposition: usageDisposition ?? this.usageDisposition,
    errorCode: errorCode ?? this.errorCode,
    output: output ?? this.output,
  );
}

@immutable
class GenerationRequestIdentity {
  GenerationRequestIdentity({
    required this.projectId,
    required this.sourcePhotoId,
    required this.sourceSha256,
    required this.capability,
    this.inputIdentity,
  }) {
    if (projectId.trim().isEmpty || sourcePhotoId.trim().isEmpty) {
      throw ArgumentError('Generation request identity must not be empty');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceSha256)) {
      throw ArgumentError.value(
        sourceSha256,
        'sourceSha256',
        'Generation request identity requires a lowercase SHA-256',
      );
    }
    if (inputIdentity != null && inputIdentity!.trim().isEmpty) {
      throw ArgumentError.value(
        inputIdentity,
        'inputIdentity',
        'Generation input identity must not be empty',
      );
    }
  }

  factory GenerationRequestIdentity.fromSnapshot(
    GenerationSourceSnapshot snapshot, {
    String? inputIdentity,
  }) => GenerationRequestIdentity(
    projectId: snapshot.projectId,
    sourcePhotoId: snapshot.sourcePhotoId,
    sourceSha256: snapshot.sourceSha256,
    capability: snapshot.capability,
    inputIdentity: inputIdentity ?? snapshot.input?.identity,
  );

  final String projectId;
  final String sourcePhotoId;
  final String sourceSha256;
  final CreationCapability capability;
  final String? inputIdentity;

  bool matches(GenerationJob job, {bool includeAnyInput = false}) =>
      job.projectId == projectId &&
      job.sourcePhotoId == sourcePhotoId &&
      job.sourceSha256 == sourceSha256 &&
      job.capability == capability &&
      (includeAnyInput || job.inputIdentity == inputIdentity);

  @override
  bool operator ==(Object other) =>
      other is GenerationRequestIdentity &&
      other.projectId == projectId &&
      other.sourcePhotoId == sourcePhotoId &&
      other.sourceSha256 == sourceSha256 &&
      other.capability == capability &&
      other.inputIdentity == inputIdentity;

  @override
  int get hashCode => Object.hash(
    projectId,
    sourcePhotoId,
    sourceSha256,
    capability,
    inputIdentity,
  );
}

enum GenerationRequestReservationState { prepared, reconciliationRequired }

@immutable
class GenerationRequestReservation {
  GenerationRequestReservation({
    required this.clientRequestId,
    required this.identity,
    required this.createdAt,
    this.state = GenerationRequestReservationState.prepared,
  }) {
    if (clientRequestId.trim().isEmpty) {
      throw ArgumentError.value(
        clientRequestId,
        'clientRequestId',
        'Reserved client request identity must not be empty',
      );
    }
  }

  final String clientRequestId;
  final GenerationRequestIdentity identity;
  final DateTime createdAt;
  final GenerationRequestReservationState state;

  GenerationRequestReservation copyWith({
    GenerationRequestReservationState? state,
  }) => GenerationRequestReservation(
    clientRequestId: clientRequestId,
    identity: identity,
    createdAt: createdAt,
    state: state ?? this.state,
  );
}

abstract interface class GenerationProvider {
  Set<CreationCapability> get availableCapabilities;

  Future<void> refreshCapabilities();

  GenerationOffer offerFor(CreationCapability capability);

  Future<GenerationJob> create({
    required GenerationSourceSnapshot snapshot,
    required String clientRequestId,
    required GenerationConsent? consent,
  });

  Future<GenerationJob> cancel(GenerationJob job);

  Stream<GenerationJob> observe(GenerationJob job);
}

/// Optional provider interface for querying a create attempt by its stable,
/// app-owned request identity without submitting the paid request again.
abstract interface class GenerationRequestReconciler {
  Future<GenerationJob> reconcile(GenerationRequestReservation reservation);
}

abstract interface class GenerationJobStore {
  Future<GenerationJob?> findByClientRequestId(String clientRequestId);

  Future<GenerationJob?> findById(String id);

  Future<List<GenerationJob>> findByProjectId(String projectId);

  Future<GenerationJob?> findLatest(
    GenerationRequestIdentity identity, {
    Set<GenerationJobState>? states,
    bool includeAnyInput = false,
  });

  Future<GenerationRequestReservation?> findReservation(
    GenerationRequestIdentity identity,
  );

  Future<GenerationRequestReservation?> findReconciliationRequired();

  Future<void> saveReservation(GenerationRequestReservation reservation);

  Future<void> deleteReservation(String clientRequestId);

  Future<void> deleteProjectState(String projectId);

  Future<void> save(GenerationJob job);
}

/// Durable authorization to finish generation cleanup after a user-confirmed
/// project deletion. Implementations must not treat a pending entry alone as
/// proof that the project was deleted; callers also provide the current project
/// catalog before a retry is allowed to remove anything.
abstract interface class GenerationProjectDeletionCleanupStore {
  Future<void> stageProjectDeletionCleanup(String projectId);

  Future<Set<String>> findPendingProjectDeletionCleanups();

  Future<void> completeProjectDeletionCleanup(String projectId);
}

final class GenerationConsentRequired implements Exception {
  const GenerationConsentRequired();

  @override
  String toString() => 'Upload and cost consent are required for generation';
}

final class GenerationCapabilityUnavailable implements Exception {
  const GenerationCapabilityUnavailable(this.capability);

  final CreationCapability capability;

  @override
  String toString() =>
      'Generation capability ${capability.persistedId} is unavailable';
}

final class GenerationRequestConflict implements Exception {
  const GenerationRequestConflict(this.clientRequestId);

  final String clientRequestId;

  @override
  String toString() =>
      'Generation request $clientRequestId is already bound to another source';
}

final class GenerationCannotCancel implements Exception {
  const GenerationCannotCancel(this.jobId);

  final String jobId;

  @override
  String toString() => 'Generation job $jobId cannot be cancelled';
}

final class GenerationProjectDeletionBlocked implements Exception {
  const GenerationProjectDeletionBlocked(this.projectId, this.jobId);

  final String projectId;
  final String jobId;

  @override
  String toString() =>
      'Generation job $jobId must reach a confirmed terminal state before '
      'project $projectId can be deleted';
}

final class GenerationProtocolViolation implements Exception {
  const GenerationProtocolViolation(this.message);

  final String message;

  @override
  String toString() => 'Invalid generation provider response: $message';
}

/// The first-party gateway may have durably created or dispatched the request,
/// but the client did not receive a trustworthy final create response.
///
/// Callers must reconcile [clientRequestId] instead of creating another paid
/// request. The value is an app-owned idempotency identity, not a provider ID.
final class GenerationCreateOutcomeUnknown implements Exception {
  const GenerationCreateOutcomeUnknown(this.clientRequestId);

  final String clientRequestId;

  @override
  String toString() =>
      'Generation request $clientRequestId requires first-party reconciliation';
}

final class GenerationReconciliationRequired implements Exception {
  const GenerationReconciliationRequired(this.reservation);

  final GenerationRequestReservation reservation;

  @override
  String toString() =>
      'Generation request ${reservation.clientRequestId} must be reconciled';
}

final class GenerationReconciliationUnavailable implements Exception {
  const GenerationReconciliationUnavailable();
}

final class GenerationReconciliationNotFound implements Exception {
  const GenerationReconciliationNotFound(this.clientRequestId);

  final String clientRequestId;
}

/// A privacy-safe first-party gateway failure. [code] is constrained by the
/// gateway contract and must never contain raw provider text or identifiers.
final class GenerationRemoteFailure implements Exception {
  const GenerationRemoteFailure(this.statusCode, this.code);

  final int statusCode;
  final String code;

  @override
  String toString() => 'Generation gateway failed ($statusCode: $code)';
}

final class GenerationCoordinator {
  GenerationCoordinator({
    required GenerationProvider provider,
    required GenerationJobStore store,
  }) : this._(provider, store);

  GenerationCoordinator._(this._provider, this._store);

  final GenerationProvider _provider;
  final GenerationJobStore _store;
  Future<void> _createTail = Future.value();

  Set<CreationCapability> get availableCapabilities =>
      _provider.availableCapabilities;

  Future<void> refreshCapabilities() => _provider.refreshCapabilities();

  GenerationOffer offerFor(CreationCapability capability) {
    if (!_provider.availableCapabilities.contains(capability)) {
      throw GenerationCapabilityUnavailable(capability);
    }
    final offer = _provider.offerFor(capability);
    if (offer.capability != capability) {
      throw const GenerationProtocolViolation(
        'offer does not match the selected capability',
      );
    }
    return offer;
  }

  Future<GenerationJob> create({
    required GenerationSourceSnapshot snapshot,
    required String clientRequestId,
    required GenerationConsent? consent,
  }) async {
    if (!_provider.availableCapabilities.contains(snapshot.capability)) {
      throw GenerationCapabilityUnavailable(snapshot.capability);
    }
    final offer = offerFor(snapshot.capability);
    if (offer.requiresConsent &&
        (consent == null ||
            !consent.isComplete ||
            consent.offerId != offer.id)) {
      throw const GenerationConsentRequired();
    }
    final existing = await _store.findByClientRequestId(clientRequestId);
    if (existing != null) {
      if (existing.projectId != snapshot.projectId ||
          existing.sourcePhotoId != snapshot.sourcePhotoId ||
          existing.sourceSha256 != snapshot.sourceSha256 ||
          existing.inputIdentity != snapshot.input?.identity ||
          existing.capability != snapshot.capability) {
        throw GenerationRequestConflict(clientRequestId);
      }
      return existing;
    }
    final created = await _provider.create(
      snapshot: snapshot,
      clientRequestId: clientRequestId,
      consent: consent,
    );
    if (created.clientRequestId != clientRequestId ||
        created.projectId != snapshot.projectId ||
        created.sourcePhotoId != snapshot.sourcePhotoId ||
        created.sourceSha256 != snapshot.sourceSha256 ||
        created.inputIdentity != snapshot.input?.identity ||
        created.capability != snapshot.capability) {
      throw const GenerationProtocolViolation(
        'created job does not match the confirmed source',
      );
    }
    await _store.save(created);
    return created;
  }

  Future<GenerationJob> createPersisted({
    required GenerationSourceSnapshot snapshot,
    required GenerationConsent? consent,
    required String Function() clientRequestIdFactory,
  }) => _serializeCreate(
    () => _createPersisted(
      snapshot: snapshot,
      consent: consent,
      clientRequestIdFactory: clientRequestIdFactory,
    ),
  );

  Future<GenerationJob> _createPersisted({
    required GenerationSourceSnapshot snapshot,
    required GenerationConsent? consent,
    required String Function() clientRequestIdFactory,
  }) async {
    final unresolved = await _store.findReconciliationRequired();
    if (unresolved != null) {
      throw GenerationReconciliationRequired(unresolved);
    }
    final identity = GenerationRequestIdentity.fromSnapshot(snapshot);
    var reservation = await _store.findReservation(identity);
    if (reservation == null) {
      reservation = GenerationRequestReservation(
        clientRequestId: clientRequestIdFactory(),
        identity: identity,
        createdAt: DateTime.now().toUtc(),
      );
      await _store.saveReservation(reservation);
    }
    late final GenerationJob job;
    try {
      job = await create(
        snapshot: snapshot,
        clientRequestId: reservation.clientRequestId,
        consent: consent,
      );
    } on GenerationCreateOutcomeUnknown catch (error) {
      if (error.clientRequestId != reservation.clientRequestId) {
        throw const GenerationProtocolViolation(
          'unknown create outcome does not match the reserved request',
        );
      }
      final pending = reservation.copyWith(
        state: GenerationRequestReservationState.reconciliationRequired,
      );
      await _store.saveReservation(pending);
      throw GenerationReconciliationRequired(pending);
    }
    await _store.deleteReservation(reservation.clientRequestId);
    return job;
  }

  Future<GenerationRequestReservation?> findReconciliationRequired() =>
      _store.findReconciliationRequired();

  Future<GenerationJob> reconcile(
    GenerationRequestReservation reservation,
  ) async {
    final pending = await _store.findReconciliationRequired();
    if (pending == null ||
        pending.clientRequestId != reservation.clientRequestId ||
        pending.identity != reservation.identity) {
      throw const GenerationReconciliationUnavailable();
    }
    final GenerationRequestReconciler reconciler;
    if (_provider case final GenerationRequestReconciler value) {
      reconciler = value;
    } else {
      throw const GenerationReconciliationUnavailable();
    }
    late final GenerationJob job;
    try {
      job = await reconciler.reconcile(pending);
    } on GenerationRemoteFailure catch (error) {
      if (error.statusCode == 404 && error.code == 'task_not_found') {
        await _store.deleteReservation(pending.clientRequestId);
        throw GenerationReconciliationNotFound(pending.clientRequestId);
      }
      rethrow;
    }
    if (!pending.identity.matches(job)) {
      throw const GenerationProtocolViolation(
        'reconciled job does not match the reserved request',
      );
    }
    await _store.save(job);
    if (!job.requiresReconciliation) {
      await _store.deleteReservation(pending.clientRequestId);
    }
    return job;
  }

  Future<T> _serializeCreate<T>(Future<T> Function() operation) {
    final result = _createTail.then((_) => operation());
    _createTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<GenerationJob> recordLocalSuccess({
    required GenerationSourceSnapshot snapshot,
    required String inputIdentity,
    required String provider,
    required String model,
    required GeneratedMedia output,
  }) async {
    if (inputIdentity.trim().isEmpty ||
        provider.trim().isEmpty ||
        model.trim().isEmpty) {
      throw ArgumentError(
        'Local generation input, provider, and model identities are required',
      );
    }
    final now = DateTime.now().toUtc();
    final job = GenerationJob(
      id: 'local:${output.id}',
      clientRequestId: 'local:${output.id}:$inputIdentity',
      projectId: snapshot.projectId,
      sourcePhotoId: snapshot.sourcePhotoId,
      sourceSha256: snapshot.sourceSha256,
      inputIdentity: inputIdentity,
      capability: snapshot.capability,
      state: GenerationJobState.succeeded,
      provider: provider,
      model: model,
      canCancel: false,
      createdAt: now,
      updatedAt: now,
      output: output,
    );
    await _store.save(job);
    return job;
  }

  Future<GenerationJob> markOutputSaved({
    required String jobId,
    required String mediaId,
    required String assetId,
  }) async {
    final job = await _store.findById(jobId);
    final output = job?.output;
    if (job == null || output == null || output.id != mediaId) {
      throw StateError('Unknown generated output $jobId/$mediaId');
    }
    final updated = job.copyWith(
      updatedAt: DateTime.now().toUtc(),
      output: output.markSaved(assetId),
    );
    await _store.save(updated);
    return updated;
  }

  Future<GenerationJob?> findLatest({
    required GenerationSourceSnapshot snapshot,
    String? inputIdentity,
    Set<GenerationJobState>? states,
    bool includeAnyInput = false,
  }) => _store.findLatest(
    GenerationRequestIdentity.fromSnapshot(
      snapshot,
      inputIdentity: inputIdentity,
    ),
    states: states,
    includeAnyInput: includeAnyInput,
  );

  Future<GenerationJob?> findLatestForIdentity(
    GenerationRequestIdentity identity, {
    Set<GenerationJobState>? states,
    bool includeAnyInput = false,
  }) => _store.findLatest(
    identity,
    states: states,
    includeAnyInput: includeAnyInput,
  );

  Future<GenerationJob?> findLatestSucceeded({
    required GenerationSourceSnapshot snapshot,
    String? inputIdentity,
  }) => findLatest(
    snapshot: snapshot,
    inputIdentity: inputIdentity,
    states: const {GenerationJobState.succeeded},
  );

  Future<void> prepareProjectDeletion(String projectId) async {
    if (projectId.trim().isEmpty) {
      throw ArgumentError.value(projectId, 'projectId');
    }
    final pending = await _store.findReconciliationRequired();
    if (pending != null && pending.identity.projectId == projectId) {
      throw GenerationProjectDeletionBlocked(
        projectId,
        pending.clientRequestId,
      );
    }
    final jobs = await _store.findByProjectId(projectId);
    for (final job in jobs) {
      if (job.state.isTerminal) {
        final usageStillHeld =
            job.usageDisposition == GenerationUsageDisposition.hold &&
            job.usageState != GenerationUsageState.released &&
            job.usageState != GenerationUsageState.settled;
        if (usageStillHeld) {
          throw GenerationProjectDeletionBlocked(projectId, job.id);
        }
        continue;
      }
      if (!job.canCancel) {
        throw GenerationProjectDeletionBlocked(projectId, job.id);
      }
      final cancelled = await cancel(job.id);
      final cancellationConfirmed =
          cancelled.state == GenerationJobState.cancelled &&
          (cancelled.usageState == null ||
              cancelled.usageState == GenerationUsageState.released);
      if (!cancellationConfirmed) {
        throw GenerationProjectDeletionBlocked(projectId, job.id);
      }
    }
  }

  Future<void> stageProjectDeletionCleanup(String projectId) {
    if (projectId.trim().isEmpty) {
      throw ArgumentError.value(projectId, 'projectId');
    }
    final cleanupStore = switch (_store) {
      GenerationProjectDeletionCleanupStore store => store,
      _ => null,
    };
    if (cleanupStore == null) return Future.value();
    return cleanupStore.stageProjectDeletionCleanup(projectId);
  }

  Future<void> deleteProjectState(String projectId) async {
    if (projectId.trim().isEmpty) {
      throw ArgumentError.value(projectId, 'projectId');
    }
    await _store.deleteProjectState(projectId);
    if (_store case final GenerationProjectDeletionCleanupStore cleanupStore) {
      await cleanupStore.completeProjectDeletionCleanup(projectId);
    }
  }

  /// Retries only cleanup that the user already authorized, and only when the
  /// current project catalog proves that the project no longer exists. A
  /// failure remains pending and never blocks the app or another cleanup.
  Future<void> retryProjectDeletionCleanups({
    required Set<String> existingProjectIds,
  }) async {
    final cleanupStore = switch (_store) {
      GenerationProjectDeletionCleanupStore store => store,
      _ => null,
    };
    if (cleanupStore == null) return;
    final pending = await cleanupStore.findPendingProjectDeletionCleanups();
    for (final projectId in pending) {
      if (existingProjectIds.contains(projectId)) continue;
      try {
        await _store.deleteProjectState(projectId);
        await cleanupStore.completeProjectDeletionCleanup(projectId);
      } on Object {
        // Keep the tombstone so a later safe catalog load can retry.
      }
    }
  }

  Future<GenerationJob> cancel(String id) async {
    final job = await _store.findById(id);
    if (job == null) throw StateError('Unknown generation job $id');
    if (!job.canCancel) throw GenerationCannotCancel(id);
    final updated = await _provider.cancel(job);
    _requireSameJobIdentity(job, updated);
    await _store.save(updated);
    return updated;
  }

  Stream<GenerationJob> observe(String id) async* {
    final job = await _store.findById(id);
    if (job == null) throw StateError('Unknown generation job $id');
    yield job;
    if (job.state.isTerminal) return;
    await for (final updated in _provider.observe(job)) {
      _requireSameJobIdentity(job, updated);
      await _store.save(updated);
      yield updated;
      if (updated.state.isTerminal) return;
    }
  }

  static void _requireSameJobIdentity(
    GenerationJob expected,
    GenerationJob actual,
  ) {
    if (actual.id != expected.id ||
        actual.clientRequestId != expected.clientRequestId ||
        actual.projectId != expected.projectId ||
        actual.sourcePhotoId != expected.sourcePhotoId ||
        actual.sourceSha256 != expected.sourceSha256 ||
        actual.sourceUploadSha256 != expected.sourceUploadSha256 ||
        actual.maskUploadSha256 != expected.maskUploadSha256 ||
        actual.inputIdentity != expected.inputIdentity ||
        actual.capability != expected.capability) {
      throw const GenerationProtocolViolation(
        'job update does not match the persisted source',
      );
    }
  }
}
