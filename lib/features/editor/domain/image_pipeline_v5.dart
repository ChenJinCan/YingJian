import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v4.dart';

/// iOS contract for deterministic per-face slimming without exposing geometry.
@immutable
final class ImagePipelineV5 implements ImagePipeline {
  const ImagePipelineV5._({required this.recipe});

  factory ImagePipelineV5.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV5._(recipe: recipe);

  static const int schemaVersion = 5;

  final EditRecipe recipe;

  @override
  Map<String, Object> toPlatformArguments() {
    final arguments = Map<String, Object>.of(
      ImagePipelineV4.fromRecipe(recipe).toPlatformArguments(),
    );
    arguments['schemaVersion'] = schemaVersion;
    arguments['faceSlimRecipeV1'] = recipe.faceSlimRecipe.toJson();
    return arguments;
  }
}
