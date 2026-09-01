import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';

void main() {
  test('generation requires explicit upload and cost consent', () async {
    final provider = _RecordingGenerationProvider();
    final coordinator = GenerationCoordinator(
      provider: provider,
      store: _MemoryGenerationJobStore(),
    );
    final snapshot = GenerationSourceSnapshot(
      projectId: 'project-1',
      sourcePhotoId: 'photo-1',
      sourcePath: '/private/source.jpg',
      sourceSha256: List.filled(64, 'a').join(),
      capability: CreationCapability.optimizeAiRepair,
      createdAt: DateTime.utc(2026, 9, 1),
    );

    await expectLater(
      coordinator.create(
        snapshot: snapshot,
        clientRequestId: 'request-1',
        consent: null,
      ),
      throwsA(isA<GenerationConsentRequired>()),
    );

    expect(provider.createCalls, isEmpty);
  });

  test(
    'a local zero-cost capability runs after its explicit primary action',
    () async {
      final provider = _RecordingGenerationProvider(
        offer: GenerationOffer.local(
          id: 'local-upscale-v1',
          capability: CreationCapability.optimizeUpscale,
        ),
        availableCapabilities: const {CreationCapability.optimizeUpscale},
      );
      final coordinator = GenerationCoordinator(
        provider: provider,
        store: _MemoryGenerationJobStore(),
      );

      final job = await coordinator.create(
        snapshot: _snapshot(CreationCapability.optimizeUpscale),
        clientRequestId: 'request-local',
        consent: null,
      );

      expect(job.capability, CreationCapability.optimizeUpscale);
      expect(provider.createCalls, hasLength(1));
    },
  );

  test(
    'generation rejects a capability the configured provider cannot run',
    () async {
      final provider = _RecordingGenerationProvider(
        availableCapabilities: const {CreationCapability.optimizeUpscale},
      );
      final coordinator = GenerationCoordinator(
        provider: provider,
        store: _MemoryGenerationJobStore(),
      );

      await expectLater(
        coordinator.create(
          snapshot: _snapshot(CreationCapability.optimizeAiRepair),
          clientRequestId: 'request-unsupported',
          consent: _completeConsent,
        ),
        throwsA(
          isA<GenerationCapabilityUnavailable>().having(
            (error) => error.capability,
            'capability',
            CreationCapability.optimizeAiRepair,
          ),
        ),
      );

      expect(provider.createCalls, isEmpty);
    },
  );

  test('the same confirmed client request creates at most one job', () async {
    final provider = _RecordingGenerationProvider();
    final store = _MemoryGenerationJobStore();
    final coordinator = GenerationCoordinator(provider: provider, store: store);

    final first = await coordinator.create(
      snapshot: _snapshot(CreationCapability.optimizeAiRepair),
      clientRequestId: 'request-idempotent',
      consent: _completeConsent,
    );
    final recovered = await coordinator.create(
      snapshot: _snapshot(CreationCapability.optimizeAiRepair),
      clientRequestId: 'request-idempotent',
      consent: _completeConsent,
    );

    expect(recovered, first);
    expect(provider.createCalls, hasLength(1));
    expect(await store.findByClientRequestId('request-idempotent'), first);
  });

  test(
    'a cloud retry reuses the request id reserved before the provider call',
    () async {
      final provider = _RecordingGenerationProvider()..failCreateCount = 1;
      final store = _MemoryGenerationJobStore();
      final coordinator = GenerationCoordinator(
        provider: provider,
        store: store,
      );
      var requestSequence = 0;
      String nextRequestId() => 'persistent-request-${requestSequence++}';
      final snapshot = _snapshot(CreationCapability.optimizeAiRepair);

      await expectLater(
        coordinator.createPersisted(
          snapshot: snapshot,
          consent: _completeConsent,
          clientRequestIdFactory: nextRequestId,
        ),
        throwsA(isA<StateError>()),
      );
      final recovered = await coordinator.createPersisted(
        snapshot: snapshot,
        consent: _completeConsent,
        clientRequestIdFactory: nextRequestId,
      );

      expect(provider.createRequestIds, [
        'persistent-request-0',
        'persistent-request-0',
      ]);
      expect(recovered.clientRequestId, 'persistent-request-0');
      expect(requestSequence, 1);
      expect(
        await store.findReservation(
          GenerationRequestIdentity.fromSnapshot(snapshot),
        ),
        isNull,
      );
    },
  );

  test(
    'a completed local result is recoverable by its exact input identity',
    () async {
      final store = _MemoryGenerationJobStore();
      final coordinator = GenerationCoordinator(
        provider: const _UnavailableGenerationProvider(),
        store: store,
      );
      final snapshot = _snapshot(CreationCapability.optimizeUpscale);
      final output = GeneratedMedia(
        id: 'local-media-4x',
        kind: GeneratedMediaKind.image,
        localPath: '/private/generated/upscale-4x.jpg',
        contentSha256: List.filled(64, 'd').join(),
        width: 4096,
        height: 3072,
      );

      final recorded = await coordinator.recordLocalSuccess(
        snapshot: snapshot,
        inputIdentity: 'local-upscale-v1:4',
        provider: 'ios-core-image',
        model: 'lanczos-v1',
        output: output,
      );

      expect(recorded.state, GenerationJobState.succeeded);
      expect(recorded.inputIdentity, 'local-upscale-v1:4');
      expect(
        await coordinator.findLatestSucceeded(
          snapshot: snapshot,
          inputIdentity: 'local-upscale-v1:4',
        ),
        recorded,
      );
      expect(
        await coordinator.findLatestSucceeded(
          snapshot: snapshot,
          inputIdentity: 'local-upscale-v1:2',
        ),
        isNull,
      );
    },
  );

  test(
    'saving generated media persists the real photo-library asset id',
    () async {
      final store = _MemoryGenerationJobStore();
      final coordinator = GenerationCoordinator(
        provider: const _UnavailableGenerationProvider(),
        store: store,
      );
      final recorded = await coordinator.recordLocalSuccess(
        snapshot: _snapshot(CreationCapability.optimizeUpscale),
        inputIdentity: 'local-upscale-v1:2',
        provider: 'ios-core-image',
        model: 'lanczos-v1',
        output: _generatedImage,
      );

      final saved = await coordinator.markOutputSaved(
        jobId: recorded.id,
        mediaId: _generatedImage.id,
        assetId: 'photos-asset-42',
      );

      expect(saved.output?.savedAssetId, 'photos-asset-42');
      expect(
        (await store.findById(recorded.id))?.output?.savedAssetId,
        'photos-asset-42',
      );
    },
  );

  test('an idempotency key cannot be reused for a different source', () async {
    final provider = _RecordingGenerationProvider();
    final store = _MemoryGenerationJobStore();
    final coordinator = GenerationCoordinator(provider: provider, store: store);

    await coordinator.create(
      snapshot: _snapshot(CreationCapability.optimizeAiRepair),
      clientRequestId: 'request-conflict',
      consent: _completeConsent,
    );
    final changedSource = GenerationSourceSnapshot(
      projectId: 'project-1',
      sourcePhotoId: 'photo-2',
      sourcePath: '/private/other.jpg',
      sourceSha256: List.filled(64, 'b').join(),
      capability: CreationCapability.optimizeAiRepair,
      createdAt: DateTime.utc(2026, 9, 1),
    );

    await expectLater(
      coordinator.create(
        snapshot: changedSource,
        clientRequestId: 'request-conflict',
        consent: _completeConsent,
      ),
      throwsA(isA<GenerationRequestConflict>()),
    );
    expect(provider.createCalls, hasLength(1));
  });

  test(
    'project deletion cancels an active job and persists the outcome',
    () async {
      final provider = _RecordingGenerationProvider();
      final store = _MemoryGenerationJobStore();
      final coordinator = GenerationCoordinator(
        provider: provider,
        store: store,
      );
      final created = await coordinator.create(
        snapshot: _snapshot(CreationCapability.optimizeAiRepair),
        clientRequestId: 'request-cancel',
        consent: _completeConsent,
      );
      provider.cancelResponse = created.copyWith(
        state: GenerationJobState.cancelled,
        canCancel: false,
        usageState: GenerationUsageState.released,
        usageDisposition: GenerationUsageDisposition.release,
        updatedAt: DateTime.utc(2026, 9, 1, 0, 1),
      );

      await coordinator.prepareProjectDeletion(created.projectId);

      expect(provider.cancelCalls, [created.id]);
      expect(
        (await store.findById(created.id))?.state,
        GenerationJobState.cancelled,
      );
    },
  );

  test('a non-cancellable job never sends a false cancel request', () async {
    final provider = _RecordingGenerationProvider(canCancelOnCreate: false);
    final store = _MemoryGenerationJobStore();
    final coordinator = GenerationCoordinator(provider: provider, store: store);
    final created = await coordinator.create(
      snapshot: _snapshot(CreationCapability.optimizeAiRepair),
      clientRequestId: 'request-non-cancellable',
      consent: _completeConsent,
    );

    await expectLater(
      coordinator.cancel(created.id),
      throwsA(isA<GenerationCannotCancel>()),
    );
    expect(provider.cancelCalls, isEmpty);
  });

  test('observe persists remote progress through the terminal state', () async {
    final provider = _RecordingGenerationProvider();
    final store = _MemoryGenerationJobStore();
    final coordinator = GenerationCoordinator(provider: provider, store: store);
    final created = await coordinator.create(
      snapshot: _snapshot(CreationCapability.optimizeAiRepair),
      clientRequestId: 'request-observe',
      consent: _completeConsent,
    );
    provider.observedJobs = [
      created.copyWith(
        state: GenerationJobState.running,
        updatedAt: DateTime.utc(2026, 9, 1, 0, 1),
      ),
      created.copyWith(
        state: GenerationJobState.succeeded,
        canCancel: false,
        output: _generatedImage,
        updatedAt: DateTime.utc(2026, 9, 1, 0, 2),
      ),
    ];

    final states = await coordinator
        .observe(created.id)
        .map((job) => job.state)
        .toList();

    expect(states, [
      GenerationJobState.queued,
      GenerationJobState.running,
      GenerationJobState.succeeded,
    ]);
    expect(provider.observeCalls, [created.id]);
    final saved = await store.findById(created.id);
    expect(saved?.state, GenerationJobState.succeeded);
    expect(saved?.output, _generatedImage);
  });

  test('observe rejects an update bound to another source', () async {
    final provider = _RecordingGenerationProvider();
    final store = _MemoryGenerationJobStore();
    final coordinator = GenerationCoordinator(provider: provider, store: store);
    final created = await coordinator.create(
      snapshot: _snapshot(CreationCapability.optimizeAiRepair),
      clientRequestId: 'request-wrong-source',
      consent: _completeConsent,
    );
    provider.observedJobs = [
      GenerationJob(
        id: created.id,
        clientRequestId: created.clientRequestId,
        projectId: created.projectId,
        sourcePhotoId: 'other-photo',
        sourceSha256: List.filled(64, 'b').join(),
        capability: created.capability,
        state: GenerationJobState.succeeded,
        provider: created.provider,
        model: created.model,
        canCancel: false,
        createdAt: created.createdAt,
        updatedAt: DateTime.utc(2026, 9, 1, 0, 2),
      ),
    ];

    await expectLater(
      coordinator.observe(created.id).drain<void>(),
      throwsA(isA<GenerationProtocolViolation>()),
    );
    expect(
      (await store.findById(created.id))?.state,
      GenerationJobState.queued,
    );
  });
}

