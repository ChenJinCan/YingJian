import 'dart:io';

import 'package:flutter/services.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';

/// A private, canonical media proxy prepared only after the user has confirmed
/// the selected cloud capability, upload, and bounded cost.
///
/// [sourceSha256] and [maskSha256] identify the actual bytes uploaded to the
/// first-party gateway. They deliberately do not replace the immutable source
/// or user-confirmed mask identities stored by the generation job.
final class PreparedGenerationUpload {
  PreparedGenerationUpload({
    required this.sourcePath,
    required this.sourceSha256,
    this.maskPath,
    this.maskSha256,
    this.cleanupToken,
  }) {
    if (sourcePath.trim().isEmpty) {
      throw ArgumentError.value(sourcePath, 'sourcePath');
    }
    _validateSha256(sourceSha256, 'sourceSha256');
    if ((maskPath == null) != (maskSha256 == null)) {
      throw ArgumentError(
        'A prepared mask path and SHA-256 must be returned together',
      );
    }
    if (maskPath case final path?) {
      if (path.trim().isEmpty) throw ArgumentError.value(path, 'maskPath');
      _validateSha256(maskSha256!, 'maskSha256');
    }
    if (cleanupToken != null && cleanupToken!.trim().isEmpty) {
      throw ArgumentError.value(cleanupToken, 'cleanupToken');
    }
  }

  final String sourcePath;
  final String sourceSha256;
  final String? maskPath;
  final String? maskSha256;
  final String? cleanupToken;

  static void _validateSha256(String value, String name) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw ArgumentError.value(value, name, 'A lowercase SHA-256 is required');
    }
  }
}

abstract interface class GenerationUploadPreparer {
  Future<PreparedGenerationUpload> prepare({
    required String clientRequestId,
    required CreationCapability capability,
    required String sourcePath,
    required String sourceSha256,
    String? maskPath,
    String? maskSha256,
  });

  Future<void> cleanup(PreparedGenerationUpload upload);
}

/// Used on platforms without the iOS canonical proxy bridge and by narrow
/// provider tests. The provider still verifies every byte before upload.
final class DirectGenerationUploadPreparer implements GenerationUploadPreparer {
  const DirectGenerationUploadPreparer();

  @override
  Future<PreparedGenerationUpload> prepare({
    required String clientRequestId,
    required CreationCapability capability,
    required String sourcePath,
    required String sourceSha256,
    String? maskPath,
    String? maskSha256,
  }) async => PreparedGenerationUpload(
    sourcePath: sourcePath,
    sourceSha256: sourceSha256,
    maskPath: maskPath,
    maskSha256: maskSha256,
  );

  @override
  Future<void> cleanup(PreparedGenerationUpload upload) async {}
}

final class MethodChannelGenerationUploadPreparer
    implements GenerationUploadPreparer {
  const MethodChannelGenerationUploadPreparer({
    this.channel = const MethodChannel('yingjian/generation_upload'),
  });

  final MethodChannel channel;

  @override
  Future<PreparedGenerationUpload> prepare({
    required String clientRequestId,
    required CreationCapability capability,
    required String sourcePath,
    required String sourceSha256,
    String? maskPath,
    String? maskSha256,
  }) async {
    final raw = await channel
        .invokeMapMethod<String, Object?>('prepareCanonicalUpload', {
          'clientRequestId': clientRequestId,
          'capability': capability.persistedId,
          'sourcePath': sourcePath,
          'sourceSha256': sourceSha256,
          'maskPath': ?maskPath,
          'maskSha256': ?maskSha256,
        });
    if (raw == null) {
      throw const FormatException(
        'The canonical upload bridge returned no result',
      );
    }
    final preparedSourcePath = raw['sourcePath'];
    final preparedSourceSha256 = raw['sourceSha256'];
    final preparedMaskPath = raw['maskPath'];
    final preparedMaskSha256 = raw['maskSha256'];
    final cleanupToken = raw['cleanupToken'];
    if (preparedSourcePath is! String ||
        preparedSourceSha256 is! String ||
        (preparedMaskPath != null && preparedMaskPath is! String) ||
        (preparedMaskSha256 != null && preparedMaskSha256 is! String) ||
        (cleanupToken != null && cleanupToken is! String)) {
      throw const FormatException(
        'The canonical upload bridge returned an invalid result',
      );
    }
    return PreparedGenerationUpload(
      sourcePath: preparedSourcePath,
      sourceSha256: preparedSourceSha256,
      maskPath: preparedMaskPath as String?,
      maskSha256: preparedMaskSha256 as String?,
      cleanupToken: cleanupToken as String?,
    );
  }

  @override
  Future<void> cleanup(PreparedGenerationUpload upload) async {
    final token = upload.cleanupToken;
    if (token == null) return;
    await channel.invokeMethod<void>('cleanupCanonicalUpload', {
      'cleanupToken': token,
    });
  }
}

GenerationUploadPreparer defaultGenerationUploadPreparer() => Platform.isIOS
    ? const MethodChannelGenerationUploadPreparer()
    : const DirectGenerationUploadPreparer();
