import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_exporter.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('yingjian/photo_export');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('exports from the original path without sending image bytes', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return <String, Object>{
            'assetId': 'asset-42',
            'width': 4032,
            'height': 3024,
          };
        });
    final exporter = MethodChannelPhotoExporter();
    const photo = ProjectPhoto(
      id: 'photo-1',
      localPath: '/private/project/original.heic',
      originalName: 'original.heic',
    );

    final exported = await exporter.export(
      photo: photo,
      recipe: EditRecipe(exposure: 0.25),
    );

    expect(receivedCall?.method, 'exportPhoto');
    final arguments = receivedCall?.arguments! as Map<Object?, Object?>;
    expect(arguments['sourcePath'], photo.localPath);
    expect(arguments.containsKey('imageBytes'), isFalse);
    final pipeline = arguments['pipeline']! as Map<Object?, Object?>;
    expect(pipeline['schemaVersion'], 2);
    expect(pipeline['workingColorSpace'], 'srgb');
    final adjustments = pipeline['adjustments']! as Map<Object?, Object?>;
    expect(adjustments['exposureEv'], 0.5);
    expect(exported.assetId, 'asset-42');
    expect(exported.width, 4032);
    expect(exported.height, 3024);
  });
}
