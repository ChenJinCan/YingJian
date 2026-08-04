import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/application/local_recommendation_coordinator.dart';
import 'package:yingjian/features/recommendations/application/photo_analysis_cache.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';
import 'package:yingjian/features/recommendations/domain/recipe_catalog.dart';

import 'support/memory_photo_analysis_cache.dart';

void main() {
  const hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const photo = ProjectPhoto(
    id: 'photo-1',
    localPath: '/private/project/photo.jpg',
    originalName: 'photo.jpg',
    contentSha256: hash,
    pixelWidth: 4032,
    pixelHeight: 3024,
    colorSpace: PhotoColorSpace.srgb,
    inputFormat: PhotoInputFormat.jpeg,
    supportState: PhotoSupportState.supported,
  );

  test(
    'metadata analyzer returns an explicit deterministic local fallback',
    () async {
      const analyzer = MetadataSafePhotoAnalyzer();
      final first = await analyzer.analyze(photo);
      final second = await analyzer.analyze(photo);

      expect(first, second);
      expect(first.usesSafeFallback, isTrue);
      expect(
        first.fallbackReason,
        AnalysisFallbackReason.capabilityUnavailable,
      );
      expect(first.cacheIdentity, contains(hash));
      expect(first.cacheIdentity, isNot(contains(photo.localPath)));
    },
  );

  test('analysis cache identity binds content, orientation and capability', () {
    const first = LocalPhotoAnalysis(
      analysisVersion: 'analysis-v1',
      capabilityVersion: 'capability-v1',
      contentSha256: hash,
      orientation: 1,
      pixelWidth: 4032,
      pixelHeight: 3024,
      colorSpace: PhotoColorSpace.srgb,
      disposition: PhotoAnalysisDisposition.ready,
      fallbackReason: AnalysisFallbackReason.none,
    );
    const changed = LocalPhotoAnalysis(
      analysisVersion: 'analysis-v1',
      capabilityVersion: 'capability-v2',
      contentSha256: hash,
      orientation: 6,
      pixelWidth: 4032,
      pixelHeight: 3024,
      colorSpace: PhotoColorSpace.srgb,
      disposition: PhotoAnalysisDisposition.ready,
      fallbackReason: AnalysisFallbackReason.none,
    );

    expect(first.cacheIdentity, isNot(changed.cacheIdentity));
  });

  test(
    'catalog has twelve bounded recipes across the three product families',
    () {
      final entries = MvpRecipeCatalog.entries;
      expect(entries, hasLength(12));
      expect(entries.map((entry) => entry.id).toSet(), hasLength(12));
      expect(
        entries.map((entry) => entry.family).toSet(),
        containsAll(<SharedStyleFamily>{
          SharedStyleFamily.naturalClean,
          SharedStyleFamily.atmosphericColor,
          SharedStyleFamily.texturedStyle,
        }),
      );
      expect(entries.where((entry) => entry.safeForFallback), isNotEmpty);
      expect(
        () => LocalRecommendationEngine(catalog: entries.take(11).toList()),
        throwsArgumentError,
      );
    },
  );

  test('safe fallback always yields three distinct local intents', () async {
    final analysis = await const MetadataSafePhotoAnalyzer().analyze(photo);
    final recommendations = LocalRecommendationEngine().recommend(
      photos: const [photo],
      analyses: {'photo-1': analysis},
    );

    expect(recommendations, hasLength(3));
    expect(recommendations.map((item) => item.id).toSet(), hasLength(3));
    expect(recommendations.map((item) => item.family).toSet(), hasLength(3));
    expect(
      recommendations.every(
        (item) => item.catalogVersion == MvpRecipeCatalog.version,
      ),
      isTrue,
    );
    expect(
      recommendations.every((item) => item.sharedStyle.intensity == 0.72),
      isTrue,
    );
    expect(recommendations.map((item) => item.reason), [
      RecommendationReason.balancedLocalFallback,
      RecommendationReason.warmLocalFallback,
      RecommendationReason.texturedLocalFallback,
    ]);
    expect(
      recommendations.every(
        (item) =>
            item.adaptiveCompensations['photo-1']!.source ==
            AdaptiveCompensationSource.safeFallbackV1,
      ),
      isTrue,
    );
  });

  test(
    'ready analysis selects families deterministically and limits compensation',
    () {
      const analysis = LocalPhotoAnalysis(
        analysisVersion: 'native-v1',
        capabilityVersion: 'core-image-v1',
        contentSha256: hash,
        orientation: 1,
        pixelWidth: 4032,
        pixelHeight: 3024,
        colorSpace: PhotoColorSpace.srgb,
        disposition: PhotoAnalysisDisposition.ready,
        fallbackReason: AnalysisFallbackReason.none,
        confidence: AnalysisConfidence.high,
        exposure: ExposureCondition.underexposed,
        whiteBalance: WhiteBalanceCondition.warmCast,
        clarity: ClarityCondition.clear,
        scene: SceneKind.people,
      );
      final engine = LocalRecommendationEngine();
      final first = engine.recommend(
        photos: const [photo],
        analyses: const {'photo-1': analysis},
      );
      final second = engine.recommend(
        photos: const [photo],
        analyses: const {'photo-1': analysis},
      );

      expect(first.map((item) => item.id), second.map((item) => item.id));
      expect(first.map((item) => item.family).toSet(), hasLength(3));
      expect(first.map((item) => item.reason), [
        RecommendationReason.correctsExposure,
        RecommendationReason.correctsWhiteBalance,
        RecommendationReason.protectsTexture,
      ]);
      expect(
        first.first.adaptiveCompensations['photo-1']!.recipe.exposure,
        0.15,
      );
      expect(
        first.first.adaptiveCompensations['photo-1']!.recipe.warmth,
        -0.08,
      );
    },
  );

  test(
    'coordinator isolates a failed analysis and still returns three options',
    () async {
      final states = <PhotoAnalysisState>[];
      final result =
          await LocalRecommendationCoordinator(
            analyzer: _FailingAnalyzer(),
          ).prepare(
            projectId: 'project-1',
            photos: const [photo],
            onStateChanged: (_, state) async => states.add(state),
          );

      expect(states, [PhotoAnalysisState.running, PhotoAnalysisState.fallback]);
      expect(result.fallbackCount, 1);
      expect(
        result.analyses['photo-1']!.fallbackReason,
        AnalysisFallbackReason.analysisFailed,
      );
      expect(result.recommendations, hasLength(3));
    },
  );

  test(
    'coordinator reuses matching project analysis without rerunning',
    () async {
      final analyzer = _CountingAnalyzer();
      final cache = MemoryPhotoAnalysisCache();
      final coordinator = LocalRecommendationCoordinator(
        analyzer: analyzer,
        cache: cache,
      );

      final first = await coordinator.prepare(
        projectId: 'project-1',
        photos: const [photo],
      );
      final second = await coordinator.prepare(
        projectId: 'project-1',
        photos: const [photo],
      );

      expect(analyzer.calls, 1);
      expect(second.analyses, first.analyses);
      expect(
        second.recommendations.map((item) => item.id),
        first.recommendations.map((item) => item.id),
      );
    },
  );

  test(
    'analysis cache misses after capability or input identity changes',
    () async {
      final cache = MemoryPhotoAnalysisCache();
      final firstAnalyzer = _CountingAnalyzer();
      await LocalRecommendationCoordinator(
        analyzer: firstAnalyzer,
        cache: cache,
      ).prepare(projectId: 'project-1', photos: const [photo]);

      final upgradedAnalyzer = _CountingAnalyzer(
        capabilityVersion: 'fixture-v2',
      );
      await LocalRecommendationCoordinator(
        analyzer: upgradedAnalyzer,
        cache: cache,
      ).prepare(projectId: 'project-1', photos: const [photo]);
      final changedPhoto = ProjectPhoto(
        id: photo.id,
        localPath: photo.localPath,
        originalName: photo.originalName,
        contentSha256:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        pixelWidth: photo.pixelWidth,
        pixelHeight: photo.pixelHeight,
        colorSpace: photo.colorSpace,
        inputFormat: photo.inputFormat,
        supportState: photo.supportState,
      );
      await LocalRecommendationCoordinator(
        analyzer: upgradedAnalyzer,
        cache: cache,
      ).prepare(projectId: 'project-1', photos: [changedPhoto]);

      expect(firstAnalyzer.calls, 1);
      expect(upgradedAnalyzer.calls, 2);
    },
  );

  test(
    'cancelled analysis discards the late result and is not cached',
    () async {
      final analyzer = _DeferredAnalyzer();
      final cache = MemoryPhotoAnalysisCache();
      final cancellation = PhotoAnalysisCancellationToken();
      final states = <PhotoAnalysisState>[];
      final preparing =
          LocalRecommendationCoordinator(
            analyzer: analyzer,
            cache: cache,
          ).prepare(
            projectId: 'project-1',
            photos: const [photo],
            cancellation: cancellation,
            onStateChanged: (_, state) async => states.add(state),
          );
      await analyzer.started.future;

      cancellation.cancel();
      analyzer.complete();
      final result = await preparing;

      expect(states, [PhotoAnalysisState.running, PhotoAnalysisState.fallback]);
      expect(
        result.analyses[photo.id]?.fallbackReason,
        AnalysisFallbackReason.cancelled,
      );
      expect(result.recommendations, hasLength(3));
      expect(
        await cache.read(
          projectId: 'project-1',
          photo: photo,
          engineIdentity: analyzer.identityFor(photo),
        ),
        isNull,
      );
    },
  );

  test(
    'coordinator rejects analysis from an unexpected engine version',
    () async {
      final result = await LocalRecommendationCoordinator(
        analyzer: _WrongVersionAnalyzer(),
        cache: MemoryPhotoAnalysisCache(),
      ).prepare(projectId: 'project-1', photos: const [photo]);

      expect(
        result.analyses[photo.id]?.fallbackReason,
        AnalysisFallbackReason.analysisFailed,
      );
    },
  );

  test('cancellation during cache write rolls back only that write', () async {
    final cache = _DeferredWriteCache();
    final cancellation = PhotoAnalysisCancellationToken();
    final states = <PhotoAnalysisState>[];
    final preparing =
        LocalRecommendationCoordinator(
          analyzer: _CountingAnalyzer(),
          cache: cache,
        ).prepare(
          projectId: 'project-1',
          photos: const [photo],
          cancellation: cancellation,
          onStateChanged: (_, state) async => states.add(state),
        );
    await cache.started.future;

    cancellation.cancel();
    cache.complete();
    final result = await preparing;

    expect(states, [PhotoAnalysisState.running, PhotoAnalysisState.fallback]);
    expect(
      result.analyses[photo.id]?.fallbackReason,
      AnalysisFallbackReason.cancelled,
    );
    expect(cache.current, isNull);
  });

  test('cancellation during cache commit rejects the staged result', () async {
    final cache = _DeferredCommitCache();
    final cancellation = PhotoAnalysisCancellationToken();
    final preparing =
        LocalRecommendationCoordinator(
          analyzer: _CountingAnalyzer(),
          cache: cache,
        ).prepare(
          projectId: 'project-1',
          photos: const [photo],
          cancellation: cancellation,
        );
    await cache.commitStarted.future;

    cancellation.cancel();
    cache.completeCommitCheck();
    final result = await preparing;

    expect(
      result.analyses[photo.id]?.fallbackReason,
      AnalysisFallbackReason.cancelled,
    );
    expect(cache.current, isNull);
    expect(cache.staged, isNull);
  });

  test('recommendation engine rejects stale content analysis', () async {
    final analysis = await const MetadataSafePhotoAnalyzer().analyze(photo);
    final stalePhoto = ProjectPhoto(
      id: photo.id,
      localPath: photo.localPath,
      originalName: photo.originalName,
      contentSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      pixelWidth: photo.pixelWidth,
      pixelHeight: photo.pixelHeight,
      colorSpace: photo.colorSpace,
      inputFormat: photo.inputFormat,
      supportState: photo.supportState,
    );

    expect(
      () => LocalRecommendationEngine().recommend(
        photos: [stalePhoto],
        analyses: {'photo-1': analysis},
      ),
      throwsArgumentError,
    );
  });
}

