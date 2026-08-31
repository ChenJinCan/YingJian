import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/navigation/app_router.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/photo_analysis/domain/photo_analysis.dart';

import 'support/memory_photo_analysis_cache.dart';
import 'support/test_services.dart';

void main() {
  testWidgets('user can see the Yingjian starting action', (tester) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings));
    await tester.pumpAndSettle();

    expect(find.text('映见'), findsOneWidget);
    expect(find.text('选择想得到的结果'), findsOneWidget);
    expect(find.text('图片应用'), findsOneWidget);
    expect(find.text('动起来'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-apply-style')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-motion')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-full-screen-background')),
      findsOneWidget,
    );
    final backgroundRect = tester.getRect(
      find.byKey(const ValueKey('home-full-screen-background')),
    );
    expect(backgroundRect.top, 0);
    expect(
      backgroundRect.bottom,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
    expect(find.byKey(const ValueKey('home-journey-guide')), findsNothing);
    expect(find.text('最近项目'), findsNothing);
    expect(find.text('还没有项目，选一张照片开始吧'), findsNothing);
    expect(find.byKey(const ValueKey('home-new-project')), findsNothing);
  });

  testWidgets('follows a persisted English locale', (tester) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'en'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings));

    expect(find.text('Yingjian'), findsOneWidget);
    expect(find.text('Choose the result you want'), findsOneWidget);
    expect(find.text('Apply a look'), findsOneWidget);
    expect(find.text('Bring it to life'), findsOneWidget);
  });

  testWidgets('English draft metadata only presents the last edit time', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'project-1',
        createdAt: DateTime(2026, 8, 4),
        updatedAt: DateTime(2026, 8, 5),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/private/project/photo.jpg',
            originalName: 'photo.jpg',
          ),
        ],
        flowState: PhotoProjectFlowState.editing,
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'en'});
    final settings = await AppSettings.load();

    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();

    expect(find.textContaining('Last edited'), findsOneWidget);
    expect(find.textContaining('1 photo'), findsNothing);
  });

  testWidgets('home exposes an unfinished project and its last edit time', (
    tester,
  ) async {
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'project-1',
        createdAt: DateTime(2026, 8, 4, 9),
        updatedAt: DateTime(2026, 8, 5, 14, 30),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/private/project/photo.jpg',
            originalName: 'photo.jpg',
          ),
        ],
        flowState: PhotoProjectFlowState.editing,
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();

    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();

    expect(find.text('未完成项目'), findsNothing);
    expect(find.byKey(const ValueKey('home-apply-style')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-motion')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-resume-project')), findsOneWidget);
    expect(find.textContaining('1 张照片'), findsNothing);
    expect(find.textContaining('14:30'), findsOneWidget);
    expect(find.text('编辑中'), findsOneWidget);
  });

  testWidgets('home distinguishes exported drafts from later edits', (
    tester,
  ) async {
    const photo = ProjectPhoto(
      id: 'status-photo',
      localPath: '/private/project/status.jpg',
      originalName: 'status.jpg',
    );
    final exported = PhotoProject(
      id: 'exported-draft',
      createdAt: DateTime.utc(2026, 8, 28, 8),
      updatedAt: DateTime.utc(2026, 8, 28, 9),
      photos: [photo],
      lastSuccessfulExportEditStateVersion: 0,
    );
    final changed = PhotoProject(
      id: 'changed-draft',
      createdAt: DateTime.utc(2026, 8, 28, 10),
      updatedAt: DateTime.utc(2026, 8, 28, 11),
      photos: const [
        ProjectPhoto(
          id: 'changed-photo',
          localPath: '/private/project/changed.jpg',
          originalName: 'changed.jpg',
        ),
      ],
      editState: const EditState(version: 1),
      lastSuccessfulExportEditStateVersion: 0,
    );
    final store = MemoryPhotoProjectStore.withProjects([exported, changed]);
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-featured-draft-changed-draft')),
        matching: find.text('有新修改'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-draft-exported-draft')),
        matching: find.text('已导出'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('home lists multiple drafts and opens the selected draft', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    PhotoProject project(String id, String photoId, int hour) => PhotoProject(
      id: id,
      createdAt: DateTime.utc(2026, 8, 28, hour),
      updatedAt: DateTime.utc(2026, 8, 28, hour),
      photos: [
        ProjectPhoto(
          id: photoId,
          localPath: photoFile.path,
          originalName: '$photoId.png',
        ),
      ],
      flowState: PhotoProjectFlowState.editing,
    );
    final first = project('project-1', 'photo-1', 8);
    final second = project('project-2', 'photo-2', 9);
    final store = MemoryPhotoProjectStore.withProjects([first, second]);
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();

    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-featured-draft-project-2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-draft-project-2')), findsNothing);
    expect(find.byKey(const ValueKey('home-draft-project-1')), findsOneWidget);
    expect(find.text('最近创作'), findsOneWidget);

    final firstDraft = find.byKey(const ValueKey('home-draft-project-1'));
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.tap(firstDraft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('apply-style-workspace')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('style-workspace-source-photo')),
      findsOneWidget,
    );
    expect(store.project?.id, first.id);
    expect(
      store.projects.map((project) => project.id),
      containsAll(<String>[first.id, second.id]),
    );
  });

  testWidgets(
    'home deletes only the selected draft after a safe confirmation',
    (tester) async {
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      PhotoProject project(String id, String photoId, int hour) => PhotoProject(
        id: id,
        createdAt: DateTime.utc(2026, 8, 28, hour),
        updatedAt: DateTime.utc(2026, 8, 28, hour),
        photos: [
          ProjectPhoto(
            id: photoId,
            localPath: photoFile.path,
            originalName: '$photoId.png',
          ),
        ],
        flowState: PhotoProjectFlowState.editing,
      );
      final older = project('draft-older', 'photo-older', 8);
      final latest = project('draft-latest', 'photo-latest', 9);
      final store = MemoryPhotoProjectStore.withProjects([older, latest]);
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('home-scroll')),
        const Offset(0, -520),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('home-delete-draft-draft-older')),
      );
      await tester.tap(
        find.byKey(const ValueKey('home-delete-draft-draft-older')),
      );
      await tester.pumpAndSettle();
      expect(find.text('只会删除映见中的草稿，不会删除系统相册原图。'), findsOne);
      await tester.tap(find.byKey(const ValueKey('home-confirm-delete-draft')));
      await tester.pumpAndSettle();

      expect(store.projects.map((project) => project.id), [latest.id]);
      expect(
        find.byKey(const ValueKey('home-draft-draft-older')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('home-featured-draft-draft-latest')),
        findsOneWidget,
      );
    },
  );

  testWidgets('future meta ops open visibly read-only until update', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final project = PhotoProject(
      id: 'future-project',
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(2026, 8, 20),
      photos: [
        ProjectPhoto(
          id: 'photo-1',
          localPath: photoFile.path,
          originalName: 'future.jpg',
        ),
      ],
      flowState: PhotoProjectFlowState.editing,
      unknownMetaOps: const [
        {
          'id': 'future.generative_relight',
          'version': 7,
          'payload': {'mode': 'cinematic'},
        },
      ],
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: MemoryPhotoProjectStore(project),
      ),
    );
    await tester.pumpAndSettle();

    await _openLegacyEditorRoute(tester);

    expect(
      find.byKey(const ValueKey('project-requires-update')),
      findsOneWidget,
    );
    expect(find.text('需要更新后继续编辑'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('editor-export')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('AI asks for one face then commits one undoable transaction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(
          disableAnimations: true,
          reduceMotion: true,
          highContrast: true,
        );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'project-ai-target',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: [
          ProjectPhoto(
            id: 'photo-1',
            localPath: photoFile.path,
            originalName: '多人合照.png',
          ),
        ],
        flowState: PhotoProjectFlowState.editing,
        focusPhotoId: 'photo-1',
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
        photoAnalyzer: _CountingPhotoAnalyzer(
          portrait: PortraitApplicability.applicable,
          faceSlimTargetCount: 2,
          faceTargetRegions: const [
            NormalizedTargetRegion(
              left: 0.05,
              top: 0.1,
              right: 0.4,
              bottom: 0.65,
            ),
            NormalizedTargetRegion(
              left: 0.58,
              top: 0.12,
              right: 0.94,
              bottom: 0.68,
            ),
          ],
        ),
      ),
    );

    await _openLegacyEditorRoute(tester);
    final targetIds = store.project!.targetRegistries['photo-1']!.targets.keys
        .toList(growable: false);
    await tester.tap(find.byKey(const ValueKey('voice-edit-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('voice-edit-text-field')),
      '皮肤自然一点',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('voice-edit-submit'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(ValueKey('ai-target-${targetIds[0]}')), findsOneWidget);
    expect(find.byKey(ValueKey('ai-target-${targetIds[1]}')), findsOneWidget);
    expect(
      find.byKey(ValueKey('ai-target-overlay-${targetIds[0]}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('ai-target-overlay-${targetIds[1]}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(store.project!.undoHistory, isEmpty);

    await tester.tap(find.byKey(const ValueKey('ai-target-cancel')));
    await tester.pumpAndSettle();
    expect(store.project!.undoHistory, isEmpty);
    expect(find.byKey(ValueKey('ai-target-${targetIds[0]}')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('voice-edit-text-field')),
      '皮肤自然一点',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final secondSubmit = find.byKey(const ValueKey('voice-edit-submit'));
    await tester.ensureVisible(secondSubmit);
    await tester.pumpAndSettle();
    await tester.tap(secondSubmit);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(ValueKey('ai-target-${targetIds[1]}')));
    await tester.pumpAndSettle();

    expect(store.project!.undoHistory, hasLength(1));
    expect(store.project!.undoHistory.single.source, EditSource.ai);
    expect(store.project!.undoHistory.single.changedAddresses, hasLength(3));
    expect(
      store.project!.undoHistory.single.changedAddresses
          .map((address) => address.targetId)
          .toSet(),
      {targetIds[1]},
    );
    expect(find.byKey(const ValueKey('editor-feedback-pill')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
    await tester.pumpAndSettle();
    final tabs = find.descendant(
      of: find.byKey(const ValueKey('editor-adjustment-tabs')),
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('editor-adjustment-tab-');
      }),
    );
    expect(
      (tabs.evaluate().first.widget.key! as ValueKey<String>).value,
      'editor-adjustment-tab-textureSmoothing',
    );
    final smoothing = find.byKey(
      const ValueKey('editor-adjustment-textureSmoothing'),
    );
    expect(
      tester
          .widget<Slider>(
            find.descendant(of: smoothing, matching: find.byType(Slider)),
          )
          .value,
      closeTo(0.5, 0.001),
    );
  });

  testWidgets('AI keeps the safe state when its proposed render fails', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'project-ai-render-failure',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: [
          ProjectPhoto(
            id: 'photo-1',
            localPath: photoFile.path,
            originalName: 'AI 渲染失败.png',
          ),
        ],
        flowState: PhotoProjectFlowState.editing,
        focusPhotoId: 'photo-1',
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        metaOpCapabilities: iosMetaOpCapabilities,
        photoPreviewRenderer: FakePhotoPreviewRenderer.unsupported(),
      ),
    );

    await _pushLegacyEditorRoute(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-edit-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('voice-edit-text-field')),
      '照片亮一点',
    );
    await tester.tap(find.byKey(const ValueKey('voice-edit-submit')));
    await tester.pumpAndSettle();

    expect(store.project!.undoHistory, isEmpty);
    expect(store.project!.sharedStyle.recipe.exposure, 0);
    expect(find.byKey(const ValueKey('voice-edit-text-field')), findsOneWidget);
  });

  testWidgets('starting a new draft keeps the existing draft', (tester) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final project = PhotoProject(
      id: 'project-1',
      createdAt: DateTime(2026, 8, 4),
      updatedAt: DateTime(2026, 8, 5),
      photos: const [
        ProjectPhoto(
          id: 'photo-1',
          localPath: '/private/project/photo.jpg',
          originalName: 'photo.jpg',
        ),
      ],
      flowState: PhotoProjectFlowState.editing,
    );
    final store = MemoryPhotoProjectStore(project);
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        photoImporter: FakePhotoImporter([
          ProjectPhoto(
            id: 'photo-2',
            localPath: photoFile.path,
            originalName: 'second.png',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('apply-style-workspace')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('style-workspace-source-photo')),
      findsOneWidget,
    );
    expect(store.projects.map((draft) => draft.id), contains(project.id));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-draft-project-1')), findsOneWidget);
    expect(store.projects, hasLength(2));
  });

  testWidgets('user imports photos and sees an app-owned preview', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          ProjectPhoto(
            id: 'photo-1',
            localPath: photoFile.path,
            originalName: '周末人像.png',
          ),
        ]),
      ),
    );

    await _openLegacyEditorRoute(tester);

    expect(find.byKey(const ValueKey('photo-preview-photo-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-preview-stage')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-bottom-command-bar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('voice-edit-entry')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-quick-suggestion-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-quick-suggestion-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-quick-suggestion-2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('editor-lighting-track')), findsNothing);
    expect(find.text('无法读取这张照片'), findsNothing);
  });

  testWidgets('default command dock stays reachable at two-times text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([
          ProjectPhoto(
            id: 'large-text-dock-photo',
            localPath: photoFile.path,
            originalName: '大字体.png',
          ),
        ]),
      ),
    );
    await _openLegacyEditorRoute(tester);

    expect(find.byKey(const ValueKey('voice-edit-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-manual-entry')), findsOneWidget);
    for (var index = 0; index < 3; index += 1) {
      expect(
        find.byKey(ValueKey('editor-quick-suggestion-$index')),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey('editor-quick-suggestion-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visual-tracks-dock')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-track-era-tab')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      find.byKey(const ValueKey('visual-track-lighting-tab')),
      findsOneWidget,
    );
  });

  testWidgets(
    'manual adjustments keep the photo visible and support fullscreen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([
            ProjectPhoto(
              id: 'manual-dock-photo',
              localPath: photoFile.path,
              originalName: '全屏预览.png',
            ),
          ]),
          photoPreviewRenderer: FakePhotoPreviewRenderer.supported(),
        ),
      );

      await _openLegacyEditorRoute(tester);
      expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-bottom-command-bar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-quick-suggestion-2')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('editor-page'))).width,
        lessThan(700),
      );
      await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('editor-preview-stage')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('editor-tools-dock')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-tools-sheet')), findsNothing);
      expect(
        find.byKey(const ValueKey('editor-canvas-interaction-hint')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('editor-preview-fullscreen')).hitTestable(),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('editor-fullscreen-preview')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('editor-tools-dock')), findsNothing);
      expect(find.byKey(const ValueKey('editor-export')), findsNothing);
      expect(
        find.byKey(const ValueKey('editor-canvas-interaction-hint')),
        findsNothing,
      );

      tester
          .widget<GestureDetector>(
            find.byKey(const ValueKey('editor-fullscreen-preview-surface')),
          )
          .onTap!();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('editor-fullscreen-preview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-fullscreen-close')),
        findsNothing,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-fullscreen-preview')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('editor-tools-dock')), findsOneWidget);
    },
  );

  testWidgets('a valid single-photo import proceeds without stale failures', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter(
          [
            ProjectPhoto(
              id: 'photo-1',
              localPath: photoFile.path,
              originalName: '可用照片.png',
            ),
          ],
          const [
            PhotoImportFailure(
              photoName: '动态照片.png',
              reason: PhotoImportFailureReason.animatedImage,
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('apply-style-workspace')), findsOneWidget);
    expect(find.textContaining('动态照片.png'), findsNothing);
  });

  testWidgets('a fully rejected import remains recoverable', (tester) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter(const [], const [
          PhotoImportFailure(
            photoName: '损坏照片.jpg',
            reason: PhotoImportFailureReason.unreadable,
          ),
        ]),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-page')), findsNothing);
    expect(find.textContaining('损坏照片.jpg'), findsOneWidget);
    expect(find.textContaining('无法读取'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-import-retry')), findsOneWidget);
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsWidgets);
  });

  testWidgets('cancelled import silently remains on the home page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(settings, photoImporter: FakePhotoImporter()),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-page')), findsNothing);
    expect(find.text('未添加任何照片'), findsNothing);
    expect(find.byKey(const ValueKey('home-apply-style')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-motion')), findsOneWidget);
  });

  testWidgets('import progress is announced while local copying is active', (
    tester,
  ) async {
    final importer = _DeferredPhotoImporter();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings, photoImporter: importer));

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final progress = find.semantics.byPredicate(
      (node) =>
          node.label.contains('正在准备图片') && node.flagsCollection.isLiveRegion,
    );
    expect(progress, findsOne);
    expect(progress.evaluate().single.flagsCollection.isLiveRegion, isTrue);
    expect(find.byKey(const ValueKey('editor-page')), findsNothing);

    importer.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('cancelling photo preparation cleans a late working copy', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final importer = _DeferredPhotoImporter();
    final store = MemoryPhotoProjectStore();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(settings, photoImporter: importer, photoProjectStore: store),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.byKey(const ValueKey('home-cancel-import')));
    await tester.pump();
    importer.complete(
      PhotoImportBatch(
        photos: [
          ProjectPhoto(
            id: 'late-photo',
            localPath: photoFile.path,
            originalName: '迟到照片.png',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-page')), findsNothing);
    expect(store.projects, isEmpty);
  });

  testWidgets('photo picker timeout restores a retryable import button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: _ThrowingPhotoImporter(
          TimeoutException('photo picker did not respond'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-apply-style')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.text('照片导入失败，请重试'), findsOneWidget);
    final retry = find.byKey(const ValueKey('home-import-retry'));
    expect(retry, findsOneWidget);
    expect(tester.widget<TextButton>(retry).onPressed, isNotNull);
    expect(find.text('正在准备图片…'), findsNothing);
  });

  testWidgets('import opens a neutral editor without another decision', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final store = MemoryPhotoProjectStore();
    final previewRenderer = FakePhotoPreviewRenderer.supported();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        photoPreviewRenderer: previewRenderer,
        photoImporter: FakePhotoImporter([
          ProjectPhoto(
            id: 'photo-1',
            localPath: photoFile.path,
            originalName: '推荐样片.png',
          ),
        ]),
      ),
    );

    await _openLegacyEditorRoute(tester);
    expect(previewRenderer.maxEdges, contains(2048));
    expect(store.project?.flowState, PhotoProjectFlowState.editing);
    expect(store.project?.sharedStyle.recipe, EditRecipe.neutral);
    expect(store.project?.adaptiveCompensations, isEmpty);
    expect(find.byKey(const ValueKey('voice-edit-entry')), findsOneWidget);
  });

  testWidgets('restored project reuses analysis before opening the editor', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photo = ProjectPhoto(
      id: 'photo-1',
      localPath: photoFile.path,
      originalName: '推荐样片.png',
      contentSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      pixelWidth: 1024,
      pixelHeight: 1024,
      colorSpace: PhotoColorSpace.srgb,
      inputFormat: PhotoInputFormat.png,
      supportState: PhotoSupportState.supported,
    );
    final store = MemoryPhotoProjectStore();
    final analyzer = _CountingPhotoAnalyzer();
    final cache = MemoryPhotoAnalysisCache();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();

    Widget app() => buildTestApp(
      settings,
      photoProjectStore: store,
      photoImporter: FakePhotoImporter([photo]),
      photoAnalyzer: analyzer,
      photoAnalysisCache: cache,
    );

    await tester.pumpWidget(app());
    await _openLegacyEditorRoute(tester);
    expect(analyzer.calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app());
    await _openLegacyEditorRoute(tester);

    expect(analyzer.calls, 1);
    expect(store.project?.flowState, PhotoProjectFlowState.editing);
    expect(find.byKey(const ValueKey('voice-edit-entry')), findsOneWidget);
  });

  testWidgets('backgrounding analysis discards a late native result', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photo = ProjectPhoto(
      id: 'photo-1',
      localPath: photoFile.path,
      originalName: '后台样片.png',
      contentSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      pixelWidth: 1024,
      pixelHeight: 1024,
      colorSpace: PhotoColorSpace.srgb,
      inputFormat: PhotoInputFormat.png,
      supportState: PhotoSupportState.supported,
    );
    final store = MemoryPhotoProjectStore();
    final analyzer = _DeferredPhotoAnalyzer();
    final cache = MemoryPhotoAnalysisCache();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        photoImporter: FakePhotoImporter([photo]),
        photoAnalyzer: analyzer,
        photoAnalysisCache: cache,
      ),
    );
    await _pushLegacyEditorRoute(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await analyzer.started.future;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    analyzer.complete();
    await tester.pumpAndSettle();

    expect(
      store.project?.analysisStates[photo.id],
      PhotoAnalysisState.fallback,
    );
    expect(
      await cache.read(
        projectId: store.project!.id,
        photo: photo,
        engineIdentity: analyzer.identityFor(photo),
      ),
      isNull,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(store.project?.flowState, PhotoProjectFlowState.editing);
  });

  testWidgets('rapid resume waits for the serialized lifecycle fallback', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photo = ProjectPhoto(
      id: 'photo-1',
      localPath: photoFile.path,
      originalName: '快速恢复.png',
      contentSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      pixelWidth: 1024,
      pixelHeight: 1024,
      colorSpace: PhotoColorSpace.srgb,
      inputFormat: PhotoInputFormat.png,
      supportState: PhotoSupportState.supported,
    );
    final store = _DeferredFallbackProjectStore();
    final analyzer = _DeferredPhotoAnalyzer();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        photoImporter: FakePhotoImporter([photo]),
        photoAnalyzer: analyzer,
      ),
    );
    await _pushLegacyEditorRoute(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await analyzer.started.future;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    analyzer.complete();
    await tester.pump();
    await store.fallbackSaveStarted.future;

    expect(store.project?.flowState, PhotoProjectFlowState.editing);
    store.completeFallbackSave();
    await tester.pumpAndSettle();

    expect(store.project?.flowState, PhotoProjectFlowState.editing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the editor ignores a late analysis completion', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photo = ProjectPhoto(
      id: 'photo-1',
      localPath: photoFile.path,
      originalName: '退出样片.png',
      contentSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      pixelWidth: 1024,
      pixelHeight: 1024,
      colorSpace: PhotoColorSpace.srgb,
      inputFormat: PhotoInputFormat.png,
      supportState: PhotoSupportState.supported,
    );
    final analyzer = _DeferredPhotoAnalyzer();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([photo]),
        photoAnalyzer: analyzer,
      ),
    );
    await _pushLegacyEditorRoute(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await analyzer.started.future;

    await tester.pumpWidget(const SizedBox.shrink());
    analyzer.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a project discards its late analysis and cache', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photo = ProjectPhoto(
      id: 'photo-1',
      localPath: photoFile.path,
      originalName: '删除样片.png',
      contentSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      pixelWidth: 1024,
      pixelHeight: 1024,
      colorSpace: PhotoColorSpace.srgb,
      inputFormat: PhotoInputFormat.png,
      supportState: PhotoSupportState.supported,
    );
    final store = MemoryPhotoProjectStore();
    final analyzer = _DeferredPhotoAnalyzer();
    final cache = MemoryPhotoAnalysisCache();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        photoImporter: FakePhotoImporter([photo]),
        photoAnalyzer: analyzer,
        photoAnalysisCache: cache,
      ),
    );
    await _pushLegacyEditorRoute(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await analyzer.started.future;

    await tester.tap(find.byTooltip('删除项目'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('删除').last);
    await tester.pump();
    analyzer.complete();
    await tester.pumpAndSettle();

    expect(store.project, isNull);
    expect(
      await cache.read(
        projectId: 'project-1',
        photo: photo,
        engineIdentity: analyzer.identityFor(photo),
      ),
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('project deletion drains a claimed analysis state save', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photo = ProjectPhoto(
      id: 'photo-1',
      localPath: photoFile.path,
      originalName: '慢保存删除.png',
      contentSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      pixelWidth: 1024,
      pixelHeight: 1024,
      colorSpace: PhotoColorSpace.srgb,
      inputFormat: PhotoInputFormat.png,
      supportState: PhotoSupportState.supported,
    );
    final store = _DeferredAnalysisStateProjectStore();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        photoImporter: FakePhotoImporter([photo]),
        photoAnalyzer: _CountingPhotoAnalyzer(),
      ),
    );
    await _pushLegacyEditorRoute(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await store.analysisSaveStarted.future;

    await tester.tap(find.byTooltip('删除项目'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('删除').last);
    await tester.pump();
    expect(store.project, isNotNull);

    store.completeAnalysisSave();
    await tester.pumpAndSettle();

    expect(store.project, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('user adjusts a photo and exports from its original', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photo = ProjectPhoto(
      id: 'photo-1',
      localPath: photoFile.path,
      originalName: '周末人像.png',
    );
    final exporter = FakePhotoExporter();
    final sharer = FakePhotoSharer();
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: [photo],
        flowState: PhotoProjectFlowState.editing,
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        photoExporter: exporter,
        photoSharer: sharer,
      ),
    );

    await _openLegacyEditorRoute(tester);

    await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
    await tester.pumpAndSettle();
    final exposureAdjustment = find.byKey(
      const ValueKey('editor-adjustment-exposure'),
    );
    await tester.ensureVisible(exposureAdjustment);
    await tester.pumpAndSettle();
    expect(find.text('高光'), findsOneWidget);
    expect(find.text('阴影'), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-all-tools')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-tool-categories')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'editor-adjustment-tab-',
            ),
      ),
      findsNWidgets(5),
    );
    await tester.drag(
      find.descendant(of: exposureAdjustment, matching: find.byType(Slider)),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    expect(exporter.exportedRecipe, isNull);
    expect(store.project?.undoHistory, hasLength(1));

    final saveButton = find.byKey(const ValueKey('editor-export'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(exporter.exportedPhoto, photo);
    expect(exporter.exportedRecipe?.exposure, greaterThan(0));
    expect(find.text('已保存到系统相册'), findsOneWidget);
    final exportStatesBeforeShare = Map.of(store.project!.exportStates);
    await tester.ensureVisible(find.byKey(const ValueKey('save-share')));
    await tester.tap(find.byKey(const ValueKey('save-share')));
    await _pumpUntilText(tester, '已通过系统分享完成操作');
    expect(sharer.sharedPaths, ['/tmp/Yingjian_fixture.jpg']);
    expect(find.text('已通过系统分享完成操作'), findsOneWidget);
    expect(find.text('分享已保存照片'), findsNothing);
    expect(store.project?.exportStates, exportStatesBeforeShare);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('system share cancellation preserves the saved result', (
    tester,
  ) async {
    final sharer = FakePhotoSharer(outcome: PhotoShareOutcome.canceled);
    final store = await _pumpSinglePhotoExport(tester, sharer);
    final exportStatesBeforeShare = Map.of(store.project!.exportStates);

    await tester.ensureVisible(find.byKey(const ValueKey('save-share')));
    await tester.tap(find.byKey(const ValueKey('save-share')));
    await _pumpUntilText(tester, '已取消分享，成片仍已保存到系统相册');

    expect(find.text('已取消分享，成片仍已保存到系统相册'), findsOneWidget);
    expect(find.text('已保存到系统相册'), findsOneWidget);
    expect(find.text('分享已保存照片'), findsOneWidget);
    expect(store.project?.exportStates, exportStatesBeforeShare);
    await tester.tap(find.byKey(const ValueKey('save-finish')));
    await tester.pumpAndSettle();
    expect(sharer.discardedPaths, ['/tmp/Yingjian_fixture.jpg']);
  });

  testWidgets('saved export replaces editing inputs until finishing', (
    tester,
  ) async {
    final store = await _pumpSinglePhotoExport(tester, FakePhotoSharer());

    expect(find.byKey(const Key('photo-workspace-scroll')), findsNothing);
    expect(find.byKey(const ValueKey('editor-save-success')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-finish')));
    await tester.pumpAndSettle();
    unawaited(
      AppRouter.navigatorKey.currentState!.pushReplacementNamed(AppRoutes.home),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-resume-project')), findsOneWidget);
    final status = find.byKey(
      ValueKey('home-draft-status-${store.project!.id}'),
    );
    expect(status, findsOneWidget);
    expect(tester.widget<Text>(status).data, '已导出');
  });

  testWidgets('an exported draft reopens for editing and can export again', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photo = ProjectPhoto(
      id: 'reexport-photo',
      localPath: photoFile.path,
      originalName: '重新导出.png',
    );
    final project = PhotoProject(
      id: 'reexport-project',
      createdAt: DateTime.utc(2026, 8, 28),
      updatedAt: DateTime.utc(2026, 8, 28),
      photos: [photo],
      flowState: PhotoProjectFlowState.exported,
      exportStates: {photo.id: PhotoExportState.saved},
    );
    final exporter = FakePhotoExporter();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: MemoryPhotoProjectStore(project),
        photoExporter: exporter,
      ),
    );

    await _openLegacyEditorRoute(tester);
    expect(find.byKey(const ValueKey('editor-save-success')), findsNothing);
    expect(find.byKey(const ValueKey('editor-bottom-command-bar')), findsOne);
    await tester.tap(find.byKey(const ValueKey('editor-export')));
    await tester.pumpAndSettle();

    expect(exporter.exportedPhoto, photo);
    expect(find.text('已保存到系统相册'), findsOneWidget);
  });

  testWidgets('system share failure preserves the saved result', (
    tester,
  ) async {
    final sharer = FakePhotoSharer(error: StateError('fixture share failure'));
    final store = await _pumpSinglePhotoExport(tester, sharer);
    final exportStatesBeforeShare = Map.of(store.project!.exportStates);

    await tester.ensureVisible(find.byKey(const ValueKey('save-share')));
    await tester.tap(find.byKey(const ValueKey('save-share')));
    await _pumpUntilText(tester, '暂时无法分享，成片仍已保存到系统相册');

    expect(find.text('暂时无法分享，成片仍已保存到系统相册'), findsOneWidget);
    expect(find.text('已保存到系统相册'), findsOneWidget);
    expect(find.text('分享已保存照片'), findsOneWidget);
    expect(store.project?.exportStates, exportStatesBeforeShare);
  });

  testWidgets('project actions stay disabled while system share is opening', (
    tester,
  ) async {
    final sharer = _DeferredPhotoSharer();
    await _pumpSinglePhotoExport(tester, sharer);

    await tester.ensureVisible(find.byKey(const ValueKey('save-share')));
    await tester.tap(find.byKey(const ValueKey('save-share')));
    await tester.pump();
    await sharer.started.future;

    expect(find.text('正在打开系统分享…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-finish')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('save-share')))
          .onPressed,
      isNull,
    );

    sharer.complete(PhotoShareOutcome.canceled);
    await _pumpUntilText(tester, '已取消分享，成片仍已保存到系统相册');
    expect(find.text('分享已保存照片'), findsOneWidget);
  });

  testWidgets('leaving during a canceled share drains its temporary photo', (
    tester,
  ) async {
    final sharer = _DeferredPhotoSharer();
    await _pumpSinglePhotoExport(tester, sharer);

    await tester.ensureVisible(find.text('分享已保存照片'));
    await tester.tap(find.text('分享已保存照片'));
    await tester.pump();
    await sharer.started.future;
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    sharer.complete(PhotoShareOutcome.canceled);
    for (
      var attempt = 0;
      attempt < 10 && sharer.discardedPaths == null;
      attempt += 1
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(sharer.discardedPaths, ['/tmp/Yingjian_fixture.jpg']);
  });

  testWidgets(
    'an unavailable composition preview is explicit and recoverable',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      final project = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: [
          ProjectPhoto(
            id: 'photo-1',
            localPath: photoFile.path,
            originalName: '构图预览.png',
          ),
        ],
        flowState: PhotoProjectFlowState.editing,
      );
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      final store = MemoryPhotoProjectStore(project);
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoProjectStore: store,
          photoPreviewRenderer: FakePhotoPreviewRenderer.unsupported(),
        ),
      );
      await _pushLegacyEditorRoute(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);
      await _openManualMetaOp(tester, MetaOpIds.compositionGeometry);
      await tester.ensureVisible(find.byTooltip('向左旋转'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('向左旋转'));
      await tester.pumpAndSettle();

      expect(find.textContaining('当前效果预览暂不可用'), findsOneWidget);
      expect(store.project!.effectiveRecipeFor('photo-1').crop.quarterTurns, 0);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'restore original composition clears every geometry edit but preserves the look',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      final look = BasicEditingRecipe(
        filter: PhotoFilter.cinematic,
        filterStrength: 55,
        hsl: {HslChannel.orange: HslAdjustment(saturation: 18)},
        flipHorizontal: true,
        perspectiveVertical: 12,
      );
      final store = MemoryPhotoProjectStore(
        PhotoProject(
          id: 'composition-reset-project',
          createdAt: DateTime.utc(2026, 8, 9),
          updatedAt: DateTime.utc(2026, 8, 9),
          photos: [
            ProjectPhoto(
              id: 'photo-1',
              localPath: photoFile.path,
              originalName: '完整构图复位.png',
            ),
          ],
          flowState: PhotoProjectFlowState.editing,
          photoOverrides: {
            'photo-1': PhotoOverride(
              recipe: EditRecipe(basicEditingRecipe: look),
            ),
          },
        ),
      );
      final previewRenderer = FakePhotoPreviewRenderer.supported();
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoProjectStore: store,
          photoPreviewRenderer: previewRenderer,
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      await _pushLegacyEditorRoute(tester);
      await tester.pumpAndSettle();

      await _openManualMetaOp(tester, MetaOpIds.compositionGeometry);
      final reset = find.widgetWithText(TextButton, '恢复原始构图');
      await tester.ensureVisible(reset);
      expect(tester.widget<TextButton>(reset).onPressed, isNotNull);
      await tester.tap(reset);
      await tester.pumpAndSettle();

      for (
        var attempt = 0;
        attempt < 10 &&
            store
                .project!
                .photoOverrides['photo-1']!
                .recipe
                .basicEditingRecipe
                .flipHorizontal;
        attempt += 1
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(previewRenderer.creates, hasLength(1));
      expect(previewRenderer.updates, isNotEmpty);
      final recipe = store.project!.photoOverrides['photo-1']!.recipe;
      expect(recipe.crop, CropGeometry.original);
      expect(recipe.basicEditingRecipe.flipHorizontal, isFalse);
      expect(recipe.basicEditingRecipe.flipVertical, isFalse);
      expect(recipe.basicEditingRecipe.perspectiveHorizontal, 0);
      expect(recipe.basicEditingRecipe.perspectiveVertical, 0);
      expect(recipe.basicEditingRecipe.filter, PhotoFilter.cinematic);
      expect(recipe.basicEditingRecipe.filterStrength, 55);
      expect(recipe.basicEditingRecipe.hsl[HslChannel.orange]?.saturation, 18);
      expect(store.project?.undoHistory, hasLength(1));

      final portraitFourThree = find.byKey(const ValueKey('editor-crop-3-4'));
      final portraitSixteenNine = find.byKey(
        const ValueKey('editor-crop-9-16'),
      );
      expect(portraitFourThree, findsOneWidget);
      expect(portraitSixteenNine, findsOneWidget);
      await tester.tap(portraitFourThree);
      await tester.pumpAndSettle();
      final crop = store.project!.photoOverrides['photo-1']!.recipe.crop;
      final displayedRatio =
          ((crop.right - crop.left) * 4) / ((crop.bottom - crop.top) * 3);
      expect(displayedRatio, closeTo(3 / 4, 0.001));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('a non-composition V2 preview failure is not misclassified', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final project = PhotoProject(
      id: 'project-v2-color',
      createdAt: DateTime.utc(2026, 8, 5),
      updatedAt: DateTime.utc(2026, 8, 5),
      photos: [
        ProjectPhoto(
          id: 'photo-1',
          localPath: photoFile.path,
          originalName: '清晰度预览.png',
        ),
      ],
      flowState: PhotoProjectFlowState.editing,
      sharedStyle: SharedStyle(
        family: SharedStyleFamily.naturalClean,
        recipe: EditRecipe(clarity: 0.2),
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: MemoryPhotoProjectStore(project),
        photoPreviewRenderer: FakePhotoPreviewRenderer.unsupported(),
      ),
    );

    await _openLegacyEditorRoute(tester);

    expect(find.textContaining('当前效果预览暂不可用'), findsOneWidget);
    expect(find.textContaining('构图预览暂不可用'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('applicable portrait exposes one undoable natural retouch control', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photo = ProjectPhoto(
      id: 'portrait-photo',
      localPath: photoFile.path,
      originalName: '已有照片人像.png',
      contentSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      pixelWidth: 1024,
      pixelHeight: 1024,
      colorSpace: PhotoColorSpace.srgb,
      inputFormat: PhotoInputFormat.png,
      supportState: PhotoSupportState.supported,
    );
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'portrait-project',
        createdAt: DateTime.utc(2026, 8, 5),
        updatedAt: DateTime.utc(2026, 8, 5),
        photos: [photo],
        flowState: PhotoProjectFlowState.editing,
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: photo.id,
      ),
    );
    final cache = MemoryPhotoAnalysisCache();
    final cachedWrite = await cache.stage(
      projectId: 'portrait-project',
      photoId: photo.id,
      analysis: LocalPhotoAnalysis(
        analysisVersion: 'widget-analysis-v1',
        capabilityVersion: 'widget-capability-v1',
        contentSha256: photo.contentSha256,
        orientation: photo.orientation,
        pixelWidth: photo.pixelWidth,
        pixelHeight: photo.pixelHeight,
        colorSpace: photo.colorSpace,
        disposition: PhotoAnalysisDisposition.ready,
        fallbackReason: AnalysisFallbackReason.none,
        portrait: PortraitApplicability.applicable,
        faceSlimTargetCount: 2,
        faceTargetRegions: const [
          NormalizedTargetRegion(
            left: 0.12,
            top: 0.18,
            right: 0.38,
            bottom: 0.5,
          ),
          NormalizedTargetRegion(
            left: 0.62,
            top: 0.18,
            right: 0.88,
            bottom: 0.5,
          ),
        ],
        body: PortraitApplicability.applicable,
        bodyTargetCount: 2,
        bodyTargetRegions: const [
          NormalizedTargetRegion(
            left: 0.05,
            top: 0.34,
            right: 0.44,
            bottom: 0.92,
          ),
          NormalizedTargetRegion(
            left: 0.56,
            top: 0.34,
            right: 0.95,
            bottom: 0.92,
          ),
        ],
      ),
    );
    await cache.commit(cachedWrite, canCommit: () => true);
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    final backgroundImporter = FakePhotoImporter([
      ProjectPhoto(
        id: 'background-photo',
        localPath: photoFile.path,
        originalName: '背景.png',
        contentSha256:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
    ]);
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: backgroundImporter,
        photoProjectStore: store,
        photoAnalyzer: _CountingPhotoAnalyzer(
          portrait: PortraitApplicability.applicable,
          faceSlimTargetCount: 2,
          body: PortraitApplicability.applicable,
          bodyTargetCount: 2,
        ),
        metaOpCapabilities: iosMetaOpCapabilities,
        photoAnalysisCache: cache,
        photoPreviewRenderer: FakePhotoPreviewRenderer.supported(),
      ),
    );

    await _openLegacyEditorRoute(tester);
    await _openManualMetaOp(tester, MetaOpIds.skinSmooth);
    await tester.ensureVisible(
      find.byKey(const ValueKey('editor-adjustment-tab-naturalBeautification')),
    );
    await tester.pumpAndSettle();
    final portraitTab = find.byKey(
      const ValueKey('editor-adjustment-tab-naturalBeautification'),
    );
    expect(portraitTab.hitTestable(), findsOneWidget);
    for (final category in [
      'composition',
      'color',
      'filters',
      'quality',
      'retouch',
      'semantic',
    ]) {
      expect(
        find.byKey(ValueKey('editor-tool-category-$category')),
        findsNothing,
      );
    }
    final exposureTab = find.byKey(
      const ValueKey('editor-adjustment-tab-exposure'),
    );
    expect(exposureTab, findsNothing);
    await tester.tap(portraitTab);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-apply-one-tap-natural-beautification')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-adjustment-section')),
      findsOneWidget,
    );
    expect(find.text('人像'), findsWidgets);
    final faceSlimTab = find.byKey(
      const ValueKey('editor-adjustment-tab-faceSlim'),
    );
    expect(faceSlimTab.hitTestable(), findsOneWidget);
    await _openManualMetaOp(tester, MetaOpIds.exposure);
    expect(exposureTab, findsOneWidget);
    await tester.tap(exposureTab);
    await tester.pumpAndSettle();
    final exposureSemantics = tester.getSemantics(
      find.descendant(
        of: find.byKey(const ValueKey('editor-adjustment-exposure')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.slider == true,
        ),
      ),
    );
    expect(exposureSemantics.label, isNotEmpty);
    expect(exposureSemantics.value, '0');
    expect(
      exposureSemantics.getSemanticsData().hasAction(SemanticsAction.increase),
      isTrue,
    );
    expect(
      exposureSemantics.getSemanticsData().hasAction(SemanticsAction.decrease),
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('editor-adjustment-tab-faceSlim')),
      findsNothing,
    );
    await _openManualMetaOp(tester, MetaOpIds.noiseReduction);
    await tester.tap(
      find.byKey(const ValueKey('editor-adjustment-tab-qualityImprovement')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-apply-quality-improvement')),
      findsOneWidget,
    );
    await _openManualMetaOp(tester, MetaOpIds.skinSmooth);
    await tester.tap(portraitTab);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-adjustment-tab-textureSmoothing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-adjustment-tab-skinToneLighting')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-adjustment-tab-blemishReduction')),
      findsOneWidget,
    );
    expect(store.project!.targetRegistries[photo.id]!.targets, hasLength(4));
    await tester.ensureVisible(
      find.byKey(const ValueKey('editor-apply-one-tap-natural-beautification')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editor-apply-one-tap-natural-beautification')),
    );
    await tester.pumpAndSettle();
    var targetedPortraitRecipe = store.project!
        .effectiveRecipeFor(photo.id)
        .targetedPortraitRecipe;
    expect(targetedPortraitRecipe.adjustments, hasLength(2));
    for (final adjustment in targetedPortraitRecipe.adjustments.values) {
      expect(adjustment.textureSmoothing, 50);
      expect(adjustment.skinToneLighting, 50);
      expect(adjustment.blemishReduction, 20);
    }

    final textureSmoothingTab = find.byKey(
      const ValueKey('editor-adjustment-tab-textureSmoothing'),
    );
    await tester.tap(textureSmoothingTab);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-stable-face-target-selector')),
      findsOneWidget,
    );
    final secondStableFaceOverlay = find.byKey(
      const ValueKey('portrait-target-overlay-1'),
    );
    tester
        .widget<GestureDetector>(
          find.descendant(
            of: secondStableFaceOverlay,
            matching: find.byType(GestureDetector),
          ),
        )
        .onTap!();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-stable-face-target-selector')),
      findsNothing,
    );
    final textureSmoothingControl = find.descendant(
      of: find.byKey(const ValueKey('editor-adjustment-textureSmoothing')),
      matching: find.byType(Slider),
    );
    expect(textureSmoothingControl, findsOneWidget);
    final textureSmoothingSlider = tester.widget<Slider>(
      textureSmoothingControl,
    );
    textureSmoothingSlider.onChangeStart!(textureSmoothingSlider.value);
    textureSmoothingSlider.onChanged!(0.8);
    textureSmoothingSlider.onChangeEnd!(0.8);
    await tester.pumpAndSettle();
    expect(find.text('无法保存本次调整，请重试'), findsNothing);
    expect(
      tester.widget<Slider>(textureSmoothingControl).value,
      greaterThan(0.5),
    );
    targetedPortraitRecipe = store.project!
        .effectiveRecipeFor(photo.id)
        .targetedPortraitRecipe;
    expect(
      targetedPortraitRecipe.adjustments.values.where(
        (adjustment) => adjustment.textureSmoothing > 50,
      ),
      hasLength(1),
    );

    await tester.ensureVisible(faceSlimTab);
    await tester.pumpAndSettle();
    await tester.tap(faceSlimTab);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-face-slim-target-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-face-slim-target-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-face-target-selector')),
      findsOneWidget,
    );
    final secondFaceOverlay = find.byKey(
      const ValueKey('portrait-target-overlay-1'),
    );
    expect(secondFaceOverlay, findsOneWidget);
    expect(tester.getSize(secondFaceOverlay).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(secondFaceOverlay).height, greaterThanOrEqualTo(44));
    final faceSlimSlider = find.semantics.byPredicate(
      (node) => node.label.startsWith('瘦脸') && node.flagsCollection.isSlider,
    );
    expect(faceSlimSlider, findsOne);
    expect(
      find.byKey(const ValueKey('editor-adjustment-faceSlim')),
      findsOneWidget,
    );
    final faceSlimControl = find.descendant(
      of: find.byKey(const ValueKey('editor-adjustment-faceSlim')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(faceSlimControl);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(faceSlimControl).max, 0.5);
    var faceSlimWidget = tester.widget<Slider>(faceSlimControl);
    faceSlimWidget.onChangeStart!(faceSlimWidget.value);
    faceSlimWidget.onChanged!(0.2);
    faceSlimWidget.onChangeEnd!(0.2);
    await tester.pumpAndSettle();
    final firstFaceStrength = (await store.loadLatest())!
        .effectiveRecipeFor(photo.id)
        .faceSlimRecipe
        .targetStrengths[0];
    expect(firstFaceStrength, greaterThan(0));
    await tester.ensureVisible(secondFaceOverlay);
    await tester.pumpAndSettle();
    tester
        .widget<GestureDetector>(
          find.descendant(
            of: secondFaceOverlay,
            matching: find.byType(GestureDetector),
          ),
        )
        .onTap!();
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(faceSlimControl).value, 0);
    faceSlimWidget = tester.widget<Slider>(faceSlimControl);
    faceSlimWidget.onChangeStart!(faceSlimWidget.value);
    faceSlimWidget.onChanged!(0.15);
    faceSlimWidget.onChangeEnd!(0.15);
    await tester.pumpAndSettle();
    final multiFaceRecipe = (await store.loadLatest())!
        .effectiveRecipeFor(photo.id)
        .faceSlimRecipe;
    expect(multiFaceRecipe.targetStrengths[0], firstFaceStrength);
    expect(multiFaceRecipe.targetStrengths[1], greaterThan(0));
    expect(
      (await store.loadLatest())?.effectiveRecipeFor(photo.id).faceSlimStrength,
      greaterThan(0),
    );
    final headSizeTab = find.byKey(
      const ValueKey('editor-adjustment-tab-headSize'),
    );
    await tester.ensureVisible(headSizeTab);
    await tester.pumpAndSettle();
    expect(headSizeTab.hitTestable(), findsOneWidget);
    await tester.tap(headSizeTab);
    await tester.pumpAndSettle();
    final headSizeControl = find.descendant(
      of: find.byKey(const ValueKey('editor-adjustment-headSize')),
      matching: find.byType(Slider),
    );
    final headSizeWidget = tester.widget<Slider>(headSizeControl);
    headSizeWidget.onChangeStart!(headSizeWidget.value);
    headSizeWidget.onChanged!(0.2);
    headSizeWidget.onChangeEnd!(0.2);
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())!
          .effectiveRecipeFor(photo.id)
          .portraitGeometryRecipe
          .faceTargets[1]
          .headSize,
      greaterThan(0),
    );
    final bodySlimTab = find.byKey(
      const ValueKey('editor-adjustment-tab-bodySlim'),
    );
    await tester.ensureVisible(bodySlimTab);
    await tester.pumpAndSettle();
    expect(bodySlimTab.hitTestable(), findsOneWidget);
    await tester.tap(bodySlimTab);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-body-target-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-body-target-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-body-target-selector')),
      findsOneWidget,
    );
    final secondBodyOverlay = find.byKey(
      const ValueKey('portrait-target-overlay-1'),
    );
    await tester.ensureVisible(secondBodyOverlay);
    await tester.pumpAndSettle();
    tester
        .widget<GestureDetector>(
          find.descendant(
            of: secondBodyOverlay,
            matching: find.byType(GestureDetector),
          ),
        )
        .onTap!();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('editor-body-target-1')),
          )
          .selected,
      isTrue,
    );
    final bodySlimControl = find.descendant(
      of: find.byKey(const ValueKey('editor-adjustment-bodySlim')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(bodySlimControl);
    await tester.pumpAndSettle();
    expect(bodySlimControl, findsOneWidget);
    expect(tester.widget<Slider>(bodySlimControl).max, 0.35);
    final bodySlimWidget = tester.widget<Slider>(bodySlimControl);
    bodySlimWidget.onChangeStart!(bodySlimWidget.value);
    bodySlimWidget.onChanged!(0.2);
    bodySlimWidget.onChangeEnd!(0.2);
    await tester.pumpAndSettle();
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .portraitGeometryRecipe
          .selectedBodyIndex,
      1,
    );
    expect(
      (await store.loadLatest())?.effectiveRecipeFor(photo.id).bodySlimStrength,
      greaterThan(0),
    );
    final recipe = store.project!.effectiveRecipeFor('portrait-photo');
    expect(recipe.portraitStrength, 0);
    expect(recipe.targetedPortraitRecipe.adjustments, hasLength(2));
    expect(find.text('选择人像'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('editor-undo')));
    await tester.pumpAndSettle();
    expect(store.project!.effectiveRecipeFor(photo.id).bodySlimStrength, 0);
    await tester.tap(find.byKey(const ValueKey('editor-undo')));
    await tester.pumpAndSettle();
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .portraitGeometryRecipe
          .faceTargets[1]
          .headSize,
      0,
    );
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .faceSlimRecipe
          .targetStrengths[1],
      greaterThan(0),
    );
    await tester.tap(find.byKey(const ValueKey('editor-undo')));
    await tester.pumpAndSettle();
    expect(
      store.project!.effectiveRecipeFor(photo.id).faceSlimStrength,
      firstFaceStrength,
    );
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .faceSlimRecipe
          .targetStrengths[0],
      firstFaceStrength,
    );
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .faceSlimRecipe
          .targetStrengths[1],
      0,
    );
    await tester.tap(find.byKey(const ValueKey('editor-undo')));
    await tester.pumpAndSettle();
    expect(store.project!.effectiveRecipeFor(photo.id).faceSlimStrength, 0);
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .targetedPortraitRecipe
          .adjustments
          .values
          .where((adjustment) => adjustment.textureSmoothing > 50),
      hasLength(1),
    );
    await tester.tap(find.byKey(const ValueKey('editor-undo')));
    await tester.pumpAndSettle();
    targetedPortraitRecipe = store.project!
        .effectiveRecipeFor(photo.id)
        .targetedPortraitRecipe;
    expect(targetedPortraitRecipe.adjustments, hasLength(2));
    expect(
      targetedPortraitRecipe.adjustments.values.every(
        (adjustment) => adjustment.textureSmoothing == 50,
      ),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('editor-undo')));
    await tester.pumpAndSettle();
    targetedPortraitRecipe = store.project!
        .effectiveRecipeFor(photo.id)
        .targetedPortraitRecipe;
    expect(targetedPortraitRecipe.isNeutral, isTrue);

    await _openManualMetaOp(tester, MetaOpIds.semanticAdjustments);
    expect(find.byKey(const ValueKey('editor-semantic-tools')), findsOneWidget);
    final whiteBackground = find.byKey(
      const ValueKey('editor-background-white'),
    );
    await tester.ensureVisible(whiteBackground);
    await tester.pumpAndSettle();
    expect(whiteBackground.hitTestable(), findsOneWidget);
    await tester.tap(whiteBackground);
    await tester.pumpAndSettle();
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .semanticEditingRecipe
          .background,
      BackgroundTreatment.white,
    );
    final imageBackground = find.byKey(
      const ValueKey('editor-background-image'),
    );
    await Scrollable.ensureVisible(tester.element(imageBackground));
    await tester.pumpAndSettle();
    await tester.tap(imageBackground);
    await tester.pumpAndSettle();
    expect(backgroundImporter.editingResourceImportCount, 1);
    expect(backgroundImporter.lastImportedEditingResource, isNotNull);
    expect(find.text('无法保存本次调整，请重试'), findsNothing);
    expect(
      store.project!.editingResources.resources.keys,
      contains(
        'resource-v1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
    );
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .semanticEditingRecipe
          .background,
      BackgroundTreatment.image,
    );
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .semanticEditingRecipe
          .backgroundImagePath,
      photoFile.path,
    );
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .semanticEditingRecipe
          .backgroundImageResourceId,
      'resource-v1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    final subjectMaskButton = find.byKey(
      const ValueKey('editor-open-subject-mask-brush'),
    );
    await tester.dragUntilVisible(
      subjectMaskButton,
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -260),
    );
    await tester.tap(subjectMaskButton);
    await tester.pumpAndSettle();
    final subjectMaskCanvas = find.semantics.byPredicate(
      (node) =>
          node.label == '主体蒙版' &&
          node.getSemanticsData().hasAction(SemanticsAction.tap),
    );
    final subjectMaskSemantics = subjectMaskCanvas
        .evaluate()
        .single
        .getSemanticsData();
    expect(subjectMaskSemantics.label, '主体蒙版');
    expect(subjectMaskSemantics.hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(subjectMaskCanvas);
    await tester.pumpAndSettle();
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .semanticEditingRecipe
          .subjectMaskStrokes,
      isNotEmpty,
    );
    expect(find.byKey(const ValueKey('subject-mask-apply')), findsNothing);
    final subjectUndo = find.byKey(const ValueKey('subject-mask-undo'));
    final subjectRedo = find.byKey(const ValueKey('subject-mask-redo'));
    await tester.ensureVisible(subjectUndo);
    await tester.pump();
    expect(tester.widget<IconButton>(subjectUndo).onPressed, isNotNull);
    await tester.tap(subjectUndo);
    await tester.pumpAndSettle();
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .semanticEditingRecipe
          .subjectMaskStrokes,
      isEmpty,
    );
    await tester.ensureVisible(subjectRedo);
    await tester.pump();
    expect(tester.widget<IconButton>(subjectRedo).onPressed, isNotNull);
    await tester.tap(subjectRedo);
    await tester.pumpAndSettle();
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .semanticEditingRecipe
          .subjectMaskStrokes,
      isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('subject-mask-close')));
    await tester.pumpAndSettle();
    final localExposure = find.descendant(
      of: find.byKey(const ValueKey('editor-local-exposure')),
      matching: find.byType(Slider),
    );
    await tester.dragUntilVisible(
      localExposure,
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -260),
    );
    await tester.drag(localExposure, const Offset(60, 0));
    await tester.pumpAndSettle();
    final localBrushButton = find.byKey(
      const ValueKey('editor-open-local-adjustment-brush'),
    );
    await tester.dragUntilVisible(
      localBrushButton,
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -260),
    );
    await tester.tap(localBrushButton);
    await tester.pumpAndSettle();
    final localMaskCanvas = find.semantics.byPredicate(
      (node) =>
          node.label == '局部光色' &&
          node.getSemanticsData().hasAction(SemanticsAction.tap),
    );
    final localMaskSemantics = localMaskCanvas
        .evaluate()
        .single
        .getSemanticsData();
    expect(localMaskSemantics.label, '局部光色');
    expect(localMaskSemantics.hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(localMaskCanvas);
    await tester.pumpAndSettle();
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .semanticEditingRecipe
          .localAdjustmentStrokes,
      isNotEmpty,
    );
    expect(find.byKey(const ValueKey('local-mask-apply')), findsNothing);
    final localUndo = find.byKey(const ValueKey('local-mask-undo'));
    final localRedo = find.byKey(const ValueKey('local-mask-redo'));
    await tester.ensureVisible(localUndo);
    await tester.pump();
    expect(tester.widget<IconButton>(localUndo).onPressed, isNotNull);
    await tester.tap(localUndo);
    await tester.pumpAndSettle();
    await tester.ensureVisible(localRedo);
    await tester.pump();
    expect(tester.widget<IconButton>(localRedo).onPressed, isNotNull);
    await tester.tap(localRedo);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('local-mask-close')));
    await tester.pumpAndSettle();
    final semantic = store.project!
        .effectiveRecipeFor(photo.id)
        .semanticEditingRecipe;
    expect(semantic.localExposure, greaterThan(0));
    expect(semantic.localAdjustmentStrokes, isNotEmpty);
    final eraseButton = find.byKey(const ValueKey('editor-open-erase-brush'));
    await tester.dragUntilVisible(
      eraseButton,
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -260),
    );
    await Scrollable.ensureVisible(tester.element(eraseButton), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(eraseButton);
    await tester.pumpAndSettle();
    final eraseCanvas = find.semantics.byPredicate(
      (node) =>
          node.label == '消除笔' &&
          node.getSemanticsData().hasAction(SemanticsAction.tap),
    );
    final eraseCanvasSemantics = eraseCanvas
        .evaluate()
        .single
        .getSemanticsData();
    expect(eraseCanvasSemantics.label, '消除笔');
    expect(eraseCanvasSemantics.hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(eraseCanvas);
    await tester.pumpAndSettle();
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .semanticEditingRecipe
          .eraseStrokes,
      isNotEmpty,
    );
    expect(find.byKey(const ValueKey('erase-brush-apply')), findsNothing);
    final eraseUndo = find.byKey(const ValueKey('erase-brush-undo'));
    final eraseRedo = find.byKey(const ValueKey('erase-brush-redo'));
    await tester.ensureVisible(eraseUndo);
    await tester.pump();
    expect(tester.widget<IconButton>(eraseUndo).onPressed, isNotNull);
    await tester.tap(eraseUndo);
    await tester.pumpAndSettle();
    await tester.ensureVisible(eraseRedo);
    await tester.pump();
    expect(tester.widget<IconButton>(eraseRedo).onPressed, isNotNull);
    await tester.tap(eraseRedo);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('erase-brush-close')));
    await tester.pumpAndSettle();
    expect(
      store.project!
          .effectiveRecipeFor(photo.id)
          .semanticEditingRecipe
          .eraseStrokes,
      isNotEmpty,
    );
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'failed mask save discards its draft resource and keeps the safe state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      final photo = ProjectPhoto(
        id: 'failed-mask-photo',
        localPath: photoFile.path,
        originalName: '蒙版保存失败.png',
        contentSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        pixelWidth: 1024,
        pixelHeight: 1024,
        colorSpace: PhotoColorSpace.srgb,
        inputFormat: PhotoInputFormat.png,
        supportState: PhotoSupportState.supported,
      );
      final project = PhotoProject(
        id: 'failed-mask-project',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: [photo],
        flowState: PhotoProjectFlowState.editing,
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: photo.id,
      );
      final cache = MemoryPhotoAnalysisCache();
      final analyzer = _CountingPhotoAnalyzer(
        portrait: PortraitApplicability.applicable,
      );
      final cachedWrite = await cache.stage(
        projectId: project.id,
        photoId: photo.id,
        analysis: LocalPhotoAnalysis(
          analysisVersion: 'widget-analysis-v1',
          capabilityVersion: 'widget-capability-v1',
          contentSha256: photo.contentSha256,
          orientation: photo.orientation,
          pixelWidth: photo.pixelWidth,
          pixelHeight: photo.pixelHeight,
          colorSpace: photo.colorSpace,
          disposition: PhotoAnalysisDisposition.ready,
          fallbackReason: AnalysisFallbackReason.none,
          portrait: PortraitApplicability.applicable,
        ),
      );
      await cache.commit(cachedWrite, canCommit: () => true);
      final importer = FakePhotoImporter();
      final store = _ArmableFailProjectStore(project);
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: importer,
          photoProjectStore: store,
          photoAnalyzer: analyzer,
          photoAnalysisCache: cache,
          metaOpCapabilities: iosMetaOpCapabilities,
          photoPreviewRenderer: FakePhotoPreviewRenderer.supported(),
        ),
      );
      await _openLegacyEditorRoute(tester);
      await _openManualMetaOp(tester, MetaOpIds.semanticAdjustments);
      store.failSaves = true;
      expect(
        find.byKey(const ValueKey('editor-semantic-tools')),
        findsOneWidget,
      );
      final subjectMaskButton = find.byKey(
        const ValueKey('editor-open-subject-mask-brush'),
      );
      await tester.dragUntilVisible(
        subjectMaskButton,
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, -260),
      );
      await tester.tap(subjectMaskButton);
      await tester.pumpAndSettle();
      tester.semantics.tap(
        find.semantics.byPredicate(
          (node) =>
              node.label == '主体蒙版' &&
              node.getSemanticsData().hasAction(SemanticsAction.tap),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('无法保存本次调整，请重试'), findsOneWidget);
      expect(importer.lastImportedEditingResource, isNotNull);
      expect(importer.discardedEditingResourceIds, [
        importer.lastImportedEditingResource!.descriptor.id,
      ]);
      expect(
        store.project
            .effectiveRecipeFor(photo.id)
            .semanticEditingRecipe
            .subjectMaskStrokes,
        isEmpty,
      );
      expect(store.project.editingResources.resources, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'restored editing project refreshes stale portrait capability cache',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      final photo = ProjectPhoto(
        id: 'stale-portrait-photo',
        localPath: photoFile.path,
        originalName: '升级前已有人像.jpg',
        contentSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        pixelWidth: 1024,
        pixelHeight: 1024,
        colorSpace: PhotoColorSpace.srgb,
        inputFormat: PhotoInputFormat.jpeg,
        supportState: PhotoSupportState.supported,
      );
      final store = MemoryPhotoProjectStore(
        PhotoProject(
          id: 'stale-portrait-project',
          createdAt: DateTime.utc(2026, 8, 5),
          updatedAt: DateTime.utc(2026, 8, 5),
          photos: [photo],
          flowState: PhotoProjectFlowState.editing,
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: photo.id,
          analysisStates: {photo.id: PhotoAnalysisState.ready},
        ),
      );
      final cache = MemoryPhotoAnalysisCache();
      final staleWrite = await cache.stage(
        projectId: store.project!.id,
        photoId: photo.id,
        analysis: LocalPhotoAnalysis(
          analysisVersion: 'widget-analysis-v1',
          capabilityVersion: 'widget-capability-v0',
          contentSha256: photo.contentSha256,
          orientation: photo.orientation,
          pixelWidth: photo.pixelWidth,
          pixelHeight: photo.pixelHeight,
          colorSpace: photo.colorSpace,
          disposition: PhotoAnalysisDisposition.ready,
          fallbackReason: AnalysisFallbackReason.none,
          portrait: PortraitApplicability.unavailable,
          body: PortraitApplicability.unavailable,
        ),
      );
      await cache.commit(staleWrite, canCommit: () => true);
      final analyzer = _CountingPhotoAnalyzer(
        portrait: PortraitApplicability.applicable,
        faceSlim: PortraitApplicability.unsafe,
        faceSlimReason: PortraitDegradationReason.backgroundRisk,
        body: PortraitApplicability.unavailable,
        capabilityVersion: 'widget-capability-v2',
      );
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();

      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoProjectStore: store,
          photoAnalyzer: analyzer,
          photoAnalysisCache: cache,
          metaOpCapabilities: iosMetaOpCapabilities,
          photoPreviewRenderer: FakePhotoPreviewRenderer.supported(),
        ),
      );
      await _pushLegacyEditorRoute(tester);
      await tester.pumpAndSettle();

      expect(analyzer.calls, 1);
      expect(store.project?.flowState, PhotoProjectFlowState.editing);
      await _openManualMetaOp(tester, MetaOpIds.bodyGeometry);
      expect(
        find.byKey(const ValueKey('editor-body-tools-unavailable')),
        findsOneWidget,
      );
      await _openManualMetaOp(tester, MetaOpIds.skinSmooth);
      await tester.dragUntilVisible(
        find.byKey(
          const ValueKey('editor-adjustment-tab-naturalBeautification'),
        ),
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, -220),
      );
      expect(
        find
            .byKey(
              const ValueKey('editor-adjustment-tab-naturalBeautification'),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        find
            .byKey(const ValueKey('editor-adjustment-tab-faceSlim'))
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-face-slim-unavailable')),
        findsNothing,
      );
      await tester.tap(
        find
            .byKey(const ValueKey('editor-adjustment-tab-faceSlim'))
            .hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-face-slim-unavailable')),
        findsOneWidget,
      );
      expect(find.text('当前画面的背景线条与面部区域重叠，瘦脸暂不生效'), findsOneWidget);
      expect(
        find
            .byKey(const ValueKey('editor-adjustment-tab-bodySlim'))
            .hitTestable(),
        findsOneWidget,
      );
      await tester.tap(
        find
            .byKey(const ValueKey('editor-adjustment-tab-bodySlim'))
            .hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-body-tools-unavailable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-adjustment-bodySlim')),
        findsNothing,
      );
      expect(
        await cache.read(
          projectId: store.project!.id,
          photo: photo,
          engineIdentity: analyzer.identityFor(photo),
        ),
        isNotNull,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('project restore failure has a visible retry state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(settings, photoProjectStore: _FailingProjectStore()),
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.text('需要恢复'), findsOneWidget);
    expect(find.text('无法恢复上次项目'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsWidgets);
  });

  testWidgets(
    'manual edit blocks export and route exit until its atomic save completes',
    (tester) async {
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      final project = PhotoProject(
        id: 'pending-edit-project',
        createdAt: DateTime.utc(2026, 8, 28),
        updatedAt: DateTime.utc(2026, 8, 28),
        photos: [
          ProjectPhoto(
            id: 'pending-edit-photo',
            localPath: photoFile.path,
            originalName: '等待保存.png',
          ),
        ],
        flowState: PhotoProjectFlowState.editing,
      );
      final store = _DeferredEditProjectStore(project);
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
      await _openLegacyEditorRoute(tester);
      await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
      await tester.pumpAndSettle();

      store.deferNextSave();
      final adjustment = find.byKey(
        const ValueKey('editor-adjustment-exposure'),
      );
      await tester.ensureVisible(adjustment);
      final slider = tester.widget<Slider>(
        find.descendant(of: adjustment, matching: find.byType(Slider)),
      );
      final changedValue = (slider.value + 0.1).clamp(slider.min, slider.max);
      slider.onChangeStart!(slider.value);
      slider.onChanged!(changedValue);
      slider.onChangeEnd!(changedValue);
      for (var attempt = 0; attempt < 10; attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
        if (store.saveStarted.isCompleted) break;
      }
      expect(store.saveStarted.isCompleted, isTrue);

      expect(find.byKey(const ValueKey('editor-edit-save-pending')), findsOne);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('editor-export')))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-tools-dock')), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);

      store.completeSave();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
      expect(store.project.undoHistory, hasLength(1));
    },
  );

  testWidgets(
    'failed manual edit save offers inline retry and discard without corrupting history',
    (tester) async {
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      final project = PhotoProject(
        id: 'failed-edit-project',
        createdAt: DateTime.utc(2026, 8, 28),
        updatedAt: DateTime.utc(2026, 8, 28),
        photos: [
          ProjectPhoto(
            id: 'failed-edit-photo',
            localPath: photoFile.path,
            originalName: '保存恢复.png',
          ),
        ],
        flowState: PhotoProjectFlowState.editing,
      );
      final store = _ArmableFailProjectStore(project)..failSaves = true;
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
      await _openLegacyEditorRoute(tester);
      await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
      await tester.pumpAndSettle();

      final adjustment = find.byKey(
        const ValueKey('editor-adjustment-exposure'),
      );
      await tester.ensureVisible(adjustment);
      final initialSlider = tester.widget<Slider>(
        find.descendant(of: adjustment, matching: find.byType(Slider)),
      );
      final initialValue = (initialSlider.value + 0.1).clamp(
        initialSlider.min,
        initialSlider.max,
      );
      initialSlider.onChangeStart!(initialSlider.value);
      initialSlider.onChanged!(initialValue);
      initialSlider.onChangeEnd!(initialValue);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('editor-edit-save-failed')), findsOne);
      expect(find.text('本次调整尚未保存，当前仍显示上次安全结果。'), findsOne);
      expect(find.byKey(const ValueKey('editor-edit-save-retry')), findsOne);
      expect(find.byKey(const ValueKey('editor-edit-save-discard')), findsOne);
      expect(store.project.undoHistory, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('editor-export')))
            .onPressed,
        isNull,
      );

      store.failSaves = false;
      await tester.tap(find.byKey(const ValueKey('editor-edit-save-retry')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-edit-save-failed')),
        findsNothing,
      );
      expect(store.project.undoHistory, hasLength(1));

      store.failSaves = true;
      final slider = tester.widget<Slider>(
        find.descendant(of: adjustment, matching: find.byType(Slider)),
      );
      slider.onChangeStart!(slider.value);
      slider.onChanged!((slider.value - 0.1).clamp(slider.min, slider.max));
      slider.onChangeEnd!((slider.value - 0.1).clamp(slider.min, slider.max));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-edit-save-failed')), findsOne);
      await tester.tap(find.byKey(const ValueKey('editor-edit-save-discard')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-edit-save-failed')),
        findsNothing,
      );
      expect(store.project.undoHistory, hasLength(1));
    },
  );

  testWidgets('a complete export failure remains retryable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() async {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final project = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      photos: [
        ProjectPhoto(
          id: 'photo-1',
          localPath: photoFile.path,
          originalName: '导出失败.png',
        ),
      ],
      flowState: PhotoProjectFlowState.editing,
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: MemoryPhotoProjectStore(project),
        photoExporter: _AlwaysFailPhotoExporter(),
      ),
    );
    await _openLegacyEditorRoute(tester);
    final saveButton = find.byKey(const ValueKey('editor-export'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('暂时无法导出'), findsOneWidget);
    expect(find.byKey(const ValueKey('export-retry-failed')), findsOneWidget);
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'photo permission denial keeps the draft and never auto-retries',
    (tester) async {
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      final project = PhotoProject(
        id: 'permission-project',
        createdAt: DateTime.utc(2026, 8, 28),
        updatedAt: DateTime.utc(2026, 8, 28),
        photos: [
          ProjectPhoto(
            id: 'permission-photo',
            localPath: photoFile.path,
            originalName: '权限样片.png',
          ),
        ],
      );
      final exporter = _PermissionDeniedPhotoExporter();
      final store = MemoryPhotoProjectStore(project);
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoProjectStore: store,
          photoExporter: exporter,
        ),
      );
      await _openLegacyEditorRoute(tester);
      await tester.tap(find.byKey(const ValueKey('editor-export')));
      await tester.pumpAndSettle();
      expect(find.text('映见需要添加照片权限，才能把成片保存到系统相册。'), findsOne);
      await tester.tap(
        find.byKey(const ValueKey('export-permission-continue')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('export-open-settings')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('export-continue-editing')),
        findsOneWidget,
      );
      expect(store.project, isNotNull);
      expect(exporter.calls, 1);
      await tester.tap(find.byKey(const ValueKey('export-open-settings')));
      await tester.pump();
      expect(exporter.settingsCalls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(exporter.calls, 1);
    },
  );

  testWidgets('leaving during export drains a late share file', (tester) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final project = PhotoProject(
      id: 'late-share-project',
      createdAt: DateTime.utc(2026, 8, 5),
      updatedAt: DateTime.utc(2026, 8, 5),
      photos: [
        ProjectPhoto(
          id: 'late-share-photo',
          localPath: photoFile.path,
          originalName: '迟到分享样片.png',
        ),
      ],
      flowState: PhotoProjectFlowState.editing,
    );
    final exporter = _DeferredPhotoExporter();
    final sharer = FakePhotoSharer();
    final store = MemoryPhotoProjectStore(project);
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        photoExporter: exporter,
        photoSharer: sharer,
      ),
    );
    await _openLegacyEditorRoute(tester);
    final saveButton = find.byKey(const ValueKey('editor-export'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('正在准备成片…'), findsOneWidget);
    expect(find.textContaining('1 / 1'), findsNothing);
    expect(find.textContaining('第1张'), findsNothing);
    expect(find.byKey(const ValueKey('export-cancel-remaining')), findsNothing);

    exporter.beginSavingToPhotoLibrary();
    await tester.pump();
    expect(find.text('正在保存到系统相册…'), findsOneWidget);
    expect(find.text('正在准备成片…'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('正在保存到系统相册…'), findsOneWidget);
    expect(exporter.calls, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);
    exporter.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-finish')));
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 10 && sharer.discardedPaths == null;
      attempt += 1
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(sharer.discardedPaths, ['/tmp/Yingjian_deferred.jpg']);
    expect(
      store.project?.exportStates['late-share-photo'],
      PhotoExportState.saved,
    );
  });

  testWidgets('user confirms project deletion without touching originals', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: [
          ProjectPhoto(
            id: 'photo-1',
            localPath: photoFile.path,
            originalName: '周末人像.png',
          ),
        ],
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await _openLegacyEditorRoute(tester);

    await tester.tap(find.byTooltip('删除项目'));
    await tester.pumpAndSettle();
    expect(find.textContaining('系统相册原图不会被删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(store.project, isNull);
    expect(find.text('选择一张照片'), findsOneWidget);
    expect(photoFile.existsSync(), isTrue);
  });

  testWidgets('home remains clear at two-times dynamic text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() async {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();

    await tester.pumpWidget(buildTestApp(settings));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-apply-style')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-motion')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-journey-guide')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor remains operable at two-times dynamic text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() async {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'dynamic-text-project',
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
        photos: [
          ProjectPhoto(
            id: 'dynamic-text-photo',
            localPath: photoFile.path,
            originalName: '大字模式.png',
          ),
        ],
        flowState: PhotoProjectFlowState.editing,
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: 'dynamic-text-photo',
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();

    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await _openLegacyEditorRoute(tester);

    expect(
      find.byKey(const ValueKey('editor-bottom-command-bar')),
      findsOneWidget,
    );
    await _openManualMetaOp(tester, MetaOpIds.compositionGeometry);
    final freeCrop = find.byKey(const ValueKey('editor-free-crop'));
    expect(freeCrop, findsOneWidget);
    await tester.ensureVisible(freeCrop);
    await tester.pumpAndSettle();
    await tester.tap(freeCrop);
    await tester.pumpAndSettle();
    final cropCanvas = find.byKey(const ValueKey('free-crop-canvas'));
    await tester.drag(cropCanvas, const Offset(36, 28));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('free-crop-apply')), findsNothing);
    expect(
      store.project!.effectiveRecipeFor('dynamic-text-photo').crop.isOriginal,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('free-crop-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings exposes privacy, diagnostics, and rating', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('匿名诊断'), findsOneWidget);
    expect(find.text('去评分'), findsOneWidget);

    final legal = find.byKey(const ValueKey('settings-legal'));
    await tester.ensureVisible(legal);
    await tester.pumpAndSettle();
    await tester.tap(legal);
    await tester.pumpAndSettle();
    expect(find.text('隐私政策'), findsOneWidget);
    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();

    expect(find.text('映见隐私政策'), findsOneWidget);
  });
}

