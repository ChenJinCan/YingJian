import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_exporter.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('yingjian/photo_export');
  const shareChannel = MethodChannel('yingjian/photo_share');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
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
    expect(pipeline['schemaVersion'], 12);
    expect(pipeline['targetedPortraitRecipeV1'], isA<Map>());
    expect(pipeline['directionalLightingRecipeV1'], isA<Map>());
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

  test('publishes the native photo-library write stage', () async {
    final exporter = MethodChannelPhotoExporter();
    expect(exporter.stage.value, PhotoExportStage.preparing);

    final handled = Completer<void>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('exportStage', {'stage': 'savingToPhotoLibrary'}),
          ),
          (_) => handled.complete(),
        );
    await handled.future;

    expect(exporter.stage.value, PhotoExportStage.savingToPhotoLibrary);
  });

  test(
    'prepares a canonical share result without requesting a photo save',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            receivedCall = call;
            return <String, Object>{
              'requestId': 'prepare-fixture',
              'sharePath': '/tmp/Yingjian_prepare.jpg',
              'width': 3024,
              'height': 4032,
            };
          });
      final exporter = MethodChannelPhotoExporter(
        requestIdFactory: () => 'prepare-fixture',
      );
      const photo = ProjectPhoto(
        id: 'photo-prepare',
        localPath: '/private/project/prepare.heic',
        originalName: 'prepare.heic',
      );

      final preparation = exporter.prepareCanonical(
        photo: photo,
        recipe: EditRecipe(exposure: 0.1),
        editState: EditState.empty,
        editContext: EditContext.ios,
        options: PhotoExportOptions.defaults,
      );
      final prepared = await preparation.result;

      expect(receivedCall?.method, 'prepareSharePhoto');
      final arguments = receivedCall!.arguments! as Map<Object?, Object?>;
      expect(arguments['requestId'], 'prepare-fixture');
      expect(arguments['sourcePath'], photo.localPath);
      expect(arguments.containsKey('imageBytes'), isFalse);
      expect(prepared.requestId, 'prepare-fixture');
      expect(prepared.localPath, '/tmp/Yingjian_prepare.jpg');
      expect(prepared.width, 3024);
      expect(prepared.height, 4032);
    },
  );

  test('cancels only the matching render-only preparation', () async {
    final response = Completer<Object?>();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          if (call.method == 'prepareSharePhoto') return response.future;
          if (call.method == 'cancelPhotoPreparation') {
            response.completeError(PlatformException(code: 'prepareCancelled'));
            return Future<Object?>.value();
          }
          return Future<Object?>.value();
        });
    final exporter = MethodChannelPhotoExporter(
      requestIdFactory: () => 'prepare-cancel',
    );
    const photo = ProjectPhoto(
      id: 'photo-cancel',
      localPath: '/private/project/cancel.jpg',
      originalName: 'cancel.jpg',
    );

    final preparation = exporter.prepareCanonical(
      photo: photo,
      recipe: EditRecipe.neutral,
      editState: EditState.empty,
      editContext: EditContext.ios,
      options: PhotoExportOptions.defaults,
    );
    final cancellation = expectLater(
      preparation.result,
      throwsA(isA<PhotoPreparationCanceled>()),
    );
    await preparation.cancel();

    await cancellation;
    expect(calls.map((call) => call.method), [
      'prepareSharePhoto',
      'cancelPhotoPreparation',
    ]);
    expect(
      (calls.last.arguments! as Map<Object?, Object?>)['requestId'],
      'prepare-cancel',
    );
  });

  test(
    'discards a prepared file that arrives after local cancellation',
    () async {
      final response = Completer<Object?>();
      final exportCalls = <MethodCall>[];
      final shareCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            exportCalls.add(call);
            if (call.method == 'prepareSharePhoto') return response.future;
            return Future<Object?>.value();
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
            shareCalls.add(call);
            return null;
          });
      final exporter = MethodChannelPhotoExporter(
        requestIdFactory: () => 'prepare-late-success',
      );
      const photo = ProjectPhoto(
        id: 'photo-late-success',
        localPath: '/private/project/late-success.jpg',
        originalName: 'late-success.jpg',
      );

      final preparation = exporter.prepareCanonical(
        photo: photo,
        recipe: EditRecipe.neutral,
        editState: EditState.empty,
        editContext: EditContext.ios,
        options: PhotoExportOptions.defaults,
      );
      final cancellation = expectLater(
        preparation.result,
        throwsA(isA<PhotoPreparationCanceled>()),
      );

      await preparation.cancel();
      expect(response.isCompleted, isFalse);
      response.complete(const <String, Object>{
        'requestId': 'prepare-late-success',
        'sharePath': '/tmp/Yingjian_late-success.jpg',
        'width': 3024,
        'height': 4032,
      });

      await cancellation;
      expect(exportCalls.map((call) => call.method), [
        'prepareSharePhoto',
        'cancelPhotoPreparation',
      ]);
      expect(shareCalls, hasLength(1));
      expect(shareCalls.single.method, 'discardPhotos');
      expect(shareCalls.single.arguments, <String, Object>{
        'localPaths': <String>['/tmp/Yingjian_late-success.jpg'],
      });
    },
  );

  test('local cancellation overrides a late platform failure', () async {
    final response = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          if (call.method == 'prepareSharePhoto') return response.future;
          return Future<Object?>.value();
        });
    final exporter = MethodChannelPhotoExporter(
      requestIdFactory: () => 'prepare-late-failure',
    );
    const photo = ProjectPhoto(
      id: 'photo-late-failure',
      localPath: '/private/project/late-failure.jpg',
      originalName: 'late-failure.jpg',
    );

    final preparation = exporter.prepareCanonical(
      photo: photo,
      recipe: EditRecipe.neutral,
      editState: EditState.empty,
      editContext: EditContext.ios,
      options: PhotoExportOptions.defaults,
    );
    final cancellation = expectLater(
      preparation.result,
      throwsA(isA<PhotoPreparationCanceled>()),
    );

    await preparation.cancel();
    response.completeError(PlatformException(code: 'renderFailed'));

    await cancellation;
  });
}
