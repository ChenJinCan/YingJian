import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:yingjian/features/editor/domain/content_sha256.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/generation/domain/generation_input.dart';

typedef MaskOutputDirectoryProvider = Future<Directory> Function();

abstract interface class MaskRemovalInputCreator {
  Future<MaskRemovalGenerationInput> create({
    required int pixelWidth,
    required int pixelHeight,
    required List<MaskStroke> strokes,
  });
}

final class EmptyMaskSelectionException implements Exception {
  const EmptyMaskSelectionException();

  @override
  String toString() => 'The user-drawn mask does not select any pixels.';
}

/// Converts only the strokes explicitly drawn by the user into a provider mask.
///
/// The source photo is deliberately not accepted by this class, so this step
/// cannot mutate it or infer a selection from its contents.
final class MaskRemovalInputBuilder implements MaskRemovalInputCreator {
  MaskRemovalInputBuilder({
    MaskOutputDirectoryProvider? outputDirectoryProvider,
  }) : _outputDirectoryProvider =
           outputDirectoryProvider ?? _applicationSupportMaskDirectory;

  final MaskOutputDirectoryProvider _outputDirectoryProvider;

  @override
  Future<MaskRemovalGenerationInput> create({
    required int pixelWidth,
    required int pixelHeight,
    required List<MaskStroke> strokes,
  }) async {
    if (pixelWidth <= 0 || pixelHeight <= 0) {
      throw ArgumentError('Mask pixel dimensions must both be positive.');
    }
    if (strokes.isEmpty) {
      throw const EmptyMaskSelectionException();
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final imageSize = ui.Size(pixelWidth.toDouble(), pixelHeight.toDouble());
    canvas.drawRect(
      ui.Offset.zero & imageSize,
      ui.Paint()
        ..blendMode = ui.BlendMode.src
        ..isAntiAlias = false
        ..color = const ui.Color(0xff000000),
    );
    for (final stroke in strokes) {
      _drawStroke(canvas, imageSize, stroke);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelWidth, pixelHeight);
    picture.dispose();
    try {
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null || !_hasSelectedPixel(raw.buffer.asUint8List())) {
        throw const EmptyMaskSelectionException();
      }
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) {
        throw StateError('Flutter could not encode the user-drawn mask.');
      }
      final pngBytes = encoded.buffer.asUint8List();
      final sha256 = ContentSha256.ofBytes(pngBytes);
      final outputDirectory = await _outputDirectoryProvider();
      await outputDirectory.create(recursive: true);
      final output = File('${outputDirectory.path}/$sha256.png');
      if (!await output.exists()) {
        final temporary = File(
          '${output.path}.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
        );
        await temporary.writeAsBytes(pngBytes, flush: true);
        try {
          await temporary.rename(output.path);
        } on FileSystemException {
          if (!await output.exists()) rethrow;
          await temporary.delete();
        }
      }
      return MaskRemovalGenerationInput(
        maskPath: output.path,
        maskSha256: sha256,
      );
    } finally {
      image.dispose();
    }
  }

  static Future<Directory> _applicationSupportMaskDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/generation/masks');
  }

  static void _drawStroke(ui.Canvas canvas, ui.Size size, MaskStroke stroke) {
    final offsets = stroke.points
        .map((point) => ui.Offset(point.x * size.width, point.y * size.height))
        .toList(growable: false);
    final paint = ui.Paint()
      ..blendMode = ui.BlendMode.src
      ..isAntiAlias = false
      ..color = stroke.operation == MaskBrushOperation.paint
          ? const ui.Color(0xffffffff)
          : const ui.Color(0xff000000)
      ..strokeWidth = max(2, stroke.radius * min(size.width, size.height) * 2)
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..style = ui.PaintingStyle.stroke;
    if (offsets.length == 1) {
      canvas.drawCircle(
        offsets.single,
        paint.strokeWidth / 2,
        paint..style = ui.PaintingStyle.fill,
      );
      return;
    }
    final path = ui.Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final point in offsets.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  static bool _hasSelectedPixel(Uint8List rgba) {
    for (var offset = 0; offset < rgba.length; offset += 4) {
      if (rgba[offset] == 255 &&
          rgba[offset + 1] == 255 &&
          rgba[offset + 2] == 255 &&
          rgba[offset + 3] == 255) {
        return true;
      }
    }
    return false;
  }
}
