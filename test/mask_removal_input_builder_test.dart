import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/content_sha256.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/generation/application/mask_removal_input_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit strokes become an exact-size black and white PNG', () async {
    final output = await Directory.systemTemp.createTemp('yingjian-mask-');
    addTearDown(() => output.delete(recursive: true));
    final builder = MaskRemovalInputBuilder(
      outputDirectoryProvider: () async => output,
    );

    final input = await builder.create(
      pixelWidth: 8,
      pixelHeight: 6,
      strokes: [
        MaskStroke(
          operation: MaskBrushOperation.paint,
          radius: 0.1,
          points: const [NormalizedPoint(0.5, 0.5)],
        ),
      ],
    );

    final file = File(input.maskPath);
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final rgba = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    addTearDown(() {
      frame.image.dispose();
      codec.dispose();
    });
    final pixels = rgba!.buffer.asUint8List();

    expect(frame.image.width, 8);
    expect(frame.image.height, 6);
    expect(input.maskSha256, ContentSha256.ofBytes(bytes));
    expect(input.maskSha256, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(file.uri.pathSegments.last, '${input.maskSha256}.png');
    expect(_rgbColors(pixels), equals({0x000000, 0xffffff}));
    for (var offset = 3; offset < pixels.length; offset += 4) {
      expect(pixels[offset], 255, reason: 'mask pixels must be opaque');
    }
  });

  test('a fully erased draft cannot become a removal input', () async {
    final output = await Directory.systemTemp.createTemp('yingjian-mask-');
    addTearDown(() => output.delete(recursive: true));
    final builder = MaskRemovalInputBuilder(
      outputDirectoryProvider: () async => output,
    );
    const point = NormalizedPoint(0.5, 0.5);

    await expectLater(
      builder.create(
        pixelWidth: 32,
        pixelHeight: 24,
        strokes: [
          MaskStroke(
            operation: MaskBrushOperation.paint,
            radius: 0.1,
            points: [point],
          ),
          MaskStroke(
            operation: MaskBrushOperation.erase,
            radius: 0.1,
            points: [point],
          ),
        ],
      ),
      throwsA(isA<EmptyMaskSelectionException>()),
    );
    expect(output.listSync(), isEmpty);
  });
}

Set<int> _rgbColors(List<int> rgba) {
  final colors = <int>{};
  for (var offset = 0; offset < rgba.length; offset += 4) {
    colors.add(
      (rgba[offset] << 16) | (rgba[offset + 1] << 8) | rgba[offset + 2],
    );
  }
  return colors;
}
