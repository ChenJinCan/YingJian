import 'package:flutter/foundation.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/photo_analysis/domain/photo_analysis.dart';

@immutable
class PhotoAnalysisCacheWrite {
  const PhotoAnalysisCacheWrite({
    required this.projectId,
    required this.photoId,
    required this.token,
    required this.analysis,
  });

  final String projectId;
  final String photoId;
  final String token;
  final LocalPhotoAnalysis analysis;
}

abstract interface class PhotoAnalysisCache {
  Future<LocalPhotoAnalysis?> read({
    required String projectId,
    required ProjectPhoto photo,
    required PhotoAnalysisEngineIdentity engineIdentity,
  });

  Future<PhotoAnalysisCacheWrite?> stage({
    required String projectId,
    required String photoId,
    required LocalPhotoAnalysis analysis,
  });

  Future<bool> commit(
    PhotoAnalysisCacheWrite write, {
    required bool Function() canCommit,
  });

  Future<void> discard(PhotoAnalysisCacheWrite write);

  Future<void> clearPhoto({required String projectId, required String photoId});

  Future<void> clearProject(String projectId);
}

final class NoopPhotoAnalysisCache implements PhotoAnalysisCache {
  const NoopPhotoAnalysisCache();

  @override
  Future<LocalPhotoAnalysis?> read({
    required String projectId,
    required ProjectPhoto photo,
    required PhotoAnalysisEngineIdentity engineIdentity,
  }) async => null;

  @override
  Future<PhotoAnalysisCacheWrite?> stage({
    required String projectId,
    required String photoId,
    required LocalPhotoAnalysis analysis,
  }) async => null;

  @override
  Future<bool> commit(
    PhotoAnalysisCacheWrite write, {
    required bool Function() canCommit,
  }) async => false;

  @override
  Future<void> discard(PhotoAnalysisCacheWrite write) async {}

  @override
  Future<void> clearPhoto({
    required String projectId,
    required String photoId,
  }) async {}

  @override
  Future<void> clearProject(String projectId) async {}
}
