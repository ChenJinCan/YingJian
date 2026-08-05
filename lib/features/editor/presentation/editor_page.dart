import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/features/editor/application/batch_photo_exporter.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/application/local_recommendation_coordinator.dart';
import 'package:yingjian/features/recommendations/application/photo_analysis_cache.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';
import 'package:yingjian/features/recommendations/domain/recipe_catalog.dart';
import 'package:yingjian/l10n/l10n.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  PhotoProjectSession? _session;
  PhotoSharer? _photoSharer;
  final EditorSession _editorSession = EditorSession();
  ScrollController? _photoStripController;
  int _selectedIndex = 0;
  bool _busy = false;
  bool _exporting = false;
  bool _sharing = false;
  Future<void>? _shareCompletion;
  BoundedBatchPhotoExporter? _batchExporter;
  Future<BatchExportSummary>? _batchCompletion;
  BatchExportSummary? _exportSummary;
  final Map<String, String> _ownedSharePathsByPhotoId = {};
  final Set<String> _supersededSharePaths = {};
  bool _preparingRecommendations = false;
  RecommendationPreparation? _recommendationPreparation;
  final Map<String, PortraitApplicability> _portraitApplicabilityByPhotoId = {};
  int _previewRecommendationIndex = -1;
  double? _pendingPhotoStripOffset;
  bool _savingPhotoStripPosition = false;
  PhotoAnalysisCancellationToken? _analysisCancellation;
  Future<void>? _analysisCompletion;
  Future<void> _lifecycleAnalysisUpdates = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_restartRecommendationsIfNeeded());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _analysisCancellation?.cancel();
      final analysisCompletion = _analysisCompletion;
      _lifecycleAnalysisUpdates = _lifecycleAnalysisUpdates.then((_) async {
        if (analysisCompletion != null) await analysisCompletion;
        await _markRunningAnalysesAsFallback();
      });
    }
  }

  Future<void> _markRunningAnalysesAsFallback() async {
    final session = _session;
    final project = session?.project;
    if (session == null || project == null) return;
    for (final photo in project.photos) {
      if (session.project?.id != project.id) return;
      if (session.project?.analysisStates[photo.id] !=
          PhotoAnalysisState.running) {
        continue;
      }
      try {
        await session.setPhotoAnalysisState(
          photo.id,
          PhotoAnalysisState.fallback,
        );
      } on Object {
        return;
      }
    }
  }

  Future<void> _restartRecommendationsIfNeeded() async {
    final previousCompletion = _analysisCompletion;
    if (previousCompletion != null) await previousCompletion;
    await _lifecycleAnalysisUpdates;
    final session = _session;
    if (!mounted ||
        session == null ||
        session.photos.isEmpty ||
        session.project?.flowState != PhotoProjectFlowState.analyzing) {
      return;
    }
    await _prepareRecommendations(persistAnalysisStates: true);
  }

  Future<void> _cancelAndDrainAnalysis() async {
    _analysisCancellation?.cancel();
    final analysisCompletion = _analysisCompletion;
    if (analysisCompletion != null) await analysisCompletion;
    await _lifecycleAnalysisUpdates;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _photoSharer ??= context.read<PhotoSharer>();
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
    final recoveredSummary = await BoundedBatchPhotoExporter.recoverInterrupted(
      session,
    );
    final project = session.project;
    await _restoreCachedPortraitApplicability(session);
    _photoStripController?.dispose();
    _photoStripController = ScrollController(
      initialScrollOffset: project?.groupScrollOffset ?? 0,
    );
    if (mounted && recoveredSummary != null) {
      setState(() => _exportSummary = recoveredSummary);
    }
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

  Future<void> _restoreCachedPortraitApplicability(
    PhotoProjectSession session,
  ) async {
    final project = session.project;
    if (project == null) return;
    final analyzer = context.read<PhotoAnalyzer>();
    final cache = context.read<PhotoAnalysisCache>();
    final restored = <String, PortraitApplicability>{};
    for (final photo in project.photos) {
      try {
        final analysis = await cache.read(
          projectId: project.id,
          photo: photo,
          engineIdentity: analyzer.identityFor(photo),
        );
        if (analysis != null) restored[photo.id] = analysis.portrait;
      } on Object {
        // Analysis cache is advisory; editing and export remain available.
      }
    }
    if (!mounted || session.project?.id != project.id) return;
    setState(() {
      _portraitApplicabilityByPhotoId
        ..clear()
        ..addAll(restored);
    });
  }

  Future<void> _prepareRecommendations({
    required bool persistAnalysisStates,
  }) async {
    final session = _session!;
    if (_preparingRecommendations || session.photos.isEmpty) return;
    final cancellation = PhotoAnalysisCancellationToken();
    final completion = Completer<void>();
    _analysisCompletion = completion.future;
    final projectId = session.project!.id;
    final photos = List<ProjectPhoto>.unmodifiable(session.photos);
    _analysisCancellation?.cancel();
    _analysisCancellation = cancellation;
    if (mounted) setState(() => _preparingRecommendations = true);
    try {
      final preparation =
          await LocalRecommendationCoordinator(
            analyzer: context.read<PhotoAnalyzer>(),
            cache: context.read<PhotoAnalysisCache>(),
          ).prepare(
            projectId: projectId,
            photos: photos,
            cancellation: cancellation,
            onStateChanged: persistAnalysisStates
                ? (photoId, state) async {
                    if (!_isCurrentAnalysisInput(
                      cancellation: cancellation,
                      projectId: projectId,
                      photos: photos,
                      photoId: photoId,
                    )) {
                      return;
                    }
                    await session.setPhotoAnalysisState(photoId, state);
                  }
                : null,
          );
      if (_isCurrentAnalysisRun(cancellation, projectId) &&
          persistAnalysisStates &&
          session.project?.flowState == PhotoProjectFlowState.analyzing) {
        await session.transitionTo(
          PhotoProjectFlowState.choosingRecommendation,
        );
      }
      if (_isCurrentAnalysisRun(cancellation, projectId)) {
        setState(() {
          _recommendationPreparation = preparation;
          _portraitApplicabilityByPhotoId.addAll({
            for (final entry in preparation.analyses.entries)
              entry.key: entry.value.portrait,
          });
          _previewRecommendationIndex = preparation.recommendations.isEmpty
              ? -1
              : 0;
        });
      }
    } finally {
      completion.complete();
      if (identical(_analysisCompletion, completion.future)) {
        _analysisCompletion = null;
      }
      if (identical(_analysisCancellation, cancellation)) {
        _analysisCancellation = null;
      }
      if (mounted) setState(() => _preparingRecommendations = false);
    }
  }

  bool _isCurrentAnalysisRun(
    PhotoAnalysisCancellationToken cancellation,
    String projectId,
  ) =>
      mounted &&
      !cancellation.isCancelled &&
      identical(_analysisCancellation, cancellation) &&
      _session?.project?.id == projectId;

  bool _isCurrentAnalysisInput({
    required PhotoAnalysisCancellationToken cancellation,
    required String projectId,
    required List<ProjectPhoto> photos,
    required String photoId,
  }) {
    if (!mounted ||
        cancellation.isCancelled ||
        !identical(_analysisCancellation, cancellation) ||
        _session?.project?.id != projectId) {
      return false;
    }
    final expected = photos.where((photo) => photo.id == photoId).firstOrNull;
    final current = _session!.photos
        .where((photo) => photo.id == photoId)
        .firstOrNull;
    return expected != null && current == expected;
  }

  Future<void> _selectRecommendation(LocalRecommendation recommendation) async {
    if (_exportSummary != null || _exporting || _sharing) return;
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
    if (_exportSummary != null || _exporting || _sharing) return;
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
    if (_exportSummary != null || _exporting || _sharing) return;
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
    if (_exportSummary != null || _exporting || _sharing) return;
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
    if (_exportSummary != null || _exporting || _sharing) return;
    _editorSession.load(EditRecipe.neutral);
    await _persistRecipe();
  }

  Future<void> _syncCurrentPhotoAdjustmentsToGroup() async {
    if (_exportSummary != null || _exporting || _sharing) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.syncGroupConfirmationTitle),
            content: Text(context.l10n.syncGroupConfirmationMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.syncGroupAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await _session!.syncCurrentPhotoAdjustmentsToGroup();
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

  void _savePhotoStripPosition() {
    final controller = _photoStripController;
    if (controller == null || !controller.hasClients) return;
    _pendingPhotoStripOffset = controller.offset;
    if (_savingPhotoStripPosition) return;
    _savingPhotoStripPosition = true;
    unawaited(_drainPhotoStripPositionSaves());
  }

  Future<void> _drainPhotoStripPositionSaves() async {
    while (mounted && _pendingPhotoStripOffset != null) {
      final offset = _pendingPhotoStripOffset!;
      _pendingPhotoStripOffset = null;
      try {
        await _session!.setGroupScrollOffset(offset);
      } on Object {
        _pendingPhotoStripOffset = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.projectSaveFailed)),
          );
        }
        break;
      }
    }
    _savingPhotoStripPosition = false;
  }

  Future<void> _setEditingScope(ProjectEditingScope scope) async {
    if (_exportSummary != null || _exporting || _sharing) return;
    final session = _session!;
    final photo = session.photos[_selectedIndex];
    try {
      await session.setEditingScope(
        scope,
        photoId: scope == ProjectEditingScope.currentPhoto ? photo.id : null,
      );
      _editorSession.load(session.editableRecipe);
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
    if (_exportSummary != null || _exporting || _sharing) return;
    final analysisCache = context.read<PhotoAnalysisCache>();
    final confirmed = await _confirm(
      title: context.l10n.removePhoto,
      message: context.l10n.removePhotoConfirmation,
    );
    if (!confirmed) {
      return;
    }
    final projectId = _session!.project!.id;
    try {
      await _cancelAndDrainAnalysis();
      await _session!.removePhoto(photo.id);
      await analysisCache.clearPhoto(projectId: projectId, photoId: photo.id);
      _portraitApplicabilityByPhotoId.remove(photo.id);
      final focusPhotoId = _session!.project?.focusPhotoId;
      if (focusPhotoId != null) {
        _selectedIndex = _session!.photos.indexWhere(
          (candidate) => candidate.id == focusPhotoId,
        );
      } else {
        _selectedIndex = 0;
      }
      _editorSession.load(_session!.editableRecipe);
      unawaited(_restartRecommendationsIfNeeded());
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    }
  }

  Future<void> _deleteProject() async {
    if (_exporting || _sharing) return;
    final analysisCache = context.read<PhotoAnalysisCache>();
    final confirmed = await _confirm(
      title: context.l10n.deleteProject,
      message: context.l10n.deleteProjectConfirmation,
    );
    if (!confirmed) {
      return;
    }
    final projectId = _session!.project!.id;
    try {
      await _cancelAndDrainAnalysis();
      await _session!.deleteProject();
      await analysisCache.clearProject(projectId);
      _portraitApplicabilityByPhotoId.clear();
      await _discardShareFiles();
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
    if (_exportSummary != null || _exporting || _sharing) return;
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
    WidgetsBinding.instance.removeObserver(this);
    _analysisCancellation?.cancel();
    _batchExporter?.cancel();
    final batchCompletion = _batchCompletion;
    final shareCompletion = _shareCompletion;
    final session = _session;
    final analysisCompletion = _analysisCompletion;
    final lifecycleAnalysisUpdates = _lifecycleAnalysisUpdates;
    final batchDrain = batchCompletion?.then<void>((_) {}, onError: (_, _) {});
    if (session != null) {
      final pending = <Future<void>>[
        ?analysisCompletion,
        lifecycleAnalysisUpdates,
        ?batchDrain,
      ];
      if (pending.isEmpty) {
        session.dispose();
      } else {
        unawaited(Future.wait(pending).whenComplete(session.dispose));
      }
    }
    _editorSession.dispose();
    _photoStripController?.dispose();
    final cleanupPrerequisites = <Future<void>>[
      if (batchCompletion != null)
        batchCompletion.then<void>((_) {}, onError: (_, _) {}),
      if (shareCompletion != null)
        shareCompletion.then<void>((_) {}, onError: (_, _) {}),
    ];
    if (cleanupPrerequisites.isEmpty) {
      unawaited(_discardShareFiles());
    } else {
      unawaited(
        Future.wait(cleanupPrerequisites).whenComplete(_discardShareFiles),
      );
    }
    super.dispose();
  }

  Future<void> _exportBatch({bool retryFailuresOnly = false}) async {
    if (_exporting ||
        _sharing ||
        (!retryFailuresOnly && _exportSummary != null)) {
      return;
    }
    if (!retryFailuresOnly && !await _confirmBatchExport()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _exporting = true);
    final attemptPhotoIds = <String>{};
    Future<BatchExportSummary>? completion;
    try {
      final batch = BoundedBatchPhotoExporter(
        session: _session!,
        exporter: context.read<PhotoExporter>(),
        onSharePathCreated: (photoId, localPath) {
          attemptPhotoIds.add(photoId);
          _ownSharePath(photoId, localPath);
        },
      );
      _batchExporter = batch;
      completion = batch.export(retryFailuresOnly: retryFailuresOnly);
      _batchCompletion = completion;
      final summary = await completion;
      await _discardShareFiles(
        photoIds: attemptPhotoIds.difference(
          summary.sharePathsByPhotoId.keys.toSet(),
        ),
      );
      if (!mounted) {
        return;
      }
      final displaySummary = BatchExportSummary(
        savedCount: summary.savedCount,
        failedCount: summary.failedCount,
        cancelledCount: summary.cancelledCount,
        sharePathsByPhotoId: Map.unmodifiable(_ownedSharePathsByPhotoId),
      );
      setState(() => _exportSummary = displaySummary);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.exportSummary(
              summary.savedCount,
              summary.failedCount,
              summary.cancelledCount,
            ),
          ),
        ),
      );
    } on Object {
      await _discardShareFiles(photoIds: attemptPhotoIds);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.photoExportFailed)));
      }
    } finally {
      if (identical(_batchCompletion, completion)) {
        _batchCompletion = null;
      }
      if (mounted) {
        setState(() {
          _exporting = false;
          _batchExporter = null;
        });
      }
    }
  }

  Future<bool> _confirmBatchExport() async {
    final count = _session?.photos.length ?? 0;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.batchExportPhotos(count)),
            content: Text(context.l10n.exportConfirmationMessage(count)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey('export-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.startExport),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _cancelBatchExport() => _batchExporter?.cancel();

  Future<void> _shareExportedPhotos() async {
    final summary = _exportSummary;
    if (_sharing || _exporting || summary == null || !summary.canShare) return;
    final paths = <String>[
      for (final photo in _session!.photos)
        ?summary.sharePathsByPhotoId[photo.id],
    ];
    final sharer = context.read<PhotoSharer>();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _sharing = true);
    late final Future<void> completion;
    completion = _performShare(sharer: sharer, summary: summary, paths: paths);
    _shareCompletion = completion;
    try {
      await completion;
    } finally {
      if (identical(_shareCompletion, completion)) {
        _shareCompletion = null;
      }
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _performShare({
    required PhotoSharer sharer,
    required BatchExportSummary summary,
    required List<String> paths,
  }) async {
    try {
      final outcome = await sharer.share(localPaths: paths);
      if (outcome == PhotoShareOutcome.completed) {
        final transferredPaths = paths.toSet();
        _ownedSharePathsByPhotoId.removeWhere(
          (_, path) => transferredPaths.contains(path),
        );
        if (mounted) {
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
        PhotoShareOutcome.canceled => context.l10n.photoShareCanceled,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.photoShareFailed)));
      }
    }
  }

  Future<void> _continueEditing() async {
    if (_exporting || _sharing) return;
    final session = _session!;
    if (session.project?.flowState == PhotoProjectFlowState.exported) {
      await session.transitionTo(PhotoProjectFlowState.editing);
    }
    await _discardShareFiles();
    if (mounted) setState(() => _exportSummary = null);
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

  Future<void> _discardShareFiles({Set<String>? photoIds}) async {
    final entries = _ownedSharePathsByPhotoId.entries
        .where((entry) => photoIds == null || photoIds.contains(entry.key))
        .toList();
    final superseded = photoIds == null
        ? _supersededSharePaths.toList()
        : const <String>[];
    final paths = {
      ...entries.map((entry) => entry.value),
      ...superseded,
    }.toList();
    if (paths.isEmpty) return;
    final discarded = await _discardLocalPaths(paths);
    if (!discarded) return;
    for (final entry in entries) {
      if (_ownedSharePathsByPhotoId[entry.key] == entry.value) {
        _ownedSharePathsByPhotoId.remove(entry.key);
      }
    }
    _supersededSharePaths.removeAll(superseded);
  }

  Future<bool> _discardLocalPaths(List<String> paths) async {
    try {
      for (var start = 0; start < paths.length; start += 6) {
        final end = min(start + 6, paths.length);
        await _photoSharer?.discard(localPaths: paths.sublist(start, end));
      }
      return true;
    } on Object {
      // Temporary-file cleanup is best effort; iOS also cleans on next launch.
      return false;
    }
  }

  Future<void> _importPhotos() async {
    if (_busy || _exportSummary != null || _exporting || _sharing) {
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
      if (result == PhotoImportResult.canceled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.photoImportCanceled)),
        );
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
          key: const ValueKey('editor-page'),
          appBar: AppBar(
            title: Text(context.l10n.editorTitle),
            actions: photos.isEmpty
                ? null
                : [
                    IconButton(
                      tooltip: context.l10n.deleteProject,
                      onPressed: _exporting || _sharing
                          ? null
                          : () => unawaited(_deleteProject()),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
          ),
          body: SafeArea(
            child: session.isRestoring
                ? Semantics(
                    liveRegion: true,
                    label: context.l10n.restoringProject,
                    child: const Center(child: CircularProgressIndicator()),
                  )
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
                    project: session.project!,
                    importFailures: session.importFailures,
                    selectedIndex: _selectedIndex,
                    busy: _busy,
                    exporting: _exporting,
                    editingEnabled:
                        session.canEdit && !_sharing && _exportSummary == null,
                    previewRecipe: previewRecipe,
                    flowState: session.flowState,
                    preparingRecommendations: _preparingRecommendations,
                    recommendations: recommendations ?? const [],
                    selectedRecommendationIndex: _previewRecommendationIndex,
                    editorSession: _editorSession,
                    portraitApplicable:
                        _portraitApplicabilityByPhotoId[photos[_selectedIndex]
                                .id] ==
                            PortraitApplicability.applicable &&
                        session.project!.editingScope ==
                            ProjectEditingScope.currentPhoto,
                    canUndo: session.canUndo,
                    canRedo: session.canRedo,
                    canSyncCurrentPhoto:
                        session.canSyncCurrentPhotoAdjustmentsToGroup,
                    photoStripController: _photoStripController ??=
                        ScrollController(
                          initialScrollOffset:
                              session.project!.groupScrollOffset,
                        ),
                    onSelected: (index) => unawaited(_selectPhoto(index)),
                    onMove: (photo, destination) =>
                        unawaited(_movePhoto(photo, destination)),
                    onRemove: (photo) => unawaited(_removePhoto(photo)),
                    onImport: _importPhotos,
                    exportSummary: _exportSummary,
                    onExport: () => unawaited(_exportBatch()),
                    onCancelExport: _cancelBatchExport,
                    onRetryExport: () =>
                        unawaited(_exportBatch(retryFailuresOnly: true)),
                    sharing: _sharing,
                    onShareExport: () => unawaited(_shareExportedPhotos()),
                    onContinueEditing: () => unawaited(_continueEditing()),
                    onRecipeCommitted: () => unawaited(_persistRecipe()),
                    onUndo: () => unawaited(_undoEdit()),
                    onRedo: () => unawaited(_redoEdit()),
                    onReset: () => unawaited(_resetEdit()),
                    onSyncCurrentPhotoToGroup: () =>
                        unawaited(_syncCurrentPhotoAdjustmentsToGroup()),
                    onPhotoStripScrollEnd: _savePhotoStripPosition,
                    onRecommendationPreviewed: (index) =>
                        setState(() => _previewRecommendationIndex = index),
                    onRecommendationSelected: (recommendation) =>
                        unawaited(_selectRecommendation(recommendation)),
                    onEditingScopeChanged: (scope) =>
                        unawaited(_setEditingScope(scope)),
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
    return Semantics(
      liveRegion: true,
      child: Center(
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
            Semantics(
              liveRegion: busy,
              label: busy ? context.l10n.importingPhotos : null,
              child: FilledButton.icon(
                key: const ValueKey('editor-select-photos'),
                onPressed: busy ? null : onImport,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  busy
                      ? context.l10n.importingPhotos
                      : context.l10n.selectPhotos,
                ),
              ),
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
    required this.project,
    required this.importFailures,
    required this.selectedIndex,
    required this.busy,
    required this.exporting,
    required this.exportSummary,
    required this.editingEnabled,
    required this.previewRecipe,
    required this.flowState,
    required this.preparingRecommendations,
    required this.recommendations,
    required this.selectedRecommendationIndex,
    required this.editorSession,
    required this.portraitApplicable,
    required this.canUndo,
    required this.canRedo,
    required this.canSyncCurrentPhoto,
    required this.photoStripController,
    required this.onSelected,
    required this.onMove,
    required this.onRemove,
    required this.onImport,
    required this.onExport,
    required this.onCancelExport,
    required this.onRetryExport,
    required this.sharing,
    required this.onShareExport,
    required this.onContinueEditing,
    required this.onRecipeCommitted,
    required this.onUndo,
    required this.onRedo,
    required this.onReset,
    required this.onSyncCurrentPhotoToGroup,
    required this.onPhotoStripScrollEnd,
    required this.onRecommendationPreviewed,
    required this.onRecommendationSelected,
    required this.onEditingScopeChanged,
  });

  final List<ProjectPhoto> photos;
  final PhotoProject project;
  final List<PhotoImportFailure> importFailures;
  final int selectedIndex;
  final bool busy;
  final bool exporting;
  final BatchExportSummary? exportSummary;
  final bool editingEnabled;
  final EditRecipe previewRecipe;
  final PhotoProjectFlowState flowState;
  final bool preparingRecommendations;
  final List<LocalRecommendation> recommendations;
  final int selectedRecommendationIndex;
  final EditorSession editorSession;
  final bool portraitApplicable;
  final bool canUndo;
  final bool canRedo;
  final bool canSyncCurrentPhoto;
  final ScrollController photoStripController;
  final ValueChanged<int> onSelected;
  final void Function(ProjectPhoto photo, int destination) onMove;
  final ValueChanged<ProjectPhoto> onRemove;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onCancelExport;
  final VoidCallback onRetryExport;
  final bool sharing;
  final VoidCallback onShareExport;
  final VoidCallback onContinueEditing;
  final VoidCallback onRecipeCommitted;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onReset;
  final VoidCallback onSyncCurrentPhotoToGroup;
  final VoidCallback onPhotoStripScrollEnd;
  final ValueChanged<int> onRecommendationPreviewed;
  final ValueChanged<LocalRecommendation> onRecommendationSelected;
  final ValueChanged<ProjectEditingScope> onEditingScopeChanged;

  @override
  Widget build(BuildContext context) {
    final selected = photos[selectedIndex];
    final recipe = editorSession.recipe;
    final previewRenderer = context.read<PhotoPreviewRenderer>();
    final hasPhotosReadyToExport = project.exportStates.values.any(
      (state) => state == PhotoExportState.notQueued,
    );
    final interactionsBlocked = exporting || sharing || exportSummary != null;
    return ListView(
      key: const Key('photo-workspace-scroll'),
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
                    recommendationMode:
                        flowState ==
                        PhotoProjectFlowState.choosingRecommendation,
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
              onPressed: selectedIndex == 0 || interactionsBlocked
                  ? null
                  : () => onMove(selected, selectedIndex - 1),
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              tooltip: context.l10n.movePhotoLater,
              onPressed:
                  selectedIndex == photos.length - 1 || interactionsBlocked
                  ? null
                  : () => onMove(selected, selectedIndex + 1),
              icon: const Icon(Icons.arrow_forward),
            ),
            IconButton(
              tooltip: context.l10n.removePhoto,
              onPressed: interactionsBlocked ? null : () => onRemove(selected),
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
        Text(
          context.l10n.photoPositionAndScope(
            selectedIndex + 1,
            photos.length,
            project.editingScope == ProjectEditingScope.group
                ? context.l10n.editWholeGroup
                : context.l10n.editCurrentPhoto,
          ),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        if (photos.length > 1 && editingEnabled) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ProjectEditingScope>(
              segments: [
                ButtonSegment(
                  value: ProjectEditingScope.group,
                  icon: const Icon(Icons.collections_outlined),
                  label: Text(context.l10n.editWholeGroup),
                ),
                ButtonSegment(
                  value: ProjectEditingScope.currentPhoto,
                  icon: const Icon(Icons.photo_outlined),
                  label: Text(context.l10n.editCurrentPhoto),
                ),
              ],
              selected: {project.editingScope},
              onSelectionChanged: (selection) =>
                  onEditingScopeChanged(selection.single),
            ),
          ),
        ],
        const SizedBox(height: 16),
        NotificationListener<ScrollEndNotification>(
          key: const Key('photo-strip-scroll'),
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.horizontal) {
              onPhotoStripScrollEnd();
            }
            return false;
          },
          child: SizedBox(
            height: 112,
            child: ListView.separated(
              controller: photoStripController,
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final photo = photos[index];
                final status = _photoStatus(context, project, photo.id);
                return Semantics(
                  selected: index == selectedIndex,
                  button: true,
                  label: '${photo.originalName}, ${status.$2}',
                  child: InkWell(
                    onTap: () => onSelected(index),
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 88,
                      child: Column(
                        children: [
                          Container(
                            width: 68,
                            height: 68,
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
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(status.$1, size: 13),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  status.$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
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
          portraitAvailable: portraitApplicable,
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
        if (canSyncCurrentPhoto) ...[
          OutlinedButton.icon(
            onPressed: editingEnabled ? onSyncCurrentPhotoToGroup : null,
            icon: const Icon(Icons.sync_alt),
            label: Text(context.l10n.syncCurrentAdjustments),
          ),
          const SizedBox(height: 8),
        ],
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
        if (exportSummary != null) ...[
          _ExportSummaryCard(
            summary: exportSummary!,
            exporting: exporting,
            sharing: sharing,
            onRetry: onRetryExport,
            onShare: onShareExport,
            onContinueEditing: onContinueEditing,
          ),
          const SizedBox(height: 12),
        ],
        Semantics(
          container: exporting,
          liveRegion: exporting,
          label: exporting ? context.l10n.exportingPhotos : null,
          child: FilledButton.icon(
            key: const ValueKey('editor-batch-export'),
            onPressed:
                interactionsBlocked ||
                    !editingEnabled ||
                    !hasPhotosReadyToExport
                ? null
                : onExport,
            icon: exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            label: Text(
              exporting
                  ? context.l10n.exportingPhotos
                  : context.l10n.batchExportPhotos(photos.length),
            ),
          ),
        ),
        if (exporting) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onCancelExport,
            icon: const Icon(Icons.cancel_outlined),
            label: Text(context.l10n.cancelExport),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed:
              busy ||
                  interactionsBlocked ||
                  photos.length >= PhotoProject.maxPhotoCount
              ? null
              : onImport,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(context.l10n.addPhotos),
        ),
      ],
    );
  }
}

class _ExportSummaryCard extends StatelessWidget {
  const _ExportSummaryCard({
    required this.summary,
    required this.exporting,
    required this.sharing,
    required this.onRetry,
    required this.onShare,
    required this.onContinueEditing,
  });

  final BatchExportSummary summary;
  final bool exporting;
  final bool sharing;
  final VoidCallback onRetry;
  final VoidCallback onShare;
  final VoidCallback onContinueEditing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.exportSummary(
                  summary.savedCount,
                  summary.failedCount,
                  summary.cancelledCount,
                ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              if (summary.hasRetryableItems)
                FilledButton.tonal(
                  onPressed: exporting || sharing ? null : onRetry,
                  child: Text(context.l10n.retryFailedPhotos),
                ),
              if (summary.canShare)
                FilledButton.icon(
                  onPressed: exporting || sharing ? null : onShare,
                  icon: sharing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_outlined),
                  label: Text(
                    sharing
                        ? context.l10n.sharingPhotos
                        : context.l10n.shareSavedPhotos,
                  ),
                ),
              TextButton(
                onPressed: exporting || sharing ? null : onContinueEditing,
                child: Text(context.l10n.continueEditing),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

(IconData, String) _photoStatus(
  BuildContext context,
  PhotoProject project,
  String photoId,
) {
  if (project.exportStates[photoId] == PhotoExportState.queued) {
    return (Icons.outbox_outlined, context.l10n.photoStatusQueued);
  }
  if (project.analysisStates[photoId] == PhotoAnalysisState.failed) {
    return (Icons.error_outline, context.l10n.photoStatusFailed);
  }
  if (project.photoOverrides.containsKey(photoId)) {
    return (Icons.tune, context.l10n.photoStatusOverridden);
  }
  if (project.adaptiveCompensations.containsKey(photoId)) {
    return (Icons.auto_fix_high, context.l10n.photoStatusAutoCompensated);
  }
  return (Icons.hourglass_empty, context.l10n.photoStatusUnprocessed);
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
              height: 166,
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
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
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
                            Text(
                              _recommendationReason(
                                context,
                                recommendation.reason,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
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
                    _usesSafeFallback(selected.reason)
                        ? context.l10n.safeFallbackNotice
                        : context.l10n.localAnalysisNotice,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('recommendation-use'),
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

  static bool _usesSafeFallback(RecommendationReason reason) =>
      switch (reason) {
        RecommendationReason.balancedLocalFallback ||
        RecommendationReason.warmLocalFallback ||
        RecommendationReason.texturedLocalFallback ||
        RecommendationReason.protectsUncertainInput => true,
        _ => false,
      };

  static String _recommendationReason(
    BuildContext context,
    RecommendationReason reason,
  ) => switch (reason) {
    RecommendationReason.balancedLocalFallback =>
      context.l10n.recommendationReasonBalancedFallback,
    RecommendationReason.warmLocalFallback =>
      context.l10n.recommendationReasonWarmFallback,
    RecommendationReason.texturedLocalFallback =>
      context.l10n.recommendationReasonTexturedFallback,
    RecommendationReason.protectsUncertainInput =>
      context.l10n.recommendationReasonProtectsUncertain,
    RecommendationReason.protectsTexture =>
      context.l10n.recommendationReasonProtectsTexture,
    RecommendationReason.correctsExposure =>
      context.l10n.recommendationReasonCorrectsExposure,
    RecommendationReason.correctsWhiteBalance =>
      context.l10n.recommendationReasonCorrectsWhiteBalance,
  };
}

class _ImportFailures extends StatelessWidget {
  const _ImportFailures({required this.failures});

  final List<PhotoImportFailure> failures;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Card(
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
    required this.recommendationMode,
    super.key,
  });

  final String sourcePath;
  final EditRecipe recipe;
  final PhotoPreviewRenderer renderer;
  final bool recommendationMode;

  @override
  State<_BeforeAfterPreview> createState() => _BeforeAfterPreviewState();
}

class _BeforeAfterPreviewState extends State<_BeforeAfterPreview> {
  bool _showOriginal = false;
  int _retryToken = 0;

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
          retryToken: _retryToken,
          errorBuilder: (context) => Semantics(
            liveRegion: true,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.recommendationMode
                          ? context.l10n.recommendationPreviewUnavailable
                          : !widget.recipe.crop.isOriginal
                          ? context.l10n.compositionPreviewUnavailable
                          : !widget.recipe.isLegacyColorOnly
                          ? context.l10n.effectPreviewUnavailable
                          : context.l10n.photoLoadFailed,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      key: const ValueKey('photo-preview-retry'),
                      onPressed: () => setState(() => _retryToken += 1),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(96, 48),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: Text(context.l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
  portraitRetouch,
}

class _AdjustmentToolStrip extends StatefulWidget {
  const _AdjustmentToolStrip({
    required this.enabled,
    required this.extended,
    required this.portraitAvailable,
    required this.recipe,
    required this.editorSession,
    required this.onRecipeCommitted,
  });

  final bool enabled;
  final bool extended;
  final bool portraitAvailable;
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
        ? <_AdjustmentParameter>[
            ..._AdjustmentParameter.values.where(
              (parameter) => parameter != _AdjustmentParameter.portraitRetouch,
            ),
            if (widget.portraitAvailable) _AdjustmentParameter.portraitRetouch,
          ]
        : const <_AdjustmentParameter>[
            _AdjustmentParameter.exposure,
            _AdjustmentParameter.contrast,
            _AdjustmentParameter.warmth,
          ];
    final selected = parameters.contains(_selected)
        ? _selected
        : parameters.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: parameters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, index) {
              final parameter = parameters[index];
              final label = _label(context, parameter);
              final isSelected = parameter == selected;
              void select() => setState(() => _selected = parameter);
              return Semantics(
                container: true,
                excludeSemantics: true,
                button: true,
                enabled: widget.enabled,
                selected: isSelected,
                label: label,
                onTap: widget.enabled ? select : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 48),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: widget.enabled ? (_) => select() : null,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _AdjustmentSlider(
          enabled: widget.enabled,
          label: '',
          semanticLabel: _label(context, selected),
          value: _value(widget.recipe, selected),
          minimum: selected == _AdjustmentParameter.portraitRetouch ? 0 : -1,
          onStart: widget.editorSession.beginAdjustment,
          onChanged: (value) => widget.editorSession.preview(
            _copyWith(widget.recipe, selected, value),
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
        _AdjustmentParameter.portraitRetouch =>
          context.l10n.naturalPortraitRetouch,
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
        _AdjustmentParameter.portraitRetouch => recipe.portraitStrength,
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
    _AdjustmentParameter.portraitRetouch => recipe.copyWith(
      portraitStrength: value,
    ),
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
          semanticLabel: context.l10n.straighten,
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
    required this.semanticLabel,
    required this.value,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    this.minimum = -1,
  });

  final bool enabled;
  final String label;
  final String semanticLabel;
  final double value;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  final double minimum;
  static const double maximum = 1;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (label.isNotEmpty) SizedBox(width: 88, child: Text(label)),
        Expanded(
          child: Semantics(
            slider: true,
            enabled: enabled,
            label: semanticLabel,
            value: '${(value * 100).round()}',
            increasedValue: value < maximum
                ? '${(_semanticValue(0.02) * 100).round()}'
                : null,
            decreasedValue: value > minimum
                ? '${(_semanticValue(-0.02) * 100).round()}'
                : null,
            onIncrease: enabled && value < maximum
                ? () => _adjustFromSemantics(0.02)
                : null,
            onDecrease: enabled && value > minimum
                ? () => _adjustFromSemantics(-0.02)
                : null,
            child: ExcludeSemantics(
              child: Slider(
                value: value,
                min: minimum,
                max: maximum,
                divisions: 100,
                label: '${(value * 100).round()}',
                semanticFormatterCallback: (value) =>
                    '${(value * 100).round()}',
                onChangeStart: enabled ? (_) => onStart() : null,
                onChanged: enabled ? onChanged : null,
                onChangeEnd: enabled ? (_) => onEnd() : null,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('${(value * 100).round()}', textAlign: TextAlign.end),
        ),
      ],
    );
  }

  double _semanticValue(double delta) =>
      (value + delta).clamp(minimum, maximum);

  void _adjustFromSemantics(double delta) {
    onStart();
    onChanged(_semanticValue(delta));
    onEnd();
  }
}
