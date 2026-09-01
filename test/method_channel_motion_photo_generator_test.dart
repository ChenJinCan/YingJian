import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/generation/application/motion_photo_generator.dart';
import 'package:yingjian/features/generation/infrastructure/method_channel_motion_photo_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('yingjian/motion_photo');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('generates only the explicitly selected motion effect', () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recordedCall = call;
          return <String, Object>{
            'outputPath': '/private/results/camera-push.mp4',
            'contentSha256': 'c' * 64,
            'effectId': 'cameraPush',
            'width': 720,
            'height': 960,
            'durationMilliseconds': 2000,
          };
        });
    final generator = MethodChannelMotionPhotoGenerator();

    final artifact = await generator.generate(
      sourcePath: '/private/project/source.heic',
      effect: MotionPhotoEffect.cameraPush,
    );

    expect(recordedCall?.method, 'generate');
    expect(recordedCall?.arguments, <String, Object>{
      'sourcePath': '/private/project/source.heic',
      'effectId': 'cameraPush',
    });
    expect(artifact.outputPath, '/private/results/camera-push.mp4');
    expect(artifact.contentSha256, 'c' * 64);
    expect(artifact.effect, MotionPhotoEffect.cameraPush);
    expect(artifact.width, 720);
    expect(artifact.height, 960);
    expect(artifact.duration, const Duration(seconds: 2));
  });

  test('rejects a native result that substitutes another effect', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object>{
            'outputPath': '/private/results/subtle.mp4',
            'contentSha256': 'd' * 64,
            'effectId': 'subtle',
            'width': 720,
            'height': 960,
            'durationMilliseconds': 2000,
          };
        });

    await expectLater(
      MethodChannelMotionPhotoGenerator().generate(
        sourcePath: '/private/project/source.heic',
        effect: MotionPhotoEffect.cameraPush,
      ),
      throwsFormatException,
    );
  });

  test('rejects an empty source path before invoking native code', () async {
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          invoked = true;
          return null;
        });

    await expectLater(
      MethodChannelMotionPhotoGenerator().generate(
        sourcePath: '  ',
        effect: MotionPhotoEffect.subtle,
      ),
      throwsArgumentError,
    );
    expect(invoked, isFalse);
  });

  test('freezes the three supplier-neutral effect identifiers', () {
    expect(MotionPhotoEffect.values.map((effect) => effect.id), <String>[
      'subtle',
      'cameraPush',
      'lightFlow',
    ]);
  });
}
