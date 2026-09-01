import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/application/local_reference_style_analyzer.dart';

void main() {
  test('extracts bounded contrast from local luminance differences', () {
    final flat = LocalReferenceStyleAnalyzer.signalsFromRgba(
      const [
        128,
        128,
        128,
        255,
        128,
        128,
        128,
        255,
        128,
        128,
        128,
        255,
        128,
        128,
        128,
        255,
      ],
      width: 2,
      height: 2,
    );
    final checker = LocalReferenceStyleAnalyzer.signalsFromRgba(
      const [
        0,
        0,
        0,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        0,
        0,
        0,
        255,
      ],
      width: 2,
      height: 2,
    );

    expect(flat.contrast, closeTo(0, 0.001));
    expect(checker.contrast, closeTo(1, 0.001));
    expect(checker.contrast, inInclusiveRange(0, 1));
  });

  test('extracts bounded edge strength and softness from local neighbors', () {
    final flat = LocalReferenceStyleAnalyzer.signalsFromRgba(
      const [
        96,
        96,
        96,
        255,
        96,
        96,
        96,
        255,
        96,
        96,
        96,
        255,
        96,
        96,
        96,
        255,
      ],
      width: 2,
      height: 2,
    );
    final checker = LocalReferenceStyleAnalyzer.signalsFromRgba(
      const [
        0,
        0,
        0,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        0,
        0,
        0,
        255,
      ],
      width: 2,
      height: 2,
    );

    expect(flat.edgeStrength, closeTo(0, 0.001));
    expect(flat.softness, closeTo(1, 0.001));
    expect(checker.edgeStrength, closeTo(1, 0.001));
    expect(checker.softness, closeTo(0, 0.001));
    expect(checker.edgeStrength, inInclusiveRange(0, 1));
  });

  test('extracts bounded color, light, and saturation from visible pixels', () {
    final signals = LocalReferenceStyleAnalyzer.signalsFromRgba(const [
      255,
      64,
      32,
      255,
      255,
      64,
      32,
      255,
    ]);

    expect(signals.red, closeTo(1, 0.001));
    expect(signals.green, closeTo(64 / 255, 0.001));
    expect(signals.blue, closeTo(32 / 255, 0.001));
    expect(signals.luminance, inInclusiveRange(0, 1));
    expect(signals.saturation, greaterThan(0.5));
  });

  test('ignores fully transparent pixels', () {
    final signals = LocalReferenceStyleAnalyzer.signalsFromRgba(const [
      0,
      0,
      0,
      0,
      64,
      128,
      192,
      255,
    ]);

    expect(signals.red, closeTo(64 / 255, 0.001));
    expect(signals.green, closeTo(128 / 255, 0.001));
    expect(signals.blue, closeTo(192 / 255, 0.001));
  });

  test('rejects an invalid RGBA buffer', () {
    expect(
      () => LocalReferenceStyleAnalyzer.signalsFromRgba(const [1, 2, 3]),
      throwsArgumentError,
    );
    expect(
      () => LocalReferenceStyleAnalyzer.signalsFromRgba(const [256, 0, 0, 255]),
      throwsArgumentError,
    );
    expect(
      () => LocalReferenceStyleAnalyzer.signalsFromRgba(
        const [0, 0, 0, 255, 255, 255, 255, 255],
        width: 2,
        height: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => LocalReferenceStyleAnalyzer.signalsFromRgba(
        const [0, 0, 0, 0],
        width: 1,
        height: 1,
      ),
      throwsStateError,
    );
  });
}