Future<void> _pushLegacyEditorRoute(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final resume = find.byKey(const ValueKey('home-resume-project'));
  unawaited(
    AppRouter.navigatorKey.currentState!.pushNamed(
      AppRoutes.editor,
      arguments: resume.evaluate().isEmpty,
    ),
  );
}

Future<void> _openLegacyEditorRoute(WidgetTester tester) async {
  await _pushLegacyEditorRoute(tester);
  await tester.pumpAndSettle();
}

Future<void> _openManualMetaOp(WidgetTester tester, String metaOpId) async {
  if (find.byKey(const ValueKey('editor-tools-dock')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('editor-all-tools')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('editor-meta-op-search')),
    metaOpId,
  );
  await tester.pumpAndSettle();
  final result = find.byKey(ValueKey('editor-meta-op-result-$metaOpId'));
  expect(result, findsOneWidget);
  tester.widget<ListTile>(result).onTap!();
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<MemoryPhotoProjectStore> _pumpSinglePhotoExport(
  WidgetTester tester,
  PhotoSharer sharer,
) async {
  final photoFile = File(
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
    'Icon-App-1024x1024@1x.png',
  );
  final project = PhotoProject(
    id: 'share-project',
    createdAt: DateTime.utc(2026, 8, 5),
    updatedAt: DateTime.utc(2026, 8, 5),
    photos: [
      ProjectPhoto(
        id: 'share-photo',
        localPath: photoFile.path,
        originalName: '分享样片.png',
      ),
    ],
    flowState: PhotoProjectFlowState.editing,
  );
  SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
  final settings = await AppSettings.load();
  final store = MemoryPhotoProjectStore(project);
  await tester.pumpWidget(
    buildTestApp(
      settings,
      photoProjectStore: store,
      photoExporter: FakePhotoExporter(),
      photoSharer: sharer,
    ),
  );
  await _pushLegacyEditorRoute(tester);
  await tester.pumpAndSettle();
  final saveButton = find.byKey(const ValueKey('editor-export'));
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
  return store;
}

Future<void> _pumpUntilText(WidgetTester tester, String text) async {
  for (
    var attempt = 0;
    attempt < 10 && find.text(text).evaluate().isEmpty;
    attempt += 1
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final class _FailingProjectStore implements PhotoProjectStore {
  @override
  Future<PhotoProject?> loadLatest() async {
    throw const FormatException('corrupt project');
  }

  @override
  Future<void> save(PhotoProject project) async {}
}

final class _DeferredFallbackProjectStore
    implements PhotoProjectLifecycleStore {
  final Completer<void> fallbackSaveStarted = Completer<void>();
  final Completer<void> _fallbackSaveRelease = Completer<void>();
  PhotoProject? project;
  bool _delayFallback = true;

  void completeFallbackSave() => _fallbackSaveRelease.complete();

  @override
  Future<PhotoProject?> loadLatest() async => project;

  @override
  Future<void> save(PhotoProject project) async {
    if (_delayFallback &&
        project.analysisStates.values.contains(PhotoAnalysisState.fallback)) {
      _delayFallback = false;
      fallbackSaveStarted.complete();
      await _fallbackSaveRelease.future;
    }
    this.project = project;
  }

  @override
  Future<void> deletePhotoCopy(ProjectPhoto photo) async {}

  @override
  Future<void> deleteProject(PhotoProject project) async {
    this.project = null;
  }
}

final class _DeferredAnalysisStateProjectStore
    implements PhotoProjectLifecycleStore {
  final Completer<void> analysisSaveStarted = Completer<void>();
  final Completer<void> _analysisSaveRelease = Completer<void>();
  PhotoProject? project;
  bool _delayReady = true;

  void completeAnalysisSave() => _analysisSaveRelease.complete();

  @override
  Future<PhotoProject?> loadLatest() async => project;

  @override
  Future<void> save(PhotoProject project) async {
    if (_delayReady &&
        project.analysisStates.values.contains(PhotoAnalysisState.ready)) {
      _delayReady = false;
      analysisSaveStarted.complete();
      await _analysisSaveRelease.future;
    }
    this.project = project;
  }

  @override
  Future<void> deletePhotoCopy(ProjectPhoto photo) async {}

  @override
  Future<void> deleteProject(PhotoProject project) async {
    this.project = null;
  }
}

final class _CountingPhotoAnalyzer implements PhotoAnalyzer {
  _CountingPhotoAnalyzer({
    this.portrait = PortraitApplicability.unavailable,
    PortraitApplicability? faceSlim,
    this.faceSlimReason = PortraitDegradationReason.none,
    this.faceSlimTargetCount,
    this.body = PortraitApplicability.unavailable,
    this.bodyTargetCount,
    this.faceTargetRegions = const [],
    this.capabilityVersion = 'widget-capability-v1',
  }) : faceSlim = faceSlim ?? portrait;

  final PortraitApplicability portrait;
  final PortraitApplicability faceSlim;
  final PortraitDegradationReason faceSlimReason;
  final int? faceSlimTargetCount;
  final PortraitApplicability body;
  final int? bodyTargetCount;
  final List<NormalizedTargetRegion> faceTargetRegions;
  final List<NormalizedTargetRegion> bodyTargetRegions = const [];
  final String capabilityVersion;
  int calls = 0;

  @override
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) =>
      PhotoAnalysisEngineIdentity(
        analysisVersion: 'widget-analysis-v1',
        capabilityVersion: capabilityVersion,
      );

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) async {
    calls += 1;
    return LocalPhotoAnalysis(
      analysisVersion: 'widget-analysis-v1',
      capabilityVersion: capabilityVersion,
      contentSha256: photo.contentSha256,
      orientation: photo.orientation,
      pixelWidth: photo.pixelWidth,
      pixelHeight: photo.pixelHeight,
      colorSpace: photo.colorSpace,
      disposition: PhotoAnalysisDisposition.ready,
      fallbackReason: AnalysisFallbackReason.none,
      confidence: AnalysisConfidence.high,
      exposure: ExposureCondition.underexposed,
      whiteBalance: WhiteBalanceCondition.warmCast,
      clarity: ClarityCondition.clear,
      portrait: portrait,
      faceSlim: faceSlim,
      faceSlimReason: faceSlimReason,
      faceSlimTargetCount: faceSlimTargetCount,
      faceTargetRegions: faceTargetRegions,
      body: body,
      bodyTargetCount: bodyTargetCount,
      bodyTargetRegions: bodyTargetRegions,
    );
  }
}

final class _DeferredPhotoAnalyzer implements PhotoAnalyzer {
  final Completer<void> started = Completer<void>();
  final Completer<void> _release = Completer<void>();

  void complete() => _release.complete();

  @override
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) =>
      const PhotoAnalysisEngineIdentity(
        analysisVersion: 'widget-deferred-v1',
        capabilityVersion: 'widget-capability-v1',
      );

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) async {
    started.complete();
    await _release.future;
    return LocalPhotoAnalysis(
      analysisVersion: 'widget-deferred-v1',
      capabilityVersion: 'widget-capability-v1',
      contentSha256: photo.contentSha256,
      orientation: photo.orientation,
      pixelWidth: photo.pixelWidth,
      pixelHeight: photo.pixelHeight,
      colorSpace: photo.colorSpace,
      disposition: PhotoAnalysisDisposition.ready,
      fallbackReason: AnalysisFallbackReason.none,
    );
  }
}