final _completeConsent = GenerationConsent(
  offerId: 'test-cloud-offer-v1',
  uploadConfirmed: true,
  costConfirmed: true,
  policyVersion: 1,
  confirmedAt: DateTime.utc(2026, 9, 1),
);

final _generatedImage = GeneratedMedia(
  id: 'media-1',
  kind: GeneratedMediaKind.image,
  localPath: '/private/generated/result.jpg',
  contentSha256: List.filled(64, 'c').join(),
  width: 2048,
  height: 1536,
);

GenerationSourceSnapshot _snapshot(CreationCapability capability) =>
    GenerationSourceSnapshot(
      projectId: 'project-1',
      sourcePhotoId: 'photo-1',
      sourcePath: '/private/source.jpg',
      sourceSha256: List.filled(64, 'a').join(),
      capability: capability,
      createdAt: DateTime.utc(2026, 9, 1),
    );

final class _RecordingGenerationProvider implements GenerationProvider {
  _RecordingGenerationProvider({
    this.availableCapabilities = const {CreationCapability.optimizeAiRepair},
    this.canCancelOnCreate = true,
    GenerationOffer? offer,
  }) : offer =
           offer ??
           GenerationOffer.cloud(
             id: 'test-cloud-offer-v1',
             capability: availableCapabilities.first,
             creditCost: 1,
             expiresAt: DateTime.utc(2026, 9, 2),
           );

