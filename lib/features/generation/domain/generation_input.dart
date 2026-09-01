import 'package:flutter/foundation.dart';

sealed class GenerationInput {
  const GenerationInput();

  /// Non-sensitive identity persisted with a task for idempotency checks.
  String get identity;
}

enum OldPhotoColorMode { preserve, colorize }

@immutable
final class OldPhotoGenerationInput extends GenerationInput {
  const OldPhotoGenerationInput({required this.colorMode});

  final OldPhotoColorMode colorMode;

  @override
  String get identity => 'old-photo-v1:${colorMode.name}';
}

@immutable
final class StyleRedrawGenerationInput extends GenerationInput {
  StyleRedrawGenerationInput({
    required this.confirmedDefinition,
    required this.definitionFingerprint,
  }) {
    if (confirmedDefinition.trim().isEmpty ||
        confirmedDefinition != confirmedDefinition.trim() ||
        confirmedDefinition.length > 1000) {
      throw ArgumentError.value(
        confirmedDefinition,
        'confirmedDefinition',
        'A confirmed style definition must be 1 to 1000 trimmed characters',
      );
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(definitionFingerprint)) {
      throw ArgumentError.value(
        definitionFingerprint,
        'definitionFingerprint',
        'Style definitions require a lowercase SHA-256 identity',
      );
    }
  }

  /// Sensitive content used only for the confirmed provider request.
  final String confirmedDefinition;
  final String definitionFingerprint;

  @override
  String get identity => 'style-redraw-v1:$definitionFingerprint';
}

@immutable
final class MaskRemovalGenerationInput extends GenerationInput {
  MaskRemovalGenerationInput({
    required this.maskPath,
    required this.maskSha256,
  }) {
    if (maskPath.trim().isEmpty) {
      throw ArgumentError.value(
        maskPath,
        'maskPath',
        'A mask file is required',
      );
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(maskSha256)) {
      throw ArgumentError.value(
        maskSha256,
        'maskSha256',
        'Masks require a lowercase SHA-256 identity',
      );
    }
  }

  final String maskPath;
  final String maskSha256;

  @override
  String get identity => 'mask-removal-v1:$maskSha256';
}
