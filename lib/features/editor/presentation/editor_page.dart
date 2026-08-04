import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/l10n/l10n.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  PhotoProjectSession? _session;
  final EditorSession _editorSession = EditorSession();
  int _selectedIndex = 0;
  bool _busy = false;
  bool _exporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) {
      return;
    }
    final session = PhotoProjectSession(
      importer: context.read<PhotoImporter>(),
      store: context.read<PhotoProjectStore>(),
    );
    _session = session;
    unawaited(_restoreProject(session));
  }

  Future<void> _restoreProject(PhotoProjectSession session) async {
    await session.restore();
    final project = session.project;
    _editorSession.load(session.editableRecipe);
    final focusPhotoId = project?.focusPhotoId;
    if (focusPhotoId != null) {
      final focusIndex = project!.photos.indexWhere(
        (photo) => photo.id == focusPhotoId,
      );
      if (focusIndex >= 0) {
        _selectedIndex = focusIndex;
      }
    }
  }

  Future<void> _persistRecipe() async {
    try {
      await _session?.commitEdit(_editorSession.recipe);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    } finally {
      _editorSession.load(_session?.editableRecipe ?? EditRecipe.neutral);
    }
  }

  Future<void> _undoEdit() async {
    try {
      await _session?.undoEdit();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    } finally {
      _editorSession.load(_session?.editableRecipe ?? EditRecipe.neutral);
    }
  }

  Future<void> _redoEdit() async {
    try {
      await _session?.redoEdit();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    } finally {
      _editorSession.load(_session?.editableRecipe ?? EditRecipe.neutral);
    }
  }

  Future<void> _resetEdit() async {
    _editorSession.load(EditRecipe.neutral);
    await _persistRecipe();
  }

  Future<void> _selectPhoto(int index) async {
    final photo = _session!.photos[index];
    try {
      await _session!.setFocusPhoto(photo.id);
      if (mounted) setState(() => _selectedIndex = index);
      _editorSession.load(_session!.editableRecipe);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.delete),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _removePhoto(ProjectPhoto photo) async {
    if (_exporting) return;
    final confirmed = await _confirm(
      title: context.l10n.removePhoto,
      message: context.l10n.removePhotoConfirmation,
    );
    if (!confirmed) {
      return;
    }
    try {
      await _session!.removePhoto(photo.id);
      final focusPhotoId = _session!.project?.focusPhotoId;
      if (focusPhotoId != null) {
        _selectedIndex = _session!.photos.indexWhere(
          (candidate) => candidate.id == focusPhotoId,
        );
      } else {
        _selectedIndex = 0;
      }
      _editorSession.load(_session!.editableRecipe);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    }
  }

  Future<void> _deleteProject() async {
    if (_exporting) return;
    final confirmed = await _confirm(
      title: context.l10n.deleteProject,
      message: context.l10n.deleteProjectConfirmation,
    );
    if (!confirmed) {
      return;
    }
    try {
      await _session!.deleteProject();
      _selectedIndex = 0;
      _editorSession.load(EditRecipe.neutral);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    }
  }

  Future<void> _movePhoto(ProjectPhoto photo, int destination) async {
    if (_exporting) return;
    try {
      await _session!.movePhoto(photoId: photo.id, toIndex: destination);
      _selectedIndex = destination;
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    _editorSession.dispose();
    super.dispose();
  }

  Future<void> _exportPhoto(ProjectPhoto photo) async {
    if (_exporting) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final exported = await context.read<PhotoExporter>().export(
        photo: photo,
        recipe: _session!.effectiveRecipeFor(photo.id),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.photoExported(exported.width, exported.height),
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.photoExportFailed)));
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _importPhotos() async {
    if (_busy || _exporting) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _session!.importPhotos();
      if (!mounted) {
        return;
      }
      if (result == PhotoImportResult.limitReached) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.photoLimitReached)));
      }
      if (result == PhotoImportResult.imported) {
        _editorSession.load(_session!.editableRecipe);
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.photoImportFailed)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session!;
    return ListenableBuilder(
      listenable: Listenable.merge([session, _editorSession]),
      builder: (context, _) {
        final photos = session.photos;
        if (_selectedIndex >= photos.length && photos.isNotEmpty) {
          _selectedIndex = photos.length - 1;
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.editorTitle),
            actions: photos.isEmpty
                ? null
                : [
                    IconButton(
                      tooltip: context.l10n.deleteProject,
                      onPressed: _exporting
                          ? null
                          : () => unawaited(_deleteProject()),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
          ),
          body: SafeArea(
            child: session.isRestoring
                ? const Center(child: CircularProgressIndicator())
                : session.restoreError != null
                ? _RestoreError(onRetry: session.restore)
                : photos.isEmpty
                ? _EmptyProject(
                    busy: _busy,
                    failures: session.importFailures,
                    onImport: _importPhotos,
                  )
                : _PhotoWorkspace(
                    photos: photos,
                    importFailures: session.importFailures,
                    selectedIndex: _selectedIndex,
                    busy: _busy,
                    exporting: _exporting,
                    editingEnabled: session.canEdit,
                    previewRecipe: session.previewRecipeFor(
                      photos[_selectedIndex].id,
                      _editorSession.recipe,
                    ),
                    editorSession: _editorSession,
                    canUndo: session.canUndo,
                    canRedo: session.canRedo,
                    onSelected: (index) => unawaited(_selectPhoto(index)),
                    onMove: (photo, destination) =>
                        unawaited(_movePhoto(photo, destination)),
                    onRemove: (photo) => unawaited(_removePhoto(photo)),
                    onImport: _importPhotos,
                    onExport: _exportPhoto,
                    onRecipeCommitted: () => unawaited(_persistRecipe()),
                    onUndo: () => unawaited(_undoEdit()),
                    onRedo: () => unawaited(_redoEdit()),
                    onReset: () => unawaited(_resetEdit()),
                  ),
          ),
        );
      },
    );
  }
}

