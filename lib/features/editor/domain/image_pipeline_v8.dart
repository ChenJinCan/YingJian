import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v7.dart';

@immutable
final class ImagePipelineV8 implements ImagePipeline {
  const ImagePipelineV8._({required this.recipe});

  factory ImagePipelineV8.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV8._(recipe: recipe);

  static const schemaVersion = 8;
  final EditRecipe recipe;

  @override
  Map<String, Object> toPlatformArguments() {
    final arguments = Map<String, Object>.of(
      ImagePipelineV7.fromRecipe(recipe).toPlatformArguments(),
    );
    arguments['schemaVersion'] = schemaVersion;
    arguments['portraitGeometryRecipeV1'] = recipe.portraitGeometryRecipe
        .toJson();
    return arguments;
  }
}
