import 'package:yingjian/features/editor/domain/image_pipeline.dart';

abstract interface class PhotoPreviewRenderer {
  Future<PhotoPreviewHandle> create({
    required String sourcePath,
    required ImagePipeline pipeline,
    int maxEdge = 2048,
  });

  Future<void> update({
    required PhotoPreviewHandle handle,
    required ImagePipeline pipeline,
  });

  Future<void> dispose(PhotoPreviewHandle handle);
}

final class PhotoPreviewHandle {
  const PhotoPreviewHandle({
    required this.textureId,
    required this.width,
    required this.height,
    required this.backend,
  });

  final int textureId;
  final int width;
  final int height;
  final String backend;
}
