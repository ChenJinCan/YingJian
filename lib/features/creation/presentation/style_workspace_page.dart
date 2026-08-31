import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/features/creation/domain/creation_intent.dart';
import 'package:yingjian/features/editor/application/ai_edit_planner.dart';
import 'package:yingjian/features/editor/application/batch_photo_exporter.dart';
import 'package:yingjian/features/editor/application/meta_op_capabilities_provider.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/l10n/l10n.dart';

class StyleWorkspacePage extends StatefulWidget {
  const StyleWorkspacePage({required this.intent, this.projectId, super.key});

  final CreationIntent intent;
  final String? projectId;

  @override
  State<StyleWorkspacePage> createState() => _StyleWorkspacePageState();
}

class _StyleWorkspacePageState extends State<StyleWorkspacePage> {
  PhotoProjectStore? _store;
  PhotoProjectSession? _session;
  PhotoSharer? _photoSharer;
  Future<PhotoProject?>? _project;
  PlatformMetaOpCapabilities? _capabilities;
  late List<_StyleChoice> _officialStyles;
  _StyleChoice? _aiStyle;
  late String _selectedStyleId;
  bool _savingStyle = false;
  bool _applying = false;
  bool _styleApplied = false;
  bool _exporting = false;
  bool _sharing = false;
  bool _preparingShare = false;
  bool _continuingStyle = false;
  PhotoExportStage _exportStage = PhotoExportStage.preparing;
  bool _explainedPhotoPermission = false;
  bool _photoPermissionDenied = false;
  EditRecipe? _renderedPreviewRecipe;
  EditRecipe? _failedPreviewRecipe;
  int _previewRetryToken = 0;
  int _previewSelectionGeneration = 0;
  BoundedBatchPhotoExporter? _batchExporter;
  Future<BatchExportSummary>? _batchCompletion;
  Future<void>? _shareCompletion;
  Future<void>? _continueStyleCompletion;
  PhotoPreparation? _activeSharePreparation;
  BatchExportSummary? _exportSummary;
  final Map<String, String> _ownedSharePathsByPhotoId = {};
  final Set<String> _supersededSharePaths = {};

  bool get _interactionLocked =>
      _savingStyle || _applying || _exporting || _sharing || _continuingStyle;

  List<_StyleChoice> get _styles => [..._officialStyles, ?_aiStyle];

  _StyleChoice get _selectedStyle => _styles.firstWhere(
    (style) => style.id == _selectedStyleId,
    orElse: () => _officialStyles.first,
  );

  EditRecipe _projectedStyleRecipe(_StyleChoice style) {
    if (widget.intent != CreationIntent.apply || _session?.project == null) {
      return style.recipe;
    }
    return _session!.projectCreationStyle(style.recipe);
  }

  bool get _selectedPreviewReady =>
      _renderedPreviewRecipe == _projectedStyleRecipe(_selectedStyle) &&
      _failedPreviewRecipe != _projectedStyleRecipe(_selectedStyle);

  @override
  void initState() {
    super.initState();
    _officialStyles = _stylesFor(widget.intent);
    _selectedStyleId = _officialStyles.first.id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.read<PhotoProjectStore>();
    _photoSharer = context.read<PhotoSharer>();
    if (identical(store, _store)) return;
    _session?.dispose();
    _store = store;
    _session = PhotoProjectSession(
      importer: context.read<PhotoImporter>(),
      store: store,
      creationIntent: widget.intent,
      projectId: widget.projectId,
    );
    _project = _restoreProject(
      _session!,
      context.read<MetaOpCapabilitiesProvider>(),
    );
  }

  Future<PhotoProject?> _restoreProject(
    PhotoProjectSession session,
    MetaOpCapabilitiesProvider capabilitiesProvider,
  ) async {
    await session.restore(enforceSinglePhoto: true);
    if (session.project == null) return null;
    await BoundedBatchPhotoExporter.recoverInterrupted(session);
    var project = session.project;
    if (project == null || project.requiresUpdate) return null;
    if (project.creationIntent == CreationIntent.apply &&
        project.flowState == PhotoProjectFlowState.exported &&
        project.currentStaticStyleResult == null) {
      await session.transitionTo(PhotoProjectFlowState.editing);
      project = session.project;
    }
    _capabilities = await capabilitiesProvider.load();
    if (project != null && project.creationIntent == widget.intent) {
      _restoreSelectedStyle(project, session.editableRecipe);
      _styleApplied = project.currentStaticStyleResult != null;
      _restoreExportSummary(project);
      if (project.creationStyleId == null &&
          project.flowState == PhotoProjectFlowState.editing) {
        final style = _selectedStyle;
        await session.selectCreationStyle(
          styleId: style.id,
          styleName: style.persistedName,
          recipe: style.recipe,
        );
      }
    }
    return session.project;
  }

  void _restoreExportSummary(PhotoProject project) {
    _exportSummary = null;
    if (widget.intent != CreationIntent.apply ||
        !_styleApplied ||
        project.flowState != PhotoProjectFlowState.exported) {
      return;
    }
    final summary = BatchExportSummary.fromProject(project);
    final savedResultIsCurrent =
        summary.savedCount == 0 ||
        project.lastSuccessfulExportEditStateVersion ==
            project.editStateVersion;
    if (summary.totalCount > 0 && savedResultIsCurrent) {
      _exportSummary = summary;
    }
  }

