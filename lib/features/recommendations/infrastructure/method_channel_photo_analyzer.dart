import 'dart:io';

import 'package:flutter/services.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';

final class MethodChannelPhotoAnalyzer implements PhotoAnalyzer {
  const MethodChannelPhotoAnalyzer({
    this.channel = const MethodChannel('yingjian/photo_analysis'),
    this.fallback = const MetadataSafePhotoAnalyzer(),
    this.nativeAnalysisAvailable,
    this.nativeCapabilityVersion,
  });

  final MethodChannel channel;
  final PhotoAnalyzer fallback;
  final bool? nativeAnalysisAvailable;
  final String? nativeCapabilityVersion;

  bool get _canUseNativeAnalysis =>
      nativeAnalysisAvailable ?? (Platform.isIOS || Platform.isAndroid);

  String get _nativeCapabilityVersion =>
      nativeCapabilityVersion ??
      (Platform.isAndroid
          ? 'android-bitmap-face-v1'
          : 'ios-core-image-vision-v2-portrait-locked');

  @override
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) {
    if (!_canUseNativeAnalysis ||
        photo.supportState != PhotoSupportState.supported ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(photo.contentSha256)) {
      return fallback.identityFor(photo);
    }
    return PhotoAnalysisEngineIdentity(
      analysisVersion: 'local-pixels-v1',
      capabilityVersion: _nativeCapabilityVersion,
    );
  }

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) async {
    if (!_canUseNativeAnalysis ||
        photo.supportState != PhotoSupportState.supported ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(photo.contentSha256)) {
      return fallback.analyze(photo);
    }
    try {
      final raw = await channel.invokeMapMethod<String, Object?>(
        'analyzePhoto',
        {'sourcePath': photo.localPath},
      );
      if (raw == null) return fallback.analyze(photo);
      final analysis = LocalPhotoAnalysis(
        analysisVersion: _requiredString(raw, 'analysisVersion'),
        capabilityVersion: _requiredString(raw, 'capabilityVersion'),
        contentSha256: photo.contentSha256,
        orientation: photo.orientation,
        pixelWidth: photo.pixelWidth,
        pixelHeight: photo.pixelHeight,
        colorSpace: photo.colorSpace,
        disposition: PhotoAnalysisDisposition.ready,
        fallbackReason: AnalysisFallbackReason.none,
        confidence: _enum(raw['confidence'], AnalysisConfidence.values),
        exposure: _enum(raw['exposure'], ExposureCondition.values),
        whiteBalance: _enum(raw['whiteBalance'], WhiteBalanceCondition.values),
        clarity: _enum(raw['clarity'], ClarityCondition.values),
        portrait: _enum(raw['portrait'], PortraitApplicability.values),
        scene: _enum(raw['scene'], SceneKind.values),
      );
      return analysis.matchesInput(photo) &&
              identityFor(photo).matches(analysis)
          ? analysis
          : fallback.analyze(photo);
    } on Object {
      return fallback.analyze(photo);
    }
  }

  String _requiredString(Map<String, Object?> raw, String key) {
    final value = raw[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing $key');
    }
    return value;
  }

  T _enum<T extends Enum>(Object? raw, List<T> values) {
    if (raw is! String) throw const FormatException('Invalid category');
    return values.firstWhere(
      (value) => value.name == raw,
      orElse: () => throw FormatException('Unknown category: $raw'),
    );
  }
}
