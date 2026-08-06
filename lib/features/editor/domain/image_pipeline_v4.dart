import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v3.dart';

/// Current iOS contract for the five explicit portrait parameters.
///
/// V4 deliberately removes the legacy composite portrait and reshape payloads.
/// Older schemas remain readable by their original adapters, but new renders
/// have exactly one portrait contract.
@immutable
final class ImagePipelineV4 implements ImagePipeline {
  const ImagePipelineV4._({required this.recipe});

  factory ImagePipelineV4.fromRecipe(EditRecipe recipe) =>
      ImagePipelineV4._(recipe: recipe);

  static const int schemaVersion = 4;

  final EditRecipe recipe;

  @override
  Map<String, Object> toPlatformArguments() {
    final arguments = Map<String, Object>.of(
      ImagePipelineV3.fromRecipe(recipe).toPlatformArguments(),
    );
    arguments['schemaVersion'] = schemaVersion;
    arguments.remove('portrait');
    arguments.remove('reshape');
    arguments['portraitRecipeV2'] = recipe.portraitRecipe.toJson();
    return arguments;
  }
}