  final List<GenerationSourceSnapshot> createCalls = [];
  final List<String> createRequestIds = [];
  final List<String> cancelCalls = [];
  final List<String> observeCalls = [];
  GenerationJob? cancelResponse;
  List<GenerationJob> observedJobs = [];
  int failCreateCount = 0;
  final bool canCancelOnCreate;
  final GenerationOffer offer;

  @override
  final Set<CreationCapability> availableCapabilities;

  @override
  Future<void> refreshCapabilities() async {}

  @override
  GenerationOffer offerFor(CreationCapability capability) => offer;

  @override
  Future<GenerationJob> create({
    required GenerationSourceSnapshot snapshot,
    required String clientRequestId,
    required GenerationConsent? consent,
  }) async {
    createCalls.add(snapshot);
    createRequestIds.add(clientRequestId);
    if (failCreateCount > 0) {
      failCreateCount -= 1;
      throw StateError('simulated response loss');
    }
    return GenerationJob(
      id: 'job-1',
      clientRequestId: clientRequestId,
      projectId: snapshot.projectId,
      sourcePhotoId: snapshot.sourcePhotoId,
      sourceSha256: snapshot.sourceSha256,
      capability: snapshot.capability,
      state: GenerationJobState.queued,
      provider: 'test',
      model: 'test-v1',
      canCancel: canCancelOnCreate,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );
  }

