import 'dart:convert';
import 'dart:io';

import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

typedef ProjectDirectoryProvider = Future<Directory> Function();

final class JsonPhotoProjectStore implements PhotoProjectLifecycleStore {
  factory JsonPhotoProjectStore({required ProjectDirectoryProvider directory}) {
    return JsonPhotoProjectStore._(directory);
  }

  JsonPhotoProjectStore._(this._directory);

  final ProjectDirectoryProvider _directory;

  @override
  Future<PhotoProject?> loadLatest() async {
    final root = await _directory();
    final file = _projectFile(root);
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Photo project must be a JSON object');
    }
    final value = Map<String, Object?>.from(decoded);
    final storedVersion = (value['schemaVersion'] as num?)?.toInt() ?? 1;
    await _rewriteBackgroundImagePaths(
      value,
      (path) => _resolvePath(root, path),
    );
    final stored = PhotoProject.fromJson(value);
    final resolved = stored.copyWith(
      photos: await Future.wait(
        stored.photos.map(
          (photo) async => ProjectPhoto(
            id: photo.id,
            localPath: await _resolvePath(root, photo.localPath),
            originalName: photo.originalName,
            contentSha256: photo.contentSha256,
            pixelWidth: photo.pixelWidth,
            pixelHeight: photo.pixelHeight,
            orientation: photo.orientation,
            colorSpace: photo.colorSpace,
            inputFormat: photo.inputFormat,
            supportState: photo.supportState,
          ),
        ),
      ),
    );
    if (storedVersion < PhotoProject.schemaVersion) {
      try {
        await save(resolved);
      } on Object {
        // The old snapshot remains authoritative and migration retries on the
        // next open; the already validated visible result is still usable.
      }
    }
    return resolved;
  }

  @override
  Future<void> save(PhotoProject project) async {
    if (project.requiresUpdate) {
      throw StateError(
        'A project with unknown meta operations is read-only until update',
      );
    }
    if (!project.hasConsistentEditState) {
      throw StateError(
        'Photo project edit state does not match its render projection',
      );
    }
    final root = await _directory();
    final file = _projectFile(root);
    final previousResources = await _readStoredResources(file);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final value = project.toJson();
    value['photos'] = project.photos
        .map(
          (photo) => {
            ...photo.toJson(),
            'localPath': _storedPath(root, photo.localPath),
          },
        )
        .toList();
    await _rewriteBackgroundImagePaths(
      value,
      (path) async => _storedPath(root, path),
    );
    try {
      await temporary.writeAsString(jsonEncode(value), flush: true);
      final verified = jsonDecode(await temporary.readAsString());
      if (verified is! Map<String, Object?>) {
        throw const FormatException('Saved project must be a JSON object');
      }
      PhotoProject.fromJson(verified);
      await temporary.rename(file.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      await _deleteResources(
        root,
        project.editingResources.resources.values.where(
          (resource) => !previousResources.containsKey(resource.id),
        ),
      );
      rethrow;
    }
    await _deleteResources(
      root,
      previousResources.values.where(
        (resource) =>
            !project.editingResources.resources.containsKey(resource.id),
      ),
    );
  }

  @override
  Future<void> deletePhotoCopy(ProjectPhoto photo) async {
    final root = await _directory();
    final file = File(photo.localPath);
    final media = Directory('${root.path}/media');
    if (await file.exists() && await media.exists()) {
      final mediaPath = await media.resolveSymbolicLinks();
      final filePath = await file.resolveSymbolicLinks();
      if (filePath.startsWith('$mediaPath/')) {
        await file.delete();
      }
    }
    await _deletePhotoDerivedArtifacts(root, photo.id);
  }

  @override
  Future<void> deleteProject(PhotoProject project) async {
    final root = await _directory();
    final snapshot = _projectFile(root);
    if (await snapshot.exists()) {
      await snapshot.delete();
    }
    for (final photo in project.photos) {
      await deletePhotoCopy(photo);
    }
    for (final name in const [
      'media',
      'resources',
      'previews',
      'analysis',
      'debug',
    ]) {
      final directory = Directory('${root.path}/$name');
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  File _projectFile(Directory root) {
    return File('${root.path}/projects/latest.json');
  }

  String _storedPath(Directory root, String path) {
    final prefix = '${root.path}/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  Future<String> _resolvePath(Directory root, String path) async {
    if (path.startsWith('/')) {
      if (!await File(path).exists() && path.contains('/media/')) {
        final fileName = path.split('/').last;
        final currentCopy = File('${root.path}/media/$fileName');
        if (await currentCopy.exists()) {
          return currentCopy.path;
        }
      }
      return path;
    }
    if (path.split('/').contains('..')) {
      throw const FormatException('Photo path leaves the project directory');
    }
    return '${root.path}/$path';
  }

  Future<void> _deletePhotoDerivedArtifacts(
    Directory root,
    String photoId,
  ) async {
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(photoId) ||
        photoId == '.' ||
        photoId == '..') {
      return;
    }
    for (final name in const ['previews', 'analysis', 'debug']) {
      final directory = Directory('${root.path}/$name/$photoId');
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<void> _rewriteBackgroundImagePaths(
    Object? value,
    Future<String> Function(String path) rewrite,
  ) async {
    if (value is List) {
      for (final item in value) {
        await _rewriteBackgroundImagePaths(item, rewrite);
      }
      return;
    }
    if (value is! Map) return;
    for (final entry in value.entries.toList()) {
      if (entry.key == 'unknownMetaOps') continue;
      if (entry.key == 'backgroundImagePath' &&
          entry.value is String &&
          (entry.value! as String).isNotEmpty) {
        value[entry.key] = await rewrite(entry.value! as String);
      } else {
        await _rewriteBackgroundImagePaths(entry.value, rewrite);
      }
    }
  }

  Future<Map<String, EditingResourceDescriptor>> _readStoredResources(
    File file,
  ) async {
    if (!await file.exists()) return const {};
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map || value['editingResources'] is! Map) return const {};
      return EditingResourceRegistry.fromJson(
        Map<String, Object?>.from(value['editingResources']! as Map),
      ).resources;
    } on Object {
      return const {};
    }
  }

  Future<void> _deleteResources(
    Directory root,
    Iterable<EditingResourceDescriptor> resources,
  ) async {
    final resourceRoot = Directory('${root.path}/resources');
    if (!await resourceRoot.exists()) return;
    final safeRoot = await resourceRoot.resolveSymbolicLinks();
    for (final resource in resources) {
      resource.validate();
      final file = File('${root.path}/${resource.relativePath}');
      if (!await file.exists()) continue;
      final safePath = await file.resolveSymbolicLinks();
      if (safePath.startsWith('$safeRoot${Platform.pathSeparator}')) {
        await file.delete();
      }
    }
  }
}