  void _restoreSelectedStyle(PhotoProject project, EditRecipe appliedRecipe) {
    final storedId = project.creationStyleId;
    final storedName = project.creationStyleName;
    final storedRecipe = project.creationStyleRecipe;
    if (storedId != null) {
      final officialIndex = _officialStyles.indexWhere(
        (style) => style.id == storedId,
      );
      if (officialIndex >= 0) {
        final official = _officialStyles[officialIndex];
        final storedResult = project.creationResult;
        final storedRecipeIsResult =
            storedResult?.styleId == storedId &&
            storedResult?.recipe == storedRecipe;
        final styleDefinition = storedRecipeIsResult
            ? project.sharedStyle.recipe
            : storedRecipe;
        if (styleDefinition != null && styleDefinition != official.recipe) {
          _officialStyles = List.of(_officialStyles)
            ..[officialIndex] = official.copyWith(recipe: styleDefinition);
        }
        _selectedStyleId = storedId;
        return;
      }
      if (storedRecipe != null) {
        final storedResult = project.creationResult;
        final storedRecipeIsResult =
            storedResult?.styleId == storedId &&
            storedResult?.recipe == storedRecipe;
        _aiStyle = _StyleChoice(
          id: storedId,
          label: storedName == null
              ? storedId == 'ai-custom'
                    ? (context) => context.l10n.styleAiCustom
                    : (context) => context.l10n.styleSavedCustom
              : (_) => _compactStyleName(storedName),
          persistedName: storedName,
          recipe: storedRecipeIsResult
              ? project.sharedStyle.recipe
              : storedRecipe,
          previewFilter: _Filters.cool,
        );
        _selectedStyleId = storedId;
        return;
      }
    }
    final matching = _officialStyles
        .where((style) => _projectedStyleRecipe(style) == appliedRecipe)
        .firstOrNull;
    if (matching != null) {
      _selectedStyleId = matching.id;
      return;
    }
    if (appliedRecipe == EditRecipe.neutral) return;
    _aiStyle = _StyleChoice(
      id: 'saved-custom',
      label: (context) => context.l10n.styleSavedCustom,
      recipe: project.sharedStyle.recipe,
      previewFilter: _Filters.natural,
    );
    _selectedStyleId = 'saved-custom';
  }

  @override
  void dispose() {
    _batchExporter?.cancel();
    unawaited(_activeSharePreparation?.cancel());
    final session = _session;
    final batchCompletion = _batchCompletion;
    final shareCompletion = _shareCompletion;
    final continueStyleCompletion = _continueStyleCompletion;
    final pending = <Future<void>>[
      if (batchCompletion != null)
        batchCompletion.then<void>((_) {}, onError: (_, _) {}),
      if (shareCompletion != null)
        shareCompletion.then<void>((_) {}, onError: (_, _) {}),
      if (continueStyleCompletion != null)
        continueStyleCompletion.then<void>((_) {}, onError: (_, _) {}),
    ];
    if (pending.isEmpty) {
      session?.dispose();
      unawaited(_discardShareFiles());
    } else {
      unawaited(
        Future.wait(pending).whenComplete(() async {
          session?.dispose();
          await _discardShareFiles();
        }),
      );
    }
    super.dispose();
  }

