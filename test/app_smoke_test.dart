import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction, SemanticsFlag, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';

import 'support/memory_photo_analysis_cache.dart';
import 'support/test_services.dart';

void main() {
  testWidgets('user can see the Yingjian starting action', (tester) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings));

    expect(find.text('映见'), findsOneWidget);
    expect(find.text('一张精修，整组好看'), findsOneWidget);
    expect(find.text('开始修图'), findsOneWidget);

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);
    expect(find.text('选择 1–6 张照片'), findsOneWidget);
  });

  testWidgets('follows a persisted English locale', (tester) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'en'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings));

    expect(find.text('Yingjian'), findsOneWidget);
    expect(find.text('Start editing'), findsOneWidget);
  });

  testWidgets('English unfinished-project count uses singular grammar', (
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
        flowState: PhotoProjectFlowState.analyzing,
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'en'});
    final settings = await AppSettings.load();

    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 photo ·'), findsOneWidget);
    expect(find.textContaining('1 photos'), findsNothing);
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
        flowState: PhotoProjectFlowState.analyzing,
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();

    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();

    expect(find.text('未完成项目'), findsOneWidget);
    expect(find.text('继续上次编辑'), findsOneWidget);
    expect(find.text('开始新项目'), findsOneWidget);
    expect(find.textContaining('1 张照片'), findsOneWidget);
    expect(find.textContaining('14:30'), findsOneWidget);
  });

  testWidgets('starting over requires confirmation before deleting copies', (
    tester,
  ) async {
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
      flowState: PhotoProjectFlowState.analyzing,
    );
    final store = MemoryPhotoProjectStore(project);
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始新项目'));
    await tester.pumpAndSettle();
    expect(find.textContaining('系统相册原图不会被删除'), findsOneWidget);
    expect(store.project, project);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.project, project);
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

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    expect(find.text('选择 1–6 张照片'), findsOneWidget);

    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('photo-preview-photo-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-preview-stage')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-bottom-command-bar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recommendation-use')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('周末人像.png'), findsOneWidget);
    expect(find.text('1/6'), findsOneWidget);
    expect(find.text('无法读取这张照片'), findsNothing);
  });

  testWidgets('a rejected photo is explained while valid photos continue', (
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

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();

    expect(find.text('可用照片.png'), findsOneWidget);
    expect(find.textContaining('动态照片.png'), findsOneWidget);
    expect(find.textContaining('暂不支持动态图片'), findsOneWidget);
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

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();

    expect(find.textContaining('损坏照片.jpg'), findsOneWidget);
    expect(find.textContaining('无法读取'), findsOneWidget);
    expect(find.text('选择照片'), findsOneWidget);
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsWidgets);
  });

  testWidgets('cancelled import is explicit and remains retryable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(settings, photoImporter: FakePhotoImporter()),
    );

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();

    expect(find.text('未添加任何照片'), findsOneWidget);
    expect(find.text('选择照片'), findsOneWidget);
  });

  testWidgets('import progress is announced while local copying is active', (
    tester,
  ) async {
    final importer = _DeferredPhotoImporter();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings, photoImporter: importer));

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pump();

    final progress = find.semantics.byPredicate(
      (node) =>
          node.label.contains('正在本地导入照片') && node.flagsCollection.isLiveRegion,
    );
    expect(progress, findsOne);
    expect(progress.evaluate().single.flagsCollection.isLiveRegion, isTrue);

    importer.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('user chooses one of three local recommendation directions', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final store = MemoryPhotoProjectStore();
    final previewRenderer = FakePhotoPreviewRenderer.supported();
    const frameKey = ValueKey('reduced-motion-frame');
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      RepaintBoundary(
        key: frameKey,
        child: buildTestApp(
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
      ),
    );

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    expect(find.text('自然干净'), findsOneWidget);
    expect(find.text('氛围色彩'), findsOneWidget);
    expect(find.text('质感风格'), findsOneWidget);
    expect(find.text('主推荐'), findsOneWidget);
    expect(find.text('备选'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('recommendation-preview-naturalClean')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recommendation-preview-atmosphericColor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recommendation-preview-texturedStyle')),
      findsOneWidget,
    );
    expect(previewRenderer.maxEdges.where((edge) => edge == 384), hasLength(3));
    expect(previewRenderer.maxEdges, contains(2048));
    expect(find.textContaining('不上传照片'), findsOneWidget);
    expect(find.text('均衡克制的安全回退'), findsOneWidget);
    expect(find.text('安全增加轻微暖意'), findsOneWidget);
    expect(find.text('克制增强质感，不激进锐化'), findsOneWidget);
    final initialPreviewPipeline = previewRenderer.updates.isNotEmpty
        ? previewRenderer.updates.last
        : previewRenderer.creates.last;
    final initialAdjustments =
        initialPreviewPipeline.toPlatformArguments()['adjustments']!
            as Map<String, double>;
    expect(
      initialAdjustments.values.any((value) => value != 0),
      isTrue,
      reason: 'The first selected recommendation must be the visible preview.',
    );
    expect(
      store.project?.flowState,
      PhotoProjectFlowState.choosingRecommendation,
    );

    final atmosphereOption = find.semantics.byLabel(RegExp('氛围色彩'));
    expect(atmosphereOption, findsOne);
    tester.semantics.tap(atmosphereOption);
    await tester.pump();
    expect(
      atmosphereOption.evaluate().single.flagsCollection.isSelected,
      Tristate.isTrue,
    );
    final frame = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byKey(frameKey),
    );
    final immediateFrame = await frame.toImage();
    addTearDown(immediateFrame.dispose);
    await tester.pump(const Duration(milliseconds: 80));
    final laterFrame = await frame.toImage();
    addTearDown(laterFrame.dispose);
    await expectLater(laterFrame, matchesReferenceImage(immediateFrame));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('recommendation-use')));
    await tester.pumpAndSettle();

    expect(store.project?.flowState, PhotoProjectFlowState.editing);
    expect(
      store.project?.selectedRecommendationId,
      contains('atmosphere-warm'),
    );
    expect(
      store.project?.sharedStyle.family,
      SharedStyleFamily.atmosphericColor,
    );
    expect(
      store.project?.adaptiveCompensations['photo-1']?.source,
      AdaptiveCompensationSource.safeFallbackV1,
    );
  });

  testWidgets('restored recommendations reuse project-local analysis', (
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
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();
    expect(analyzer.calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app());
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    expect(analyzer.calls, 1);
    await tester.dragUntilVisible(
      find.text('自然干净'),
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -200),
    );
    expect(find.text('自然干净'), findsOneWidget);
    expect(find.text('氛围色彩'), findsOneWidget);
    expect(find.text('质感风格'), findsOneWidget);
    expect(find.textContaining('本机像素分析'), findsOneWidget);
    expect(find.text('平衡检测到的曝光'), findsOneWidget);
    expect(find.text('修正检测到的偏色'), findsOneWidget);
    expect(find.text('保留细节与局部反差'), findsOneWidget);
  });

  testWidgets(
    'an unavailable recommendation preview is explicit and retryable',
    (tester) async {
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      final renderer = FakePhotoPreviewRenderer.unsupported();
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoPreviewRenderer: renderer,
          photoImporter: FakePhotoImporter([
            ProjectPhoto(
              id: 'photo-preview-failure',
              localPath: photoFile.path,
              originalName: '推荐预览失败.png',
            ),
          ]),
        ),
      );

      await tester.tap(find.text('开始修图'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择照片'));
      await tester.pumpAndSettle();

      expect(find.textContaining('这套推荐预览暂不可用'), findsOneWidget);
      expect(find.textContaining('原图不受影响'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-preview-retry')), findsOneWidget);
      final createCountBeforeRetry = renderer.creates.length;

      await tester.tap(find.byKey(const ValueKey('photo-preview-retry')));
      await tester.pumpAndSettle();

      expect(renderer.creates.length, createCountBeforeRetry + 1);
      expect(find.textContaining('这套推荐预览暂不可用'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('自然干净'),
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, -200),
      );
      expect(find.text('自然干净'), findsOneWidget);
      expect(find.text('氛围色彩'), findsOneWidget);
      expect(find.text('质感风格'), findsOneWidget);
    },
  );

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
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pump();
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

    expect(
      store.project?.flowState,
      PhotoProjectFlowState.choosingRecommendation,
    );
    await tester.dragUntilVisible(
      find.text('自然干净'),
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -200),
    );
    expect(find.text('自然干净'), findsOneWidget);
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
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pump();
    await analyzer.started.future;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    analyzer.complete();
    await tester.pump();
    await store.fallbackSaveStarted.future;

    expect(store.project?.flowState, PhotoProjectFlowState.analyzing);
    store.completeFallbackSave();
    await tester.pumpAndSettle();

    expect(
      store.project?.flowState,
      PhotoProjectFlowState.choosingRecommendation,
    );
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
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pump();
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
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pump();
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
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pump();
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

  testWidgets('removing a photo restarts analysis for the remaining group', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    ProjectPhoto photo(String id) => ProjectPhoto(
      id: id,
      localPath: photoFile.path,
      originalName: '$id.png',
      contentSha256: id == 'photo-1'
          ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
          : 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      pixelWidth: 1024,
      pixelHeight: 1024,
      colorSpace: PhotoColorSpace.srgb,
      inputFormat: PhotoInputFormat.png,
      supportState: PhotoSupportState.supported,
    );
    final store = MemoryPhotoProjectStore();
    final analyzer = _FirstDeferredPhotoAnalyzer();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: store,
        photoImporter: FakePhotoImporter([photo('photo-1'), photo('photo-2')]),
        photoAnalyzer: analyzer,
      ),
    );
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pump();
    await analyzer.started.future;

    await tester.tap(find.byTooltip('移除照片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('删除').last);
    await tester.pump();
    analyzer.completeFirst();
    await tester.pumpAndSettle();

    expect(store.project?.photos.map((photo) => photo.id), ['photo-2']);
    expect(
      store.project?.flowState,
      PhotoProjectFlowState.choosingRecommendation,
    );
    expect(analyzer.calls, greaterThanOrEqualTo(2));
    await tester.dragUntilVisible(
      find.text('自然干净'),
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -200),
    );
    expect(find.text('自然干净'), findsOneWidget);
  });

  testWidgets('photo removal drains a claimed analysis state save', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    ProjectPhoto photo(String id, String hash) => ProjectPhoto(
      id: id,
      localPath: photoFile.path,
      originalName: '$id.png',
      contentSha256: hash,
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
        photoImporter: FakePhotoImporter([
          photo(
            'photo-1',
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
          photo(
            'photo-2',
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          ),
        ]),
        photoAnalyzer: _CountingPhotoAnalyzer(),
      ),
    );
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pump();
    await store.analysisSaveStarted.future;

    await tester.tap(find.byTooltip('移除照片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('删除').last);
    await tester.pump();
    expect(store.project?.photos, hasLength(2));

    store.completeAnalysisSave();
    await tester.pumpAndSettle();

    expect(store.project?.photos.map((photo) => photo.id), ['photo-2']);
    expect(
      store.project?.flowState,
      PhotoProjectFlowState.choosingRecommendation,
    );
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
        selectedRecommendationId: 'clean-natural-01',
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

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    expect(find.text('周末人像.png'), findsOneWidget);
    final exposureAdjustment = find.byKey(
      const ValueKey('editor-adjustment-exposure'),
    );
    await tester.dragUntilVisible(
      exposureAdjustment,
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('高光'), findsOneWidget);
    expect(find.text('阴影'), findsOneWidget);
    expect(find.text('构图'), findsOneWidget);
    await tester.drag(
      find.descendant(of: exposureAdjustment, matching: find.byType(Slider)),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    expect(exporter.exportedRecipe, isNull);
    expect(store.project?.undoHistory, hasLength(1));

    await tester.dragUntilVisible(
      find.text('重做'),
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -200),
    );
    expect(find.text('重做'), findsOneWidget);

    final saveButton = find.byKey(const ValueKey('editor-batch-export'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-save-options')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-current')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-all')));
    await tester.pumpAndSettle();

    expect(exporter.exportedPhoto, photo);
    expect(exporter.exportedRecipe?.exposure, greaterThan(0));
    expect(find.text('1 张照片已保存到相册'), findsOneWidget);
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
    await _pumpUntilText(tester, '已取消分享，保存结果不受影响');

    expect(find.text('已取消分享，保存结果不受影响'), findsOneWidget);
    expect(find.text('1 张照片已保存到相册'), findsOneWidget);
    expect(find.text('分享已保存照片'), findsOneWidget);
    expect(store.project?.exportStates, exportStatesBeforeShare);
    await tester.tap(find.byKey(const ValueKey('save-finish')));
    await tester.pumpAndSettle();
    expect(sharer.discardedPaths, ['/tmp/Yingjian_fixture.jpg']);
  });

  testWidgets('saved export replaces editing inputs until finishing', (
    tester,
  ) async {
    await _pumpSinglePhotoExport(tester, FakePhotoSharer());

    expect(find.byKey(const Key('photo-workspace-scroll')), findsNothing);
    expect(find.byKey(const ValueKey('editor-save-success')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-finish')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-start-editing')), findsOneWidget);
  });

  testWidgets('system share failure preserves the saved result', (
    tester,
  ) async {
    final sharer = FakePhotoSharer(error: StateError('fixture share failure'));
    final store = await _pumpSinglePhotoExport(tester, sharer);
    final exportStatesBeforeShare = Map.of(store.project!.exportStates);

    await tester.ensureVisible(find.byKey(const ValueKey('save-share')));
    await tester.tap(find.byKey(const ValueKey('save-share')));
    await _pumpUntilText(tester, '暂时无法分享，保存结果不受影响');

    expect(find.text('暂时无法分享，保存结果不受影响'), findsOneWidget);
    expect(find.text('1 张照片已保存到相册'), findsOneWidget);
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
    await _pumpUntilText(tester, '已取消分享，保存结果不受影响');
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
        selectedRecommendationId: 'clean-natural-01',
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
      await tester.tap(find.text('开始修图'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);
      expect(find.byKey(const Key('photo-workspace-scroll')), findsOneWidget);
      for (
        var attempt = 0;
        attempt < 8 && find.text('构图').evaluate().isEmpty;
        attempt += 1
      ) {
        await tester.drag(
          find.byKey(const Key('photo-workspace-scroll')),
          const Offset(0, -260),
        );
        await tester.pumpAndSettle();
      }
      final compositionCategory = find.byKey(
        const ValueKey('editor-tool-category-composition'),
      );
      expect(compositionCategory, findsOneWidget);
      await Scrollable.ensureVisible(tester.element(compositionCategory));
      await tester.pumpAndSettle();
      await tester.tap(compositionCategory);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('向左旋转'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('向左旋转'));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 6; attempt += 1) {
        await tester.drag(
          find.byKey(const Key('photo-workspace-scroll')),
          const Offset(0, 320),
        );
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('构图预览暂不可用'), findsOneWidget);
      expect(find.textContaining('原图不受影响'), findsOneWidget);
      expect(find.text('构图预览.png'), findsOneWidget);
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
          selectedRecommendationId: 'clean-natural-01',
          photoOverrides: {
            'photo-1': PhotoOverride(
              recipe: EditRecipe(basicEditingRecipe: look),
            ),
          },
        ),
      );
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
      await tester.tap(find.text('开始修图'));
      await tester.pumpAndSettle();

      final compositionCategory = find.byKey(
        const ValueKey('editor-tool-category-composition'),
      );
      await tester.ensureVisible(compositionCategory);
      await tester.tap(compositionCategory);
      await tester.pumpAndSettle();
      final reset = find.widgetWithText(TextButton, '恢复原始构图');
      await tester.ensureVisible(reset);
      expect(tester.widget<TextButton>(reset).onPressed, isNotNull);
      await tester.tap(reset);
      await tester.pumpAndSettle();

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
      selectedRecommendationId: 'clean-natural-01',
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

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    expect(find.textContaining('当前效果预览暂不可用'), findsOneWidget);
    expect(find.textContaining('原图不受影响'), findsOneWidget);
    expect(find.textContaining('构图预览暂不可用'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'applicable portrait exposes one undoable natural retouch control',
    (tester) async {
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
          selectedRecommendationId: 'clean-natural-01',
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
      await tester.pumpWidget(
        buildTestApp(
          settings,
          photoImporter: FakePhotoImporter([
            ProjectPhoto(
              id: 'background-photo',
              localPath: photoFile.path,
              originalName: '背景.png',
            ),
          ]),
          photoProjectStore: store,
          photoAnalyzer: _CountingPhotoAnalyzer(
            portrait: PortraitApplicability.applicable,
            faceSlimTargetCount: 2,
            body: PortraitApplicability.applicable,
            bodyTargetCount: 2,
          ),
          photoAnalysisCache: cache,
          photoPreviewRenderer: FakePhotoPreviewRenderer.supported(),
        ),
      );

      await tester.tap(find.text('开始修图'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(
          const ValueKey('editor-adjustment-tab-naturalBeautification'),
        ),
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
          findsOneWidget,
        );
      }
      final exposureTab = find.byKey(
        const ValueKey('editor-adjustment-tab-exposure'),
      );
      expect(exposureTab, findsNothing);
      expect(
        find.byKey(
          const ValueKey('editor-apply-one-tap-natural-beautification'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-adjustment-section')),
        findsOneWidget,
      );
      expect(find.text('人像'), findsOneWidget);
      expect(find.text('人像工具已就绪 · 本地处理'), findsOneWidget);
      final faceSlimTab = find.byKey(
        const ValueKey('editor-adjustment-tab-faceSlim'),
      );
      expect(faceSlimTab.hitTestable(), findsOneWidget);
      final colorCategory = find.byKey(
        const ValueKey('editor-tool-category-color'),
      );
      await Scrollable.ensureVisible(tester.element(colorCategory));
      await tester.pumpAndSettle();
      await tester.tap(colorCategory);
      await tester.pumpAndSettle();
      expect(exposureTab, findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-adjustment-tab-faceSlim')),
        findsNothing,
      );
      final qualityCategory = find.byKey(
        const ValueKey('editor-tool-category-quality'),
      );
      await Scrollable.ensureVisible(tester.element(qualityCategory));
      await tester.pumpAndSettle();
      await tester.tap(qualityCategory);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-apply-quality-improvement')),
        findsOneWidget,
      );
      final retouchCategory = find.byKey(
        const ValueKey('editor-tool-category-retouch'),
      );
      await Scrollable.ensureVisible(tester.element(retouchCategory));
      await tester.pumpAndSettle();
      await tester.tap(retouchCategory);
      await tester.pumpAndSettle();
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
      await tester.tap(
        find.byKey(
          const ValueKey('editor-apply-one-tap-natural-beautification'),
        ),
      );
      await tester.pumpAndSettle();
      var portraitRecipe = store.project!
          .effectiveRecipeFor(photo.id)
          .portraitRecipe;
      expect(portraitRecipe.textureSmoothing, 50);
      expect(portraitRecipe.skinToneLighting, 50);
      expect(portraitRecipe.blemishReduction, 20);

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
      expect(
        tester.getSize(secondFaceOverlay).height,
        greaterThanOrEqualTo(44),
      );
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
      await tester.drag(faceSlimControl, const Offset(80, 0));
      await tester.pumpAndSettle();
      final firstFaceStrength = (await store.loadLatest())!
          .effectiveRecipeFor(photo.id)
          .faceSlimRecipe
          .targetStrengths[0];
      expect(firstFaceStrength, greaterThan(0));
      await tester.ensureVisible(secondFaceOverlay);
      await tester.pumpAndSettle();
      await tester.tap(secondFaceOverlay);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(faceSlimControl).value, 0);
      await tester.drag(faceSlimControl, const Offset(48, 0));
      await tester.pumpAndSettle();
      final multiFaceRecipe = (await store.loadLatest())!
          .effectiveRecipeFor(photo.id)
          .faceSlimRecipe;
      expect(multiFaceRecipe.targetStrengths[0], firstFaceStrength);
      expect(multiFaceRecipe.targetStrengths[1], greaterThan(0));
      expect(
        (await store.loadLatest())
            ?.effectiveRecipeFor(photo.id)
            .faceSlimStrength,
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
      await tester.drag(headSizeControl, const Offset(60, 0));
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
      expect(
        find.byKey(const ValueKey('editor-body-target-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-body-target-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-body-target-selector')),
        findsOneWidget,
      );
      final secondBodyOverlay = find.byKey(
        const ValueKey('portrait-target-overlay-1'),
      );
      await tester.ensureVisible(secondBodyOverlay);
      await tester.pumpAndSettle();
      await tester.tap(secondBodyOverlay);
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
      await tester.drag(bodySlimControl, const Offset(70, 0));
      await tester.pumpAndSettle();
      expect(
        store.project!
            .effectiveRecipeFor(photo.id)
            .portraitGeometryRecipe
            .selectedBodyIndex,
        1,
      );
      expect(
        (await store.loadLatest())
            ?.effectiveRecipeFor(photo.id)
            .bodySlimStrength,
        greaterThan(0),
      );
      final recipe = store.project!.effectiveRecipeFor('portrait-photo');
      expect(recipe.portraitStrength, 0);
      expect(recipe.portraitRecipe.textureSmoothing, 50);
      expect(find.text('选择人像'), findsNothing);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(store.project!.effectiveRecipeFor(photo.id).bodySlimStrength, 0);
      await tester.tap(find.text('撤销'));
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
      await tester.tap(find.text('撤销'));
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
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(store.project!.effectiveRecipeFor(photo.id).faceSlimStrength, 0);
      expect(
        store.project!
            .effectiveRecipeFor(photo.id)
            .portraitRecipe
            .textureSmoothing,
        50,
      );
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      portraitRecipe = store.project!
          .effectiveRecipeFor(photo.id)
          .portraitRecipe;
      expect(portraitRecipe, isNot(equals(recipe.portraitRecipe)));
      expect(portraitRecipe.textureSmoothing, 0);
      expect(portraitRecipe.skinToneLighting, 0);
      expect(portraitRecipe.blemishReduction, 0);

      final semanticCategory = find.byKey(
        const ValueKey('editor-tool-category-semantic'),
      );
      await tester.dragUntilVisible(
        semanticCategory,
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, -260),
      );
      await Scrollable.ensureVisible(
        tester.element(semanticCategory),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      expect(semanticCategory.hitTestable(), findsOneWidget);
      await tester.tap(semanticCategory);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-semantic-tools')),
        findsOneWidget,
      );
      final whiteBackground = find.byKey(
        const ValueKey('editor-background-white'),
      );
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
      await tester.pump();
      final subjectUndo = find.byKey(const ValueKey('subject-mask-undo'));
      final subjectRedo = find.byKey(const ValueKey('subject-mask-redo'));
      await tester.ensureVisible(subjectUndo);
      await tester.pump();
      expect(tester.widget<IconButton>(subjectUndo).onPressed, isNotNull);
      await tester.tap(subjectUndo);
      await tester.pump();
      await tester.ensureVisible(subjectRedo);
      await tester.pump();
      expect(tester.widget<IconButton>(subjectRedo).onPressed, isNotNull);
      await tester.tap(subjectRedo);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('subject-mask-apply')));
      await tester.pumpAndSettle();
      expect(
        store.project!
            .effectiveRecipeFor(photo.id)
            .semanticEditingRecipe
            .subjectMaskStrokes,
        isNotEmpty,
      );
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
      await tester.pump();
      final localUndo = find.byKey(const ValueKey('local-mask-undo'));
      final localRedo = find.byKey(const ValueKey('local-mask-redo'));
      await tester.ensureVisible(localUndo);
      await tester.pump();
      expect(tester.widget<IconButton>(localUndo).onPressed, isNotNull);
      await tester.tap(localUndo);
      await tester.pump();
      await tester.ensureVisible(localRedo);
      await tester.pump();
      expect(tester.widget<IconButton>(localRedo).onPressed, isNotNull);
      await tester.tap(localRedo);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('local-mask-apply')));
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
      await Scrollable.ensureVisible(
        tester.element(eraseButton),
        alignment: 0.5,
      );
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
      await tester.pump();
      final eraseUndo = find.byKey(const ValueKey('erase-brush-undo'));
      final eraseRedo = find.byKey(const ValueKey('erase-brush-redo'));
      await tester.ensureVisible(eraseUndo);
      await tester.pump();
      expect(tester.widget<IconButton>(eraseUndo).onPressed, isNotNull);
      await tester.tap(eraseUndo);
      await tester.pump();
      await tester.ensureVisible(eraseRedo);
      await tester.pump();
      expect(tester.widget<IconButton>(eraseRedo).onPressed, isNotNull);
      await tester.tap(eraseRedo);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('erase-brush-apply')));
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
          selectedRecommendationId: 'clean-natural-01',
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
        body: PortraitApplicability.applicable,
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
          photoPreviewRenderer: FakePhotoPreviewRenderer.supported(),
        ),
      );
      await tester.tap(find.text('开始修图'));
      await tester.pumpAndSettle();

      expect(analyzer.calls, 1);
      expect(store.project?.flowState, PhotoProjectFlowState.editing);
      expect(find.byKey(const ValueKey('recommendation-use')), findsNothing);
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
        find.byKey(const ValueKey('editor-adjustment-tab-faceSlim')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('editor-face-slim-unavailable')),
        findsOneWidget,
      );
      expect(find.text('为保护背景线条，这张照片暂不提供瘦脸'), findsOneWidget);
      expect(
        find
            .byKey(const ValueKey('editor-adjustment-tab-bodySlim'))
            .hitTestable(),
        findsOneWidget,
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

  testWidgets(
    'multi-photo editing makes group and current-photo scope explicit',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final photoFile = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      );
      final photos = [
        ProjectPhoto(
          id: 'photo-1',
          localPath: photoFile.path,
          originalName: 'first.png',
        ),
        ProjectPhoto(
          id: 'photo-2',
          localPath: photoFile.path,
          originalName: 'second.png',
        ),
      ];
      final store = MemoryPhotoProjectStore(
        PhotoProject(
          id: 'project-1',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: photos,
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'mvp-catalog-v1:clean-balanced',
          sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.1)),
          adaptiveCompensations: {
            'photo-1': AdaptiveCompensation(
              recipe: EditRecipe.neutral,
              source: AdaptiveCompensationSource.safeFallbackV1,
              portraitStrength: 0.35,
            ),
            'photo-2': AdaptiveCompensation(
              recipe: EditRecipe.neutral,
              source: AdaptiveCompensationSource.safeFallbackV1,
            ),
          },
        ),
      );
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();
      await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));

      await tester.tap(find.text('开始修图'));
      await tester.pumpAndSettle();

      expect(find.text('第 1 / 2 张 · 编辑整组'), findsOneWidget);
      expect(find.text('编辑整组'), findsOneWidget);
      expect(find.text('仅当前照片'), findsOneWidget);
      expect(find.text('自动补偿'), findsNWidgets(2));
      final groupIntensity = find.byKey(
        const ValueKey('editor-group-style-intensity'),
      );
      expect(find.textContaining('保留每张照片的独立补偿'), findsOneWidget);
      await tester.dragUntilVisible(
        groupIntensity,
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      expect(groupIntensity, findsOneWidget);
      final groupIntensitySlider = find.descendant(
        of: groupIntensity,
        matching: find.byType(Slider),
      );
      await tester.drag(groupIntensitySlider, const Offset(-90, 0));
      await tester.pumpAndSettle();
      final adjustedGroupIntensity = store.project!.sharedStyle.intensity;
      expect(adjustedGroupIntensity, lessThan(1));
      expect(store.project!.undoHistory, hasLength(1));
      expect(
        store.project!.effectiveRecipeFor('photo-1').exposure,
        lessThan(0.1),
      );

      await tester.dragUntilVisible(
        find.text('仅当前照片'),
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, 180),
      );
      await tester.tap(find.text('仅当前照片'));
      await tester.pumpAndSettle();
      expect(store.project?.editingScope, ProjectEditingScope.currentPhoto);
      await tester.dragUntilVisible(
        find.text('第 1 / 2 张 · 仅当前照片'),
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, 180),
      );
      expect(find.text('第 1 / 2 张 · 仅当前照片'), findsOneWidget);
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('editor-tool-category-composition')),
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, -180),
      );
      for (final category in <String>[
        'composition',
        'color',
        'filters',
        'quality',
        'semantic',
      ]) {
        expect(
          find.byKey(ValueKey('editor-tool-category-$category')),
          findsOneWidget,
        );
      }

      final exposureAdjustment = find.byKey(
        const ValueKey('editor-adjustment-exposure'),
      );
      await tester.dragUntilVisible(
        exposureAdjustment,
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, -240),
      );
      await tester.drag(
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.descendant(of: exposureAdjustment, matching: find.byType(Slider)),
        const Offset(90, 0),
      );
      await tester.pumpAndSettle();

      expect(store.project?.photoOverrides.containsKey('photo-1'), isTrue);
      expect(store.project?.photoOverrides.containsKey('photo-2'), isFalse);
      expect(
        store.project?.effectiveRecipeFor('photo-2').exposure,
        closeTo(0.1 * adjustedGroupIntensity, 1e-12),
      );
      expect(find.text('单张精修'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('重置'),
        find.byKey(const Key('photo-workspace-scroll')),
        const Offset(0, -180),
      );
      await tester.tap(find.text('重置'));
      await tester.pumpAndSettle();
      expect(store.project?.photoOverrides.containsKey('photo-1'), isFalse);
      expect(store.project?.sharedStyle.recipe.exposure, 0.1);
      expect(
        store.project
            ?.effectiveRecipeFor('photo-1')
            .portraitRecipe
            .textureSmoothing,
        35,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('syncing a photo adjustment to the group requires confirmation', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photos = [
      ProjectPhoto(
        id: 'photo-1',
        localPath: photoFile.path,
        originalName: 'first.png',
      ),
      ProjectPhoto(
        id: 'photo-2',
        localPath: photoFile.path,
        originalName: 'second.png',
      ),
    ];
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: photos,
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'mvp-catalog-v1:clean-balanced',
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: 'photo-1',
        sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.1)),
        photoOverrides: {
          'photo-1': PhotoOverride(recipe: EditRecipe(contrast: 0.2)),
        },
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('同步当前调整到整组'),
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -200),
    );
    expect(find.text('同步当前调整到整组'), findsOneWidget);
    await tester.tap(find.text('同步当前调整到整组'));
    await tester.pumpAndSettle();

    expect(find.text('将当前光色调整同步到整组？'), findsOneWidget);
    expect(find.textContaining('构图仍只保留在当前照片'), findsOneWidget);
    expect(store.project?.sharedStyle.recipe, EditRecipe(exposure: 0.1));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.project?.photoOverrides, isNotEmpty);

    await tester.tap(find.text('同步当前调整到整组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步整组'));
    await tester.pumpAndSettle();

    expect(
      store.project?.sharedStyle.recipe,
      EditRecipe(exposure: 0.1, contrast: 0.2),
    );
    expect(store.project?.photoOverrides, isEmpty);
    expect(store.project?.undoHistory, hasLength(1));

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(store.project?.sharedStyle.recipe, EditRecipe(exposure: 0.1));
    expect(
      store.project?.photoOverrides['photo-1']?.recipe,
      EditRecipe(contrast: 0.2),
    );

    await tester.tap(find.text('重做'));
    await tester.pumpAndSettle();
    expect(
      store.project?.sharedStyle.recipe,
      EditRecipe(exposure: 0.1, contrast: 0.2),
    );
    expect(store.project?.photoOverrides, isEmpty);
  });

  testWidgets('restores the saved group photo-strip position', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photos = List.generate(
      6,
      (index) => ProjectPhoto(
        id: 'photo-${index + 1}',
        localPath: photoFile.path,
        originalName: 'photo-${index + 1}.png',
      ),
    );
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: photos,
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'mvp-catalog-v1:clean-balanced',
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: 'photo-4',
        exportStates: const {'photo-6': PhotoExportState.queued},
        groupScrollOffset: 190,
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    expect(find.text('第 4 / 6 张 · 仅当前照片'), findsOneWidget);
    await tester.tap(find.text('编辑整组'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('photo-strip-scroll')),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    expect(store.project?.groupScrollOffset, greaterThan(190));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    expect(find.text('第 4 / 6 张 · 编辑整组'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^photo-6\.png, 待导出')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('photo-strip save failure is visible and keeps safe state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final project = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      photos: List.generate(
        6,
        (index) => ProjectPhoto(
          id: 'photo-${index + 1}',
          localPath: photoFile.path,
          originalName: 'photo-${index + 1}.png',
        ),
      ),
      flowState: PhotoProjectFlowState.editing,
      selectedRecommendationId: 'mvp-catalog-v1:clean-balanced',
    );
    final store = _FailingSaveProjectStore(project);
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('photo-strip-scroll')),
      const Offset(-160, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法保存本次调整，请重试'), findsOneWidget);
    expect(store.project.groupScrollOffset, 0);
  });

  testWidgets('project restore failure has a visible retry state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(settings, photoProjectStore: _FailingProjectStore()),
    );

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    expect(find.text('无法恢复上次项目'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsWidgets);
  });

  testWidgets('batch export keeps successes and retries only failed photos', (
    tester,
  ) async {
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photos = [
      ProjectPhoto(
        id: 'photo-1',
        localPath: photoFile.path,
        originalName: 'first.png',
      ),
      ProjectPhoto(
        id: 'photo-2',
        localPath: photoFile.path,
        originalName: 'second.png',
      ),
    ];
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: photos,
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'mvp-catalog-v1:clean-balanced',
      ),
    );
    final exporter = _FailOncePhotoExporter('photo-2');
    final sharer = FakePhotoSharer();
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

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const ValueKey('editor-batch-export'));
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-all')));
    await tester.pumpAndSettle();

    expect(find.text('已保存 1 张 · 失败 1 张 · 取消 0 张'), findsWidgets);
    expect(store.project?.exportStates['photo-1'], PhotoExportState.saved);
    expect(store.project?.exportStates['photo-2'], PhotoExportState.failed);
    expect(find.bySemanticsLabel(RegExp(r'^first\.png, 已导出')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^second\.png, 导出失败')),
      findsOneWidget,
    );
    await tester.tap(find.text('只重试失败与取消项'));
    await tester.pumpAndSettle();

    expect(
      store.project?.exportStates.values,
      everyElement(PhotoExportState.saved),
    );
    expect(exporter.calls, ['photo-1', 'photo-2', 'photo-2']);
    await tester.ensureVisible(find.text('分享已保存照片'));
    await tester.tap(find.text('分享已保存照片'));
    await _pumpUntilText(tester, '已通过系统分享完成操作');
    expect(sharer.sharedPaths, [
      '/tmp/Yingjian_photo-1.jpg',
      '/tmp/Yingjian_photo-2.jpg',
    ]);
  });

  testWidgets('a complete export failure remains retryable', (tester) async {
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
      selectedRecommendationId: 'clean-natural-01',
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
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const ValueKey('editor-batch-export'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-all')));
    await tester.pumpAndSettle();

    expect(find.text('已保存 0 张 · 失败 1 张 · 取消 0 张'), findsWidgets);
    expect(find.text('只重试失败与取消项'), findsOneWidget);
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsWidgets);
  });

  testWidgets('input-destructive actions stay disabled during export', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final photoFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photos = [
      ProjectPhoto(
        id: 'photo-1',
        localPath: photoFile.path,
        originalName: 'first.png',
      ),
      ProjectPhoto(
        id: 'photo-2',
        localPath: photoFile.path,
        originalName: 'second.png',
      ),
    ];
    final store = MemoryPhotoProjectStore(
      PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: photos,
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
      ),
    );
    final exporter = _DeferredPhotoExporter();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(settings, photoProjectStore: store, photoExporter: exporter),
    );
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const ValueKey('editor-batch-export'));
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-all')));
    for (
      var attempt = 0;
      attempt < 6 &&
          find.byKey(const ValueKey('save-all')).evaluate().isNotEmpty;
      attempt += 1
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('save-all')), findsNothing);

    await tester.ensureVisible(find.text('正在逐张导出…'));
    await tester.pump();
    final exportProgress = find.semantics.byPredicate(
      (node) =>
          node.label.contains('正在逐张导出') && node.flagsCollection.isLiveRegion,
    );
    expect(exportProgress, findsOne);
    expect(
      exportProgress.evaluate().single.flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(find.bySemanticsLabel(RegExp(r'^first\.png, 导出中')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^second\.png, 待导出')), findsOneWidget);

    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_forward),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.remove_circle_outline),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '继续添加照片'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('取消未开始项'));
    exporter.complete();
    await tester.pumpAndSettle();

    expect(find.text('已保存 1 张 · 失败 0 张 · 取消 1 张'), findsWidgets);
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsWidgets);
    expect(store.project?.exportStates['photo-1'], PhotoExportState.saved);
    expect(store.project?.exportStates['photo-2'], PhotoExportState.cancelled);
    expect(find.bySemanticsLabel(RegExp(r'^first\.png, 已导出')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^second\.png, 已取消导出')),
      findsOneWidget,
    );
    semantics.dispose();
  });

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
      selectedRecommendationId: 'clean-natural-01',
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
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const ValueKey('editor-batch-export'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-all')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    exporter.complete();
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
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除项目'));
    await tester.pumpAndSettle();
    expect(find.textContaining('系统相册原图不会被删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(store.project, isNull);
    expect(find.text('选择 1–6 张照片'), findsOneWidget);
    expect(photoFile.existsSync(), isTrue);
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
        selectedRecommendationId: 'clean-natural-01',
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: 'dynamic-text-photo',
      ),
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();

    await tester.pumpWidget(buildTestApp(settings, photoProjectStore: store));
    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('editor-bottom-command-bar')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('editor-manual-adjustments')));
    await tester.pumpAndSettle();
    final composition = find.byKey(
      const ValueKey('editor-tool-category-composition'),
    );
    await tester.dragUntilVisible(
      composition,
      find.byKey(const Key('photo-workspace-scroll')),
      const Offset(0, -220),
    );
    expect(composition.hitTestable(), findsOneWidget);
    await tester.tap(composition);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-free-crop')), findsOneWidget);
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
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('去评分'), findsOneWidget);

    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();

    expect(find.text('映见隐私政策'), findsOneWidget);
  });
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
    selectedRecommendationId: 'clean-natural-01',
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
  await tester.tap(find.text('开始修图'));
  await tester.pumpAndSettle();
  final saveButton = find.byKey(const ValueKey('editor-batch-export'));
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('save-all')));
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
    this.capabilityVersion = 'widget-capability-v1',
  }) : faceSlim = faceSlim ?? portrait;

  final PortraitApplicability portrait;
  final PortraitApplicability faceSlim;
  final PortraitDegradationReason faceSlimReason;
  final int? faceSlimTargetCount;
  final PortraitApplicability body;
  final int? bodyTargetCount;
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
      body: body,
      bodyTargetCount: bodyTargetCount,
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

