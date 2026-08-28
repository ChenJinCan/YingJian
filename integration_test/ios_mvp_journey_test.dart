import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/content_sha256.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';
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

      await tester.tap(find.byKey(const ValueKey('settings-export-quality')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('节省空间'));
      await tester.pumpAndSettle();
      expect(settings.exportQuality, AppExportQuality.compact);

      await tester.tap(find.byKey(const ValueKey('settings-legal')));
      await tester.pumpAndSettle();
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

      await tester.tap(find.byKey(const ValueKey('settings-legal')));
      await tester.pumpAndSettle();
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
    final sourceBytes = await _createPngFixtureBytes();
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
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-start-editing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-recommendation-stage')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('recommendation-confirm')));
    await tester.pump();
    for (
      var attempt = 0;
      attempt < 100 &&
          (await store.loadLatest())?.flowState !=
              PhotoProjectFlowState.editing;
      attempt += 1
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final importedProject = await store.loadLatest();
    final importedPhoto = importedProject!.photos.single;
    expect(analyzer.photoIds, ['ios-runtime-photo']);
    expect(
      importedProject.analysisStates[importedPhoto.id],
      PhotoAnalysisState.ready,
    );
    expect(importedPhoto.localPath, isNot(source.path));
    expect(importedPhoto.localPath, startsWith('${projectRoot.path}/media/'));
    expect(importedPhoto.contentSha256, ContentSha256.ofBytes(sourceBytes));
    expect(importedPhoto.pixelWidth, 32);
    expect(importedPhoto.pixelHeight, 32);
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
    expect(
      find.byKey(const ValueKey('editor-recommendation-stage')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('editor-preview-stage')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-bottom-command-bar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('voice-edit-entry')), findsOneWidget);
    for (
      var attempt = 0;
      attempt < 100 && previewRenderer.textureSmoothingStrengths.isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(previewRenderer.textureSmoothingStrengths, contains(0.5));
    expect(previewRenderer.maxEdges, contains(2048));
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
    expect(find.byKey(const ValueKey('voice-compose')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('voice-edit-text-field')),
      '照片亮一点',
    );
    await tester.tap(find.byKey(const ValueKey('voice-edit-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-confirmation')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice-edit-apply-preview')));
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

    await tester.tap(find.byKey(const ValueKey('voice-edit-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('voice-edit-text-field')),
      '皮肤自然一点',
    );
    await tester.tap(find.byKey(const ValueKey('voice-edit-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-edit-apply-preview')));
    await tester.pump(const Duration(milliseconds: 300));
    final aiTargetChoices = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('ai-target-');
    });
    expect(aiTargetChoices, findsNWidgets(2));
    await tester.tap(aiTargetChoices.last);
    await tester.pumpAndSettle();
    final aiProject = (await store.loadLatest())!;
    expect(aiProject.undoHistory.last.source, EditSource.ai);
    expect(aiProject.undoHistory.last.changedAddresses, hasLength(3));
    expect(
      aiProject.undoHistory.last.changedAddresses
          .map((address) => address.targetId)
          .toSet(),
      hasLength(1),
    );

    await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-tools-dock')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-preview-stage')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-scope-menu')), findsNothing);
    final commonTabs = find.descendant(
      of: find.byKey(const ValueKey('editor-adjustment-tabs')),
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('editor-adjustment-tab-');
      }),
    );
    expect(
      (commonTabs.evaluate().first.widget.key! as ValueKey<String>).value,
      'editor-adjustment-tab-textureSmoothing',
    );
    final aiSmoothing = find.byKey(
      const ValueKey('editor-adjustment-textureSmoothing'),
    );
    expect(
      tester
          .widget<Slider>(
            find.descendant(of: aiSmoothing, matching: find.byType(Slider)),
          )
          .value,
      closeTo(0.5, 0.001),
    );
    final exposureBeforeManual = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .exposure;
    await _openManualMetaOp(tester, MetaOpIds.exposure);
    final commonExposure = find.byKey(
      const ValueKey('editor-adjustment-exposure'),
    );
    expect(commonExposure, findsOneWidget);
    await tester.drag(
      find.descendant(of: commonExposure, matching: find.byType(Slider)),
      const Offset(70, 0),
    );
    await tester.pumpAndSettle();
    final exposureAfterManual = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .exposure;
    expect(exposureAfterManual, isNot(exposureBeforeManual));
    expect(
      find.byKey(const ValueKey('editor-reset-current-adjustment')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('editor-reset-current-adjustment')),
    );
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())!.effectiveRecipeFor(importedPhoto.id).exposure,
      exposureBeforeManual,
    );
    await tester.tap(find.byKey(const ValueKey('editor-undo')));
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())!.effectiveRecipeFor(importedPhoto.id).exposure,
      exposureAfterManual,
    );

    final previewSurface = find.byKey(const ValueKey('editor-preview-surface'));
    final editedExposure = previewRenderer.exposureStrengths.last;
    final compareGesture = await tester.startGesture(
      tester.getCenter(previewSurface),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(previewRenderer.exposureStrengths.last, 0);
    await compareGesture.up();
    await tester.pumpAndSettle();
    expect(
      previewRenderer.exposureStrengths.last,
      closeTo(editedExposure, 1e-6),
    );

    await tester.tap(
      find.byKey(const ValueKey('editor-preview-fullscreen')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-fullscreen-preview')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('editor-fullscreen-close')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-tools-dock')), findsOneWidget);

    await _openManualMetaOp(tester, MetaOpIds.noiseReduction);
    final qualityTab = find.byKey(
      const ValueKey('editor-adjustment-tab-qualityImprovement'),
    );
    await tester.ensureVisible(qualityTab);
    await tester.pumpAndSettle();
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

    final workspace = find.byKey(const ValueKey('editor-tools-scroll'));
    await _openManualMetaOp(tester, MetaOpIds.skinSmooth);
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
    var targetedPortraitRecipe = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .targetedPortraitRecipe;
    expect(targetedPortraitRecipe.adjustments, hasLength(2));
    for (final adjustment in targetedPortraitRecipe.adjustments.values) {
      expect(adjustment.textureSmoothing, 50);
      expect(adjustment.skinToneLighting, 50);
      expect(adjustment.blemishReduction, 20);
    }
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
    expect(
      find.byKey(const ValueKey('editor-stable-face-target-selector')),
      findsNothing,
    );
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
    targetedPortraitRecipe = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .targetedPortraitRecipe;
    expect(
      targetedPortraitRecipe.adjustments.values.where(
        (adjustment) => adjustment.textureSmoothing > 50,
      ),
      hasLength(1),
    );
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
    await tester.ensureVisible(faceSlimControl);
    await tester.pumpAndSettle();
    expect(faceSlimControl.hitTestable(), findsOneWidget);
    await tester.drag(faceSlimControl, const Offset(90, 0));
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())!
          .effectiveRecipeFor(importedPhoto.id)
          .faceSlimRecipe
          .targetStrengths,
      everyElement(greaterThan(0)),
    );
    await _openManualMetaOp(tester, MetaOpIds.exposure);
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

    await _openManualMetaOp(tester, MetaOpIds.compositionGeometry);
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
    expect(find.byKey(const ValueKey('free-crop-apply')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('free-crop-close')));
    await tester.pumpAndSettle();
    final crop = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .crop;
    expect(crop.left, greaterThan(0));
    expect(crop.top, greaterThan(0));
    await _openManualMetaOp(tester, MetaOpIds.filter);
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
    await _openManualMetaOp(tester, MetaOpIds.hslBlue);
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

    await _openManualMetaOp(tester, MetaOpIds.semanticAdjustments);
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
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-mask-apply')), findsNothing);
    expect(
      (await store.loadLatest())!
          .effectiveRecipeFor(importedPhoto.id)
          .semanticEditingRecipe
          .localAdjustmentStrokes,
      isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('local-mask-close')));
    await tester.pumpAndSettle();
    final semanticEditing = (await store.loadLatest())!
        .effectiveRecipeFor(importedPhoto.id)
        .semanticEditingRecipe;
    expect(semanticEditing.background, BackgroundTreatment.white);
    expect(semanticEditing.localExposure, greaterThan(0));
    expect(semanticEditing.localAdjustmentStrokes, isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('editor-tools-done')));
    await tester.pumpAndSettle();
    final visualTracksEntry = find.byKey(
      const ValueKey('editor-visual-tracks'),
    );
    await tester.ensureVisible(visualTracksEntry);
    await tester.tap(visualTracksEntry);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visual-tracks-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-tracks-preview')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('visual-tracks-open-era')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('visual-tracks-open-era')));
    await tester.pumpAndSettle();
    final eraBefore = (await store.loadLatest())!.effectiveRecipeFor(
      importedPhoto.id,
    );
    await tester.drag(
      find.byKey(const ValueKey('era-arc-track')),
      const Offset(110, 0),
    );
    await tester.pumpAndSettle();
    final eraAfter = (await store.loadLatest())!.effectiveRecipeFor(
      importedPhoto.id,
    );
    expect(eraAfter, isNot(eraBefore));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('visual-tracks-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('visual-track-lighting-tab')));
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('lighting-overlay-target-0'));
    if (target.evaluate().isNotEmpty) {
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('lighting-arc-track')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('lighting-arc-track')),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    expect(
      (await store.loadLatest())!
          .effectiveRecipeFor(importedPhoto.id)
          .directionalLightingRecipe
          .adjustments,
      isNotEmpty,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);
    final saveButton = find.byKey(const ValueKey('editor-batch-export'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-save-options')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-current')));
    await tester.tap(find.byKey(const ValueKey('save-confirm')));
    await tester.pump();
    // Vision/Core Image cold starts on the iOS simulator can take several
    // minutes once portrait, semantic masks, filters, geometry, and targeted
    // directional lighting are combined. Wait for the real terminal result or
    // error instead of treating an intermediate native render as completion.
    for (
      var attempt = 0;
      attempt < 2400 && exporter.results.isEmpty && exporter.errors.isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(exporter.photoIds, ['ios-runtime-photo']);
    expect(exporter.errors, isEmpty);
    expect(exporter.results, hasLength(1));
    expect(exporter.options.single.size, PhotoExportSize.longEdge);
    expect(exporter.options.single.longEdgePixels, 2048);
    expect(exporter.options.single.quality, PhotoExportQuality.high);
    expect(exporter.recipes.single.portraitStrength, 0);
    final exportedPortrait = exporter.recipes.single.targetedPortraitRecipe;
    expect(exportedPortrait.adjustments, hasLength(2));
    expect(
      exportedPortrait.adjustments.values.where(
        (adjustment) => adjustment.textureSmoothing > 50,
      ),
      hasLength(1),
    );
    expect(
      exportedPortrait.adjustments.values.every(
        (adjustment) => adjustment.skinToneLighting == 50,
      ),
      isTrue,
    );
    expect(
      exportedPortrait.adjustments.values.every(
        (adjustment) => adjustment.blemishReduction == 20,
      ),
      isTrue,
    );
    expect(previewRenderer.backends, contains('ios-core-image'));
    expect(previewRenderer.updateCount, greaterThan(0));
    final exported = exporter.results.single;
    expect(exported.width, inInclusiveRange(1, 32));
    expect(exported.height, inInclusiveRange(1, 32));
    expect(exported.width < 32 || exported.height < 32, isTrue);
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
    expect(find.text('已保存 1 张照片'), findsOneWidget);
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
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-resume-project')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-save-success')), findsOneWidget);
    expect(find.text('已保存 1 张照片'), findsOneWidget);
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
      final sourceBytes = await _createPngFixtureBytes();
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
          metaOpCapabilities: iosMetaOpCapabilities,
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
        store.project?.flowState,
        PhotoProjectFlowState.choosingRecommendation,
      );
      await tester.tap(find.byKey(const ValueKey('recommendation-confirm')));
      await tester.pumpAndSettle();
      expect(store.project?.flowState, PhotoProjectFlowState.editing);
      expect(store.project?.sharedStyle.family, SharedStyleFamily.naturalClean);
      expect(store.project?.adaptiveCompensations, hasLength(6));

      expect(find.byKey(const ValueKey('editor-scope-switch')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('editor-open-tools')));
      await tester.pumpAndSettle();
      var workspace = find.byKey(const ValueKey('editor-tools-scroll'));

      await _openManualMetaOp(tester, MetaOpIds.filter);
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
      await _openManualMetaOp(tester, MetaOpIds.exposure);

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

      expect(find.byKey(const ValueKey('editor-scope-menu')), findsNothing);
      await tester.fling(
        find.byKey(const ValueKey('editor-swipe-photos')),
        const Offset(-500, 0),
        1200,
      );
      await tester.pumpAndSettle();
      workspace = find.byKey(const ValueKey('editor-tools-scroll'));
      for (final category in <String>[
        'composition',
        'color',
        'filters',
        'quality',
        'semantic',
      ]) {
        expect(
          find.byKey(ValueKey('editor-tool-category-$category')),
          findsNothing,
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

      expect(store.project?.photoOverrides, isEmpty);
      expect(store.project?.sharedStyle.recipe.exposure, sharedExposure);
      expect(
        store.project?.effectiveRecipeFor('ios-runtime-photo-1').contrast,
        store.project?.effectiveRecipeFor('ios-runtime-photo-2').contrast,
      );

      await tester.tap(find.byKey(const ValueKey('editor-tools-done')));
      await tester.pumpAndSettle();
      final exportButton = find.byKey(const ValueKey('editor-batch-export'));
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-all')));
      await tester.tap(find.byKey(const ValueKey('save-confirm')));
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
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

Future<List<int>> _createPngFixtureBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 32, 32),
    Paint()..color = const Color(0xFF8B5A72),
  );
  final image = await recorder.endRecording().toImage(32, 32);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
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
  await tester.ensureVisible(result);
  await tester.tap(result);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

