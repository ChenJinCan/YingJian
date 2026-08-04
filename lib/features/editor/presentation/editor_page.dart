import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/photo_color_transform.dart';
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
    _editorSession.load(session.project?.recipe ?? EditRecipe.neutral);
  }

  Future<void> _persistRecipe() async {
    try {
      await _session?.updateRecipe(_editorSession.recipe);
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
        recipe: _editorSession.recipe,
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
    if (_busy) {
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
          appBar: AppBar(title: Text(context.l10n.editorTitle)),
          body: SafeArea(
            child: session.isRestoring
                ? const Center(child: CircularProgressIndicator())
                : session.restoreError != null
                ? _RestoreError(onRetry: session.restore)
                : photos.isEmpty
                ? _EmptyProject(busy: _busy, onImport: _importPhotos)
                : _PhotoWorkspace(
                    photos: photos,
                    selectedIndex: _selectedIndex,
                    busy: _busy,
                    exporting: _exporting,
                    editorSession: _editorSession,
                    onSelected: (index) {
                      setState(() => _selectedIndex = index);
                    },
                    onImport: _importPhotos,
                    onExport: _exportPhoto,
                    onRecipeCommitted: () => unawaited(_persistRecipe()),
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
  const _EmptyProject({required this.busy, required this.onImport});

  final bool busy;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
    required this.selectedIndex,
    required this.busy,
    required this.exporting,
    required this.editorSession,
    required this.onSelected,
    required this.onImport,
    required this.onExport,
    required this.onRecipeCommitted,
  });

  final List<ProjectPhoto> photos;
  final int selectedIndex;
  final bool busy;
  final bool exporting;
  final EditorSession editorSession;
  final ValueChanged<int> onSelected;
  final VoidCallback onImport;
  final ValueChanged<ProjectPhoto> onExport;
  final VoidCallback onRecipeCommitted;

  @override
  Widget build(BuildContext context) {
    final selected = photos[selectedIndex];
    final recipe = editorSession.recipe;
    final transform = PhotoColorTransform.fromRecipe(recipe);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.matrix(transform.flutterMatrix),
                    child: Image.file(
                      File(selected.localPath),
                      key: ValueKey('photo-preview-${selected.id}'),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          Center(child: Text(context.l10n.photoLoadFailed)),
                    ),
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
                onPressed: editorSession.canUndo
                    ? () {
                        editorSession.undo();
                        onRecipeCommitted();
                      }
                    : null,
                icon: const Icon(Icons.undo),
                label: Text(context.l10n.undo),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: editorSession.isEdited
                    ? () {
                        editorSession.reset();
                        onRecipeCommitted();
                      }
                    : null,
                child: Text(context.l10n.reset),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: exporting ? null : () => onExport(selected),
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
          onPressed: busy || photos.length >= PhotoProject.maxPhotoCount
              ? null
              : onImport,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(context.l10n.addPhotos),
        ),
      ],
    );
  }
}

class _AdjustmentSlider extends StatelessWidget {
  const _AdjustmentSlider({
    required this.label,
    required this.value,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

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
            onChangeStart: (_) => onStart(),
            onChanged: onChanged,
            onChangeEnd: (_) => onEnd(),
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
