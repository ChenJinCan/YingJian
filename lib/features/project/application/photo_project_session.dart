import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

abstract interface class PhotoImporter {
  Future<List<ProjectPhoto>> importPhotos({required int limit});
}

abstract interface class PhotoProjectStore {
  Future<PhotoProject?> loadLatest();

  Future<void> save(PhotoProject project);
}

enum PhotoImportResult { imported, canceled, limitReached }

class PhotoProjectSession extends ChangeNotifier {
  factory PhotoProjectSession({
    required PhotoImporter importer,
    required PhotoProjectStore store,
    DateTime Function()? now,
    String Function()? createId,
  }) {
    return PhotoProjectSession._(
      importer,
      store,
      now ?? DateTime.now,
      createId ?? _defaultId,
    );
  }

  PhotoProjectSession._(this._importer, this._store, this._now, this._createId);

  final PhotoImporter _importer;
  final PhotoProjectStore _store;
  final DateTime Function() _now;
  final String Function() _createId;

  PhotoProject? _project;
  Object? _restoreError;
  bool _isRestoring = false;

  PhotoProject? get project => _project;
  List<ProjectPhoto> get photos => _project?.photos ?? const [];
  Object? get restoreError => _restoreError;
  bool get isRestoring => _isRestoring;

  Future<void> restore() async {
    _isRestoring = true;
    _restoreError = null;
    notifyListeners();
    try {
      _project = await _store.loadLatest();
    } on Object catch (error) {
      _restoreError = error;
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<PhotoImportResult> importPhotos() async {
    final remaining = PhotoProject.maxPhotoCount - photos.length;
    if (remaining == 0) {
      return PhotoImportResult.limitReached;
    }

    final imported = await _importer.importPhotos(limit: remaining);
    if (imported.isEmpty) {
      return PhotoImportResult.canceled;
    }
    if (imported.length > remaining) {
      throw StateError('Photo importer returned more than the requested limit');
    }

    final timestamp = _now();
    final existing = _project;
    final next = existing == null
        ? PhotoProject(
            id: _createId(),
            createdAt: timestamp,
            updatedAt: timestamp,
            photos: imported,
          )
        : existing.copyWith(
            updatedAt: timestamp,
            photos: [...existing.photos, ...imported],
          );
    await _store.save(next);
    _project = next;
    notifyListeners();
    return PhotoImportResult.imported;
  }

  Future<void> updateRecipe(EditRecipe recipe) async {
    final current = _project;
    if (current == null || current.recipe == recipe) {
      return;
    }
    final next = current.copyWith(updatedAt: _now(), recipe: recipe);
    await _store.save(next);
    _project = next;
    notifyListeners();
  }

  static String _defaultId() {
    return 'project-${DateTime.now().toUtc().microsecondsSinceEpoch}';
  }
}
