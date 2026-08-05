import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
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
      await sourceFile.writeAsBytes(_jpeg(width: 4000, height: 3000));
      final mediaDirectory = Directory('${directory.path}/app-media');
      final importer = AppOwnedPhotoImporter(
        source: _FakePhotoSource([
          SelectedPhoto(path: sourceFile.path, name: 'camera photo.jpg'),
        ]),
        mediaDirectory: () async => mediaDirectory,
        inspectPhoto: _inspectJpeg,
        createId: () => 'photo-1',
      );

      final batch = await importer.importPhotos(limit: 6);

      expect(batch.failures, isEmpty);
      expect(batch.photos.single.id, 'photo-1');
      expect(batch.photos.single.originalName, 'camera photo.jpg');
      expect(batch.photos.single.localPath, isNot(sourceFile.path));
      expect(
        batch.photos.single.contentSha256,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(batch.photos.single.pixelWidth, 4000);
      expect(batch.photos.single.pixelHeight, 3000);
      expect(batch.photos.single.orientation, 1);
      expect(batch.photos.single.colorSpace, PhotoColorSpace.srgb);
      expect(batch.photos.single.inputFormat, PhotoInputFormat.jpeg);
      expect(batch.photos.single.supportState, PhotoSupportState.supported);
      expect(
        await File(batch.photos.single.localPath).readAsBytes(),
        _jpeg(width: 4000, height: 3000),
      );
      expect(await sourceFile.readAsBytes(), _jpeg(width: 4000, height: 3000));
    },
  );

  test(
    'releases temporary picker files after creating app-owned copies',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yingjian-photo-import-release-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final sourceFile = File('${directory.path}/picker/photo.jpg');
      await sourceFile.parent.create(recursive: true);
      await sourceFile.writeAsBytes(_jpeg(width: 1200, height: 900));
      final source = _ReleasablePhotoSource([
        SelectedPhoto(path: sourceFile.path, name: 'photo.jpg'),
      ]);
      final importer = AppOwnedPhotoImporter(
        source: source,
        mediaDirectory: () async => Directory('${directory.path}/app-media'),
        inspectPhoto: _inspectJpeg,
        createId: () => 'photo-release',
      );

      final batch = await importer.importPhotos(limit: 6);

      expect(batch.photos.single.localPath, isNot(sourceFile.path));
      expect(source.released, [sourceFile.path]);
    },
  );

  test('removes app-owned copies when picker cleanup fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-photo-import-release-failure-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final sourceFile = File('${directory.path}/picker/photo.jpg');
    await sourceFile.parent.create(recursive: true);
    await sourceFile.writeAsBytes(_jpeg(width: 1200, height: 900));
    final source = _ReleasablePhotoSource([
      SelectedPhoto(path: sourceFile.path, name: 'photo.jpg'),
    ], releaseError: FileSystemException('cleanup failed'));
    final importer = AppOwnedPhotoImporter(
      source: source,
      mediaDirectory: () async => Directory('${directory.path}/app-media'),
      inspectPhoto: _inspectJpeg,
      createId: () => 'photo-release-failure',
    );

    await expectLater(
      importer.importPhotos(limit: 6),
      throwsA(isA<FileSystemException>()),
    );

    expect(source.released, [sourceFile.path]);
    expect(
      File(
        '${directory.path}/app-media/photo-release-failure.jpg',
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'keeps valid photos when another selected item is unsupported',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yingjian-photo-partial-import-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final valid = File('${directory.path}/valid.jpg');
      final raw = File('${directory.path}/portrait.dng');
      await valid.writeAsBytes(_jpeg(width: 4032, height: 3024));
      await raw.writeAsBytes(const [0x49, 0x49, 0x2A, 0x00]);
      final importer = AppOwnedPhotoImporter(
        source: _FakePhotoSource([
          SelectedPhoto(path: valid.path, name: 'valid.jpg'),
          SelectedPhoto(path: raw.path, name: 'portrait.dng'),
        ]),
        mediaDirectory: () async => Directory('${directory.path}/app-media'),
        inspectPhoto: _inspectJpeg,
        createId: () => 'photo-valid',
      );

      final batch = await importer.importPhotos(limit: 6);

      expect(batch.photos.map((photo) => photo.originalName), ['valid.jpg']);
      expect(batch.failures, [
        const PhotoImportFailure(
          photoName: 'portrait.dng',
          reason: PhotoImportFailureReason.unsupportedFormat,
        ),
      ]);
    },
  );

  test('rejects an oversized JPEG before creating an app copy', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-photo-dimension-limit-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/oversized.jpg');
    await source.writeAsBytes(_jpeg(width: 12001, height: 100));
    final media = Directory('${directory.path}/app-media');
    final importer = AppOwnedPhotoImporter(
      source: _FakePhotoSource([
        SelectedPhoto(path: source.path, name: 'oversized.jpg'),
      ]),
      mediaDirectory: () async => media,
      inspectPhoto: _inspectJpeg,
      createId: () => 'must-not-be-copied',
    );

    final batch = await importer.importPhotos(limit: 6);

    expect(batch.photos, isEmpty);
    expect(
      batch.failures.single.reason,
      PhotoImportFailureReason.dimensionsTooLarge,
    );
    expect(File('${media.path}/must-not-be-copied.jpg').existsSync(), isFalse);
  });

  test('imports a non-animated PNG within the frozen limits', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-photo-png-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/portrait.png');
    await source.writeAsBytes(_png(width: 2048, height: 1536));
    final importer = AppOwnedPhotoImporter(
      source: _FakePhotoSource([
        SelectedPhoto(path: source.path, name: 'portrait.png'),
      ]),
      mediaDirectory: () async => Directory('${directory.path}/app-media'),
      inspectPhoto: _inspectJpeg,
      createId: () => 'photo-png',
    );

    final batch = await importer.importPhotos(limit: 6);

    expect(batch.failures, isEmpty);
    expect(batch.photos.single.originalName, 'portrait.png');
  });

  test('rejects an animated PNG without rejecting a valid neighbor', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-photo-animated-png-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final animated = File('${directory.path}/animated.png');
    final valid = File('${directory.path}/still.png');
    await animated.writeAsBytes(_png(width: 1200, height: 900, animated: true));
    await valid.writeAsBytes(_png(width: 1200, height: 900));
    var nextId = 0;
    final importer = AppOwnedPhotoImporter(
      source: _FakePhotoSource([
        SelectedPhoto(path: animated.path, name: 'animated.png'),
        SelectedPhoto(path: valid.path, name: 'still.png'),
      ]),
      mediaDirectory: () async => Directory('${directory.path}/app-media'),
      inspectPhoto: _inspectJpeg,
      createId: () => 'photo-${++nextId}',
    );

    final batch = await importer.importPhotos(limit: 6);

    expect(batch.photos.single.originalName, 'still.png');
    expect(batch.failures, [
      const PhotoImportFailure(
        photoName: 'animated.png',
        reason: PhotoImportFailureReason.animatedImage,
      ),
    ]);
  });

  test('rejects a file over 100 MB before inspecting or copying it', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-photo-file-limit-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/huge.jpg');
    final handle = await source.open(mode: FileMode.write);
    await handle.truncate(AppOwnedPhotoImporter.maxFileBytes + 1);
    await handle.close();
    final media = Directory('${directory.path}/app-media');
    final importer = AppOwnedPhotoImporter(
      source: _FakePhotoSource([
        SelectedPhoto(path: source.path, name: 'huge.jpg'),
      ]),
      mediaDirectory: () async => media,
      inspectPhoto: _inspectJpeg,
      createId: () => 'must-not-be-copied',
    );

    final batch = await importer.importPhotos(limit: 6);

    expect(batch.photos, isEmpty);
    expect(batch.failures.single.reason, PhotoImportFailureReason.fileTooLarge);
    expect(File('${media.path}/must-not-be-copied.jpg').existsSync(), isFalse);
  });

  test('imports a supported HEIC after reading its pixel dimensions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-photo-heic-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/portrait.heic');
    await source.writeAsBytes(_heic(width: 4032, height: 3024));
    final importer = AppOwnedPhotoImporter(
      source: _FakePhotoSource([
        SelectedPhoto(path: source.path, name: 'portrait.heic'),
      ]),
      mediaDirectory: () async => Directory('${directory.path}/app-media'),
      inspectPhoto: _inspectJpeg,
      supportsHeif: () async => true,
      createId: () => 'photo-heic',
    );

    final batch = await importer.importPhotos(limit: 6);

    expect(batch.failures, isEmpty);
    expect(batch.photos.single.originalName, 'portrait.heic');
  });

  test('rejects a HEIF image sequence as an animated image', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-photo-heif-sequence-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/sequence.heic');
    await source.writeAsBytes(_heic(width: 1920, height: 1080, sequence: true));
    final importer = AppOwnedPhotoImporter(
      source: _FakePhotoSource([
        SelectedPhoto(path: source.path, name: 'sequence.heic'),
      ]),
      mediaDirectory: () async => Directory('${directory.path}/app-media'),
      supportsHeif: () async => true,
      inspectPhoto: _inspectJpeg,
      createId: () => 'sequence',
    );

    final batch = await importer.importPhotos(limit: 6);

    expect(batch.photos, isEmpty);
    expect(
      batch.failures.single.reason,
      PhotoImportFailureReason.animatedImage,
    );
  });

  test('inspects the app copy and names it from decoded content', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-photo-content-copy-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/misleading.png');
    final bytes = _jpeg(width: 4000, height: 3000);
    await source.writeAsBytes(bytes);
    String? inspectedPath;
    final importer = AppOwnedPhotoImporter(
      source: _FakePhotoSource([
        SelectedPhoto(path: source.path, name: 'misleading.png'),
      ]),
      mediaDirectory: () async => Directory('${directory.path}/app-media'),
      inspectPhoto: (path) async {
        inspectedPath = path;
        expect(await File(path).readAsBytes(), bytes);
        return _inspectJpeg(path);
      },
      createId: () => 'content-copy',
    );

    final batch = await importer.importPhotos(limit: 6);

    expect(inspectedPath, endsWith('.importing'));
    expect(batch.photos.single.localPath, endsWith('content-copy.jpg'));
    expect(await File(batch.photos.single.localPath).readAsBytes(), bytes);
  });
}

