import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v6.dart';

@immutable
final class ImagePipelineV7 implements ImagePipeline {
  const ImagePipelineV7._({required this.recipe});

  factory ImagePipelineV7.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV7._(recipe: recipe);

  static const schemaVersion = 7;
  final EditRecipe recipe;

  @override
  Map<String, Object> toPlatformArguments() {
    final arguments = Map<String, Object>.of(
      ImagePipelineV6.fromRecipe(recipe).toPlatformArguments(),
    );
    arguments['schemaVersion'] = schemaVersion;
    arguments['basicEditingRecipeV1'] = recipe.basicEditingRecipe.toJson();
    return arguments;
  }
}
