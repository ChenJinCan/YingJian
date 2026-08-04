import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('releases and recreates its texture across app suspension', (
    tester,
  ) async {
    final renderer = _RecordingPreviewRenderer();
    await tester.pumpWidget(_previewApp(renderer));
    await tester.pumpAndSettle();

    expect(renderer.createCount, 1);
    expect(find.byType(Texture), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(renderer.disposedTextureIds, [1]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(renderer.createCount, 2);
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('replaces its texture after a memory-pressure signal', (
    tester,
  ) async {
    final renderer = _RecordingPreviewRenderer();
    await tester.pumpWidget(_previewApp(renderer));
    await tester.pumpAndSettle();

    tester.binding.handleMemoryPressure();
    await tester.pumpAndSettle();

    expect(renderer.disposedTextureIds, [1]);
    expect(renderer.createCount, 2);
    expect(find.byType(Texture), findsOneWidget);
  });
}

Widget _previewApp(PhotoPreviewRenderer renderer) => MaterialApp(
  home: Scaffold(
    body: NativePhotoPreview(
      sourcePath: '/tmp/Yingjian_preview_fixture.jpg',
      recipe: EditRecipe.neutral,
      renderer: renderer,
      errorBuilder: (_) => const Text('preview unavailable'),
    ),
  ),
);

final class _RecordingPreviewRenderer implements PhotoPreviewRenderer {
  int createCount = 0;
  final List<int> disposedTextureIds = [];

  @override
  Future<PhotoPreviewHandle> create({
    required String sourcePath,
    required ImagePipeline pipeline,
    int maxEdge = 2048,
  }) async {
    createCount += 1;
    return PhotoPreviewHandle(
      textureId: createCount,
      width: 1200,
      height: 800,
      backend: 'recording-native',
    );
  }

  @override
  Future<void> dispose(PhotoPreviewHandle handle) async {
    disposedTextureIds.add(handle.textureId);
  }

  @override
  Future<void> update({
    required PhotoPreviewHandle handle,
    required ImagePipeline pipeline,
  }) async {}
}
