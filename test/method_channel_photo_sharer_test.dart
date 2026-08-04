import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_sharer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/photo_share');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('shares only bounded local paths and maps completion', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return 'completed';
        });

    final outcome = await const MethodChannelPhotoSharer(
      channel: channel,
    ).share(localPaths: const ['/tmp/Yingjian_a.jpg']);

    expect(outcome, PhotoShareOutcome.completed);
    expect(captured?.method, 'sharePhotos');
    expect(captured?.arguments, {
      'localPaths': ['/tmp/Yingjian_a.jpg'],
    });
  });

  test('maps system cancellation without treating it as failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'canceled');

    expect(
      await const MethodChannelPhotoSharer(
        channel: channel,
      ).share(localPaths: const ['/tmp/Yingjian_a.jpg']),
      PhotoShareOutcome.canceled,
    );
  });

  test(
    'discards bounded temporary paths through the native boundary',
    () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return null;
          });

      await const MethodChannelPhotoSharer(
        channel: channel,
      ).discard(localPaths: const ['/tmp/Yingjian_a.jpg']);

      expect(captured?.method, 'discardPhotos');
      expect(captured?.arguments, {
        'localPaths': ['/tmp/Yingjian_a.jpg'],
      });
    },
  );

  test('rejects empty, oversized, and malformed native outcomes', () async {
    const sharer = MethodChannelPhotoSharer(channel: channel);
    await expectLater(sharer.share(localPaths: const []), throwsArgumentError);
    await expectLater(
      sharer.share(localPaths: List.filled(7, '/tmp/Yingjian_a.jpg')),
      throwsArgumentError,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'unknown');
    await expectLater(
      sharer.share(localPaths: const ['/tmp/Yingjian_a.jpg']),
      throwsFormatException,
    );
  });
}
