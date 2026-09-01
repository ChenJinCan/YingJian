import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/creation/domain/creation_task.dart';
import 'package:yingjian/features/creation/domain/style_definition.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

void main() {
  group('PhotoProjectSession explicit creation capability', () {
    test('a newly imported project has no selected capability', () async {
      final store = _CountingPhotoProjectStore();
      final session = PhotoProjectSession(
        importer: const _FixedPhotoImporter([_photo]),
        store: store,
        creationTask: CreationTask.optimize,
        now: () => DateTime.utc(2026, 9, 1),
        createId: () => 'project-1',
      );

      final result = await session.importPhotos();

      expect(result, PhotoImportResult.imported);
      expect(session.project?.creationTask, CreationTask.optimize);
      expect(session.project?.creationCapability, isNull);
      expect(store.saveCount, 1);
    });

    test(
      'selection saves the exact capability and identical selection is a no-op',
      () async {
        final initial = _project(task: CreationTask.style);
        final store = _CountingPhotoProjectStore(initial);
        final session = PhotoProjectSession(
          importer: const _FixedPhotoImporter(),
          store: store,
        );
        await session.restore();

        await session.selectCreationCapability(CreationCapability.styleText);

        final selected = session.project;
        expect(selected?.creationCapability, CreationCapability.styleText);
        expect(store.latest, same(selected));
        expect(store.saveCount, 1);

        await session.selectCreationCapability(CreationCapability.styleText);

        expect(session.project, same(selected));
        expect(store.latest, same(selected));
        expect(store.saveCount, 1);
      },
    );

    test(
      'clear is explicit and preserves the recoverable result identity',
      () async {
        final recipe = EditRecipe.neutral;
        final definition = StyleDefinition(
          styleId: 'natural',
          revision: 1,
          origin: StyleDefinitionOrigin.official,
          title: '自然',
          summary: '官方自然风格',
          recipe: recipe,
          createdAt: DateTime.utc(2026, 9, 1),
        );
        final result = StaticStyleResultIdentity(
          sourcePhotoId: _photo.id,
          editStateVersion: 0,
          styleId: definition.styleId,
          capability: CreationCapability.styleOfficial,
          styleName: definition.title,
          recipe: recipe,
        );
        final initial = PhotoProject(
          id: 'style-result-project',
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
          photos: const [_photo],
          creationTask: CreationTask.style,
          creationCapability: CreationCapability.styleOfficial,
          creationStyleId: definition.styleId,
          creationStyleName: definition.title,
          creationStyleRecipe: recipe,
          creationStyleDefinition: definition,
          creationResult: result,
          creationResultActive: true,
          sharedStyle: SharedStyle(recipe: recipe),
        );
        final store = _CountingPhotoProjectStore(initial);
        final session = PhotoProjectSession(
          importer: const _FixedPhotoImporter(),
          store: store,
        );

        await session.restore();

        expect(session.project, same(initial));
        expect(session.project?.creationCapability, isNotNull);
        expect(session.project?.creationStyleDefinition, same(definition));
        expect(session.project?.currentStaticStyleResult, result);
        expect(store.saveCount, 0);

        await session.clearCreationCapability();

        final cleared = session.project!;
        expect(cleared.creationCapability, isNull);
        expect(cleared.creationStyleId, isNull);
        expect(cleared.creationStyleName, isNull);
        expect(cleared.creationStyleRecipe, isNull);
        expect(cleared.creationStyleDefinition, isNull);
        expect(cleared.creationResultActive, isFalse);
        expect(cleared.creationResult, same(result));
        expect(cleared.recoverableStaticStyleResult, isNull);
        expect(cleared.currentStaticStyleResult, isNull);
        expect(store.latest, same(cleared));
        expect(store.saveCount, 1);

        await session.clearCreationCapability();

        expect(session.project, same(cleared));
        expect(store.latest, same(cleared));
        expect(store.saveCount, 1);

        await session.selectCreationCapability(
          CreationCapability.styleOfficial,
        );

        final reselected = session.project!;
        expect(reselected.creationCapability, CreationCapability.styleOfficial);
        expect(reselected.creationResult, same(result));
        expect(reselected.recoverableStaticStyleResult, same(result));
        expect(reselected.creationResultActive, isFalse);
        expect(store.latest, same(reselected));
        expect(store.saveCount, 2);
      },
    );

    test('clear is a no-op when selection is already empty', () async {
      final initial = _project(task: CreationTask.style);
      final store = _CountingPhotoProjectStore(initial);
      final session = PhotoProjectSession(
        importer: const _FixedPhotoImporter(),
        store: store,
      );
      await session.restore();

      await session.clearCreationCapability();

      expect(session.project, same(initial));
      expect(store.latest, same(initial));
      expect(store.saveCount, 0);
    });

    test(
      'non-editing project rejects clear without changing the project',
      () async {
        final initial = _project(
          task: CreationTask.style,
          capability: CreationCapability.styleOfficial,
          flowState: PhotoProjectFlowState.exporting,
        );
        final store = _CountingPhotoProjectStore(initial);
        final session = PhotoProjectSession(
          importer: const _FixedPhotoImporter(),
          store: store,
        );
        await session.restore();

        await expectLater(session.clearCreationCapability(), throwsStateError);

        expect(session.project, same(initial));
        expect(store.latest, same(initial));
        expect(store.saveCount, 0);
      },
    );

    test(
      'task mismatch rejects selection without changing the project',
      () async {
        final initial = _project(task: CreationTask.optimize);
        final store = _CountingPhotoProjectStore(initial);
        final session = PhotoProjectSession(
          importer: const _FixedPhotoImporter(),
          store: store,
        );
        await session.restore();

        await expectLater(
          session.selectCreationCapability(CreationCapability.cleanupWhite),
          throwsArgumentError,
        );

        expect(session.project, same(initial));
        expect(store.latest, same(initial));
        expect(store.saveCount, 0);
      },
    );

    test(
      'non-editing project rejects selection without changing the project',
      () async {
        final initial = _project(
          task: CreationTask.style,
          flowState: PhotoProjectFlowState.exporting,
        );
        final store = _CountingPhotoProjectStore(initial);
        final session = PhotoProjectSession(
          importer: const _FixedPhotoImporter(),
          store: store,
        );
        await session.restore();

        await expectLater(
          session.selectCreationCapability(CreationCapability.styleOfficial),
          throwsStateError,
        );

        expect(session.project, same(initial));
        expect(store.latest, same(initial));
        expect(store.saveCount, 0);
      },
    );

    test(
      'style selection and apply fail closed without a capability',
      () async {
        final initial = _project(task: CreationTask.style);
        final store = _CountingPhotoProjectStore(initial);
        final session = PhotoProjectSession(
          importer: const _FixedPhotoImporter(),
          store: store,
        );
        await session.restore();
        final recipe = EditRecipe(exposure: 0.2);

        await expectLater(
          session.selectCreationStyle(
            styleId: 'natural',
            styleName: '自然',
            recipe: recipe,
          ),
          throwsStateError,
        );
        await expectLater(
          session.applyCreationStyle(
            styleId: 'natural',
            styleName: '自然',
            recipe: recipe,
            context: EditContext.ios,
          ),
          throwsStateError,
        );

        expect(session.project, same(initial));
        expect(store.latest, same(initial));
        expect(store.saveCount, 0);
      },
    );

    test(
      'text style persists only under the matching explicit capability',
      () async {
        final initial = _project(
          task: CreationTask.style,
          capability: CreationCapability.styleText,
        );
        final store = _CountingPhotoProjectStore(initial);
        final session = PhotoProjectSession(
          importer: const _FixedPhotoImporter(),
          store: store,
        );
        await session.restore();
        final recipe = EditRecipe(
          warmth: 0.05,
          basicEditingRecipe: BasicEditingRecipe(
            filter: PhotoFilter.film,
            filterStrength: 42,
          ),
        );
        final definition = StyleDefinition(
          styleId: 'text-film-v1',
          revision: 1,
          origin: StyleDefinitionOrigin.text,
          title: '温暖的胶片感',
          summary: '根据用户确认的文字生成的本地风格。',
          recipe: recipe,
          sourceText: '温暖的胶片感',
          createdAt: DateTime.utc(2026, 9, 1),
        );

        await session.selectCreationStyle(
          styleId: definition.styleId,
          styleName: definition.title,
          recipe: recipe,
          definition: definition,
        );

        expect(
          session.project?.creationCapability,
          CreationCapability.styleText,
        );
        expect(session.project?.creationStyleDefinition, definition);
        expect(session.project?.creationStyleRecipe, recipe);
        expect(store.saveCount, 1);

        final mismatched = StyleDefinition(
          styleId: 'voice-film-v1',
          revision: 1,
          origin: StyleDefinitionOrigin.voice,
          title: '语音胶片感',
          summary: '根据用户确认的语音转写生成的本地风格。',
          recipe: recipe,
          sourceText: '语音胶片感',
          createdAt: DateTime.utc(2026, 9, 1),
        );
        await expectLater(
          session.selectCreationStyle(
            styleId: mismatched.styleId,
            styleName: mismatched.title,
            recipe: mismatched.recipe,
            definition: mismatched,
          ),
          throwsStateError,
        );
        expect(store.saveCount, 1);
      },
    );

    test(
      'optimize local apply rejects missing or different capabilities',
      () async {
        await _expectLocalResultRejected(
          task: CreationTask.optimize,
          capability: null,
        );
        await _expectLocalResultRejected(
          task: CreationTask.optimize,
          capability: CreationCapability.optimizeAiRepair,
        );
      },
    );

    test(
      'cleanup local apply rejects missing or different capabilities',
      () async {
        await _expectLocalResultRejected(
          task: CreationTask.cleanup,
          capability: null,
        );
        await _expectLocalResultRejected(
          task: CreationTask.cleanup,
          capability: CreationCapability.cleanupBrushRemove,
        );
      },
    );
  });
}

