import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v11.dart';

@immutable
final class ImagePipelineV12 implements ImagePipeline {
  const ImagePipelineV12._({required this.recipe});

  factory ImagePipelineV12.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV12._(recipe: recipe);

  static const schemaVersion = 12;
  final EditRecipe recipe;

  @override
  Map<String, Object> toPlatformArguments() {
    final arguments = Map<String, Object>.of(
      ImagePipelineV11.fromRecipe(recipe).toPlatformArguments(),
    );
    arguments['schemaVersion'] = schemaVersion;
    arguments['directionalLightingRecipeV1'] = recipe.directionalLightingRecipe
        .toJson();
    return arguments;
  }
}
