import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

typedef MediaDirectoryProvider = Future<Directory> Function();

@immutable
class SelectedPhoto {
  const SelectedPhoto({required this.path, required this.name});

  final String path;
  final String name;
}

abstract interface class PhotoSource {
  Future<List<SelectedPhoto>> pickPhotos({required int limit});
}

final class AppOwnedPhotoImporter implements PhotoImporter {
  factory AppOwnedPhotoImporter({
    required PhotoSource source,
    required MediaDirectoryProvider mediaDirectory,
    String Function()? createId,
  }) {
    return AppOwnedPhotoImporter._(
      source,
      mediaDirectory,
      createId ?? _defaultId,
    );
  }

  AppOwnedPhotoImporter._(this._source, this._mediaDirectory, this._createId);

  final PhotoSource _source;
  final MediaDirectoryProvider _mediaDirectory;
  final String Function() _createId;

  @override
  Future<List<ProjectPhoto>> importPhotos({required int limit}) async {
    final selected = await _source.pickPhotos(limit: limit);
    if (selected.length > limit) {
      throw StateError('Photo source returned more than the requested limit');
    }
    if (selected.isEmpty) {
      return const [];
    }

    final directory = await _mediaDirectory();
    await directory.create(recursive: true);
    final created = <File>[];
    try {
      final imported = <ProjectPhoto>[];
      for (final photo in selected) {
        final id = _createId();
        final destination = File(
          '${directory.path}/$id${_extension(photo.name)}',
        );
        created.add(await File(photo.path).copy(destination.path));
        imported.add(
          ProjectPhoto(
            id: id,
            localPath: destination.path,
            originalName: photo.name,
          ),
        );
      }
      return imported;
    } catch (_) {
      for (final file in created) {
        if (await file.exists()) {
          await file.delete();
        }
      }
      rethrow;
    }
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || name.length - dot > 10) {
      return '';
    }
    final extension = name.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]+$').hasMatch(extension) ? extension : '';
  }

  static String _defaultId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final entropy = Random.secure().nextInt(0x100000000).toRadixString(16);
    return 'photo-$timestamp-$entropy';
  }
}
