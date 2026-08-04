import 'dart:convert';
import 'dart:io';

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
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, Object?>) {
      throw const FormatException('Photo project must be a JSON object');
    }
    final stored = PhotoProject.fromJson(value);
    return stored.copyWith(
      photos: await Future.wait(
        stored.photos.map(
          (photo) async => ProjectPhoto(
            id: photo.id,
            localPath: await _resolvePath(root, photo.localPath),
            originalName: photo.originalName,
          ),
        ),
      ),
    );
  }

  @override
  Future<void> save(PhotoProject project) async {
    final root = await _directory();
    final file = _projectFile(root);
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
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> deletePhotoCopy(ProjectPhoto photo) async {
    final root = await _directory();
    final file = File(photo.localPath);
    if (!await file.exists()) {
      return;
    }
    final media = Directory('${root.path}/media');
    if (!await media.exists()) {
      return;
    }
    final mediaPath = await media.resolveSymbolicLinks();
    final filePath = await file.resolveSymbolicLinks();
    if (filePath.startsWith('$mediaPath/')) {
      await file.delete();
    }
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
}
