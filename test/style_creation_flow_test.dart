import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/creation/domain/creation_intent.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

import 'support/test_services.dart';

void main() {
  test(
    'creation intent survives persistence and old projects migrate safely',
    () {
      final project = PhotoProject(
        id: 'motion-project',
        createdAt: DateTime.utc(2026, 8, 31),
        updatedAt: DateTime.utc(2026, 8, 31),
        photos: [_fixturePhoto('persisted-motion')],
        creationIntent: CreationIntent.motion,
        creationStyleId: 'breeze',
        creationStyleName: '轻风',
        creationStyleRecipe: EditRecipe(
          basicEditingRecipe: BasicEditingRecipe(
            filter: PhotoFilter.coolAir,
            filterStrength: 30,
          ),
        ),
        creationResult: StaticStyleResultIdentity(
          sourcePhotoId: 'persisted-motion',
          editStateVersion: 0,
          styleId: 'breeze',
          recipe: EditRecipe(
            basicEditingRecipe: BasicEditingRecipe(
              filter: PhotoFilter.coolAir,
              filterStrength: 30,
            ),
          ),
        ),
      );

      final restored = PhotoProject.fromJson(project.toJson());
      expect(restored.creationIntent, CreationIntent.motion);
      expect(restored.creationStyleId, 'breeze');
      expect(restored.creationStyleName, '轻风');
      expect(restored.creationStyleRecipe, project.creationStyleRecipe);
      expect(restored.creationResult, project.creationResult);

      final legacyJson = Map<String, Object?>.from(project.toJson())
        ..['schemaVersion'] = 14
        ..remove('creationIntent');
      final legacy = PhotoProject.fromJson(legacyJson);
      expect(legacy.creationIntent, CreationIntent.apply);
      expect(legacy.creationResult, isNull);

      final exportedMotion = PhotoProject(
        id: 'exported-motion-project',
        createdAt: DateTime.utc(2026, 8, 31),
        updatedAt: DateTime.utc(2026, 8, 31),
        photos: [_fixturePhoto('exported-motion')],
        creationIntent: CreationIntent.motion,
        creationStyleId: 'breeze',
        creationStyleRecipe: EditRecipe.neutral,
        flowState: PhotoProjectFlowState.exported,
        exportStates: const {'exported-motion': PhotoExportState.saved},
        lastSuccessfulExportEditStateVersion: 0,
      );
      final legacyMotionJson = Map<String, Object?>.from(
        exportedMotion.toJson(),
      )..['schemaVersion'] = 15;
      final restoredMotion = PhotoProject.fromJson(legacyMotionJson);
      expect(restoredMotion.creationIntent, CreationIntent.motion);
      expect(restoredMotion.creationResult, isNull);
      expect(restoredMotion.creationResultActive, isFalse);
      expect(restoredMotion.flowState, PhotoProjectFlowState.exported);
    },
  );

  testWidgets('creation surfaces keep their intentional dark appearance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app.locale': 'zh',
      'app.theme_mode': ThemeMode.light.name,
    });
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('light-mode-photo')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('home-page'))),
      ).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('apply-style-workspace'))),
      ).brightness,
      Brightness.dark,
    );
  });

  testWidgets('default style is frozen before the user applies it', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('default-style')]),
        photoProjectStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();

    expect(store.project!.creationStyleId, 'natural');
    expect(store.project!.creationStyleRecipe, isNotNull);
  });

  testWidgets('a style cannot be applied before its preview succeeds', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final previewRenderer = FakePhotoPreviewRenderer.unsupported();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          _fixturePhoto('unavailable-style-preview'),
        ]),
        photoProjectStore: store,
        photoPreviewRenderer: previewRenderer,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();

    final apply = tester.widget<FilledButton>(
      find.byKey(const ValueKey('apply-style-primary-action')),
    );
    expect(apply.onPressed, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('apply-style-primary-action')),
        matching: find.text('应用风格'),
      ),
      findsOneWidget,
    );
    expect(find.text('当前效果预览暂不可用，请重试。'), findsOneWidget);
    final previousAttempts = previewRenderer.creates.length;
    await tester.tap(find.byKey(const ValueKey('style-preview-retry')));
    await tester.pumpAndSettle();
    expect(previewRenderer.creates.length, greaterThan(previousAttempts));
    expect(store.project!.currentStaticStyleResult, isNull);
  });

  testWidgets('legacy custom recipe is restored without visual replacement', (
    tester,
  ) async {
    final customRecipe = EditRecipe(warmth: 0.07, saturation: -0.03);
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'legacy-custom-look',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: [_fixturePhoto('legacy-custom-photo')],
        recipe: customRecipe,
      ),
    );
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    final resume = find.byKey(const ValueKey('home-resume-project'));
    await tester.ensureVisible(resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();

    expect(
      tester.widget<NativePhotoPreview>(find.byType(NativePhotoPreview)).recipe,
      customRecipe,
    );
    expect(store.project!.creationStyleId, 'saved-custom');
    expect(store.project!.creationStyleRecipe, customRecipe);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-style-name')))
          .data,
      '已保存风格',
    );
  });

  for (final legacySchema in [11, 13, 14]) {
    testWidgets(
      'schema $legacySchema exported single-photo project restores its static result',
      (tester) async {
        final photo = _fixturePhoto('legacy-exported-photo');
        final recipe = EditRecipe(
          exposure: 0.02,
          basicEditingRecipe: BasicEditingRecipe(
            filter: PhotoFilter.clean,
            filterStrength: 42,
          ),
        );
        final current = PhotoProject(
          id: 'legacy-exported-project',
          createdAt: DateTime.utc(2026, 8, 20),
          updatedAt: DateTime.utc(2026, 8, 20),
          photos: [photo],
          recipe: recipe,
        );
        final persistedJson =
            current
                .copyWith(
                  flowState: PhotoProjectFlowState.exported,
                  exportStates: {photo.id: PhotoExportState.saved},
                  lastSuccessfulExportEditStateVersion:
                      current.editStateVersion,
                )
                .toJson()
              ..['schemaVersion'] = legacySchema;
        if (legacySchema < 14) {
          persistedJson.remove('lastSuccessfulExportEditStateVersion');
        }
        final store = MemoryPhotoProjectStore(
          PhotoProject.fromJson(persistedJson),
        );
        final settings = await _settings();
        await tester.pumpWidget(
          buildTestApp(
            settings,
            photoProjectStore: store,
            metaOpCapabilities: iosMetaOpCapabilities,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('home-resume-project')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('apply-style-workspace')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('style-static-result-controls')),
          findsOneWidget,
        );
        expect(find.text('已保存到系统相册'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('style-workspace-retry')),
          findsNothing,
        );
      },
    );
  }

  testWidgets('an exported project without a valid result resumes editing', (
    tester,
  ) async {
    final photo = _fixturePhoto('failed-exported-photo');
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'failed-exported-project',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: [photo],
        flowState: PhotoProjectFlowState.exported,
        exportStates: {photo.id: PhotoExportState.failed},
      ),
    );
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-resume-project')));
    await tester.pumpAndSettle();

    expect(store.project!.flowState, PhotoProjectFlowState.editing);
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('apply-style-primary-action')),
      findsOneWidget,
    );
  });

  testWidgets('style workspace preserves a legacy multi-photo project', (
    tester,
  ) async {
    final first = _fixturePhoto('legacy-first');
    final focused = _fixturePhoto('legacy-focused');
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'legacy-multi-photo',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: [first, focused],
        focusPhotoId: focused.id,
      ),
    );
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-resume-project')));
    await tester.pumpAndSettle();

    expect(store.project!.photos, [first, focused]);
    expect(find.byKey(const ValueKey('style-workspace-retry')), findsOneWidget);
  });

  testWidgets('style workspace recovers an interrupted static result save', (
    tester,
  ) async {
    final photo = _fixturePhoto('interrupted-static-result');
    final recipe = EditRecipe(
      exposure: 0.02,
      basicEditingRecipe: BasicEditingRecipe(
        filter: PhotoFilter.clean,
        filterStrength: 42,
      ),
    );
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'interrupted-static-project',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: [photo],
        recipe: recipe,
        creationStyleId: 'natural',
        creationStyleRecipe: recipe,
        creationResult: StaticStyleResultIdentity(
          sourcePhotoId: photo.id,
          editStateVersion: 0,
          styleId: 'natural',
          recipe: recipe,
        ),
        flowState: PhotoProjectFlowState.exporting,
        exportStates: {photo.id: PhotoExportState.running},
      ),
    );
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-resume-project')));
    await tester.pumpAndSettle();

    expect(store.project!.flowState, PhotoProjectFlowState.exported);
    expect(store.project!.exportStates[photo.id], PhotoExportState.cancelled);
    expect(find.byKey(const ValueKey('style-result-retry')), findsOneWidget);
  });

  testWidgets('creation flow remains operable at maximum accessibility text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3.2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('large-type')]),
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final entry = find.byKey(const ValueKey('home-apply-style'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    final action = find.byKey(const ValueKey('apply-style-primary-action'));
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(action, findsOneWidget);
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(action);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('style-result-save'));
    await tester.ensureVisible(save);
    await tester.pump();
    expect(save, findsOneWidget);
    expect(find.text('换个风格'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion confirmation stays reachable with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('motion-large-type')]),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('home-motion'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('motion-style-primary-action'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final close = find.byKey(const ValueKey('motion-confirmation-close'));
    await tester.ensureVisible(close);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('motion-confirmation-sheet')),
      findsNothing,
    );
  });

  testWidgets(
    'home chooses image application before import and opens its workspace',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final source = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      final photo = ProjectPhoto(
        id: 'apply-photo',
        localPath: source.path,
        originalName: 'portrait.png',
      );
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();

      await tester.pumpWidget(
        buildTestApp(settings, photoImporter: FakePhotoImporter([photo])),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-apply-style')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-motion')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-start-editing')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('home-apply-style')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('apply-style-workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('style-workspace-source-photo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('apply-style-primary-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('motion-style-primary-action')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('editor-page')), findsNothing);
    },
  );

  testWidgets(
    'home chooses motion before import and opens only the motion workspace',
    (tester) async {
      final photo = _fixturePhoto('motion-photo');
      final store = MemoryPhotoProjectStore();
      final settings = await _settings();

      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([photo]),
          photoProjectStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-motion')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('motion-style-workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('motion-style-primary-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('apply-style-primary-action')),
        findsNothing,
      );
      expect(store.project?.creationIntent, CreationIntent.motion);
    },
  );

  testWidgets('canceling a selected task does not create an empty creation', (
    tester,
  ) async {
    final importer = _ControlledImporter();
    final store = MemoryPhotoProjectStore();
    final settings = await _settings();

    await tester.pumpWidget(
      buildTestApp(settings, photoImporter: importer, photoProjectStore: store),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-motion')));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byKey(const ValueKey('home-motion-preparing')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-apply-preparing')), findsNothing);

    final cancel = find.byKey(const ValueKey('home-cancel-import'));
    await tester.ensureVisible(cancel);
    await tester.pump();
    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('motion-style-workspace')), findsNothing);
    expect(store.project, isNull);
    expect(importer.cancelCount, 1);
  });

  testWidgets('canceling a new task restores the previous active draft', (
    tester,
  ) async {
    final previous = PhotoProject(
      id: 'previous-draft',
      createdAt: DateTime.utc(2026, 8, 30),
      updatedAt: DateTime.utc(2026, 8, 30),
      photos: [_fixturePhoto('previous-photo')],
    );
    final store = MemoryPhotoProjectStore(previous);
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter(),
        photoProjectStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-motion')));
    await tester.pumpAndSettle();

    expect((await store.loadLatest())?.id, previous.id);
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
  });

  testWidgets('a native error after cancel remains a quiet cancellation', (
    tester,
  ) async {
    final importer = _ErrorAfterCancelImporter();
    final settings = await _settings();
    await tester.pumpWidget(buildTestApp(settings, photoImporter: importer));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.byKey(const ValueKey('home-cancel-import')));
    await tester.pumpAndSettle();

    expect(find.text('照片导入失败，请重试。'), findsNothing);
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
  });

  testWidgets('apply style commits the selected official style locally', (
    tester,
  ) async {
    final photo = _fixturePhoto('styled-photo');
    final store = MemoryPhotoProjectStore();
    final previewRenderer = FakePhotoPreviewRenderer.supported();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([photo]),
        photoProjectStore: store,
        photoPreviewRenderer: previewRenderer,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();

    final beforeSelection = store.project!;
    final beforeRecipe = beforeSelection.effectiveRecipeFor(photo.id);
    final beforeVersion = beforeSelection.editStateVersion;
    final beforeUndoCount = beforeSelection.undoHistory.length;

    await tester.tap(find.byKey(const ValueKey('style-option-soft-light')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-style-name')))
          .data,
      '柔光',
    );
    expect(previewRenderer.updates, isNotEmpty);
    expect(
      previewRenderer.updates.last.toPlatformArguments(),
      isNot(previewRenderer.creates.first.toPlatformArguments()),
    );
    expect(store.project!.effectiveRecipeFor(photo.id), beforeRecipe);
    expect(store.project!.editStateVersion, beforeVersion);
    expect(store.project!.undoHistory, hasLength(beforeUndoCount));
    expect(store.project!.creationStyleId, 'soft-light');

    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();

    expect(find.text('风格已应用'), findsOneWidget);
    final expected = EditRecipe(
      exposure: 0.03,
      basicEditingRecipe: BasicEditingRecipe(
        filter: PhotoFilter.portrait,
        filterStrength: 38,
      ),
    );
    expect(store.project!.effectiveRecipeFor(photo.id), expected);
    expect(store.project!.editStateVersion, beforeVersion + 1);
    expect(store.project!.undoHistory, hasLength(beforeUndoCount + 1));
    expect(
      store.project!.currentStaticStyleResult,
      StaticStyleResultIdentity(
        sourcePhotoId: photo.id,
        editStateVersion: beforeVersion + 1,
        styleId: 'soft-light',
        recipe: expected,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('style-workspace-close')));
    await tester.pumpAndSettle();
    await tester.pump();
    final resume = find.byKey(const ValueKey('home-resume-project'));
    await tester.ensureVisible(resume);
    await tester.pumpAndSettle();
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-style-name')))
          .data,
      '柔光',
    );
    expect(
      find.byKey(const ValueKey('style-static-result-controls')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('style-result-change-style')));
    await tester.pumpAndSettle();
    expect(store.project!.currentStaticStyleResult, isNull);
    expect(store.project!.recoverableStaticStyleResult, isNotNull);
    await tester.tap(find.byKey(const ValueKey('style-option-natural')));
    await tester.pumpAndSettle();
    expect(store.project!.currentStaticStyleResult, isNull);
    await tester.tap(find.byKey(const ValueKey('style-workspace-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-resume-project')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('style-static-result-controls')),
      findsNothing,
    );
    final restoreResult = find.byKey(
      const ValueKey('style-restore-previous-result'),
    );
    await tester.ensureVisible(restoreResult);
    await tester.tap(restoreResult);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('style-static-result-controls')),
      findsOneWidget,
    );
    expect(store.project!.currentStaticStyleResult?.styleId, 'soft-light');
  });

  testWidgets('official styles preserve an existing draft non-style edits', (
    tester,
  ) async {
    final crop = CropGeometry(left: 0.1, top: 0.05, right: 0.9, bottom: 0.95);
    final legacyRecipe = EditRecipe(crop: crop);
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'legacy-non-style-draft',
        createdAt: DateTime.utc(2026, 8, 30),
        updatedAt: DateTime.utc(2026, 8, 31),
        photos: [_fixturePhoto('legacy-non-style-photo')],
        recipe: legacyRecipe,
      ),
    );
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-resume-project')));
    await tester.pumpAndSettle();

    final preview = tester.widget<NativePhotoPreview>(
      find.byType(NativePhotoPreview),
    );
    expect(preview.recipe.crop, crop);

    await tester.tap(find.byKey(const ValueKey('style-option-soft-light')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NativePhotoPreview>(find.byType(NativePhotoPreview))
          .recipe
          .crop,
      crop,
    );
    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();

    final applied = store.project!.effectiveRecipeFor(
      store.project!.photos.single.id,
    );
    expect(applied.crop, crop);
    expect(applied.basicEditingRecipe.filter, PhotoFilter.portrait);
    expect(store.project!.currentStaticStyleResult, isNotNull);
  });

  testWidgets('failed style application publishes neither pixels nor result', (
    tester,
  ) async {
    final photo = _fixturePhoto('atomic-style-failure');
    final store = _FailingCreationResultStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([photo]),
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-option-soft-light')));
    await tester.pumpAndSettle();
    final before = store.project!;

    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();

    expect(store.project!.editStateVersion, before.editStateVersion);
    expect(store.project!.effectiveRecipeFor(photo.id), EditRecipe.neutral);
    expect(store.project!.currentStaticStyleResult, isNull);
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('style-static-result-controls')),
      findsNothing,
    );
  });

  testWidgets(
    'applied style exports the exact static result from the production flow',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final photo = _fixturePhoto('static-result-photo');
      final store = MemoryPhotoProjectStore();
      final exporter = FakePhotoExporter();
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([photo]),
          photoProjectStore: store,
          photoExporter: exporter,
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-apply-style')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-option-soft-light')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('apply-style-primary-action')),
      );
      await tester.pumpAndSettle();

      final save = find.byKey(const ValueKey('style-result-save'));
      expect(save, findsOneWidget);
      expect(find.text('换个风格'), findsOneWidget);
      expect(find.byKey(const ValueKey('style-options')), findsNothing);
      expect(find.byKey(const ValueKey('style-ai-entry')), findsNothing);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('style-result-status')))
            .label,
        '风格已应用',
      );
      final previewSemantics = tester
          .getSemantics(
            find.byKey(const ValueKey('style-workspace-source-photo')),
          )
          .label;
      expect(previewSemantics, contains('照片预览区域'));
      expect(previewSemantics, contains('柔光'));
      expect(previewSemantics, contains('风格已应用'));
      final close = find.byKey(const ValueKey('style-workspace-close'));
      expect(close, findsOneWidget);
      expect(find.byKey(const ValueKey('style-workspace-back')), findsNothing);
      expect(
        tester.widget<IconButton>(close).tooltip,
        MaterialLocalizations.of(tester.element(close)).closeButtonTooltip,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(exporter.exportedPhoto, photo);
      expect(
        exporter.exportedRecipe,
        store.project!.effectiveRecipeFor(photo.id),
      );
      expect(store.project!.exportStates[photo.id], PhotoExportState.saved);
      expect(find.text('已保存到系统相册'), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-page')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('style-workspace-close')));
      await tester.pumpAndSettle();
      final resume = find.byKey(const ValueKey('home-resume-project'));
      await tester.ensureVisible(resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(find.text('已保存到系统相册'), findsOneWidget);
      expect(find.byKey(const ValueKey('style-result-save')), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('reapplying the same saved style preserves its saved status', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          _fixturePhoto('reapply-saved-style'),
        ]),
        photoProjectStore: store,
        photoExporter: FakePhotoExporter(),
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-result-save')));
    await tester.pumpAndSettle();
    expect(find.text('已保存到系统相册'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('style-result-change-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();

    expect(find.text('已保存到系统相册'), findsOneWidget);
    expect(find.byKey(const ValueKey('style-result-save')), findsNothing);
  });

  testWidgets(
    'saved static result shares without leaving the style workspace',
    (tester) async {
      final sharer = FakePhotoSharer();
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([
            _fixturePhoto('share-static-result'),
          ]),
          photoExporter: FakePhotoExporter(),
          photoSharer: sharer,
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-apply-style')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('apply-style-primary-action')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-result-save')));
      await tester.pumpAndSettle();

      final share = find.byKey(const ValueKey('style-result-share'));
      expect(share, findsOneWidget);
      await tester.tap(share);
      await tester.pumpAndSettle();

      expect(sharer.sharedPaths, ['/tmp/Yingjian_fixture.jpg']);
      expect(find.text('已通过系统分享完成操作'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('apply-style-workspace')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Android hides the unavailable static result share action', (
    tester,
  ) async {
    final photo = _fixturePhoto('android-static-result');
    final recipe = EditRecipe(exposure: 0.04);
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'android-static-project',
        createdAt: DateTime.utc(2026, 8, 31),
        updatedAt: DateTime.utc(2026, 8, 31),
        photos: [photo],
        recipe: recipe,
        creationStyleId: 'saved-custom',
        creationStyleRecipe: recipe,
        creationResult: StaticStyleResultIdentity(
          sourcePhotoId: photo.id,
          editStateVersion: 0,
          styleId: 'saved-custom',
          recipe: recipe,
        ),
      ),
    );
    final settings = await _settings();
    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-resume-project')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('style-static-result-controls')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('style-result-share')), findsNothing);
  });

  testWidgets(
    'applied result shares independently before save and after cold restore',
    (tester) async {
      final photo = _fixturePhoto('independent-share-result');
      final store = MemoryPhotoProjectStore();
      final exporter = _PreparingPhotoExporter();
      final sharer = FakePhotoSharer();
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([photo]),
          photoProjectStore: store,
          photoExporter: exporter,
          photoSharer: sharer,
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-apply-style')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('apply-style-primary-action')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-result-save')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('style-result-share')));
      await tester.pumpAndSettle();

      expect(exporter.exportCalls, 0);
      expect(exporter.preparedPhotos, [photo]);
      expect(exporter.preparedRecipes, [store.project!.creationStyleRecipe]);
      expect(sharer.sharedPaths, ['/tmp/Yingjian_prepared-1.jpg']);
      expect(store.project!.flowState, PhotoProjectFlowState.editing);
      expect(store.project!.exportStates[photo.id], PhotoExportState.notQueued);

      await tester.tap(find.byKey(const ValueKey('style-workspace-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-resume-project')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-result-share')));
      await tester.pumpAndSettle();

      expect(exporter.preparedPhotos, [photo, photo]);
      expect(sharer.sharedPaths, ['/tmp/Yingjian_prepared-2.jpg']);
    },
  );

  testWidgets('a failed share retry prepares a fresh result file', (
    tester,
  ) async {
    final exporter = _PreparingPhotoExporter();
    final sharer = _FailFirstPhotoSharer();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          _fixturePhoto('failed-share-retry-result'),
        ]),
        photoExporter: exporter,
        photoSharer: sharer,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();

    final share = find.byKey(const ValueKey('style-result-share'));
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(sharer.sharedAttempts, [
      ['/tmp/Yingjian_prepared-1.jpg'],
    ]);

    await tester.tap(share);
    await tester.pumpAndSettle();

    expect(exporter.preparedPhotos, hasLength(2));
    expect(sharer.sharedAttempts, [
      ['/tmp/Yingjian_prepared-1.jpg'],
      ['/tmp/Yingjian_prepared-2.jpg'],
    ]);
  });

  testWidgets('share preparation can be canceled without losing the result', (
    tester,
  ) async {
    final exporter = _ControlledPreparingPhotoExporter();
    final store = MemoryPhotoProjectStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          _fixturePhoto('cancel-share-preparation'),
        ]),
        photoProjectStore: store,
        photoExporter: exporter,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('style-result-share')));
    await exporter.started.future;
    await tester.pump();
    expect(find.text('正在准备分享…'), findsWidgets);
    expect(
      find.byKey(const ValueKey('style-result-cancel-preparation')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('style-result-cancel-preparation')),
    );
    await tester.pumpAndSettle();

    expect(exporter.cancelCount, 1);
    expect(store.project!.currentStaticStyleResult, isNotNull);
    expect(store.project!.flowState, PhotoProjectFlowState.editing);
    expect(find.byKey(const ValueKey('style-result-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('style-result-share')), findsOneWidget);
    expect(find.text('导出失败'), findsNothing);
  });

  testWidgets(
    'photo permission denial preserves the result and offers system settings',
    (tester) async {
      final exporter = _DeniedPhotoExporter();
      final store = MemoryPhotoProjectStore();
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([
            _fixturePhoto('permission-static-result'),
          ]),
          photoProjectStore: store,
          photoExporter: exporter,
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-apply-style')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('apply-style-primary-action')),
      );
      await tester.pumpAndSettle();
      final appliedRecipe = store.project!.sharedStyle.recipe;
      await tester.tap(find.byKey(const ValueKey('style-result-save')));
      await tester.pumpAndSettle();

      expect(find.text('映见需要添加照片权限，才能把成片保存到系统相册。'), findsOneWidget);
      expect(exporter.exportCalls, 0);
      await tester.tap(
        find.byKey(const ValueKey('style-export-permission-continue')),
      );
      await tester.pumpAndSettle();

      expect(exporter.exportCalls, 1);
      expect(store.project!.sharedStyle.recipe, appliedRecipe);
      expect(
        store.project!.exportStates.values.single,
        PhotoExportState.failed,
      );
      expect(
        find.byKey(const ValueKey('style-result-open-settings')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('style-workspace-source-photo')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('style-result-open-settings')),
      );
      await tester.pumpAndSettle();
      expect(exporter.openSettingsCalls, 1);
      expect(find.byKey(const ValueKey('style-result-retry')), findsOneWidget);
    },
  );

  testWidgets('static result save retries from the preserved result', (
    tester,
  ) async {
    final exporter = _FailOncePhotoExporter();
    final store = MemoryPhotoProjectStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          _fixturePhoto('retry-static-result'),
        ]),
        photoProjectStore: store,
        photoExporter: exporter,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();
    final appliedRecipe = store.project!.sharedStyle.recipe;
    await tester.tap(find.byKey(const ValueKey('style-result-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('style-result-retry')), findsOneWidget);
    expect(store.project!.sharedStyle.recipe, appliedRecipe);
    expect(store.project!.exportStates.values.single, PhotoExportState.failed);

    await tester.tap(find.byKey(const ValueKey('style-result-retry')));
    await tester.pumpAndSettle();
    expect(exporter.exportCalls, 2);
    expect(store.project!.exportStates.values.single, PhotoExportState.saved);
    expect(find.text('已保存到系统相册'), findsOneWidget);
  });

  testWidgets(
    'static result reports preparation and system photo write stages',
    (tester) async {
      final exporter = _StagedPhotoExporter();
      addTearDown(exporter.dispose);
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([
            _fixturePhoto('staged-static-result'),
          ]),
          photoExporter: exporter,
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-apply-style')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('apply-style-primary-action')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-result-save')));
      await tester.pump();
      await exporter.started.future;

      expect(find.text('正在准备成片…'), findsWidgets);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('style-workspace-close')),
            )
            .onPressed,
        isNull,
      );
      exporter.moveToSystemWrite();
      await tester.pump();
      expect(find.text('正在保存到系统相册…'), findsWidgets);

      exporter.complete();
      await tester.pumpAndSettle();
      expect(find.text('已保存到系统相册'), findsOneWidget);
    },
  );

  testWidgets(
    'canceled static result share stays saved and is cleaned on restyle',
    (tester) async {
      final sharer = FakePhotoSharer(outcome: PhotoShareOutcome.canceled);
      final store = MemoryPhotoProjectStore();
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([
            _fixturePhoto('cancel-share-result'),
          ]),
          photoProjectStore: store,
          photoExporter: FakePhotoExporter(),
          photoSharer: sharer,
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-apply-style')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('apply-style-primary-action')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-result-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-result-share')));
      await tester.pumpAndSettle();

      expect(find.text('已取消分享，成片仍已保存到系统相册'), findsOneWidget);
      expect(find.text('已保存到系统相册'), findsOneWidget);
      expect(store.project!.exportStates.values.single, PhotoExportState.saved);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final changeStyle = find.byKey(
        const ValueKey('style-result-change-style'),
      );
      await tester.ensureVisible(changeStyle);
      await tester.tap(changeStyle);
      await tester.pumpAndSettle();
      expect(sharer.discardedPaths, ['/tmp/Yingjian_fixture.jpg']);
      expect(store.project!.flowState, PhotoProjectFlowState.editing);
      expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    },
  );

  testWidgets('a failed temp cleanup never reuses the previous style result', (
    tester,
  ) async {
    final exporter = _PreparingPhotoExporter();
    final sharer = FakePhotoSharer(
      outcome: PhotoShareOutcome.canceled,
      discardError: StateError('temporary cleanup failed'),
    );
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          _fixturePhoto('failed-cleanup-result'),
        ]),
        photoExporter: exporter,
        photoSharer: sharer,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-result-share')));
    await tester.pumpAndSettle();
    expect(sharer.sharedPaths, ['/tmp/Yingjian_prepared-1.jpg']);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final changeStyle = find.byKey(const ValueKey('style-result-change-style'));
    await tester.ensureVisible(changeStyle);
    await tester.tap(changeStyle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-option-soft-light')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-result-share')));
    await tester.pumpAndSettle();

    expect(exporter.preparedPhotos, hasLength(2));
    expect(sharer.sharedPaths, ['/tmp/Yingjian_prepared-2.jpg']);
  });

  testWidgets(
    'restyle transition locks result actions until persistence settles',
    (tester) async {
      final store = _DelayedRestyleStore();
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([_fixturePhoto('delayed-restyle')]),
          photoProjectStore: store,
          photoExporter: FakePhotoExporter(),
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-apply-style')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('apply-style-primary-action')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-result-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-result-change-style')));
      await store.transitionStarted.future;
      await tester.pump();

      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('style-result-change-style')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('style-result-share')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('style-workspace-close')),
            )
            .onPressed,
        isNull,
      );

      store.completeTransition();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    },
  );

  testWidgets('motion primary action keeps generation behind confirmation', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('motion-confirm')]),
        photoProjectStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-motion')));
    await tester.pumpAndSettle();

    final beforeSelection = store.project!;
    final photoId = beforeSelection.photos.single.id;
    final beforeRecipe = beforeSelection.effectiveRecipeFor(photoId);
    final beforeVersion = beforeSelection.editStateVersion;
    final beforeUndoCount = beforeSelection.undoHistory.length;
    await tester.tap(find.byKey(const ValueKey('style-option-breeze')));
    await tester.pumpAndSettle();
    expect(store.project!.creationStyleId, 'breeze');
    expect(store.project!.effectiveRecipeFor(photoId), beforeRecipe);
    expect(store.project!.editStateVersion, beforeVersion);
    expect(store.project!.undoHistory, hasLength(beforeUndoCount));

    await tester.tap(find.byKey(const ValueKey('motion-style-primary-action')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('motion-confirmation-sheet')),
      findsOneWidget,
    );
    expect(find.text('动态生成服务尚未接入'), findsOneWidget);
    expect(store.project!.effectiveRecipeFor(photoId), beforeRecipe);
    expect(store.project!.editStateVersion, beforeVersion);
    expect(store.project!.undoHistory, hasLength(beforeUndoCount));
  });

  testWidgets('recent motion creation resumes only the motion workspace', (
    tester,
  ) async {
    final project = PhotoProject(
      id: 'persisted-motion',
      createdAt: DateTime.utc(2026, 8, 31),
      updatedAt: DateTime.utc(2026, 8, 31),
      photos: [_fixturePhoto('persisted-motion-photo')],
      creationIntent: CreationIntent.motion,
      creationStyleId: 'breeze',
    );
    final settings = await _settings();

    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: MemoryPhotoProjectStore(project),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-resume-project')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('motion-style-workspace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('motion-style-primary-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('apply-style-primary-action')),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-style-name')))
          .data,
      '微风',
    );
  });

  testWidgets('recent creation route restores the tapped immutable project', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final expectedRecipe = EditRecipe(
      exposure: 0.03,
      basicEditingRecipe: BasicEditingRecipe(
        filter: PhotoFilter.portrait,
        filterStrength: 38,
      ),
    );
    PhotoProject project({
      required String id,
      required String photoId,
      required DateTime updatedAt,
      String? styleId,
      EditRecipe? styleRecipe,
    }) => PhotoProject(
      id: id,
      createdAt: updatedAt,
      updatedAt: updatedAt,
      photos: [_fixturePhoto(photoId)],
      creationStyleId: styleId,
      creationStyleRecipe: styleRecipe,
    );
    final selected = project(
      id: 'selected-draft',
      photoId: 'selected-photo',
      updatedAt: DateTime.utc(2026, 8, 30),
      styleId: 'soft-light',
      styleRecipe: expectedRecipe,
    );
    final misleadingLatest = project(
      id: 'latest-draft',
      photoId: 'latest-photo',
      updatedAt: DateTime.utc(2026, 8, 31),
    );
    final store = _MisleadingLatestStore([misleadingLatest, selected]);
    final settings = await _settings();

    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();
    final selectedCard = find.byKey(
      const ValueKey('home-draft-selected-draft'),
    );
    await tester.ensureVisible(selectedCard);
    await tester.pumpAndSettle();
    await tester.tap(selectedCard);
    await tester.pumpAndSettle();

    expect(store.loadedProjectIds, ['selected-draft']);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-style-name')))
          .data,
      '柔光',
    );
  });

  testWidgets('project actions lock while a confirmed deletion is pending', (
    tester,
  ) async {
    final project = PhotoProject(
      id: 'delete-pending',
      createdAt: DateTime.utc(2026, 8, 31),
      updatedAt: DateTime.utc(2026, 8, 31),
      photos: [_fixturePhoto('delete-pending-photo')],
    );
    final store = _DelayedDeleteStore(project);
    final settings = await _settings();
    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();

    final delete = find.byKey(
      const ValueKey('home-delete-draft-delete-pending'),
    );
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-confirm-delete-draft')));
    await tester.pump();
    await store.deleteStarted.future;
    await tester.pump();

    expect(tester.widget<IconButton>(delete).onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey('home-featured-draft-delete-pending')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('apply-style-workspace')), findsNothing);
    expect(store.deleteCalls, 1);

    store.completeDelete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('home-featured-draft-delete-pending')),
      findsNothing,
    );
  });

  testWidgets('restored official style keeps its persisted recipe version', (
    tester,
  ) async {
    final persistedRecipe = EditRecipe(
      exposure: 0.01,
      basicEditingRecipe: BasicEditingRecipe(
        filter: PhotoFilter.portrait,
        filterStrength: 20,
      ),
    );
    final project = PhotoProject(
      id: 'versioned-style',
      createdAt: DateTime.utc(2026, 8, 31),
      updatedAt: DateTime.utc(2026, 8, 31),
      photos: [_fixturePhoto('versioned-style-photo')],
      recipe: persistedRecipe,
      creationStyleId: 'soft-light',
      creationStyleRecipe: persistedRecipe,
    );
    final settings = await _settings();

    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: MemoryPhotoProjectStore(project),
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    final resume = find.byKey(const ValueKey('home-resume-project'));
    await tester.ensureVisible(resume);
    await tester.pumpAndSettle();
    await tester.tap(resume);
    await tester.pumpAndSettle();

    expect(
      tester.widget<NativePhotoPreview>(find.byType(NativePhotoPreview)).recipe,
      persistedRecipe,
    );
    expect(find.text('风格已应用'), findsNothing);
    expect(
      find.byKey(const ValueKey('apply-style-primary-action')),
      findsOneWidget,
    );
  });

  testWidgets('AI style starts from the latest applied recipe', (tester) async {
    final store = MemoryPhotoProjectStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('ai-current-state')]),
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-option-warm-sun')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-style-primary-action')));
    await tester.pumpAndSettle();
    expect(store.project!.recipe.warmth, closeTo(0.04, 0.0001));

    await tester.tap(find.byKey(const ValueKey('style-result-change-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-ai-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-style-prompt')),
      '暖一点',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-style-define')));
    await tester.pumpAndSettle();

    expect(store.project!.creationStyleRecipe!.warmth, closeTo(0.16, 0.0001));
  });

  testWidgets('failed AI style save restores the visible persisted style', (
    tester,
  ) async {
    final store = _FailingAiStyleStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('ai-save-failure')]),
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();
    expect(store.project!.creationStyleId, 'natural');

    await tester.tap(find.byKey(const ValueKey('style-ai-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-style-prompt')),
      '电影感',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-style-define')));
    await tester.pumpAndSettle();

    expect(store.project!.creationStyleId, 'natural');
    expect(find.byKey(const ValueKey('style-option-ai-custom')), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-style-name')))
          .data,
      '自然',
    );
  });

  testWidgets('redefining the AI style persists the newest recipe', (
    tester,
  ) async {
    final photo = _fixturePhoto('ai-style-photo');
    final store = MemoryPhotoProjectStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([photo]),
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();

    Future<void> define(String prompt) async {
      await tester.tap(find.byKey(const ValueKey('style-ai-entry')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-style-prompt')),
        prompt,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ai-style-define')));
      await tester.pumpAndSettle();
    }

    await define('电影感一点');
    final firstRecipe = store.project!.creationStyleRecipe;
    expect(store.project!.creationStyleId, 'ai-custom');
    expect(store.project!.creationStyleName, '电影感一点');
    expect(firstRecipe, isNotNull);

    await define('暖一点');
    final latestRecipe = store.project!.creationStyleRecipe;
    expect(latestRecipe, isNot(firstRecipe));
    expect(store.project!.creationStyleId, 'ai-custom');
    expect(store.project!.creationStyleName, '暖一点');

    await tester.tap(find.byKey(const ValueKey('style-workspace-back')));
    await tester.pumpAndSettle();
    final resume = find.byKey(const ValueKey('home-resume-project'));
    await tester.ensureVisible(resume);
    await tester.pumpAndSettle();
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NativePhotoPreview>(find.byType(NativePhotoPreview)).recipe,
      latestRecipe,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-style-name')))
          .data,
      '暖一点',
    );
  });
}

