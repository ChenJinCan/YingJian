import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';

/// Versioned single-photo contract. V1 remains unchanged for migrated projects.
@immutable
final class ImagePipelineV2 implements ImagePipeline {
  const ImagePipelineV2._({required this.recipe});

  factory ImagePipelineV2.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV2._(recipe: recipe);

  static const int schemaVersion = 2;
  static const String workingColorSpace = 'srgb';

  final EditRecipe recipe;

  double get exposureEv => recipe.exposure * 2;

  @override
  Map<String, Object> toPlatformArguments() => <String, Object>{
    'schemaVersion': schemaVersion,
    'workingColorSpace': workingColorSpace,
    'adjustments': <String, double>{
      'exposureEv': exposureEv,
      'highlights': recipe.highlights,
      'shadows': recipe.shadows,
      'contrast': recipe.contrast,
      'warmth': recipe.warmth,
      'tint': recipe.tint,
      'saturation': recipe.saturation,
      'clarity': recipe.clarity,
    },
    'geometry': <String, Object>{
      'normalizedCrop': <double>[
        recipe.crop.left,
        recipe.crop.top,
        recipe.crop.right,
        recipe.crop.bottom,
      ],
      'quarterTurns': recipe.crop.quarterTurns,
      'straightenDegrees': recipe.crop.straightenDegrees,
    },
    'portrait': <String, Object>{
      'recipeVersion': 1,
      'strength': recipe.portraitStrength,
    },
  };
}
