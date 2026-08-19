import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_meta_op_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('yingjian/photo_preview');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'loads strict per-meta-op capability declarations from the platform',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getMetaOpCapabilities');
            return <String, Object>{
              'platform': 'ios',
              'operations': <Object>[
                <String, Object>{
                  'id': MetaOpIds.exposure,
                  'version': 1,
                  'preview': true,
                  'export': true,
                  'maxTargets': 0,
                  'maxResourceBytes': 0,
                },
              ],
            };
          });

      final capabilities = await MethodChannelMetaOpCapabilities().load();

      expect(capabilities.platform, EditPlatform.ios);
      final exposure = capabilities.supportFor(MetaOpIds.exposure, 1)!;
      expect(exposure.preview, isTrue);
      expect(exposure.export, isTrue);
    },
  );

  test('rejects malformed or duplicate platform declarations', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          final operation = <String, Object>{
            'id': MetaOpIds.exposure,
            'version': 1,
            'preview': true,
            'export': true,
            'maxTargets': 0,
            'maxResourceBytes': 0,
          };
          return <String, Object>{
            'platform': 'ios',
            'operations': <Object>[operation, operation],
          };
        });

    expect(MethodChannelMetaOpCapabilities().load(), throwsFormatException);
  });
}