Future<AppSettings> _settings() async {
  SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
  return AppSettings.load();
}

ProjectPhoto _fixturePhoto(String id) => ProjectPhoto(
  id: id,
  localPath:
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
  originalName: '$id.png',
);

final class _DeniedPhotoExporter
    implements
        PhotoExporter,
        PhotoLibraryPermissionAwareExporter,
        PhotoLibrarySettingsOpener {
  int exportCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    exportCalls += 1;
    throw PlatformException(code: 'photoAccessDenied');
  }

  @override
  Future<void> openPhotoLibrarySettings() async {
    openSettingsCalls += 1;
  }
}

final class _FailOncePhotoExporter implements PhotoExporter {
  int exportCalls = 0;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    exportCalls += 1;
    if (exportCalls == 1) throw StateError('fixture export failure');
    return const ExportedPhoto(
      assetId: 'asset-retry',
      width: 4032,
      height: 3024,
      sharePath: '/tmp/Yingjian_retry.jpg',
    );
  }
}

final class _StagedPhotoExporter
    implements PhotoExporter, PhotoExportStageAware {
  final Completer<void> started = Completer<void>();
  final Completer<ExportedPhoto> _result = Completer<ExportedPhoto>();
  final ValueNotifier<PhotoExportStage> _stage = ValueNotifier(
    PhotoExportStage.preparing,
  );

  @override
  ValueListenable<PhotoExportStage> get stage => _stage;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) {
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  void moveToSystemWrite() {
    _stage.value = PhotoExportStage.savingToPhotoLibrary;
  }

  void complete() {
    _result.complete(
      const ExportedPhoto(
        assetId: 'asset-staged',
        width: 4032,
        height: 3024,
        sharePath: '/tmp/Yingjian_staged.jpg',
      ),
    );
  }

  void dispose() => _stage.dispose();
}

