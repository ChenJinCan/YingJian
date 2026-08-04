import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/application/local_recommendation_coordinator.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';
import 'package:yingjian/features/recommendations/domain/recipe_catalog.dart';
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
  bool _preparingRecommendations = false;
  RecommendationPreparation? _recommendationPreparation;
  int _previewRecommendationIndex = -1;

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
    if (project != null &&
        (project.flowState == PhotoProjectFlowState.analyzing ||
            project.flowState ==
                PhotoProjectFlowState.choosingRecommendation)) {
      await _prepareRecommendations(
        persistAnalysisStates:
            project.flowState == PhotoProjectFlowState.analyzing,
      );
    }
  }

  Future<void> _prepareRecommendations({
    required bool persistAnalysisStates,
  }) async {
    final session = _session!;
    if (_preparingRecommendations || session.photos.isEmpty) return;
    if (mounted) setState(() => _preparingRecommendations = true);
    try {
      final preparation =
          await LocalRecommendationCoordinator(
            analyzer: context.read<PhotoAnalyzer>(),
          ).prepare(
            photos: session.photos,
            onStateChanged: persistAnalysisStates
                ? session.setPhotoAnalysisState
                : null,
          );
      if (persistAnalysisStates &&
          session.project?.flowState == PhotoProjectFlowState.analyzing) {
        await session.transitionTo(
          PhotoProjectFlowState.choosingRecommendation,
        );
      }
      if (mounted) {
        setState(() {
          _recommendationPreparation = preparation;
          _previewRecommendationIndex = -1;
        });
      }
    } finally {
      if (mounted) setState(() => _preparingRecommendations = false);
    }
  }

  Future<void> _selectRecommendation(LocalRecommendation recommendation) async {
    try {
      await _session!.selectRecommendation(
        recommendationId: recommendation.id,
        sharedStyle: recommendation.sharedStyle,
        adaptiveCompensations: recommendation.adaptiveCompensations,
      );
      _editorSession.load(_session!.editableRecipe);
      if (mounted) setState(() => _recommendationPreparation = null);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
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
        await _prepareRecommendations(persistAnalysisStates: true);
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
        final recommendations = _recommendationPreparation?.recommendations;
        final previewRecommendation =
            recommendations == null || _previewRecommendationIndex < 0
            ? null
            : recommendations[_previewRecommendationIndex
                  .clamp(0, recommendations.length - 1)
                  .toInt()];
        final previewRecipe = photos.isEmpty
            ? EditRecipe.neutral
            : previewRecommendation == null
            ? session.previewRecipeFor(
                photos[_selectedIndex].id,
                _editorSession.recipe,
              )
            : session.project!
                  .copyWith(
                    sharedStyle: previewRecommendation.sharedStyle,
                    adaptiveCompensations:
                        previewRecommendation.adaptiveCompensations,
                  )
                  .effectiveRecipeFor(photos[_selectedIndex].id);
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
                    previewRecipe: previewRecipe,
                    flowState: session.flowState,
                    preparingRecommendations: _preparingRecommendations,
                    recommendations: recommendations ?? const [],
                    selectedRecommendationIndex: _previewRecommendationIndex,
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
                    onRecommendationPreviewed: (index) =>
                        setState(() => _previewRecommendationIndex = index),
                    onRecommendationSelected: (recommendation) =>
                        unawaited(_selectRecommendation(recommendation)),
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
    required this.flowState,
    required this.preparingRecommendations,
    required this.recommendations,
    required this.selectedRecommendationIndex,
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
    required this.onRecommendationPreviewed,
    required this.onRecommendationSelected,
  });

  final List<ProjectPhoto> photos;
  final List<PhotoImportFailure> importFailures;
  final int selectedIndex;
  final bool busy;
  final bool exporting;
  final bool editingEnabled;
  final EditRecipe previewRecipe;
  final PhotoProjectFlowState flowState;
  final bool preparingRecommendations;
  final List<LocalRecommendation> recommendations;
  final int selectedRecommendationIndex;
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
  final ValueChanged<int> onRecommendationPreviewed;
  final ValueChanged<LocalRecommendation> onRecommendationSelected;

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
                  child: _BeforeAfterPreview(
                    key: ValueKey('photo-preview-${selected.id}'),
                    sourcePath: selected.localPath,
                    recipe: previewRecipe,
                    renderer: previewRenderer,
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
        if (flowState == PhotoProjectFlowState.analyzing ||
            flowState == PhotoProjectFlowState.choosingRecommendation) ...[
          _RecommendationPanel(
            preparing: preparingRecommendations,
            recommendations: recommendations,
            selectedIndex: selectedRecommendationIndex,
            onPreviewed: onRecommendationPreviewed,
            onSelected: onRecommendationSelected,
          ),
          const SizedBox(height: 20),
        ],
        _AdjustmentToolStrip(
          enabled: editingEnabled,
          extended: supportsImagePipelineV2,
          recipe: recipe,
          editorSession: editorSession,
          onRecipeCommitted: onRecipeCommitted,
        ),
        const SizedBox(height: 8),
        if (supportsImagePipelineV2 && photos.length == 1)
          _CompositionTools(
            enabled: editingEnabled,
            photo: selected,
            recipe: recipe,
            editorSession: editorSession,
            onRecipeCommitted: onRecipeCommitted,
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

class _RecommendationPanel extends StatelessWidget {
  const _RecommendationPanel({
    required this.preparing,
    required this.recommendations,
    required this.selectedIndex,
    required this.onPreviewed,
    required this.onSelected,
  });

  final bool preparing;
  final List<LocalRecommendation> recommendations;
  final int selectedIndex;
  final ValueChanged<int> onPreviewed;
  final ValueChanged<LocalRecommendation> onSelected;

  @override
  Widget build(BuildContext context) {
    if (preparing || recommendations.isEmpty) {
      return Semantics(
        liveRegion: true,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(context.l10n.analysisPreparing)),
              ],
            ),
          ),
        ),
      );
    }
    final safeIndex = selectedIndex
        .clamp(0, recommendations.length - 1)
        .toInt();
    final selected = recommendations[safeIndex];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.recommendationsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(context.l10n.recommendationsSubtitle),
            const SizedBox(height: 12),
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recommendations.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final recommendation = recommendations[index];
                  final isSelected = index == safeIndex;
                  return Semantics(
                    selected: isSelected,
                    button: true,
                    child: InkWell(
                      onTap: () => onPreviewed(index),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 148,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(_recommendationIcon(recommendation.family)),
                            Text(
                              _recommendationLabel(
                                context,
                                recommendation.family,
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              context.l10n.localEffect,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.safeFallbackNotice,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => onSelected(selected),
                child: Text(context.l10n.useThisLook),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _recommendationIcon(SharedStyleFamily family) =>
      switch (family) {
        SharedStyleFamily.naturalClean => Icons.wb_sunny_outlined,
        SharedStyleFamily.atmosphericColor => Icons.palette_outlined,
        SharedStyleFamily.texturedStyle => Icons.grain,
        SharedStyleFamily.manual => Icons.tune,
      };

  static String _recommendationLabel(
    BuildContext context,
    SharedStyleFamily family,
  ) => switch (family) {
    SharedStyleFamily.naturalClean => context.l10n.recommendationNaturalClean,
    SharedStyleFamily.atmosphericColor =>
      context.l10n.recommendationAtmosphericColor,
    SharedStyleFamily.texturedStyle => context.l10n.recommendationTexturedStyle,
    SharedStyleFamily.manual => context.l10n.recommendationNaturalClean,
  };
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

class _BeforeAfterPreview extends StatefulWidget {
  const _BeforeAfterPreview({
    required this.sourcePath,
    required this.recipe,
    required this.renderer,
    super.key,
  });

  final String sourcePath;
  final EditRecipe recipe;
  final PhotoPreviewRenderer renderer;

  @override
  State<_BeforeAfterPreview> createState() => _BeforeAfterPreviewState();
}

class _BeforeAfterPreviewState extends State<_BeforeAfterPreview> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final recipe = _showOriginal
        ? EditRecipe(crop: widget.recipe.crop)
        : widget.recipe;
    return Stack(
      fit: StackFit.expand,
      children: [
        NativePhotoPreview(
          sourcePath: widget.sourcePath,
          recipe: recipe,
          renderer: widget.renderer,
          errorBuilder: (context) =>
              Center(child: Text(context.l10n.photoLoadFailed)),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: FilledButton.tonalIcon(
            onPressed: () => setState(() => _showOriginal = !_showOriginal),
            icon: Icon(
              _showOriginal ? Icons.auto_fix_high : Icons.compare_outlined,
            ),
            label: Text(
              _showOriginal
                  ? context.l10n.compareEdited
                  : context.l10n.compareOriginal,
            ),
          ),
        ),
      ],
    );
  }
}

enum _AdjustmentParameter {
  exposure,
  highlights,
  shadows,
  contrast,
  warmth,
  tint,
  saturation,
  clarity,
}

class _AdjustmentToolStrip extends StatefulWidget {
  const _AdjustmentToolStrip({
    required this.enabled,
    required this.extended,
    required this.recipe,
    required this.editorSession,
    required this.onRecipeCommitted,
  });

  final bool enabled;
  final bool extended;
  final EditRecipe recipe;
  final EditorSession editorSession;
  final VoidCallback onRecipeCommitted;

  @override
  State<_AdjustmentToolStrip> createState() => _AdjustmentToolStripState();
}

class _AdjustmentToolStripState extends State<_AdjustmentToolStrip> {
  _AdjustmentParameter _selected = _AdjustmentParameter.exposure;

  @override
  Widget build(BuildContext context) {
    final parameters = widget.extended
        ? _AdjustmentParameter.values
        : const <_AdjustmentParameter>[
            _AdjustmentParameter.exposure,
            _AdjustmentParameter.contrast,
            _AdjustmentParameter.warmth,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: parameters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final parameter = parameters[index];
              return ChoiceChip(
                label: Text(_label(context, parameter)),
                selected: parameter == _selected,
                onSelected: widget.enabled
                    ? (_) => setState(() => _selected = parameter)
                    : null,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _AdjustmentSlider(
          enabled: widget.enabled,
          label: '',
          value: _value(widget.recipe, _selected),
          onStart: widget.editorSession.beginAdjustment,
          onChanged: (value) => widget.editorSession.preview(
            _copyWith(widget.recipe, _selected, value),
          ),
          onEnd: () {
            widget.editorSession.commitAdjustment();
            widget.onRecipeCommitted();
          },
        ),
      ],
    );
  }

  String _label(BuildContext context, _AdjustmentParameter parameter) =>
      switch (parameter) {
        _AdjustmentParameter.exposure => context.l10n.exposure,
        _AdjustmentParameter.highlights => context.l10n.highlights,
        _AdjustmentParameter.shadows => context.l10n.shadows,
        _AdjustmentParameter.contrast => context.l10n.contrast,
        _AdjustmentParameter.warmth => context.l10n.warmth,
        _AdjustmentParameter.tint => context.l10n.tint,
        _AdjustmentParameter.saturation => context.l10n.saturation,
        _AdjustmentParameter.clarity => context.l10n.clarity,
      };

  double _value(EditRecipe recipe, _AdjustmentParameter parameter) =>
      switch (parameter) {
        _AdjustmentParameter.exposure => recipe.exposure,
        _AdjustmentParameter.highlights => recipe.highlights,
        _AdjustmentParameter.shadows => recipe.shadows,
        _AdjustmentParameter.contrast => recipe.contrast,
        _AdjustmentParameter.warmth => recipe.warmth,
        _AdjustmentParameter.tint => recipe.tint,
        _AdjustmentParameter.saturation => recipe.saturation,
        _AdjustmentParameter.clarity => recipe.clarity,
      };

  EditRecipe _copyWith(
    EditRecipe recipe,
    _AdjustmentParameter parameter,
    double value,
  ) => switch (parameter) {
    _AdjustmentParameter.exposure => recipe.copyWith(exposure: value),
    _AdjustmentParameter.highlights => recipe.copyWith(highlights: value),
    _AdjustmentParameter.shadows => recipe.copyWith(shadows: value),
    _AdjustmentParameter.contrast => recipe.copyWith(contrast: value),
    _AdjustmentParameter.warmth => recipe.copyWith(warmth: value),
    _AdjustmentParameter.tint => recipe.copyWith(tint: value),
    _AdjustmentParameter.saturation => recipe.copyWith(saturation: value),
    _AdjustmentParameter.clarity => recipe.copyWith(clarity: value),
  };
}

class _CompositionTools extends StatelessWidget {
  const _CompositionTools({
    required this.enabled,
    required this.photo,
    required this.recipe,
    required this.editorSession,
    required this.onRecipeCommitted,
  });

  final bool enabled;
  final ProjectPhoto photo;
  final EditRecipe recipe;
  final EditorSession editorSession;
  final VoidCallback onRecipeCommitted;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: const Icon(Icons.crop_rotate),
      title: Text(context.l10n.composition),
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: context.l10n.rotateLeft,
              onPressed: enabled ? () => _rotate(-1) : null,
              icon: const Icon(Icons.rotate_left),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: context.l10n.rotateRight,
              onPressed: enabled ? () => _rotate(1) : null,
              icon: const Icon(Icons.rotate_right),
            ),
            const Spacer(),
            TextButton(
              onPressed: enabled && !recipe.crop.isOriginal
                  ? () => _commit(recipe.copyWith(crop: CropGeometry.original))
                  : null,
              child: Text(context.l10n.resetComposition),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _cropChip(context.l10n.originalCrop, null),
              const SizedBox(width: 8),
              _cropChip(context.l10n.cropSquare, 1),
              const SizedBox(width: 8),
              _cropChip(context.l10n.cropFourThree, 4 / 3),
              const SizedBox(width: 8),
              _cropChip(context.l10n.cropSixteenNine, 16 / 9),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _AdjustmentSlider(
          enabled: enabled,
          label: context.l10n.straighten,
          value: recipe.crop.straightenDegrees / 45,
          onStart: editorSession.beginAdjustment,
          onChanged: (value) => editorSession.preview(
            recipe.copyWith(
              crop: recipe.crop.copyWith(straightenDegrees: value * 45),
            ),
          ),
          onEnd: () {
            editorSession.commitAdjustment();
            onRecipeCommitted();
          },
        ),
      ],
    );
  }

  Widget _cropChip(String label, double? targetAspectRatio) {
    return ActionChip(
      label: Text(label),
      onPressed: enabled
          ? () {
              final crop = targetAspectRatio == null
                  ? recipe.crop.copyWith(left: 0, top: 0, right: 1, bottom: 1)
                  : _centeredCrop(targetAspectRatio);
              _commit(recipe.copyWith(crop: crop));
            }
          : null,
    );
  }

  CropGeometry _centeredCrop(double targetAspectRatio) {
    final swapsAxes = photo.orientation >= 5;
    final width = swapsAxes ? photo.pixelHeight : photo.pixelWidth;
    final height = swapsAxes ? photo.pixelWidth : photo.pixelHeight;
    return recipe.crop.centeredForAspect(
      sourceWidth: width > 0 ? width : 4,
      sourceHeight: height > 0 ? height : 3,
      targetAspectRatio: targetAspectRatio,
    );
  }

  void _rotate(int delta) {
    final turns = (recipe.crop.quarterTurns + delta) % 4;
    _commit(recipe.copyWith(crop: recipe.crop.copyWith(quarterTurns: turns)));
  }

  void _commit(EditRecipe next) {
    editorSession.apply(next);
    onRecipeCommitted();
  }
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
        if (label.isNotEmpty) SizedBox(width: 88, child: Text(label)),
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