  @override
  Future<GenerationJob> cancel(GenerationJob job) async {
    cancelCalls.add(job.id);
    return cancelResponse ?? job;
  }

  @override
  Stream<GenerationJob> observe(GenerationJob job) async* {
    observeCalls.add(job.id);
    for (final update in observedJobs) {
      yield update;
    }
  }
}

final class _UnavailableGenerationProvider implements GenerationProvider {
  const _UnavailableGenerationProvider();

  @override
  Set<CreationCapability> get availableCapabilities => const {};

  @override
  Future<void> refreshCapabilities() async {}

  @override
  Future<GenerationJob> cancel(GenerationJob job) =>
      throw UnsupportedError('unavailable');

  @override
  Future<GenerationJob> create({
    required GenerationSourceSnapshot snapshot,
    required String clientRequestId,
    required GenerationConsent? consent,
  }) => throw UnsupportedError('unavailable');

  @override
  Stream<GenerationJob> observe(GenerationJob job) => const Stream.empty();

  @override
  GenerationOffer offerFor(CreationCapability capability) =>
      throw UnsupportedError('unavailable');
}

final class _MemoryGenerationJobStore implements GenerationJobStore {
  final Map<String, GenerationJob> _jobsByRequest = {};
  final Map<String, GenerationJob> _jobsById = {};
  final Map<GenerationRequestIdentity, GenerationRequestReservation>
  _reservations = {};

  @override
  Future<GenerationJob?> findByClientRequestId(String clientRequestId) async =>
      _jobsByRequest[clientRequestId];

  @override
  Future<GenerationJob?> findById(String id) async => _jobsById[id];

  @override
  Future<List<GenerationJob>> findByProjectId(String projectId) async =>
      _jobsById.values
          .where((job) => job.projectId == projectId)
          .toList(growable: false);

  @override
  Future<GenerationJob?> findLatest(
    GenerationRequestIdentity identity, {
    Set<GenerationJobState>? states,
    bool includeAnyInput = false,
  }) async {
    final matches =
        _jobsById.values
            .where(
              (job) =>
                  identity.matches(job, includeAnyInput: includeAnyInput) &&
                  (states == null || states.contains(job.state)),
            )
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return matches.firstOrNull;
  }

  @override
  Future<GenerationRequestReservation?> findReservation(
    GenerationRequestIdentity identity,
  ) async => _reservations[identity];

  @override
  Future<void> saveReservation(GenerationRequestReservation reservation) async {
    _reservations[reservation.identity] = reservation;
  }

  @override
  Future<void> deleteReservation(String clientRequestId) async {
    _reservations.removeWhere(
      (_, reservation) => reservation.clientRequestId == clientRequestId,
    );
  }

  @override
  Future<void> deleteProjectState(String projectId) async {
    _jobsById.removeWhere((_, job) => job.projectId == projectId);
    _jobsByRequest.removeWhere((_, job) => job.projectId == projectId);
    _reservations.removeWhere((identity, _) => identity.projectId == projectId);
  }

  @override
  Future<void> save(GenerationJob job) async {
    _jobsByRequest[job.clientRequestId] = job;
    _jobsById[job.id] = job;
  }
}
