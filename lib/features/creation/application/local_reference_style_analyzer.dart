import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// The small, transferable visual signal extracted from a reference image.
///
/// This intentionally contains no pixels, objects, people, text, or image
/// path. It is sufficient to build a bounded local color, light, and texture
/// style while keeping the source image as the only image content in the
/// result.
@immutable
final class ReferenceStyleSignals {
  const ReferenceStyleSignals({
    required this.red,
    required this.green,
    required this.blue,
    required this.luminance,
    required this.saturation,
    required this.contrast,
    required this.edgeStrength,
  });

  final double red;
  final double green;
  final double blue;
  final double luminance;
  final double saturation;
  final double contrast;
  final double edgeStrength;

  double get softness => (1 - edgeStrength).clamp(0.0, 1.0).toDouble();
}

abstract interface class ReferenceStyleAnalyzer {
  Future<ReferenceStyleSignals> analyze(String localPath);
}

/// Decodes a tiny local thumbnail and derives aggregate color, light, and
/// texture signals.
///
/// This is deliberately on-device and bounded: the decoded image is capped at
/// 48 × 48 pixels and is disposed immediately after its aggregate signals are
/// calculated.
final class LocalReferenceStyleAnalyzer implements ReferenceStyleAnalyzer {
  const LocalReferenceStyleAnalyzer();

  static const _sampleEdge = 48;

  @override
  Future<ReferenceStyleSignals> analyze(String localPath) async {
    final bytes = await File(localPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _sampleEdge,
      targetHeight: _sampleEdge,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null || data.lengthInBytes < 4) {
          throw StateError('Reference image pixels are unavailable');
        }
        return _signalsFromRgba(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          width: frame.image.width,
          height: frame.image.height,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  @visibleForTesting
  static ReferenceStyleSignals signalsFromRgba(
    List<int> rgba, {
    int? width,
    int? height,
  }) => _signalsFromRgba(rgba, width: width, height: height);

  static ReferenceStyleSignals _signalsFromRgba(
    List<int> rgba, {
    int? width,
    int? height,
  }) {
    if (rgba.length < 4 || rgba.length % 4 != 0) {
      throw ArgumentError.value(rgba, 'rgba', 'Expected RGBA pixels');
    }
    if (rgba.any((channel) => channel < 0 || channel > 255)) {
      throw ArgumentError.value(
        rgba,
        'rgba',
        'RGBA channels must be integers from 0 to 255',
      );
    }
    final pixelCount = rgba.length ~/ 4;
    final resolvedWidth = width ?? pixelCount;
    final resolvedHeight = height ?? 1;
    if (resolvedWidth <= 0 ||
        resolvedHeight <= 0 ||
        resolvedWidth * resolvedHeight != pixelCount) {
      throw ArgumentError(
        'RGBA dimensions must contain exactly one value for every pixel',
      );
    }
    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;
    var luminance = 0.0;
    var luminanceSquared = 0.0;
    var weight = 0.0;
    var edgeDifference = 0.0;
    var edgeWeight = 0.0;
    var previousLuminance = 0.0;
    var previousAlpha = 0.0;
    final previousRowLuminance = List<double>.filled(resolvedWidth, 0);
    final previousRowAlpha = List<double>.filled(resolvedWidth, 0);
    for (var index = 0; index < rgba.length; index += 4) {
      final pixelIndex = index ~/ 4;
      final column = pixelIndex % resolvedWidth;
      if (column == 0) {
        previousLuminance = 0;
        previousAlpha = 0;
      }
      final alpha = rgba[index + 3] / 255;
      final pixelRed = rgba[index] / 255;
      final pixelGreen = rgba[index + 1] / 255;
      final pixelBlue = rgba[index + 2] / 255;
      final pixelLuminance =
          0.2126 * pixelRed + 0.7152 * pixelGreen + 0.0722 * pixelBlue;
      if (alpha > 0) {
        red += pixelRed * alpha;
        green += pixelGreen * alpha;
        blue += pixelBlue * alpha;
        luminance += pixelLuminance * alpha;
        luminanceSquared += pixelLuminance * pixelLuminance * alpha;
        weight += alpha;
        if (previousAlpha > 0) {
          final pairWeight = math.min(alpha, previousAlpha);
          edgeDifference +=
              (pixelLuminance - previousLuminance).abs() * pairWeight;
          edgeWeight += pairWeight;
        }
        final aboveAlpha = previousRowAlpha[column];
        if (aboveAlpha > 0) {
          final pairWeight = math.min(alpha, aboveAlpha);
          edgeDifference +=
              (pixelLuminance - previousRowLuminance[column]).abs() *
              pairWeight;
          edgeWeight += pairWeight;
        }
      }
      previousLuminance = pixelLuminance;
      previousAlpha = alpha;
      previousRowLuminance[column] = pixelLuminance;
      previousRowAlpha[column] = alpha;
    }
    if (weight == 0) {
      throw StateError('Reference image has no visible pixels');
    }
    red /= weight;
    green /= weight;
    blue /= weight;
    luminance /= weight;
    luminanceSquared /= weight;
    final maximum = [red, green, blue].reduce((a, b) => a > b ? a : b);
    final minimum = [red, green, blue].reduce((a, b) => a < b ? a : b);
    final saturation = maximum == 0 ? 0.0 : (maximum - minimum) / maximum;
    final variance = math.max(0.0, luminanceSquared - luminance * luminance);
    return ReferenceStyleSignals(
      red: red,
      green: green,
      blue: blue,
      luminance: luminance.clamp(0.0, 1.0).toDouble(),
      saturation: saturation.clamp(0.0, 1.0).toDouble(),
      contrast: (math.sqrt(variance) * 2).clamp(0.0, 1.0).toDouble(),
      edgeStrength: edgeWeight == 0
          ? 0
          : (edgeDifference / edgeWeight).clamp(0.0, 1.0).toDouble(),
    );
  }
}
