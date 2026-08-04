import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/project/infrastructure/app_owned_photo_importer.dart';

void main() {
  test(
    'copies selected photos into app-owned storage without changing source',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yingjian-photo-import-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final sourceFile = File('${directory.path}/camera photo.jpg');
      await sourceFile.writeAsBytes([1, 2, 3, 4]);
      final mediaDirectory = Directory('${directory.path}/app-media');
      final importer = AppOwnedPhotoImporter(
        source: _FakePhotoSource([
          SelectedPhoto(path: sourceFile.path, name: 'camera photo.jpg'),
        ]),
        mediaDirectory: () async => mediaDirectory,
        createId: () => 'photo-1',
      );

      final imported = await importer.importPhotos(limit: 9);

      expect(imported.single.id, 'photo-1');
      expect(imported.single.originalName, 'camera photo.jpg');
      expect(imported.single.localPath, isNot(sourceFile.path));
      expect(await File(imported.single.localPath).readAsBytes(), [1, 2, 3, 4]);
      expect(await sourceFile.readAsBytes(), [1, 2, 3, 4]);
    },
  );
}

final class _FakePhotoSource implements PhotoSource {
  _FakePhotoSource(this.photos);

  final List<SelectedPhoto> photos;

  @override
  Future<List<SelectedPhoto>> pickPhotos({required int limit}) async => photos;
}
