import 'package:flutter/services.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v1.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

final class MethodChannelPhotoExporter implements PhotoExporter {
  MethodChannelPhotoExporter({
    this.channel = const MethodChannel('yingjian/photo_export'),
  });

  final MethodChannel channel;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    final pipeline = ImagePipelineV1.fromRecipe(recipe);
    final response = await channel.invokeMapMethod<String, Object?>(
      'exportPhoto',
      <String, Object?>{
        'sourcePath': photo.localPath,
        'pipeline': pipeline.toPlatformArguments(),
      },
    );
    if (response == null) {
      throw const FormatException('Photo export returned no result');
    }
    final assetId = response['assetId'];
    final width = response['width'];
    final height = response['height'];
    if (assetId is! String || width is! int || height is! int) {
      throw const FormatException('Photo export returned an invalid result');
    }
    return ExportedPhoto(assetId: assetId, width: width, height: height);
  }
}
