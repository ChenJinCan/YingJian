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
    this.sharePathsByPhotoId = const {},
  });

  final int savedCount;
  final int failedCount;
  final int cancelledCount;
  final Map<String, String> sharePathsByPhotoId;

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
  bool get canShare => sharePathsByPhotoId.isNotEmpty;
}

final class BoundedBatchPhotoExporter {
  BoundedBatchPhotoExporter({
    required this.session,
    required this.exporter,
    this.options = PhotoExportOptions.defaults,
    this.onSharePathCreated,
  });

  final PhotoProjectSession session;
  final PhotoExporter exporter;
  final PhotoExportOptions options;
  final void Function(String photoId, String localPath)? onSharePathCreated;
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

  Future<BatchExportSummary> export({
    bool retryFailuresOnly = false,
    Set<String>? photoIds,
  }) async {
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
      if (photoIds != null && !photoIds.contains(photo.id)) return false;
      final state = project.exportStates[photo.id]!;
      return retryFailuresOnly
          ? state == PhotoExportState.failed ||
                state == PhotoExportState.cancelled
          : state == PhotoExportState.notQueued;
    }).toList();
    if (targets.isEmpty) throw StateError('There are no photos to export');

    _running = true;
    _cancelRequested = false;
    final sharePathsByPhotoId = <String, String>{};
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
          final recipe = session.effectiveRecipeFor(photo.id);
          final exported = exporter is ConfigurablePhotoExporter
              ? await (exporter as ConfigurablePhotoExporter).exportWithOptions(
                  photo: photo,
                  recipe: recipe,
                  options: options,
                )
              : await exporter.export(photo: photo, recipe: recipe);
          final sharePath = exported.sharePath;
          if (sharePath != null && sharePath.isNotEmpty) {
            onSharePathCreated?.call(photo.id, sharePath);
          }
          await session.setPhotoExportState(photo.id, PhotoExportState.saved);
          if (sharePath != null && sharePath.isNotEmpty) {
            sharePathsByPhotoId[photo.id] = sharePath;
          }
        } on Object {
          await session.setPhotoExportState(photo.id, PhotoExportState.failed);
        }
      }
      await session.transitionTo(PhotoProjectFlowState.exported);
      final summary = BatchExportSummary.fromProject(session.project!);
      return BatchExportSummary(
        savedCount: summary.savedCount,
        failedCount: summary.failedCount,
        cancelledCount: summary.cancelledCount,
        sharePathsByPhotoId: Map.unmodifiable(sharePathsByPhotoId),
      );
    } finally {
      _running = false;
    }
  }
}