final class _PreparingPhotoExporter
    implements PhotoExporter, PhotoResultPreparer {
  int exportCalls = 0;
  final List<ProjectPhoto> preparedPhotos = [];
  final List<EditRecipe> preparedRecipes = [];

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    exportCalls += 1;
    return const ExportedPhoto(assetId: 'unexpected', width: 1, height: 1);
  }

  @override
  PhotoPreparation prepareCanonical({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required EditState editState,
    required EditContext editContext,
    required PhotoExportOptions options,
  }) {
    preparedPhotos.add(photo);
    preparedRecipes.add(recipe);
    final count = preparedPhotos.length;
    return _ImmediatePhotoPreparation(
      PreparedPhoto(
        requestId: 'prepared-$count',
        localPath: '/tmp/Yingjian_prepared-$count.jpg',
        width: 4032,
        height: 3024,
      ),
    );
  }
}

final class _FailFirstPhotoSharer implements PhotoSharer {
  final List<List<String>> sharedAttempts = [];
  final List<String> discardedPaths = [];

  @override
  Future<PhotoShareOutcome> share({required List<String> localPaths}) async {
    sharedAttempts.add(List.unmodifiable(localPaths));
    if (sharedAttempts.length == 1) {
      throw StateError('fixture share failure');
    }
    return PhotoShareOutcome.completed;
  }

