import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_exporter.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_preview_renderer.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/project/infrastructure/app_owned_photo_importer.dart';
import 'package:yingjian/features/project/infrastructure/json_photo_project_store.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';

import '../test/support/test_services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS runtime opens privacy and terms through production settings navigation',
    (tester) async {
      SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
      final settings = await AppSettings.load();

      await tester.pumpWidget(buildTestApp(settings));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);

      final diagnostics = find.byKey(
        const ValueKey('settings-anonymous-diagnostics'),
      );
      expect(diagnostics, findsOneWidget);
      expect(tester.widget<SwitchListTile>(diagnostics).value, isFalse);

      await tester.tap(find.byKey(const ValueKey('settings-privacy-policy')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('legal-document-privacy')),
        findsOneWidget,
      );
      expect(find.textContaining('隐私政策'), findsWidgets);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings-terms-of-use')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('legal-document-terms')),
        findsOneWidget,
      );
      expect(find.textContaining('使用条款'), findsWidgets);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-settings')), findsOneWidget);
    },
  );

  testWidgets('iOS runtime completes the production one-photo MVP journey', (
    tester,
  ) async {
    final fixtureDirectory = await Directory.systemTemp.createTemp(
      'yingjian-ios-mvp-',
    );
    addTearDown(() => fixtureDirectory.delete(recursive: true));
    final source = File('${fixtureDirectory.path}/portrait.png');
    final sourceBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP4z8AAQgbG'
      '////Z2BgAABOCAf03sBqAAAAAElFTkSuQmCC',
    );
    await source.writeAsBytes(sourceBytes, flush: true);
    final projectRoot = Directory('${fixtureDirectory.path}/project');
    final PhotoProjectStore store = JsonPhotoProjectStore(
      directory: () async => projectRoot,
    );
    final importer = AppOwnedPhotoImporter(
      source: _SelectedPhotoSource([
        SelectedPhoto(path: source.path, name: 'portrait.png'),
      ]),
      mediaDirectory: () async => Directory('${projectRoot.path}/media'),
      createId: () => 'ios-runtime-photo',
    );
    final previewRenderer = _NativePreviewProbe(
      delegate: MethodChannelPhotoPreviewRenderer(),
    );
    final exporter = _NativeExportProbe(delegate: MethodChannelPhotoExporter());
    final analyzer = _ApplicablePortraitAnalyzer();
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();

    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: importer,
        photoProjectStore: store,
        photoExporter: exporter,
        photoPreviewRenderer: previewRenderer,
        photoAnalyzer: analyzer,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-start-editing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor-select-photos')));
    await tester.pumpAndSettle();
    final importedProject = await store.loadLatest();
    final importedPhoto = importedProject!.photos.single;
    expect(analyzer.photoIds, ['ios-runtime-photo']);
    expect(
      importedProject.analysisStates[importedPhoto.id],
      PhotoAnalysisState.ready,
    );
    expect(importedPhoto.localPath, isNot(source.path));
    expect(importedPhoto.localPath, startsWith('${projectRoot.path}/media/'));
    expect(
      importedPhoto.contentSha256,
      '8af516495891dfa905d910262db1f9e4517a83fe2a14a499e4e16480fdeaf751',
    );
    expect(importedPhoto.pixelWidth, 2);
    expect(importedPhoto.pixelHeight, 2);
    expect(importedPhoto.orientation, 1);
    expect(importedPhoto.colorSpace, PhotoColorSpace.srgb);
    expect(importedPhoto.inputFormat, PhotoInputFormat.png);
    expect(await File(importedPhoto.localPath).readAsBytes(), sourceBytes);
    final snapshot =
        jsonDecode(
              await File(
                '${projectRoot.path}/projects/latest.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    final snapshotPhotos = snapshot['photos']! as List<Object?>;
    expect(
      (snapshotPhotos.single! as Map<String, Object?>)['localPath'],
      'media/ios-runtime-photo.png',
    );
    expect(find.text('自然干净'), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-preview-stage')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-bottom-command-bar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recommendation-use')).hitTestable(),
      findsOneWidget,
    );
    expect(previewRenderer.textureSmoothingStrengths, contains(0.35));

    final useRecommendation = find.byKey(const ValueKey('recommendation-use'));
    await tester.ensureVisible(useRecommendation);
    await tester.pumpAndSettle();
    await tester.tap(useRecommendation);
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())?.flowState,
      PhotoProjectFlowState.editing,
    );
    expect(
      (await store.loadLatest())
          ?.effectiveRecipeFor(importedPhoto.id)
          .portraitRecipe
          .textureSmoothing,
      35,
    );
    expect(previewRenderer.textureSmoothingStrengths.last, 0.35);
    expect(
      find.byKey(const ValueKey('editor-batch-export')).hitTestable(),
      findsOneWidget,
    );

    final qualityTab = find.byKey(
      const ValueKey('editor-adjustment-tab-qualityImprovement'),
    );
    expect(qualityTab.hitTestable(), findsOneWidget);
    await tester.tap(qualityTab);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-adjustment-tab-noiseReduction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-adjustment-tab-lowLightRecovery')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-adjustment-tab-hazeRemoval')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-adjustment-tab-detailSharpening')),
      findsOneWidget,
    );
    final applyQualityImprovement = find.byKey(
      const ValueKey('editor-apply-quality-improvement'),
    );
    await tester.ensureVisible(applyQualityImprovement);
    await tester.pumpAndSettle();
    expect(applyQualityImprovement.hitTestable(), findsOneWidget);
    await tester.tap(applyQualityImprovement);
    await tester.pumpAndSettle();
    final qualityRecipe = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .qualityEnhancementRecipe;
    expect(qualityRecipe.noiseReduction, 28);
    expect(qualityRecipe.lowLightRecovery, 32);
    expect(qualityRecipe.hazeRemoval, 18);
    expect(qualityRecipe.detailSharpening, 16);

    final workspace = find.byKey(const ValueKey('photo-workspace-scroll'));
    final portraitTab = find.byKey(
      const ValueKey('editor-adjustment-tab-naturalBeautification'),
    );
    await tester.ensureVisible(portraitTab);
    await tester.pumpAndSettle();
    expect(portraitTab.hitTestable(), findsOneWidget);
    await tester.tap(portraitTab);
    await tester.pumpAndSettle();
    final exposureTab = find.byKey(
      const ValueKey('editor-adjustment-tab-exposure'),
    );
    expect(
      tester.getTopLeft(portraitTab).dx,
      lessThan(tester.getTopLeft(exposureTab).dx),
    );
    expect(
      find.byKey(const ValueKey('editor-apply-one-tap-natural-beautification')),
      findsOneWidget,
    );
    final faceSlimTab = find.byKey(
      const ValueKey('editor-adjustment-tab-faceSlim'),
    );
    expect(faceSlimTab.hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(faceSlimTab).dx,
      lessThan(tester.getTopLeft(exposureTab).dx),
    );
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
    final applyNaturalBeautification = find.byKey(
      const ValueKey('editor-apply-one-tap-natural-beautification'),
    );
    await tester.ensureVisible(applyNaturalBeautification);
    await tester.pumpAndSettle();
    await tester.tap(applyNaturalBeautification);
    await tester.pumpAndSettle();
    var portraitRecipe = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .portraitRecipe;
    expect(portraitRecipe.textureSmoothing, 45);
    expect(portraitRecipe.skinToneLighting, 40);
    expect(portraitRecipe.blemishReduction, 20);
    expect(
      (await store.loadLatest())
          ?.effectiveRecipeFor(importedPhoto.id)
          .portraitStrength,
      0,
    );

    final textureSmoothingTab = find.byKey(
      const ValueKey('editor-adjustment-tab-textureSmoothing'),
    );
    await tester.ensureVisible(textureSmoothingTab);
    await tester.pumpAndSettle();
    expect(textureSmoothingTab.hitTestable(), findsOneWidget);
    await tester.tap(textureSmoothingTab);
    await tester.pumpAndSettle();
    final textureSlider = find.byKey(
      const ValueKey('editor-adjustment-textureSmoothing'),
    );
    await tester.ensureVisible(textureSlider);
    await tester.pumpAndSettle();
    expect(textureSlider, findsOneWidget);
    final textureControl = find.descendant(
      of: textureSlider,
      matching: find.byType(Slider),
    );
    expect(textureControl, findsOneWidget);
    expect(tester.widget<Slider>(textureControl).value, closeTo(0.45, 0.01));
    await tester.drag(textureControl, const Offset(90, 0));
    await tester.pumpAndSettle();
    portraitRecipe = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .portraitRecipe;
    expect(portraitRecipe.textureSmoothing, greaterThan(45));
    expect(
      find.byKey(const ValueKey('editor-adjustment-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-portrait-tool-status')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-reset-current-adjustment')),
      findsOneWidget,
    );

    final bodySlimTab = find.byKey(
      const ValueKey('editor-adjustment-tab-bodySlim'),
    );
    await tester.ensureVisible(bodySlimTab);
    await tester.pumpAndSettle();
    expect(bodySlimTab.hitTestable(), findsOneWidget);
    await tester.tap(bodySlimTab);
    await tester.pumpAndSettle();
    final bodySlimControl = find.descendant(
      of: find.byKey(const ValueKey('editor-adjustment-bodySlim')),
      matching: find.byType(Slider),
    );
    expect(bodySlimControl, findsOneWidget);
    expect(tester.widget<Slider>(bodySlimControl).max, 0.35);
    await tester.drag(bodySlimControl, const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())
          ?.effectiveRecipeFor(importedPhoto.id)
          .bodySlimStrength,
      greaterThan(0),
    );

    await tester.drag(
      find.byKey(const ValueKey('editor-adjustment-tabs')),
      const Offset(180, 0),
    );
    await tester.pumpAndSettle();
    final visibleFaceSlimTab = find.byKey(
      const ValueKey('editor-adjustment-tab-faceSlim'),
    );
    expect(visibleFaceSlimTab.hitTestable(), findsOneWidget);
    await tester.tap(visibleFaceSlimTab);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-face-slim-target-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-face-slim-target-1')),
      findsOneWidget,
    );
    final faceSlimControl = find.descendant(
      of: find.byKey(const ValueKey('editor-adjustment-faceSlim')),
      matching: find.byType(Slider),
    );
    expect(faceSlimControl, findsOneWidget);
    expect(tester.widget<Slider>(faceSlimControl).max, 0.5);
    await tester.drag(faceSlimControl, const Offset(90, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-face-slim-target-1')));
    await tester.pumpAndSettle();
    await tester.drag(faceSlimControl, const Offset(50, 0));
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())!
          .effectiveRecipeFor(importedPhoto.id)
          .faceSlimRecipe
          .targetStrengths,
      everyElement(greaterThan(0)),
    );

    await tester.ensureVisible(exposureTab);
    await tester.pumpAndSettle();
    expect(exposureTab.hitTestable(), findsOneWidget);
    await tester.tap(exposureTab);
    await tester.pumpAndSettle();
    final exposureSlider = find.byKey(
      const ValueKey('editor-adjustment-exposure'),
    );
    await tester.dragUntilVisible(
      exposureSlider,
      workspace,
      const Offset(0, -260),
    );
    final exposureControl = find.descendant(
      of: exposureSlider,
      matching: find.byType(Slider),
    );
    expect(exposureControl, findsOneWidget);
    await tester.drag(exposureControl, const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())?.effectiveRecipeFor(importedPhoto.id).exposure,
      isNot(0),
    );

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('editor-batch-export')),
      workspace,
      const Offset(0, -320),
    );
    await tester.tap(find.byKey(const ValueKey('editor-batch-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-confirm')));
    await tester.pump();
    for (
      var attempt = 0;
      attempt < 300 && exporter.results.isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(exporter.photoIds, ['ios-runtime-photo']);
    expect(exporter.errors, isEmpty);
    expect(exporter.results, hasLength(1));
    expect(exporter.recipes.single.portraitStrength, 0);
    expect(
      exporter.recipes.single.portraitRecipe.textureSmoothing,
      greaterThan(45),
    );
    expect(exporter.recipes.single.portraitRecipe.skinToneLighting, 40);
    expect(exporter.recipes.single.portraitRecipe.blemishReduction, 20);
    expect(previewRenderer.backends, contains('ios-core-image'));
    expect(previewRenderer.updateCount, greaterThan(0));
    final exported = exporter.results.single;
    expect(exported.width, 2);
    expect(exported.height, 2);
    final sharePath = exported.sharePath;
    expect(sharePath, isNotNull);
    final shareFile = File(sharePath!);
    expect(await shareFile.exists(), isTrue);
    expect((await shareFile.readAsBytes()).take(2), [0xff, 0xd8]);
    expect(find.text('已保存 1 张 · 失败 0 张 · 取消 0 张'), findsWidgets);
    expect(await source.readAsBytes(), sourceBytes);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(previewRenderer.disposeCount, greaterThan(0));
    if (await shareFile.exists()) {
      await shareFile.delete();
    }

    final restoredPreviewRenderer = _NativePreviewProbe(
      delegate: MethodChannelPhotoPreviewRenderer(),
    );
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoProjectStore: JsonPhotoProjectStore(
          directory: () async => projectRoot,
        ),
        photoPreviewRenderer: restoredPreviewRenderer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-resume-project')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);
    expect(find.text('portrait.png'), findsOneWidget);
    expect(
      find.byKey(ValueKey('photo-preview-${importedPhoto.id}')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(restoredPreviewRenderer.disposeCount, greaterThan(0));
  });

  testWidgets(
    'iOS runtime completes the production six-photo journey and retries only failures',
    (tester) async {
      final fixtureDirectory = await Directory.systemTemp.createTemp(
        'yingjian-ios-six-photo-mvp-',
      );
      addTearDown(() => fixtureDirectory.delete(recursive: true));
      final sourceBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP4z8AAQgbG'
        '////Z2BgAABOCAf03sBqAAAAAElFTkSuQmCC',
      );
      final photos = <ProjectPhoto>[];
      final originalBytes = <String, List<int>>{};
      for (var index = 0; index < 6; index += 1) {
        final id = 'ios-runtime-photo-${index + 1}';
        final source = File('${fixtureDirectory.path}/$id.png');
        await source.writeAsBytes(sourceBytes, flush: true);
        originalBytes[source.path] = await source.readAsBytes();
        photos.add(
          ProjectPhoto(id: id, localPath: source.path, originalName: '$id.png'),
        );
      }
      final store = MemoryPhotoProjectStore();
      final exporter = _FailOnceRecordingExporter(
        failOncePhotoId: 'ios-runtime-photo-4',
      );
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
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-start-editing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-select-photos')));
      await tester.pumpAndSettle();

      expect(store.project?.photos, hasLength(6));
      expect(
        store.project?.analysisStates.values,
        everyElement(PhotoAnalysisState.fallback),
      );
      expect(
        find.byKey(const ValueKey('recommendation-texturedStyle')),
        findsOneWidget,
      );
      final workspace = find.byKey(const ValueKey('photo-workspace-scroll'));
      final naturalRecommendation = find.byKey(
        const ValueKey('recommendation-naturalClean'),
      );
      final naturalRecommendationLabel = find
          .descendant(of: naturalRecommendation, matching: find.byType(Text))
          .first;
      await tester.dragUntilVisible(
        naturalRecommendationLabel,
        workspace,
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();
      await tester.tap(naturalRecommendationLabel);
      await tester.pumpAndSettle();
      final useRecommendation = find.byKey(
        const ValueKey('recommendation-use'),
      );
      await tester.dragUntilVisible(
        useRecommendation,
        workspace,
        const Offset(0, -220),
      );
      await tester.tap(useRecommendation);
      await tester.pumpAndSettle();

      expect(store.project?.flowState, PhotoProjectFlowState.editing);
      expect(store.project?.sharedStyle.family, SharedStyleFamily.naturalClean);
      expect(store.project?.adaptiveCompensations, hasLength(6));

      final exposureSlider = find.byKey(
        const ValueKey('editor-adjustment-exposure'),
      );
      await tester.dragUntilVisible(
        exposureSlider,
        workspace,
        const Offset(0, -260),
      );
      await tester.drag(exposureSlider, const Offset(70, 0));
      await tester.pumpAndSettle();
      final sharedExposure = store.project!.sharedStyle.recipe.exposure;
      expect(sharedExposure, isNot(0));

      final currentPhotoScope = find.byKey(
        const ValueKey('editor-scope-currentPhoto'),
      );
      await tester.dragUntilVisible(
        currentPhotoScope,
        workspace,
        const Offset(0, 260),
      );
      await tester.tap(currentPhotoScope);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-photo-ios-runtime-photo-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-adjustment-tab-contrast')),
      );
      await tester.pumpAndSettle();
      final contrastSlider = find.byKey(
        const ValueKey('editor-adjustment-contrast'),
      );
      await tester.drag(contrastSlider, const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(store.project?.photoOverrides.keys, ['ios-runtime-photo-2']);
      expect(store.project?.sharedStyle.recipe.exposure, sharedExposure);
      expect(
        store.project?.effectiveRecipeFor('ios-runtime-photo-1').contrast,
        isNot(
          store.project?.effectiveRecipeFor('ios-runtime-photo-2').contrast,
        ),
      );

      final exportButton = find.byKey(const ValueKey('editor-batch-export'));
      await tester.dragUntilVisible(
        exportButton,
        workspace,
        const Offset(0, -340),
      );
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-confirm')));
      await tester.pumpAndSettle();

      expect(exporter.photoIds, [
        'ios-runtime-photo-1',
        'ios-runtime-photo-2',
        'ios-runtime-photo-3',
        'ios-runtime-photo-4',
        'ios-runtime-photo-5',
        'ios-runtime-photo-6',
      ]);
      expect(
        store.project?.exportStates['ios-runtime-photo-4'],
        PhotoExportState.failed,
      );
      expect(find.byKey(const ValueKey('export-retry-failed')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('export-retry-failed')));
      await tester.pumpAndSettle();

      expect(
        store.project?.exportStates.values,
        everyElement(PhotoExportState.saved),
      );
      expect(exporter.photoIds.last, 'ios-runtime-photo-4');
      expect(exporter.photoIds, hasLength(7));
      for (final photo in photos) {
        expect(
          await File(photo.localPath).readAsBytes(),
          originalBytes[photo.localPath],
        );
      }
    },
  );
}

