import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/infrastructure/method_channel_photo_analyzer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/photo_analysis');
  const photo = ProjectPhoto(
    id: 'photo-1',
    localPath: '/private/project/photo.jpg',
    originalName: 'photo.jpg',
    contentSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    pixelWidth: 4032,
    pixelHeight: 3024,
    colorSpace: PhotoColorSpace.srgb,
    inputFormat: PhotoInputFormat.jpeg,
    supportState: PhotoSupportState.supported,
  );

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'uses bounded native categories without transferring image bytes',
    () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return <String, Object>{
              'analysisVersion': 'local-pixels-v1',
              'capabilityVersion': 'ios-core-image-vision-v1',
              'confidence': 'medium',
              'exposure': 'underexposed',
              'whiteBalance': 'coolCast',
              'clarity': 'clear',
              'portrait': 'unavailable',
              'scene': 'people',
            };
          });

      final result = await const MethodChannelPhotoAnalyzer(
        channel: channel,
      ).analyze(photo);

      expect(captured?.method, 'analyzePhoto');
      expect(captured?.arguments, {'sourcePath': photo.localPath});
      expect(captured?.arguments, isNot(contains('bytes')));
      expect(result.usesSafeFallback, isFalse);
      expect(result.exposure.name, 'underexposed');
      expect(result.whiteBalance.name, 'coolCast');
      expect(result.scene.name, 'people');
      expect(result.matchesInput(photo), isTrue);
    },
  );

  test('invalid or unavailable native analysis falls back safely', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) => throw PlatformException(code: 'analysisUnavailable'),
        );

    final result = await const MethodChannelPhotoAnalyzer(
      channel: channel,
    ).analyze(photo);

    expect(result.usesSafeFallback, isTrue);
    expect(result.fallbackReason.name, 'capabilityUnavailable');
  });
}
