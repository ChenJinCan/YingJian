import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v8.dart';

@immutable
final class ImagePipelineV9 implements ImagePipeline {
  const ImagePipelineV9._({required this.recipe});

  factory ImagePipelineV9.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV9._(recipe: recipe);

  static const schemaVersion = 9;
  final EditRecipe recipe;

  @override
  Map<String, Object> toPlatformArguments() {
    final arguments = Map<String, Object>.of(
      ImagePipelineV8.fromRecipe(recipe).toPlatformArguments(),
    );
    arguments['schemaVersion'] = schemaVersion;
    arguments['semanticEditingRecipeV1'] = recipe.semanticEditingRecipe
        .toLegacyV1Json();
    return arguments;
  }
}
