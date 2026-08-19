import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/project/infrastructure/json_photo_project_store.dart';

void main() {
  test(
    'rejects a project whose canonical state disagrees with pixels',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yingjian-project-inconsistent-state-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final project = PhotoProject(
        id: 'project-inconsistent',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/app/media/photo-1.jpg',
            originalName: 'photo.jpg',
          ),
        ],
        sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.25)),
        editState: EditState.empty,
      );
      final store = JsonPhotoProjectStore(directory: () async => directory);

      await expectLater(store.save(project), throwsStateError);
      expect(
        () => PhotoProject.fromJson(project.toJson()),
        throwsFormatException,
      );
    },
  );

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

  test('invalid history cannot replace the last safe project', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-project-invalid-history-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = JsonPhotoProjectStore(directory: () async => directory);
    final safe = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(2026, 8, 20),
      photos: const [
        ProjectPhoto(
          id: 'photo-1',
          localPath: '/external/photo.jpg',
          originalName: 'photo.jpg',
        ),
      ],
    );
    await store.save(safe);
    final after = safe.copyWith(
      sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.2)),
    );
    final invalid = safe.copyWith(
      historyBaseSnapshot: ProjectEditSnapshot.fromProject(safe),
      undoHistory: [
        ProjectEditOperation(
          scope: ProjectEditingScope.group,
          beforeRecipe: EditRecipe.neutral,
          afterRecipe: EditRecipe(exposure: 0.2),
          beforeSnapshot: ProjectEditSnapshot.fromProject(safe),
          afterSnapshot: ProjectEditSnapshot.fromProject(after),
        ),
      ],
    );

    await expectLater(store.save(invalid), throwsA(isA<FormatException>()));

    expect(await store.loadLatest(), safe);
    expect(
      await File('${directory.path}/projects/latest.json.tmp').exists(),
      isFalse,
    );
  });

  test('read-only future meta ops cannot overwrite the safe project', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yingjian-project-future-op-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = JsonPhotoProjectStore(directory: () async => directory);
    final safe = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(2026, 8, 20),
      photos: const [
        ProjectPhoto(
          id: 'photo-1',
          localPath: '/external/photo.jpg',
          originalName: 'photo.jpg',
        ),
      ],
    );
    await store.save(safe);
    final protected = safe.copyWith(
      unknownMetaOps: const [
        {
          'id': 'future.generative_relight',
          'version': 7,
          'payload': {'mode': 'cinematic'},
        },
      ],
    );

    await expectLater(store.save(protected), throwsA(isA<StateError>()));

    expect(await store.loadLatest(), safe);
  });

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

  test(
    'content-addressed editing resources survive a container move',
    () async {
      const sha =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const resourceId = 'resource-v1-$sha';
      final parent = await Directory.systemTemp.createTemp(
        'yingjian-resource-relocation-',
      );
      addTearDown(() => parent.delete(recursive: true));
      final originalRoot = Directory('${parent.path}/old-container');
      final background = File('${originalRoot.path}/resources/aa/$sha.jpg');
      await background.parent.create(recursive: true);
      await background.writeAsBytes(const [4, 5, 6]);
      final registry = EditingResourceRegistry.empty
          .register(
            const EditingResourceDescriptor(
              id: resourceId,
              kind: EditingResourceKind.backgroundImage,
              relativePath: 'resources/aa/$sha.jpg',
              contentSha256: sha,
              byteLength: 3,
            ),
          )
          .retain(resourceId, EditingResourceOwner.currentState);
      final project = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/external/photo.jpg',
            originalName: 'photo.jpg',
          ),
        ],
        photoOverrides: {
          'photo-1': PhotoOverride(
            recipe: EditRecipe(
              semanticEditingRecipe: SemanticEditingRecipe(
                background: BackgroundTreatment.image,
                backgroundImagePath:
                    '${originalRoot.path}/resources/aa/$sha.jpg',
                backgroundImageResourceId: resourceId,
              ),
            ),
          ),
        },
        editingResources: registry,
      );
      final store = JsonPhotoProjectStore(directory: () async => originalRoot);
      await store.save(project);
      final snapshot = File('${originalRoot.path}/projects/latest.json');
      expect(
        await snapshot.readAsString(),
        contains('"backgroundImagePath":"resources/aa/$sha.jpg"'),
      );
      final relocatedRoot = await originalRoot.rename(
        '${parent.path}/new-container',
      );

      final restored = await JsonPhotoProjectStore(
        directory: () async => relocatedRoot,
      ).loadLatest();

      expect(
        restored
            ?.photoOverrides['photo-1']
            ?.recipe
            .semanticEditingRecipe
            .backgroundImagePath,
        '${relocatedRoot.path}/resources/aa/$sha.jpg',
      );
    },
  );

  test(
    'a zero-reference resource is reclaimed only after the new snapshot saves',
    () async {
      const sha =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const resourceId = 'resource-v1-$sha';
      final root = await Directory.systemTemp.createTemp(
        'yingjian-resource-reclaim-',
      );
      addTearDown(() => root.delete(recursive: true));
      final resourceFile = File('${root.path}/resources/aa/$sha.jpg');
      await resourceFile.parent.create(recursive: true);
      await resourceFile.writeAsBytes(const [1, 2, 3]);
      final registry = EditingResourceRegistry.empty
          .register(
            const EditingResourceDescriptor(
              id: resourceId,
              kind: EditingResourceKind.backgroundImage,
              relativePath: 'resources/aa/$sha.jpg',
              contentSha256: sha,
              byteLength: 3,
            ),
          )
          .retain(resourceId, EditingResourceOwner.currentState);
      final initial = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/external/photo.jpg',
            originalName: 'photo.jpg',
          ),
        ],
        editingResources: registry,
      );
      final store = JsonPhotoProjectStore(directory: () async => root);
      await store.save(initial);

      await store.save(
        initial.copyWith(
          updatedAt: DateTime.utc(2026, 8, 20, 1),
          editingResources: EditingResourceRegistry.empty,
        ),
      );

      expect(await resourceFile.exists(), isFalse);
      expect((await store.loadLatest())!.editingResources.resources, isEmpty);
    },
  );

  test(
    'failed first save removes only the uncommitted editing resource',
    () async {
      const sha =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const resourceId = 'resource-v1-$sha';
      final root = await Directory.systemTemp.createTemp(
        'yingjian-resource-failed-save-',
      );
      addTearDown(() => root.delete(recursive: true));
      final resourceFile = File('${root.path}/resources/aa/$sha.jpg');
      await resourceFile.parent.create(recursive: true);
      await resourceFile.writeAsBytes(const [1, 2, 3]);
      final blockingTemporary = Directory(
        '${root.path}/projects/latest.json.tmp',
      );
      await blockingTemporary.create(recursive: true);
      final registry = EditingResourceRegistry.empty
          .register(
            const EditingResourceDescriptor(
              id: resourceId,
              kind: EditingResourceKind.backgroundImage,
              relativePath: 'resources/aa/$sha.jpg',
              contentSha256: sha,
              byteLength: 3,
            ),
          )
          .retain(resourceId, EditingResourceOwner.currentState);
      final project = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/external/photo.jpg',
            originalName: 'photo.jpg',
          ),
        ],
        editingResources: registry,
      );
      final store = JsonPhotoProjectStore(directory: () async => root);

      await expectLater(
        store.save(project),
        throwsA(isA<FileSystemException>()),
      );

      expect(await resourceFile.exists(), isFalse);
      expect(await blockingTemporary.exists(), isTrue);
      expect(await store.loadLatest(), isNull);
    },
  );

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

  test(
    'loading version eleven atomically persists an idempotent migration',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yingjian-project-history-migration-',
      );
      addTearDown(() => root.delete(recursive: true));
      final legacy = PhotoProject(
        id: 'legacy-history',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20, 1),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/external/photo.jpg',
            originalName: 'photo.jpg',
          ),
        ],
        sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.2)),
        undoHistory: [
          ProjectEditOperation(
            scope: ProjectEditingScope.group,
            beforeRecipe: EditRecipe.neutral,
            afterRecipe: EditRecipe(exposure: 0.2),
          ),
        ],
      ).toJson()..['schemaVersion'] = 11;
      final operation = (legacy['undoHistory']! as List).single as Map;
      for (final key in const [
        'source',
        'changedAddresses',
        'beforeSnapshot',
        'afterSnapshot',
      ]) {
        operation.remove(key);
      }
      final snapshot = File('${root.path}/projects/latest.json');
      await snapshot.parent.create(recursive: true);
      await snapshot.writeAsString(jsonEncode(legacy));
      final store = JsonPhotoProjectStore(directory: () async => root);

      final migrated = await store.loadLatest();
      final persisted = jsonDecode(await snapshot.readAsString()) as Map;
      final reopened = await store.loadLatest();

      expect(migrated!.hasValidHistoryReplay, isTrue);
      expect(persisted['schemaVersion'], PhotoProject.schemaVersion);
      expect(reopened, migrated);
      expect(await File('${snapshot.path}.tmp').exists(), isFalse);
    },
  );

  test('failed migration keeps the last safe legacy snapshot', () async {
    final root = await Directory.systemTemp.createTemp(
      'yingjian-project-migration-retry-',
    );
    addTearDown(() => root.delete(recursive: true));
    final legacy = PhotoProject(
      id: 'legacy-safe',
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(2026, 8, 20),
      photos: const [
        ProjectPhoto(
          id: 'photo-1',
          localPath: '/external/photo.jpg',
          originalName: 'photo.jpg',
        ),
      ],
    ).toJson()..['schemaVersion'] = 11;
    final snapshot = File('${root.path}/projects/latest.json');
    await snapshot.parent.create(recursive: true);
    await snapshot.writeAsString(jsonEncode(legacy));
    await Directory('${snapshot.path}.tmp').create();

    final restored = await JsonPhotoProjectStore(
      directory: () async => root,
    ).loadLatest();
    final stillSafe = jsonDecode(await snapshot.readAsString()) as Map;

    expect(restored, isNotNull);
    expect(stillSafe['schemaVersion'], 11);
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
