import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yingjian/features/project/infrastructure/app_owned_photo_importer.dart';

final class ImagePickerPhotoSource implements PhotoSource {
  ImagePickerPhotoSource({ImagePicker? picker, TargetPlatform? platform})
    : _picker = picker ?? ImagePicker(),
      _platform = platform ?? defaultTargetPlatform;

  final ImagePicker _picker;
  final TargetPlatform _platform;

  @override
  Future<List<SelectedPhoto>> pickPhotos({required int limit}) async {
    if (_platform == TargetPlatform.android) {
      final lost = await _picker.retrieveLostData();
      final recovered = lost.files ?? const <XFile>[];
      if (recovered.isNotEmpty) {
        return recovered
            .take(limit)
            .map((file) => SelectedPhoto(path: file.path, name: file.name))
            .toList();
      }
    }

    final selected = await _picker.pickMultiImage(
      limit: limit,
      requestFullMetadata: true,
    );
    return selected
        .map((file) => SelectedPhoto(path: file.path, name: file.name))
        .toList();
  }
}
