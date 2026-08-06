import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v1.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v2.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v5.dart';

bool get supportsImagePipelineV2 =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

ImagePipeline imagePipelineForCurrentPlatform(EditRecipe recipe) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return ImagePipelineV5.fromRecipe(recipe);
  }
  return supportsImagePipelineV2
      ? ImagePipelineV2.fromRecipe(recipe)
      : ImagePipelineV1.fromRecipe(recipe);
}
