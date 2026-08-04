import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

void main() {
  group('PhotoProjectSession', () {
    test('imports up to six app-owned photos and saves the project', () async {
      final importer = _FakePhotoImporter([
        const ProjectPhoto(
          id: 'photo-1',
          localPath: '/app/media/photo-1.jpg',
          originalName: 'first.jpg',
        ),
        const ProjectPhoto(
          id: 'photo-2',
          localPath: '/app/media/photo-2.heic',
          originalName: 'second.heic',
        ),
      ]);
      final store = _MemoryPhotoProjectStore();
      final session = PhotoProjectSession(
        importer: importer,
        store: store,
        now: () => DateTime.utc(2026, 8, 4, 5),
        createId: () => 'project-1',
      );

      final result = await session.importPhotos();

      expect(result, PhotoImportResult.imported);
      expect(importer.requestedLimits, [6]);
      expect(session.project?.id, 'project-1');
      expect(session.photos, hasLength(2));
      expect(session.photos.first.localPath, '/app/media/photo-1.jpg');
      expect(store.savedProject, session.project);
    });

    test('restores the latest saved project before editing', () async {
      final saved = PhotoProject(
        id: 'project-restored',
        createdAt: DateTime.utc(2026, 8, 3),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [
          ProjectPhoto(
            id: 'photo-restored',
            localPath: '/app/media/restored.jpg',
            originalName: 'restored.jpg',
          ),
        ],
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );

      await session.restore();

      expect(session.project, saved);
      expect(session.photos.single.originalName, 'restored.jpg');
    });

    test('persists the reversible edit recipe with the project', () async {
      final store = _MemoryPhotoProjectStore()
        ..savedProject = PhotoProject(
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
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
        now: () => DateTime.utc(2026, 8, 4, 6),
      );
      await session.restore();
      final recipe = EditRecipe(exposure: 0.3, contrast: 0.2, warmth: -0.1);

      await session.updateRecipe(recipe);

      expect(session.project?.recipe, recipe);
      expect(store.savedProject?.recipe, recipe);
      expect(store.savedProject?.updatedAt, DateTime.utc(2026, 8, 4, 6));
    });

    test(
      'keeps startup available when the saved project is unreadable',
      () async {
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: _FailingPhotoProjectStore(),
        );

        await session.restore();

        expect(session.photos, isEmpty);
        expect(session.restoreError, isA<FormatException>());
      },
    );

    test('treats closing the system picker as a cancellation', () async {
      final store = _MemoryPhotoProjectStore();
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );

      final result = await session.importPhotos();

      expect(result, PhotoImportResult.canceled);
      expect(session.project, isNull);
      expect(store.savedProject, isNull);
    });

    test(
      'does not open the picker after a project reaches six photos',
      () async {
        final saved = PhotoProject(
          id: 'full-project',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: List.generate(
            6,
            (index) => ProjectPhoto(
              id: 'photo-$index',
              localPath: '/app/media/photo-$index.jpg',
              originalName: 'photo-$index.jpg',
            ),
          ),
        );
        final importer = _FakePhotoImporter(const []);
        final session = PhotoProjectSession(
          importer: importer,
          store: _MemoryPhotoProjectStore()..savedProject = saved,
        );
        await session.restore();

        final result = await session.importPhotos();

        expect(result, PhotoImportResult.limitReached);
        expect(importer.requestedLimits, isEmpty);
      },
    );

    test(
      'publishes valid photos and item-level import failures together',
      () async {
        final importer = _FakePhotoImporter(
          const [
            ProjectPhoto(
              id: 'photo-1',
              localPath: '/app/media/photo-1.jpg',
              originalName: 'valid.jpg',
            ),
          ],
          failures: const [
            PhotoImportFailure(
              photoName: 'animated.png',
              reason: PhotoImportFailureReason.animatedImage,
            ),
          ],
        );
        final session = PhotoProjectSession(
          importer: importer,
          store: _MemoryPhotoProjectStore(),
        );

        final result = await session.importPhotos();

        expect(result, PhotoImportResult.imported);
        expect(session.photos.single.originalName, 'valid.jpg');
        expect(session.importFailures, importer.failures);
      },
    );

    test(
      'moves a photo and saves the new project order before publishing',
      () async {
        final saved = PhotoProject(
          id: 'project-1',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: const [
            ProjectPhoto(
              id: 'photo-1',
              localPath: '/app/media/photo-1.jpg',
              originalName: 'first.jpg',
            ),
            ProjectPhoto(
              id: 'photo-2',
              localPath: '/app/media/photo-2.jpg',
              originalName: 'second.jpg',
            ),
          ],
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
          now: () => DateTime.utc(2026, 8, 4, 1),
        );
        await session.restore();

        await session.movePhoto(photoId: 'photo-2', toIndex: 0);

        expect(session.photos.map((photo) => photo.id), ['photo-2', 'photo-1']);
        expect(store.savedProject, session.project);
        expect(session.project?.updatedAt, DateTime.utc(2026, 8, 4, 1));
      },
    );

    test('selects and persists the focus photo', () async {
      final saved = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/app/media/photo-1.jpg',
            originalName: 'first.jpg',
          ),
          ProjectPhoto(
            id: 'photo-2',
            localPath: '/app/media/photo-2.jpg',
            originalName: 'second.jpg',
          ),
        ],
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
        now: () => DateTime.utc(2026, 8, 4, 2),
      );
      await session.restore();

      await session.setFocusPhoto('photo-2');

      expect(session.project?.focusPhotoId, 'photo-2');
      expect(store.savedProject, session.project);
    });

    test(
      'removes a photo and its layers, then chooses a valid focus',
      () async {
        final saved = PhotoProject(
          id: 'project-1',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: const [
            ProjectPhoto(
              id: 'photo-1',
              localPath: '/app/media/photo-1.jpg',
              originalName: 'first.jpg',
            ),
            ProjectPhoto(
              id: 'photo-2',
              localPath: '/app/media/photo-2.jpg',
              originalName: 'second.jpg',
            ),
          ],
          focusPhotoId: 'photo-2',
          adaptiveCompensations: {
            'photo-2': AdaptiveCompensation(recipe: EditRecipe(exposure: 0.1)),
          },
          photoOverrides: {
            'photo-2': PhotoOverride(recipe: EditRecipe(warmth: 0.2)),
          },
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
          now: () => DateTime.utc(2026, 8, 4, 3),
        );
        await session.restore();

        await session.removePhoto('photo-2');

        expect(session.photos.map((photo) => photo.id), ['photo-1']);
        expect(session.project?.focusPhotoId, 'photo-1');
        expect(session.project?.adaptiveCompensations, isEmpty);
        expect(session.project?.photoOverrides, isEmpty);
        expect(store.deletedPhotoIds, ['photo-2']);
      },
    );

    test('removing the final photo deletes the project', () async {
      final saved = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/app/media/photo-1.jpg',
            originalName: 'only.jpg',
          ),
        ],
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await session.removePhoto('photo-1');

      expect(session.project, isNull);
      expect(store.savedProject, isNull);
      expect(store.deletedProjectIds, ['project-1']);
    });

    test('deletes the complete project on request', () async {
      final saved = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/app/media/photo-1.jpg',
            originalName: 'first.jpg',
          ),
          ProjectPhoto(
            id: 'photo-2',
            localPath: '/app/media/photo-2.jpg',
            originalName: 'second.jpg',
          ),
        ],
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await session.deleteProject();

      expect(session.project, isNull);
      expect(store.savedProject, isNull);
      expect(store.deletedProjectIds, ['project-1']);
    });
  });
}

