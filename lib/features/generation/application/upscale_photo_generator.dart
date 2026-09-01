import 'package:flutter/foundation.dart';

/// A scale selected explicitly by the user.
///
/// This is intentionally a closed set: implementations must not infer a scale
/// from the source photo or silently substitute another one.
enum UpscalePhotoScale {
  twoX(2),
  fourX(4);

  const UpscalePhotoScale(this.factor);

  final int factor;
}

/// Supplier-neutral boundary for producing a larger local photo result.
///
/// The current iOS adapter performs deterministic high-quality resampling. It
/// does not synthesize new AI detail. A future Core ML adapter can implement
/// this same interface without changing the caller's capability contract.
abstract interface class UpscalePhotoGenerator {
  Future<UpscalePhotoArtifact> generate({
    required String sourcePath,
    required UpscalePhotoScale scale,
  });
}

@immutable
class UpscalePhotoArtifact {
  const UpscalePhotoArtifact({
    required this.outputPath,
    required this.contentSha256,
    required this.scale,
    required this.width,
    required this.height,
  });

  final String outputPath;
  final String contentSha256;
  final UpscalePhotoScale scale;
  final int width;
  final int height;
}
