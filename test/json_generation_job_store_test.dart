import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';
import 'package:yingjian/features/generation/infrastructure/json_generation_job_store.dart';

void main() {
  test('generation jobs survive a JSON store round trip', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-generation-jobs-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = JsonGenerationJobStore(directory: () async => directory);
    final job = _job().copyWith(errorCode: 'provider_failed');

    await store.save(job);

    _expectSameJob(await store.findById(job.id), job);
    _expectSameJob(await store.findByClientRequestId(job.clientRequestId), job);
    expect(await store.findById('missing-job'), isNull);
    expect(await store.findByClientRequestId('missing-request'), isNull);
  });

  test('a verified generated media result survives restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-generated-media-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = JsonGenerationJobStore(directory: () async => directory);
    final output = GeneratedMedia(
      id: 'media-1',
      kind: GeneratedMediaKind.imageMotion,
      localPath: '${directory.path}/generated/result.mp4',
      contentSha256: List.filled(64, 'b').join(),
      width: 720,
      height: 1280,
      duration: const Duration(seconds: 2),
      savedAssetId: 'photos-asset-restored',
    );
    final completed = _job().copyWith(
      state: GenerationJobState.succeeded,
      canCancel: false,
      output: output,
      updatedAt: DateTime.utc(2026, 9, 1, 0, 2),
    );

    await store.save(completed);

    expect((await store.findById(completed.id))?.output, output);
    expect(
      (await store.findById(completed.id))?.output?.savedAssetId,
      'photos-asset-restored',
    );
  });

  test('a pre-dispatch request reservation survives restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-generation-reservation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = JsonGenerationJobStore(directory: () async => directory);
    final identity = GenerationRequestIdentity(
      projectId: 'project-1',
      sourcePhotoId: 'photo-1',
      sourceSha256: List.filled(64, 'a').join(),
      capability: CreationCapability.optimizeAiRepair,
    );
    final reservation = GenerationRequestReservation(
      clientRequestId: 'request-before-provider-call',
      identity: identity,
      createdAt: DateTime.utc(2026, 9, 1),
      state: GenerationRequestReservationState.reconciliationRequired,
    );

    await store.saveReservation(reservation);

    final restored = await JsonGenerationJobStore(
      directory: () async => directory,
    ).findReservation(identity);
    expect(restored?.clientRequestId, reservation.clientRequestId);
    expect(restored?.identity, identity);
    expect(restored?.createdAt, reservation.createdAt);
    expect(
      restored?.state,
      GenerationRequestReservationState.reconciliationRequired,
    );
    expect(
      (await store.findReconciliationRequired())?.clientRequestId,
      reservation.clientRequestId,
    );

    await store.deleteReservation(reservation.clientRequestId);
    expect(await store.findReservation(identity), isNull);
  });

  test(
    'a legacy incomplete reservation is migrated to reconciliation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yingjian-generation-legacy-reservation-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}/generation/request-reservations.json',
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'reservations': [
            {
              'clientRequestId': 'legacy-unknown-request',
              'projectId': 'legacy-project',
              'sourcePhotoId': 'legacy-photo',
              'sourceSha256': 'a' * 64,
              'capability': 'style.aiRedraw',
              'inputIdentity': 'style-redraw-v1:${'b' * 64}',
              'createdAt': '2026-09-02T01:00:30.000Z',
            },
          ],
        }),
      );
      final store = JsonGenerationJobStore(directory: () async => directory);

      final pending = await store.findReconciliationRequired();

      expect(pending?.clientRequestId, 'legacy-unknown-request');
      expect(
        pending?.state,
        GenerationRequestReservationState.reconciliationRequired,
      );
    },
  );

  test('project deletion cleanup authorization survives restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-generation-cleanup-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = JsonGenerationJobStore(directory: () async => directory);

    await store.stageProjectDeletionCleanup('project-1');

    final restored = JsonGenerationJobStore(directory: () async => directory);
    expect(await restored.findPendingProjectDeletionCleanups(), {'project-1'});

    await restored.completeProjectDeletionCleanup('project-1');
    expect(await restored.findPendingProjectDeletionCleanups(), isEmpty);
  });

  test(
    'latest result lookup respects exact input and terminal state',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yingjian-generation-latest-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = JsonGenerationJobStore(directory: () async => directory);
      final succeeded = _jobWith(
        id: 'job-success',
        requestId: 'request-success',
        inputIdentity: 'local-upscale-v1:4',
        state: GenerationJobState.succeeded,
        updatedAt: DateTime.utc(2026, 9, 1, 0, 1),
      );
      final failed = _jobWith(
        id: 'job-failed',
        requestId: 'request-failed',
        inputIdentity: 'local-upscale-v1:4',
        state: GenerationJobState.failed,
        updatedAt: DateTime.utc(2026, 9, 1, 0, 2),
      );
      await store.save(succeeded);
      await store.save(failed);
      final identity = GenerationRequestIdentity(
        projectId: 'project-1',
        sourcePhotoId: 'photo-1',
        sourceSha256: List.filled(64, 'a').join(),
        capability: CreationCapability.motionCameraPush,
        inputIdentity: 'local-upscale-v1:4',
      );

      expect((await store.findLatest(identity))?.id, failed.id);
      expect(
        (await store.findLatest(
          identity,
          states: const {GenerationJobState.succeeded},
        ))?.id,
        succeeded.id,
      );
    },
  );

  test('a failed atomic replacement preserves the last safe job', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-generation-job-atomic-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = JsonGenerationJobStore(directory: () async => directory);
    final queued = _job();
    await store.save(queued);
    final blockingTemporary = Directory(
      '${directory.path}/generation/jobs.json.tmp',
    );
    await blockingTemporary.create(recursive: true);

    await expectLater(
      store.save(
        queued.copyWith(
          state: GenerationJobState.running,
          updatedAt: DateTime.utc(2026, 9, 1, 0, 1),
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );

    final restored = await store.findById(queued.id);
    expect(restored?.state, GenerationJobState.queued);
    expect(restored?.updatedAt, DateTime.utc(2026, 9, 1));
  });

  test('corrupted JSON is rejected', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-generation-job-corrupt-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/generation/jobs.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('{not-json');
    final store = JsonGenerationJobStore(directory: () async => directory);

    await expectLater(store.findById('job-1'), throwsFormatException);
  });

  test('an unknown store schema is rejected', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-generation-job-schema-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/generation/jobs.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('{"schemaVersion":4,"jobs":[]}');
    final store = JsonGenerationJobStore(directory: () async => directory);

    await expectLater(store.findById('job-1'), throwsFormatException);
  });
}

