import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/project/infrastructure/app_owned_photo_importer.dart';
import 'package:yingjian/features/project/infrastructure/method_channel_photo_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/photo_picker');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('selects original file representations without image bytes', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return <Map<String, Object>>[
            <String, Object>{
              'path': '/private/tmp/yingjian-picker/photo-1.heic',
              'name': 'photo-1.heic',
            },
          ];
        });

    final photos = await const MethodChannelPhotoSource(
      channel: channel,
    ).pickPhotos(limit: 6);

    expect(captured?.method, 'pickPhotos');
    expect(captured?.arguments, <String, Object>{'limit': 6});
    expect(captured?.arguments, isNot(contains('bytes')));
    expect(photos.single.path, '/private/tmp/yingjian-picker/photo-1.heic');
    expect(photos.single.name, 'photo-1.heic');
  });

  test('releases only picker-owned temporary files after import', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return null;
        });
    const source = MethodChannelPhotoSource(channel: channel);

    await source.releasePhotos(const <SelectedPhoto>[
      SelectedPhoto(
        path: '/private/tmp/yingjian-photo-picker/request/photo-1.jpg',
        name: 'photo-1.jpg',
      ),
    ]);

    expect(captured?.method, 'discardPhotos');
    expect(captured?.arguments, <String, Object>{
      'paths': <String>[
        '/private/tmp/yingjian-photo-picker/request/photo-1.jpg',
      ],
    });
  });

  test('bounds a photo picker call that never returns', () async {
    final pending = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => pending.future);
    const source = MethodChannelPhotoSource(
      channel: channel,
      selectionTimeout: Duration(milliseconds: 10),
    );

    await expectLater(
      source.pickPhotos(limit: 6),
      throwsA(isA<TimeoutException>()),
    );
  });
}