  @override
  Future<void> discard({required List<String> localPaths}) async {
    discardedPaths.addAll(localPaths);
  }
}

final class _ImmediatePhotoPreparation implements PhotoPreparation {
  _ImmediatePhotoPreparation(PreparedPhoto prepared)
    : requestId = prepared.requestId,
      result = Future.value(prepared);

  @override
  final String requestId;
  @override
  final Future<PreparedPhoto> result;

  @override
  Future<void> cancel() async {}
}

final class _ControlledPreparingPhotoExporter
    implements PhotoExporter, PhotoResultPreparer {
  final Completer<void> started = Completer<void>();
  final Completer<PreparedPhoto> _prepared = Completer<PreparedPhoto>();
  int cancelCount = 0;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) => throw StateError('Saving is not expected in this fixture');

  @override
  PhotoPreparation prepareCanonical({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required EditState editState,
    required EditContext editContext,
    required PhotoExportOptions options,
  }) {
    if (!started.isCompleted) started.complete();
    return _ControlledPhotoPreparation(
      result: _prepared.future,
      onCancel: () {
        cancelCount += 1;
        if (!_prepared.isCompleted) {
          _prepared.completeError(const PhotoPreparationCanceled());
        }
      },
    );
  }
}

final class _ControlledPhotoPreparation implements PhotoPreparation {
  _ControlledPhotoPreparation({required this.result, required this.onCancel});

