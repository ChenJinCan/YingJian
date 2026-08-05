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
              'capabilityVersion': 'ios-core-image-vision-v4-local-portrait',
              'confidence': 'medium',
              'exposure': 'underexposed',
              'whiteBalance': 'coolCast',
              'clarity': 'clear',
              'portrait': 'applicable',
              'portraitReason': 'none',
              'scene': 'people',
            };
          });

      final result = await const MethodChannelPhotoAnalyzer(
        channel: channel,
        nativeAnalysisAvailable: true,
      ).analyze(photo);

      expect(captured?.method, 'analyzePhoto');
      expect(captured?.arguments, {'sourcePath': photo.localPath});
      expect(captured?.arguments, isNot(contains('bytes')));
      expect(result.usesSafeFallback, isFalse);
      expect(
        result.capabilityVersion,
        'ios-core-image-vision-v4-local-portrait',
      );
      expect(result.exposure.name, 'underexposed');
      expect(result.whiteBalance.name, 'coolCast');
      expect(result.scene.name, 'people');
      expect(result.portrait.name, 'applicable');
      expect(result.portraitReason.name, 'none');
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
      nativeAnalysisAvailable: true,
    ).analyze(photo);

    expect(result.usesSafeFallback, isTrue);
    expect(result.fallbackReason.name, 'capabilityUnavailable');
  });

  test('unknown portrait degradation reason falls back safely', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object>{
            'analysisVersion': 'local-pixels-v1',
            'capabilityVersion': 'ios-core-image-vision-v3-portrait-locked',
            'confidence': 'medium',
            'exposure': 'balanced',
            'whiteBalance': 'balanced',
            'clarity': 'clear',
            'portrait': 'unsafe',
            'portraitReason': 'unexpectedReason',
            'scene': 'people',
          };
        });

    final result = await const MethodChannelPhotoAnalyzer(
      channel: channel,
      nativeAnalysisAvailable: true,
    ).analyze(photo);

    expect(result.usesSafeFallback, isTrue);
    expect(result.fallbackReason.name, 'capabilityUnavailable');
  });

  test(
    'native analysis with an unexpected engine version is rejected',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            return <String, Object>{
              'analysisVersion': 'local-pixels-v0',
              'capabilityVersion': 'ios-core-image-vision-v1',
              'confidence': 'high',
              'exposure': 'underexposed',
              'whiteBalance': 'balanced',
              'clarity': 'clear',
              'portrait': 'applicable',
              'scene': 'people',
            };
          });

      final result = await const MethodChannelPhotoAnalyzer(
        channel: channel,
        nativeAnalysisAvailable: true,
      ).analyze(photo);

      expect(result.usesSafeFallback, isTrue);
      expect(result.analysisVersion, 'metadata-safe-v1');
    },
  );

  test(
    'platforms without native analysis use the declared fallback directly',
    () async {
      var nativeCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            nativeCalls += 1;
            throw StateError('native analysis must not run');
          });
      const analyzer = MethodChannelPhotoAnalyzer(
        channel: channel,
        nativeAnalysisAvailable: false,
      );

      final result = await analyzer.analyze(photo);

      expect(nativeCalls, 0);
      expect(result.usesSafeFallback, isTrue);
      expect(analyzer.identityFor(photo).capabilityVersion, 'metadata-only');
    },
  );

  test('accepts the declared Android local pixel capability', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object>{
            'analysisVersion': 'local-pixels-v1',
            'capabilityVersion': 'android-bitmap-face-v1',
            'confidence': 'medium',
            'exposure': 'balanced',
            'whiteBalance': 'warmCast',
            'clarity': 'soft',
            'portrait': 'unavailable',
            'portraitReason': 'capabilityUnavailable',
            'scene': 'unknown',
          };
        });
    const analyzer = MethodChannelPhotoAnalyzer(
      channel: channel,
      nativeAnalysisAvailable: true,
      nativeCapabilityVersion: 'android-bitmap-face-v1',
    );

    final result = await analyzer.analyze(photo);

    expect(result.usesSafeFallback, isFalse);
    expect(result.capabilityVersion, 'android-bitmap-face-v1');
    expect(result.portraitReason.name, 'capabilityUnavailable');
    expect(analyzer.identityFor(photo).matches(result), isTrue);
  });
}
