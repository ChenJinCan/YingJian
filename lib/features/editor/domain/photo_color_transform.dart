import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';

@immutable
class PhotoColorTransform {
  const PhotoColorTransform._({
    required this.redScale,
    required this.greenScale,
    required this.blueScale,
    required this.redBias,
    required this.greenBias,
    required this.blueBias,
  });

  factory PhotoColorTransform.fromRecipe(EditRecipe recipe) {
    final exposureScale = math.pow(2, recipe.exposure * 2).toDouble();
    final contrastScale = 1 + recipe.contrast * 0.75;
    final redWarmthScale = 1 + recipe.warmth * 0.15;
    final blueWarmthScale = 1 - recipe.warmth * 0.15;
    final contrastBias = 0.5 * (1 - contrastScale);

    return PhotoColorTransform._(
      redScale: exposureScale * contrastScale * redWarmthScale,
      greenScale: exposureScale * contrastScale,
      blueScale: exposureScale * contrastScale * blueWarmthScale,
      redBias: contrastBias * redWarmthScale,
      greenBias: contrastBias,
      blueBias: contrastBias * blueWarmthScale,
    );
  }

  final double redScale;
  final double greenScale;
  final double blueScale;
  final double redBias;
  final double greenBias;
  final double blueBias;

  List<double> get flutterMatrix => <double>[
    redScale,
    0,
    0,
    0,
    redBias * 255,
    0,
    greenScale,
    0,
    0,
    greenBias * 255,
    0,
    0,
    blueScale,
    0,
    blueBias * 255,
    0,
    0,
    0,
    1,
    0,
  ];

  Map<String, double> get platformArguments => <String, double>{
    'redScale': redScale,
    'greenScale': greenScale,
    'blueScale': blueScale,
    'redBias': redBias,
    'greenBias': greenBias,
    'blueBias': blueBias,
  };
}