final class _NativePreviewProbe implements PhotoPreviewRenderer {
  _NativePreviewProbe({required this.delegate});

  final PhotoPreviewRenderer delegate;
  final List<String> backends = [];
  final List<double> textureSmoothingStrengths = [];
  int updateCount = 0;
  int disposeCount = 0;

  @override
  Future<PhotoPreviewHandle> create({
    required String sourcePath,
    required ImagePipeline pipeline,
    int maxEdge = 2048,
  }) async {
    final handle = await delegate.create(
      sourcePath: sourcePath,
      pipeline: pipeline,
      maxEdge: maxEdge,
    );
    backends.add(handle.backend);
    textureSmoothingStrengths.add(_textureSmoothingStrength(pipeline));
    return handle;
  }

  @override
  Future<void> update({
    required PhotoPreviewHandle handle,
    required ImagePipeline pipeline,
  }) async {
    await delegate.update(handle: handle, pipeline: pipeline);
    textureSmoothingStrengths.add(_textureSmoothingStrength(pipeline));
    updateCount += 1;
  }

  @override
  Future<void> dispose(PhotoPreviewHandle handle) async {
    await delegate.dispose(handle);
    disposeCount += 1;
  }

  double _textureSmoothingStrength(ImagePipeline pipeline) {
    final arguments = pipeline.toPlatformArguments();
    final portrait = arguments['portraitRecipeV2']! as Map<String, Object>;
    return (portrait['textureSmoothing']! as num).toDouble() / 100;
  }
}

