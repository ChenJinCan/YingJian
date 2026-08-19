import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/edit_target_detection_adapter.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';

void main() {
  test('maps analysis regions to typed stable-target detections', () {
    const photo = ProjectPhoto(
      id: 'photo-1',
      localPath: '/tmp/photo.jpg',
      originalName: 'photo.jpg',
    );
    final analysis = LocalPhotoAnalysis(
      analysisVersion: 'vision-v1',
      capabilityVersion: 'cap-v1',
      contentSha256: 'a' * 64,
      orientation: 1,
      pixelWidth: 1000,
      pixelHeight: 800,
      colorSpace: PhotoColorSpace.srgb,
      disposition: PhotoAnalysisDisposition.ready,
      fallbackReason: AnalysisFallbackReason.none,
      faceTargetRegions: const [
        NormalizedTargetRegion(left: 0.1, top: 0.2, right: 0.3, bottom: 0.5),
      ],
      bodyTargetRegions: const [
        NormalizedTargetRegion(left: 0.05, top: 0.15, right: 0.5, bottom: 0.95),
      ],
    );

    final detections = detectedEditTargetsFor(photo: photo, analysis: analysis);

    expect(detections.map((target) => target.kind), [
      EditTargetKind.face,
      EditTargetKind.body,
    ]);
    expect(detections.every((target) => target.photoId == photo.id), isTrue);
    expect(
      detections.every(
        (target) => target.analysisVersion == analysis.analysisVersion,
      ),
      isTrue,
    );
  });
}
