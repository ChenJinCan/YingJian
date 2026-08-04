import 'dart:convert';
import 'dart:io';

import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

typedef ProjectDirectoryProvider = Future<Directory> Function();

final class JsonPhotoProjectStore implements PhotoProjectStore {
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