  @override
  String get requestId => 'controlled-preparation';
  @override
  final Future<PreparedPhoto> result;
  final VoidCallback onCancel;

  @override
  Future<void> cancel() async => onCancel();
}

final class _DelayedRestyleStore implements PhotoProjectStore {
  final MemoryPhotoProjectStore _delegate = MemoryPhotoProjectStore();
  final Completer<void> transitionStarted = Completer<void>();
  final Completer<void> _transitionRelease = Completer<void>();

  void completeTransition() => _transitionRelease.complete();

  @override
  Future<PhotoProject?> loadLatest() => _delegate.loadLatest();

  @override
  Future<void> save(PhotoProject project) async {
    if (_delegate.project?.flowState == PhotoProjectFlowState.exported &&
        project.flowState == PhotoProjectFlowState.editing) {
      if (!transitionStarted.isCompleted) transitionStarted.complete();
      await _transitionRelease.future;
    }
    await _delegate.save(project);
  }
}

final class _ControlledImporter implements CancelablePhotoImporter {
  final Completer<PhotoImportBatch> _result = Completer<PhotoImportBatch>();
  int cancelCount = 0;

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) => _result.future;

  @override
  Future<void> cancelImport() async {
    cancelCount += 1;
    if (!_result.isCompleted) {
      _result.complete(const PhotoImportBatch());
    }
  }
}

