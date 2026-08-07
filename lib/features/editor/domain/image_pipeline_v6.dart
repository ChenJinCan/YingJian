import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v5.dart';

/// iOS contract for deterministic, local quality enhancement.
@immutable
final class ImagePipelineV6 implements ImagePipeline {
  const ImagePipelineV6._({required this.recipe});

  factory ImagePipelineV6.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV6._(recipe: recipe);

  static const int schemaVersion = 6;

  final EditRecipe recipe;

  @override
  Map<String, Object> toPlatformArguments() {
    final arguments = Map<String, Object>.of(
      ImagePipelineV5.fromRecipe(recipe).toPlatformArguments(),
    );
    arguments['schemaVersion'] = schemaVersion;
    arguments['qualityEnhancementRecipeV1'] = recipe.qualityEnhancementRecipe
        .toJson();
    return arguments;
  }
}