final class _NativePreviewProbe implements PhotoPreviewRenderer {
  _NativePreviewProbe({required this.delegate});

  final PhotoPreviewRenderer delegate;
  final List<String> backends = [];
  final List<double> textureSmoothingStrengths = [];
  final List<double> exposureStrengths = [];
  final List<int> maxEdges = [];
  int updateCount = 0;
  int disposeCount = 0;

  @override
  Future<PhotoPreviewHandle> create({
    required String sourcePath,
    required ImagePipeline pipeline,
    int maxEdge = 2048,
  }) async {
    maxEdges.add(maxEdge);
    textureSmoothingStrengths.add(_textureSmoothingStrength(pipeline));
    exposureStrengths.add(_exposureStrength(pipeline));
    final handle = await delegate.create(
      sourcePath: sourcePath,
      pipeline: pipeline,
      maxEdge: maxEdge,
    );
    backends.add(handle.backend);
    return handle;
  }

  @override
  Future<void> update({
    required PhotoPreviewHandle handle,
    required ImagePipeline pipeline,
  }) async {
    await delegate.update(handle: handle, pipeline: pipeline);
    textureSmoothingStrengths.add(_textureSmoothingStrength(pipeline));
    exposureStrengths.add(_exposureStrength(pipeline));
    updateCount += 1;
  }