final class _FirstDeferredPhotoAnalyzer implements PhotoAnalyzer {
  final Completer<void> started = Completer<void>();
  final Completer<void> _firstRelease = Completer<void>();
  int calls = 0;

  void completeFirst() => _firstRelease.complete();

  @override
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) =>
      const PhotoAnalysisEngineIdentity(
        analysisVersion: 'widget-restart-v1',
        capabilityVersion: 'widget-capability-v1',
      );

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) async {
    calls += 1;
    if (calls == 1) {
      started.complete();
      await _firstRelease.future;
    }
    return LocalPhotoAnalysis(
      analysisVersion: 'widget-restart-v1',
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

final class _FailingSaveProjectStore implements PhotoProjectStore {
  _FailingSaveProjectStore(this.project);

  final PhotoProject project;

  @override
  Future<PhotoProject?> loadLatest() async => project;

  @override
  Future<void> save(PhotoProject project) async {
    throw StateError('fixture save failure');
  }
}

final class _FailOncePhotoExporter implements PhotoExporter {
  _FailOncePhotoExporter(this.failPhotoId);

  final String failPhotoId;
  final List<String> calls = [];
  bool _failed = false;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    calls.add(photo.id);
    if (photo.id == failPhotoId && !_failed) {
      _failed = true;
      throw StateError('fixture failure');
    }
    return ExportedPhoto(
      assetId: photo.id,
      width: 4032,
      height: 3024,
      sharePath: '/tmp/Yingjian_${photo.id}.jpg',
    );
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

final class _DeferredPhotoImporter implements PhotoImporter {
  final Completer<PhotoImportBatch> _completion = Completer<PhotoImportBatch>();

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) =>
      _completion.future;

  void cancel() => _completion.complete(const PhotoImportBatch());
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

final class _DeferredPhotoExporter implements PhotoExporter {
  final Completer<ExportedPhoto> _completion = Completer<ExportedPhoto>();

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) => _completion.future;

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
