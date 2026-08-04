import 'package:flutter/services.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v1.dart';

final class MethodChannelPhotoPreviewRenderer implements PhotoPreviewRenderer {
  MethodChannelPhotoPreviewRenderer({
    this.channel = const MethodChannel('yingjian/photo_preview'),
  });

  final MethodChannel channel;

  @override
  Future<PhotoPreviewHandle> create({
    required String sourcePath,
    required ImagePipelineV1 pipeline,
    int maxEdge = 2048,
  }) async {
    if (maxEdge < 1 || maxEdge > 2048) {
      throw RangeError.range(maxEdge, 1, 2048, 'maxEdge');
    }
    final response = await channel
        .invokeMapMethod<String, Object?>('createPreview', <String, Object?>{
          'sourcePath': sourcePath,
          'maxEdge': maxEdge,
          'pipeline': pipeline.toPlatformArguments(),
        });
    if (response == null) {
      throw const FormatException('Photo preview returned no result');
    }
    final textureId = response['textureId'];
    final width = response['width'];
    final height = response['height'];
    final backend = response['backend'];
    if (textureId is! int ||
        textureId < 0 ||
        width is! int ||
        height is! int ||
        backend is! String ||
        width <= 0 ||
        height <= 0) {
      throw const FormatException('Photo preview returned an invalid result');
    }
    return PhotoPreviewHandle(
      textureId: textureId,
      width: width,
      height: height,
      backend: backend,
    );
  }

  @override
  Future<void> update({
    required PhotoPreviewHandle handle,
    required ImagePipelineV1 pipeline,
  }) {
    return channel.invokeMethod<void>('updatePreview', <String, Object?>{
      'textureId': handle.textureId,
      'pipeline': pipeline.toPlatformArguments(),
    });
  }

  @override
  Future<void> dispose(PhotoPreviewHandle handle) {
    return channel.invokeMethod<void>('disposePreview', <String, Object?>{
      'textureId': handle.textureId,
    });
  }
}
