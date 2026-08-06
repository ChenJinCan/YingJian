import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';
import 'package:yingjian/features/recommendations/infrastructure/json_photo_analysis_cache.dart';

void main() {
  test(
    'persists only matching project analysis across cache instances',
    () async {
      final root = await Directory.systemTemp.createTemp('yingjian-analysis-');
      addTearDown(() => root.delete(recursive: true));
      const photo = ProjectPhoto(
        id: 'photo-1',
        localPath: '/private/project/photo.jpg',
        originalName: 'photo.jpg',
        contentSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        pixelWidth: 4032,
        pixelHeight: 3024,
        colorSpace: PhotoColorSpace.srgb,
        inputFormat: PhotoInputFormat.jpeg,
        supportState: PhotoSupportState.supported,
      );
      const identity = PhotoAnalysisEngineIdentity(
        analysisVersion: 'local-pixels-v1',
        capabilityVersion: 'ios-core-image-vision-v1',
      );
      const analysis = LocalPhotoAnalysis(
        analysisVersion: 'local-pixels-v1',
        capabilityVersion: 'ios-core-image-vision-v1',
        contentSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        orientation: 1,
        pixelWidth: 4032,
        pixelHeight: 3024,
        colorSpace: PhotoColorSpace.srgb,
        disposition: PhotoAnalysisDisposition.ready,
        fallbackReason: AnalysisFallbackReason.none,
        confidence: AnalysisConfidence.high,
        exposure: ExposureCondition.underexposed,
        whiteBalance: WhiteBalanceCondition.coolCast,
        clarity: ClarityCondition.clear,
        portrait: PortraitApplicability.applicable,
        portraitReason: PortraitDegradationReason.none,
        faceSlimTargetCount: 2,
        scene: SceneKind.people,
      );
      final writer = JsonPhotoAnalysisCache(directory: () async => root);
      final firstWrite = await writer.stage(
        projectId: 'project-1',
        photoId: photo.id,
        analysis: analysis,
      );
      expect(
        await writer.read(
          projectId: 'project-1',
          photo: photo,
          engineIdentity: identity,
        ),
        isNull,
      );
      await writer.commit(firstWrite, canCommit: () => true);

      final reader = JsonPhotoAnalysisCache(directory: () async => root);
      expect(
        await reader.read(
          projectId: 'project-1',
          photo: photo,
          engineIdentity: identity,
        ),
        analysis,
      );
      expect(
        await reader.read(
          projectId: 'project-1',
          photo: photo,
          engineIdentity: const PhotoAnalysisEngineIdentity(
            analysisVersion: 'local-pixels-v1',
            capabilityVersion: 'ios-core-image-vision-v2',
          ),
        ),
        isNull,
      );
      expect(
        await reader.read(
          projectId: 'another-project',
          photo: photo,
          engineIdentity: identity,
        ),
        isNull,
      );

      const replacement = LocalPhotoAnalysis(
        analysisVersion: 'local-pixels-v1',
        capabilityVersion: 'ios-core-image-vision-v1',
        contentSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        orientation: 1,
        pixelWidth: 4032,
        pixelHeight: 3024,
        colorSpace: PhotoColorSpace.srgb,
        disposition: PhotoAnalysisDisposition.ready,
        fallbackReason: AnalysisFallbackReason.none,
        confidence: AnalysisConfidence.medium,
        exposure: ExposureCondition.balanced,
        whiteBalance: WhiteBalanceCondition.balanced,
        clarity: ClarityCondition.clear,
        portrait: PortraitApplicability.unavailable,
        portraitReason: PortraitDegradationReason.capabilityUnavailable,
        scene: SceneKind.landscape,
      );
      final replacementWrite = await reader.stage(
        projectId: 'project-1',
        photoId: photo.id,
        analysis: replacement,
      );
      await reader.commit(replacementWrite, canCommit: () => true);
      await reader.discard(firstWrite);
      expect(
        await reader.read(
          projectId: 'project-1',
          photo: photo,
          engineIdentity: identity,
        ),
        replacement,
      );

      final concurrentWrites = await Future.wait([
        writer.stage(
          projectId: 'project-1',
          photoId: photo.id,
          analysis: analysis,
        ),
        reader.stage(
          projectId: 'project-1',
          photoId: photo.id,
          analysis: replacement,
        ),
      ]);
      await Future.wait(
        concurrentWrites.map(
          (write) => writer.commit(write, canCommit: () => true),
        ),
      );
      final persistedAfterConcurrentWrites = await reader.read(
        projectId: 'project-1',
        photo: photo,
        engineIdentity: identity,
      );
      expect(persistedAfterConcurrentWrites, anyOf(analysis, replacement));
      expect(
        await root
            .list(recursive: true)
            .where(
              (entry) => entry is Directory && entry.path.contains('/.write-'),
            )
            .toList(),
        isEmpty,
      );

      final cacheFiles = await root
          .list(recursive: true)
          .where((entry) => entry is File)
          .cast<File>()
          .toList();
      expect(cacheFiles, hasLength(1));
      final cacheText = await cacheFiles.single.readAsString();
      expect(cacheText, isNot(contains(photo.localPath)));
      expect(cacheText, isNot(contains(photo.originalName)));

      await reader.clearProject('project-1');
      expect(
        await reader.read(
          projectId: 'project-1',
          photo: photo,
          engineIdentity: identity,
        ),
        isNull,
      );
    },
  );

  test('reads legacy analysis without a portrait degradation reason', () {
    const analysis = LocalPhotoAnalysis(
      analysisVersion: 'metadata-safe-v1',
      capabilityVersion: 'metadata-only',
      contentSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      orientation: 1,
      pixelWidth: 100,
      pixelHeight: 100,
      colorSpace: PhotoColorSpace.srgb,
      disposition: PhotoAnalysisDisposition.safeFallback,
      fallbackReason: AnalysisFallbackReason.capabilityUnavailable,
    );
    final legacyJson = analysis.toJson()..remove('portraitReason');

    expect(
      LocalPhotoAnalysis.fromJson(legacyJson).portraitReason,
      PortraitDegradationReason.none,
    );
  });
}
