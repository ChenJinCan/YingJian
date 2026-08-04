import 'package:flutter/foundation.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

enum PhotoAnalysisDisposition { ready, safeFallback }

enum AnalysisFallbackReason {
  none,
  incompleteContentIdentity,
  unsupportedInput,
  capabilityUnavailable,
  analysisFailed,
}

enum AnalysisConfidence { unknown, low, medium, high }

enum ExposureCondition { unknown, balanced, underexposed, overexposed }

enum WhiteBalanceCondition { unknown, balanced, warmCast, coolCast }

enum ClarityCondition { unknown, clear, soft, blurred }

enum PortraitApplicability { unavailable, unsafe, applicable }

enum SceneKind { unknown, people, landscape, food, night }

@immutable
class LocalPhotoAnalysis {
  const LocalPhotoAnalysis({
    required this.analysisVersion,
    required this.capabilityVersion,
    required this.contentSha256,
    required this.orientation,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.colorSpace,
    required this.disposition,
    required this.fallbackReason,
    this.confidence = AnalysisConfidence.unknown,
    this.exposure = ExposureCondition.unknown,
    this.whiteBalance = WhiteBalanceCondition.unknown,
    this.clarity = ClarityCondition.unknown,
    this.portrait = PortraitApplicability.unavailable,
    this.scene = SceneKind.unknown,
  });

  final String analysisVersion;
  final String capabilityVersion;
  final String contentSha256;
  final int orientation;
  final int pixelWidth;
  final int pixelHeight;
  final PhotoColorSpace colorSpace;
  final PhotoAnalysisDisposition disposition;
  final AnalysisFallbackReason fallbackReason;
  final AnalysisConfidence confidence;
  final ExposureCondition exposure;
  final WhiteBalanceCondition whiteBalance;
  final ClarityCondition clarity;
  final PortraitApplicability portrait;
  final SceneKind scene;

  String get cacheIdentity => [
    analysisVersion,
    capabilityVersion,
    contentSha256,
    orientation,
    pixelWidth,
    pixelHeight,
    colorSpace.name,
  ].join('|');

  bool get usesSafeFallback =>
      disposition == PhotoAnalysisDisposition.safeFallback;

  bool matchesInput(ProjectPhoto photo) =>
      analysisVersion.trim().isNotEmpty &&
      capabilityVersion.trim().isNotEmpty &&
      contentSha256 == photo.contentSha256 &&
      orientation == photo.orientation &&
      pixelWidth == photo.pixelWidth &&
      pixelHeight == photo.pixelHeight &&
      colorSpace == photo.colorSpace &&
      ((disposition == PhotoAnalysisDisposition.ready &&
              fallbackReason == AnalysisFallbackReason.none) ||
          (disposition == PhotoAnalysisDisposition.safeFallback &&
              fallbackReason != AnalysisFallbackReason.none));

  @override
  bool operator ==(Object other) =>
      other is LocalPhotoAnalysis &&
      other.analysisVersion == analysisVersion &&
      other.capabilityVersion == capabilityVersion &&
      other.contentSha256 == contentSha256 &&
      other.orientation == orientation &&
      other.pixelWidth == pixelWidth &&
      other.pixelHeight == pixelHeight &&
      other.colorSpace == colorSpace &&
      other.disposition == disposition &&
      other.fallbackReason == fallbackReason &&
      other.confidence == confidence &&
      other.exposure == exposure &&
      other.whiteBalance == whiteBalance &&
      other.clarity == clarity &&
      other.portrait == portrait &&
      other.scene == scene;

  @override
  int get hashCode => Object.hash(
    analysisVersion,
    capabilityVersion,
    contentSha256,
    orientation,
    pixelWidth,
    pixelHeight,
    colorSpace,
    disposition,
    fallbackReason,
    confidence,
    exposure,
    whiteBalance,
    clarity,
    portrait,
    scene,
  );
}

abstract interface class PhotoAnalyzer {
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo);
}

/// Production-safe baseline until a fixed and quality-gated native analyzer is
/// available. It never reads or uploads image bytes and explicitly reports a
/// fallback instead of inventing pixel observations from metadata.
final class MetadataSafePhotoAnalyzer implements PhotoAnalyzer {
  const MetadataSafePhotoAnalyzer({
    this.analysisVersion = 'metadata-safe-v1',
    this.capabilityVersion = 'metadata-only',
  });

  final String analysisVersion;
  final String capabilityVersion;

  @override
  Future<LocalPhotoAnalysis> analyze(ProjectPhoto photo) async {
    final hasIdentity = RegExp(r'^[a-f0-9]{64}$').hasMatch(photo.contentSha256);
    final supported = photo.supportState == PhotoSupportState.supported;
    final reason = !supported
        ? AnalysisFallbackReason.unsupportedInput
        : !hasIdentity
        ? AnalysisFallbackReason.incompleteContentIdentity
        : AnalysisFallbackReason.capabilityUnavailable;
    return LocalPhotoAnalysis(
      analysisVersion: analysisVersion,
      capabilityVersion: capabilityVersion,
      contentSha256: photo.contentSha256,
      orientation: photo.orientation,
      pixelWidth: photo.pixelWidth,
      pixelHeight: photo.pixelHeight,
      colorSpace: photo.colorSpace,
      disposition: PhotoAnalysisDisposition.safeFallback,
      fallbackReason: reason,
    );
  }
}