Future<void> _expectLocalResultRejected({
  required CreationTask task,
  required CreationCapability? capability,
}) async {
  final initial = _project(task: task, capability: capability);
  final store = _CountingPhotoProjectStore(initial);
  final session = PhotoProjectSession(
    importer: const _FixedPhotoImporter(),
    store: store,
  );
  await session.restore();

  await expectLater(
    session.applyLocalStaticTaskResult(
      task: task,
      desiredRecipe: EditRecipe(exposure: 0.2),
      resultId: '${task.name}-result',
      resultName: task.name,
      context: EditContext.ios,
    ),
    throwsStateError,
  );

  expect(session.project, same(initial));
  expect(store.latest, same(initial));
  expect(store.saveCount, 0);
}

PhotoProject _project({
  required CreationTask task,
  CreationCapability? capability,
  PhotoProjectFlowState flowState = PhotoProjectFlowState.editing,
}) {
  return PhotoProject(
    id: 'project-${task.name}-${capability?.name ?? 'none'}',
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    photos: const [_photo],
    creationTask: task,
    creationCapability: capability,
    flowState: flowState,
    exportStates: flowState == PhotoProjectFlowState.exporting
        ? const {'photo-1': PhotoExportState.queued}
        : const {},
  );
}

const _photo = ProjectPhoto(
  id: 'photo-1',
  localPath: '/app/media/photo-1.jpg',
  originalName: 'photo-1.jpg',
);

final class _FixedPhotoImporter implements PhotoImporter {
  const _FixedPhotoImporter([this.photos = const []]);

  final List<ProjectPhoto> photos;

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) async {
    return PhotoImportBatch(photos: photos.take(limit).toList());
  }
}

final class _CountingPhotoProjectStore implements PhotoProjectStore {
  _CountingPhotoProjectStore([this.latest]);

  PhotoProject? latest;
  int saveCount = 0;

  @override
  Future<PhotoProject?> loadLatest() async => latest;

  @override
  Future<void> save(PhotoProject project) async {
    saveCount += 1;
    latest = project;
  }
}
