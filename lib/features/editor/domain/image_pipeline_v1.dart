import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/photo_color_transform.dart';

/// Versioned, vendor-neutral pixel semantics shared by preview and export.
@immutable
final class ImagePipelineV1 implements ImagePipeline {
  const ImagePipelineV1._({required this.recipe});

  factory ImagePipelineV1.fromRecipe(EditRecipe recipe) {
    return ImagePipelineV1._(recipe: recipe);
  }

  static const int schemaVersion = 1;
  static const String workingColorSpace = 'srgb';

  final EditRecipe recipe;

  /// Exposure is expressed in stops. The editor's normalized range maps to
  /// -2...+2 EV so every adapter uses the same meaning.
  double get exposureEv => recipe.exposure * 2;

  @override
  Map<String, Object> toPlatformArguments() => <String, Object>{
    'schemaVersion': schemaVersion,
    'workingColorSpace': workingColorSpace,
    'adjustments': <String, double>{
      'exposureEv': exposureEv,
      'contrast': recipe.contrast,
      'warmth': recipe.warmth,
    },
  };

  /// Temporary compatibility transform for the Flutter fallback and the
  /// existing export adapters. It is not the pipeline's public transport.
  PhotoColorTransform get compatibilityTransform =>
      PhotoColorTransform.fromRecipe(recipe);
}
