import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

abstract interface class PhotoExporter {
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  });
}

class ExportedPhoto {
  const ExportedPhoto({
    required this.assetId,
    required this.width,
    required this.height,
    this.sharePath,
  });

  final String assetId;
  final int width;
  final int height;
  final String? sharePath;
}
