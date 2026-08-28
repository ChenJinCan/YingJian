import 'dart:convert';
import 'dart:io';

import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

typedef ProjectDirectoryProvider = Future<Directory> Function();

final class JsonPhotoProjectStore implements PhotoProjectCatalogStore {
  factory JsonPhotoProjectStore({required ProjectDirectoryProvider directory}) {
    return JsonPhotoProjectStore._(directory);
  }

  JsonPhotoProjectStore._(this._directory);

  final ProjectDirectoryProvider _directory;
  String? _activeProjectId;
  bool _startingNewProject = false;

  @override
  Future<PhotoProject?> loadLatest() async {
    final root = await _directory();
    if (_startingNewProject) return null;
    final activeProjectId = _activeProjectId;
    if (activeProjectId != null) {
      final file = _projectFile(root, activeProjectId);
      if (await file.exists()) return _readProject(root, file);
      final legacy = _legacyProjectFile(root);
      if (await legacy.exists()) {
        final project = await _readProject(root, legacy);
        if (project.id == activeProjectId) return project;
      }
      _activeProjectId = null;
    }
    final projects = await loadProjects();
    if (projects.isEmpty) return null;
    _activeProjectId = projects.first.id;
    return projects.first;
  }

  @override
  Future<List<PhotoProject>> loadProjects() async {
    final root = await _directory();
    final projectDirectory = Directory('${root.path}/projects');
    final files = <File>[];
    if (await projectDirectory.exists()) {
      await for (final entity in projectDirectory.list(followLinks: false)) {
        if (entity is File &&
            entity.path.endsWith('.json') &&
            !entity.path.endsWith('.tmp')) {
          files.add(entity);
        }
      }
    }
    final projectsById = <String, PhotoProject>{};
    for (final file in files) {
      final project = await _readProject(root, file);
      final previous = projectsById[project.id];
      if (previous == null || project.updatedAt.isAfter(previous.updatedAt)) {
        projectsById[project.id] = project;
      }
    }
    final projects = projectsById.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List.unmodifiable(projects);
  }

  @override
  Future<void> activateProject(String projectId) async {
    final exists = (await loadProjects()).any(
      (project) => project.id == projectId,
    );
    if (!exists) throw StateError('Photo project does not exist');
    _activeProjectId = projectId;
    _startingNewProject = false;
  }

  @override
  Future<void> startNewProject() async {
    _activeProjectId = null;
    _startingNewProject = true;
  }

  Future<PhotoProject> _readProject(Directory root, File file) async {
    if (!await file.exists()) {
      throw StateError('Photo project does not exist');
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
    final file = _projectFile(root, project.id);
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
      final referencedResources = await _storedResourcePaths(root);
      await _deleteResources(
        root,
        project.editingResources.resources.values.where(
          (resource) =>
              !previousResources.containsKey(resource.id) &&
              !referencedResources.contains(resource.relativePath),
        ),
      );
      rethrow;
    }
    final referencedResources = await _storedResourcePaths(root);
    await _deleteResources(
      root,
      previousResources.values.where(
        (resource) =>
            !project.editingResources.resources.containsKey(resource.id) &&
            !referencedResources.contains(resource.relativePath),
      ),
    );
    final legacy = _legacyProjectFile(root);
    if (legacy.path != file.path &&
        await legacy.exists() &&
        await _storedProjectId(legacy) == project.id) {
      await legacy.delete();
    }
    _activeProjectId = project.id;
    _startingNewProject = false;
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
    final snapshot = _projectFile(root, project.id);
    if (await snapshot.exists()) {
      await snapshot.delete();
    }
    final legacy = _legacyProjectFile(root);
    if (await legacy.exists() && await _storedProjectId(legacy) == project.id) {
      await legacy.delete();
    }
    final referencedPhotos = await _storedPhotoReferences(root);
    for (final photo in project.photos) {
      if (!referencedPhotos.paths.contains(
        _storedPath(root, photo.localPath),
      )) {
        final file = File(photo.localPath);
        final media = Directory('${root.path}/media');
        if (await file.exists() && await media.exists()) {
          final mediaPath = await media.resolveSymbolicLinks();
          final filePath = await file.resolveSymbolicLinks();
          if (filePath.startsWith('$mediaPath/')) await file.delete();
        }
      }
      if (!referencedPhotos.ids.contains(photo.id)) {
        await _deletePhotoDerivedArtifacts(root, photo.id);
      }
    }
    final referencedResources = await _storedResourcePaths(root);
    await _deleteResources(
      root,
      project.editingResources.resources.values.where(
        (resource) => !referencedResources.contains(resource.relativePath),
      ),
    );
    if (_activeProjectId == project.id) {
      _activeProjectId = null;
    }
  }

  File _projectFile(Directory root, String projectId) {
    final encoded = base64Url
        .encode(utf8.encode(projectId))
        .replaceAll('=', '');
    return File('${root.path}/projects/$encoded.json');
  }

  File _legacyProjectFile(Directory root) =>
      File('${root.path}/projects/latest.json');

  Future<String?> _storedProjectId(File file) async {
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map ? value['id'] as String? : null;
    } on Object {
      return null;
    }
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

  Future<Set<String>> _storedResourcePaths(Directory root) async {
    final paths = <String>{};
    for (final file in await _snapshotFiles(root)) {
      paths.addAll(
        (await _readStoredResources(
          file,
        )).values.map((resource) => resource.relativePath),
      );
    }
    return paths;
  }

  Future<({Set<String> ids, Set<String> paths})> _storedPhotoReferences(
    Directory root,
  ) async {
    final ids = <String>{};
    final paths = <String>{};
    for (final file in await _snapshotFiles(root)) {
      try {
        final value = jsonDecode(await file.readAsString());
        if (value is! Map || value['photos'] is! List) continue;
        for (final item in value['photos']! as List) {
          if (item is! Map) continue;
          final id = item['id'];
          final path = item['localPath'];
          if (id is String) ids.add(id);
          if (path is String) paths.add(path);
        }
      } on Object {
        // A corrupt sibling draft is handled on open and must not block cleanup.
      }
    }
    return (ids: ids, paths: paths);
  }

  Future<List<File>> _snapshotFiles(Directory root) async {
    final directory = Directory('${root.path}/projects');
    if (!await directory.exists()) return const [];
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          entity.path.endsWith('.json') &&
          !entity.path.endsWith('.tmp')) {
        files.add(entity);
      }
    }
    return files;
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
