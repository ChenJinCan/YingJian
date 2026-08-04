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
        'sourceProxyPath': '/tmp/source.png',
        'candidateMaskPath': '/tmp/candidate.png',
        'protectionMaskPath': '/tmp/protection.png',
        'effectiveMaskPath': '/tmp/effective.png',
        'overlayPath': '/tmp/overlay.png',
        'offPath': '/tmp/off.png',
        'defaultPath': '/tmp/default.png',
        'highSafePath': '/tmp/high-safe.png',
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
      expect(result.offPath, endsWith('/off.png'));
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
