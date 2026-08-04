import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yingjian/features/project/infrastructure/image_picker_photo_source.dart';

void main() {
  test(
    'iOS opens the picker without calling Android lost-data recovery',
    () async {
      final picker = _FakeImagePicker();
      final source = ImagePickerPhotoSource(
        picker: picker,
        platform: TargetPlatform.iOS,
      );

      final photos = await source.pickPhotos(limit: 9);

      expect(picker.retrieveLostDataCalled, isFalse);
      expect(picker.requestedLimit, 9);
      expect(photos.single.name, 'selected.jpg');
    },
  );
}

final class _FakeImagePicker extends ImagePicker {
  bool retrieveLostDataCalled = false;
  int? requestedLimit;

  @override
  Future<LostDataResponse> retrieveLostData() async {
    retrieveLostDataCalled = true;
    throw UnimplementedError('getLostData is Android-only');
  }

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    requestedLimit = limit;
    return [XFile('/tmp/selected.jpg', name: 'selected.jpg')];
  }
}
