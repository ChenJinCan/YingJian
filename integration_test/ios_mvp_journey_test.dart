import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
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
    'first launch enters onboarding and continues through production routing',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();

      await tester.pumpWidget(buildTestApp(settings));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('onboarding-page')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('onboarding-full-screen-background')),
        findsOneWidget,
      );
      expect(find.textContaining('不会上传你的照片'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('onboarding-privacy')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('legal-document-privacy')),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-start-editing')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-full-screen-background')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-journey-guide')), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(settings.onboardingComplete, isTrue);
    },
  );

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
    expect(find.byKey(const ValueKey('editor-preview-stage')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-bottom-command-bar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recommendation-use')).hitTestable(),
      findsOneWidget,
    );
    expect(previewRenderer.textureSmoothingStrengths, contains(0.5));
    expect(previewRenderer.maxEdges.where((edge) => edge == 384), hasLength(3));
    expect(previewRenderer.maxEdges, contains(2048));

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
      50,
    );
    expect(
      (await store.loadLatest())
          ?.effectiveRecipeFor(importedPhoto.id)
          .portraitRecipe
          .blemishReduction,
      20,
    );
    expect(previewRenderer.textureSmoothingStrengths.last, 0.5);
    expect(
      find.byKey(const ValueKey('editor-batch-export')).hitTestable(),
      findsOneWidget,
    );

    final exposureBeforeVoice = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .exposure;
    final voiceEntry = find.byKey(const ValueKey('voice-edit-entry'));
    expect(voiceEntry.hitTestable(), findsOneWidget);
    await tester.tap(voiceEntry);
    await tester.pumpAndSettle();
    expect(find.text('想怎么改？'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('voice-edit-text-field')),
      '照片亮一点',
    );
    await tester.tap(find.byKey(const ValueKey('voice-edit-submit')));
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())!.effectiveRecipeFor(importedPhoto.id).exposure,
      closeTo(exposureBeforeVoice + 0.12, 0.0001),
    );
    expect(find.byKey(const ValueKey('editor-feedback-pill')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('editor-feedback-undo')));
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())!.effectiveRecipeFor(importedPhoto.id).exposure,
      exposureBeforeVoice,
    );

    await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-tools-dock')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-preview-stage')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('editor-preview-fullscreen')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-fullscreen-preview')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('editor-fullscreen-preview-surface')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-tools-dock')), findsOneWidget);

    final qualityCategory = find.byKey(
      const ValueKey('editor-tool-category-quality'),
    );
    await Scrollable.ensureVisible(tester.element(qualityCategory));
    await tester.pumpAndSettle();
    expect(qualityCategory.hitTestable(), findsOneWidget);
    await tester.tap(qualityCategory);
    await tester.pumpAndSettle();
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
    final retouchCategory = find.byKey(
      const ValueKey('editor-tool-category-retouch'),
    );
    await Scrollable.ensureVisible(tester.element(retouchCategory));
    await tester.pumpAndSettle();
    await tester.tap(retouchCategory);
    await tester.pumpAndSettle();
    final portraitTab = find.byKey(
      const ValueKey('editor-adjustment-tab-naturalBeautification'),
    );
    await tester.ensureVisible(portraitTab);
    await tester.pumpAndSettle();
    expect(portraitTab.hitTestable(), findsOneWidget);
    await tester.tap(portraitTab);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-apply-one-tap-natural-beautification')),
      findsOneWidget,
    );
    final faceSlimTab = find.byKey(
      const ValueKey('editor-adjustment-tab-faceSlim'),
    );
    expect(faceSlimTab.hitTestable(), findsOneWidget);
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
    expect(portraitRecipe.textureSmoothing, 50);
    expect(portraitRecipe.skinToneLighting, 50);
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
    expect(tester.widget<Slider>(textureControl).value, closeTo(0.5, 0.01));
    await tester.drag(textureControl, const Offset(90, 0));
    await tester.pumpAndSettle();
    portraitRecipe = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .portraitRecipe;
    expect(portraitRecipe.textureSmoothing, greaterThan(50));
    expect(
      find.byKey(const ValueKey('editor-adjustment-section')),
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
    final bodyTargetSelector = find.byKey(
      const ValueKey('editor-body-target-selector'),
    );
    await tester.dragUntilVisible(
      bodyTargetSelector,
      workspace,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(bodyTargetSelector, findsOneWidget);
    await tester.tap(bodyTargetSelector);
    await tester.pumpAndSettle();
    final secondBodyTarget = find.byKey(const ValueKey('editor-body-target-1'));
    expect(secondBodyTarget, findsOneWidget);
    await tester.tap(secondBodyTarget);
    await tester.pumpAndSettle();
    final bodySlimControl = find.descendant(
      of: find.byKey(const ValueKey('editor-adjustment-bodySlim')),
      matching: find.byType(Slider),
    );
    await tester.dragUntilVisible(
      bodySlimControl,
      workspace,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
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
    final visibleFaceSlimTab = find.byKey(
      const ValueKey('editor-adjustment-tab-faceSlim'),
    );
    await tester.ensureVisible(visibleFaceSlimTab);
    await tester.pumpAndSettle();
    expect(visibleFaceSlimTab.hitTestable(), findsOneWidget);
    await tester.tap(visibleFaceSlimTab);
    await tester.pumpAndSettle();
    final faceTargetSelector = find.byKey(
      const ValueKey('editor-face-target-selector'),
    );
    await tester.dragUntilVisible(
      faceTargetSelector,
      workspace,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(faceTargetSelector, findsOneWidget);
    final faceSlimControl = find.descendant(
      of: find.byKey(const ValueKey('editor-adjustment-faceSlim')),
      matching: find.byType(Slider),
    );
    await tester.dragUntilVisible(
      faceSlimControl,
      workspace,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(faceSlimControl, findsOneWidget);
    expect(faceSlimControl.hitTestable(), findsOneWidget);
    expect(tester.widget<Slider>(faceSlimControl).max, 0.5);
    await tester.drag(faceSlimControl, const Offset(90, 0));
    await tester.pumpAndSettle();
    final secondFaceTarget = find.byKey(
      const ValueKey('editor-face-slim-target-1'),
    );
    await tester.tap(faceTargetSelector);
    await tester.pumpAndSettle();
    expect(secondFaceTarget, findsOneWidget);
    await tester.tap(secondFaceTarget);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      faceSlimControl,
      workspace,
      const Offset(0, -180),
    );
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
    final colorCategory = find.byKey(
      const ValueKey('editor-tool-category-color'),
    );
    await Scrollable.ensureVisible(tester.element(colorCategory));
    await tester.pumpAndSettle();
    await tester.tap(colorCategory);
    await tester.pumpAndSettle();
    final exposureTab = find.byKey(
      const ValueKey('editor-adjustment-tab-exposure'),
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

    final compositionCategory = find.byKey(
      const ValueKey('editor-tool-category-composition'),
    );
    await tester.dragUntilVisible(
      compositionCategory,
      workspace,
      const Offset(0, 280),
    );
    await tester.pumpAndSettle();
    expect(compositionCategory.hitTestable(), findsOneWidget);
    await tester.tap(compositionCategory);
    await tester.pumpAndSettle();
    final composition = find.byKey(const ValueKey('editor-composition-tools'));
    expect(composition, findsOneWidget);
    final freeCrop = find.byKey(const ValueKey('editor-free-crop'));
    await tester.ensureVisible(freeCrop);
    await tester.tap(freeCrop);
    await tester.pumpAndSettle();
    final cropCanvas = find.byKey(const ValueKey('free-crop-canvas'));
    expect(cropCanvas, findsOneWidget);
    await tester.drag(cropCanvas, const Offset(36, 28));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('free-crop-apply')));
    await tester.pumpAndSettle();
    final crop = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .crop;
    expect(crop.left, greaterThan(0));
    expect(crop.top, greaterThan(0));
    final filterCategory = find.byKey(
      const ValueKey('editor-tool-category-filters'),
    );
    await tester.dragUntilVisible(
      filterCategory,
      workspace,
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(filterCategory.hitTestable(), findsOneWidget);
    await tester.tap(filterCategory);
    await tester.pumpAndSettle();
    final filterTools = find.byKey(const ValueKey('editor-filter-hsl-tools'));
    expect(filterTools, findsOneWidget);
    final cinematicFilter = find.byKey(
      const ValueKey('editor-filter-cinematic'),
    );
    await tester.ensureVisible(cinematicFilter);
    expect(cinematicFilter.hitTestable(), findsOneWidget);
    await tester.tap(cinematicFilter);
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())!
          .effectiveRecipeFor(importedPhoto.id)
          .basicEditingRecipe
          .filter
          .name,
      'cinematic',
    );
    await tester.tap(find.byKey(const ValueKey('editor-hsl-blue')));
    await tester.pumpAndSettle();
    final blueSaturation = find.descendant(
      of: find.byKey(const ValueKey('editor-hsl-blue-saturation')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(blueSaturation);
    await tester.pumpAndSettle();
    expect(blueSaturation.hitTestable(), findsOneWidget);
    await tester.drag(blueSaturation, const Offset(70, 0));
    await tester.pumpAndSettle();
    final basicEditing = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .basicEditingRecipe;
    expect(basicEditing.filter.name, 'cinematic');
    expect(basicEditing.filterStrength, 70);
    expect(basicEditing.hsl.values.single.saturation, greaterThan(0));

    final semanticCategory = find.byKey(
      const ValueKey('editor-tool-category-semantic'),
    );
    await Scrollable.ensureVisible(tester.element(semanticCategory));
    await tester.pumpAndSettle();
    await tester.tap(semanticCategory);
    await tester.pumpAndSettle();
    final whiteBackground = find.byKey(
      const ValueKey('editor-background-white'),
    );
    await Scrollable.ensureVisible(tester.element(whiteBackground));
    await tester.pumpAndSettle();
    await tester.tap(whiteBackground);
    await tester.pumpAndSettle();
    final localExposureSlider = find.descendant(
      of: find.byKey(const ValueKey('editor-local-exposure')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(localExposureSlider);
    await tester.pumpAndSettle();
    await tester.drag(localExposureSlider, const Offset(55, 0));
    await tester.pumpAndSettle();
    final localBrush = find.byKey(
      const ValueKey('editor-open-local-adjustment-brush'),
    );
    await tester.ensureVisible(localBrush);
    await tester.pumpAndSettle();
    await tester.tap(localBrush);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('local-mask-canvas')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('local-mask-apply')));
    await tester.pumpAndSettle();
    final semanticEditing = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .semanticEditingRecipe;
    expect(semanticEditing.background, BackgroundTreatment.white);
    expect(semanticEditing.localExposure, greaterThan(0));
    expect(semanticEditing.localAdjustmentStrokes, isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('editor-tools-done')));
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const ValueKey('editor-batch-export'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-save-options')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-current')));
    await tester.pump();
    // Vision/Core Image cold starts on the iOS simulator can exceed 30 seconds
    // once portrait, semantic masks, filters, and geometry are combined.
    for (
      var attempt = 0;
      attempt < 900 && exporter.results.isEmpty && exporter.errors.isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(exporter.photoIds, ['ios-runtime-photo']);
    expect(exporter.errors, isEmpty);
    expect(exporter.results, hasLength(1));
    expect(exporter.options.single.size, PhotoExportSize.longEdge);
    expect(exporter.options.single.longEdgePixels, 2048);
    expect(exporter.options.single.quality, PhotoExportQuality.standard);
    expect(exporter.recipes.single.portraitStrength, 0);
    expect(
      exporter.recipes.single.portraitRecipe.textureSmoothing,
      greaterThan(50),
    );
    expect(exporter.recipes.single.portraitRecipe.skinToneLighting, 50);
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
    final saveSuccess = find.byKey(const ValueKey('editor-save-success'));
    for (
      var attempt = 0;
      attempt < 200 && saveSuccess.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(saveSuccess, findsOneWidget);
    expect(find.text('1 张照片已保存到相册'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('editor-save-success')), findsOneWidget);
    expect(find.text('1 张照片已保存到相册'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-finish')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-start-editing')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(restoredPreviewRenderer.disposeCount, 0);
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

      expect(store.project?.photos, hasLength(6));
      expect(
        store.project?.analysisStates.values,
        everyElement(PhotoAnalysisState.fallback),
      );
      expect(
        find.byKey(const ValueKey('recommendation-texturedStyle')),
        findsOneWidget,
      );
      var workspace = find.byKey(const ValueKey('photo-workspace-scroll'));
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

      await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
      await tester.pumpAndSettle();
      workspace = find.byKey(const ValueKey('photo-workspace-scroll'));
      final groupIntensity = find.byKey(
        const ValueKey('editor-group-style-intensity'),
      );
      await tester.fling(workspace, const Offset(0, 1000), 2000);
      await tester.pumpAndSettle();
      await tester.ensureVisible(groupIntensity);
      await tester.drag(groupIntensity, const Offset(-70, 0));
      await tester.pumpAndSettle();
      expect(store.project!.sharedStyle.intensity, lessThan(1));

      final groupFilters = find.byKey(
        const ValueKey('editor-tool-category-filters'),
      );
      await tester.ensureVisible(groupFilters);
      await tester.tap(groupFilters);
      await tester.pumpAndSettle();
      final groupCinematic = find.byKey(
        const ValueKey('editor-filter-cinematic'),
      );
      await tester.ensureVisible(groupCinematic);
      await tester.tap(groupCinematic);
      await tester.pumpAndSettle();
      expect(
        store.project!.sharedStyle.recipe.basicEditingRecipe.filter,
        PhotoFilter.cinematic,
      );
      expect(
        store.project!.photos.map(
          (photo) => store.project!
              .effectiveRecipeFor(photo.id)
              .basicEditingRecipe
              .filter,
        ),
        everyElement(PhotoFilter.cinematic),
      );
      final groupColor = find.byKey(
        const ValueKey('editor-tool-category-color'),
      );
      await Scrollable.ensureVisible(tester.element(groupColor));
      await tester.pumpAndSettle();
      expect(groupColor.hitTestable(), findsOneWidget);
      await tester.tap(groupColor);
      await tester.pumpAndSettle();

      final exposureSlider = find.byKey(
        const ValueKey('editor-adjustment-exposure'),
      );
      await tester.dragUntilVisible(
        exposureSlider,
        workspace,
        const Offset(0, -260),
      );
      await Scrollable.ensureVisible(
        tester.element(exposureSlider),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      expect(exposureSlider.hitTestable(), findsOneWidget);
      final exposureControl = find.descendant(
        of: exposureSlider,
        matching: find.byType(Slider),
      );
      final exposureBefore = store.project!.sharedStyle.recipe.exposure;
      await tester.drag(exposureControl, const Offset(70, 0));
      await tester.pumpAndSettle();
      final sharedExposure = store.project!.sharedStyle.recipe.exposure;
      expect(sharedExposure, isNot(exposureBefore));

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
      await tester.fling(
        find.byKey(const ValueKey('editor-swipe-photos')),
        const Offset(-500, 0),
        1200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
      await tester.pumpAndSettle();
      workspace = find.byKey(const ValueKey('photo-workspace-scroll'));
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
      final contrastTab = find.byKey(
        const ValueKey('editor-adjustment-tab-contrast'),
      );
      await tester.ensureVisible(contrastTab);
      await tester.pumpAndSettle();
      await tester.tap(contrastTab);
      await tester.pumpAndSettle();
      final contrastSlider = find.byKey(
        const ValueKey('editor-adjustment-contrast'),
      );
      await tester.ensureVisible(contrastSlider);
      await tester.pumpAndSettle();
      expect(contrastSlider.hitTestable(), findsOneWidget);
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

      await tester.tap(find.byKey(const ValueKey('editor-tools-done')));
      await tester.pumpAndSettle();
      final exportButton = find.byKey(const ValueKey('editor-batch-export'));
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-all')));
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
      expect(
        exporter.recipes.map((recipe) => recipe.basicEditingRecipe.filter),
        everyElement(PhotoFilter.cinematic),
      );
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
  final List<int> maxEdges = [];
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
    maxEdges.add(maxEdge);
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

final class _NativeExportProbe implements ConfigurablePhotoExporter {
  _NativeExportProbe({required this.delegate});

  final PhotoExporter delegate;
  final List<String> photoIds = [];
  final List<EditRecipe> recipes = [];
  final List<ExportedPhoto> results = [];
  final List<Object> errors = [];
  final List<PhotoExportOptions> options = [];

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) => exportWithOptions(
    photo: photo,
    recipe: recipe,
    options: PhotoExportOptions.defaults,
  );

  @override
  Future<ExportedPhoto> exportWithOptions({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required PhotoExportOptions options,
  }) async {
    photoIds.add(photo.id);
    recipes.add(recipe);
    this.options.add(options);
    try {
      final exported = delegate is ConfigurablePhotoExporter
          ? await (delegate as ConfigurablePhotoExporter).exportWithOptions(
              photo: photo,
              recipe: recipe,
              options: options,
            )
          : await delegate.export(photo: photo, recipe: recipe);
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
      faceTargetRegions: const [
        NormalizedTargetRegion(left: 0.12, top: 0.18, right: 0.38, bottom: 0.5),
        NormalizedTargetRegion(left: 0.62, top: 0.18, right: 0.88, bottom: 0.5),
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
      scene: SceneKind.people,
    );
  }
}

final class _FailOnceRecordingExporter implements PhotoExporter {
  _FailOnceRecordingExporter({required this.failOncePhotoId});

  final String failOncePhotoId;
  final List<String> photoIds = [];
  final List<EditRecipe> recipes = [];
  bool _failed = false;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    photoIds.add(photo.id);
    recipes.add(recipe);
    if (photo.id == failOncePhotoId && !_failed) {
      _failed = true;
      throw StateError('injected iOS runtime export failure');
    }
    return ExportedPhoto(assetId: 'export-${photo.id}', width: 2, height: 2);
  }
}
