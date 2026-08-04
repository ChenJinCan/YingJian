import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

void main() {
  group('PhotoProjectSession', () {
    test('imports up to nine app-owned photos and saves the project', () async {
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
      expect(importer.requestedLimits, [9]);
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
      'does not open the picker after a project reaches nine photos',
      () async {
        final saved = PhotoProject(
          id: 'full-project',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: List.generate(
            9,
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
  });
}

final class _FakePhotoImporter implements PhotoImporter {
  _FakePhotoImporter(this.photos);

  final List<ProjectPhoto> photos;
  final List<int> requestedLimits = [];

  @override
  Future<List<ProjectPhoto>> importPhotos({required int limit}) async {
    requestedLimits.add(limit);
    return photos;
  }
}

final class _MemoryPhotoProjectStore implements PhotoProjectStore {
  PhotoProject? savedProject;

  @override
  Future<PhotoProject?> loadLatest() async => savedProject;

  @override
  Future<void> save(PhotoProject project) async {
    savedProject = project;
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
