import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';

enum RecommendationReason {
  balancedLocalFallback,
  warmLocalFallback,
  texturedLocalFallback,
  protectsUncertainInput,
  protectsTexture,
  correctsExposure,
  correctsWhiteBalance,
}

@immutable
class RecipeCatalogEntry {
  const RecipeCatalogEntry({
    required this.id,
    required this.family,
    required this.recipe,
    required this.safeForFallback,
  });

  final String id;
  final SharedStyleFamily family;
  final EditRecipe recipe;
  final bool safeForFallback;
}

final class MvpRecipeCatalog {
  const MvpRecipeCatalog._();

  static const version = 'mvp-catalog-v1';

  static final entries = List<RecipeCatalogEntry>.unmodifiable([
    RecipeCatalogEntry(
      id: 'clean-balanced',
      family: SharedStyleFamily.naturalClean,
      recipe: EditRecipe(
        exposure: 0.04,
        highlights: -0.08,
        shadows: 0.08,
        contrast: 0.03,
        saturation: 0.02,
      ),
      safeForFallback: true,
    ),
    RecipeCatalogEntry(
      id: 'clean-airy',
      family: SharedStyleFamily.naturalClean,
      recipe: EditRecipe(
        exposure: 0.10,
        highlights: -0.10,
        shadows: 0.12,
        contrast: -0.04,
        saturation: -0.02,
      ),
      safeForFallback: true,
    ),
    RecipeCatalogEntry(
      id: 'clean-clear',
      family: SharedStyleFamily.naturalClean,
      recipe: EditRecipe(
        highlights: -0.12,
        shadows: 0.06,
        contrast: 0.08,
        clarity: 0.06,
      ),
      safeForFallback: false,
    ),
    RecipeCatalogEntry(
      id: 'clean-soft',
      family: SharedStyleFamily.naturalClean,
      recipe: EditRecipe(
        exposure: 0.05,
        highlights: -0.08,
        shadows: 0.10,
        contrast: -0.06,
        clarity: -0.04,
      ),
      safeForFallback: true,
    ),
    RecipeCatalogEntry(
      id: 'atmosphere-warm',
      family: SharedStyleFamily.atmosphericColor,
      recipe: EditRecipe(
        highlights: -0.10,
        shadows: 0.06,
        warmth: 0.12,
        tint: 0.02,
        saturation: 0.06,
      ),
      safeForFallback: true,
    ),
    RecipeCatalogEntry(
      id: 'atmosphere-cool',
      family: SharedStyleFamily.atmosphericColor,
      recipe: EditRecipe(
        highlights: -0.08,
        shadows: 0.05,
        warmth: -0.12,
        tint: 0.02,
        saturation: 0.03,
      ),
      safeForFallback: true,
    ),
    RecipeCatalogEntry(
      id: 'atmosphere-evening',
      family: SharedStyleFamily.atmosphericColor,
      recipe: EditRecipe(
        exposure: -0.04,
        highlights: -0.15,
        shadows: 0.08,
        warmth: 0.09,
        saturation: 0.08,
      ),
      safeForFallback: false,
    ),
    RecipeCatalogEntry(
      id: 'atmosphere-fresh',
      family: SharedStyleFamily.atmosphericColor,
      recipe: EditRecipe(
        exposure: 0.04,
        shadows: 0.08,
        warmth: -0.05,
        tint: -0.03,
        saturation: 0.07,
      ),
      safeForFallback: true,
    ),
    RecipeCatalogEntry(
      id: 'texture-gentle',
      family: SharedStyleFamily.texturedStyle,
      recipe: EditRecipe(
        highlights: -0.10,
        shadows: 0.05,
        contrast: 0.08,
        saturation: -0.04,
        clarity: 0.08,
      ),
      safeForFallback: true,
    ),
    RecipeCatalogEntry(
      id: 'texture-matte',
      family: SharedStyleFamily.texturedStyle,
      recipe: EditRecipe(
        exposure: 0.03,
        shadows: 0.14,
        contrast: -0.08,
        saturation: -0.10,
        clarity: 0.04,
      ),
      safeForFallback: true,
    ),
    RecipeCatalogEntry(
      id: 'texture-crisp',
      family: SharedStyleFamily.texturedStyle,
      recipe: EditRecipe(
        highlights: -0.12,
        contrast: 0.14,
        saturation: -0.02,
        clarity: 0.14,
      ),
      safeForFallback: false,
    ),
    RecipeCatalogEntry(
      id: 'texture-muted',
      family: SharedStyleFamily.texturedStyle,
      recipe: EditRecipe(
        highlights: -0.08,
        shadows: 0.06,
        contrast: 0.05,
        warmth: 0.04,
        saturation: -0.14,
        clarity: 0.05,
      ),
      safeForFallback: true,
    ),
  ]);
}

@immutable
class LocalRecommendation {
  const LocalRecommendation({
    required this.id,
    required this.catalogVersion,
    required this.family,
    required this.sharedStyle,
    required this.adaptiveCompensations,
    required this.reason,
  });

  final String id;
  final String catalogVersion;
  final SharedStyleFamily family;
  final SharedStyle sharedStyle;
  final Map<String, AdaptiveCompensation> adaptiveCompensations;
  final RecommendationReason reason;
}

final class LocalRecommendationEngine {
  LocalRecommendationEngine({List<RecipeCatalogEntry>? catalog})
    : catalog = List.unmodifiable(catalog ?? MvpRecipeCatalog.entries) {
    _validateCatalog(this.catalog);
  }

  final List<RecipeCatalogEntry> catalog;

