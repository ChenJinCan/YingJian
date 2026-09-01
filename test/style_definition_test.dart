import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/creation/domain/creation_intent.dart';
import 'package:yingjian/features/creation/domain/creation_task.dart';
import 'package:yingjian/features/creation/domain/style_definition.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

void main() {
  group('StyleDefinition', () {
    test('round trips the confirmed local style snapshot', () {
      final definition = _textDefinition();

      final restored = StyleDefinition.fromJson(definition.toJson());

      expect(restored, definition);
      expect(restored.recipe, EditRecipe(warmth: 0.14, clarity: 0.08));
    });

    test(
      'AI redraw freezes normalized visual intent with a stable versioned identity',
      () {
        final first = StyleDefinition.aiRedraw(
          confirmedVisualIntent: '  保留人物身份，\n  改成低饱和电影剧照  ',
          title: 'AI 风格重绘',
          summary: '仅按已确认的视觉意图重绘',
          createdAt: DateTime.utc(2026, 9, 1, 10),
        );
        final equivalent = StyleDefinition.aiRedraw(
          confirmedVisualIntent: '保留人物身份， 改成低饱和电影剧照',
          title: 'AI 风格重绘',
          summary: '仅按已确认的视觉意图重绘',
          createdAt: DateTime.utc(2026, 9, 1, 11),
        );

        expect(first.origin, StyleDefinitionOrigin.aiRedraw);
        expect(first.visualIntent, '保留人物身份， 改成低饱和电影剧照');
        expect(first.sourceText, first.visualIntent);
        expect(first.recipe, EditRecipe.neutral);
        expect(first.styleId, 'ai-redraw-0479f853c91384bd6133c4e5');
        expect(
          first.versionedIdentity,
          'style-definition-v1:ai-redraw-0479f853c91384bd6133c4e5:r1',
        );
        expect(
          first.contentFingerprint,
          'ddafbabba5a62b5d0e6df4b5e310cfb7c92402a1a409b3f20814a0ab657636b0',
        );
        expect(first.versionedIdentity, equivalent.versionedIdentity);
        expect(first.contentFingerprint, equivalent.contentFingerprint);
        expect(StyleDefinition.fromJson(first.toJson()), first);
      },
    );

    test('AI redraw rejects empty, overlong, and hidden control input', () {
      StyleDefinition build(String input) => StyleDefinition.aiRedraw(
        confirmedVisualIntent: input,
        title: 'AI 风格重绘',
        summary: '仅按已确认的视觉意图重绘',
      );

      expect(() => build('  \n\t '), throwsArgumentError);
      expect(
        () => build('a' * (StyleDefinition.maxAiRedrawIntentLength + 1)),
        throwsArgumentError,
      );
      expect(() => build('低饱和\u202E电影感'), throwsArgumentError);
      expect(() => build('低饱和\u0000电影感'), throwsArgumentError);
    });

    test('rejects unbounded identifiers and unsupported provenance', () {
      expect(
        () => StyleDefinition(
          styleId: 'Not-a-stable-id',
          revision: 1,
          origin: StyleDefinitionOrigin.official,
          title: '自然通透',
          summary: '清晰而克制的自然光感',
          recipe: EditRecipe.neutral,
        ),
        throwsArgumentError,
      );
      expect(
        () => StyleDefinition(
          styleId: 'reference-v1',
          revision: 1,
          origin: StyleDefinitionOrigin.reference,
          title: '参考风格',
          summary: '来自参考图的光色方向',
          recipe: EditRecipe.neutral,
        ),
        throwsArgumentError,
      );
      expect(
        () => StyleDefinition(
          styleId: 'partial-mixed-v1',
          revision: 1,
          origin: StyleDefinitionOrigin.mixed,
          title: '不完整混合风格',
          summary: '缺少参考图来源',
          recipe: EditRecipe.neutral,
          sourceText: '暖一点',
        ),
        throwsArgumentError,
      );
      expect(
        () => StyleDefinition.fromJson({
          ..._textDefinition().toJson(),
          'schemaVersion': StyleDefinition.currentSchemaVersion + 1,
        }),
        throwsFormatException,
      );
    });

    test(
      'persists an optional definition without changing legacy snapshots',
      () {
        final definition = _textDefinition();
        final project = _styleProject(
          creationStyleId: definition.styleId,
          creationStyleName: definition.title,
          creationStyleRecipe: definition.recipe,
          creationStyleDefinition: definition,
        );

        final restored = PhotoProject.fromJson(project.toJson());
        final legacy = Map<String, Object?>.from(project.toJson())
          ..['schemaVersion'] = 18
          ..remove('creationStyleDefinition');
        final legacyRestored = PhotoProject.fromJson(legacy);

        expect(restored.creationStyleDefinition, definition);
        expect(restored.creationStyleId, definition.styleId);
        expect(legacyRestored.creationStyleDefinition, isNull);
        expect(legacyRestored.creationStyleRecipe, definition.recipe);
      },
    );

    test('rejects a style definition on an independent motion project', () {
      final definition = _officialDefinition();

      expect(
        () =>
            _styleProject(
              creationStyleId: definition.styleId,
              creationStyleName: definition.title,
              creationStyleRecipe: definition.recipe,
              creationStyleDefinition: definition,
            ).copyWith(
              creationIntent: CreationIntent.motion,
              creationTask: CreationTask.motion,
            ),
        throwsArgumentError,
      );
    });
  });

  group('PhotoProjectSession.selectCreationStyle', () {
    test(
      'stores a matching definition atomically and clears it for legacy selection',
      () async {
        final definition = _officialDefinition();
        final store = _MemoryStore(_styleProject());
        final session = PhotoProjectSession(
          importer: const _NoopImporter(),
          store: store,
          creationIntent: CreationIntent.apply,
          creationTask: CreationTask.style,
          now: () => DateTime.utc(2026, 9, 1, 12),
        );
        await session.restore();
        await session.selectCreationCapability(
          CreationCapability.styleOfficial,
        );

        await session.selectCreationStyle(
          styleId: definition.styleId,
          styleName: definition.title,
          recipe: definition.recipe,
          definition: definition,
        );

        expect(session.project!.creationStyleDefinition, definition);
        expect(store.project, session.project);
        expect(
          PhotoProject.fromJson(
            store.project!.toJson(),
          ).creationStyleDefinition,
          definition,
        );

        await session.selectCreationStyle(
          styleId: 'natural',
          styleName: '自然',
          recipe: EditRecipe.neutral,
        );

        expect(session.project!.creationStyleDefinition, isNull);
        expect(session.project!.creationStyleId, 'natural');
      },
    );

    test(
      'rejects a definition that disagrees with its selected recipe',
      () async {
        final definition = _officialDefinition();
        final session = PhotoProjectSession(
          importer: const _NoopImporter(),
          store: _MemoryStore(_styleProject()),
          creationTask: CreationTask.style,
        );
        await session.restore();
        await session.selectCreationCapability(
          CreationCapability.styleOfficial,
        );

        await expectLater(
          session.selectCreationStyle(
            styleId: definition.styleId,
            recipe: EditRecipe.neutral,
            definition: definition,
          ),
          throwsArgumentError,
        );
        expect(session.project!.creationStyleDefinition, isNull);
      },
    );

    test(
      'keeps the selected definition after its static result is committed',
      () async {
        final definition = _officialDefinition();
        final store = _MemoryStore(_styleProject());
        final session = PhotoProjectSession(
          importer: const _NoopImporter(),
          store: store,
          creationTask: CreationTask.style,
        );
        await session.restore();
        await session.selectCreationCapability(
          CreationCapability.styleOfficial,
        );
        await session.selectCreationStyle(
          styleId: definition.styleId,
          recipe: definition.recipe,
          definition: definition,
        );

        await session.applyCreationStyle(
          styleId: definition.styleId,
          recipe: definition.recipe,
          context: const EditContext(
            platform: EditPlatform.ios,
            photoIds: {'photo-1'},
            applicability: {'photo'},
          ),
        );

        expect(session.project!.creationStyleDefinition, definition);
        expect(session.project!.currentStaticStyleResult, isNotNull);
        expect(store.project!.creationStyleDefinition, definition);
      },
    );
  });
}

