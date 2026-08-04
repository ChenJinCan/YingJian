import 'dart:io';

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
          await tester.tap(find.text('开始修图'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('选择照片'));
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
          await tester.ensureVisible(find.text('使用这套效果'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('使用这套效果'));
          await tester.pumpAndSettle();

          expect(store.project?.flowState, PhotoProjectFlowState.editing);
          expect(
            store.project?.sharedStyle.family,
            SharedStyleFamily.texturedStyle,
          );
          expect(store.project?.adaptiveCompensations, hasLength(6));

          await tester.dragUntilVisible(
            find.text('曝光'),
            find.byType(ListView).first,
            const Offset(0, -240),
          );
          await tester.drag(find.byType(Slider).first, const Offset(70, 0));
          await tester.pumpAndSettle();
          final sharedExposure = store.project!.sharedStyle.recipe.exposure;
          expect(sharedExposure, isNot(0));

          await tester.dragUntilVisible(
            find.text('仅当前照片'),
            find.byType(ListView).first,
            const Offset(0, 320),
          );
          await tester.tap(find.text('仅当前照片'));
          await tester.pumpAndSettle();
          final thumbnailStrip = find.byType(ListView).last;
          await tester.ensureVisible(thumbnailStrip);
          await tester.pumpAndSettle();
          await tester.tap(find.bySemanticsLabel(RegExp(r'^photo-2\.png')));
          await tester.pumpAndSettle();
          await tester.dragUntilVisible(
            find.text('对比度'),
            find.byType(ListView).first,
            const Offset(0, -260),
          );
          await tester.tap(find.text('对比度'));
          await tester.pumpAndSettle();
          await tester.drag(find.byType(Slider).first, const Offset(60, 0));
          await tester.pumpAndSettle();

          expect(store.project?.photoOverrides.keys, ['photo-2']);
          expect(store.project?.sharedStyle.recipe.exposure, sharedExposure);
          expect(
            store.project?.effectiveRecipeFor('photo-1').contrast,
            isNot(store.project?.effectiveRecipeFor('photo-2').contrast),
          );

          await tester.dragUntilVisible(
            find.text('批量导出 6 张'),
            find.byType(ListView).first,
            const Offset(0, -340),
          );
          await tester.drag(find.byType(ListView).first, const Offset(0, -90));
          await tester.pumpAndSettle();
          await tester.tap(find.text('批量导出 6 张'));
          await tester.pumpAndSettle();
          expect(find.textContaining('共 6 张'), findsOneWidget);
          await tester.tap(find.text('开始导出'));
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

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('第 1 / 6 张 · 编辑整组'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^photo-1\.png')), findsWidgets);

    await tester.dragUntilVisible(
      find.text('批量导出 6 张'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('批量导出 6 张'), findsOneWidget);
    expect(tester.getSize(find.text('批量导出 6 张')).height, greaterThan(20));
    semantics.dispose();
  });
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
