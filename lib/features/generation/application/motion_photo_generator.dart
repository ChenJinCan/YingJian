import 'package:flutter/foundation.dart';

enum MotionPhotoEffect { subtle, cameraPush, lightFlow }

extension MotionPhotoEffectId on MotionPhotoEffect {
  String get id => switch (this) {
    MotionPhotoEffect.subtle => 'subtle',
    MotionPhotoEffect.cameraPush => 'cameraPush',
    MotionPhotoEffect.lightFlow => 'lightFlow',
  };
}

abstract interface class MotionPhotoGenerator {
  Future<MotionPhotoArtifact> generate({
    required String sourcePath,
    required MotionPhotoEffect effect,
  });
}

@immutable
class MotionPhotoArtifact {
  const MotionPhotoArtifact({
    required this.outputPath,
    required this.contentSha256,
    required this.effect,
    required this.width,
    required this.height,
    required this.duration,
  });

  final String outputPath;
  final String contentSha256;
  final MotionPhotoEffect effect;
  final int width;
  final int height;
  final Duration duration;
}