class _RestoreError extends StatelessWidget {
  const _RestoreError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              context.l10n.projectRestoreFailed,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => unawaited(onRetry()),
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProject extends StatelessWidget {
  const _EmptyProject({
    required this.busy,
    required this.failures,
    required this.onImport,
  });

  final bool busy;
  final List<PhotoImportFailure> failures;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (failures.isNotEmpty) ...[
              _ImportFailures(failures: failures),
              const SizedBox(height: 24),
            ],
            Icon(
              Icons.photo_library_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.selectPhotosTitle,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.photoImportPrivacy,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: busy ? null : onImport,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(context.l10n.selectPhotos),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoWorkspace extends StatelessWidget {
  const _PhotoWorkspace({
    required this.photos,
    required this.importFailures,
    required this.selectedIndex,
    required this.busy,
    required this.exporting,
    required this.editingEnabled,
    required this.previewRecipe,
    required this.editorSession,
    required this.canUndo,
    required this.canRedo,
    required this.onSelected,
    required this.onMove,
    required this.onRemove,
    required this.onImport,
    required this.onExport,
    required this.onRecipeCommitted,
    required this.onUndo,
    required this.onRedo,
    required this.onReset,
  });

  final List<ProjectPhoto> photos;
  final List<PhotoImportFailure> importFailures;
  final int selectedIndex;
  final bool busy;
  final bool exporting;
  final bool editingEnabled;
  final EditRecipe previewRecipe;
  final EditorSession editorSession;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<int> onSelected;
  final void Function(ProjectPhoto photo, int destination) onMove;
  final ValueChanged<ProjectPhoto> onRemove;
  final VoidCallback onImport;
  final ValueChanged<ProjectPhoto> onExport;
  final VoidCallback onRecipeCommitted;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final selected = photos[selectedIndex];
    final recipe = editorSession.recipe;
    final previewRenderer = context.read<PhotoPreviewRenderer>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (importFailures.isNotEmpty) ...[
          _ImportFailures(failures: importFailures),
          const SizedBox(height: 12),
        ],
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: NativePhotoPreview(
                    key: ValueKey('photo-preview-${selected.id}'),
                    sourcePath: selected.localPath,
                    recipe: previewRecipe,
                    renderer: previewRenderer,
                    errorBuilder: (context) =>
                        Center(child: Text(context.l10n.photoLoadFailed)),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                selected.originalName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(context.l10n.photoCount(photos.length)),
            IconButton(
              tooltip: context.l10n.movePhotoEarlier,
              onPressed: selectedIndex == 0 || exporting
                  ? null
                  : () => onMove(selected, selectedIndex - 1),
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              tooltip: context.l10n.movePhotoLater,
              onPressed: selectedIndex == photos.length - 1 || exporting
                  ? null
                  : () => onMove(selected, selectedIndex + 1),
              icon: const Icon(Icons.arrow_forward),
            ),
            IconButton(
              tooltip: context.l10n.removePhoto,
              onPressed: exporting ? null : () => onRemove(selected),
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final photo = photos[index];
              return Semantics(
                selected: index == selectedIndex,
                button: true,
                label: photo.originalName,
                child: InkWell(
                  onTap: () => onSelected(index),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: index == selectedIndex
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.file(
                      File(photo.localPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        _AdjustmentSlider(
          enabled: editingEnabled,
          label: context.l10n.exposure,
          value: recipe.exposure,
          onStart: editorSession.beginAdjustment,
          onChanged: (value) {
            editorSession.preview(recipe.copyWith(exposure: value));
          },
          onEnd: () {
            editorSession.commitAdjustment();
            onRecipeCommitted();
          },
        ),
        _AdjustmentSlider(
          enabled: editingEnabled,
          label: context.l10n.contrast,
          value: recipe.contrast,
          onStart: editorSession.beginAdjustment,
          onChanged: (value) {
            editorSession.preview(recipe.copyWith(contrast: value));
          },
          onEnd: () {
            editorSession.commitAdjustment();
            onRecipeCommitted();
          },
        ),
        _AdjustmentSlider(
          enabled: editingEnabled,
          label: context.l10n.warmth,
          value: recipe.warmth,
          onStart: editorSession.beginAdjustment,
          onChanged: (value) {
            editorSession.preview(recipe.copyWith(warmth: value));
          },
          onEnd: () {
            editorSession.commitAdjustment();
            onRecipeCommitted();
          },
        ),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: editingEnabled && canUndo ? onUndo : null,
                icon: const Icon(Icons.undo),
                label: Text(context.l10n.undo),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: editingEnabled && canRedo ? onRedo : null,
                icon: const Icon(Icons.redo),
                label: Text(context.l10n.redo),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: editingEnabled && editorSession.isEdited
                    ? onReset
                    : null,
                child: Text(context.l10n.reset),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: exporting || !editingEnabled
              ? null
              : () => onExport(selected),
          icon: exporting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_download_outlined),
          label: Text(context.l10n.exportOriginalQuality),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed:
              busy || exporting || photos.length >= PhotoProject.maxPhotoCount
              ? null
              : onImport,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(context.l10n.addPhotos),
        ),
      ],
    );
  }
}

class _ImportFailures extends StatelessWidget {
  const _ImportFailures({required this.failures});

  final List<PhotoImportFailure> failures;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: colors.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.photoImportIssuesTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final failure in failures)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _photoImportFailureMessage(context, failure),
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _photoImportFailureMessage(
  BuildContext context,
  PhotoImportFailure failure,
) {
  return switch (failure.reason) {
    PhotoImportFailureReason.unsupportedFormat =>
      context.l10n.photoUnsupportedFormat(failure.photoName),
    PhotoImportFailureReason.unsupportedColorSpace =>
      context.l10n.photoUnsupportedFormat(failure.photoName),
    PhotoImportFailureReason.animatedImage =>
      context.l10n.photoAnimatedUnsupported(failure.photoName),
    PhotoImportFailureReason.fileTooLarge => context.l10n.photoFileTooLarge(
      failure.photoName,
    ),
    PhotoImportFailureReason.dimensionsTooLarge =>
      context.l10n.photoDimensionsTooLarge(failure.photoName),
    PhotoImportFailureReason.unreadable => context.l10n.photoUnreadable(
      failure.photoName,
    ),
    PhotoImportFailureReason.copyFailed => context.l10n.photoCopyFailed(
      failure.photoName,
    ),
  };
}

class _AdjustmentSlider extends StatelessWidget {
  const _AdjustmentSlider({
    required this.enabled,
    required this.label,
    required this.value,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

  final bool enabled;
  final String label;
  final double value;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: -1,
            max: 1,
            divisions: 100,
            label: '${(value * 100).round()}',
            onChangeStart: enabled ? (_) => onStart() : null,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? (_) => onEnd() : null,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('${(value * 100).round()}', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
