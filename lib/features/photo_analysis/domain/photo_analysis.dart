import 'package:flutter/foundation.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

enum PhotoAnalysisDisposition { ready, safeFallback }

enum AnalysisFallbackReason {
  none,
  incompleteContentIdentity,
  unsupportedInput,
  capabilityUnavailable,
  analysisFailed,
  cancelled,
}

enum AnalysisConfidence { unknown, low, medium, high }

enum ExposureCondition { unknown, balanced, underexposed, overexposed }

enum WhiteBalanceCondition { unknown, balanced, warmCast, coolCast }

enum ClarityCondition { unknown, clear, soft, blurred }

enum PortraitApplicability { unavailable, unsafe, applicable }

enum PortraitDegradationReason {
  none,
  noFace,
  multipleFaces,
  lowConfidence,
  faceTooSmall,
  landmarksUnavailable,
  backgroundRisk,
  capabilityLocked,
  capabilityUnavailable,
}

enum SceneKind { unknown, people, landscape, food, night }

@immutable
class NormalizedTargetRegion {
  const NormalizedTargetRegion({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(left >= 0 && left <= 1),
       assert(top >= 0 && top <= 1),
       assert(right >= 0 && right <= 1),
       assert(bottom >= 0 && bottom <= 1),
       assert(right > left),
       assert(bottom > top);

  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, double> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory NormalizedTargetRegion.fromJson(Map<String, Object?> json) {
    double coordinate(String key) {
      final value = json[key];
      if (value is! num || !value.isFinite || value < 0 || value > 1) {
        throw FormatException('Invalid normalized target coordinate $key');
      }
      return value.toDouble();
    }

    final region = NormalizedTargetRegion(
      left: coordinate('left'),
      top: coordinate('top'),
      right: coordinate('right'),
      bottom: coordinate('bottom'),
    );
    if (region.right <= region.left || region.bottom <= region.top) {
      throw const FormatException('Invalid normalized target region');
    }
    return region;
  }

  @override
  bool operator ==(Object other) =>
      other is NormalizedTargetRegion &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

@immutable
class PhotoAnalysisEngineIdentity {
  const PhotoAnalysisEngineIdentity({
    required this.analysisVersion,
    required this.capabilityVersion,
  });

  final String analysisVersion;
  final String capabilityVersion;

  bool matches(LocalPhotoAnalysis analysis) =>
      analysis.analysisVersion == analysisVersion &&
      analysis.capabilityVersion == capabilityVersion;
}

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
    PortraitApplicability portrait = PortraitApplicability.unavailable,
    PortraitDegradationReason portraitReason = PortraitDegradationReason.none,
    PortraitApplicability? faceSlim,
    PortraitDegradationReason? faceSlimReason,
    int? faceSlimTargetCount,
    this.faceTargetRegions = const [],
    this.body = PortraitApplicability.unavailable,
    int? bodyTargetCount,
    this.bodyTargetRegions = const [],
    this.scene = SceneKind.unknown,
  }) : assert(
         faceSlimTargetCount == null ||
             (faceSlimTargetCount >= 0 && faceSlimTargetCount <= 3),
       ),
       assert(
         bodyTargetCount == null ||
             (bodyTargetCount >= 0 && bodyTargetCount <= 3),
       ),
       portrait = portrait,
       portraitReason = portraitReason,
       faceSlim = faceSlim ?? portrait,
       faceSlimReason = faceSlimReason ?? portraitReason,
       faceSlimTargetCount =
           faceSlimTargetCount ??
           ((faceSlim ?? portrait) == PortraitApplicability.applicable ? 1 : 0),
       bodyTargetCount =
           bodyTargetCount ??
           (body == PortraitApplicability.applicable ? 1 : 0);

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
  final PortraitDegradationReason portraitReason;
  final PortraitApplicability faceSlim;
  final PortraitDegradationReason faceSlimReason;
  final int faceSlimTargetCount;
  final List<NormalizedTargetRegion> faceTargetRegions;
  final PortraitApplicability body;
  final int bodyTargetCount;
  final List<NormalizedTargetRegion> bodyTargetRegions;
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

  Map<String, Object> toJson() => {
    'analysisVersion': analysisVersion,
    'capabilityVersion': capabilityVersion,
    'contentSha256': contentSha256,
    'orientation': orientation,
    'pixelWidth': pixelWidth,
    'pixelHeight': pixelHeight,
    'colorSpace': colorSpace.name,
    'disposition': disposition.name,
    'fallbackReason': fallbackReason.name,
    'confidence': confidence.name,
    'exposure': exposure.name,
    'whiteBalance': whiteBalance.name,
    'clarity': clarity.name,
    'portrait': portrait.name,
    'portraitReason': portraitReason.name,
    'faceSlim': faceSlim.name,
    'faceSlimReason': faceSlimReason.name,
    'faceSlimTargetCount': faceSlimTargetCount,
    'faceTargetRegions': faceTargetRegions
        .map((region) => region.toJson())
        .toList(growable: false),
    'body': body.name,
    'bodyTargetCount': bodyTargetCount,
    'bodyTargetRegions': bodyTargetRegions
        .map((region) => region.toJson())
        .toList(growable: false),
    'scene': scene.name,
  };

