import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

import 'support/test_services.dart';

void main() {
  testWidgets(
    'complete six-photo MVP journey survives partial export failure',
    (tester) async {
      var networkClientCreations = 0;
      await HttpOverrides.runZoned(
        () async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final source = File(
            'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
            'Icon-App-1024x1024@1x.png',
          );
          final originalBytes = source.readAsBytesSync();
          final photos = List.generate(
            6,
            (index) => ProjectPhoto(
              id: 'photo-${index + 1}',
              localPath: source.path,
              originalName: 'photo-${index + 1}.png',
            ),
          );
          final store = MemoryPhotoProjectStore();
          final exporter = _JourneyExporter(failOncePhotoId: 'photo-4');
          SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
          final settings = await AppSettings.load();
          await tester.pumpWidget(
            buildTestApp(
              settings,
              photoImporter: FakePhotoImporter(photos),
              photoProjectStore: store,
              photoExporter: exporter,
            ),
          );

          expect(find.textContaining('登录'), findsNothing);
          await tester.tap(find.byKey(const ValueKey('home-start-editing')));
          await tester.pumpAndSettle();

          expect(store.project?.photos, hasLength(6));
          expect(
            store.project?.analysisStates.values,
            everyElement(PhotoAnalysisState.fallback),
          );
          expect(
            store.project?.flowState,
            PhotoProjectFlowState.choosingRecommendation,
          );
          expect(find.text('自然干净'), findsOneWidget);
          expect(find.text('氛围色彩'), findsOneWidget);
          await tester.drag(find.byType(ListView).last, const Offset(-220, 0));
          await tester.pumpAndSettle();
          expect(find.text('质感风格'), findsOneWidget);
          await tester.tap(find.text('质感风格'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('就用这个'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('就用这个'));
          await tester.pumpAndSettle();

          expect(store.project?.flowState, PhotoProjectFlowState.editing);
          expect(
            store.project?.sharedStyle.family,
            SharedStyleFamily.texturedStyle,
          );
          expect(store.project?.adaptiveCompensations, hasLength(6));

          await tester.tap(find.byKey(const ValueKey('editor-manual-entry')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('editor-manual-sheet')),
            findsOneWidget,
          );
          expect(find.text('亮一点'), findsOneWidget);
          expect(find.text('暖一点'), findsOneWidget);
          expect(find.text('自然肤色'), findsOneWidget);
          expect(find.text('皮肤更细腻'), findsOneWidget);
          expect(find.text('脸小一点'), findsOneWidget);
          expect(find.text('身形更自然'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('manual-action-brighter')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('editor-feedback-pill')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('editor-feedback-undo')));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
          await tester.pumpAndSettle();
          var workspace = find.byKey(const Key('photo-workspace-scroll'));
          final exposureAdjustment = find.byKey(
            const ValueKey('editor-adjustment-exposure'),
          );
          await tester.dragUntilVisible(
            exposureAdjustment,
            workspace,
            const Offset(0, -240),
          );
          await Scrollable.ensureVisible(
            tester.element(exposureAdjustment),
            alignment: 0.35,
          );
          await tester.pumpAndSettle();
          await tester.drag(
            find.descendant(
              of: exposureAdjustment,
              matching: find.byType(Slider),
            ),
            const Offset(70, 0),
          );
          await tester.pumpAndSettle();
          final sharedExposure = store.project!.sharedStyle.recipe.exposure;
          expect(sharedExposure, isNot(0));

          await tester.dragUntilVisible(
            find.text('仅当前照片'),
            workspace,
            const Offset(0, 320),
          );
          await tester.tap(find.text('仅当前照片'));
          await tester.pumpAndSettle();
          await tester.fling(
            find.byKey(const ValueKey('editor-swipe-photos')),
            const Offset(-300, 0),
            1200,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
          await tester.pumpAndSettle();
          workspace = find.byKey(const Key('photo-workspace-scroll'));
          await tester.dragUntilVisible(
            find.byKey(const ValueKey('editor-adjustment-tab-contrast')),
            workspace,
            const Offset(0, -260),
          );
          final contrastTab = find.byKey(
            const ValueKey('editor-adjustment-tab-contrast'),
          );
          await Scrollable.ensureVisible(
            tester.element(contrastTab),
            alignment: 0.35,
          );
          await tester.pumpAndSettle();
          await tester.tap(contrastTab.hitTestable());
          await tester.pumpAndSettle();
          final contrastAdjustment = find.byKey(
            const ValueKey('editor-adjustment-contrast'),
          );
          await tester.ensureVisible(contrastAdjustment);
          await tester.drag(
            find.descendant(
              of: contrastAdjustment,
              matching: find.byType(Slider),
            ),
            const Offset(60, 0),
          );
          await tester.pumpAndSettle();

          expect(store.project?.photoOverrides.keys, ['photo-2']);
          expect(store.project?.sharedStyle.recipe.exposure, sharedExposure);
          expect(
            store.project?.effectiveRecipeFor('photo-1').contrast,
            isNot(store.project?.effectiveRecipeFor('photo-2').contrast),
          );

          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();
          final savePhotos = find.byKey(const ValueKey('editor-batch-export'));
          await tester.ensureVisible(savePhotos);
          await tester.tap(savePhotos);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('editor-save-options')),
            findsOneWidget,
          );
          expect(find.text('保存全部 6 张'), findsOneWidget);
          expect(find.text('保存当前 1 张'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('save-all')));
          await tester.pumpAndSettle();

          expect(find.text('已保存 5 张 · 失败 1 张 · 取消 0 张'), findsWidgets);
          expect(exporter.calls, [
            'photo-1',
            'photo-2',
            'photo-3',
            'photo-4',
            'photo-5',
            'photo-6',
          ]);
          await tester.tap(find.text('只重试失败与取消项'));
          await tester.pumpAndSettle();

          expect(
            store.project?.exportStates.values,
            everyElement(PhotoExportState.saved),
          );
          expect(exporter.calls.last, 'photo-4');
          expect(source.readAsBytesSync(), originalBytes);
        },
        createHttpClient: (_) {
          networkClientCreations += 1;
          throw StateError('The local MVP journey must remain offline');
        },
      );
      expect(networkClientCreations, 0);
    },
  );

  testWidgets('editing journey remains understandable at maximum text size', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final semantics = tester.ensureSemantics();

    final source = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final photos = List.generate(
      6,
      (index) => ProjectPhoto(
        id: 'photo-${index + 1}',
        localPath: source.path,
        originalName: 'photo-${index + 1}.png',
      ),
    );
    final project = PhotoProject(
      id: 'accessible-project',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      photos: photos,
      flowState: PhotoProjectFlowState.editing,
      selectedRecommendationId: 'mvp-catalog-v1:clean-balanced',
      sharedStyle: SharedStyle(
        family: SharedStyleFamily.naturalClean,
        recipe: EditRecipe(exposure: 0.1),
      ),
      adaptiveCompensations: {
        for (final photo in photos)
          photo.id: AdaptiveCompensation(
            recipe: EditRecipe.neutral,
            source: AdaptiveCompensationSource.safeFallbackV1,
          ),
      },
    );
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: MemoryPhotoProjectStore(project),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('home-start-editing')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('1 / 6'), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-open-tools')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
    await tester.pumpAndSettle();
    var workspace = find.byKey(const Key('photo-workspace-scroll'));
    final exposureAdjustment = find.byKey(
      const ValueKey('editor-adjustment-exposure'),
    );
    await tester.dragUntilVisible(
      exposureAdjustment,
      workspace,
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    final exposureSlider = find.semantics.byPredicate(
      (node) => node.label.startsWith('曝光') && node.flagsCollection.isSlider,
    );
    expect(exposureSlider, findsOne);
    final exposureData = exposureSlider.evaluate().single.getSemanticsData();
    expect(exposureData.value, '10');
    expect(exposureData.hasAction(SemanticsAction.increase), isTrue);
    expect(exposureData.hasAction(SemanticsAction.decrease), isTrue);
    tester.semantics.increase(exposureSlider);
    await tester.pump();
    expect(
      find.semantics.byPredicate(
        (node) => node.label.startsWith('曝光') && node.value == '12',
      ),
      findsOne,
    );
    for (var step = 0; step < 44; step += 1) {
      tester.semantics.increase(exposureSlider);
      await tester.pump();
    }
    final maximumExposure = exposureSlider.evaluate().single.getSemanticsData();
    expect(maximumExposure.value, '100');
    expect(maximumExposure.hasAction(SemanticsAction.increase), isFalse);
    expect(maximumExposure.hasAction(SemanticsAction.decrease), isTrue);
    _expectCurrentTapSemanticsAtLeast(tester, 48);

    final currentPhotoScope = find.byKey(
      const ValueKey('editor-scope-currentPhoto'),
    );
    await tester.dragUntilVisible(
      currentPhotoScope,
      workspace,
      const Offset(0, 300),
    );
    await Scrollable.ensureVisible(
      tester.element(currentPhotoScope),
      alignment: 0.15,
    );
    await tester.pumpAndSettle();
    await tester.tap(currentPhotoScope.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
    await tester.pumpAndSettle();
    workspace = find.byKey(const Key('photo-workspace-scroll'));
    final semanticCategory = find.byKey(
      const ValueKey('editor-tool-category-semantic'),
    );
    await tester.ensureVisible(semanticCategory);
    await tester.tap(semanticCategory);
    await tester.pumpAndSettle();
    final eraseBrush = find.byKey(const ValueKey('editor-open-erase-brush'));
    await tester.dragUntilVisible(eraseBrush, workspace, const Offset(0, -300));
    await Scrollable.ensureVisible(tester.element(eraseBrush), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(eraseBrush.hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('erase-brush-undo')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('erase-brush-apply')));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();

    final savePhotos = find.byKey(const ValueKey('editor-batch-export'));
    await tester.ensureVisible(savePhotos);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(savePhotos, findsOneWidget);
    expect(tester.getSize(find.text('保存')).height, greaterThan(20));
    _expectCurrentTapSemanticsAtLeast(tester, 48);
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}

void _expectCurrentTapSemanticsAtLeast(WidgetTester tester, double minimum) {
  final targets = find.semantics.byAction(SemanticsAction.tap);
  expect(targets, findsWidgets);
  for (final node in targets.evaluate()) {
    expect(
      node.rect.width,
      greaterThanOrEqualTo(minimum),
      reason: 'Tap target "${node.label}" is too narrow.',
    );
    expect(
      node.rect.height,
      greaterThanOrEqualTo(minimum),
      reason: 'Tap target "${node.label}" is too short.',
    );
  }
}

final class _JourneyExporter implements PhotoExporter {
  _JourneyExporter({required this.failOncePhotoId});

  final String failOncePhotoId;
  final List<String> calls = [];
  bool _failed = false;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    calls.add(photo.id);
    if (photo.id == failOncePhotoId && !_failed) {
      _failed = true;
      throw StateError('injected export failure');
    }
    return ExportedPhoto(assetId: photo.id, width: 4032, height: 3024);
  }
}