final class _FailingAnalyzer implements PhotoAnalyzer {
  @override
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) =>
      const PhotoAnalysisEngineIdentity(
        analysisVersion: 'failing-v1',
        capabilityVersion: 'fixture-v1',
      );

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) {
    throw StateError('fixture failure must not escape');
  }
}

final class _CountingAnalyzer implements PhotoAnalyzer {
  _CountingAnalyzer({this.capabilityVersion = 'fixture-v1'});

  final String capabilityVersion;
  int calls = 0;

  @override
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) =>
      PhotoAnalysisEngineIdentity(
        analysisVersion: 'counting-v1',
        capabilityVersion: capabilityVersion,
      );

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) async {
    calls += 1;
    return LocalPhotoAnalysis(
      analysisVersion: 'counting-v1',
      capabilityVersion: capabilityVersion,
      contentSha256: photo.contentSha256,
      orientation: photo.orientation,
      pixelWidth: photo.pixelWidth,
      pixelHeight: photo.pixelHeight,
      colorSpace: photo.colorSpace,
      disposition: PhotoAnalysisDisposition.ready,
      fallbackReason: AnalysisFallbackReason.none,
    );
  }
}

final class _DeferredAnalyzer implements PhotoAnalyzer {
  final Completer<void> started = Completer<void>();
  final Completer<void> _release = Completer<void>();