StyleDefinition _textDefinition() => StyleDefinition(
  styleId: 'text-warm-evening-v1',
  revision: 1,
  origin: StyleDefinitionOrigin.text,
  title: '暖调傍晚',
  summary: '柔和暖光与清晰细节',
  recipe: EditRecipe(warmth: 0.14, clarity: 0.08),
  createdAt: DateTime.utc(2026, 9, 1, 10),
  sourceText: '想要柔和一点的暖调傍晚感',
);

StyleDefinition _officialDefinition() => StyleDefinition(
  styleId: 'soft-light',
  revision: 1,
  origin: StyleDefinitionOrigin.official,
  title: '柔光',
  summary: '固定且可复现的本地风格',
  recipe: EditRecipe(warmth: 0.14, clarity: 0.08),
  createdAt: DateTime.utc(2026, 9, 1, 10),
);

PhotoProject _styleProject({
  String? creationStyleId,
  String? creationStyleName,
  EditRecipe? creationStyleRecipe,
  StyleDefinition? creationStyleDefinition,
}) => PhotoProject(
  id: 'style-definition-project',
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  photos: const [
    ProjectPhoto(
      id: 'photo-1',
      localPath: '/app/media/photo-1.jpg',
      originalName: 'photo.jpg',
    ),
  ],
  creationIntent: CreationIntent.apply,
  creationTask: CreationTask.style,
  creationStyleId: creationStyleId,
  creationStyleName: creationStyleName,
  creationStyleRecipe: creationStyleRecipe,
  creationStyleDefinition: creationStyleDefinition,
);

final class _MemoryStore implements PhotoProjectStore {
  _MemoryStore(this.project);

  PhotoProject? project;

  @override
  Future<PhotoProject?> loadLatest() async => project;

  @override
  Future<void> save(PhotoProject value) async {
    project = value;
  }
}

final class _NoopImporter implements PhotoImporter {
  const _NoopImporter();

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) async =>
      const PhotoImportBatch();
}
