import 'package:flutter/services.dart';
import 'package:yingjian/features/generation/application/upscale_photo_generator.dart';

/// iOS Core Image adapter for deterministic high-quality image scaling.
///
/// Despite the product capability name, this adapter does not claim to create
/// AI-generated detail.
final class MethodChannelUpscalePhotoGenerator
    implements UpscalePhotoGenerator {
  MethodChannelUpscalePhotoGenerator({
    this.channel = const MethodChannel('yingjian/photo_upscale'),
  });

  final MethodChannel channel;

  @override
  Future<UpscalePhotoArtifact> generate({
    required String sourcePath,
    required UpscalePhotoScale scale,
  }) async {
    if (sourcePath.isEmpty) {
      throw ArgumentError.value(sourcePath, 'sourcePath', 'must not be empty');
    }
    final response = await channel.invokeMapMethod<String, Object?>(
      'generateHighQualityScale',
      <String, Object?>{'sourcePath': sourcePath, 'scaleFactor': scale.factor},
    );
    if (response == null) {
      throw const FormatException('Photo upscale returned no result');
    }
    final outputPath = response['outputPath'];
    final contentSha256 = response['contentSha256'];
    final scaleFactor = response['scaleFactor'];
    final width = response['width'];
    final height = response['height'];
    if (outputPath is! String ||
        outputPath.isEmpty ||
        outputPath == sourcePath ||
        contentSha256 is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(contentSha256) ||
        scaleFactor != scale.factor ||
        width is! int ||
        width <= 0 ||
        height is! int ||
        height <= 0) {
      throw const FormatException('Photo upscale returned an invalid result');
    }
    return UpscalePhotoArtifact(
      outputPath: outputPath,
      contentSha256: contentSha256,
      scale: scale,
      width: width,
      height: height,
    );
  }
}
