import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
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
            'sharePath': '/tmp/Yingjian_42.jpg',
          };
        });
    final exporter = MethodChannelPhotoExporter();
    const photo = ProjectPhoto(
      id: 'photo-1',
      localPath: '/private/project/original.heic',
      originalName: 'original.heic',
    );

    final exported = await exporter.exportWithOptions(
      photo: photo,
      recipe: EditRecipe(exposure: 0.25),
      options: PhotoExportOptions(
        format: PhotoExportFormat.heif,
        size: PhotoExportSize.longEdge,
        longEdgePixels: 2048,
        quality: PhotoExportQuality.standard,
      ),
    );

    expect(receivedCall?.method, 'exportPhoto');
    final arguments = receivedCall?.arguments! as Map<Object?, Object?>;
    expect(arguments['sourcePath'], photo.localPath);
    expect(arguments.containsKey('imageBytes'), isFalse);
    final envelope = arguments['pipeline']! as Map<Object?, Object?>;
    final plan = envelope['renderPlanV1']! as Map<Object?, Object?>;
    final pipeline = plan['backendPayload']! as Map<Object?, Object?>;
    expect(plan['sourceId'], photo.id);
    expect(plan['stateRevision'], 0);
    expect(plan['outputRequirements'], {
      'purpose': 'export',
      'colorSpace': 'srgb',
      'format': 'heif',
      'quality': 'standard',
      'maxEdge': 2048,
    });
    expect(pipeline['schemaVersion'], 11);
    expect(pipeline['targetedPortraitRecipeV1'], isA<Map>());
    expect(arguments['options'], {
      'format': 'heif',
      'size': 'longEdge',
      'longEdgePixels': 2048,
      'quality': 'standard',
      'colorSpace': 'srgb',
    });
    expect(pipeline['workingColorSpace'], 'srgb');
    expect(pipeline['portraitRecipeV2'], isA<Map<Object?, Object?>>());
    expect(pipeline['faceSlimRecipeV1'], isA<Map<Object?, Object?>>());
    expect(pipeline['portraitGeometryRecipeV1'], isA<Map<Object?, Object?>>());
    expect(pipeline['semanticEditingRecipeV2'], isA<Map<Object?, Object?>>());
    expect(
      pipeline['qualityEnhancementRecipeV1'],
      isA<Map<Object?, Object?>>(),
    );
    final adjustments = pipeline['adjustments']! as Map<Object?, Object?>;
    expect(adjustments['exposureEv'], 0.5);
    expect(exported.assetId, 'asset-42');
    expect(exported.width, 4032);
    expect(exported.height, 3024);
    expect(exported.sharePath, '/tmp/Yingjian_42.jpg');
  });
}