  List<LocalRecommendation> recommend({
    required List<ProjectPhoto> photos,
    required Map<String, LocalPhotoAnalysis> analyses,
  }) {
    if (photos.isEmpty) throw ArgumentError.value(photos, 'photos');
    if (!photos.every(
      (photo) =>
          analyses.containsKey(photo.id) &&
          analyses[photo.id]!.matchesInput(photo),
    )) {
      throw ArgumentError.value(
        analyses,
        'analyses',
        'Every photo needs a current stable analysis result',
      );
    }
    final allFallback = analyses.values.every(
      (analysis) => analysis.usesSafeFallback,
    );
    final selected = <RecipeCatalogEntry>[
      _entry(allFallback ? 'clean-balanced' : _naturalId(analyses.values)),
      _entry(allFallback ? 'atmosphere-warm' : _atmosphereId(analyses.values)),
      _entry(allFallback ? 'texture-gentle' : _textureId(analyses.values)),
    ];
    if (allFallback && selected.any((entry) => !entry.safeForFallback)) {
      throw StateError(
        'Fallback recommendations must use safe catalog entries',
      );
    }
    return List.unmodifiable(
      selected.map((entry) {
        final compensations = <String, AdaptiveCompensation>{
          for (final photo in photos)
            photo.id: _compensation(analyses[photo.id]!),
        };
        return LocalRecommendation(
          id: '${MvpRecipeCatalog.version}:${entry.id}',
          catalogVersion: MvpRecipeCatalog.version,
          family: entry.family,
          sharedStyle: SharedStyle(
            recipe: entry.recipe,
            family: entry.family,
            intensity: allFallback ? 0.72 : 1,
          ),
          adaptiveCompensations: Map.unmodifiable(compensations),
          reason: _reason(entry.family, allFallback),
        );
      }),
    );
  }

  RecipeCatalogEntry _entry(String id) =>
      catalog.singleWhere((entry) => entry.id == id);

  String _naturalId(Iterable<LocalPhotoAnalysis> values) =>
      values.any((value) => value.clarity == ClarityCondition.blurred)
      ? 'clean-soft'
      : 'clean-clear';

  String _atmosphereId(Iterable<LocalPhotoAnalysis> values) {
    if (values.any(
      (value) => value.whiteBalance == WhiteBalanceCondition.warmCast,
    )) {
      return 'atmosphere-cool';
    }
    if (values.any(
      (value) => value.whiteBalance == WhiteBalanceCondition.coolCast,
    )) {
      return 'atmosphere-warm';
    }
    return 'atmosphere-fresh';
  }

  String _textureId(Iterable<LocalPhotoAnalysis> values) =>
      values.any(
        (value) =>
            value.clarity == ClarityCondition.soft ||
            value.clarity == ClarityCondition.blurred,
      )
      ? 'texture-muted'
      : 'texture-crisp';

  AdaptiveCompensation _compensation(LocalPhotoAnalysis analysis) {
    final exposure = switch (analysis.exposure) {
      ExposureCondition.underexposed => 0.15,
      ExposureCondition.overexposed => -0.12,
      _ => 0.0,
    };
    final warmth = switch (analysis.whiteBalance) {
      WhiteBalanceCondition.warmCast => -0.08,
      WhiteBalanceCondition.coolCast => 0.08,
      _ => 0.0,
    };
    return AdaptiveCompensation(
      recipe: EditRecipe(exposure: exposure, warmth: warmth),
      source: analysis.usesSafeFallback
          ? AdaptiveCompensationSource.safeFallbackV1
          : AdaptiveCompensationSource.localAnalysisV1,
      safeSharedIntensity:
          analysis.usesSafeFallback ||
              analysis.confidence == AnalysisConfidence.low
          ? 0.72
          : 1,
      skinProtection: analysis.portrait == PortraitApplicability.applicable
          ? 1
          : 0,
    );
  }

  RecommendationReason _reason(SharedStyleFamily family, bool fallback) {
    if (!fallback) {
      return switch (family) {
        SharedStyleFamily.naturalClean => RecommendationReason.correctsExposure,
        SharedStyleFamily.atmosphericColor =>
          RecommendationReason.correctsWhiteBalance,
        SharedStyleFamily.texturedStyle => RecommendationReason.protectsTexture,
        SharedStyleFamily.manual => RecommendationReason.protectsUncertainInput,
      };
    }
    return switch (family) {
      SharedStyleFamily.naturalClean =>
        RecommendationReason.balancedLocalFallback,
      SharedStyleFamily.atmosphericColor =>
        RecommendationReason.warmLocalFallback,
      SharedStyleFamily.texturedStyle =>
        RecommendationReason.texturedLocalFallback,
      SharedStyleFamily.manual => RecommendationReason.protectsUncertainInput,
    };
  }

  static void _validateCatalog(List<RecipeCatalogEntry> catalog) {
    if (catalog.length < 12 || catalog.length > 18) {
      throw ArgumentError.value(
        catalog.length,
        'catalog',
        'The MVP catalog must contain 12–18 entries',
      );
    }
    if (catalog.map((entry) => entry.id).toSet().length != catalog.length) {
      throw ArgumentError.value(
        catalog,
        'catalog',
        'Recipe ids must be unique',
      );
    }
    const requiredFamilies = {
      SharedStyleFamily.naturalClean,
      SharedStyleFamily.atmosphericColor,
      SharedStyleFamily.texturedStyle,
    };
    if (!catalog
        .map((entry) => entry.family)
        .toSet()
        .containsAll(requiredFamilies)) {
      throw ArgumentError.value(
        catalog,
        'catalog',
        'The three MVP recommendation families are required',
      );
    }
  }
}
