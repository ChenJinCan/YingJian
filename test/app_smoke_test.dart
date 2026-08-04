import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

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

    expect(find.text('精修工作台'), findsOneWidget);
    expect(find.text('选择 1–6 张照片'), findsOneWidget);
  });

  testWidgets('follows a persisted English locale', (tester) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'en'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(buildTestApp(settings));

    expect(find.text('Yingjian'), findsOneWidget);
    expect(find.text('Start editing'), findsOneWidget);
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

  testWidgets('user adjusts a photo and exports from its original', (
    tester,
  ) async {
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
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      buildTestApp(
        settings,
        photoImporter: FakePhotoImporter([photo]),
        photoExporter: exporter,
      ),
    );

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();

    expect(find.text('周末人像.png'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('曝光'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(120, 0));
    await tester.pump();
    expect(exporter.exportedRecipe, isNull);

    await tester.dragUntilVisible(
      find.text('重做'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.text('重做'), findsOneWidget);

    await tester.ensureVisible(find.text('原画质导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原画质导出'));
    await tester.pumpAndSettle();

    expect(exporter.exportedPhoto, photo);
    expect(exporter.exportedRecipe?.exposure, greaterThan(0));
    expect(find.text('已保存到系统相册（4032 × 3024）'), findsOneWidget);
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

final class _FailingProjectStore implements PhotoProjectStore {
  @override
  Future<PhotoProject?> loadLatest() async {
    throw const FormatException('corrupt project');
  }

  @override
  Future<void> save(PhotoProject project) async {}
}
