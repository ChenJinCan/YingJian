import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/application/local_recommendation_coordinator.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';
import 'package:yingjian/features/recommendations/domain/recipe_catalog.dart';

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
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) {
    throw StateError('fixture failure must not escape');
  }
}
