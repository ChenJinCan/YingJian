import 'package:flutter/foundation.dart';

@immutable
final class QualityEnhancementRecipe {
  factory QualityEnhancementRecipe({
    int noiseReduction = 0,
    int lowLightRecovery = 0,
    int hazeRemoval = 0,
    int detailSharpening = 0,
  }) {
    for (final entry in <String, int>{
      'noiseReduction': noiseReduction,
      'lowLightRecovery': lowLightRecovery,
      'hazeRemoval': hazeRemoval,
      'detailSharpening': detailSharpening,
    }.entries) {
      if (entry.value < 0 || entry.value > 100) {
        throw RangeError.range(entry.value, 0, 100, entry.key);
      }
    }
    return QualityEnhancementRecipe._(
      noiseReduction: noiseReduction,
      lowLightRecovery: lowLightRecovery,
      hazeRemoval: hazeRemoval,
      detailSharpening: detailSharpening,
    );
  }

  const QualityEnhancementRecipe._({
    required this.noiseReduction,
    required this.lowLightRecovery,
    required this.hazeRemoval,
    required this.detailSharpening,
  });

  static const neutral = QualityEnhancementRecipe._(
    noiseReduction: 0,
    lowLightRecovery: 0,
    hazeRemoval: 0,
    detailSharpening: 0,
  );

  static const safeAutomatic = QualityEnhancementRecipe._(
    noiseReduction: 28,
    lowLightRecovery: 32,
    hazeRemoval: 18,
    detailSharpening: 16,
  );

  static const recipeVersion = 1;

  final int noiseReduction;
  final int lowLightRecovery;
  final int hazeRemoval;
  final int detailSharpening;

  bool get isNeutral =>
      noiseReduction == 0 &&
      lowLightRecovery == 0 &&
      hazeRemoval == 0 &&
      detailSharpening == 0;

  Map<String, Object> toJson() => <String, Object>{
    'recipeVersion': recipeVersion,
    'noiseReduction': noiseReduction,
    'lowLightRecovery': lowLightRecovery,
    'hazeRemoval': hazeRemoval,
    'detailSharpening': detailSharpening,
  };

  factory QualityEnhancementRecipe.fromJson(Map<String, Object?> json) {
    if (json['recipeVersion'] != recipeVersion) {
      throw const FormatException('Unsupported quality enhancement recipe');
    }
    int read(String key) {
      final value = json[key];
      if (value is! int) {
        throw FormatException('Invalid $key');
      }
      return value;
    }

    return QualityEnhancementRecipe(
      noiseReduction: read('noiseReduction'),
      lowLightRecovery: read('lowLightRecovery'),
      hazeRemoval: read('hazeRemoval'),
      detailSharpening: read('detailSharpening'),
    );
  }

  QualityEnhancementRecipe copyWith({
    int? noiseReduction,
    int? lowLightRecovery,
    int? hazeRemoval,
    int? detailSharpening,
  }) => QualityEnhancementRecipe(
    noiseReduction: noiseReduction ?? this.noiseReduction,
    lowLightRecovery: lowLightRecovery ?? this.lowLightRecovery,
    hazeRemoval: hazeRemoval ?? this.hazeRemoval,
    detailSharpening: detailSharpening ?? this.detailSharpening,
  );

  @override
  bool operator ==(Object other) =>
      other is QualityEnhancementRecipe &&
      other.noiseReduction == noiseReduction &&
      other.lowLightRecovery == lowLightRecovery &&
      other.hazeRemoval == hazeRemoval &&
      other.detailSharpening == detailSharpening;

  @override
  int get hashCode => Object.hash(
    noiseReduction,
    lowLightRecovery,
    hazeRemoval,
    detailSharpening,
  );
}
