import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

@immutable
class BatchExportSummary {
  const BatchExportSummary({
    required this.savedCount,
    required this.failedCount,
    required this.cancelledCount,
  });

  final int savedCount;
  final int failedCount;
  final int cancelledCount;

  factory BatchExportSummary.fromProject(PhotoProject project) =>
      BatchExportSummary(
        savedCount: project.exportStates.values
            .where((state) => state == PhotoExportState.saved)
            .length,
        failedCount: project.exportStates.values
            .where((state) => state == PhotoExportState.failed)
            .length,
        cancelledCount: project.exportStates.values
            .where((state) => state == PhotoExportState.cancelled)
            .length,
      );

  int get totalCount => savedCount + failedCount + cancelledCount;
  bool get hasRetryableItems => failedCount > 0 || cancelledCount > 0;
}

final class BoundedBatchPhotoExporter {
  BoundedBatchPhotoExporter({required this.session, required this.exporter});

  final PhotoProjectSession session;
  final PhotoExporter exporter;
  bool _cancelRequested = false;
  bool _running = false;

  bool get isRunning => _running;

  void cancel() {
    if (_running) _cancelRequested = true;
  }

  static Future<BatchExportSummary?> recoverInterrupted(
    PhotoProjectSession session,
  ) async {
    final project = session.project;
    if (project == null) return null;
    if (project.flowState == PhotoProjectFlowState.exporting) {
      for (final photo in project.photos) {
        final state = session.project!.exportStates[photo.id]!;
        if (state == PhotoExportState.queued ||
            state == PhotoExportState.running) {
          await session.setPhotoExportState(
            photo.id,
            PhotoExportState.cancelled,
          );
        }
      }
      await session.transitionTo(PhotoProjectFlowState.exported);
    }
    return session.project?.flowState == PhotoProjectFlowState.exported
        ? BatchExportSummary.fromProject(session.project!)
        : null;
  }

  Future<BatchExportSummary> export({bool retryFailuresOnly = false}) async {
    if (_running) throw StateError('A batch export is already active');
    final initial = session.project;
    if (initial == null) throw StateError('A photo project is required');
    if (initial.flowState == PhotoProjectFlowState.exported) {
      await session.transitionTo(PhotoProjectFlowState.editing);
    }
    final project = session.project!;
    if (project.flowState != PhotoProjectFlowState.editing) {
      throw StateError('Batch export can only start from editing');
    }
    final targets = project.photos.where((photo) {
      final state = project.exportStates[photo.id]!;
      return retryFailuresOnly
          ? state == PhotoExportState.failed ||
                state == PhotoExportState.cancelled
          : state == PhotoExportState.notQueued;
    }).toList();
    if (targets.isEmpty) throw StateError('There are no photos to export');

    _running = true;
    _cancelRequested = false;
    try {
      for (final photo in targets) {
        await session.setPhotoExportState(photo.id, PhotoExportState.queued);
      }
      await session.transitionTo(PhotoProjectFlowState.exporting);
      for (final photo in targets) {
        if (_cancelRequested) {
          await session.setPhotoExportState(
            photo.id,
            PhotoExportState.cancelled,
          );
          continue;
        }
        await session.setPhotoExportState(photo.id, PhotoExportState.running);
        try {
          await exporter.export(
            photo: photo,
            recipe: session.effectiveRecipeFor(photo.id),
          );
          await session.setPhotoExportState(photo.id, PhotoExportState.saved);
        } on Object {
          await session.setPhotoExportState(photo.id, PhotoExportState.failed);
        }
      }
      await session.transitionTo(PhotoProjectFlowState.exported);
      return BatchExportSummary.fromProject(session.project!);
    } finally {
      _running = false;
    }
  }
}
