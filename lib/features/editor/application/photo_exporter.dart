import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

abstract interface class PhotoExporter {
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  });
}

abstract interface class PhotoLibraryPermissionAwareExporter {}

abstract interface class PhotoLibrarySettingsOpener {
  Future<void> openPhotoLibrarySettings();
}

enum PhotoExportStage { preparing, savingToPhotoLibrary }

abstract interface class PhotoExportStageAware {
  ValueListenable<PhotoExportStage> get stage;
}

abstract interface class PhotoResultPreparer {
  PhotoPreparation prepareCanonical({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required EditState editState,
    required EditContext editContext,
    required PhotoExportOptions options,
  });
}

abstract interface class PhotoPreparation {
  String get requestId;
  Future<PreparedPhoto> get result;
  Future<void> cancel();
}

@immutable
final class PreparedPhoto {
  const PreparedPhoto({
    required this.requestId,
    required this.localPath,
    required this.width,
    required this.height,
  });

  final String requestId;
  final String localPath;
  final int width;
  final int height;
}

final class PhotoPreparationCanceled implements Exception {
  const PhotoPreparationCanceled();
}

abstract interface class ConfigurablePhotoExporter implements PhotoExporter {
  Future<ExportedPhoto> exportWithOptions({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required PhotoExportOptions options,
  });
}

abstract interface class CanonicalPhotoExporter
    implements ConfigurablePhotoExporter {
  Future<ExportedPhoto> exportCanonical({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required EditState editState,
    required EditContext editContext,
    required PhotoExportOptions options,
  });
}

enum PhotoExportFormat { jpeg, heif }

enum PhotoExportSize { original, longEdge }

enum PhotoExportQuality { high, standard, compact }

@immutable
final class PhotoExportOptions {
  factory PhotoExportOptions({
    PhotoExportFormat format = PhotoExportFormat.jpeg,
    PhotoExportSize size = PhotoExportSize.original,
    int? longEdgePixels,
    PhotoExportQuality quality = PhotoExportQuality.high,
  }) {
    if (size == PhotoExportSize.longEdge &&
        (longEdgePixels == null ||
            longEdgePixels < 640 ||
            longEdgePixels > 16384)) {
      throw RangeError.value(
        longEdgePixels ?? -1,
        'longEdgePixels',
        'Must be between 640 and 16384 for long-edge export',
      );
    }
    return PhotoExportOptions._(
      format: format,
      size: size,
      longEdgePixels: size == PhotoExportSize.longEdge ? longEdgePixels : null,
      quality: quality,
    );
  }

  const PhotoExportOptions._({
    required this.format,
    required this.size,
    required this.longEdgePixels,
    required this.quality,
  });
  static const defaults = PhotoExportOptions._(
    format: PhotoExportFormat.jpeg,
    size: PhotoExportSize.original,
    longEdgePixels: null,
    quality: PhotoExportQuality.high,
  );

  final PhotoExportFormat format;
  final PhotoExportSize size;
  final int? longEdgePixels;
  final PhotoExportQuality quality;

  Map<String, Object> toPlatformArguments() {
    final result = <String, Object>{
      'format': format.name,
      'size': size.name,
      'quality': quality.name,
      'colorSpace': 'srgb',
    };
    final pixels = longEdgePixels;
    if (pixels != null) result['longEdgePixels'] = pixels;
    return result;
  }
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
