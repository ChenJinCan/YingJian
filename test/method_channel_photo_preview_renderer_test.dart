import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v1.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_preview_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('yingjian/photo_preview');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('creates, updates, and disposes a path-backed texture', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'createPreview') {
            return <String, Object>{
              'textureId': 73,
              'width': 1600,
              'height': 1200,
              'backend': 'android-gles3',
            };
          }
          return null;
        });
    final renderer = MethodChannelPhotoPreviewRenderer();
    final neutral = ImagePipelineV1.fromRecipe(EditRecipe.neutral);

    final handle = await renderer.create(
      sourcePath: '/private/project/original.heic',
      pipeline: neutral,
    );
    await renderer.update(
      handle: handle,
      pipeline: ImagePipelineV1.fromRecipe(EditRecipe(exposure: 0.5)),
    );
    await renderer.dispose(handle);

    expect(handle.textureId, 73);
    expect(handle.backend, 'android-gles3');
    expect(calls.map((call) => call.method), <String>[
      'createPreview',
      'updatePreview',
      'disposePreview',
    ]);
    final createArguments = calls.first.arguments! as Map<Object?, Object?>;
    expect(createArguments['sourcePath'], '/private/project/original.heic');
    expect(createArguments.containsKey('imageBytes'), isFalse);
    expect(createArguments['maxEdge'], 2048);
  });

  test('rejects malformed native texture metadata', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object>{'textureId': 1, 'width': 0, 'height': 10};
        });

    expect(
      MethodChannelPhotoPreviewRenderer().create(
        sourcePath: '/photo.jpg',
        pipeline: ImagePipelineV1.fromRecipe(EditRecipe.neutral),
      ),
      throwsFormatException,
    );
  });

  test('rejects preview requests outside the frozen proxy budget', () async {
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          invoked = true;
          return null;
        });

    expect(
      MethodChannelPhotoPreviewRenderer().create(
        sourcePath: '/photo.jpg',
        pipeline: ImagePipelineV1.fromRecipe(EditRecipe.neutral),
        maxEdge: 2049,
      ),
      throwsArgumentError,
    );
    expect(invoked, isFalse);
  });

  test('rejects negative native texture identifiers', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object>{
            'textureId': -1,
            'width': 10,
            'height': 10,
            'backend': 'ios-core-image',
          };
        });

    expect(
      MethodChannelPhotoPreviewRenderer().create(
        sourcePath: '/photo.jpg',
        pipeline: ImagePipelineV1.fromRecipe(EditRecipe.neutral),
      ),
      throwsFormatException,
    );
  });
}