GenerationJob _job() => GenerationJob(
  id: 'job-1',
  clientRequestId: 'request-1',
  projectId: 'project-1',
  sourcePhotoId: 'photo-1',
  sourceSha256: List.filled(64, 'a').join(),
  capability: CreationCapability.motionCameraPush,
  state: GenerationJobState.queued,
  provider: 'test-provider',
  model: 'test-model-v1',
  canCancel: true,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  cancellationDisposition:
      GenerationCancellationDisposition.availableWhilePending,
  usageState: GenerationUsageState.reserved,
  usageDisposition: GenerationUsageDisposition.hold,
);

GenerationJob _jobWith({
  required String id,
  required String requestId,
  required String inputIdentity,
  required GenerationJobState state,
  required DateTime updatedAt,
}) => GenerationJob(
  id: id,
  clientRequestId: requestId,
  projectId: 'project-1',
  sourcePhotoId: 'photo-1',
  sourceSha256: List.filled(64, 'a').join(),
  inputIdentity: inputIdentity,
  capability: CreationCapability.motionCameraPush,
  state: state,
  provider: 'ios-local',
  model: 'motion-v1',
  canCancel: false,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: updatedAt,
);

void _expectSameJob(GenerationJob? actual, GenerationJob expected) {
  expect(actual, isNotNull);
  expect(actual!.id, expected.id);
  expect(actual.clientRequestId, expected.clientRequestId);
  expect(actual.projectId, expected.projectId);
  expect(actual.sourcePhotoId, expected.sourcePhotoId);
  expect(actual.sourceSha256, expected.sourceSha256);
  expect(actual.capability, expected.capability);
  expect(actual.state, expected.state);
  expect(actual.provider, expected.provider);
  expect(actual.model, expected.model);
  expect(actual.canCancel, expected.canCancel);
  expect(actual.createdAt, expected.createdAt);
  expect(actual.updatedAt, expected.updatedAt);
  expect(actual.cancellationDisposition, expected.cancellationDisposition);
  expect(actual.usageState, expected.usageState);
  expect(actual.usageDisposition, expected.usageDisposition);
  expect(actual.errorCode, expected.errorCode);
  expect(actual.output, expected.output);
}
