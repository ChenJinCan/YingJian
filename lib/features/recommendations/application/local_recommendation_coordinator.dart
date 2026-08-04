import 'package:flutter/foundation.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';
import 'package:yingjian/features/recommendations/domain/recipe_catalog.dart';

typedef AnalysisStateCallback =
    Future<void> Function(String photoId, PhotoAnalysisState state);

@immutable
class RecommendationPreparation {
  const RecommendationPreparation({
    required this.analyses,
    required this.recommendations,
  });

  final Map<String, LocalPhotoAnalysis> analyses;
  final List<LocalRecommendation> recommendations;

  int get fallbackCount =>
      analyses.values.where((analysis) => analysis.usesSafeFallback).length;
}

final class LocalRecommendationCoordinator {
  LocalRecommendationCoordinator({
    required this.analyzer,
    LocalRecommendationEngine? recommendationEngine,
  }) : recommendationEngine =
           recommendationEngine ?? LocalRecommendationEngine();

  final PhotoAnalyzer analyzer;
  final LocalRecommendationEngine recommendationEngine;

  Future<RecommendationPreparation> prepare({
    required List<ProjectPhoto> photos,
    AnalysisStateCallback? onStateChanged,
  }) async {
    final analyses = <String, LocalPhotoAnalysis>{};
    for (final photo in photos) {
      await onStateChanged?.call(photo.id, PhotoAnalysisState.running);
      try {
        final analysis = await analyzer.analyze(photo);
        if (!analysis.matchesInput(photo)) {
          throw StateError('Analyzer returned a stale or invalid result');
        }
        analyses[photo.id] = analysis;
        await onStateChanged?.call(
          photo.id,
          analysis.usesSafeFallback
              ? PhotoAnalysisState.fallback
              : PhotoAnalysisState.ready,
        );
      } on Object {
        analyses[photo.id] = _failedFallback(photo);
        await onStateChanged?.call(photo.id, PhotoAnalysisState.fallback);
      }
    }
    return RecommendationPreparation(
      analyses: Map.unmodifiable(analyses),
      recommendations: recommendationEngine.recommend(
        photos: photos,
        analyses: analyses,
      ),
    );
  }

  LocalPhotoAnalysis _failedFallback(ProjectPhoto photo) => LocalPhotoAnalysis(
    analysisVersion: 'failed-safe-v1',
    capabilityVersion: 'unavailable',
    contentSha256: photo.contentSha256,
    orientation: photo.orientation,
    pixelWidth: photo.pixelWidth,
    pixelHeight: photo.pixelHeight,
    colorSpace: photo.colorSpace,
    disposition: PhotoAnalysisDisposition.safeFallback,
    fallbackReason: AnalysisFallbackReason.analysisFailed,
  );
}