  void complete() => _release.complete();

  @override
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) =>
      const PhotoAnalysisEngineIdentity(
        analysisVersion: 'deferred-v1',
        capabilityVersion: 'fixture-v1',
      );

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) async {
    started.complete();
    await _release.future;
    return LocalPhotoAnalysis(
      analysisVersion: 'deferred-v1',
      capabilityVersion: 'fixture-v1',
      contentSha256: photo.contentSha256,
      orientation: photo.orientation,
      pixelWidth: photo.pixelWidth,
      pixelHeight: photo.pixelHeight,
      colorSpace: photo.colorSpace,
      disposition: PhotoAnalysisDisposition.ready,
      fallbackReason: AnalysisFallbackReason.none,
    );
  }
}

final class _WrongVersionAnalyzer implements PhotoAnalyzer {
  @override
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) =>
      const PhotoAnalysisEngineIdentity(
        analysisVersion: 'expected-v1',
        capabilityVersion: 'fixture-v1',
      );

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) async =>
      LocalPhotoAnalysis(
        analysisVersion: 'unexpected-v0',
        capabilityVersion: 'fixture-v1',
        contentSha256: photo.contentSha256,
        orientation: photo.orientation,
        pixelWidth: photo.pixelWidth,
        pixelHeight: photo.pixelHeight,
        colorSpace: photo.colorSpace,
        disposition: PhotoAnalysisDisposition.ready,
        fallbackReason: AnalysisFallbackReason.none,
      );
}

