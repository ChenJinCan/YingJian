import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';
import 'package:yingjian/features/generation/infrastructure/method_channel_generated_media_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('yingjian/generated_media_actions');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('saves a generated static image with its exact media kind', () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recordedCall = call;
          return <String, Object>{'assetId': 'photo-asset-id'};
        });

    final assetId = await const MethodChannelGeneratedMediaActions(
      channel: channel,
    ).saveToPhotoLibrary(_image);

    expect(recordedCall?.method, 'saveToPhotoLibrary');
    expect(recordedCall?.arguments, <String, Object>{
      'path': '/private/results/upscale.jpg',
      'kind': 'image',
    });
    expect(assetId, 'photo-asset-id');
  });

  test('saves a generated MP4 as motion media', () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recordedCall = call;
          return <String, Object>{'assetId': 'video-asset-id'};
        });

    final assetId = await const MethodChannelGeneratedMediaActions(
      channel: channel,
    ).saveToPhotoLibrary(_motion);

    expect(recordedCall?.arguments, <String, Object>{
      'path': '/private/results/subtle.mp4',
      'kind': 'imageMotion',
    });
    expect(assetId, 'video-asset-id');
  });

  test('previews only an explicitly tapped generated MP4', () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recordedCall = call;
          return null;
        });

    await const MethodChannelGeneratedMediaActions(
      channel: channel,
    ).previewMotion(_motion);

    expect(recordedCall?.method, 'previewMotion');
    expect(recordedCall?.arguments, <String, Object>{
      'path': '/private/results/subtle.mp4',
      'kind': 'imageMotion',
    });
  });

  test(
    'rejects mismatched kinds and extensions before native invocation',
    () async {
      var invocations = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            invocations += 1;
            return null;
          });
      const actions = MethodChannelGeneratedMediaActions(channel: channel);

      await expectLater(actions.previewMotion(_image), throwsArgumentError);
      await expectLater(
        actions.saveToPhotoLibrary(
          _media(kind: GeneratedMediaKind.image, path: '/private/result.mp4'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        actions.saveToPhotoLibrary(
          _media(
            kind: GeneratedMediaKind.imageMotion,
            path: '/private/result.jpg',
          ),
        ),
        throwsArgumentError,
      );
      expect(invocations, 0);
    },
  );

  test('rejects a malformed native save result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => <String, Object>{});

    await expectLater(
      const MethodChannelGeneratedMediaActions(
        channel: channel,
      ).saveToPhotoLibrary(_image),
      throwsFormatException,
    );
  });
}

final _image = _media(
  kind: GeneratedMediaKind.image,
  path: '/private/results/upscale.jpg',
);

final _motion = _media(
  kind: GeneratedMediaKind.imageMotion,
  path: '/private/results/subtle.mp4',
);

GeneratedMedia _media({
  required GeneratedMediaKind kind,
  required String path,
}) => GeneratedMedia(
  id: 'result-id',
  kind: kind,
  localPath: path,
  contentSha256: 'a' * 64,
  width: 720,
  height: 960,
  duration: kind == GeneratedMediaKind.imageMotion
      ? const Duration(seconds: 2)
      : null,
);