Future<PhotoContentInspection> _inspectJpeg(String path) async {
  return const PhotoContentInspection(
    contentSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    pixelWidth: 4000,
    pixelHeight: 3000,
    orientation: 1,
    colorSpace: PhotoColorSpace.srgb,
    inputFormat: PhotoInputFormat.jpeg,
  );
}

List<int> _jpeg({required int width, required int height}) => [
  0xFF,
  0xD8,
  0xFF,
  0xC0,
  0x00,
  0x11,
  0x08,
  height >> 8,
  height & 0xFF,
  width >> 8,
  width & 0xFF,
  0x03,
  0x01,
  0x11,
  0x00,
  0x02,
  0x11,
  0x00,
  0x03,
  0x11,
  0x00,
  0xFF,
  0xD9,
];

List<int> _png({
  required int width,
  required int height,
  bool animated = false,
}) {
  final bytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  void chunk(String type, List<int> data) {
    bytes.addAll(_uint32(data.length));
    bytes.addAll(type.codeUnits);
    bytes.addAll(data);
    bytes.addAll(const [0, 0, 0, 0]);
  }

  chunk('IHDR', [..._uint32(width), ..._uint32(height), 8, 2, 0, 0, 0]);
  if (animated) {
    chunk('acTL', const [0, 0, 0, 1, 0, 0, 0, 0]);
  }
  chunk('IDAT', const []);
  chunk('IEND', const []);
  return bytes;
}

