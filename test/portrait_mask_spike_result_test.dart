import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/presentation/portrait_spike/portrait_mask_spike_app.dart';

void main() {
  test(
    'keeps debug portrait candidates explicitly ineligible for production',
    () {
      final result = PortraitMaskSpikeResult.fromMap(<Object?, Object?>{
        'faceCount': 1,
        'width': 1200,
        'height': 800,
        'sourceWidth': 4032,
        'sourceHeight': 3024,
        'sourceProxyPath': '/tmp/source.png',
        'candidateMaskPath': '/tmp/candidate.png',
        'protectionMaskPath': '/tmp/protection.png',
        'effectiveMaskPath': '/tmp/effective.png',
        'overlayPath': '/tmp/overlay.png',
        'baselineOriginalPath': '/tmp/original.jpg',
        'offExportPath': '/tmp/off.jpg',
        'defaultExportPath': '/tmp/default.jpg',
        'highSafeExportPath': '/tmp/high-safe.jpg',
        'defaultPreviewPath': '/tmp/default-preview.png',
        'captureManifestPath': '/tmp/capture-manifest.json',
        'captureRelativePath': 'tmp/portrait-mask-spike/capture-001',
        'candidateKind': 'vision-landmarks-geometry-roi',
        'geometryOnly': true,
        'effectVersion': 'ios-geometry-retouch-spike-v1',
        'defaultStrength': 0.35,
        'highSafeStrength': 0.55,
        'productionEligible': false,
        'executionEnvironment': 'physical-device',
        'landmarkSummary': 'available',
        'landmarkBoundsSummary': 'available',
      });

      expect(result.productionEligible, isFalse);
      expect(result.offExportPath, endsWith('/off.jpg'));
      expect(result.sourceWidth, 4032);
      expect(
        result.captureRelativePath,
        startsWith('tmp/portrait-mask-spike/'),
      );
      expect(result.defaultStrength, 0.35);
      expect(result.highSafeStrength, 0.55);
    },
  );

  test('rejects a missing production eligibility marker', () {
    expect(
      () => PortraitMaskSpikeResult.fromMap(<Object?, Object?>{}),
      throwsFormatException,
    );
  });
}
