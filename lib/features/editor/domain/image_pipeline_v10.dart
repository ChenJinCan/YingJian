import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v9.dart';

@immutable
final class ImagePipelineV10 implements ImagePipeline {
  const ImagePipelineV10._({required this.recipe});

  factory ImagePipelineV10.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV10._(recipe: recipe);

  static const schemaVersion = 10;
  final EditRecipe recipe;

  @override
  Map<String, Object> toPlatformArguments() {
    final arguments = Map<String, Object>.of(
      ImagePipelineV9.fromRecipe(recipe).toPlatformArguments(),
    );
    arguments['schemaVersion'] = schemaVersion;
    arguments.remove('semanticEditingRecipeV1');
    arguments['semanticEditingRecipeV2'] = recipe.semanticEditingRecipe
        .toJson();
    return arguments;
  }
}