  Future<void> _selectStyle(String styleId, {VoidCallback? onFailure}) async {
    final style = _styles.firstWhere((candidate) => candidate.id == styleId);
    if (_interactionLocked ||
        (_selectedStyleId == styleId &&
            _session?.project?.creationStyleName == style.persistedName &&
            _session?.project?.creationStyleRecipe == style.recipe)) {
      return;
    }
    final previousStyleId = _selectedStyleId;
    setState(() {
      _selectedStyleId = styleId;
      _styleApplied = false;
      _savingStyle = true;
      _renderedPreviewRecipe = null;
      _failedPreviewRecipe = null;
      _previewSelectionGeneration += 1;
    });
    try {
      await _session!.selectCreationStyle(
        styleId: style.id,
        styleName: style.persistedName,
        recipe: style.recipe,
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _selectedStyleId = previousStyleId;
        _renderedPreviewRecipe = null;
        _failedPreviewRecipe = null;
        _previewSelectionGeneration += 1;
      });
      onFailure?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (mounted) setState(() => _savingStyle = false);
    }
  }

  EditContext _editContext(PhotoProject project) {
    final capabilities = _capabilities!;
    final photoId = project.focusPhotoId ?? project.photos.first.id;
    final targets =
        project.targetRegistries[photoId]?.targets.values
            .where((target) => target.status == EditTargetStatus.active)
            .toList(growable: false) ??
        const <StableEditTarget>[];
    return EditContext(
      platform: capabilities.platform,
      photoIds: project.photos.map((photo) => photo.id).toSet(),
      targetIds: targets.map((target) => target.id).toSet(),
      applicability: {
        'photo',
        if (targets.any((target) => target.kind == EditTargetKind.face)) 'face',
        if (targets.any((target) => target.kind == EditTargetKind.body)) 'body',
      },
      resourceIds: project.editingResources.resources.keys.toSet(),
      resourceByteLengths: {
        for (final resource in project.editingResources.resources.values)
          resource.id: resource.byteLength,
      },
      metaOpCapabilities: capabilities,
    );
  }

  Future<void> _applyStyle(PhotoProject project) async {
    if (_interactionLocked || !_selectedPreviewReady) return;
    final style = _selectedStyle;
    setState(() => _applying = true);
    try {
      final commit = await _session!.applyCreationStyle(
        styleId: style.id,
        styleName: style.persistedName,
        recipe: style.recipe,
        context: _editContext(project),
      );
      if (!mounted) return;
      final accepted = commit.result is AcceptedEdit;
      final alreadyApplied =
          _session!.project!.currentStaticStyleResult != null;
      if (!accepted && !alreadyApplied) {
        throw StateError('The style was not admitted by the editing core');
      }
      final updatedProject = _session!.project!;
      setState(() {
        _styleApplied = updatedProject.currentStaticStyleResult != null;
        _restoreExportSummary(updatedProject);
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _onPreviewRendered(EditRecipe recipe, int selectionGeneration) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          selectionGeneration != _previewSelectionGeneration ||
          _projectedStyleRecipe(_selectedStyle) != recipe) {
        return;
      }
      setState(() {
        _renderedPreviewRecipe = recipe;
        if (_failedPreviewRecipe == recipe) _failedPreviewRecipe = null;
      });
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _onPreviewFailed(EditRecipe recipe, int selectionGeneration) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          selectionGeneration != _previewSelectionGeneration ||
          _projectedStyleRecipe(_selectedStyle) != recipe) {
        return;
      }
      setState(() => _failedPreviewRecipe = recipe);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _retryPreview() {
    if (_interactionLocked) return;
    setState(() {
      _renderedPreviewRecipe = null;
      _failedPreviewRecipe = null;
      _previewRetryToken += 1;
      _previewSelectionGeneration += 1;
    });
  }

  Future<void> _saveStyleResult() async {
    final project = _session?.project;
    if (project == null || _interactionLocked || !_styleApplied) return;
    final exporter = context.read<PhotoExporter>();
    if (!_explainedPhotoPermission &&
        exporter is PhotoLibraryPermissionAwareExporter) {
      final confirmed = await showAdaptiveDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog.adaptive(
          title: Text(context.l10n.saveToAlbum),
          content: Text(context.l10n.photoPermissionPurpose),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey('style-export-permission-continue'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.saveToAlbum),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      _explainedPhotoPermission = true;
    }
    await _exportStyleResult(project.photos.single.id);
  }

  Future<void> _exportStyleResult(String photoId) async {
    if (_exporting) return;
    final exporter = context.read<PhotoExporter>();
    final stagedExporter = exporter is PhotoExportStageAware
        ? exporter as PhotoExportStageAware
        : null;
    VoidCallback? stageListener;
    if (stagedExporter != null) {
      stageListener = () {
        if (!mounted || !_exporting) return;
        setState(() => _exportStage = stagedExporter.stage.value);
      };
      stagedExporter.stage.addListener(stageListener);
    }
    setState(() {
      _exporting = true;
      _exportStage = stagedExporter?.stage.value ?? PhotoExportStage.preparing;
      _photoPermissionDenied = false;
    });
    Future<BatchExportSummary>? completion;
    try {
      final batch = BoundedBatchPhotoExporter(
        session: _session!,
        exporter: exporter,
        options: PhotoExportOptions.defaults,
        onSharePathCreated: _ownSharePath,
      );
      _batchExporter = batch;
      completion = batch.export(photoIds: {photoId});
      _batchCompletion = completion;
      final summary = await completion;
      if (!mounted) return;
      setState(() {
        _exportSummary = BatchExportSummary(
          savedCount: summary.savedCount,
          failedCount: summary.failedCount,
          cancelledCount: summary.cancelledCount,
          sharePathsByPhotoId: Map.unmodifiable(_ownedSharePathsByPhotoId),
        );
        final error = batch.lastError;
        _photoPermissionDenied =
            error is PlatformException && error.code == 'photoAccessDenied';
      });
    } on Object {
      if (mounted) {
        setState(
          () => _exportSummary = const BatchExportSummary(
            savedCount: 0,
            failedCount: 1,
            cancelledCount: 0,
          ),
        );
      }
    } finally {
      if (stagedExporter != null && stageListener != null) {
        stagedExporter.stage.removeListener(stageListener);
      }
      if (identical(_batchCompletion, completion)) _batchCompletion = null;
      if (mounted) {
        setState(() {
          _exporting = false;
          _batchExporter = null;
        });
      }
    }
  }

  Future<void> _continueStyling() async {
    if (_interactionLocked) return;
    setState(() => _continuingStyle = true);
    final completion = _performContinueStyling();
    _continueStyleCompletion = completion;
    try {
      await completion;
      if (!mounted) return;
      setState(() {
        _styleApplied = false;
        _exportSummary = null;
        _photoPermissionDenied = false;
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (identical(_continueStyleCompletion, completion)) {
        _continueStyleCompletion = null;
      }
      if (mounted) setState(() => _continuingStyle = false);
    }
  }

  Future<void> _restorePreviousResult() async {
    if (_interactionLocked) return;
    setState(() => _continuingStyle = true);
    try {
      await _session!.restorePreviousCreationResult();
      if (!mounted) return;
      final project = _session!.project!;
      _restoreSelectedStyle(project, _session!.editableRecipe);
      setState(() {
        _styleApplied = project.currentStaticStyleResult != null;
        _photoPermissionDenied = false;
        _restoreExportSummary(project);
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (mounted) setState(() => _continuingStyle = false);
    }
  }

  Future<void> _performContinueStyling() async {
    await _session!.resumeCreationStyleSelection();
    await _discardShareFiles();
  }

  Future<void> _shareStyleResult() async {
    final project = _session?.project;
    final resultIdentity = project?.currentStaticStyleResult;
    if (_interactionLocked || project == null || resultIdentity == null) return;
    setState(() => _sharing = true);
    late final Future<void> completion;
    completion = _prepareAndShare(project, resultIdentity);
    _shareCompletion = completion;
    try {
      await completion;
    } finally {
      if (identical(_shareCompletion, completion)) {
        _shareCompletion = null;
        if (mounted) setState(() => _sharing = false);
      }
    }
  }

  Future<void> _prepareAndShare(
    PhotoProject project,
    StaticStyleResultIdentity resultIdentity,
  ) async {
    final photo = project.photos.singleWhere(
      (candidate) => candidate.id == resultIdentity.sourcePhotoId,
    );
    var path =
        _ownedSharePathsByPhotoId[photo.id] ??
        _exportSummary?.sharePathsByPhotoId[photo.id];
    if (path == null || path.isEmpty) {
      final exporter = context.read<PhotoExporter>();
      if (exporter is! PhotoResultPreparer) return;
      final preparation = (exporter as PhotoResultPreparer).prepareCanonical(
        photo: photo,
        recipe: resultIdentity.recipe,
        editState: project.renderStateFor(
          photo.id,
          recipe: resultIdentity.recipe,
        ),
        editContext: _editContext(project),
        options: PhotoExportOptions.defaults,
      );
      _activeSharePreparation = preparation;
      if (mounted) setState(() => _preparingShare = true);
      try {
        final prepared = await preparation.result;
        if (!mounted ||
            _session?.project?.currentStaticStyleResult != resultIdentity) {
          await _photoSharer?.discard(localPaths: [prepared.localPath]);
          return;
        }
        _ownSharePath(photo.id, prepared.localPath);
        path = prepared.localPath;
      } on PhotoPreparationCanceled {
        return;
      } on Object {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.photoResultShareFailed)),
        );
        return;
      } finally {
        if (identical(_activeSharePreparation, preparation)) {
          _activeSharePreparation = null;
          if (mounted) setState(() => _preparingShare = false);
        }
      }
    }
    if (path.isEmpty || !mounted) return;
    final summary = _exportSummary;
    final saved = summary?.savedCount == 1 && summary?.failedCount == 0;
    await _performShare(_photoSharer!, [path], saved: saved);
  }

  Future<void> _cancelSharePreparation() async {
    await _activeSharePreparation?.cancel();
  }

  Future<void> _performShare(
    PhotoSharer sharer,
    List<String> paths, {
    required bool saved,
  }) async {
    try {
      final outcome = await sharer.share(localPaths: paths);
      if (outcome == PhotoShareOutcome.completed) {
        final transferredPaths = paths.toSet();
        _ownedSharePathsByPhotoId.removeWhere(
          (_, path) => transferredPaths.contains(path),
        );
        final summary = _exportSummary;
        if (mounted && summary != null) {
          setState(
            () => _exportSummary = BatchExportSummary(
              savedCount: summary.savedCount,
              failedCount: summary.failedCount,
              cancelledCount: summary.cancelledCount,
              sharePathsByPhotoId: Map.unmodifiable(_ownedSharePathsByPhotoId),
            ),
          );
        }
      }
      if (!mounted) return;
      final message = switch (outcome) {
        PhotoShareOutcome.completed => context.l10n.photoShareCompleted,
        PhotoShareOutcome.canceled =>
          saved
              ? context.l10n.photoShareCanceled
              : context.l10n.photoResultShareCanceled,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Object {
      _invalidateSharePaths(paths);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? context.l10n.photoShareFailed
                : context.l10n.photoResultShareFailed,
          ),
        ),
      );
    }
  }

  void _invalidateSharePaths(Iterable<String> paths) {
    final invalidPaths = paths.where((path) => path.isNotEmpty).toSet();
    if (invalidPaths.isEmpty) return;
    _ownedSharePathsByPhotoId.removeWhere(
      (_, path) => invalidPaths.contains(path),
    );
    _supersededSharePaths.addAll(invalidPaths);
    final summary = _exportSummary;
    if (summary != null) {
      final retainedPaths = Map<String, String>.from(
        summary.sharePathsByPhotoId,
      )..removeWhere((_, path) => invalidPaths.contains(path));
      final replacement = BatchExportSummary(
        savedCount: summary.savedCount,
        failedCount: summary.failedCount,
        cancelledCount: summary.cancelledCount,
        sharePathsByPhotoId: Map.unmodifiable(retainedPaths),
      );
      if (mounted) {
        setState(() => _exportSummary = replacement);
      } else {
        _exportSummary = replacement;
      }
    }
    unawaited(_discardSupersededSharePaths(invalidPaths.toList()));
  }

  Future<void> _openPhotoSettings() async {
    final exporter = context.read<PhotoExporter>();
    if (exporter is PhotoLibrarySettingsOpener) {
      await (exporter as PhotoLibrarySettingsOpener).openPhotoLibrarySettings();
      if (mounted) setState(() => _photoPermissionDenied = false);
    }
  }

  void _ownSharePath(String photoId, String localPath) {
    final previous = _ownedSharePathsByPhotoId[photoId];
    _ownedSharePathsByPhotoId[photoId] = localPath;
    if (previous != null && previous != localPath) {
      _supersededSharePaths.add(previous);
      unawaited(_discardSupersededSharePaths([previous]));
    }
  }

  Future<void> _discardSupersededSharePaths(List<String> paths) async {
    if (!await _discardLocalPaths(paths)) return;
    _supersededSharePaths.removeAll(paths);
  }

  Future<void> _discardShareFiles() async {
    final entries = _ownedSharePathsByPhotoId.entries.toList();
    for (final entry in entries) {
      if (_ownedSharePathsByPhotoId[entry.key] == entry.value) {
        _ownedSharePathsByPhotoId.remove(entry.key);
        _supersededSharePaths.add(entry.value);
      }
    }
    final paths = _supersededSharePaths.toList();
    if (paths.isEmpty) return;
    if (!await _discardLocalPaths(paths)) return;
    _supersededSharePaths.removeAll(paths);
  }

  Future<bool> _discardLocalPaths(List<String> paths) async {
    try {
      await _photoSharer?.discard(localPaths: paths);
      return true;
    } on Object {
      // Best effort: the platform also removes stale temporary share files.
      return false;
    }
  }

  Future<void> _showMotionConfirmation() async {
    if (_interactionLocked) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            key: const ValueKey('motion-confirmation-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.motionConfirmationTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.motionConfirmationBody,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              Text(
                context.l10n.motionUnavailable,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                key: const ValueKey('motion-confirmation-close'),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(context.l10n.gotIt),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAiComposer() async {
    if (_interactionLocked) return;
    final project = _session?.project;
    if (project == null) return;
    final prepared = await showModalBottomSheet<_StyleChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _AiStyleComposerSheet(
        prepare: (prompt) => _prepareAiStyle(project, prompt),
      ),
    );
    if (!mounted || prepared == null) return;
    final previousAiStyle = _aiStyle;
    setState(() => _aiStyle = prepared);
    await _selectStyle(
      prepared.id,
      onFailure: () {
        if (mounted) setState(() => _aiStyle = previousAiStyle);
      },
    );
  }

  Future<_StyleChoice?> _prepareAiStyle(
    PhotoProject project,
    String prompt,
  ) async {
    final normalizedPrompt = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedPrompt.isEmpty || normalizedPrompt.length > 120) return null;
    final ids = [
      MetaOpIds.filter,
      MetaOpIds.exposure,
      MetaOpIds.warmth,
      MetaOpIds.saturation,
    ];
    final outcome = await const LocalAiEditPlanner().plan(
      AiEditPlanningRequest(
        intent: normalizedPrompt,
        baseStateVersion: project.editStateVersion,
        currentState: project.editState,
        capabilities: ids.map(
          (id) => AiMetaOpCapability.fromDefinition(
            MetaOpCatalog.standard.definition(id),
          ),
        ),
        photoAnalysis: const AiPhotoAnalysis(scene: 'unknown'),
        photoId: project.focusPhotoId ?? project.photos.first.id,
      ),
    );
    if (outcome is! AiEditProposal) return null;
    final preview = _session!.prepareMetaOpsForPreview(
      changes: outcome.changes,
      source: EditSource.ai,
      context: _editContext(project),
    );
    if (preview == null) return null;
    return _StyleChoice(
      id: 'ai-custom',
      label: (_) => _compactStyleName(normalizedPrompt),
      persistedName: normalizedPrompt,
      recipe: preview.scopedRecipe,
      previewFilter: _Filters.cool,
    );
  }

  void _retryRestore() {
    final session = _session;
    if (session == null) return;
    setState(() {
      _renderedPreviewRecipe = null;
      _failedPreviewRecipe = null;
      _previewSelectionGeneration += 1;
      _project = _restoreProject(
        session,
        context.read<MetaOpCapabilitiesProvider>(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pageKey = widget.intent == CreationIntent.apply
        ? const ValueKey('apply-style-workspace')
        : const ValueKey('motion-style-workspace');
    final showingStaticResult =
        widget.intent == CreationIntent.apply && _styleApplied;
    return PopScope(
      canPop: !_interactionLocked,
      child: Scaffold(
        key: pageKey,
        backgroundColor: AppTheme.canvas,
        appBar: AppBar(
          backgroundColor: AppTheme.canvas,
          leading: IconButton(
            key: showingStaticResult
                ? const ValueKey('style-workspace-close')
                : const ValueKey('style-workspace-back'),
            tooltip: showingStaticResult
                ? MaterialLocalizations.of(context).closeButtonTooltip
                : MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _interactionLocked
                ? null
                : () => Navigator.of(context).maybePop(),
            icon: Icon(
              showingStaticResult
                  ? Icons.close_rounded
                  : Icons.chevron_left_rounded,
            ),
          ),
          title: Text(
            widget.intent == CreationIntent.apply
                ? context.l10n.imageApplication
                : context.l10n.motionCreation,
          ),
        ),
        body: FutureBuilder<PhotoProject?>(
          future: _project,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final project = snapshot.data;
            if (snapshot.hasError ||
                project == null ||
                project.creationIntent != widget.intent) {
              return _WorkspaceFailure(
                onRetry: _retryRestore,
                onBack: () => Navigator.of(context).maybePop(),
              );
            }
            return _buildWorkspace(context, _session?.project ?? project);
          },
        ),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context, PhotoProject project) {
    final photo = project.photos.first;
    final selected = _selectedStyle;
    final textScaler = MediaQuery.textScalerOf(context);
    final stacksStyleHeader =
        MediaQuery.sizeOf(context).width < 350 || textScaler.scale(1) > 1.4;
    final styleRailHeight = 82 + textScaler.scale(16);
    final projectedRecipe = _projectedStyleRecipe(selected);
    final previewFailed = _failedPreviewRecipe == projectedRecipe;
    final previewStatus = previewFailed
        ? context.l10n.stylePreviewFailedShowingOriginal
        : _styleApplied
        ? context.l10n.styleApplied
        : _selectedPreviewReady
        ? context.l10n.stylePreviewReady
        : context.l10n.preparingStylePreview;
    final previewSelectionGeneration = _previewSelectionGeneration;
    final styleSummary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.currentStyle,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 2),
        Text(
          selected.label(context),
          key: const ValueKey('current-style-name'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
    final aiEntry = stacksStyleHeader
        ? TextButton(
            key: const ValueKey('style-ai-entry'),
            onPressed: _interactionLocked ? null : _showAiComposer,
            child: Text(context.l10n.aiDefineStyle),
          )
        : TextButton.icon(
            key: const ValueKey('style-ai-entry'),
            onPressed: _interactionLocked ? null : _showAiComposer,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(context.l10n.aiDefineStyle),
          );
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: ColoredBox(
                  color: Colors.black,
                  child: Semantics(
                    key: const ValueKey('style-workspace-source-photo'),
                    image: true,
                    label:
                        '${context.l10n.photoPreviewArea}, '
                        '${selected.label(context)}, '
                        '$previewStatus',
                    child: NativePhotoPreview(
                      sourcePath: photo.localPath,
                      sourceId: photo.id,
                      recipe: projectedRecipe,
                      renderer: context.read<PhotoPreviewRenderer>(),
                      editContext: _editContext(project),
                      retryToken: _previewRetryToken,
                      allowLegacyColorFallback: false,
                      preserveLastFrameOnUpdateFailure: true,
                      onRendered: (recipe) => _onPreviewRendered(
                        recipe,
                        previewSelectionGeneration,
                      ),
                      onRenderFailed: (recipe) =>
                          _onPreviewFailed(recipe, previewSelectionGeneration),
                      errorBuilder: (_) => Image.file(
                        File(photo.localPath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            Center(child: Text(context.l10n.photoLoadFailed)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 292),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF151719),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(color: Color(0xFF2B2D2F), width: 0.5),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: widget.intent == CreationIntent.apply && _styleApplied
                      ? _buildStaticResultControls(context, project, selected)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (stacksStyleHeader)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  styleSummary,
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: aiEntry,
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  Expanded(child: styleSummary),
                                  aiEntry,
                                ],
                              ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: styleRailHeight,
                              child: ListView.separated(
                                key: const ValueKey('style-options'),
                                scrollDirection: Axis.horizontal,
                                itemCount: _styles.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final style = _styles[index];
                                  return _StyleOption(
                                    key: ValueKey('style-option-${style.id}'),
                                    style: style,
                                    sourcePath: photo.localPath,
                                    selected: style.id == selected.id,
                                    onTap: _interactionLocked
                                        ? null
                                        : () =>
                                              unawaited(_selectStyle(style.id)),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (widget.intent == CreationIntent.apply &&
                                previewFailed) ...[
                              Semantics(
                                liveRegion: true,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        context.l10n.effectPreviewUnavailable,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      key: const ValueKey(
                                        'style-preview-retry',
                                      ),
                                      onPressed: _interactionLocked
                                          ? null
                                          : _retryPreview,
                                      child: Text(context.l10n.retry),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            FilledButton(
                              key: widget.intent == CreationIntent.apply
                                  ? const ValueKey('apply-style-primary-action')
                                  : const ValueKey(
                                      'motion-style-primary-action',
                                    ),
                              onPressed:
                                  _interactionLocked ||
                                      (widget.intent == CreationIntent.apply &&
                                          !_selectedPreviewReady)
                                  ? null
                                  : widget.intent == CreationIntent.apply
                                  ? () => _applyStyle(project)
                                  : _showMotionConfirmation,
                              child: _applying
                                  ? Text(context.l10n.applyingStyle)
                                  : Text(
                                      widget.intent == CreationIntent.apply
                                          ? context.l10n.applyStyle
                                          : context.l10n.generateMotion,
                                    ),
                            ),
                            if (widget.intent == CreationIntent.apply &&
                                project.recoverableStaticStyleResult != null &&
                                project.currentStaticStyleResult == null) ...[
                              const SizedBox(height: 4),
                              TextButton(
                                key: const ValueKey(
                                  'style-restore-previous-result',
                                ),
                                onPressed: _interactionLocked
                                    ? null
                                    : _restorePreviousResult,
                                child: Text(context.l10n.restorePreviousResult),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaticResultControls(
    BuildContext context,
    PhotoProject project,
    _StyleChoice selected,
  ) {
    final summary = _exportSummary;
    final saved = summary?.savedCount == 1 && summary?.failedCount == 0;
    final failed = summary != null && !saved;
    final sharingSupported = _capabilities?.platform == EditPlatform.ios;
    final canShare =
        sharingSupported &&
        (summary?.canShare == true ||
            context.read<PhotoExporter>() is PhotoResultPreparer);
    final status = _preparingShare
        ? context.l10n.preparingShare
        : _exporting
        ? _exportStage == PhotoExportStage.savingToPhotoLibrary
              ? context.l10n.savingToSystemPhotos
              : context.l10n.preparingExport
        : saved
        ? context.l10n.savedToSystemPhotos
        : failed
        ? _photoPermissionDenied
              ? context.l10n.photoPermissionPurpose
              : context.l10n.exportFailedTitle
        : context.l10n.styleApplied;
    final icon = _preparingShare
        ? Icons.hourglass_top_rounded
        : saved
        ? Icons.check_circle_rounded
        : failed
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;
    return Column(
      key: const ValueKey('style-static-result-controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.currentStyle,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 2),
        Text(
          selected.label(context),
          key: const ValueKey('current-style-name'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Semantics(
          key: const ValueKey('style-result-status'),
          container: true,
          liveRegion: true,
          excludeSemantics: true,
          label: status,
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(status)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_exporting)
          FilledButton.icon(
            key: const ValueKey('style-result-save'),
            onPressed: null,
            icon: const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: Text(status),
          )
        else if (failed && _photoPermissionDenied)
          FilledButton(
            key: const ValueKey('style-result-open-settings'),
            onPressed: _interactionLocked ? null : _openPhotoSettings,
            child: Text(context.l10n.goToSystemSettings),
          )
        else if (failed)
          FilledButton(
            key: const ValueKey('style-result-retry'),
            onPressed: _interactionLocked
                ? null
                : () => _exportStyleResult(project.photos.single.id),
            child: Text(context.l10n.retry),
          )
        else if (!saved)
          FilledButton(
            key: const ValueKey('style-result-save'),
            onPressed: _interactionLocked ? null : _saveStyleResult,
            child: Text(context.l10n.saveToAlbum),
          ),
        if (canShare) ...[
          const SizedBox(height: 4),
          if (saved)
            FilledButton.icon(
              key: const ValueKey('style-result-share'),
              onPressed: _interactionLocked ? null : _shareStyleResult,
              icon: _sharing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_outlined),
              label: Text(
                _preparingShare
                    ? context.l10n.preparingShare
                    : _sharing
                    ? context.l10n.sharingPhotos
                    : context.l10n.shareResult,
              ),
            )
          else
            OutlinedButton.icon(
              key: const ValueKey('style-result-share'),
              onPressed: _interactionLocked ? null : _shareStyleResult,
              icon: _sharing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_outlined),
              label: Text(
                _preparingShare
                    ? context.l10n.preparingShare
                    : _sharing
                    ? context.l10n.sharingPhotos
                    : context.l10n.shareResult,
              ),
            ),
          if (_preparingShare)
            TextButton(
              key: const ValueKey('style-result-cancel-preparation'),
              onPressed: _cancelSharePreparation,
              child: Text(context.l10n.cancel),
            ),
        ],
        if (!_exporting) ...[
          const SizedBox(height: 4),
          TextButton(
            key: const ValueKey('style-result-change-style'),
            onPressed: _interactionLocked ? null : _continueStyling,
            child: Text(context.l10n.changeStyle),
          ),
        ],
      ],
    );
  }
}

class _AiStyleComposerSheet extends StatefulWidget {
  const _AiStyleComposerSheet({required this.prepare});

  final Future<_StyleChoice?> Function(String prompt) prepare;

  @override
  State<_AiStyleComposerSheet> createState() => _AiStyleComposerSheetState();
}

class _AiStyleComposerSheetState extends State<_AiStyleComposerSheet> {
  late final TextEditingController _controller;
  bool _planning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _define() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || _planning) return;
    setState(() {
      _planning = true;
      _error = null;
    });
    _StyleChoice? prepared;
    try {
      prepared = await widget.prepare(prompt);
    } on Object {
      if (!mounted) return;
      setState(() {
        _planning = false;
        _error = context.l10n.styleNotUnderstood;
      });
      return;
    }
    if (!mounted) return;
    if (prepared == null) {
      setState(() {
        _planning = false;
        _error = context.l10n.styleNotUnderstood;
      });
      return;
    }
    Navigator.of(context).pop(prepared);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: const ValueKey('ai-style-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.describeStyleTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('ai-style-prompt'),
              controller: _controller,
              autofocus: true,
              enabled: !_planning,
              maxLength: 120,
              maxLines: 3,
              minLines: 2,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: context.l10n.describeStyleHint,
              ),
              onSubmitted: (_) => _define(),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              key: const ValueKey('ai-style-define'),
              onPressed: _controller.text.trim().isEmpty || _planning
                  ? null
                  : _define,
              child: _planning
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.l10n.defineStyle),
            ),
          ],
        ),
      ),
    );
  }
}

class _StyleOption extends StatelessWidget {
  const _StyleOption({
    required this.style,
    required this.sourcePath,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final _StyleChoice style;
  final String sourcePath;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    selected: selected,
    label: style.label(context),
    child: SizedBox(
      width: 72,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 66,
              height: 66,
              padding: EdgeInsets.all(selected ? 2 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: selected
                    ? Border.all(color: AppTheme.gold, width: 2)
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: ColorFiltered(
                  colorFilter: style.previewFilter,
                  child: Image.file(
                    File(sourcePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xFF2C2C2E),
                      child: Icon(Icons.photo_outlined),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              style.label(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? AppTheme.softWhite : AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WorkspaceFailure extends StatelessWidget {
  const _WorkspaceFailure({required this.onRetry, required this.onBack});

  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.projectRestoreFailed),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('style-workspace-retry'),
            onPressed: onRetry,
            child: Text(context.l10n.retry),
          ),
          TextButton(onPressed: onBack, child: Text(context.l10n.cancel)),
        ],
      ),
    ),
  );
}

typedef _StyleLabel = String Function(BuildContext context);

class _StyleChoice {
  const _StyleChoice({
    required this.id,
    required this.label,
    required this.recipe,
    required this.previewFilter,
    this.persistedName,
  });

  final String id;
  final _StyleLabel label;
  final String? persistedName;
  final EditRecipe recipe;
  final ColorFilter previewFilter;

  _StyleChoice copyWith({EditRecipe? recipe}) => _StyleChoice(
    id: id,
    label: label,
    persistedName: persistedName,
    recipe: recipe ?? this.recipe,
    previewFilter: previewFilter,
  );
}

String _compactStyleName(String name) =>
    name.length > 10 ? '${name.substring(0, 10)}…' : name;

List<_StyleChoice> _stylesFor(CreationIntent intent) {
  _StyleChoice choice(
    String id,
    _StyleLabel label,
    PhotoFilter filter,
    double strength,
    ColorFilter previewFilter, {
    double exposure = 0,
    double warmth = 0,
    double saturation = 0,
    double contrast = 0,
  }) => _StyleChoice(
    id: id,
    label: label,
    recipe: EditRecipe(
      exposure: exposure,
      warmth: warmth,
      saturation: saturation,
      contrast: contrast,
      basicEditingRecipe: BasicEditingRecipe(
        filter: filter,
        filterStrength: strength,
      ),
    ),
    previewFilter: previewFilter,
  );

  if (intent == CreationIntent.motion) {
    return [
      choice(
        'natural',
        (c) => c.l10n.styleNatural,
        PhotoFilter.clean,
        38,
        _Filters.natural,
      ),
      choice(
        'breeze',
        (c) => c.l10n.styleBreeze,
        PhotoFilter.coolAir,
        30,
        _Filters.cool,
      ),
      choice(
        'breathe',
        (c) => c.l10n.styleBreathe,
        PhotoFilter.portrait,
        28,
        _Filters.soft,
      ),
      choice(
        'push',
        (c) => c.l10n.stylePushIn,
        PhotoFilter.cinematic,
        30,
        _Filters.night,
      ),
      choice(
        'flowing-light',
        (c) => c.l10n.styleFlowingLight,
        PhotoFilter.warmSun,
        34,
        _Filters.warm,
      ),
      choice(
        'cinema',
        (c) => c.l10n.styleCinema,
        PhotoFilter.cinematic,
        48,
        _Filters.cinema,
      ),
    ];
  }
  return [
    choice(
      'natural',
      (c) => c.l10n.styleNatural,
      PhotoFilter.clean,
      42,
      _Filters.natural,
      exposure: 0.02,
    ),
    choice(
      'soft-light',
      (c) => c.l10n.styleSoftLight,
      PhotoFilter.portrait,
      38,
      _Filters.soft,
      exposure: 0.03,
    ),
    choice(
      'night',
      (c) => c.l10n.styleNight,
      PhotoFilter.night,
      48,
      _Filters.night,
      contrast: 0.05,
    ),
    choice(
      'cool',
      (c) => c.l10n.styleCool,
      PhotoFilter.coolAir,
      42,
      _Filters.cool,
      warmth: -0.05,
    ),
    choice(
      'warm-sun',
      (c) => c.l10n.styleWarmSun,
      PhotoFilter.warmSun,
      40,
      _Filters.warm,
      warmth: 0.04,
    ),
    choice(
      'mono',
      (c) => c.l10n.styleMono,
      PhotoFilter.noir,
      52,
      _Filters.mono,
    ),
  ];
}

abstract final class _Filters {
  static const natural = ColorFilter.matrix(<double>[
    1.02,
    0,
    0,
    0,
    2,
    0,
    1.01,
    0,
    0,
    2,
    0,
    0,
    0.98,
    0,
    1,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const soft = ColorFilter.matrix(<double>[
    1.03,
    0.02,
    0.01,
    0,
    4,
    0.01,
    1.01,
    0.01,
    0,
    3,
    0.01,
    0.02,
    0.96,
    0,
    2,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const night = ColorFilter.matrix(<double>[
    0.82,
    0.02,
    0.08,
    0,
    -6,
    0.01,
    0.88,
    0.08,
    0,
    -4,
    0.04,
    0.08,
    1.02,
    0,
    2,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const cool = ColorFilter.matrix(<double>[
    0.9,
    0.02,
    0.08,
    0,
    -2,
    0.02,
    0.97,
    0.05,
    0,
    1,
    0.02,
    0.06,
    1.06,
    0,
    5,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const warm = ColorFilter.matrix(<double>[
    1.06,
    0.03,
    0,
    0,
    5,
    0.01,
    1.01,
    0,
    0,
    2,
    0,
    0.01,
    0.91,
    0,
    -2,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const mono = ColorFilter.matrix(<double>[
    0.33,
    0.59,
    0.11,
    0,
    0,
    0.33,
    0.59,
    0.11,
    0,
    0,
    0.33,
    0.59,
    0.11,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const cinema = ColorFilter.matrix(<double>[
    0.9,
    0.04,
    0.08,
    0,
    -4,
    0.02,
    0.92,
    0.02,
    0,
    -2,
    0.08,
    0.02,
    0.88,
    0,
    -4,
    0,
    0,
    0,
    1,
    0,
  ]);
}
