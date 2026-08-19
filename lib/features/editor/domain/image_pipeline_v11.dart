import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v10.dart';

@immutable
final class ImagePipelineV11 implements ImagePipeline {
  const ImagePipelineV11._({required this.recipe});

  factory ImagePipelineV11.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV11._(recipe: recipe);

  static const schemaVersion = 11;
  final EditRecipe recipe;

  @override
  Map<String, Object> toPlatformArguments() {
    final arguments = Map<String, Object>.of(
      ImagePipelineV10.fromRecipe(recipe).toPlatformArguments(),
    );
    arguments['schemaVersion'] = schemaVersion;
    arguments['targetedPortraitRecipeV1'] = recipe.targetedPortraitRecipe
        .toJson();
    return arguments;
  }
}
