import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';
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
          expect(
            find.byKey(const ValueKey('editor-recommendation-stage')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('recommendation-confirm')),
          );
          await tester.pumpAndSettle();
          expect(store.project?.flowState, PhotoProjectFlowState.editing);
          expect(
            store.project?.sharedStyle.family,
            SharedStyleFamily.naturalClean,
          );
          expect(store.project?.adaptiveCompensations, hasLength(6));
          expect(find.text('自然干净'), findsNothing);

          await tester.tap(find.byKey(const ValueKey('editor-manual-entry')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('editor-tools-dock')),
            findsOneWidget,
          );
          final commonMetaOps = find.byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('editor-adjustment-tab-');
          });
          expect(commonMetaOps.evaluate().length, lessThanOrEqualTo(5));
          expect(find.byKey(const ValueKey('editor-scope-menu')), findsNothing);
          final workspace = find.byKey(const Key('editor-tools-scroll'));
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
          expect(
            find.byKey(const ValueKey('editor-reset-current-adjustment')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('editor-reset-current-adjustment')),
          );
          await tester.pumpAndSettle();
          expect(store.project!.sharedStyle.recipe.exposure, 0);
          await tester.tap(find.byKey(const ValueKey('editor-undo')));
          await tester.pumpAndSettle();
          expect(store.project!.sharedStyle.recipe.exposure, sharedExposure);

          await tester.tap(find.byKey(const ValueKey('editor-tools-done')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('editor-manual-entry')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('editor-all-tools')));
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(
            find.byKey(const ValueKey('editor-tools-dock')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('editor-meta-op-search')),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const ValueKey('editor-meta-op-search')),
            '对比度',
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('editor-meta-op-result-tone.contrast')),
          );
          await tester.pumpAndSettle();
          await tester.fling(
            find.byKey(const ValueKey('editor-swipe-photos')),
            const Offset(-300, 0),
            1200,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('editor-adjustment-tab-contrast')),
          );
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

          expect(store.project?.photoOverrides, isEmpty);
          expect(store.project?.sharedStyle.recipe.exposure, sharedExposure);
          expect(
            store.project?.effectiveRecipeFor('photo-1').contrast,
            store.project?.effectiveRecipeFor('photo-2').contrast,
          );

          await tester.tap(find.byKey(const ValueKey('editor-tools-done')));
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
          expect(find.text('仅保存这张'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('save-all')));
          await tester.tap(find.byKey(const ValueKey('save-confirm')));
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
          await tester.tap(find.byKey(const ValueKey('export-retry-failed')));
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
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('home-start-editing')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('1/6'), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-open-tools')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
    await tester.pumpAndSettle();
    final workspace = find.byKey(const Key('editor-tools-scroll'));
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
      (node) => node.label.startsWith('亮一点') && node.flagsCollection.isSlider,
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
        (node) => node.label.startsWith('亮一点') && node.value == '12',
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

    await tester.tap(find.byKey(const ValueKey('editor-all-tools')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('editor-meta-op-search'));
    expect(search, findsOneWidget);
    await tester.enterText(search, '不存在');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-meta-op-search-empty')),
      findsOneWidget,
    );
    _expectCurrentTapSemanticsAtLeast(tester, 48);
    await tester.tap(find.byKey(const ValueKey('editor-all-tools-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-all-tools')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-meta-op-search')),
      '构图',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editor-meta-op-result-composition.geometry')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-composition-tools')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('editor-all-tools')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-meta-op-search')),
      '滤镜',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editor-meta-op-result-style.filter')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-filter-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-hsl-channels')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('editor-all-tools')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-meta-op-search')),
      '蓝色',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editor-meta-op-result-color.hsl.blue')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-hsl-channels')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-filter-list')), findsNothing);
    final selectedBlue = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('editor-hsl-blue')),
    );
    expect(selectedBlue.selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('editor-all-tools')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-meta-op-search')),
      '降噪',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('editor-meta-op-result-quality.noise_reduction'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-adjustment-noiseReduction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-adjustment-detailSharpening')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('editor-all-tools')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-meta-op-search')),
      '曝光',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editor-meta-op-result-tone.exposure')),
    );
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