final class _ErrorAfterCancelImporter implements CancelablePhotoImporter {
  final Completer<PhotoImportBatch> _result = Completer<PhotoImportBatch>();

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) => _result.future;

  @override
  Future<void> cancelImport() async {
    if (!_result.isCompleted) {
      _result.completeError(StateError('picker cancellation raced timeout'));
    }
  }
}

final class _FailingAiStyleStore implements PhotoProjectStore {
  PhotoProject? project;

  @override
  Future<PhotoProject?> loadLatest() async => project;

  @override
  Future<void> save(PhotoProject project) async {
    if (project.creationStyleId == 'ai-custom') {
      throw StateError('AI style snapshot save failed');
    }
    this.project = project;
  }
}

final class _FailingCreationResultStore implements PhotoProjectStore {
  final MemoryPhotoProjectStore _delegate = MemoryPhotoProjectStore();

  PhotoProject? get project => _delegate.project;

  @override
  Future<PhotoProject?> loadLatest() => _delegate.loadLatest();

  @override
  Future<void> save(PhotoProject project) {
    if (project.creationResult != null) {
      throw StateError('Static result persistence failed');
    }
    return _delegate.save(project);
  }
}

final class _DelayedDeleteStore implements PhotoProjectCatalogStore {
  _DelayedDeleteStore(PhotoProject project)
    : _delegate = MemoryPhotoProjectStore(project);