List<int> _uint32(int value) => [
  value >> 24 & 0xFF,
  value >> 16 & 0xFF,
  value >> 8 & 0xFF,
  value & 0xFF,
];

List<int> _heic({
  required int width,
  required int height,
  bool sequence = false,
}) {
  List<int> box(String type, List<int> payload) => [
    ..._uint32(8 + payload.length),
    ...type.codeUnits,
    ...payload,
  ];

  final ftyp = box('ftyp', [
    ...(sequence ? 'msf1' : 'heic').codeUnits,
    0,
    0,
    0,
    0,
    ...'mif1'.codeUnits,
    ...(sequence ? 'msf1' : 'heic').codeUnits,
  ]);
  final ispe = box('ispe', [0, 0, 0, 0, ..._uint32(width), ..._uint32(height)]);
  final ipco = box('ipco', ispe);
  final iprp = box('iprp', ipco);
  final meta = box('meta', [0, 0, 0, 0, ...iprp]);
  return [...ftyp, ...meta];
}

final class _FakePhotoSource implements PhotoSource {
  _FakePhotoSource(this.photos);

  final List<SelectedPhoto> photos;

  @override
  Future<List<SelectedPhoto>> pickPhotos({required int limit}) async => photos;
}

final class _ReleasablePhotoSource implements ReleasablePhotoSource {
  _ReleasablePhotoSource(this.photos, {this.releaseError});

  final List<SelectedPhoto> photos;
  final Object? releaseError;
  final List<String> released = [];

  @override
  Future<List<SelectedPhoto>> pickPhotos({required int limit}) async => photos;

  @override
  Future<void> releasePhotos(List<SelectedPhoto> photos) async {
    released.addAll(photos.map((photo) => photo.path));
    final error = releaseError;
    if (error != null) {
      throw error;
    }
  }
}
