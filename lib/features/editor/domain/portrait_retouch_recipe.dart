import 'package:flutter/foundation.dart';

/// Versioned user-facing portrait values. These are semantic percentages,
/// never hidden engine strengths.
@immutable
final class PortraitRetouchRecipe {
  factory PortraitRetouchRecipe({
    int textureSmoothing = 0,
    int skinToneLighting = 0,
    int blemishReduction = 0,
    int faceSlimming = 0,
    int torsoSlimming = 0,
  }) {
    for (final entry in <String, int>{
      'textureSmoothing': textureSmoothing,
      'skinToneLighting': skinToneLighting,
      'blemishReduction': blemishReduction,
      'faceSlimming': faceSlimming,
      'torsoSlimming': torsoSlimming,
    }.entries) {
      if (entry.value < 0 || entry.value > 100) {
        throw RangeError.range(entry.value, 0, 100, entry.key);
      }
    }
    return PortraitRetouchRecipe._(
      textureSmoothing: textureSmoothing,
      skinToneLighting: skinToneLighting,
      blemishReduction: blemishReduction,
      faceSlimming: faceSlimming,
      torsoSlimming: torsoSlimming,
    );
  }

  const PortraitRetouchRecipe._({
    required this.textureSmoothing,
    required this.skinToneLighting,
    required this.blemishReduction,
    required this.faceSlimming,
    required this.torsoSlimming,
  });

  static const int recipeVersion = 2;
  static const String analysisVersion = 'vision-multiface-v1';
  static const String effectVersion = 'portrait-core-contract-v2';
  static const String naturalBeautificationProfileVersion =
      'natural-beautification-profile-v2';

  static final neutral = PortraitRetouchRecipe();
  static const naturalBeautificationRecommended = PortraitRetouchRecipe._(
    textureSmoothing: 50,
    skinToneLighting: 50,
    blemishReduction: 20,
    faceSlimming: 0,
    torsoSlimming: 0,
  );

  final int textureSmoothing;
  final int skinToneLighting;
  final int blemishReduction;
  final int faceSlimming;
  final int torsoSlimming;

  bool get isNeutral =>
      textureSmoothing == 0 &&
      skinToneLighting == 0 &&
      blemishReduction == 0 &&
      faceSlimming == 0 &&
      torsoSlimming == 0;

  factory PortraitRetouchRecipe.migrateLegacy({
    required double portraitStrength,
    required double faceSlimStrength,
    required double bodySlimStrength,
  }) => PortraitRetouchRecipe(
    textureSmoothing: (portraitStrength * 100).round(),
    skinToneLighting: (portraitStrength * 100).round(),
    blemishReduction: 0,
    faceSlimming: (faceSlimStrength * 100).round(),
    torsoSlimming: (bodySlimStrength * 100).round(),
  );

  Map<String, Object> toJson() => <String, Object>{
    'recipeVersion': recipeVersion,
    'analysisVersion': analysisVersion,
    'effectVersion': effectVersion,
    'textureSmoothing': textureSmoothing,
    'skinToneLighting': skinToneLighting,
    'blemishReduction': blemishReduction,
    'faceSlimming': faceSlimming,
    'torsoSlimming': torsoSlimming,
  };

  factory PortraitRetouchRecipe.fromJson(Map<String, Object?> json) {
    const knownFields = <String>{
      'recipeVersion',
      'analysisVersion',
      'effectVersion',
      'textureSmoothing',
      'skinToneLighting',
      'blemishReduction',
      'faceSlimming',
      'torsoSlimming',
    };
    if (json.keys.toSet().difference(knownFields).isNotEmpty ||
        _exactInt(json['recipeVersion']) != recipeVersion ||
        json['analysisVersion'] != analysisVersion ||
        json['effectVersion'] != effectVersion) {
      throw const FormatException('Unknown portrait recipe identity');
    }
    final values = <String, int?>{
      'textureSmoothing': _exactInt(json['textureSmoothing']),
      'skinToneLighting': _exactInt(json['skinToneLighting']),
      'blemishReduction': _exactInt(json['blemishReduction']),
      'faceSlimming': _exactInt(json['faceSlimming']),
      'torsoSlimming': _exactInt(json['torsoSlimming']),
    };
    if (values.values.any(
      (value) => value == null || value < 0 || value > 100,
    )) {
      throw const FormatException('Invalid portrait recipe value');
    }
    return PortraitRetouchRecipe(
      textureSmoothing: values['textureSmoothing']!,
      skinToneLighting: values['skinToneLighting']!,
      blemishReduction: values['blemishReduction']!,
      faceSlimming: values['faceSlimming']!,
      torsoSlimming: values['torsoSlimming']!,
    );
  }

  PortraitRetouchRecipe copyWith({
    int? textureSmoothing,
    int? skinToneLighting,
    int? blemishReduction,
    int? faceSlimming,
    int? torsoSlimming,
  }) => PortraitRetouchRecipe(
    textureSmoothing: textureSmoothing ?? this.textureSmoothing,
    skinToneLighting: skinToneLighting ?? this.skinToneLighting,
    blemishReduction: blemishReduction ?? this.blemishReduction,
    faceSlimming: faceSlimming ?? this.faceSlimming,
    torsoSlimming: torsoSlimming ?? this.torsoSlimming,
  );

  static int? _exactInt(Object? value) {
    if (value is! num || !value.isFinite || value.truncateToDouble() != value) {
      return null;
    }
    return value.toInt();
  }

  @override
  bool operator ==(Object other) =>
      other is PortraitRetouchRecipe &&
      other.textureSmoothing == textureSmoothing &&
      other.skinToneLighting == skinToneLighting &&
      other.blemishReduction == blemishReduction &&
      other.faceSlimming == faceSlimming &&
      other.torsoSlimming == torsoSlimming;

  @override
  int get hashCode => Object.hash(
    textureSmoothing,
    skinToneLighting,
    blemishReduction,
    faceSlimming,
    torsoSlimming,
  );
}
