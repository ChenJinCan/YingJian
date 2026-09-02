import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/creation/domain/creation_intent.dart';
import 'package:yingjian/features/creation/domain/creation_task.dart';
import 'package:yingjian/features/creation/domain/style_definition.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';
import 'package:yingjian/features/generation/application/upscale_photo_generator.dart';
import 'package:yingjian/features/generation/application/motion_photo_generator.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';
import 'package:yingjian/features/generation/application/mask_removal_input_builder.dart';
import 'package:yingjian/features/generation/domain/generation_input.dart';
import 'package:yingjian/features/generation/infrastructure/explicit_refresh_generation_provider.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/photo_analysis/domain/photo_analysis.dart';

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
        creationTask: CreationTask.motion,
        creationCapability: CreationCapability.motionSubtle,
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
      expect(restored.creationTask, CreationTask.motion);
      expect(restored.creationCapability, CreationCapability.motionSubtle);
      expect(restored.creationStyleId, 'breeze');
      expect(restored.creationStyleName, '轻风');
      expect(restored.creationStyleRecipe, project.creationStyleRecipe);
      expect(restored.creationResult, project.creationResult);

      for (final task in CreationTask.values) {
        final taskProject = PhotoProject(
          id: 'task-${task.name}',
          createdAt: DateTime.utc(2026, 8, 31),
          updatedAt: DateTime.utc(2026, 8, 31),
          photos: [_fixturePhoto('task-${task.name}-photo')],
          creationIntent: task.creationIntent,
          creationTask: task,
        );
        final restoredTask = PhotoProject.fromJson(taskProject.toJson());
        expect(restoredTask.creationIntent, task.creationIntent);
        expect(restoredTask.creationTask, task);
      }

      final legacyJson = Map<String, Object?>.from(project.toJson())
        ..['schemaVersion'] = 14
        ..remove('creationIntent');
      final legacy = PhotoProject.fromJson(legacyJson);
      expect(legacy.creationIntent, CreationIntent.apply);
      expect(legacy.creationTask, CreationTask.style);
      expect(legacy.creationResult, isNull);

      final previousStaticSchema =
          PhotoProject(
              id: 'previous-static-project',
              createdAt: DateTime.utc(2026, 8, 31),
              updatedAt: DateTime.utc(2026, 8, 31),
              photos: [_fixturePhoto('previous-static-photo')],
            ).toJson()
            ..['schemaVersion'] = 17
            ..remove('creationTask');
      expect(
        PhotoProject.fromJson(previousStaticSchema).creationTask,
        CreationTask.style,
      );

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
      expect(restoredMotion.creationTask, CreationTask.motion);
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

    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('apply-style-workspace'))),
      ).brightness,
      Brightness.dark,
    );
  });

  testWidgets('style workspace exposes outcome styles and applies on tap', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('default-style')]),
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('style-workspace-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('style-workspace-back')), findsOneWidget);
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('style-option-japanese-v1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('style-option-film-v1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('style-option-illustration-v1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('style-option-cinematic-v1')),
      findsOneWidget,
    );
    expect(find.text('请选择能力'), findsNothing);
    expect(find.textContaining('系统不会替你'), findsNothing);
    expect(find.byKey(const ValueKey('style-capability-text')), findsNothing);
    expect(store.project!.creationStyleId, isNull);
    expect(store.project!.creationStyleRecipe, isNull);
    expect(store.project!.creationCapability, isNull);
    expect(
      find.byKey(const ValueKey('apply-style-primary-action')),
      findsNothing,
    );

    final film = find.byKey(const ValueKey('style-option-film-v1'));
    await tester.ensureVisible(film);
    expect(
      tester
          .widget<InkWell>(
            find.ancestor(of: find.text('胶片'), matching: find.byType(InkWell)),
          )
          .onTap,
      isNotNull,
    );
    await tester.tap(find.text('胶片'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(store.project!.creationCapability, CreationCapability.styleOfficial);
    expect(store.project!.creationStyleId, 'film-v1');
    expect(store.project!.creationStyleRecipe, isNotNull);
    expect(store.project!.currentStaticStyleResult?.styleId, 'film-v1');
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('apply-style-primary-action')),
      findsNothing,
    );
  });

  testWidgets(
    'style workspace keeps implementation inputs out of the main path',
    (tester) async {
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([_fixturePhoto('simple-style')]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-style')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('style-capability-text')), findsNothing);
      expect(
        find.byKey(const ValueKey('style-capability-voice')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('style-capability-reference')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('style-define-primary-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ai-redraw-style-definition')),
        findsNothing,
      );
      expect(find.text('日系'), findsOneWidget);
      expect(find.text('胶片'), findsOneWidget);
      expect(find.text('插画'), findsOneWidget);
      expect(find.text('电影感'), findsOneWidget);
    },
  );

  testWidgets('optimize capabilities stay visible and execute on tap', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final previewRenderer = FakePhotoPreviewRenderer.supported();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('optimize-choice')]),
        photoProjectStore: store,
        photoPreviewRenderer: previewRenderer,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await _tapHomeTarget(tester, find.byKey(const ValueKey('home-optimize')));
    await tester.pumpAndSettle();

    _expectCapabilityKeyOrder(tester, const [
      'optimize-capability-natural',
      'optimize-capability-ai-repair',
      'optimize-capability-upscale',
      'optimize-capability-old-photo',
    ]);
    expect(store.project!.creationStyleId, isNull);
    expect(store.project!.creationStyleRecipe, isNull);
    expect(store.project!.creationCapability, isNull);
    expect(find.byKey(const ValueKey('optimize-primary-action')), findsNothing);
    expect(
      find.byKey(const ValueKey('optimize-capability-unavailable-state')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('optimize-task-unavailable')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('optimize-capability-ai-repair')),
    );
    await tester.pumpAndSettle();

    expect(
      store.project!.creationCapability,
      CreationCapability.optimizeAiRepair,
    );
    expect(
      find.byKey(const ValueKey('optimize-capability-rail')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('optimize-primary-action')), findsNothing);
    expect(find.textContaining('本地改善亮度'), findsNothing);
    expect(previewRenderer.updates, isEmpty);

    final natural = find.byKey(const ValueKey('optimize-capability-natural'));
    await tester.ensureVisible(natural);
    await tester.tap(natural);
    await tester.pumpAndSettle();

    expect(
      store.project!.creationCapability,
      CreationCapability.optimizeNatural,
    );
    expect(
      store.project!.currentStaticStyleResult?.capability,
      CreationCapability.optimizeNatural,
    );
    expect(find.text('应用自然优化'), findsNothing);
  });

  testWidgets('HD upscale defaults to 2x and generates on tap', (tester) async {
    final store = MemoryPhotoProjectStore();
    final generator = _RecordingUpscalePhotoGenerator();
    final sharer = FakePhotoSharer();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          _fixturePhoto('upscale-choice', contentSha256: 'a' * 64),
        ]),
        photoProjectStore: store,
        upscalePhotoGenerator: generator,
        photoSharer: sharer,
      ),
    );
    await tester.pumpAndSettle();
    await _tapHomeTarget(tester, find.byKey(const ValueKey('home-optimize')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('optimize-capability-upscale')));
    await tester.pumpAndSettle();

    expect(generator.scales, [UpscalePhotoScale.twoX]);
    expect(find.byKey(const ValueKey('upscale-scale-2x')), findsNothing);
    expect(find.byKey(const ValueKey('upscale-scale-4x')), findsNothing);
    expect(
      find.byKey(const ValueKey('optimize-upscale-primary-action')),
      findsNothing,
    );
    final share = find.byKey(const ValueKey('optimize-generated-result-share'));
    await tester.ensureVisible(share);
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(sharer.sharedPaths, ['/tmp/yingjian-upscaled-2x.jpg']);
  });

  testWidgets(
    'cloud repair uploads and charges only after both confirmations',
    (tester) async {
      final store = MemoryPhotoProjectStore();
      final provider = _CompletedCloudGenerationProvider();
      final coordinator = GenerationCoordinator(
        provider: provider,
        store: _UiGenerationJobStore(),
      );
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([
            ProjectPhoto(
              id: 'cloud-repair-photo',
              localPath:
                  'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
                  'Icon-App-1024x1024@1x.png',
              originalName: 'cloud-repair.png',
              contentSha256: 'a' * 64,
            ),
          ]),
          photoProjectStore: store,
          generationCoordinator: coordinator,
        ),
      );
      await tester.pumpAndSettle();
      await _tapHomeTarget(tester, find.byKey(const ValueKey('home-optimize')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('optimize-capability-ai-repair')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('generation-consent-sheet')),
        findsOneWidget,
      );
      expect(provider.createCount, 0);
      final confirm = find.byKey(const ValueKey('generation-confirm-create'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('generation-upload-consent')));
      await tester.pumpAndSettle();
      expect(provider.createCount, 0);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('generation-cost-consent')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(provider.createCount, 1);
      expect(
        find.byKey(const ValueKey('optimize-cloud-result-save')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'unknown cloud create outcome is shown as reconciliation and blocks another cloud request',
    (tester) async {
      final projectStore = MemoryPhotoProjectStore();
      final generationStore = _UiGenerationJobStore();
      final provider = _CompletedCloudGenerationProvider(
        capabilities: const {
          CreationCapability.optimizeAiRepair,
          CreationCapability.optimizeOldPhoto,
        },
        createOutcomeUnknown: true,
      );
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([
            ProjectPhoto(
              id: 'cloud-reconciliation-photo',
              localPath:
                  'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
                  'Icon-App-1024x1024@1x.png',
              originalName: 'cloud-reconciliation.png',
              contentSha256: '9' * 64,
            ),
          ]),
          photoProjectStore: projectStore,
          generationCoordinator: GenerationCoordinator(
            provider: provider,
            store: generationStore,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapHomeTarget(tester, find.byKey(const ValueKey('home-optimize')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('optimize-capability-ai-repair')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generation-upload-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generation-cost-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generation-confirm-create')));
      await tester.pumpAndSettle();

      expect(provider.createCount, 1);
      expect(
        find.byKey(const ValueKey('optimize-cloud-reconciliation-required')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('optimize-cloud-result-failed')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('optimize-capability-old-photo')),
      );
      await tester.pumpAndSettle();
      expect(
        projectStore.project?.creationCapability,
        CreationCapability.optimizeAiRepair,
      );
      expect(provider.createCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final restoredProvider = _CompletedCloudGenerationProvider(
        capabilities: const {
          CreationCapability.optimizeAiRepair,
          CreationCapability.optimizeOldPhoto,
        },
      );
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoProjectStore: projectStore,
          generationCoordinator: GenerationCoordinator(
            provider: restoredProvider,
            store: generationStore,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final resume = find.byKey(const ValueKey('home-resume-project'));
      await _scrollHomeTo(tester, resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('optimize-cloud-reconciliation-required')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('optimize-capability-unavailable-state')),
        findsNothing,
      );
      expect(restoredProvider.createCount, 0);

      await tester.tap(
        find.byKey(const ValueKey('optimize-cloud-reconciliation-check')),
      );
      await tester.pumpAndSettle();
      expect(restoredProvider.reconcileCount, 1);
      expect(
        find.byKey(const ValueKey('optimize-cloud-reconciliation-required')),
        findsOneWidget,
      );
      expect(restoredProvider.createCount, 0);

      restoredProvider.resolveReconciliation = true;
      await tester.tap(
        find.byKey(const ValueKey('optimize-cloud-reconciliation-check')),
      );
      await tester.pumpAndSettle();
      expect(restoredProvider.reconcileCount, 2);
      expect(
        find.byKey(const ValueKey('optimize-cloud-reconciliation-required')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('optimize-cloud-result-failed')),
        findsOneWidget,
      );
      expect(find.text('已有云端任务仍在处理或待确认，暂时不能创建新的云端任务。'), findsOneWidget);
      expect(restoredProvider.createCount, 0);
    },
  );

  testWidgets(
    'old photo repair defaults to preservation and opens consent on tap',
    (tester) async {
      final provider = _CompletedCloudGenerationProvider(
        capabilities: const {CreationCapability.optimizeOldPhoto},
      );
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([
            ProjectPhoto(
              id: 'old-photo-input',
              localPath:
                  'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
                  'Icon-App-1024x1024@1x.png',
              originalName: 'old-photo-input.png',
              contentSha256: 'c' * 64,
            ),
          ]),
          generationCoordinator: GenerationCoordinator(
            provider: provider,
            store: _UiGenerationJobStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapHomeTarget(tester, find.byKey(const ValueKey('home-optimize')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('optimize-capability-old-photo')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('old-photo-mode-preserve')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('old-photo-mode-colorize')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('optimize-cloud-primary-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('generation-consent-sheet')),
        findsOneWidget,
      );
      expect(provider.createCount, 0);

      await tester.tap(find.byKey(const ValueKey('generation-upload-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generation-cost-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generation-confirm-create')));
      await tester.pumpAndSettle();

      expect(provider.createCount, 1);
      expect(
        provider.snapshots.single.input,
        isA<OldPhotoGenerationInput>().having(
          (input) => input.colorMode,
          'colorMode',
          OldPhotoColorMode.preserve,
        ),
      );
    },
  );

  testWidgets(
    'illustration freezes a safe definition and opens consent on tap',
    (tester) async {
      final store = MemoryPhotoProjectStore();
      final provider = _CompletedCloudGenerationProvider(
        capabilities: const {CreationCapability.styleAiRedraw},
      );
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([
            ProjectPhoto(
              id: 'illustration-input',
              localPath:
                  'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
                  'Icon-App-1024x1024@1x.png',
              originalName: 'illustration-input.png',
              contentSha256: 'e' * 64,
            ),
          ]),
          photoProjectStore: store,
          generationCoordinator: GenerationCoordinator(
            provider: provider,
            store: _UiGenerationJobStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapHomeTarget(tester, find.byKey(const ValueKey('home-style')));
      await tester.pumpAndSettle();
      final illustration = find.byKey(
        const ValueKey('style-option-illustration-v1'),
      );
      await tester.ensureVisible(illustration);
      await tester.tap(illustration);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ai-redraw-style-definition')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('style-cloud-primary-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('generation-consent-sheet')),
        findsOneWidget,
      );
      expect(
        store.project!.creationStyleDefinition,
        isA<StyleDefinition>().having(
          (definition) => definition.origin,
          'origin',
          StyleDefinitionOrigin.aiRedraw,
        ),
      );
      expect(provider.createCount, 0);

      await tester.tap(find.byKey(const ValueKey('generation-upload-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generation-cost-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generation-confirm-create')));
      await tester.pumpAndSettle();

      expect(provider.createCount, 1);
      expect(
        provider.snapshots.single.input,
        isA<StyleRedrawGenerationInput>(),
      );
    },
  );

  testWidgets('cleanup workspace waits for an explicit capability', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final analyzer = _CountingPhotoAnalyzer(subjectAvailable: true);
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('cleanup-choice')]),
        photoProjectStore: store,
        photoAnalyzer: analyzer,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await _tapHomeTarget(tester, find.byKey(const ValueKey('home-cleanup')));
    await tester.pumpAndSettle();

    _expectCapabilityKeyOrder(tester, const [
      'cleanup-capability-white',
      'cleanup-capability-transparent',
      'cleanup-capability-replace-background',
      'cleanup-capability-remove-passerby',
      'cleanup-capability-brush-remove',
    ]);
    expect(store.project!.creationStyleId, isNull);
    expect(store.project!.creationStyleRecipe, isNull);
    expect(store.project!.creationCapability, isNull);
    expect(find.byKey(const ValueKey('cleanup-primary-action')), findsNothing);
    expect(
      find.byKey(const ValueKey('cleanup-capability-unavailable-state')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('cleanup-task-unavailable')),
      findsNothing,
    );
    expect(analyzer.analyzeCalls, 0);

    await tester.tap(find.byKey(const ValueKey('cleanup-capability-white')));
    await tester.pumpAndSettle();

    expect(analyzer.analyzeCalls, 1);
    expect(store.project!.creationCapability, CreationCapability.cleanupWhite);
    expect(
      store.project!.currentStaticStyleResult?.capability,
      CreationCapability.cleanupWhite,
    );
    expect(find.text('应用白底'), findsNothing);
  });

  testWidgets('brush removal uploads only the mask the user explicitly drew', (
    tester,
  ) async {
    final provider = _CompletedCloudGenerationProvider(
      capabilities: const {CreationCapability.cleanupBrushRemove},
    );
    final maskCreator = _RecordingMaskRemovalInputCreator();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          ProjectPhoto(
            id: 'brush-remove-input',
            localPath:
                'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
                'Icon-App-1024x1024@1x.png',
            originalName: 'brush-remove.png',
            contentSha256: 'e' * 64,
            pixelWidth: 1024,
            pixelHeight: 1024,
          ),
        ]),
        generationCoordinator: GenerationCoordinator(
          provider: provider,
          store: _UiGenerationJobStore(),
        ),
        maskRemovalInputCreator: maskCreator,
      ),
    );
    await tester.pumpAndSettle();
    await _tapHomeTarget(tester, find.byKey(const ValueKey('home-cleanup')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cleanup-capability-brush-remove')),
    );
    await tester.pumpAndSettle();

    expect(provider.createCount, 0);
    final maskConfirm = find.byKey(const ValueKey('mask-removal-confirm'));
    expect(tester.widget<FilledButton>(maskConfirm).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('mask-removal-canvas')));
    await tester.pump();
    expect(tester.widget<FilledButton>(maskConfirm).onPressed, isNotNull);
    expect(provider.createCount, 0);
    await tester.ensureVisible(maskConfirm);
    await tester.pumpAndSettle();
    await tester.tap(maskConfirm);
    await tester.pumpAndSettle();

    expect(maskCreator.calls, hasLength(1));
    expect(
      find.byKey(const ValueKey('generation-consent-sheet')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('generation-upload-consent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('generation-cost-consent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('generation-confirm-create')));
    await tester.pumpAndSettle();

    expect(provider.createCount, 1);
    expect(provider.snapshots.single.input, same(maskCreator.result));
  });

  testWidgets(
    'replacement background imports only after its explicit selection',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync(
        'yingjian-replacement-background-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final sha = 'a' * 64;
      final path = '${temp.path}/resources/aa/$sha.png';
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(
        File(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
          'Icon-App-1024x1024@1x.png',
        ).readAsBytesSync(),
      );
      final sourceAndBackground = ProjectPhoto(
        id: 'cleanup-replacement-choice',
        localPath: path,
        originalName: 'background.png',
        contentSha256: sha,
        pixelWidth: 1024,
        pixelHeight: 1024,
        colorSpace: PhotoColorSpace.srgb,
        inputFormat: PhotoInputFormat.png,
        supportState: PhotoSupportState.supported,
      );
      final importer = FakePhotoImporter([sourceAndBackground]);
      final analyzer = _CountingPhotoAnalyzer(subjectAvailable: true);
      final store = MemoryPhotoProjectStore();
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: importer,
          photoProjectStore: store,
          photoAnalyzer: analyzer,
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      await tester.pumpAndSettle();
      await _tapHomeTarget(tester, find.byKey(const ValueKey('home-cleanup')));
      await tester.pumpAndSettle();

      expect(importer.editingResourceImportCount, 0);
      expect(analyzer.analyzeCalls, 0);
      await tester.tap(
        find.byKey(const ValueKey('cleanup-capability-replace-background')),
      );
      await tester.pumpAndSettle();

      expect(
        store.project!.creationCapability,
        CreationCapability.cleanupReplaceBackground,
      );
      expect(analyzer.analyzeCalls, 1);
      expect(importer.editingResourceImportCount, 1);
      final imported = importer.lastImportedEditingResource!;
      expect(imported.localPath, path);
      expect(
        find.byKey(const ValueKey('cleanup-choose-background-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('cleanup-primary-action')),
        findsNothing,
      );

      final result = store.project!.currentStaticStyleResult!;
      expect(result.capability, CreationCapability.cleanupReplaceBackground);
      expect(
        result.recipe.semanticEditingRecipe.background,
        BackgroundTreatment.image,
      );
      expect(result.recipe.semanticEditingRecipe.backgroundImagePath, path);
      expect(
        result.recipe.semanticEditingRecipe.backgroundImageResourceId,
        imported.descriptor.id,
      );
      expect(
        store.project!.editingResources.resources[imported.descriptor.id],
        imported.descriptor,
      );
      expect(importer.discardedEditingResourceIds, isEmpty);
    },
  );

  testWidgets('transparent cutout applies only after its explicit selection', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final analyzer = _CountingPhotoAnalyzer(subjectAvailable: true);
    final exporter = _PreparingPhotoExporter();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          _fixturePhoto('cleanup-transparent-choice'),
        ]),
        photoProjectStore: store,
        photoAnalyzer: analyzer,
        photoExporter: exporter,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await _tapHomeTarget(tester, find.byKey(const ValueKey('home-cleanup')));
    await tester.pumpAndSettle();

    expect(analyzer.analyzeCalls, 0);
    await tester.tap(
      find.byKey(const ValueKey('cleanup-capability-transparent')),
    );
    await tester.pumpAndSettle();

    expect(
      store.project!.creationCapability,
      CreationCapability.cleanupTransparent,
    );
    expect(analyzer.analyzeCalls, 1);
    expect(find.text('抠出主体并生成透明背景图片。'), findsNothing);
    expect(
      find.byKey(const ValueKey('cleanup-capability-unavailable-state')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('cleanup-primary-action')), findsNothing);
    expect(
      store.project!.currentStaticStyleResult?.capability,
      CreationCapability.cleanupTransparent,
    );
    expect(
      store
          .project!
          .currentStaticStyleResult
          ?.recipe
          .semanticEditingRecipe
          .background,
      BackgroundTreatment.transparent,
    );
    await tester.tap(find.byKey(const ValueKey('style-result-share')));
    await tester.pumpAndSettle();
    expect(exporter.preparedOptions.single.format, PhotoExportFormat.png);
  });

  testWidgets('motion workspace waits for an explicit capability', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([_fixturePhoto('motion-choice')]),
        photoProjectStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await _tapHomeTarget(tester, find.byKey(const ValueKey('home-motion')));
    await tester.pumpAndSettle();

    _expectCapabilityKeyOrder(tester, const [
      'motion-capability-subtle',
      'motion-capability-camera-push',
      'motion-capability-light-flow',
    ]);
    expect(store.project!.creationStyleId, isNull);
    expect(store.project!.creationStyleRecipe, isNull);
    expect(store.project!.creationCapability, isNull);
    expect(
      find.byKey(const ValueKey('motion-unavailable-state')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('motion-generate-primary-action')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('motion-style-primary-action')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('motion-capability-camera-push')),
    );
    await tester.pumpAndSettle();

    expect(
      store.project!.creationCapability,
      CreationCapability.motionCameraPush,
    );
    expect(find.text('生成镜头缓慢推进的动态效果。'), findsNothing);
    expect(
      find.byKey(const ValueKey('motion-capability-unavailable-state')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('motion-generate-primary-action')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('motion-style-primary-action')),
      findsNothing,
    );
  });

  testWidgets('motion generates only the direction the user selected', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final generator = _RecordingMotionPhotoGenerator();
    final sharer = FakePhotoSharer();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          _fixturePhoto('motion-local', contentSha256: 'b' * 64),
        ]),
        photoProjectStore: store,
        motionPhotoGenerator: generator,
        photoSharer: sharer,
      ),
    );
    await tester.pumpAndSettle();
    await _tapHomeTarget(tester, find.byKey(const ValueKey('home-motion')));
    await tester.pumpAndSettle();

    expect(generator.effects, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey('motion-capability-camera-push')),
    );
    await tester.pumpAndSettle();

    expect(generator.effects, [MotionPhotoEffect.cameraPush]);
    expect(
      find.byKey(const ValueKey('motion-generate-primary-action')),
      findsNothing,
    );
    final share = find.byKey(const ValueKey('motion-generated-result-share'));
    await tester.ensureVisible(share);
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(sharer.sharedPaths, ['/tmp/yingjian-motion-cameraPush.mp4']);
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
    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();
    await _selectOfficialStyle(tester);

    expect(
      find.byKey(const ValueKey('apply-style-primary-action')),
      findsNothing,
    );
    final failure = find.byKey(const ValueKey('style-preview-failed'));
    expect(failure, findsOneWidget);
    final previousAttempts = previewRenderer.creates.length;
    await tester.tap(
      find.descendant(of: failure, matching: find.byType(TextButton)),
    );
    await tester.pumpAndSettle();
    expect(previewRenderer.creates.length, greaterThan(previousAttempts));
    expect(store.project!.currentStaticStyleResult, isNull);
  });

  testWidgets('legacy custom recipe waits for an explicit capability', (
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
    await _scrollHomeTo(tester, resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();

    expect(store.project!.recipe, customRecipe);
    expect(store.project!.creationCapability, isNull);
    expect(store.project!.creationStyleId, isNull);
    expect(store.project!.creationStyleRecipe, isNull);
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('style-option-japanese-v1')),
      findsOneWidget,
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

        await _tapHomeTarget(
          tester,
          find.byKey(const ValueKey('home-resume-project')),
        );
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

    await _tapHomeTarget(
      tester,
      find.byKey(const ValueKey('home-resume-project')),
    );
    await tester.pumpAndSettle();

    expect(store.project!.flowState, PhotoProjectFlowState.editing);
    expect(store.project!.creationCapability, isNull);
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('apply-style-primary-action')),
      findsNothing,
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
    await _tapHomeTarget(
      tester,
      find.byKey(const ValueKey('home-resume-project')),
    );
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
        creationCapability: CreationCapability.styleOfficial,
        creationStyleId: 'natural',
        creationStyleRecipe: recipe,
        creationResult: StaticStyleResultIdentity(
          sourcePhotoId: photo.id,
          editStateVersion: 0,
          styleId: 'natural',
          capability: CreationCapability.styleOfficial,
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
    await _tapHomeTarget(
      tester,
      find.byKey(const ValueKey('home-resume-project')),
    );
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

    final entry = find.byKey(const ValueKey('home-style'));
    await tester.scrollUntilVisible(
      entry,
      260,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('home-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await _selectOfficialStyle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    final save = find.byKey(const ValueKey('style-result-save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(save, findsOneWidget);
    expect(save.hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('apply-style-primary-action')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion unavailable state stays reachable with large text', (
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
    await tester.scrollUntilVisible(
      entry,
      260,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('home-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('motion-capability-subtle')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('motion-capability-unavailable-state')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('motion-style-primary-action')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('motion-confirmation-sheet')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('style-options')), findsNothing);
    final back = find.byKey(const ValueKey('style-workspace-back'));
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
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
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([photo]),
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-style')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-motion')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-start-editing')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('home-style')));
      await tester.pumpAndSettle();
      await _selectOfficialStyle(tester);

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
        findsNothing,
      );
      expect(find.byKey(const ValueKey('style-result-save')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('motion-style-primary-action')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('editor-page')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('style-workspace-back')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-resume-project')), findsOneWidget);
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

      await _tapHomeTarget(tester, find.byKey(const ValueKey('home-motion')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('motion-capability-light-flow')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('motion-style-workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('motion-capability-unavailable-state')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('apply-style-primary-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('motion-style-primary-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('motion-confirmation-sheet')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('style-options')), findsNothing);
      expect(store.project?.creationIntent, CreationIntent.motion);
      expect(store.project?.creationTask, CreationTask.motion);
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

    await _tapHomeTarget(tester, find.byKey(const ValueKey('home-motion')));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byKey(const ValueKey('home-motion-preparing')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-style-preparing')), findsNothing);

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
    await _tapHomeTarget(tester, find.byKey(const ValueKey('home-motion')));
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
    await tester.tap(find.byKey(const ValueKey('home-style')));
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
    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();
    await _selectOfficialCapability(tester);

    final beforeSelection = store.project!;
    final beforeVersion = beforeSelection.editStateVersion;
    final beforeUndoCount = beforeSelection.undoHistory.length;

    await tester.tap(find.byKey(const ValueKey('style-option-film-v1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-style-name')))
          .data,
      '胶片',
    );
    expect(previewRenderer.creates, isNotEmpty);
    final expected = EditRecipe(
      warmth: 0.02,
      contrast: 0.03,
      basicEditingRecipe: BasicEditingRecipe(
        filter: PhotoFilter.film,
        filterStrength: 58,
      ),
    );
    expect(store.project!.creationStyleId, 'film-v1');
    expect(store.project!.effectiveRecipeFor(photo.id), expected);
    expect(store.project!.editStateVersion, beforeVersion + 1);
    expect(store.project!.undoHistory, hasLength(beforeUndoCount + 1));
    expect(
      store.project!.currentStaticStyleResult,
      StaticStyleResultIdentity(
        sourcePhotoId: photo.id,
        editStateVersion: beforeVersion + 1,
        styleId: 'film-v1',
        capability: CreationCapability.styleOfficial,
        styleName: '胶片',
        recipe: expected,
      ),
    );
    expect(
      find.byKey(const ValueKey('apply-style-primary-action')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('style-workspace-back')));
    await tester.pumpAndSettle();
    await tester.pump();
    final resume = find.byKey(const ValueKey('home-resume-project'));
    await _scrollHomeTo(tester, resume);
    await tester.pumpAndSettle();
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-style-name')))
          .data,
      '胶片',
    );
    expect(
      find.byKey(const ValueKey('style-static-result-controls')),
      findsOneWidget,
    );

    final japanese = find.byKey(const ValueKey('style-option-japanese-v1'));
    await tester.ensureVisible(japanese);
    await tester.tap(japanese);
    await tester.pumpAndSettle();
    expect(store.project!.currentStaticStyleResult?.styleId, 'japanese-v1');
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
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
    await _tapHomeTarget(
      tester,
      find.byKey(const ValueKey('home-resume-project')),
    );
    await tester.pumpAndSettle();
    expect(store.project!.recipe.crop, crop);
    expect(store.project!.creationCapability, isNull);
    await _selectOfficialCapability(tester);

    await tester.tap(find.byKey(const ValueKey('style-option-film-v1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NativePhotoPreview>(find.byType(NativePhotoPreview))
          .recipe
          .crop,
      crop,
    );
    await tester.pumpAndSettle();

    final applied = store.project!.effectiveRecipeFor(
      store.project!.photos.single.id,
    );
    expect(applied.crop, crop);
    expect(applied.basicEditingRecipe.filter, PhotoFilter.film);
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
    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();
    await _selectOfficialCapability(tester);
    await tester.tap(find.byKey(const ValueKey('style-option-film-v1')));
    await tester.pumpAndSettle();
    final before = store.project!;

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

      await tester.tap(find.byKey(const ValueKey('home-style')));
      await tester.pumpAndSettle();
      await _selectOfficialCapability(tester);
      await tester.tap(find.byKey(const ValueKey('style-option-film-v1')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      final save = find.byKey(const ValueKey('style-result-save'));
      expect(save, findsOneWidget);
      expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
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
      expect(previewSemantics, contains('胶片'));
      expect(previewSemantics, contains('风格已应用'));
      final back = find.byKey(const ValueKey('style-workspace-back'));
      expect(back, findsOneWidget);
      expect(
        tester.widget<IconButton>(back).tooltip,
        MaterialLocalizations.of(tester.element(back)).backButtonTooltip,
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

      await tester.tap(find.byKey(const ValueKey('style-workspace-back')));
      await tester.pumpAndSettle();
      final resume = find.byKey(const ValueKey('home-resume-project'));
      await _scrollHomeTo(tester, resume);
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
    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();
    await _selectOfficialStyle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-result-save')));
    await tester.pumpAndSettle();
    expect(find.text('已保存到系统相册'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('style-option-japanese-v1')));
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

      await tester.tap(find.byKey(const ValueKey('home-style')));
      await tester.pumpAndSettle();
      await _selectOfficialStyle(tester);
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
        creationCapability: CreationCapability.styleOfficial,
        creationStyleId: 'natural',
        creationStyleRecipe: recipe,
        creationResult: StaticStyleResultIdentity(
          sourcePhotoId: photo.id,
          editStateVersion: 0,
          styleId: 'natural',
          capability: CreationCapability.styleOfficial,
          recipe: recipe,
        ),
      ),
    );
    final settings = await _settings();
    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();
    await _tapHomeTarget(
      tester,
      find.byKey(const ValueKey('home-resume-project')),
    );
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

      await tester.tap(find.byKey(const ValueKey('home-style')));
      await tester.pumpAndSettle();
      await _selectOfficialStyle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-result-save')), findsOneWidget);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('style-result-share')),
      );
      await tester.pumpAndSettle();

      expect(exporter.exportCalls, 0);
      expect(exporter.preparedPhotos, [photo]);
      expect(exporter.preparedRecipes, [store.project!.creationStyleRecipe]);
      expect(sharer.sharedPaths, ['/tmp/Yingjian_prepared-1.jpg']);
      expect(store.project!.flowState, PhotoProjectFlowState.editing);
      expect(store.project!.exportStates[photo.id], PhotoExportState.notQueued);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-workspace-back')));
      await tester.pumpAndSettle();
      await _tapHomeTarget(
        tester,
        find.byKey(const ValueKey('home-resume-project')),
      );
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('style-result-share')),
      );
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
    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();
    await _selectOfficialStyle(tester);
    await tester.pumpAndSettle();

    final share = find.byKey(const ValueKey('style-result-share'));
    await _tapVisible(tester, share);
    await tester.pumpAndSettle();
    expect(sharer.sharedAttempts, [
      ['/tmp/Yingjian_prepared-1.jpg'],
    ]);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('style-result-share')));
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
    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();
    await _selectOfficialStyle(tester);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('style-result-share')));
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

      await tester.tap(find.byKey(const ValueKey('home-style')));
      await tester.pumpAndSettle();
      await _selectOfficialStyle(tester);
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

    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();
    await _selectOfficialStyle(tester);
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

      await tester.tap(find.byKey(const ValueKey('home-style')));
      await tester.pumpAndSettle();
      await _selectOfficialStyle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-result-save')));
      await tester.pump();
      await exporter.started.future;

      expect(find.text('正在准备成片…'), findsWidgets);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('style-workspace-back')),
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

      await tester.tap(find.byKey(const ValueKey('home-style')));
      await tester.pumpAndSettle();
      await _selectOfficialStyle(tester);
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
      final film = find.byKey(const ValueKey('style-option-film-v1'));
      await tester.ensureVisible(film);
      await tester.tap(film);
      await tester.pumpAndSettle();
      expect(sharer.discardedPaths, ['/tmp/Yingjian_fixture.jpg']);
      expect(store.project!.flowState, PhotoProjectFlowState.editing);
      expect(
        store.project!.creationCapability,
        CreationCapability.styleOfficial,
      );
      expect(store.project!.currentStaticStyleResult?.styleId, 'film-v1');
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
    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();
    await _selectOfficialStyle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-result-share')));
    await tester.pumpAndSettle();
    expect(sharer.sharedPaths, ['/tmp/Yingjian_prepared-1.jpg']);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final film = find.byKey(const ValueKey('style-option-film-v1'));
    await tester.ensureVisible(film);
    await tester.tap(film);
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('style-result-share')));
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

      await tester.tap(find.byKey(const ValueKey('home-style')));
      await tester.pumpAndSettle();
      await _selectOfficialStyle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-result-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('style-option-film-v1')));
      await store.transitionStarted.future;
      await tester.pump();

      expect(
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.byKey(const ValueKey('style-option-film-v1')),
                matching: find.byType(InkWell),
              ),
            )
            .onTap,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('style-workspace-back')),
            )
            .onPressed,
        isNull,
      );

      store.completeTransition();
      await tester.pumpAndSettle();
      expect(
        (await store.loadLatest())!.currentStaticStyleResult?.styleId,
        'film-v1',
      );
      expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    },
  );

  testWidgets('motion unavailable never creates a job or static result', (
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
    await _tapHomeTarget(tester, find.byKey(const ValueKey('home-motion')));
    await tester.pumpAndSettle();

    final beforeSelection = store.project!;
    final photoId = beforeSelection.photos.single.id;
    final beforeRecipe = beforeSelection.effectiveRecipeFor(photoId);
    final beforeVersion = beforeSelection.editStateVersion;
    final beforeUndoCount = beforeSelection.undoHistory.length;

    await tester.tap(
      find.byKey(const ValueKey('motion-capability-camera-push')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('motion-capability-unavailable-state')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('motion-style-primary-action')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('motion-confirmation-sheet')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('style-options')), findsNothing);
    expect(store.project!.effectiveRecipeFor(photoId), beforeRecipe);
    expect(store.project!.editStateVersion, beforeVersion);
    expect(store.project!.undoHistory, hasLength(beforeUndoCount));
    expect(store.project!.currentStaticStyleResult, isNull);
    expect(
      store.project!.creationCapability,
      CreationCapability.motionCameraPush,
    );

    await tester.tap(find.byKey(const ValueKey('style-workspace-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
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
      creationCapability: CreationCapability.motionLightFlow,
    );
    final store = MemoryPhotoProjectStore(project);
    final settings = await _settings();

    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();
    await _tapHomeTarget(
      tester,
      find.byKey(const ValueKey('home-resume-project')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('motion-style-workspace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('motion-capability-unavailable-state')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('apply-style-primary-action')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('motion-style-primary-action')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('motion-confirmation-sheet')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('style-options')), findsNothing);
    expect(store.project?.creationTask, CreationTask.motion);
    expect(
      store.project?.creationCapability,
      CreationCapability.motionLightFlow,
    );
    expect(store.project?.currentStaticStyleResult, isNull);
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
      creationCapability: styleId == null
          ? null
          : CreationCapability.styleOfficial,
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
    await _scrollHomeTo(tester, selectedCard);
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
    await _scrollHomeTo(tester, delete);
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
      creationCapability: CreationCapability.styleOfficial,
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
    await _scrollHomeTo(tester, resume);
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
      findsNothing,
    );
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-style-name')))
          .data,
      '柔光',
    );
  });

  testWidgets(
    'restored cloud capability is shown as not connected until explicit refresh',
    (tester) async {
      final project = PhotoProject(
        id: 'restored-cloud-capability',
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
        photos: [
          _fixturePhoto('restored-cloud-photo', contentSha256: '8' * 64),
        ],
        creationIntent: CreationIntent.apply,
        creationTask: CreationTask.optimize,
        creationCapability: CreationCapability.optimizeAiRepair,
      );
      var connectorCalls = 0;
      final provider = ExplicitRefreshGenerationProvider(
        connector: () async {
          connectorCalls += 1;
          return _CompletedCloudGenerationProvider();
        },
      );
      final settings = await _settings();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoProjectStore: MemoryPhotoProjectStore(project),
          generationCoordinator: GenerationCoordinator(
            provider: provider,
            store: _UiGenerationJobStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final resume = find.byKey(const ValueKey('home-resume-project'));
      await _scrollHomeTo(tester, resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();

      expect(connectorCalls, 0);
      expect(find.text('云端能力待连接'), findsOneWidget);
      expect(find.text('该能力尚未完成'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('optimize-cloud-capability-refresh')),
      );
      await tester.pumpAndSettle();

      expect(connectorCalls, 1);
      expect(
        find.byKey(const ValueKey('optimize-cloud-primary-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('optimize-capability-unavailable-state')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('optimize-capability-ai-repair')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('generation-consent-sheet')),
        findsOneWidget,
      );
    },
  );

  testWidgets('hidden style input modes stay out of the outcome rail', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore();
    final previewRenderer = FakePhotoPreviewRenderer.supported();
    final settings = await _settings();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          _fixturePhoto('unavailable-style-capabilities'),
        ]),
        photoProjectStore: store,
        photoPreviewRenderer: previewRenderer,
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-style')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('style-capability-text')), findsNothing);
    expect(find.byKey(const ValueKey('style-capability-voice')), findsNothing);
    expect(
      find.byKey(const ValueKey('style-capability-reference')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('style-capability-ai-redraw')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
    expect(store.project!.creationCapability, isNull);
    expect(previewRenderer.updates, isEmpty);
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
}

Future<void> _selectOfficialCapability(WidgetTester tester) async {
  expect(find.byKey(const ValueKey('style-options')), findsOneWidget);
  await tester.pump();
}

Future<void> _selectOfficialStyle(
  WidgetTester tester, {
  String styleKey = 'style-option-japanese-v1',
}) async {
  await _selectOfficialCapability(tester);
  final style = find.byKey(ValueKey(styleKey));
  await tester.ensureVisible(style);
  await tester.pump();
  await tester.tap(style);
  await tester.pumpAndSettle();
}

Future<void> _scrollHomeTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    320,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('home-scroll')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapHomeTarget(WidgetTester tester, Finder target) async {
  await _scrollHomeTo(tester, target);
  await tester.tap(target);
}

void _expectCapabilityKeyOrder(WidgetTester tester, List<String> expectedKeys) {
  final renderedKeys = find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && expectedKeys.contains(key.value);
      })
      .evaluate()
      .map((element) => (element.widget.key! as ValueKey<String>).value)
      .toList(growable: false);
  expect(renderedKeys, expectedKeys);
}

Future<AppSettings> _settings() async {
  SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
  return AppSettings.load();
}

ProjectPhoto _fixturePhoto(String id, {String contentSha256 = ''}) =>
    ProjectPhoto(
      id: id,
      localPath:
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
          'Icon-App-1024x1024@1x.png',
      originalName: '$id.png',
      contentSha256: contentSha256,
    );

final class _RecordingUpscalePhotoGenerator implements UpscalePhotoGenerator {
  final List<UpscalePhotoScale> scales = [];

  @override
  Future<UpscalePhotoArtifact> generate({
    required String sourcePath,
    required UpscalePhotoScale scale,
  }) async {
    scales.add(scale);
    return UpscalePhotoArtifact(
      outputPath: '/tmp/yingjian-upscaled-${scale.factor}x.jpg',
      contentSha256: 'e' * 64,
      scale: scale,
      width: 2048 * scale.factor,
      height: 2048 * scale.factor,
    );
  }
}

final class _RecordingMotionPhotoGenerator implements MotionPhotoGenerator {
  final List<MotionPhotoEffect> effects = [];

  @override
  Future<MotionPhotoArtifact> generate({
    required String sourcePath,
    required MotionPhotoEffect effect,
  }) async {
    effects.add(effect);
    return MotionPhotoArtifact(
      outputPath: '/tmp/yingjian-motion-${effect.id}.mp4',
      contentSha256: 'f' * 64,
      effect: effect,
      width: 720,
      height: 1280,
      duration: const Duration(seconds: 3),
    );
  }
}

final class _UiGenerationJobStore implements GenerationJobStore {
  final Map<String, GenerationJob> jobs = {};
  final Map<GenerationRequestIdentity, GenerationRequestReservation>
  reservations = {};

  @override
  Future<GenerationJob?> findByClientRequestId(String clientRequestId) async =>
      jobs.values
          .where((job) => job.clientRequestId == clientRequestId)
          .firstOrNull;

  @override
  Future<GenerationJob?> findById(String id) async => jobs[id];

  @override
  Future<List<GenerationJob>> findByProjectId(String projectId) async => jobs
      .values
      .where((job) => job.projectId == projectId)
      .toList(growable: false);

  @override
  Future<GenerationJob?> findLatest(
    GenerationRequestIdentity identity, {
    Set<GenerationJobState>? states,
    bool includeAnyInput = false,
  }) async {
    final matches =
        jobs.values
            .where(
              (job) =>
                  identity.matches(job, includeAnyInput: includeAnyInput) &&
                  (states == null || states.contains(job.state)),
            )
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return matches.firstOrNull;
  }

  @override
  Future<GenerationRequestReservation?> findReservation(
    GenerationRequestIdentity identity,
  ) async => reservations[identity];

  @override
  Future<GenerationRequestReservation?> findReconciliationRequired() async =>
      reservations.values
          .where(
            (reservation) =>
                reservation.state ==
                GenerationRequestReservationState.reconciliationRequired,
          )
          .firstOrNull;

  @override
  Future<void> saveReservation(GenerationRequestReservation reservation) async {
    reservations[reservation.identity] = reservation;
  }

  @override
  Future<void> deleteReservation(String clientRequestId) async {
    reservations.removeWhere(
      (_, reservation) => reservation.clientRequestId == clientRequestId,
    );
  }

  @override
  Future<void> deleteProjectState(String projectId) async {
    jobs.removeWhere((_, job) => job.projectId == projectId);
    reservations.removeWhere((identity, _) => identity.projectId == projectId);
  }

  @override
  Future<void> save(GenerationJob job) async {
    jobs[job.id] = job;
  }
}

final class _RecordingMaskRemovalInputCreator
    implements MaskRemovalInputCreator {
  final calls = <({int width, int height, int strokeCount})>[];
  final result = MaskRemovalGenerationInput(
    maskPath: '/app-support/explicit-mask.png',
    maskSha256: 'f' * 64,
  );

  @override
  Future<MaskRemovalGenerationInput> create({
    required int pixelWidth,
    required int pixelHeight,
    required List<MaskStroke> strokes,
  }) async {
    calls.add((
      width: pixelWidth,
      height: pixelHeight,
      strokeCount: strokes.length,
    ));
    return result;
  }
}

final class _CompletedCloudGenerationProvider
    implements GenerationProvider, GenerationRequestReconciler {
  _CompletedCloudGenerationProvider({
    this.capabilities = const {CreationCapability.optimizeAiRepair},
    this.createOutcomeUnknown = false,
  });

  final Set<CreationCapability> capabilities;
  final bool createOutcomeUnknown;
  int createCount = 0;
  int reconcileCount = 0;
  bool resolveReconciliation = false;
  final List<GenerationSourceSnapshot> snapshots = [];

  @override
  Set<CreationCapability> get availableCapabilities => capabilities;

  @override
  Future<void> refreshCapabilities() async {}

  @override
  GenerationOffer offerFor(CreationCapability capability) =>
      GenerationOffer.cloud(
        id: 'baidu-repair-v1',
        capability: capability,
        creditCost: 1,
        expiresAt: DateTime.utc(2026, 9, 2),
      );

  @override
  Future<GenerationJob> create({
    required GenerationSourceSnapshot snapshot,
    required String clientRequestId,
    required GenerationConsent? consent,
  }) async {
    createCount += 1;
    snapshots.add(snapshot);
    if (createOutcomeUnknown) {
      throw GenerationCreateOutcomeUnknown(clientRequestId);
    }
    return GenerationJob(
      id: 'cloud-job-1',
      clientRequestId: clientRequestId,
      projectId: snapshot.projectId,
      sourcePhotoId: snapshot.sourcePhotoId,
      sourceSha256: snapshot.sourceSha256,
      inputIdentity: snapshot.input?.identity,
      capability: snapshot.capability,
      state: GenerationJobState.succeeded,
      provider: 'baidu',
      model: 'image_definition_enhance',
      canCancel: false,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
      output: GeneratedMedia(
        id: 'cloud-media-1',
        kind: GeneratedMediaKind.image,
        localPath: '/tmp/cloud-repair-result.jpg',
        contentSha256: 'b' * 64,
        width: 2048,
        height: 2048,
      ),
    );
  }

  @override
  Future<GenerationJob> cancel(GenerationJob job) async => job;

  @override
  Future<GenerationJob> reconcile(
    GenerationRequestReservation reservation,
  ) async {
    reconcileCount += 1;
    final resolved = resolveReconciliation;
    return GenerationJob(
      id: 'cloud-reconciliation-job',
      clientRequestId: reservation.clientRequestId,
      projectId: reservation.identity.projectId,
      sourcePhotoId: reservation.identity.sourcePhotoId,
      sourceSha256: reservation.identity.sourceSha256,
      inputIdentity: reservation.identity.inputIdentity,
      capability: reservation.identity.capability,
      state: GenerationJobState.failed,
      provider: 'baidu',
      model: 'image_definition_enhance',
      canCancel: false,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1, 0, reconcileCount),
      usageState: resolved
          ? GenerationUsageState.released
          : GenerationUsageState.reserved,
      usageDisposition: resolved
          ? GenerationUsageDisposition.release
          : GenerationUsageDisposition.hold,
      errorCode: resolved
          ? 'generation_concurrency_exceeded'
          : 'dispatch_reconciliation_required',
    );
  }

  @override
  Stream<GenerationJob> observe(GenerationJob job) => const Stream.empty();
}

final class _CountingPhotoAnalyzer implements PhotoAnalyzer {
  _CountingPhotoAnalyzer({this.subjectAvailable = false});

  final PhotoAnalyzer _delegate = const MetadataSafePhotoAnalyzer();
  final bool subjectAvailable;
  int analyzeCalls = 0;

  @override
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) =>
      _delegate.identityFor(photo);

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) {
    analyzeCalls += 1;
    if (subjectAvailable) {
      return Future.value(
        LocalPhotoAnalysis(
          analysisVersion: 'widget-subject-v1',
          capabilityVersion: 'widget-subject',
          contentSha256: photo.contentSha256,
          orientation: photo.orientation,
          pixelWidth: photo.pixelWidth,
          pixelHeight: photo.pixelHeight,
          colorSpace: photo.colorSpace,
          disposition: PhotoAnalysisDisposition.ready,
          fallbackReason: AnalysisFallbackReason.none,
          portrait: PortraitApplicability.applicable,
          faceTargetRegions: const [
            NormalizedTargetRegion(
              left: 0.2,
              top: 0.1,
              right: 0.8,
              bottom: 0.9,
            ),
          ],
        ),
      );
    }
    return _delegate.analyze(photo);
  }
}

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
  final List<PhotoExportOptions> preparedOptions = [];

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
    preparedOptions.add(options);
    final count = preparedPhotos.length;
    final extension = options.format == PhotoExportFormat.png ? 'png' : 'jpg';
    return _ImmediatePhotoPreparation(
      PreparedPhoto(
        requestId: 'prepared-$count',
        localPath: '/tmp/Yingjian_prepared-$count.$extension',
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
