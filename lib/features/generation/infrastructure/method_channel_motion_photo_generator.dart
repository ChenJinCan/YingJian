import 'package:flutter/services.dart';
import 'package:yingjian/features/generation/application/motion_photo_generator.dart';

final class MethodChannelMotionPhotoGenerator implements MotionPhotoGenerator {
  MethodChannelMotionPhotoGenerator({
    this.channel = const MethodChannel('yingjian/motion_photo'),
  });

  final MethodChannel channel;

  @override
  Future<MotionPhotoArtifact> generate({
    required String sourcePath,
    required MotionPhotoEffect effect,
  }) async {
    if (sourcePath.trim().isEmpty) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'A motion photo requires a source file path',
      );
    }
    final response = await channel.invokeMapMethod<String, Object?>(
      'generate',
      <String, Object?>{'sourcePath': sourcePath, 'effectId': effect.id},
    );
    if (response == null) {
      throw const FormatException('Motion photo generation returned no result');
    }
    final outputPath = response['outputPath'];
    final contentSha256 = response['contentSha256'];
    final effectId = response['effectId'];
    final width = response['width'];
    final height = response['height'];
    final durationMilliseconds = response['durationMilliseconds'];
    if (outputPath is! String ||
        outputPath.isEmpty ||
        contentSha256 is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(contentSha256) ||
        effectId != effect.id ||
        width is! int ||
        width <= 0 ||
        height is! int ||
        height <= 0 ||
        durationMilliseconds is! int ||
        durationMilliseconds <= 0) {
      throw const FormatException(
        'Motion photo generation returned an invalid result',
      );
    }
    return MotionPhotoArtifact(
      outputPath: outputPath,
      contentSha256: contentSha256,
      effect: effect,
      width: width,
      height: height,
      duration: Duration(milliseconds: durationMilliseconds),
    );
  }
}
