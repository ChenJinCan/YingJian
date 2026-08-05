import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v2.dart';

/// iOS-only extension that adds explicit, opt-in portrait geometry.
///
/// V2 remains the stable contract for adapters that do not implement reshape.
@immutable
final class ImagePipelineV3 implements ImagePipeline {
  const ImagePipelineV3._({required this.recipe});

  factory ImagePipelineV3.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV3._(recipe: recipe);

  static const int schemaVersion = 3;

  final EditRecipe recipe;

  @override
  Map<String, Object> toPlatformArguments() {
    final arguments = Map<String, Object>.of(
      ImagePipelineV2.fromRecipe(recipe).toPlatformArguments(),
    );
    arguments['schemaVersion'] = schemaVersion;
    arguments['reshape'] = <String, Object>{
      'recipeVersion': 1,
      'faceSlimStrength': recipe.faceSlimStrength,
      'bodySlimStrength': recipe.bodySlimStrength,
    };
    return arguments;
  }
}
