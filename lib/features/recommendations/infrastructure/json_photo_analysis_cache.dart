import 'dart:convert';
import 'dart:io';

import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/application/photo_analysis_cache.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';

typedef AnalysisDirectoryProvider = Future<Directory> Function();

final class JsonPhotoAnalysisCache implements PhotoAnalysisCache {
  factory JsonPhotoAnalysisCache({
    required AnalysisDirectoryProvider directory,
  }) => JsonPhotoAnalysisCache._(directory);

  const JsonPhotoAnalysisCache._(this._directory);

  static const _schemaVersion = 1;

  final AnalysisDirectoryProvider _directory;

  @override
  Future<LocalPhotoAnalysis?> read({
    required String projectId,
    required ProjectPhoto photo,
    required PhotoAnalysisEngineIdentity engineIdentity,
  }) async {
    final file = await _cacheFile(photo.id);
    if (file == null || !await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?> ||
          decoded['schemaVersion'] != _schemaVersion ||
          decoded['projectId'] != projectId ||
          decoded['photoId'] != photo.id ||
          decoded['analysis'] is! Map<String, Object?>) {
        return null;
      }
      final analysis = LocalPhotoAnalysis.fromJson(
        decoded['analysis']! as Map<String, Object?>,
      );
      return analysis.matchesInput(photo) && engineIdentity.matches(analysis)
          ? analysis
          : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<PhotoAnalysisCacheWrite> stage({
    required String projectId,
    required String photoId,
    required LocalPhotoAnalysis analysis,
  }) async {
    final file = await _cacheFile(photoId);
    if (file == null) {
      throw ArgumentError.value(photoId, 'photoId', 'Unsafe cache photo id');
    }
    await file.parent.create(recursive: true);
    final temporaryDirectory = await file.parent.createTemp('.write-');
    final token = temporaryDirectory.path.split(Platform.pathSeparator).last;
    final payload = <String, Object>{
      'schemaVersion': _schemaVersion,
      'projectId': projectId,
      'photoId': photoId,
      'writeToken': token,
      'analysis': analysis.toJson(),
    };
    final temporary = File('${temporaryDirectory.path}/result.json');
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    return PhotoAnalysisCacheWrite(
      projectId: projectId,
      photoId: photoId,
      token: temporaryDirectory.path.split(Platform.pathSeparator).last,
      analysis: analysis,
    );
  }

  @override
  Future<bool> commit(
    PhotoAnalysisCacheWrite write, {
    required bool Function() canCommit,
  }) async {
    final file = await _cacheFile(write.photoId);
    final staged = await _stagedFile(write);
    if (file == null || staged == null || !await staged.exists()) return false;
    try {
      final decoded = jsonDecode(await staged.readAsString());
      if (decoded is Map<String, Object?> &&
          decoded['projectId'] == write.projectId &&
          decoded['photoId'] == write.photoId &&
          canCommit()) {
        await staged.rename(file.path);
        return true;
      }
      return false;
    } on Object {
      rethrow;
    } finally {
      final directory = staged.parent;
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> discard(PhotoAnalysisCacheWrite write) async {
    final staged = await _stagedFile(write);
    final directory = staged?.parent;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> clearPhoto({
    required String projectId,
    required String photoId,
  }) async {
    final file = await _cacheFile(photoId);
    if (file == null || !await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?> &&
          decoded['projectId'] == projectId &&
          decoded['photoId'] == photoId) {
        await file.parent.delete(recursive: true);
      }
    } on Object {
      // Unreadable entries cannot be attributed to the requested project.
    }
  }

  @override
  Future<void> clearProject(String projectId) async {
    final root = await _directory();
    final analysisDirectory = Directory('${root.path}/analysis');
    if (!await analysisDirectory.exists()) return;
    await for (final entity in analysisDirectory.list()) {
      if (entity is! Directory) continue;
      final file = File('${entity.path}/result.json');
      if (!await file.exists()) continue;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?> &&
            decoded['projectId'] == projectId) {
          await entity.delete(recursive: true);
        }
      } on Object {
        // Unreadable entries cannot be attributed to the requested project.
      }
    }
  }

  Future<File?> _cacheFile(String photoId) async {
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(photoId) ||
        photoId == '.' ||
        photoId == '..') {
      return null;
    }
    final root = await _directory();
    return File('${root.path}/analysis/$photoId/result.json');
  }

  Future<File?> _stagedFile(PhotoAnalysisCacheWrite write) async {
    if (!RegExp(r'^\.write-[A-Za-z0-9._-]+$').hasMatch(write.token)) {
      return null;
    }
    final file = await _cacheFile(write.photoId);
    if (file == null) return null;
    return File('${file.parent.path}/${write.token}/result.json');
  }
}
