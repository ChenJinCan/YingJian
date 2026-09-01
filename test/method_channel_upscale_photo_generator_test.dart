import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/generation/application/upscale_photo_generator.dart';
import 'package:yingjian/features/generation/infrastructure/method_channel_upscale_photo_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('yingjian/photo_upscale');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'generates only the explicitly requested 4x high-quality scale',
    () async {
      MethodCall? recordedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            recordedCall = call;
            return <String, Object>{
              'outputPath': '/private/results/source-4x.jpg',
              'contentSha256': 'a' * 64,
              'scaleFactor': 4,
              'width': 1600,
              'height': 1200,
            };
          });

      final artifact = await MethodChannelUpscalePhotoGenerator().generate(
        sourcePath: '/private/project/source.heic',
        scale: UpscalePhotoScale.fourX,
      );

      expect(recordedCall?.method, 'generateHighQualityScale');
      expect(recordedCall?.arguments, <String, Object>{
        'sourcePath': '/private/project/source.heic',
        'scaleFactor': 4,
      });
      expect(artifact.outputPath, '/private/results/source-4x.jpg');
      expect(artifact.contentSha256, 'a' * 64);
      expect(artifact.scale, UpscalePhotoScale.fourX);
      expect(artifact.width, 1600);
      expect(artifact.height, 1200);
    },
  );

  test('rejects a result path that could overwrite the source photo', () async {
    const sourcePath = '/private/project/source.heic';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object>{
            'outputPath': sourcePath,
            'contentSha256': 'b' * 64,
            'scaleFactor': 2,
            'width': 800,
            'height': 600,
          };
        });

    await expectLater(
      MethodChannelUpscalePhotoGenerator().generate(
        sourcePath: sourcePath,
        scale: UpscalePhotoScale.twoX,
      ),
      throwsFormatException,
    );
  });

  test('rejects an empty source path before invoking native code', () async {
    var nativeCallCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          nativeCallCount += 1;
          return null;
        });

    await expectLater(
      MethodChannelUpscalePhotoGenerator().generate(
        sourcePath: '',
        scale: UpscalePhotoScale.twoX,
      ),
      throwsArgumentError,
    );
    expect(nativeCallCount, 0);
  });
}