  @override
  Future<void> dispose(PhotoPreviewHandle handle) async {
    await delegate.dispose(handle);
    disposeCount += 1;
  }

  double _textureSmoothingStrength(ImagePipeline pipeline) {
    final arguments = _backendArguments(pipeline);
    final targeted = arguments['targetedPortraitRecipeV1'];
    if (targeted is Map) {
      final adjustments = targeted['adjustments'];
      if (adjustments is List && adjustments.isNotEmpty) {
        return adjustments
                .map(
                  (entry) =>
                      ((entry as Map)['textureSmoothing']! as num).toDouble(),
                )
                .reduce((left, right) => left > right ? left : right) /
            100;
      }
    }
    final portrait = arguments['portraitRecipeV2']! as Map<String, Object>;
    return (portrait['textureSmoothing']! as num).toDouble() / 100;
  }

  double _exposureStrength(ImagePipeline pipeline) {
    final arguments = _backendArguments(pipeline);
    final adjustments = arguments['adjustments']! as Map<String, Object>;
    return (adjustments['exposureEv']! as num).toDouble() / 2;
  }

  Map<String, Object> _backendArguments(ImagePipeline pipeline) {
    final arguments = pipeline.toPlatformArguments();
    final renderPlan = arguments['renderPlanV1']! as Map<String, Object>;
    return renderPlan['backendPayload']! as Map<String, Object>;
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
