import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/application/photo_analysis_cache.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';

final class MemoryPhotoAnalysisCache implements PhotoAnalysisCache {
  final Map<String, Map<String, _MemoryEntry>> _projects = {};
  final Map<String, PhotoAnalysisCacheWrite> _staged = {};
  int _nextToken = 0;

  @override
  Future<LocalPhotoAnalysis?> read({
    required String projectId,
    required ProjectPhoto photo,
    required PhotoAnalysisEngineIdentity engineIdentity,
  }) async {
    final analysis = _projects[projectId]?[photo.id]?.analysis;
    return analysis != null &&
            analysis.matchesInput(photo) &&
            engineIdentity.matches(analysis)
        ? analysis
        : null;
  }

  @override
  Future<PhotoAnalysisCacheWrite> stage({
    required String projectId,
    required String photoId,
    required LocalPhotoAnalysis analysis,
  }) async {
    final token = 'memory-${_nextToken++}';
    final write = PhotoAnalysisCacheWrite(
      projectId: projectId,
      photoId: photoId,
      token: token,
      analysis: analysis,
    );
    _staged[token] = write;
    return write;
  }

  @override
  Future<bool> commit(
    PhotoAnalysisCacheWrite write, {
    required bool Function() canCommit,
  }) async {
    if (!identical(_staged[write.token], write) || !canCommit()) {
      _staged.remove(write.token);
      return false;
    }
    _staged.remove(write.token);
    (_projects[write.projectId] ??= {})[write.photoId] = _MemoryEntry(
      write.token,
      write.analysis,
    );
    return true;
  }

  @override
  Future<void> discard(PhotoAnalysisCacheWrite write) async {
    _staged.remove(write.token);
  }

  @override
  Future<void> clearPhoto({
    required String projectId,
    required String photoId,
  }) async {
    final photos = _projects[projectId];
    photos?.remove(photoId);
    _staged.removeWhere(
      (_, write) => write.projectId == projectId && write.photoId == photoId,
    );
    if (photos?.isEmpty == true) _projects.remove(projectId);
  }

  @override
  Future<void> clearProject(String projectId) async {
    _projects.remove(projectId);
    _staged.removeWhere((_, write) => write.projectId == projectId);
  }
}

final class _MemoryEntry {
  const _MemoryEntry(this.token, this.analysis);

  final String token;
  final LocalPhotoAnalysis analysis;
}
