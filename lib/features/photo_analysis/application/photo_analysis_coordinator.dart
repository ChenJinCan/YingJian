import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/photo_analysis/application/photo_analysis_cache.dart';
import 'package:yingjian/features/photo_analysis/domain/photo_analysis.dart';

typedef AnalysisStateCallback =
    Future<void> Function(String photoId, PhotoAnalysisState state);

final class PhotoAnalysisCancellationToken {
  bool _cancelRequested = false;
  bool _commitInProgress = false;

  bool get isCancelled => _cancelRequested && !_commitInProgress;

  void cancel() => _cancelRequested = true;

  bool tryStartCommit() {
    if (_cancelRequested || _commitInProgress) return false;
    _commitInProgress = true;
    return true;
  }

  void finishCommit() => _commitInProgress = false;
}

/// Performs optional local capability analysis without producing a user-facing
/// stage or blocking access to the editor.
final class PhotoAnalysisCoordinator {
  const PhotoAnalysisCoordinator({required this.analyzer, required this.cache});

  final PhotoAnalyzer analyzer;
  final PhotoAnalysisCache cache;

  Future<Map<String, LocalPhotoAnalysis>> analyze({
    required String projectId,
    required List<ProjectPhoto> photos,
    AnalysisStateCallback? onStateChanged,
    PhotoAnalysisCancellationToken? cancellation,
  }) async {
    final analyses = <String, LocalPhotoAnalysis>{};
    for (final photo in photos) {
      await onStateChanged?.call(photo.id, PhotoAnalysisState.running);
      if (cancellation?.isCancelled == true) {
        analyses[photo.id] = _cancelledFallback(photo);
        await onStateChanged?.call(photo.id, PhotoAnalysisState.fallback);
        continue;
      }
      final engineIdentity = analyzer.identityFor(photo);
      final cached = await _readCache(
        projectId: projectId,
        photo: photo,
        engineIdentity: engineIdentity,
      );
      if (cached != null && cancellation?.isCancelled != true) {
        analyses[photo.id] = cached;
        await onStateChanged?.call(
          photo.id,
          cached.usesSafeFallback
              ? PhotoAnalysisState.fallback
              : PhotoAnalysisState.ready,
        );
        continue;
      }
      if (cancellation?.isCancelled == true) {
        analyses[photo.id] = _cancelledFallback(photo);
        await onStateChanged?.call(photo.id, PhotoAnalysisState.fallback);
        continue;
      }
      try {
        final analysis = await analyzer.analyze(photo);
        if (cancellation?.isCancelled == true) {
          analyses[photo.id] = _cancelledFallback(photo);
          await onStateChanged?.call(photo.id, PhotoAnalysisState.fallback);
          continue;
        }
        if (!analysis.matchesInput(photo) ||
            !engineIdentity.matches(analysis)) {
          throw StateError('Analyzer returned a stale or invalid result');
        }
        final stagedWrite = await _stageCache(
          projectId: projectId,
          photoId: photo.id,
          analysis: analysis,
        );
        if (cancellation?.isCancelled == true) {
          await _discardCacheWrite(stagedWrite);
          analyses[photo.id] = _cancelledFallback(photo);
          await onStateChanged?.call(photo.id, PhotoAnalysisState.fallback);
          continue;
        }
        var commitClaimed = false;
        final committed = await _commitCacheWrite(
          stagedWrite,
          canCommit: () {
            if (cancellation == null) return true;
            commitClaimed = cancellation.tryStartCommit();
            return commitClaimed;
          },
        );
        if (!committed && cancellation?.isCancelled == true) {
          analyses[photo.id] = _cancelledFallback(photo);
          await onStateChanged?.call(photo.id, PhotoAnalysisState.fallback);
          continue;
        }
        try {
          analyses[photo.id] = analysis;
          await onStateChanged?.call(
            photo.id,
            analysis.usesSafeFallback
                ? PhotoAnalysisState.fallback
                : PhotoAnalysisState.ready,
          );
        } finally {
          if (commitClaimed) cancellation!.finishCommit();
        }
      } on Object {
        analyses[photo.id] = _failedFallback(photo);
        await onStateChanged?.call(photo.id, PhotoAnalysisState.fallback);
      }
    }
    return Map.unmodifiable(analyses);
  }

  Future<LocalPhotoAnalysis?> _readCache({
    required String projectId,
    required ProjectPhoto photo,
    required PhotoAnalysisEngineIdentity engineIdentity,
  }) async {
    try {
      return await cache.read(
        projectId: projectId,
        photo: photo,
        engineIdentity: engineIdentity,
      );
    } on Object {
      return null;
    }
  }

  Future<PhotoAnalysisCacheWrite?> _stageCache({
    required String projectId,
    required String photoId,
    required LocalPhotoAnalysis analysis,
  }) async {
    try {
      return await cache.stage(
        projectId: projectId,
        photoId: photoId,
        analysis: analysis,
      );
    } on Object {
      return null;
    }
  }

  Future<bool> _commitCacheWrite(
    PhotoAnalysisCacheWrite? write, {
    required bool Function() canCommit,
  }) async {
    if (write == null) return false;
    try {
      return await cache.commit(write, canCommit: canCommit);
    } on Object {
      return false;
    }
  }

  Future<void> _discardCacheWrite(PhotoAnalysisCacheWrite? write) async {
    if (write == null) return;
    try {
      await cache.discard(write);
    } on Object {
      // Staged writes are never visible, so cleanup remains best effort.
    }
  }

  LocalPhotoAnalysis _failedFallback(ProjectPhoto photo) => LocalPhotoAnalysis(
    analysisVersion: 'failed-safe-v1',
    capabilityVersion: 'unavailable',
    contentSha256: photo.contentSha256,
    orientation: photo.orientation,
    pixelWidth: photo.pixelWidth,
    pixelHeight: photo.pixelHeight,
    colorSpace: photo.colorSpace,
    disposition: PhotoAnalysisDisposition.safeFallback,
    fallbackReason: AnalysisFallbackReason.analysisFailed,
  );

  LocalPhotoAnalysis _cancelledFallback(ProjectPhoto photo) =>
      LocalPhotoAnalysis(
        analysisVersion: 'cancelled-safe-v1',
        capabilityVersion: 'unavailable',
        contentSha256: photo.contentSha256,
        orientation: photo.orientation,
        pixelWidth: photo.pixelWidth,
        pixelHeight: photo.pixelHeight,
        colorSpace: photo.colorSpace,
        disposition: PhotoAnalysisDisposition.safeFallback,
        fallbackReason: AnalysisFallbackReason.cancelled,
      );
}