final class _ArmableFailProjectStore implements PhotoProjectStore {
  _ArmableFailProjectStore(this.project);

  PhotoProject project;
  bool failSaves = false;

  @override
  Future<PhotoProject?> loadLatest() async => project;

  @override
  Future<void> save(PhotoProject project) async {
    if (failSaves) throw StateError('fixture save failure');
    this.project = project;
  }
}

final class _DeferredEditProjectStore implements PhotoProjectStore {
  _DeferredEditProjectStore(this.project);

  PhotoProject project;
  bool _defer = false;
  Completer<void> saveStarted = Completer<void>();
  Completer<void> _saveRelease = Completer<void>();

  void deferNextSave() {
    _defer = true;
    saveStarted = Completer<void>();
    _saveRelease = Completer<void>();
  }

  void completeSave() => _saveRelease.complete();

  @override
  Future<PhotoProject?> loadLatest() async => project;

  @override
  Future<void> save(PhotoProject project) async {
    if (_defer) {
      _defer = false;
      saveStarted.complete();
      await _saveRelease.future;
    }
    this.project = project;
  }
}

final class _AlwaysFailPhotoExporter implements PhotoExporter {
  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) {
    throw StateError('fixture export failure');
  }
}

final class _PermissionDeniedPhotoExporter
    implements
        PhotoExporter,
        PhotoLibraryPermissionAwareExporter,
        PhotoLibrarySettingsOpener {
  int calls = 0;
  int settingsCalls = 0;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    calls += 1;
    throw PlatformException(code: 'photoAccessDenied');
  }

  @override
  Future<void> openPhotoLibrarySettings() async {
    settingsCalls += 1;
  }
}

