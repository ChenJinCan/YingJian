import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

import '../test/support/test_services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS runtime completes the production one-photo MVP journey', (
    tester,
  ) async {
    final fixtureDirectory = await Directory.systemTemp.createTemp(
      'yingjian-ios-mvp-',
    );
    addTearDown(() => fixtureDirectory.delete(recursive: true));
    final source = File('${fixtureDirectory.path}/portrait.png');
    await source.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP4z8AAQgbG'
        '////Z2BgAABOCAf03sBqAAAAAElFTkSuQmCC',
      ),
      flush: true,
    );
    final photo = ProjectPhoto(
      id: 'ios-runtime-photo',
      localPath: source.path,
      originalName: 'portrait.png',
    );
    final store = MemoryPhotoProjectStore();
    final exporter = _RecordingExporter();
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

    await tester.tap(find.byKey(const ValueKey('home-start-editing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-page')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor-select-photos')));
    await tester.pumpAndSettle();
    expect(store.project?.photos.map((item) => item.id), ['ios-runtime-photo']);
    expect(find.text('自然干净'), findsOneWidget);

    final useRecommendation = find.byKey(const ValueKey('recommendation-use'));
    await tester.ensureVisible(useRecommendation);
    await tester.pumpAndSettle();
    await tester.tap(useRecommendation);
    await tester.pumpAndSettle();
    expect(store.project?.flowState, PhotoProjectFlowState.editing);

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('editor-batch-export')),
      find.byType(ListView).first,
      const Offset(0, -320),
    );
    await tester.tap(find.byKey(const ValueKey('editor-batch-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-confirm')));
    await tester.pumpAndSettle();

    expect(exporter.photoIds, ['ios-runtime-photo']);
    expect(find.text('已保存 1 张 · 失败 0 张 · 取消 0 张'), findsWidgets);
    expect(
      source.existsSync(),
      isTrue,
      reason: 'The original must stay intact.',
    );
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
      await tester.dragUntilVisible(
        naturalRecommendation,
        workspace,
        const Offset(0, -260),
      );
      await tester.tap(naturalRecommendation);
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

final class _RecordingExporter implements PhotoExporter {
  final List<String> photoIds = [];

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    photoIds.add(photo.id);
    return ExportedPhoto(
      assetId: 'export-${photo.id}',
      width: 2,
      height: 2,
      sharePath: '${Directory.systemTemp.path}/export-${photo.id}.jpg',
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