  final MemoryPhotoProjectStore _delegate;
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> _deleteRelease = Completer<void>();
  int deleteCalls = 0;

  void completeDelete() => _deleteRelease.complete();

  @override
  Future<void> activateProject(String projectId) =>
      _delegate.activateProject(projectId);

  @override
  Future<void> cancelNewProject() => _delegate.cancelNewProject();

  @override
  Future<void> deletePhotoCopy(ProjectPhoto photo) =>
      _delegate.deletePhotoCopy(photo);

  @override
  Future<void> deleteProject(PhotoProject project) async {
    deleteCalls += 1;
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await _deleteRelease.future;
    await _delegate.deleteProject(project);
  }

  @override
  Future<PhotoProject?> loadLatest() => _delegate.loadLatest();

  @override
  Future<PhotoProject?> loadProject(String projectId) =>
      _delegate.loadProject(projectId);

  @override
  Future<List<PhotoProject>> loadProjects() => _delegate.loadProjects();

  @override
  Future<void> save(PhotoProject project) => _delegate.save(project);

  @override
  Future<void> startNewProject() => _delegate.startNewProject();
}

final class _MisleadingLatestStore implements PhotoProjectCatalogStore {
  _MisleadingLatestStore(List<PhotoProject> projects)
    : _projects = List.of(projects);

  final List<PhotoProject> _projects;
  final List<String> loadedProjectIds = [];

  @override
  Future<PhotoProject?> loadLatest() async => _projects.first;

  @override
  Future<List<PhotoProject>> loadProjects() async => List.of(_projects);

  @override
  Future<PhotoProject?> loadProject(String projectId) async {
    loadedProjectIds.add(projectId);
    return _projects.where((project) => project.id == projectId).firstOrNull;
  }

  @override
  Future<void> activateProject(String projectId) async {}

  @override
  Future<void> startNewProject() async {}

  @override
  Future<void> cancelNewProject() async {}

  @override
  Future<void> save(PhotoProject project) async {
    _projects.removeWhere((candidate) => candidate.id == project.id);
    _projects.add(project);
  }

  @override
  Future<void> deletePhotoCopy(ProjectPhoto photo) async {}

  @override
  Future<void> deleteProject(PhotoProject project) async {
    _projects.removeWhere((candidate) => candidate.id == project.id);
  }
}
