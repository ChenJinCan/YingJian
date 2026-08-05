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