final class _DeferredPhotoImporter implements PhotoImporter {
  final Completer<PhotoImportBatch> _completion = Completer<PhotoImportBatch>();

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) =>
      _completion.future;

  void cancel() => _completion.complete(const PhotoImportBatch());

  void complete(PhotoImportBatch batch) => _completion.complete(batch);
}

final class _ThrowingPhotoImporter implements PhotoImporter {
  _ThrowingPhotoImporter(this.error);

  final Object error;

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) async {
    throw error;
  }
}

final class _DeferredPhotoSharer implements PhotoSharer {
  final Completer<void> started = Completer<void>();
  final Completer<PhotoShareOutcome> _completion =
      Completer<PhotoShareOutcome>();
  List<String>? discardedPaths;

  @override
  Future<PhotoShareOutcome> share({required List<String> localPaths}) {
    started.complete();
    return _completion.future;
  }

  @override
  Future<void> discard({required List<String> localPaths}) async {
    discardedPaths = List.unmodifiable(localPaths);
  }

  void complete(PhotoShareOutcome outcome) => _completion.complete(outcome);
}

final class _DeferredPhotoExporter
    implements PhotoExporter, PhotoExportStageAware {
  final Completer<ExportedPhoto> _completion = Completer<ExportedPhoto>();
  int calls = 0;
  @override
  final ValueNotifier<PhotoExportStage> stage = ValueNotifier(
    PhotoExportStage.preparing,
  );

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) {
    calls += 1;
    return _completion.future;
  }

  void beginSavingToPhotoLibrary() {
    stage.value = PhotoExportStage.savingToPhotoLibrary;
  }

  void complete() {
    _completion.complete(
      const ExportedPhoto(
        assetId: 'asset-42',
        width: 4032,
        height: 3024,
        sharePath: '/tmp/Yingjian_deferred.jpg',
      ),
    );
  }
}