final class _SelectedPhotoSource implements PhotoSource {
  _SelectedPhotoSource(this.photos);

  final List<SelectedPhoto> photos;

  @override
  Future<List<SelectedPhoto>> pickPhotos({required int limit}) async {
    return photos.take(limit).toList(growable: false);
  }
}

final class _NativeExportProbe implements PhotoExporter {
  _NativeExportProbe({required this.delegate});

  final PhotoExporter delegate;
  final List<String> photoIds = [];
  final List<EditRecipe> recipes = [];
  final List<ExportedPhoto> results = [];
  final List<Object> errors = [];

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    photoIds.add(photo.id);
    recipes.add(recipe);
    try {
      final exported = await delegate.export(photo: photo, recipe: recipe);
      results.add(exported);
      return exported;
    } on Object catch (error) {
      errors.add(error);
      rethrow;
    }
  }
}

final class _ApplicablePortraitAnalyzer implements PhotoAnalyzer {
  static const _analysisVersion = 'ios-runtime-fixture-v1';
  static const _capabilityVersion = 'ios-core-image-vision-v12-multiface-slim';
  final List<String> photoIds = [];

  @override
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) =>
      const PhotoAnalysisEngineIdentity(
        analysisVersion: _analysisVersion,
        capabilityVersion: _capabilityVersion,
      );

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) async {
    photoIds.add(photo.id);
    return LocalPhotoAnalysis(
      analysisVersion: _analysisVersion,
      capabilityVersion: _capabilityVersion,
      contentSha256: photo.contentSha256,
      orientation: photo.orientation,
      pixelWidth: photo.pixelWidth,
      pixelHeight: photo.pixelHeight,
      colorSpace: photo.colorSpace,
      disposition: PhotoAnalysisDisposition.ready,
      fallbackReason: AnalysisFallbackReason.none,
      confidence: AnalysisConfidence.high,
      exposure: ExposureCondition.balanced,
      whiteBalance: WhiteBalanceCondition.balanced,
      clarity: ClarityCondition.clear,
      portrait: PortraitApplicability.applicable,
      portraitReason: PortraitDegradationReason.none,
      faceSlimTargetCount: 2,
      body: PortraitApplicability.applicable,
      scene: SceneKind.people,
    );
  }
}

final class _FailOnceRecordingExporter implements PhotoExporter {
  _FailOnceRecordingExporter({required this.failOncePhotoId});

  final String failOncePhotoId;
  final List<String> photoIds = [];
  bool _failed = false;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    photoIds.add(photo.id);
    if (photo.id == failOncePhotoId && !_failed) {
      _failed = true;
      throw StateError('injected iOS runtime export failure');
    }
    return ExportedPhoto(assetId: 'export-${photo.id}', width: 2, height: 2);
  }
}
