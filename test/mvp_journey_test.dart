import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/navigation/app_router.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';
import 'package:yingjian/features/editor/presentation/editor_page.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

import 'support/test_services.dart';

void main() {
  testWidgets('legacy editor export regression stays focused and offline', (
    tester,
  ) async {
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
        final photo = ProjectPhoto(
          id: 'photo-1',
          localPath: source.path,
          originalName: 'portrait.png',
        );
        final store = MemoryPhotoProjectStore();
        final exporter = _JourneyExporter(failOncePhotoId: 'never');
        SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
        final settings = await AppSettings.load();
        await tester.pumpWidget(
          buildTestApp(
            settings,
            photoImporter: FakePhotoImporter([photo]),
            photoProjectStore: store,
            photoExporter: exporter,
          ),
        );
        await tester.pumpAndSettle();

        await _openLegacyEditor(tester, startWithImport: true);

        expect(store.project?.photos, [photo]);
        expect(store.project?.flowState, PhotoProjectFlowState.editing);
        expect(
          find.byKey(const ValueKey('editor-photo-preview')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('editor-scope-menu')), findsNothing);
        expect(find.byKey(const Key('photo-strip-scroll')), findsNothing);
        expect(find.textContaining('添加照片'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('editor-export')));
        await tester.pumpAndSettle();

        expect(exporter.calls, ['photo-1']);
        expect(store.project?.exportStates['photo-1'], PhotoExportState.saved);
        expect(source.readAsBytesSync(), originalBytes);
      },
      createHttpClient: (_) {
        networkClientCreations += 1;
        throw StateError('The local MVP journey must remain offline');
      },
    );
    expect(networkClientCreations, 0);
  });

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
    final photos = [
      ProjectPhoto(
        id: 'photo-1',
        localPath: source.path,
        originalName: 'photo-1.png',
      ),
    ];
    final project = PhotoProject(
      id: 'accessible-project',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      photos: photos,
      flowState: PhotoProjectFlowState.editing,
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
    await tester.pumpAndSettle();

    await _openLegacyEditor(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('photo-strip-scroll')), findsNothing);
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
    await tester.pumpAndSettle();
    expect(
      find.semantics.byPredicate(
        (node) => node.label.startsWith('亮一点') && node.value == '12',
      ),
      findsOne,
    );
    for (var step = 0; step < 44; step += 1) {
      tester.semantics.increase(exposureSlider);
      await tester.pumpAndSettle();
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

    final savePhotos = find.byKey(const ValueKey('editor-export'));
    await tester.ensureVisible(savePhotos);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(savePhotos, findsOneWidget);
    expect(tester.getSize(find.text('导出')).height, greaterThan(20));
    _expectCurrentTapSemanticsAtLeast(tester, 48);
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _openLegacyEditor(
  WidgetTester tester, {
  bool startWithImport = false,
}) async {
  unawaited(
    AppRouter.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(startWithImport: startWithImport),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
