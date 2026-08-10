import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/project/infrastructure/json_photo_project_store.dart';

void main() {
  test('saved project can be restored from a fresh store instance', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-project-store-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final project = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 4, 5),
      updatedAt: DateTime.utc(2026, 8, 4, 6),
      photos: const [
        ProjectPhoto(
          id: 'photo-1',
          localPath: '/app/media/photo-1.jpg',
          originalName: 'holiday.jpg',
          contentSha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          pixelWidth: 4032,
          pixelHeight: 3024,
          orientation: 6,
          colorSpace: PhotoColorSpace.displayP3,
          inputFormat: PhotoInputFormat.jpeg,
          supportState: PhotoSupportState.supported,
        ),
      ],
    );

    await JsonPhotoProjectStore(directory: () async => directory).save(project);
    final restored = await JsonPhotoProjectStore(
      directory: () async => directory,
    ).loadLatest();

    expect(restored, project);
  });

  test(
    'a later save atomically replaces the previous project snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yingjian-project-update-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = JsonPhotoProjectStore(directory: () async => directory);
      final initial = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4, 5),
        updatedAt: DateTime.utc(2026, 8, 4, 5),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/app/media/photo-1.jpg',
            originalName: 'first.jpg',
          ),
        ],
      );
      final updated = initial.copyWith(
        updatedAt: DateTime.utc(2026, 8, 4, 6),
        photos: [
          ...initial.photos,
          const ProjectPhoto(
            id: 'photo-2',
            localPath: '/app/media/photo-2.jpg',
            originalName: 'second.jpg',
          ),
        ],
      );

      await store.save(initial);
      await store.save(updated);

      expect(await store.loadLatest(), updated);
    },
  );

  test('app-owned photo paths survive a container directory change', () async {
    final parent = await Directory.systemTemp.createTemp(
      'yingjian-project-relocation-',
    );
    addTearDown(() => parent.delete(recursive: true));
    final originalRoot = Directory('${parent.path}/old-container');
    final originalPhoto = File('${originalRoot.path}/media/photo-1.jpg');
    await originalPhoto.parent.create(recursive: true);
    await originalPhoto.writeAsBytes(const [1, 2, 3]);
    final project = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 4, 5),
      updatedAt: DateTime.utc(2026, 8, 4, 5),
      photos: [
        ProjectPhoto(
          id: 'photo-1',
          localPath: originalPhoto.path,
          originalName: 'holiday.jpg',
        ),
      ],
    );
    await JsonPhotoProjectStore(
      directory: () async => originalRoot,
    ).save(project);
    final relocatedRoot = await originalRoot.rename(
      '${parent.path}/new-container',
    );

    final restored = await JsonPhotoProjectStore(
      directory: () async => relocatedRoot,
    ).loadLatest();

    expect(
      restored?.photos.single.localPath,
      '${relocatedRoot.path}/media/photo-1.jpg',
    );
  });

  test('legacy absolute app path migrates to the current media copy', () async {
    final root = await Directory.systemTemp.createTemp(
      'yingjian-project-legacy-',
    );
    addTearDown(() => root.delete(recursive: true));
    final currentPhoto = File('${root.path}/media/photo-1.jpg');
    await currentPhoto.parent.create(recursive: true);
    await currentPhoto.writeAsBytes(const [1, 2, 3]);
    final legacyProject = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 4, 5),
      updatedAt: DateTime.utc(2026, 8, 4, 5),
      photos: const [
        ProjectPhoto(
          id: 'photo-1',
          localPath: '/old-ios-container/media/photo-1.jpg',
          originalName: 'holiday.jpg',
        ),
      ],
    );
    final snapshot = File('${root.path}/projects/latest.json');
    await snapshot.parent.create(recursive: true);
    await snapshot.writeAsString(jsonEncode(legacyProject.toJson()));

    final restored = await JsonPhotoProjectStore(
      directory: () async => root,
    ).loadLatest();

    expect(restored?.photos.single.localPath, currentPhoto.path);
  });

  test('deletes only an app-owned media copy', () async {
    final root = await Directory.systemTemp.createTemp(
      'yingjian-project-delete-photo-',
    );
    addTearDown(() => root.delete(recursive: true));
    final appCopy = File('${root.path}/media/photo-1.jpg');
    final externalSource = File('${root.parent.path}/source-photo.jpg');
    await appCopy.parent.create(recursive: true);
    await appCopy.writeAsBytes(const [1, 2, 3]);
    await externalSource.writeAsBytes(const [4, 5, 6]);
    addTearDown(() async {
      if (await externalSource.exists()) {
        await externalSource.delete();
      }
    });
    final store = JsonPhotoProjectStore(directory: () async => root);

    await store.deletePhotoCopy(
      ProjectPhoto(
        id: 'photo-1',
        localPath: appCopy.path,
        originalName: 'source-photo.jpg',
      ),
    );
    await store.deletePhotoCopy(
      ProjectPhoto(
        id: 'external',
        localPath: externalSource.path,
        originalName: 'source-photo.jpg',
      ),
    );

    expect(await appCopy.exists(), isFalse);
    expect(await externalSource.exists(), isTrue);
  });

  test('deletes the project snapshot and its app-owned media copies', () async {
    final root = await Directory.systemTemp.createTemp(
      'yingjian-project-delete-',
    );
    addTearDown(() => root.delete(recursive: true));
    final appCopy = File('${root.path}/media/photo-1.jpg');
    final backgroundCopy = File('${root.path}/media/background-1.jpg');
    final preview = File('${root.path}/previews/photo-1/preview.jpg');
    final analysis = File('${root.path}/analysis/photo-1/result.json');
    final debugArtifact = File('${root.path}/debug/photo-1/trace.txt');
    await appCopy.parent.create(recursive: true);
    await appCopy.writeAsBytes(const [1, 2, 3]);
    await backgroundCopy.writeAsBytes(const [4, 5, 6]);
    for (final derived in [preview, analysis, debugArtifact]) {
      await derived.parent.create(recursive: true);
      await derived.writeAsString('derived');
    }
    final project = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      photos: [
        ProjectPhoto(
          id: 'photo-1',
          localPath: appCopy.path,
          originalName: 'photo.jpg',
        ),
      ],
    );
    final store = JsonPhotoProjectStore(directory: () async => root);
    await store.save(project);

    await store.deleteProject(project);

    expect(await store.loadLatest(), isNull);
    expect(await appCopy.exists(), isFalse);
    expect(await backgroundCopy.exists(), isFalse);
    expect(await preview.exists(), isFalse);
    expect(await analysis.exists(), isFalse);
    expect(await debugArtifact.exists(), isFalse);
  });

  test('deleting one photo also removes only its derived artifacts', () async {
    final root = await Directory.systemTemp.createTemp(
      'yingjian-project-delete-derived-',
    );
    addTearDown(() => root.delete(recursive: true));
    final first = File('${root.path}/previews/photo-1/preview.jpg');
    final second = File('${root.path}/previews/photo-2/preview.jpg');
    for (final file in [first, second]) {
      await file.parent.create(recursive: true);
      await file.writeAsString('preview');
    }
    final store = JsonPhotoProjectStore(directory: () async => root);

    await store.deletePhotoCopy(
      ProjectPhoto(
        id: 'photo-1',
        localPath: '${root.path}/media/missing.jpg',
        originalName: 'first.jpg',
      ),
    );

    expect(await first.exists(), isFalse);
    expect(await second.exists(), isTrue);
  });
}
