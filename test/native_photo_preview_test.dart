import 'dart:async';

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

  testWidgets('disposes a late texture created after app suspension', (
    tester,
  ) async {
    final renderer = _DelayedFirstCreatePreviewRenderer();
    await tester.pumpWidget(_previewApp(renderer));
    await tester.pump();
    expect(renderer.createCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    renderer.completeFirstCreate();
    await tester.pumpAndSettle();

    expect(renderer.disposedTextureIds, [1]);
    expect(find.byType(Texture), findsNothing);

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

  testWidgets('uses the requested preview edge and recreates when it changes', (
    tester,
  ) async {
    final renderer = _RecordingPreviewRenderer();
    var maxEdge = 384;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return NativePhotoPreview(
              sourcePath: '/tmp/Yingjian_preview_fixture.jpg',
              recipe: EditRecipe.neutral,
              renderer: renderer,
              maxEdge: maxEdge,
              errorBuilder: (_) => const Text('preview unavailable'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(renderer.maxEdges, [384]);

    rebuild(() => maxEdge = 512);
    await tester.pumpAndSettle();

    expect(renderer.maxEdges, [384, 512]);
    expect(renderer.disposedTextureIds, [1]);
  });

  testWidgets('retries the same failed preview when retryToken changes', (
    tester,
  ) async {
    final renderer = _FailFirstCreatePreviewRenderer();
    var retryToken = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return NativePhotoPreview(
              sourcePath: '/tmp/Yingjian_preview_fixture.jpg',
              recipe: EditRecipe(clarity: 0.1),
              renderer: renderer,
              retryToken: retryToken,
              errorBuilder: (_) => const Text('preview unavailable'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('preview unavailable'), findsOneWidget);
    rebuild(() => retryToken += 1);
    await tester.pumpAndSettle();

    expect(renderer.createCount, 2);
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('a new recipe recovers after one preview update fails', (
    tester,
  ) async {
    final renderer = _FailFirstUpdatePreviewRenderer();
    var recipe = EditRecipe.neutral;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return NativePhotoPreview(
              sourcePath: '/tmp/Yingjian_preview_fixture.jpg',
              recipe: recipe,
              renderer: renderer,
              errorBuilder: (_) => const Text('preview unavailable'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    rebuild(() => recipe = EditRecipe(clarity: 0.1));
    await tester.pumpAndSettle();
    expect(find.text('preview unavailable'), findsOneWidget);

    rebuild(() => recipe = EditRecipe(warmth: 0.1));
    await tester.pumpAndSettle();

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

class _RecordingPreviewRenderer implements PhotoPreviewRenderer {
  int createCount = 0;
  final List<int> disposedTextureIds = [];
  final List<int> maxEdges = [];

  @override
  Future<PhotoPreviewHandle> create({
    required String sourcePath,
    required ImagePipeline pipeline,
    int maxEdge = 2048,
  }) async {
    createCount += 1;
    maxEdges.add(maxEdge);
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

final class _FailFirstCreatePreviewRenderer extends _RecordingPreviewRenderer {
  @override
  Future<PhotoPreviewHandle> create({
    required String sourcePath,
    required ImagePipeline pipeline,
    int maxEdge = 2048,
  }) async {
    if (createCount == 0) {
      createCount += 1;
      throw StateError('fixture create failure');
    }
    return super.create(
      sourcePath: sourcePath,
      pipeline: pipeline,
      maxEdge: maxEdge,
    );
  }
}

final class _DelayedFirstCreatePreviewRenderer
    extends _RecordingPreviewRenderer {
  final Completer<PhotoPreviewHandle> _firstCreate = Completer();

  @override
  Future<PhotoPreviewHandle> create({
    required String sourcePath,
    required ImagePipeline pipeline,
    int maxEdge = 2048,
  }) {
    createCount += 1;
    if (createCount == 1) return _firstCreate.future;
    return Future.value(
      PhotoPreviewHandle(
        textureId: createCount,
        width: 1200,
        height: 800,
        backend: 'recording-native',
      ),
    );
  }

  void completeFirstCreate() {
    _firstCreate.complete(
      const PhotoPreviewHandle(
        textureId: 1,
        width: 1200,
        height: 800,
        backend: 'recording-native',
      ),
    );
  }
}

final class _FailFirstUpdatePreviewRenderer extends _RecordingPreviewRenderer {
  bool _failed = false;

  @override
  Future<void> update({
    required PhotoPreviewHandle handle,
    required ImagePipeline pipeline,
  }) async {
    if (!_failed) {
      _failed = true;
      throw StateError('fixture update failure');
    }
  }
}