final class _DeferredWriteCache implements PhotoAnalysisCache {
  final Completer<void> started = Completer<void>();
  final Completer<void> _release = Completer<void>();
  PhotoAnalysisCacheWrite? current;
  PhotoAnalysisCacheWrite? staged;

  void complete() => _release.complete();

  @override
  Future<LocalPhotoAnalysis?> read({
    required String projectId,
    required ProjectPhoto photo,
    required PhotoAnalysisEngineIdentity engineIdentity,
  }) async => null;

  @override
  Future<PhotoAnalysisCacheWrite> stage({
    required String projectId,
    required String photoId,
    required LocalPhotoAnalysis analysis,
  }) async {
    started.complete();
    await _release.future;
    return staged = PhotoAnalysisCacheWrite(
      projectId: projectId,
      photoId: photoId,
      token: 'deferred-write',
      analysis: analysis,
    );
  }

  @override
  Future<bool> commit(
    PhotoAnalysisCacheWrite write, {
    required bool Function() canCommit,
  }) async {
    if (identical(staged, write) && canCommit()) {
      staged = null;
      current = write;
      return true;
    }
    staged = null;
    return false;
  }

  @override
  Future<void> discard(PhotoAnalysisCacheWrite write) async {
    if (identical(staged, write)) staged = null;
  }

  @override
  Future<void> clearPhoto({
    required String projectId,
    required String photoId,
  }) async {
    current = null;
  }

  @override
  Future<void> clearProject(String projectId) async {
    current = null;
  }
}

final class _DeferredCommitCache implements PhotoAnalysisCache {
  final Completer<void> commitStarted = Completer<void>();
  final Completer<void> _releaseCommitCheck = Completer<void>();
  PhotoAnalysisCacheWrite? staged;
  PhotoAnalysisCacheWrite? current;

  void completeCommitCheck() => _releaseCommitCheck.complete();

  @override
  Future<LocalPhotoAnalysis?> read({
    required String projectId,
    required ProjectPhoto photo,
    required PhotoAnalysisEngineIdentity engineIdentity,
  }) async => null;

  @override
  Future<PhotoAnalysisCacheWrite> stage({
    required String projectId,
    required String photoId,
    required LocalPhotoAnalysis analysis,
  }) async => staged = PhotoAnalysisCacheWrite(
    projectId: projectId,
    photoId: photoId,
    token: 'deferred-commit',
    analysis: analysis,
  );

  @override
  Future<bool> commit(
    PhotoAnalysisCacheWrite write, {
    required bool Function() canCommit,
  }) async {
    commitStarted.complete();
    await _releaseCommitCheck.future;
    if (!identical(staged, write) || !canCommit()) {
      staged = null;
      return false;
    }
    staged = null;
    current = write;
    return true;
  }

  @override
  Future<void> discard(PhotoAnalysisCacheWrite write) async {
    if (identical(staged, write)) staged = null;
  }

  @override
  Future<void> clearPhoto({
    required String projectId,
    required String photoId,
  }) async {
    staged = null;
    current = null;
  }

  @override
  Future<void> clearProject(String projectId) async {
    staged = null;
    current = null;
  }
}
