import 'package:flutter/services.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/domain/legacy_edit_recipe_adapter.dart';
import 'package:yingjian/features/editor/domain/render_plan.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

final class MethodChannelPhotoExporter implements CanonicalPhotoExporter {
  MethodChannelPhotoExporter({
    this.channel = const MethodChannel('yingjian/photo_export'),
  });

  final MethodChannel channel;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) => exportWithOptions(
    photo: photo,
    recipe: recipe,
    options: PhotoExportOptions.defaults,
  );

  @override
  Future<ExportedPhoto> exportWithOptions({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required PhotoExportOptions options,
  }) => exportCanonical(
    photo: photo,
    recipe: recipe,
    editState: const LegacyEditRecipeAdapter().read(recipe, photoId: photo.id),
    editContext: EditContext.ios,
    options: options,
  );

  @override
  Future<ExportedPhoto> exportCanonical({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required EditState editState,
    required EditContext editContext,
    required PhotoExportOptions options,
  }) async {
    final pipeline = imagePipelineForCurrentPlatform(
      recipe,
      sourceId: photo.id,
      editState: editState,
      context: editContext,
      outputRequirements: RenderOutputRequirements.export(
        format: options.format.name,
        quality: options.quality.name,
        maxEdge: options.size == PhotoExportSize.longEdge
            ? options.longEdgePixels
            : null,
      ),
    );
    final response = await channel
        .invokeMapMethod<String, Object?>('exportPhoto', <String, Object?>{
          'sourcePath': photo.localPath,
          'pipeline': pipeline.toPlatformArguments(),
          'options': options.toPlatformArguments(),
        });
    if (response == null) {
      throw const FormatException('Photo export returned no result');
    }
    final assetId = response['assetId'];
    final width = response['width'];
    final height = response['height'];
    final sharePath = response['sharePath'];
    if (assetId is! String || width is! int || height is! int) {
      throw const FormatException('Photo export returned an invalid result');
    }
    if (sharePath != null && sharePath is! String) {
      throw const FormatException(
        'Photo export returned an invalid share path',
      );
    }
    return ExportedPhoto(
      assetId: assetId,
      width: width,
      height: height,
      sharePath: sharePath as String?,
    );
  }
}
