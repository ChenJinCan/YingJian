import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/batch_photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

import 'support/test_services.dart';

void main() {
  test(
    'partial failure preserves successes and retry only exports failures',
    () async {
      final photos = _photos(3);
      final store = MemoryPhotoProjectStore(_project(photos));
      final session = PhotoProjectSession(
        importer: FakePhotoImporter(),
        store: store,
        now: () => DateTime.utc(2026, 8, 4),
      );
      await session.restore();
      final exporter = _RecordingExporter(failOnce: {'photo-2'});
      final batch = BoundedBatchPhotoExporter(
        session: session,
        exporter: exporter,
      );

      final first = await batch.export();
      expect(first.savedCount, 2);
      expect(first.failedCount, 1);
      expect(first.cancelledCount, 0);
      expect(first.sharePathsByPhotoId.keys, {'photo-1', 'photo-3'});
      expect(exporter.calls, ['photo-1', 'photo-2', 'photo-3']);
      expect(session.project?.flowState, PhotoProjectFlowState.exported);

      final second = await batch.export(retryFailuresOnly: true);
      expect(second.savedCount, 3);
      expect(second.failedCount, 0);
      expect(second.sharePathsByPhotoId.keys, {'photo-2'});
      expect(exporter.calls, ['photo-1', 'photo-2', 'photo-3', 'photo-2']);
    },
  );

  test('cancel keeps completed saves and cancels only queued work', () async {
    final photos = _photos(3);
    final store = MemoryPhotoProjectStore(_project(photos));
    final session = PhotoProjectSession(
      importer: FakePhotoImporter(),
      store: store,
      now: () => DateTime.utc(2026, 8, 4),
    );
    await session.restore();
    final exporter = _DeferredFirstExporter();
    final batch = BoundedBatchPhotoExporter(
      session: session,
      exporter: exporter,
    );

    final pending = batch.export();
    await exporter.started.future;
    batch.cancel();
    exporter.finish.complete();
    final summary = await pending;

    expect(summary.savedCount, 1);
    expect(summary.cancelledCount, 2);
    expect(exporter.calls, ['photo-1']);
    expect(session.project?.exportStates, {
      'photo-1': PhotoExportState.saved,
      'photo-2': PhotoExportState.cancelled,
      'photo-3': PhotoExportState.cancelled,
    });
  });

  test('forwards one frozen export configuration to every photo', () async {
    final photos = _photos(2);
    final session = PhotoProjectSession(
      importer: FakePhotoImporter(),
      store: MemoryPhotoProjectStore(_project(photos)),
    );
    await session.restore();
    final exporter = _ConfigurableRecordingExporter();
    final options = PhotoExportOptions(
      format: PhotoExportFormat.heif,
      size: PhotoExportSize.longEdge,
      longEdgePixels: 2048,
      quality: PhotoExportQuality.standard,
    );

    await BoundedBatchPhotoExporter(
      session: session,
      exporter: exporter,
      options: options,
    ).export();

    expect(exporter.options, [options, options]);
  });

  test(
    'restart marks interrupted work cancelled without replaying it',
    () async {
      final photos = _photos(3);
      final store = MemoryPhotoProjectStore(
        _project(photos).copyWith(
          flowState: PhotoProjectFlowState.exporting,
          exportStates: const {
            'photo-1': PhotoExportState.saved,
            'photo-2': PhotoExportState.running,
            'photo-3': PhotoExportState.queued,
          },
        ),
      );
      final session = PhotoProjectSession(
        importer: FakePhotoImporter(),
        store: store,
        now: () => DateTime.utc(2026, 8, 4),
      );
      await session.restore();

      final summary = await BoundedBatchPhotoExporter.recoverInterrupted(
        session,
      );

      expect(summary?.savedCount, 1);
      expect(summary?.cancelledCount, 2);
      expect(session.project?.flowState, PhotoProjectFlowState.exported);
      expect(session.project?.exportStates, {
        'photo-1': PhotoExportState.saved,
        'photo-2': PhotoExportState.cancelled,
        'photo-3': PhotoExportState.cancelled,
      });
    },
  );
}

List<ProjectPhoto> _photos(int count) => List.generate(
  count,
  (index) => ProjectPhoto(
    id: 'photo-${index + 1}',
    localPath: '/project/photo-${index + 1}.jpg',
    originalName: 'photo-${index + 1}.jpg',
  ),
);

PhotoProject _project(List<ProjectPhoto> photos) => PhotoProject(
  id: 'project-1',
  createdAt: DateTime.utc(2026, 8, 4),
  updatedAt: DateTime.utc(2026, 8, 4),
  photos: photos,
  flowState: PhotoProjectFlowState.editing,
  selectedRecommendationId: 'mvp-catalog-v1:clean-balanced',
);

final class _RecordingExporter implements PhotoExporter {
  _RecordingExporter({Set<String> failOnce = const {}})
    : failOnce = {...failOnce};

  final Set<String> failOnce;
  final List<String> calls = [];

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    calls.add(photo.id);
    if (failOnce.remove(photo.id)) throw StateError('fixture failure');
    return ExportedPhoto(
      assetId: photo.id,
      width: 4032,
      height: 3024,
      sharePath: '/tmp/Yingjian_${photo.id}.jpg',
    );
  }
}

final class _DeferredFirstExporter implements PhotoExporter {
  final started = Completer<void>();
  final finish = Completer<void>();
  final List<String> calls = [];

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    calls.add(photo.id);
    started.complete();
    await finish.future;
    return ExportedPhoto(
      assetId: photo.id,
      width: 4032,
      height: 3024,
      sharePath: '/tmp/Yingjian_${photo.id}.jpg',
    );
  }
}

final class _ConfigurableRecordingExporter
    implements ConfigurablePhotoExporter {
  final List<PhotoExportOptions> options = [];

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) => exportWithOptions(
    photo: photo,
    recipe: recipe,
    options: PhotoExportOptions.defaults,
  );

  @override
  Future<ExportedPhoto> exportWithOptions({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required PhotoExportOptions options,
  }) async {
    this.options.add(options);
    return ExportedPhoto(assetId: photo.id, width: 2048, height: 1536);
  }
}