  factory LocalPhotoAnalysis.fromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Missing analysis field $key');
      }
      return value;
    }

    T enumValue<T extends Enum>(String key, List<T> values) {
      final raw = requiredString(key);
      return values.firstWhere(
        (value) => value.name == raw,
        orElse: () => throw FormatException('Unsupported $key: $raw'),
      );
    }

    final faceSlimTargetCount = json['faceSlimTargetCount'];
    if (faceSlimTargetCount != null &&
        (faceSlimTargetCount is! num ||
            faceSlimTargetCount.toInt() != faceSlimTargetCount ||
            faceSlimTargetCount < 0 ||
            faceSlimTargetCount > 3)) {
      throw const FormatException('Invalid faceSlimTargetCount');
    }
    final bodyTargetCount = json['bodyTargetCount'];
    if (bodyTargetCount != null &&
        (bodyTargetCount is! num ||
            bodyTargetCount.toInt() != bodyTargetCount ||
            bodyTargetCount < 0 ||
            bodyTargetCount > 3)) {
      throw const FormatException('Invalid bodyTargetCount');
    }
    List<NormalizedTargetRegion> regions(String key) {
      final raw = json[key];
      if (raw == null) return const [];
      if (raw is! List || raw.length > 3) {
        throw FormatException('Invalid $key');
      }
      return List.unmodifiable(
        raw.map((value) {
          if (value is! Map) throw FormatException('Invalid $key entry');
          return NormalizedTargetRegion.fromJson(
            Map<String, Object?>.from(value),
          );
        }),
      );
    }

    final faceTargetRegions = regions('faceTargetRegions');
    final bodyTargetRegions = regions('bodyTargetRegions');
    if (bodyTargetRegions.isNotEmpty &&
        bodyTargetCount != null &&
        bodyTargetRegions.length != (bodyTargetCount as num).toInt()) {
      throw const FormatException('Body target regions do not match count');
    }
    return LocalPhotoAnalysis(
      analysisVersion: requiredString('analysisVersion'),
      capabilityVersion: requiredString('capabilityVersion'),
      contentSha256: requiredString('contentSha256'),
      orientation: (json['orientation'] as num).toInt(),
      pixelWidth: (json['pixelWidth'] as num).toInt(),
      pixelHeight: (json['pixelHeight'] as num).toInt(),
      colorSpace: enumValue('colorSpace', PhotoColorSpace.values),
      disposition: enumValue('disposition', PhotoAnalysisDisposition.values),
      fallbackReason: enumValue(
        'fallbackReason',
        AnalysisFallbackReason.values,
      ),
      confidence: enumValue('confidence', AnalysisConfidence.values),
      exposure: enumValue('exposure', ExposureCondition.values),
      whiteBalance: enumValue('whiteBalance', WhiteBalanceCondition.values),
      clarity: enumValue('clarity', ClarityCondition.values),
      portrait: enumValue('portrait', PortraitApplicability.values),
      portraitReason: json['portraitReason'] == null
          ? PortraitDegradationReason.none
          : enumValue('portraitReason', PortraitDegradationReason.values),
      faceSlim: json['faceSlim'] == null
          ? null
          : enumValue('faceSlim', PortraitApplicability.values),
      faceSlimReason: json['faceSlimReason'] == null
          ? null
          : enumValue('faceSlimReason', PortraitDegradationReason.values),
      faceSlimTargetCount: faceSlimTargetCount == null
          ? null
          : (faceSlimTargetCount as num).toInt(),
      faceTargetRegions: faceTargetRegions,
      body: json['body'] == null
          ? PortraitApplicability.unavailable
          : enumValue('body', PortraitApplicability.values),
      bodyTargetCount: bodyTargetCount == null
          ? null
          : (bodyTargetCount as num).toInt(),
      bodyTargetRegions: bodyTargetRegions,
      scene: enumValue('scene', SceneKind.values),
    );
  }

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
      other.portraitReason == portraitReason &&
      other.faceSlim == faceSlim &&
      other.faceSlimReason == faceSlimReason &&
      other.faceSlimTargetCount == faceSlimTargetCount &&
      listEquals(other.faceTargetRegions, faceTargetRegions) &&
      other.body == body &&
      other.bodyTargetCount == bodyTargetCount &&
      listEquals(other.bodyTargetRegions, bodyTargetRegions) &&
      other.scene == scene;

  @override
  int get hashCode => Object.hashAll([
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
    portraitReason,
    faceSlim,
    faceSlimReason,
    faceSlimTargetCount,
    Object.hashAll(faceTargetRegions),
    body,
    bodyTargetCount,
    Object.hashAll(bodyTargetRegions),
    scene,
  ]);
}

abstract interface class PhotoAnalyzer {
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo);

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
  PhotoAnalysisEngineIdentity identityFor(ProjectPhoto photo) =>
      PhotoAnalysisEngineIdentity(
        analysisVersion: analysisVersion,
        capabilityVersion: capabilityVersion,
      );

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