final class _FakePhotoImporter implements PhotoImporter {
  _FakePhotoImporter(this.photos, {this.failures = const []});

  final List<ProjectPhoto> photos;
  final List<PhotoImportFailure> failures;
  final List<int> requestedLimits = [];

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) async {
    requestedLimits.add(limit);
    return PhotoImportBatch(photos: photos, failures: failures);
  }
}

final class _MemoryPhotoProjectStore implements PhotoProjectLifecycleStore {
  PhotoProject? savedProject;
  final List<String> deletedPhotoIds = [];
  final List<String> deletedProjectIds = [];

  @override
  Future<PhotoProject?> loadLatest() async => savedProject;

  @override
  Future<void> save(PhotoProject project) async {
    savedProject = project;
  }

  @override
  Future<void> deletePhotoCopy(ProjectPhoto photo) async {
    deletedPhotoIds.add(photo.id);
  }

  @override
  Future<void> deleteProject(PhotoProject project) async {
    deletedProjectIds.add(project.id);
    savedProject = null;
  }
}

final class _FailingPhotoProjectStore implements PhotoProjectStore {
  @override
  Future<PhotoProject?> loadLatest() async {
    throw const FormatException('corrupt project');
  }

  @override
  Future<void> save(PhotoProject project) async {}
}
