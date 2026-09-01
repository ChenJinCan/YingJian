import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/ai_edit_planner.dart';
import 'package:yingjian/features/editor/application/batch_photo_exporter.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/application/edit_target_detection_adapter.dart';
import 'package:yingjian/features/editor/application/meta_op_capabilities_provider.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/application/speech_transcriber.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/domain/legacy_edit_recipe_adapter.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/quality_enhancement_recipe.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/targeted_portrait_recipe.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_speech_transcriber.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';
import 'package:yingjian/features/editor/presentation/visual_tracks_page.dart';
import 'package:yingjian/features/editor/presentation/voice_edit_sheet.dart';
import 'package:yingjian/features/creation/domain/creation_task.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/photo_analysis/application/photo_analysis_cache.dart';
import 'package:yingjian/features/photo_analysis/application/photo_analysis_coordinator.dart';
import 'package:yingjian/features/photo_analysis/domain/photo_analysis.dart';
import 'package:yingjian/l10n/l10n.dart';

enum EditorEntryPoint { standard, optimize, cleanup }

const _legacyBackgroundTreatments = [
  BackgroundTreatment.original,
  BackgroundTreatment.blur,
  BackgroundTreatment.white,
  BackgroundTreatment.black,
  BackgroundTreatment.warm,
  BackgroundTreatment.cool,
  BackgroundTreatment.image,
];

class EditorPage extends StatefulWidget {
  const EditorPage({
    this.speechTranscriber = const MethodChannelSpeechTranscriber(),
    this.aiEditPlanner = const LocalAiEditPlanner(),
    this.startWithImport = false,
    this.projectId,
    this.entryPoint = EditorEntryPoint.standard,
    super.key,
  });

  final SpeechTranscriber speechTranscriber;
  final AiEditPlanner aiEditPlanner;
  final bool startWithImport;
  final String? projectId;
  final EditorEntryPoint entryPoint;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  PhotoProjectSession? _session;
  PhotoSharer? _photoSharer;
  PhotoImporter? _photoImporter;
  final EditorSession _editorSession = EditorSession();
  int _selectedIndex = 0;
  bool _busy = false;
  bool _exporting = false;
  PhotoExportStage _exportStage = PhotoExportStage.preparing;
  bool _showCanvasInteractionHint = true;
  bool _sharing = false;
  Future<void>? _shareCompletion;
  BoundedBatchPhotoExporter? _batchExporter;
  Future<BatchExportSummary>? _batchCompletion;
  BatchExportSummary? _exportSummary;
  PhotoExportOptions _exportOptions = PhotoExportOptions(
    size: PhotoExportSize.longEdge,
    longEdgePixels: 2048,
    quality: PhotoExportQuality.standard,
  );
  final Map<String, String> _ownedSharePathsByPhotoId = {};
  final Set<String> _supersededSharePaths = {};
  bool _preparingAnalysis = false;
  final Map<String, LocalPhotoAnalysis> _analysisByPhotoId = {};
  final Map<String, PortraitApplicability> _portraitApplicabilityByPhotoId = {};
  final Map<String, PortraitApplicability> _faceSlimApplicabilityByPhotoId = {};
  final Map<String, PortraitDegradationReason> _faceSlimReasonByPhotoId = {};
  final Map<String, int> _faceSlimTargetCountByPhotoId = {};
  final Map<String, List<NormalizedTargetRegion>> _faceTargetRegionsByPhotoId =
      {};
  final Map<String, PortraitApplicability> _bodyApplicabilityByPhotoId = {};
  final Map<String, int> _bodyTargetCountByPhotoId = {};
  final Map<String, List<NormalizedTargetRegion>> _bodyTargetRegionsByPhotoId =
      {};
  PhotoAnalysisCancellationToken? _analysisCancellation;
  Future<void>? _analysisCompletion;
  Future<void> _lifecycleAnalysisUpdates = Future.value();
  _EditFeedback? _editFeedback;
  Timer? _editFeedbackTimer;
  _PendingManualRender? _pendingManualRender;
  final Map<String, EditRecipe> _lastRenderedRecipeByPhotoId = {};
  Future<void> _recipePersistence = Future.value();
  int _recipePersistenceJobs = 0;
  _RecipeSaveFailure? _recipeSaveFailure;
  Completer<void>? _recipeSettlement;
  bool _allowRoutePop = false;
  bool _handledStartWithImport = false;
  bool _openedEntryPoint = false;
  bool _manualToolsVisible = false;
  VisualTrackKind? _visualTrackKind;
  bool _immersivePreview = false;
  MetaOpCapabilitiesProvider? _metaOpCapabilitiesProvider;
  bool _loadedExportPreference = false;
  bool _explainedPhotoPermission = false;
  bool _photoPermissionDenied = false;
  bool _taskRouteMismatch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_restartAnalysisIfNeeded());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _editorSession.cancelAdjustment();
      _loadEditableRecipe();
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

  Future<void> _restartAnalysisIfNeeded() async {
    final previousCompletion = _analysisCompletion;
    if (previousCompletion != null) await previousCompletion;
    await _lifecycleAnalysisUpdates;
    final session = _session;
    if (!mounted ||
        session == null ||
        session.photos.isEmpty ||
        !(session.project?.analysisStates.values.any(
              (state) => state != PhotoAnalysisState.ready,
            ) ??
            false)) {
      return;
    }
    await _preparePhotoAnalysis(persistAnalysisStates: true);
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
    if (!_loadedExportPreference) {
      _loadedExportPreference = true;
      final preference = context.read<AppSettings>().exportQuality;
      _exportOptions = PhotoExportOptions(
        size: PhotoExportSize.longEdge,
        longEdgePixels: 2048,
        quality: switch (preference) {
          AppExportQuality.high => PhotoExportQuality.high,
          AppExportQuality.standard => PhotoExportQuality.standard,
          AppExportQuality.compact => PhotoExportQuality.compact,
        },
      );
    }
    _photoSharer ??= context.read<PhotoSharer>();
    _photoImporter ??= context.read<PhotoImporter>();
    final capabilitiesProvider = context.read<MetaOpCapabilitiesProvider>();
    if (!identical(_metaOpCapabilitiesProvider, capabilitiesProvider)) {
      _metaOpCapabilitiesProvider = capabilitiesProvider;
      unawaited(_loadMetaOpCapabilities(capabilitiesProvider));
    }
    if (_session != null) {
      return;
    }
    final session = PhotoProjectSession(
      importer: context.read<PhotoImporter>(),
      store: context.read<PhotoProjectStore>(),
      projectId: widget.projectId,
    );
    _session = session;
    unawaited(_initializeSession(session));
  }

  Future<void> _loadMetaOpCapabilities(
    MetaOpCapabilitiesProvider provider,
  ) async {
    try {
      final capabilities = await provider.load();
      if (!mounted || !identical(_metaOpCapabilitiesProvider, provider)) {
        return;
      }
      _editorSession.setPlatformCapabilities(capabilities);
    } on Object {
      // The bundled declaration remains the conservative offline fallback.
    }
  }

  Future<void> _initializeSession(PhotoProjectSession session) async {
    await _restoreProject(session);
    if (!mounted || _taskRouteMismatch) return;
    _openEntryPointIfNeeded();
    if (!mounted ||
        _handledStartWithImport ||
        !widget.startWithImport ||
        session.photos.isNotEmpty) {
      return;
    }
    _handledStartWithImport = true;
    await _importPhotos();
  }

  void _openEntryPointIfNeeded() {
    if (!mounted ||
        _openedEntryPoint ||
        widget.entryPoint == EditorEntryPoint.standard ||
        _session?.project == null) {
      return;
    }
    setState(() {
      _openedEntryPoint = true;
      _manualToolsVisible = true;
      _visualTrackKind = null;
    });
  }

  Future<void> _restoreProject(PhotoProjectSession session) async {
    await session.restore(enforceSinglePhoto: true);
    final project = session.project;
    final expectedTask = _expectedCreationTask;
    if (project != null &&
        expectedTask != null &&
        project.creationTask != expectedTask) {
      if (mounted) setState(() => _taskRouteMismatch = true);
      return;
    }
    await BoundedBatchPhotoExporter.recoverInterrupted(session);
    if (session.project?.flowState == PhotoProjectFlowState.exported) {
      await session.transitionTo(PhotoProjectFlowState.editing);
    }
    final restoredProject = session.project;
    final analysisRefreshRequired = await _restoreCachedPortraitApplicability(
      session,
    );
    _loadEditableRecipe();
    final focusPhotoId = restoredProject?.focusPhotoId;
    if (focusPhotoId != null) {
      final focusIndex = restoredProject!.photos.indexWhere(
        (photo) => photo.id == focusPhotoId,
      );
      if (focusIndex >= 0) {
        _selectedIndex = focusIndex;
      }
    }
    if (restoredProject != null && analysisRefreshRequired) {
      unawaited(_preparePhotoAnalysis(persistAnalysisStates: true));
    }
  }

  CreationTask? get _expectedCreationTask => switch (widget.entryPoint) {
    EditorEntryPoint.standard => null,
    EditorEntryPoint.optimize => CreationTask.optimize,
    EditorEntryPoint.cleanup => CreationTask.cleanup,
  };

  void _loadEditableRecipe() {
    if (!mounted) return;
    final session = _session;
    final project = session?.project;
    final prioritized = <String>[];
    final seen = <String>{};
    if (project != null) {
      for (final operation in project.undoHistory.reversed) {
        for (final address in operation.changedAddresses) {
          if (seen.add(address.metaOpId)) prioritized.add(address.metaOpId);
        }
      }
    }
    _editorSession.load(
      session?.editableRecipe ?? EditRecipe.neutral,
      prioritizedMetaOpIds: prioritized,
    );
  }

  Future<bool> _restoreCachedPortraitApplicability(
    PhotoProjectSession session,
  ) async {
    final project = session.project;
    if (project == null) return false;
    final analyzer = context.read<PhotoAnalyzer>();
    final cache = context.read<PhotoAnalysisCache>();
    final restored = <String, PortraitApplicability>{};
    final restoredFaceSlim = <String, PortraitApplicability>{};
    final restoredFaceSlimReason = <String, PortraitDegradationReason>{};
    final restoredFaceSlimTargetCount = <String, int>{};
    final restoredFaceTargetRegions = <String, List<NormalizedTargetRegion>>{};
    final restoredBody = <String, PortraitApplicability>{};
    final restoredBodyTargetCount = <String, int>{};
    final restoredBodyTargetRegions = <String, List<NormalizedTargetRegion>>{};
    var refreshRequired = false;
    for (final photo in project.photos) {
      try {
        final analysis = await cache.read(
          projectId: project.id,
          photo: photo,
          engineIdentity: analyzer.identityFor(photo),
        );
        if (analysis != null) {
          restored[photo.id] = analysis.portrait;
          restoredFaceSlim[photo.id] = analysis.faceSlim;
          restoredFaceSlimReason[photo.id] = analysis.faceSlimReason;
          restoredFaceSlimTargetCount[photo.id] = analysis.faceSlimTargetCount;
          restoredFaceTargetRegions[photo.id] = analysis.faceTargetRegions;
          restoredBody[photo.id] = analysis.body;
          restoredBodyTargetCount[photo.id] = analysis.bodyTargetCount;
          restoredBodyTargetRegions[photo.id] = analysis.bodyTargetRegions;
          await session.reconcileEditTargets(
            photo.id,
            detectedEditTargetsFor(photo: photo, analysis: analysis),
          );
        } else {
          refreshRequired = true;
        }
      } on Object {
        // Analysis cache is advisory; editing and export remain available.
        refreshRequired = true;
      }
    }
    if (!mounted || session.project?.id != project.id) return false;
    setState(() {
      _portraitApplicabilityByPhotoId
        ..clear()
        ..addAll(restored);
      _faceSlimApplicabilityByPhotoId
        ..clear()
        ..addAll(restoredFaceSlim);
      _faceSlimReasonByPhotoId
        ..clear()
        ..addAll(restoredFaceSlimReason);
      _faceSlimTargetCountByPhotoId
        ..clear()
        ..addAll(restoredFaceSlimTargetCount);
      _faceTargetRegionsByPhotoId
        ..clear()
        ..addAll(restoredFaceTargetRegions);
      _bodyApplicabilityByPhotoId
        ..clear()
        ..addAll(restoredBody);
      _bodyTargetCountByPhotoId
        ..clear()
        ..addAll(restoredBodyTargetCount);
      _bodyTargetRegionsByPhotoId
        ..clear()
        ..addAll(restoredBodyTargetRegions);
    });
    return refreshRequired;
  }

  Future<void> _preparePhotoAnalysis({
    required bool persistAnalysisStates,
  }) async {
    final session = _session!;
    if (_preparingAnalysis || session.photos.isEmpty) return;
    final cancellation = PhotoAnalysisCancellationToken();
    final completion = Completer<void>();
    _analysisCompletion = completion.future;
    final projectId = session.project!.id;
    final photos = List<ProjectPhoto>.unmodifiable(session.photos);
    _analysisCancellation?.cancel();
    _analysisCancellation = cancellation;
    if (mounted) setState(() => _preparingAnalysis = true);
    try {
      final analyses =
          await PhotoAnalysisCoordinator(
            analyzer: context.read<PhotoAnalyzer>(),
            cache: context.read<PhotoAnalysisCache>(),
          ).analyze(
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
                    try {
                      await session.setPhotoAnalysisState(photoId, state);
                    } on Object {
                      // Capability analysis is optional and must never make a
                      // readable or editable project unavailable.
                    }
                  }
                : null,
          );
      if (_isCurrentAnalysisRun(cancellation, projectId)) {
        for (final entry in analyses.entries) {
          final photo = photos.singleWhere((photo) => photo.id == entry.key);
          try {
            await session.reconcileEditTargets(
              photo.id,
              detectedEditTargetsFor(photo: photo, analysis: entry.value),
            );
          } on Object {
            // Keep the editor usable when optional capability metadata cannot
            // be persisted (for example, a read-only future project).
          }
        }
      }
      if (_isCurrentAnalysisRun(cancellation, projectId)) {
        setState(() {
          _analysisByPhotoId.addAll(analyses);
          _portraitApplicabilityByPhotoId.addAll({
            for (final entry in analyses.entries)
              entry.key: entry.value.portrait,
          });
          _faceSlimApplicabilityByPhotoId.addAll({
            for (final entry in analyses.entries)
              entry.key: entry.value.faceSlim,
          });
          _faceSlimReasonByPhotoId.addAll({
            for (final entry in analyses.entries)
              entry.key: entry.value.faceSlimReason,
          });
          _faceSlimTargetCountByPhotoId.addAll({
            for (final entry in analyses.entries)
              entry.key: entry.value.faceSlimTargetCount,
          });
          _faceTargetRegionsByPhotoId.addAll({
            for (final entry in analyses.entries)
              entry.key: entry.value.faceTargetRegions,
          });
          _bodyApplicabilityByPhotoId.addAll({
            for (final entry in analyses.entries) entry.key: entry.value.body,
          });
          _bodyTargetCountByPhotoId.addAll({
            for (final entry in analyses.entries)
              entry.key: entry.value.bodyTargetCount,
          });
          _bodyTargetRegionsByPhotoId.addAll({
            for (final entry in analyses.entries)
              entry.key: entry.value.bodyTargetRegions,
          });
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
      if (mounted) setState(() => _preparingAnalysis = false);
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

  void _requestRecipePersistence() {
    final session = _session;
    final project = session?.project;
    if (session == null || project == null || project.photos.isEmpty) return;
    final photoId = project.focusPhotoId ?? project.photos.first.id;
    final editableRecipe = _editorSession.recipe;
    final renderedRecipe = session.previewRecipeFor(photoId, editableRecipe);
    final request = _PendingManualRender(
      photoId: photoId,
      editableRecipe: editableRecipe,
      renderedRecipe: renderedRecipe,
    );
    final previousSettlement = _recipeSettlement;
    if (previousSettlement != null && !previousSettlement.isCompleted) {
      previousSettlement.complete();
    }
    _recipeSettlement = Completer<void>();
    setState(() {
      _pendingManualRender = request;
      _recipeSaveFailure = null;
    });
    if (_lastRenderedRecipeByPhotoId[photoId] == renderedRecipe) {
      _acceptRenderedRecipe(request);
    }
  }

  void _handleRecipeRendered(String photoId, EditRecipe recipe) {
    _lastRenderedRecipeByPhotoId[photoId] = recipe;
    final request = _pendingManualRender;
    if (request != null &&
        request.photoId == photoId &&
        request.renderedRecipe == recipe) {
      _acceptRenderedRecipe(request);
    }
  }

  void _acceptRenderedRecipe(_PendingManualRender request) {
    if (!identical(_pendingManualRender, request)) return;
    setState(() => _pendingManualRender = null);
    _queueRecipePersistence(
      request.editableRecipe,
      settlement: _recipeSettlement,
    );
  }

  void _queueRecipePersistence(
    EditRecipe desiredRecipe, {
    Completer<void>? settlement,
  }) {
    setState(() => _recipePersistenceJobs += 1);
    _recipePersistence = _recipePersistence
        .then((_) => _persistRecipe(desiredRecipe))
        .whenComplete(() {
          if (!mounted) {
            if (settlement != null && !settlement.isCompleted) {
              settlement.complete();
            }
            return;
          }
          setState(() => _recipePersistenceJobs -= 1);
          if (settlement != null && !settlement.isCompleted) {
            settlement.complete();
          }
        });
  }

  void _handleRecipeRenderFailed(String photoId, EditRecipe recipe) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleRecipeRenderFailedAfterFrame(photoId, recipe);
      }
    });
  }

  void _handleRecipeRenderFailedAfterFrame(String photoId, EditRecipe recipe) {
    final request = _pendingManualRender;
    if (request == null ||
        request.photoId != photoId ||
        request.renderedRecipe != recipe) {
      return;
    }
    setState(() => _pendingManualRender = null);
    final settlement = _recipeSettlement;
    if (settlement != null && !settlement.isCompleted) settlement.complete();
    if (_editorSession.recipe == request.editableRecipe) {
      _loadEditableRecipe();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.effectPreviewUnavailable)),
      );
    }
  }

  Future<void> _persistRecipe(EditRecipe desiredRecipe) async {
    if (_exportSummary != null || _exporting || _sharing) return;
    var committedEdit = false;
    try {
      final session = _session;
      final project = session?.project;
      if (session == null || project == null) return;
      final photoId = project.focusPhotoId ?? project.photos.first.id;
      final importer = _photoImporter!;
      final activeTargetValues =
          project.targetRegistries[photoId]?.targets.values
              .where((target) => target.status == EditTargetStatus.active)
              .toList(growable: false) ??
          const <StableEditTarget>[];
      final commit = await session.commitManualRecipe(
        desiredRecipe: desiredRecipe,
        context: _editorSession.editContext(
          photoIds: project.photos.map((photo) => photo.id).toSet(),
          targetIds: activeTargetValues.map((target) => target.id).toSet(),
          applicability: {
            'photo',
            if (activeTargetValues.any(
              (target) => target.kind == EditTargetKind.face,
            ))
              'face',
            if (activeTargetValues.any(
              (target) => target.kind == EditTargetKind.body,
            ))
              'body',
          },
        ),
        resourceImporter: importer is EditingResourceImporter ? importer : null,
      );
      committedEdit = commit.result is AcceptedEdit;
      if (mounted) {
        setState(() => _recipeSaveFailure = null);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _recipeSaveFailure = _RecipeSaveFailure(desiredRecipe: desiredRecipe);
        });
      }
    } finally {
      if (mounted && _editorSession.recipe == desiredRecipe) {
        _loadEditableRecipe();
      }
      if (committedEdit && mounted) {
        _showEditFeedback(context.l10n.editApplied);
      }
    }
  }

  void _retryRecipeSave() {
    final failure = _recipeSaveFailure;
    if (failure == null || _recipePersistenceJobs > 0) return;
    final settlement = Completer<void>();
    _recipeSettlement = settlement;
    setState(() => _recipeSaveFailure = null);
    _queueRecipePersistence(failure.desiredRecipe, settlement: settlement);
  }

  void _discardFailedRecipe() {
    if (_recipeSaveFailure == null || _recipePersistenceJobs > 0) return;
    setState(() => _recipeSaveFailure = null);
    _loadEditableRecipe();
  }

  bool get _hasUnsettledRecipe =>
      _pendingManualRender != null ||
      _recipePersistenceJobs > 0 ||
      _recipeSaveFailure != null;

  bool get _hasLocalEditorLayer =>
      _immersivePreview || _visualTrackKind != null || _manualToolsVisible;

  void _handleBlockedPop() {
    if (_exporting) return;
    if (_immersivePreview) {
      setState(() => _immersivePreview = false);
      return;
    }
    if (_visualTrackKind != null) {
      setState(() => _visualTrackKind = null);
      return;
    }
    if (_manualToolsVisible) {
      _editorSession.cancelAdjustment();
      _loadEditableRecipe();
      setState(() => _manualToolsVisible = false);
      return;
    }
    if (_hasUnsettledRecipe) unawaited(_settleRecipeAndPop());
  }

  Future<void> _settleRecipeAndPop() async {
    await _recipeSettlement?.future;
    await _recipePersistence;
    if (!mounted || _hasUnsettledRecipe) return;
    setState(() => _allowRoutePop = true);
    Navigator.of(context).pop();
  }

  void _showEditFeedback(String message) {
    _editFeedbackTimer?.cancel();
    if (!mounted) return;
    setState(() => _editFeedback = _EditFeedback(message: message));
    _editFeedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _editFeedback = null);
    });
  }

  Future<void> _undoEdit() async {
    if (_exportSummary != null || _exporting || _sharing) return;
    _editFeedbackTimer?.cancel();
    try {
      await _session?.undoEdit();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    } finally {
      _loadEditableRecipe();
      if (mounted) setState(() => _editFeedback = null);
    }
  }

  void _openVisualTrack(VisualTrackKind kind) {
    if (_exportSummary != null || _exporting || _sharing) return;
    setState(() {
      _manualToolsVisible = false;
      _visualTrackKind = kind;
    });
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
      _loadEditableRecipe();
    }
  }

  Future<void> _resetEdit() async {
    if (_exportSummary != null || _exporting || _sharing) return;
    try {
      final session = _session;
      final project = session?.project;
      if (session == null || project == null) return;
      final photoId = project.focusPhotoId ?? project.photos.first.id;
      final activeTargets =
          project.targetRegistries[photoId]?.targets.values
              .where((target) => target.status == EditTargetStatus.active)
              .toList(growable: false) ??
          const <StableEditTarget>[];
      await session.resetScopedEdit(
        context: _editorSession.editContext(
          photoIds: project.photos.map((photo) => photo.id).toSet(),
          targetIds: activeTargets.map((target) => target.id).toSet(),
          applicability: {
            'photo',
            if (activeTargets.any(
              (target) => target.kind == EditTargetKind.face,
            ))
              'face',
            if (activeTargets.any(
              (target) => target.kind == EditTargetKind.body,
            ))
              'body',
          },
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    } finally {
      _loadEditableRecipe();
    }
  }

  Future<void> _showVoiceEditSheet() async {
    if (_exportSummary != null || _exporting || _sharing) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheetContext) => VoiceEditSheet(
        transcriber: widget.speechTranscriber,
        onSubmit: (intent) async {
          final applied = await _planAndCommitAiIntent(intent);
          if (applied && sheetContext.mounted) {
            final route = ModalRoute.of(sheetContext);
            final navigator = route?.navigator;
            if (route != null && navigator != null) {
              navigator.removeRoute(route);
            }
          }
          return applied;
        },
      ),
    );
  }

  Future<void> _applyQuickInstruction(String instruction) async {
    if (_exportSummary != null || _exporting || _sharing) return;
    await _planAndCommitAiIntent(instruction);
  }

  Future<bool> _planAndCommitAiIntent(String intent) async {
    final session = _session;
    final project = session?.project;
    if (session == null || project == null || !session.canEdit) return false;
    final photoId = project.focusPhotoId ?? project.photos.first.id;
    final activeTargets =
        project.targetRegistries[photoId]?.targets.values
            .where((target) => target.status == EditTargetStatus.active)
            .map((target) => target.id)
            .toSet() ??
        const <String>{};
    final applicability = {'photo', if (activeTargets.isNotEmpty) 'face'};
    final availability = _editorSession.metaOpAvailability(
      applicability: applicability,
    );
    final productionIds = availability.aiProductionIds.toSet();
    final capabilities = availability
        .aiCapabilities(MetaOpCatalog.standard)
        .where((value) => productionIds.contains(value.definition.id));
    final analysis = _analysisByPhotoId[photoId];
    final outcome = await widget.aiEditPlanner.plan(
      AiEditPlanningRequest(
        intent: intent,
        baseStateVersion: project.editStateVersion,
        currentState: project.editState,
        capabilities: capabilities,
        photoAnalysis: AiPhotoAnalysis(
          scene: analysis?.scene.name ?? SceneKind.unknown.name,
          targetIds: activeTargets.toList(growable: false),
        ),
        photoId: photoId,
      ),
    );
    final AiEditProposal proposal;
    if (outcome is AiEditProposal) {
      proposal = outcome;
    } else if (outcome is AiTargetClarification) {
      final candidates =
          project.targetRegistries[photoId]?.targets.values
              .where(
                (target) =>
                    target.status == EditTargetStatus.active &&
                    ((outcome.targetType == MetaOpTargetType.face &&
                            target.kind == EditTargetKind.face) ||
                        (outcome.targetType == MetaOpTargetType.body &&
                            target.kind == EditTargetKind.body)),
              )
              .toList() ??
          const <StableEditTarget>[];
      final selectedTargetId = await _chooseAiTarget(
        project.photos.firstWhere((photo) => photo.id == photoId),
        candidates,
      );
      if (selectedTargetId == null) return false;
      proposal = outcome.resolve(selectedTargetId);
    } else {
      return false;
    }
    final editContext = _editorSession.editContext(
      photoIds: project.photos.map((photo) => photo.id).toSet(),
      targetIds: activeTargets,
      applicability: applicability,
    );
    final preparedPreview = session.prepareMetaOpsForPreview(
      changes: proposal.changes,
      source: EditSource.ai,
      context: editContext,
    );
    if (preparedPreview == null ||
        !await _renderBeforeAiCommit(
          photo: project.photos.firstWhere((photo) => photo.id == photoId),
          preview: preparedPreview,
        )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.effectPreviewUnavailable)),
        );
      }
      return false;
    }
    final result = await session.commitAiProposal(
      proposal,
      context: editContext,
    );
    if (result is! AcceptedEdit) return false;
    _loadEditableRecipe();
    if (!mounted) return true;
    _showEditFeedback(
      proposal.changes.any(
            (change) => change.address.metaOpId == MetaOpIds.exposure,
          )
          ? context.l10n.editResultBrighter
          : context.l10n.editResultApplied,
    );
    return true;
  }

  Future<bool> _renderBeforeAiCommit({
    required ProjectPhoto photo,
    required PreparedMetaOpPreview preview,
  }) async {
    final renderer = context.read<PhotoPreviewRenderer>();
    PhotoPreviewHandle? handle;
    try {
      handle = await renderer.create(
        sourcePath: photo.localPath,
        pipeline: imagePipelineForCurrentPlatform(
          preview.recipe,
          sourceId: preview.sourceId,
          editState: preview.state,
          context: preview.context,
        ),
        maxEdge: 1024,
      );
      return true;
    } on Object {
      return false;
    } finally {
      if (handle != null) {
        try {
          await renderer.dispose(handle);
        } on Object {
          // The validation render succeeded; cleanup is best effort.
        }
      }
    }
  }

  Future<String?> _chooseAiTarget(
    ProjectPhoto photo,
    List<StableEditTarget> candidates,
  ) async {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.single.id;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(context.l10n.choosePersonTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n.choosePersonHint),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(photo.localPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFF252728)),
                    ),
                    for (var index = 0; index < candidates.length; index++)
                      Positioned.fromRect(
                        rect: Rect.fromLTRB(
                          candidates[index].region.left * 240,
                          candidates[index].region.top * 180,
                          candidates[index].region.right * 240,
                          candidates[index].region.bottom * 180,
                        ),
                        child: IgnorePointer(
                          child: Container(
                            key: ValueKey(
                              'ai-target-overlay-${candidates[index].id}',
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.topLeft,
                            child: CircleAvatar(
                              radius: 13,
                              child: Text('${index + 1}'),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < candidates.length; index++)
              ListTile(
                key: ValueKey('ai-target-${candidates[index].id}'),
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox.square(
                        dimension: 44,
                        child: Image.file(
                          File(photo.localPath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Color(0xFF252728)),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -5,
                      top: -5,
                      child: CircleAvatar(
                        radius: 11,
                        child: Text('${index + 1}'),
                      ),
                    ),
                  ],
                ),
                title: Text('${context.l10n.choosePersonTitle} ${index + 1}'),
                onTap: () => Navigator.pop(context, candidates[index].id),
              ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('ai-target-cancel'),
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
        ],
      ),
    );
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
      _faceSlimApplicabilityByPhotoId.clear();
      _faceSlimReasonByPhotoId.clear();
      _faceSlimTargetCountByPhotoId.clear();
      _bodyApplicabilityByPhotoId.clear();
      _bodyTargetCountByPhotoId.clear();
      await _discardShareFiles();
      _selectedIndex = 0;
      _loadEditableRecipe();
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
    _editFeedbackTimer?.cancel();
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
        _recipePersistence,
        ?batchDrain,
      ];
      if (pending.isEmpty) {
        session.dispose();
      } else {
        unawaited(Future.wait(pending).whenComplete(session.dispose));
      }
    }
    _editorSession.dispose();
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

  Future<void> _showSaveOptions() async {
    final project = _session?.project;
    if (project == null || _exporting || _sharing || _hasUnsettledRecipe) {
      return;
    }
    final exporter = context.read<PhotoExporter>();
    if (!_explainedPhotoPermission &&
        exporter is PhotoLibraryPermissionAwareExporter) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.saveToAlbum),
          content: Text(context.l10n.photoPermissionPurpose),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey('export-permission-continue'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.saveToAlbum),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      _explainedPhotoPermission = true;
    }
    await _exportBatch(photoIds: {project.photos.single.id});
  }

  Future<void> _exportBatch({
    bool retryFailuresOnly = false,
    Set<String>? photoIds,
  }) async {
    if (_exporting ||
        _sharing ||
        (!retryFailuresOnly && _exportSummary != null)) {
      return;
    }
    if (!mounted) {
      return;
    }
    final exporter = context.read<PhotoExporter>();
    final PhotoExportStageAware? stagedExporter =
        exporter is PhotoExportStageAware
        ? exporter as PhotoExportStageAware
        : null;
    VoidCallback? exportStageListener;
    if (stagedExporter != null) {
      exportStageListener = () {
        if (!mounted || !_exporting) return;
        setState(() => _exportStage = stagedExporter.stage.value);
      };
      stagedExporter.stage.addListener(exportStageListener);
    }
    setState(() {
      _exporting = true;
      _exportStage = stagedExporter != null
          ? stagedExporter.stage.value
          : PhotoExportStage.preparing;
    });
    final attemptPhotoIds = <String>{};
    Future<BatchExportSummary>? completion;
    try {
      final batch = BoundedBatchPhotoExporter(
        session: _session!,
        exporter: exporter,
        options: _exportOptions,
        onSharePathCreated: (photoId, localPath) {
          attemptPhotoIds.add(photoId);
          _ownSharePath(photoId, localPath);
        },
      );
      _batchExporter = batch;
      completion = batch.export(
        retryFailuresOnly: retryFailuresOnly,
        photoIds: photoIds,
      );
      _batchCompletion = completion;
      final summary = await completion;
      final error = batch.lastError;
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
      setState(() {
        _exportSummary = displaySummary;
        _photoPermissionDenied =
            error is PlatformException && error.code == 'photoAccessDenied';
      });
    } on Object {
      await _discardShareFiles(photoIds: attemptPhotoIds);
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
      if (stagedExporter != null && exportStageListener != null) {
        stagedExporter.stage.removeListener(exportStageListener);
      }
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

  void _cancelBatchExport() => _batchExporter?.cancel();

  void _finishSaving() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

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
    if (mounted) {
      setState(() {
        _exportSummary = null;
        _photoPermissionDenied = false;
      });
    }
  }

  Future<void> _openPhotoSettings() async {
    final exporter = context.read<PhotoExporter>();
    if (exporter is PhotoLibrarySettingsOpener) {
      await (exporter as PhotoLibrarySettingsOpener).openPhotoLibrarySettings();
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
        _loadEditableRecipe();
        unawaited(_preparePhotoAnalysis(persistAnalysisStates: true));
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

  EditContext _renderContextFor(PhotoProject project, String photoId) {
    final targets =
        project.targetRegistries[photoId]?.targets.values
            .where((target) => target.status == EditTargetStatus.active)
            .toList(growable: false) ??
        const <StableEditTarget>[];
    return _editorSession.editContext(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session!;
    if (_taskRouteMismatch) {
      return Scaffold(
        key: const ValueKey('editor-task-route-mismatch'),
        appBar: AppBar(title: Text(context.l10n.appTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              context.l10n.taskRouteMismatch,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([session, _editorSession]),
      builder: (context, _) {
        final photos = session.photos;
        if (_selectedIndex >= photos.length && photos.isNotEmpty) {
          _selectedIndex = photos.length - 1;
        }
        final previewRecipe = photos.isEmpty
            ? EditRecipe.neutral
            : session.previewRecipeFor(
                photos[_selectedIndex].id,
                _editorSession.recipe,
              );
        final editingEnabled =
            session.canEdit &&
            !_sharing &&
            _exportSummary == null &&
            !_hasUnsettledRecipe;
        final hasPhotosReadyToExport =
            session.project?.exportStates.values.any(
              (state) =>
                  state == PhotoExportState.notQueued ||
                  state == PhotoExportState.saved ||
                  state == PhotoExportState.failed ||
                  state == PhotoExportState.cancelled,
            ) ??
            false;
        final selectedPhoto = photos.isEmpty ? null : photos[_selectedIndex];
        final portraitApplicable =
            selectedPhoto != null &&
            _portraitApplicabilityByPhotoId[selectedPhoto.id] ==
                PortraitApplicability.applicable;
        final bodyApplicable =
            selectedPhoto != null &&
            _bodyApplicabilityByPhotoId[selectedPhoto.id] ==
                PortraitApplicability.applicable;
        final bodyTargetCount = selectedPhoto == null
            ? 0
            : _bodyTargetCountByPhotoId[selectedPhoto.id] ??
                  (bodyApplicable ? 1 : 0);
        final faceSlimApplicable =
            selectedPhoto != null &&
            _faceSlimApplicabilityByPhotoId[selectedPhoto.id] ==
                PortraitApplicability.applicable;
        final faceSlimReason = selectedPhoto == null
            ? PortraitDegradationReason.none
            : _faceSlimReasonByPhotoId[selectedPhoto.id] ??
                  PortraitDegradationReason.none;
        final faceSlimTargetCount = selectedPhoto == null
            ? 0
            : _faceSlimTargetCountByPhotoId[selectedPhoto.id] ??
                  (faceSlimApplicable ? 1 : 0);
        final faceTargetRegions = selectedPhoto == null
            ? const <NormalizedTargetRegion>[]
            : _faceTargetRegionsByPhotoId[selectedPhoto.id] ?? const [];
        final bodyTargetRegions = selectedPhoto == null
            ? const <NormalizedTargetRegion>[]
            : _bodyTargetRegionsByPhotoId[selectedPhoto.id] ?? const [];
        const photoToolsVisible = true;
        return PopScope(
          canPop:
              _allowRoutePop ||
              (!_hasUnsettledRecipe && !_hasLocalEditorLayer && !_exporting),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _handleBlockedPop();
          },
          child: Scaffold(
            key: ValueKey(switch (widget.entryPoint) {
              EditorEntryPoint.standard => 'editor-page',
              EditorEntryPoint.optimize => 'editor-task-optimize',
              EditorEntryPoint.cleanup => 'editor-task-cleanup',
            }),
            backgroundColor: _immersivePreview ? const Color(0xFF0B0D0E) : null,
            appBar: _immersivePreview
                ? null
                : AppBar(
                    title: photos.isEmpty
                        ? null
                        : Text(
                            switch (widget.entryPoint) {
                              EditorEntryPoint.standard =>
                                context.l10n.appTitle,
                              EditorEntryPoint.optimize =>
                                context.l10n.optimizePhoto,
                              EditorEntryPoint.cleanup =>
                                context.l10n.removeBackgroundOrObjects,
                            },
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                          ),
                    actions: photos.isEmpty
                        ? null
                        : [
                            IconButton(
                              key: const ValueKey('editor-undo'),
                              tooltip: context.l10n.undo,
                              onPressed: editingEnabled && session.canUndo
                                  ? () => unawaited(_undoEdit())
                                  : null,
                              icon: const Icon(Icons.undo_rounded),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: FilledButton(
                                key: const ValueKey('editor-export'),
                                onPressed:
                                    editingEnabled && hasPhotosReadyToExport
                                    ? () => unawaited(_showSaveOptions())
                                    : null,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(72, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                ),
                                child: Text(context.l10n.savePhotos),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).showMenuTooltip,
                              onSelected: (value) {
                                switch (value) {
                                  case 'redo':
                                    unawaited(_redoEdit());
                                  case 'reset':
                                    unawaited(_resetEdit());
                                  case 'delete':
                                    unawaited(_deleteProject());
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'redo',
                                  enabled: editingEnabled && session.canRedo,
                                  child: Text(context.l10n.redo),
                                ),
                                PopupMenuItem(
                                  value: 'reset',
                                  enabled:
                                      editingEnabled &&
                                      session.canResetScopedEdit,
                                  child: Text(context.l10n.reset),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'delete',
                                  enabled: !_exporting && !_sharing,
                                  child: Text(context.l10n.deleteProject),
                                ),
                              ],
                            ),
                            if (MediaQuery.sizeOf(context).width >= 700)
                              IconButton(
                                tooltip: context.l10n.deleteProject,
                                onPressed: _exporting || _sharing
                                    ? null
                                    : () => unawaited(_deleteProject()),
                                icon: const Icon(Icons.delete_outline),
                              ),
                          ],
                  ),
            bottomNavigationBar:
                _immersivePreview ||
                    _manualToolsVisible ||
                    _visualTrackKind != null ||
                    _exporting ||
                    _exportSummary != null
                ? null
                : photos.isEmpty ||
                      session.isRestoring ||
                      session.restoreError != null
                ? null
                : _EditorCommandBar(
                    editingEnabled: editingEnabled,
                    exporting: _exporting,
                    sharing: _sharing,
                    exportSummary: _exportSummary,
                    feedback: _editFeedback,
                    onVoiceEdit: () => unawaited(_showVoiceEditSheet()),
                    onManualEdit: () => setState(() {
                      _visualTrackKind = null;
                      _manualToolsVisible = true;
                    }),
                    onAtmosphere: () => _openVisualTrack(VisualTrackKind.era),
                    onUndo: () => unawaited(_undoEdit()),
                    onQuickEdit: (instruction) =>
                        unawaited(_applyQuickInstruction(instruction)),
                    onCancelExport: _cancelBatchExport,
                    onContinueEditing: () => unawaited(_continueEditing()),
                  ),
            body: _immersivePreview && selectedPhoto != null
                ? _FullscreenPhotoPreview(
                    photo: selectedPhoto,
                    recipe: previewRecipe,
                    editState: session.project!.renderStateFor(
                      selectedPhoto.id,
                      recipe: previewRecipe,
                    ),
                    editContext: _renderContextFor(
                      session.project!,
                      selectedPhoto.id,
                    ),
                    renderer: context.read<PhotoPreviewRenderer>(),
                    position: _selectedIndex + 1,
                    count: photos.length,
                    onClose: () => setState(() => _immersivePreview = false),
                  )
                : SafeArea(
                    child: _exporting
                        ? _SavingProgressView(stage: _exportStage)
                        : _exportSummary != null &&
                              _exportSummary!.failedCount == 0 &&
                              _exportSummary!.cancelledCount == 0
                        ? _SaveSuccessView(
                            onFinish: _finishSaving,
                            onShare: _exportSummary!.canShare
                                ? () => unawaited(_shareExportedPhotos())
                                : null,
                            sharing: _sharing,
                          )
                        : _exportSummary != null
                        ? _PartialSaveView(
                            exporting: _exporting,
                            sharing: _sharing,
                            permissionDenied: _photoPermissionDenied,
                            onRetry: () => unawaited(
                              _exportBatch(retryFailuresOnly: true),
                            ),
                            onBackToEditing: () =>
                                unawaited(_continueEditing()),
                            onOpenSettings: () =>
                                unawaited(_openPhotoSettings()),
                          )
                        : session.isRestoring
                        ? Semantics(
                            liveRegion: true,
                            label: context.l10n.restoringProject,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : session.restoreError != null
                        ? _RestoreError(
                            onRetry: () =>
                                session.restore(enforceSinglePhoto: true),
                          )
                        : photos.isEmpty
                        ? _EmptyProject(
                            busy: _busy,
                            failures: session.importFailures,
                            onImport: _importPhotos,
                          )
                        : Column(
                            children: [
                              if (_recipePersistenceJobs > 0 ||
                                  _pendingManualRender != null)
                                const _EditSavePending(),
                              if (_recipeSaveFailure != null)
                                _EditSaveRecovery(
                                  onRetry: _retryRecipeSave,
                                  onDiscard: _discardFailedRecipe,
                                ),
                              Expanded(
                                child: _PhotoWorkspace(
                                  photos: photos,
                                  project: session.project!,
                                  importFailures: session.importFailures,
                                  selectedIndex: _selectedIndex,
                                  exporting: _exporting,
                                  editingEnabled: editingEnabled,
                                  previewRecipe: previewRecipe,
                                  flowState: session.flowState,
                                  editorSession: _editorSession,
                                  portraitApplicable: portraitApplicable,
                                  faceSlimApplicable: faceSlimApplicable,
                                  faceSlimReason: faceSlimReason,
                                  faceSlimTargetCount: faceSlimTargetCount,
                                  faceTargetRegions: faceTargetRegions,
                                  bodyApplicable: bodyApplicable,
                                  bodyTargetCount: bodyTargetCount,
                                  bodyTargetRegions: bodyTargetRegions,
                                  photoToolsVisible: photoToolsVisible,
                                  manualToolsVisible: _manualToolsVisible,
                                  entryPoint: widget.entryPoint,
                                  visualTrackKind: _visualTrackKind,
                                  feedback: _editFeedback,
                                  showCanvasInteractionHint:
                                      _showCanvasInteractionHint,
                                  exportSummary: _exportSummary,
                                  onRetryExport: () => unawaited(
                                    _exportBatch(retryFailuresOnly: true),
                                  ),
                                  sharing: _sharing,
                                  onShareExport: () =>
                                      unawaited(_shareExportedPhotos()),
                                  onRecipeCommitted: _requestRecipePersistence,
                                  onRecipeRendered: (recipe) =>
                                      _handleRecipeRendered(
                                        photos[_selectedIndex].id,
                                        recipe,
                                      ),
                                  onRecipeRenderFailed: (recipe) =>
                                      _handleRecipeRenderFailed(
                                        photos[_selectedIndex].id,
                                        recipe,
                                      ),
                                  onUndo: () => unawaited(_undoEdit()),
                                  onOpenTools: () => setState(() {
                                    _visualTrackKind = null;
                                    _manualToolsVisible = true;
                                  }),
                                  onCloseTools: () {
                                    _editorSession.cancelAdjustment();
                                    _loadEditableRecipe();
                                    setState(() => _manualToolsVisible = false);
                                  },
                                  onCloseVisualTrack: () =>
                                      setState(() => _visualTrackKind = null),
                                  onOpenFullscreen: () => setState(() {
                                    _showCanvasInteractionHint = false;
                                    _immersivePreview = true;
                                  }),
                                ),
                              ),
                            ],
                          ),
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
            const SizedBox(height: 24),
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
    required this.exporting,
    required this.exportSummary,
    required this.editingEnabled,
    required this.previewRecipe,
    required this.flowState,
    required this.editorSession,
    required this.portraitApplicable,
    required this.faceSlimApplicable,
    required this.faceSlimReason,
    required this.faceSlimTargetCount,
    required this.faceTargetRegions,
    required this.bodyApplicable,
    required this.bodyTargetCount,
    required this.bodyTargetRegions,
    required this.photoToolsVisible,
    required this.manualToolsVisible,
    required this.entryPoint,
    required this.visualTrackKind,
    required this.feedback,
    required this.showCanvasInteractionHint,
    required this.onRetryExport,
    required this.sharing,
    required this.onShareExport,
    required this.onRecipeCommitted,
    required this.onRecipeRendered,
    required this.onRecipeRenderFailed,
    required this.onUndo,
    required this.onOpenTools,
    required this.onCloseTools,
    required this.onCloseVisualTrack,
    required this.onOpenFullscreen,
  });

  final List<ProjectPhoto> photos;
  final PhotoProject project;
  final List<PhotoImportFailure> importFailures;
  final int selectedIndex;
  final bool exporting;
  final BatchExportSummary? exportSummary;
  final bool editingEnabled;
  final EditRecipe previewRecipe;
  final PhotoProjectFlowState flowState;
  final EditorSession editorSession;
  final bool portraitApplicable;
  final bool faceSlimApplicable;
  final PortraitDegradationReason faceSlimReason;
  final int faceSlimTargetCount;
  final List<NormalizedTargetRegion> faceTargetRegions;
  final bool bodyApplicable;
  final int bodyTargetCount;
  final List<NormalizedTargetRegion> bodyTargetRegions;
  final bool photoToolsVisible;
  final bool manualToolsVisible;
  final EditorEntryPoint entryPoint;
  final VisualTrackKind? visualTrackKind;
  final _EditFeedback? feedback;
  final bool showCanvasInteractionHint;
  final VoidCallback onRetryExport;
  final bool sharing;
  final VoidCallback onShareExport;
  final VoidCallback onRecipeCommitted;
  final ValueChanged<EditRecipe> onRecipeRendered;
  final ValueChanged<EditRecipe> onRecipeRenderFailed;
  final VoidCallback onUndo;
  final VoidCallback onOpenTools;
  final VoidCallback onCloseTools;
  final VoidCallback onCloseVisualTrack;
  final VoidCallback onOpenFullscreen;

  @override
  Widget build(BuildContext context) {
    final selected = photos[selectedIndex];
    final activeTargets =
        (project.targetRegistries[selected.id]?.targets.values ?? const [])
            .where((target) => target.status == EditTargetStatus.active)
            .toList(growable: false);
    final stableFaceTargets =
        activeTargets
            .where(
              (target) =>
                  target.kind == EditTargetKind.face &&
                  target.status == EditTargetStatus.active,
            )
            .toList()
          ..sort((left, right) {
            final horizontal = left.region.left.compareTo(right.region.left);
            return horizontal != 0
                ? horizontal
                : left.region.top.compareTo(right.region.top);
          });
    final recipe = editorSession.recipe;
    final previewRenderer = context.read<PhotoPreviewRenderer>();
    final interactionsBlocked =
        project.isReadOnly || exporting || sharing || exportSummary != null;
    final compactHeight = MediaQuery.sizeOf(context).height < 700;
    final simplifiedMobile = MediaQuery.sizeOf(context).width < 700;
    final previewCard = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: _BeforeAfterPreview(
          key: ValueKey('photo-preview-${selected.id}'),
          sourcePath: selected.localPath,
          recipe: previewRecipe,
          sourceId: selected.id,
          editState: project.renderStateFor(selected.id, recipe: previewRecipe),
          editContext: editorSession.editContext(
            photoIds: project.photos.map((photo) => photo.id).toSet(),
            targetIds: activeTargets.map((target) => target.id).toSet(),
            applicability: {
              'photo',
              if (activeTargets.any(
                (target) => target.kind == EditTargetKind.face,
              ))
                'face',
              if (activeTargets.any(
                (target) => target.kind == EditTargetKind.body,
              ))
                'body',
            },
            resourceIds: project.editingResources.resources.keys.toSet(),
            resourceByteLengths: {
              for (final resource in project.editingResources.resources.values)
                resource.id: resource.byteLength,
            },
          ),
          renderer: previewRenderer,
          onRendered: onRecipeRendered,
          onRenderFailed: onRecipeRenderFailed,
        ),
      ),
    );
    return Column(
      children: [
        if (project.requiresUpdate)
          Semantics(
            key: const ValueKey('project-requires-update'),
            liveRegion: true,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.system_update_alt_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.projectRequiresUpdateTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(context.l10n.projectRequiresUpdateMessage),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          flex: exportSummary == null
              ? compactHeight
                    ? 4
                    : 6
              : 4,
          child: Padding(
            key: const ValueKey('editor-preview-stage'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: simplifiedMobile
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Semantics(
                            key: const ValueKey('editor-preview-fullscreen'),
                            button: true,
                            child: GestureDetector(
                              key: const ValueKey('editor-photo-preview'),
                              behavior: HitTestBehavior.opaque,
                              onTap: onOpenFullscreen,
                              child: SizedBox.expand(child: previewCard),
                            ),
                          ),
                          if (showCanvasInteractionHint)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: IgnorePointer(
                                child: Semantics(
                                  key: const ValueKey(
                                    'editor-canvas-interaction-hint',
                                  ),
                                  label: context.l10n.canvasInteractionHint,
                                  child: Container(
                                    margin: const EdgeInsets.all(12),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Text(
                                      context.l10n.canvasInteractionHint,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelMedium,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : AspectRatio(aspectRatio: 4 / 3, child: previewCard),
              ),
            ),
          ),
        ),
        if (manualToolsVisible && feedback != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: _ResultFeedbackPill(feedback: feedback!, onUndo: onUndo),
          ),
        if (manualToolsVisible && exportSummary == null)
          _EditorToolsDock(
            photos: photos,
            project: project,
            selected: selected,
            recipe: recipe,
            editingEnabled: editingEnabled,
            interactionsBlocked: interactionsBlocked,
            portraitApplicable: portraitApplicable,
            faceSlimApplicable: faceSlimApplicable,
            faceSlimReason: faceSlimReason,
            faceSlimTargetCount: faceSlimTargetCount,
            faceTargetRegions: faceTargetRegions,
            stableFaceTargets: stableFaceTargets,
            bodyApplicable: bodyApplicable,
            bodyTargetCount: bodyTargetCount,
            bodyTargetRegions: bodyTargetRegions,
            photoToolsVisible: photoToolsVisible,
            editorSession: editorSession,
            onRecipeCommitted: onRecipeCommitted,
            onClose: onCloseTools,
            entryPoint: entryPoint,
          ),
        if (visualTrackKind != null && exportSummary == null)
          VisualTracksDock(
            key: ValueKey('visual-tracks-dock-${visualTrackKind!.name}'),
            initialKind: visualTrackKind!,
            editorSession: editorSession,
            faceTargets: stableFaceTargets,
            editingEnabled: editingEnabled && !interactionsBlocked,
            onRecipeCommitted: onRecipeCommitted,
            onClose: onCloseVisualTrack,
          ),
        if ((!simplifiedMobile && !manualToolsVisible) || exportSummary != null)
          Expanded(
            flex: exportSummary == null
                ? compactHeight
                      ? 6
                      : 4
                : 6,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                key: const Key('photo-workspace-scroll'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                children: [
                  if (importFailures.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ImportFailures(failures: importFailures),
                  ],
                  if (exportSummary != null) ...[
                    const SizedBox(height: 12),
                    _ExportSummaryCard(
                      summary: exportSummary!,
                      exporting: exporting,
                      sharing: sharing,
                      onRetry: onRetryExport,
                      onShare: onShareExport,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _EditorToolsDock extends StatefulWidget {
  const _EditorToolsDock({
    required this.photos,
    required this.project,
    required this.selected,
    required this.recipe,
    required this.editingEnabled,
    required this.interactionsBlocked,
    required this.portraitApplicable,
    required this.faceSlimApplicable,
    required this.faceSlimReason,
    required this.faceSlimTargetCount,
    required this.faceTargetRegions,
    required this.stableFaceTargets,
    required this.bodyApplicable,
    required this.bodyTargetCount,
    required this.bodyTargetRegions,
    required this.photoToolsVisible,
    required this.editorSession,
    required this.onRecipeCommitted,
    required this.onClose,
    required this.entryPoint,
  });

  final List<ProjectPhoto> photos;
  final PhotoProject project;
  final ProjectPhoto selected;
  final EditRecipe recipe;
  final bool editingEnabled;
  final bool interactionsBlocked;
  final bool portraitApplicable;
  final bool faceSlimApplicable;
  final PortraitDegradationReason faceSlimReason;
  final int faceSlimTargetCount;
  final List<NormalizedTargetRegion> faceTargetRegions;
  final List<StableEditTarget> stableFaceTargets;
  final bool bodyApplicable;
  final int bodyTargetCount;
  final List<NormalizedTargetRegion> bodyTargetRegions;
  final bool photoToolsVisible;
  final EditorSession editorSession;
  final VoidCallback onRecipeCommitted;
  final VoidCallback onClose;
  final EditorEntryPoint entryPoint;

  @override
  State<_EditorToolsDock> createState() => _EditorToolsDockState();
}

class _EditorToolsDockState extends State<_EditorToolsDock> {
  String? _selectedMetaOpId;
  bool _showAllTools = false;
  late List<String> _frozenManualMetaOpIds;

  @override
  void initState() {
    super.initState();
    _selectedMetaOpId = _initialMetaOpId(widget.entryPoint);
    _freezeManualOrder();
  }

  @override
  void didUpdateWidget(covariant _EditorToolsDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected.id != widget.selected.id) {
      _selectedMetaOpId = _initialMetaOpId(widget.entryPoint);
      _showAllTools = false;
      _freezeManualOrder();
    }
    if (oldWidget.entryPoint != widget.entryPoint) {
      _selectedMetaOpId = _initialMetaOpId(widget.entryPoint);
      _showAllTools = false;
    }
  }

  String? _initialMetaOpId(EditorEntryPoint entryPoint) => switch (entryPoint) {
    EditorEntryPoint.cleanup => MetaOpIds.semanticAdjustments,
    EditorEntryPoint.standard => null,
    EditorEntryPoint.optimize => null,
  };

  void _freezeManualOrder() {
    _frozenManualMetaOpIds = widget.editorSession.orderedManualMetaOpIds(
      applicability: const {'photo', 'face', 'body'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final usesDedicatedEditor = _usesDedicatedEditor(_selectedMetaOpId);
    return SizedBox(
      key: const ValueKey('editor-tools-dock'),
      height: _showAllTools
          ? min(300, MediaQuery.sizeOf(context).height * 0.38)
          : usesDedicatedEditor
          ? min(320, MediaQuery.sizeOf(context).height * 0.36)
          : largeText
          ? min(320, MediaQuery.sizeOf(context).height * 0.42)
          : min(236, MediaQuery.sizeOf(context).height * 0.31),
      child: Material(
        color: colors.surface,
        child: Column(
          children: [
            Divider(height: 1, color: colors.outlineVariant),
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      key: ValueKey(
                        _showAllTools
                            ? 'editor-all-tools-back'
                            : 'editor-tools-done',
                      ),
                      tooltip: _showAllTools
                          ? MaterialLocalizations.of(context).backButtonTooltip
                          : context.l10n.backToEditing,
                      onPressed: _showAllTools
                          ? () => setState(() => _showAllTools = false)
                          : widget.onClose,
                      icon: Icon(
                        _showAllTools
                            ? Icons.arrow_back_rounded
                            : Icons.keyboard_arrow_down_rounded,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _showAllTools
                            ? context.l10n.allTools
                            : switch (widget.entryPoint) {
                                EditorEntryPoint.standard =>
                                  context.l10n.adjustPhoto,
                                EditorEntryPoint.optimize =>
                                  context.l10n.optimizePhoto,
                                EditorEntryPoint.cleanup =>
                                  context.l10n.removeBackgroundOrObjects,
                              },
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_showAllTools)
                      IconButton(
                        key: const ValueKey('editor-tools-done'),
                        tooltip: context.l10n.backToEditing,
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      )
                    else
                      IconButton(
                        key: const ValueKey('editor-all-tools'),
                        tooltip: context.l10n.allTools,
                        onPressed: widget.editingEnabled
                            ? () => setState(() => _showAllTools = true)
                            : null,
                        icon: const Icon(Icons.grid_view_rounded),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _showAllTools
                  ? _InlineMetaOpBrowser(
                      editorSession: widget.editorSession,
                      applicability: const {'photo', 'face', 'body'},
                      onSelected: (selected) => setState(() {
                        _selectedMetaOpId = selected;
                        _showAllTools = false;
                      }),
                    )
                  : SingleChildScrollView(
                      key: const ValueKey('editor-tools-scroll'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _buildSelectedTool(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _usesDedicatedEditor(String? id) =>
      id == MetaOpIds.compositionGeometry ||
      id == MetaOpIds.filter ||
      id == MetaOpIds.semanticAdjustments ||
      id == MetaOpIds.faceGeometry ||
      id == MetaOpIds.bodyGeometry ||
      id == MetaOpIds.skinSmooth ||
      id == MetaOpIds.skinToneLighting ||
      id == MetaOpIds.blemishReduction ||
      id == MetaOpIds.noiseReduction ||
      id == MetaOpIds.lowLightRecovery ||
      id == MetaOpIds.hazeRemoval ||
      id == MetaOpIds.detailSharpening ||
      MetaOpIds.hslChannels.contains(id);

  Widget _buildSelectedTool() {
    final enabled = widget.editingEnabled && !widget.interactionsBlocked;
    final selectedId = _selectedMetaOpId;
    if (widget.entryPoint == EditorEntryPoint.optimize && selectedId == null) {
      return _AdjustmentToolStrip(
        scope: _AdjustmentToolScope.quality,
        enabled: enabled,
        extended: true,
        photoToolsVisible: widget.photoToolsVisible,
        portraitAvailable: widget.portraitApplicable,
        faceSlimAvailable: widget.faceSlimApplicable,
        faceSlimReason: widget.faceSlimReason,
        faceSlimTargetCount: widget.faceSlimTargetCount,
        faceTargetRegions: widget.faceTargetRegions,
        stableFaceTargets: widget.stableFaceTargets,
        bodyAvailable: widget.bodyApplicable,
        bodyTargetCount: widget.bodyTargetCount,
        bodyTargetRegions: widget.bodyTargetRegions,
        photo: widget.selected,
        recipe: widget.recipe,
        editorSession: widget.editorSession,
        onRecipeCommitted: widget.onRecipeCommitted,
      );
    }
    if (selectedId == MetaOpIds.compositionGeometry) {
      return _CompositionTools(
        enabled: enabled,
        photo: widget.selected,
        recipe: widget.recipe,
        editorSession: widget.editorSession,
        onRecipeCommitted: widget.onRecipeCommitted,
      );
    }
    if (selectedId == MetaOpIds.filter) {
      return _FilterHslTools(
        enabled: enabled,
        recipe: widget.recipe,
        editorSession: widget.editorSession,
        onRecipeCommitted: widget.onRecipeCommitted,
        mode: _FilterHslMode.filter,
      );
    }
    if (selectedId == MetaOpIds.semanticAdjustments) {
      return _SemanticTools(
        enabled: enabled,
        subjectAvailable: widget.portraitApplicable || widget.bodyApplicable,
        photo: widget.selected,
        recipe: widget.recipe,
        editorSession: widget.editorSession,
        onRecipeCommitted: widget.onRecipeCommitted,
      );
    }
    if (selectedId == MetaOpIds.noiseReduction ||
        selectedId == MetaOpIds.lowLightRecovery ||
        selectedId == MetaOpIds.hazeRemoval ||
        selectedId == MetaOpIds.detailSharpening) {
      return _AdjustmentToolStrip(
        scope: _AdjustmentToolScope.quality,
        initialMetaOpId: selectedId,
        enabled: enabled,
        extended: true,
        photoToolsVisible: widget.photoToolsVisible,
        portraitAvailable: widget.portraitApplicable,
        faceSlimAvailable: widget.faceSlimApplicable,
        faceSlimReason: widget.faceSlimReason,
        faceSlimTargetCount: widget.faceSlimTargetCount,
        faceTargetRegions: widget.faceTargetRegions,
        stableFaceTargets: widget.stableFaceTargets,
        bodyAvailable: widget.bodyApplicable,
        bodyTargetCount: widget.bodyTargetCount,
        bodyTargetRegions: widget.bodyTargetRegions,
        photo: widget.selected,
        recipe: widget.recipe,
        editorSession: widget.editorSession,
        onRecipeCommitted: widget.onRecipeCommitted,
      );
    }
    if (selectedId == MetaOpIds.skinSmooth ||
        selectedId == MetaOpIds.skinToneLighting ||
        selectedId == MetaOpIds.blemishReduction ||
        selectedId == MetaOpIds.faceGeometry ||
        selectedId == MetaOpIds.bodyGeometry) {
      return _AdjustmentToolStrip(
        scope: _AdjustmentToolScope.portrait,
        initialMetaOpId: selectedId,
        enabled: enabled,
        extended: true,
        photoToolsVisible: widget.photoToolsVisible,
        portraitAvailable: widget.portraitApplicable,
        faceSlimAvailable: widget.faceSlimApplicable,
        faceSlimReason: widget.faceSlimReason,
        faceSlimTargetCount: widget.faceSlimTargetCount,
        faceTargetRegions: widget.faceTargetRegions,
        stableFaceTargets: widget.stableFaceTargets,
        bodyAvailable: widget.bodyApplicable,
        bodyTargetCount: widget.bodyTargetCount,
        bodyTargetRegions: widget.bodyTargetRegions,
        photo: widget.selected,
        recipe: widget.recipe,
        editorSession: widget.editorSession,
        onRecipeCommitted: widget.onRecipeCommitted,
      );
    }
    final hslIndex = MetaOpIds.hslChannels.indexOf(selectedId ?? '');
    if (hslIndex >= 0) {
      return _FilterHslTools(
        enabled: enabled,
        recipe: widget.recipe,
        editorSession: widget.editorSession,
        onRecipeCommitted: widget.onRecipeCommitted,
        mode: _FilterHslMode.hsl,
        initialChannel: HslChannel.values[hslIndex],
      );
    }
    return _AdjustmentToolStrip(
      compact: true,
      scope: _AdjustmentToolScope.common,
      initialMetaOpId: selectedId,
      manualMetaOpIds: _frozenManualMetaOpIds,
      enabled: enabled,
      extended: false,
      photoToolsVisible: widget.photoToolsVisible,
      portraitAvailable: widget.portraitApplicable,
      faceSlimAvailable: widget.faceSlimApplicable,
      faceSlimReason: widget.faceSlimReason,
      faceSlimTargetCount: widget.faceSlimTargetCount,
      faceTargetRegions: widget.faceTargetRegions,
      stableFaceTargets: widget.stableFaceTargets,
      bodyAvailable: widget.bodyApplicable,
      bodyTargetCount: widget.bodyTargetCount,
      bodyTargetRegions: widget.bodyTargetRegions,
      photo: widget.selected,
      recipe: widget.recipe,
      editorSession: widget.editorSession,
      onRecipeCommitted: widget.onRecipeCommitted,
    );
  }
}

class _InlineMetaOpBrowser extends StatefulWidget {
  const _InlineMetaOpBrowser({
    required this.editorSession,
    required this.applicability,
    required this.onSelected,
  });

  final EditorSession editorSession;
  final Set<String> applicability;
  final ValueChanged<String> onSelected;

  @override
  State<_InlineMetaOpBrowser> createState() => _InlineMetaOpBrowserState();
}

class _InlineMetaOpBrowserState extends State<_InlineMetaOpBrowser> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final availability = widget.editorSession.metaOpAvailability(
      applicability: widget.applicability,
    );
    final ids = _query.trim().isEmpty
        ? availability.searchIds
        : availability.search(MetaOpCatalog.standard, _query);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          TextField(
            key: const ValueKey('editor-meta-op-search'),
            autofocus: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.l10n.metaOpSearchHint,
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          if (ids.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  context.l10n.metaOpSearchNoResults,
                  key: const ValueKey('editor-meta-op-search-empty'),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: ids.length,
                itemBuilder: (context, index) {
                  final id = ids[index];
                  return ListTile(
                    key: ValueKey('editor-meta-op-result-$id'),
                    minTileHeight: 48,
                    leading: const Icon(Icons.tune),
                    title: Text(_metaOpLabel(context, id)),
                    onTap: () => widget.onSelected(id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

String _metaOpLabel(BuildContext context, String id) => switch (id) {
  MetaOpIds.compositionGeometry => context.l10n.composition,
  MetaOpIds.exposure => context.l10n.exposure,
  MetaOpIds.highlights => context.l10n.highlights,
  MetaOpIds.shadows => context.l10n.shadows,
  MetaOpIds.contrast => context.l10n.contrast,
  MetaOpIds.warmth => context.l10n.warmth,
  MetaOpIds.tint => context.l10n.tint,
  MetaOpIds.saturation => context.l10n.saturation,
  MetaOpIds.clarity => context.l10n.clarity,
  MetaOpIds.noiseReduction => context.l10n.noiseReduction,
  MetaOpIds.lowLightRecovery => context.l10n.lowLightRecovery,
  MetaOpIds.hazeRemoval => context.l10n.hazeRemoval,
  MetaOpIds.detailSharpening => context.l10n.detailSharpening,
  MetaOpIds.filter => context.l10n.filterAndHsl,
  MetaOpIds.hslRed => context.l10n.hslRed,
  MetaOpIds.hslOrange => context.l10n.hslOrange,
  MetaOpIds.hslYellow => context.l10n.hslYellow,
  MetaOpIds.hslGreen => context.l10n.hslGreen,
  MetaOpIds.hslCyan => context.l10n.hslCyan,
  MetaOpIds.hslBlue => context.l10n.hslBlue,
  MetaOpIds.hslPurple => context.l10n.hslPurple,
  MetaOpIds.hslMagenta => context.l10n.hslMagenta,
  MetaOpIds.skinSmooth => context.l10n.textureSmoothing,
  MetaOpIds.skinToneLighting => context.l10n.skinToneLighting,
  MetaOpIds.blemishReduction => context.l10n.blemishReduction,
  MetaOpIds.faceGeometry => context.l10n.faceSlim,
  MetaOpIds.bodyGeometry => context.l10n.bodySlim,
  MetaOpIds.semanticAdjustments => context.l10n.semanticTools,
  _ => id,
};

class _EditFeedback {
  const _EditFeedback({required this.message});

  final String message;
}

class _RecipeSaveFailure {
  const _RecipeSaveFailure({required this.desiredRecipe});

  final EditRecipe desiredRecipe;
}

class _EditSavePending extends StatelessWidget {
  const _EditSavePending();

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('editor-edit-save-pending'),
    liveRegion: true,
    label: context.l10n.editSavePending,
    child: const LinearProgressIndicator(minHeight: 3),
  );
}

class _EditSaveRecovery extends StatelessWidget {
  const _EditSaveRecovery({required this.onRetry, required this.onDiscard});

  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('editor-edit-save-failed'),
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.projectSaveFailed,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colors.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.editSaveRecoveryMessage,
              style: TextStyle(color: colors.onErrorContainer),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  key: const ValueKey('editor-edit-save-retry'),
                  onPressed: onRetry,
                  child: Text(context.l10n.retry),
                ),
                TextButton(
                  key: const ValueKey('editor-edit-save-discard'),
                  onPressed: onDiscard,
                  child: Text(context.l10n.discardAdjustment),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingManualRender {
  const _PendingManualRender({
    required this.photoId,
    required this.editableRecipe,
    required this.renderedRecipe,
  });

  final String photoId;
  final EditRecipe editableRecipe;
  final EditRecipe renderedRecipe;
}

class _ResultFeedbackPill extends StatelessWidget {
  const _ResultFeedbackPill({required this.feedback, required this.onUndo});

  final _EditFeedback feedback;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('editor-feedback-pill'),
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: colors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(feedback.message)),
              TextButton(
                key: const ValueKey('editor-feedback-undo'),
                onPressed: onUndo,
                child: Text(context.l10n.undo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveSuccessView extends StatelessWidget {
  const _SaveSuccessView({
    required this.onFinish,
    required this.onShare,
    required this.sharing,
  });

  final VoidCallback onFinish;
  final VoidCallback? onShare;
  final bool sharing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('editor-save-success'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded, color: colors.primary, size: 42),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.savedToSystemPhotos,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 28),
            FilledButton(
              key: const ValueKey('save-finish'),
              onPressed: sharing ? null : onFinish,
              child: Text(context.l10n.finish),
            ),
            if (onShare != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const ValueKey('save-share'),
                onPressed: sharing ? null : onShare,
                icon: const Icon(Icons.ios_share_outlined),
                label: Text(
                  sharing
                      ? context.l10n.sharingPhotos
                      : context.l10n.shareSavedPhotos,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditorCommandBar extends StatelessWidget {
  const _EditorCommandBar({
    required this.editingEnabled,
    required this.exporting,
    required this.sharing,
    required this.exportSummary,
    required this.feedback,
    required this.onVoiceEdit,
    required this.onManualEdit,
    required this.onAtmosphere,
    required this.onUndo,
    required this.onQuickEdit,
    required this.onCancelExport,
    required this.onContinueEditing,
  });

  final bool editingEnabled;
  final bool exporting;
  final bool sharing;
  final BatchExportSummary? exportSummary;
  final _EditFeedback? feedback;
  final VoidCallback onVoiceEdit;
  final VoidCallback onManualEdit;
  final VoidCallback onAtmosphere;
  final VoidCallback onUndo;
  final ValueChanged<String> onQuickEdit;
  final VoidCallback onCancelExport;
  final VoidCallback onContinueEditing;

  @override
  Widget build(BuildContext context) {
    final interactionsBlocked = exporting || sharing || exportSummary != null;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 0,
      child: SafeArea(
        key: const ValueKey('editor-bottom-command-bar'),
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: LayoutBuilder(
          builder: (context, constraints) => DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: interactionsBlocked
                  ? SizedBox(
                      width: double.infinity,
                      child: _statusAction(context),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (feedback != null) ...[
                          _ResultFeedbackPill(
                            feedback: feedback!,
                            onUndo: onUndo,
                          ),
                          const SizedBox(height: 10),
                        ],
                        Center(
                          child: Container(
                            width: 48,
                            height: 4,
                            decoration: BoxDecoration(
                              color: colors.onSurfaceVariant.withValues(
                                alpha: 0.35,
                              ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _QuickSuggestionButton(
                                key: const ValueKey(
                                  'editor-quick-suggestion-0',
                                ),
                                label: context.l10n.quickNatural,
                                onPressed: editingEnabled
                                    ? () => onQuickEdit('皮肤自然一点')
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _QuickSuggestionButton(
                                key: const ValueKey(
                                  'editor-quick-suggestion-1',
                                ),
                                label: context.l10n.quickBrighten,
                                onPressed: editingEnabled
                                    ? () => onQuickEdit('照片亮一点')
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _QuickSuggestionButton(
                                key: const ValueKey(
                                  'editor-quick-suggestion-2',
                                ),
                                label: context.l10n.quickAtmosphere,
                                emphasized: true,
                                onPressed: editingEnabled ? onAtmosphere : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: OutlinedButton.icon(
                                key: const ValueKey('voice-edit-entry'),
                                onPressed: editingEnabled ? onVoiceEdit : null,
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  foregroundColor: colors.onSurfaceVariant,
                                  minimumSize: const Size.fromHeight(52),
                                ),
                                icon: const Icon(
                                  Icons.mic_none_rounded,
                                  color: Color(0xFFE6BC45),
                                ),
                                label: Text(context.l10n.voiceEditPrompt),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Semantics(
                                key: const ValueKey('editor-open-tools'),
                                button: true,
                                child: FilledButton.tonal(
                                  key: const ValueKey('editor-manual-entry'),
                                  onPressed: editingEnabled
                                      ? onManualEdit
                                      : null,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                  ),
                                  child: Text(context.l10n.adjustPhoto),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusAction(BuildContext context) {
    if (exporting) {
      return Semantics(
        container: true,
        liveRegion: true,
        label: context.l10n.exportingPhotos,
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: null,
                icon: const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: Text(context.l10n.exportingPhotos),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onCancelExport,
              icon: const Icon(Icons.cancel_outlined),
              label: Text(context.l10n.cancelExport),
            ),
          ],
        ),
      );
    }
    if (exportSummary != null) {
      return TextButton(
        key: const ValueKey('export-continue-editing'),
        onPressed: sharing ? null : onContinueEditing,
        child: Text(context.l10n.continueEditing),
      );
    }
    return const SizedBox.shrink();
  }
}

class _QuickSuggestionButton extends StatelessWidget {
  const _QuickSuggestionButton({
    required this.label,
    required this.onPressed,
    this.emphasized = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      foregroundColor: emphasized
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurface,
      backgroundColor: emphasized
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      side: BorderSide(
        color: emphasized
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
    ),
    child: Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

class _ExportSummaryCard extends StatelessWidget {
  const _ExportSummaryCard({
    required this.summary,
    required this.exporting,
    required this.sharing,
    required this.onRetry,
    required this.onShare,
  });

  final BatchExportSummary summary;
  final bool exporting;
  final bool sharing;
  final VoidCallback onRetry;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('export-summary-card'),
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
                  key: const ValueKey('export-retry-failed'),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingProgressView extends StatelessWidget {
  const _SavingProgressView({required this.stage});

  final PhotoExportStage stage;

  @override
  Widget build(BuildContext context) {
    final message = stage == PhotoExportStage.savingToPhotoLibrary
        ? context.l10n.savingToSystemPhotos
        : context.l10n.preparingExport;
    return Semantics(
      key: const ValueKey('editor-saving-progress'),
      container: true,
      liveRegion: true,
      label: message,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 20),
            const LinearProgressIndicator(minHeight: 5),
            const Spacer(),
            TextButton(
              key: const ValueKey('export-continue-editing-disabled'),
              onPressed: null,
              child: Text(context.l10n.backToEditing),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartialSaveView extends StatelessWidget {
  const _PartialSaveView({
    required this.exporting,
    required this.sharing,
    required this.permissionDenied,
    required this.onRetry,
    required this.onBackToEditing,
    required this.onOpenSettings,
  });

  final bool exporting;
  final bool sharing;
  final bool permissionDenied;
  final VoidCallback onRetry;
  final VoidCallback onBackToEditing;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('editor-partial-save'),
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 42, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 52,
            ),
            const SizedBox(height: 18),
            Text(
              permissionDenied
                  ? context.l10n.photoPermissionPurpose
                  : context.l10n.exportFailedTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Spacer(),
            if (permissionDenied)
              FilledButton(
                key: const ValueKey('export-open-settings'),
                onPressed: exporting || sharing ? null : onOpenSettings,
                child: Text(context.l10n.goToSystemSettings),
              )
            else
              FilledButton(
                key: const ValueKey('export-retry-failed'),
                onPressed: exporting || sharing ? null : onRetry,
                child: Text(context.l10n.retry),
              ),
            TextButton(
              key: const ValueKey('export-continue-editing'),
              onPressed: exporting ? null : onBackToEditing,
              child: Text(context.l10n.backToEditing),
            ),
          ],
        ),
      ),
    );
  }
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

class _FullscreenPhotoPreview extends StatefulWidget {
  const _FullscreenPhotoPreview({
    required this.photo,
    required this.recipe,
    required this.editState,
    required this.editContext,
    required this.renderer,
    required this.position,
    required this.count,
    required this.onClose,
  });

  final ProjectPhoto photo;
  final EditRecipe recipe;
  final EditState editState;
  final EditContext editContext;
  final PhotoPreviewRenderer renderer;
  final int position;
  final int count;
  final VoidCallback onClose;

  @override
  State<_FullscreenPhotoPreview> createState() =>
      _FullscreenPhotoPreviewState();
}

class _FullscreenPhotoPreviewState extends State<_FullscreenPhotoPreview> {
  final TransformationController _transformation = TransformationController();
  bool _controlsVisible = true;
  bool _zoomed = false;

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    setState(() {
      _zoomed = !_zoomed;
      _transformation.value = _zoomed
          ? Matrix4.diagonal3Values(2, 2, 1)
          : Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('editor-fullscreen-preview'),
      color: const Color(0xFF0B0D0E),
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            transformationController: _transformation,
            minScale: 1,
            maxScale: 4,
            child: GestureDetector(
              key: const ValueKey('editor-fullscreen-preview-surface'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _controlsVisible = !_controlsVisible),
              onDoubleTap: _toggleZoom,
              child: _BeforeAfterPreview(
                key: ValueKey('fullscreen-photo-preview-${widget.photo.id}'),
                sourcePath: widget.photo.localPath,
                recipe: widget.recipe,
                sourceId: widget.photo.id,
                editState: widget.editState,
                editContext: widget.editContext,
                renderer: widget.renderer,
                immersive: true,
              ),
            ),
          ),
          if (_controlsVisible)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        key: const ValueKey('editor-fullscreen-close'),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      if (widget.count > 1)
                        _PreviewOverlayLabel(
                          label: '${widget.position} / ${widget.count}',
                        ),
                      const Spacer(),
                      _PreviewOverlayLabel(
                        label: context.l10n.fullscreenAdjusted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_controlsVisible)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _PreviewOverlayLabel(
                    label: context.l10n.fullscreenPreviewHint,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewOverlayLabel extends StatelessWidget {
  const _PreviewOverlayLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF0B0D0E).withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: const Color(0xFFF6F2EA)),
      ),
    ),
  );
}

class _BeforeAfterPreview extends StatefulWidget {
  const _BeforeAfterPreview({
    required this.sourcePath,
    required this.recipe,
    required this.renderer,
    this.sourceId,
    this.editState,
    this.editContext = EditContext.ios,
    this.immersive = false,
    this.onRendered,
    this.onRenderFailed,
    super.key,
  });

  final String sourcePath;
  final EditRecipe recipe;
  final PhotoPreviewRenderer renderer;
  final String? sourceId;
  final EditState? editState;
  final EditContext editContext;
  final bool immersive;
  final ValueChanged<EditRecipe>? onRendered;
  final ValueChanged<EditRecipe>? onRenderFailed;

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
    final editState = _showOriginal && widget.editState != null
        ? EditState(
            version: widget.editState!.version,
            values: const LegacyEditRecipeAdapter()
                .read(recipe, photoId: widget.sourceId)
                .values,
          )
        : widget.editState;
    return GestureDetector(
      key: widget.immersive ? null : const ValueKey('editor-preview-surface'),
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => setState(() => _showOriginal = true),
      onLongPressEnd: (_) => setState(() => _showOriginal = false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          NativePhotoPreview(
            sourcePath: widget.sourcePath,
            recipe: recipe,
            sourceId: widget.sourceId,
            editState: editState,
            editContext: widget.editContext,
            renderer: widget.renderer,
            retryToken: _retryToken,
            onRendered: widget.onRendered,
            onRenderFailed: widget.onRenderFailed,
            errorBuilder: (context) => Semantics(
              liveRegion: true,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        !widget.recipe.crop.isOriginal
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
          if (!widget.immersive)
            Positioned(
              top: 12,
              right: 12,
              child: MediaQuery.sizeOf(context).width < 700
                  ? IconButton.filledTonal(
                      key: const ValueKey('editor-compare-photo'),
                      tooltip: _showOriginal
                          ? context.l10n.compareEdited
                          : context.l10n.compareOriginal,
                      onPressed: () =>
                          setState(() => _showOriginal = !_showOriginal),
                      icon: Icon(
                        _showOriginal
                            ? Icons.auto_fix_high
                            : Icons.compare_outlined,
                      ),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: () =>
                          setState(() => _showOriginal = !_showOriginal),
                      icon: Icon(
                        _showOriginal
                            ? Icons.auto_fix_high
                            : Icons.compare_outlined,
                      ),
                      label: Text(
                        _showOriginal
                            ? context.l10n.compareEdited
                            : context.l10n.compareOriginal,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

enum _AdjustmentToolScope { common, color, quality, portrait }

enum _AdjustmentParameter {
  exposure,
  highlights,
  shadows,
  contrast,
  warmth,
  tint,
  saturation,
  clarity,
  qualityImprovement,
  noiseReduction,
  lowLightRecovery,
  hazeRemoval,
  detailSharpening,
  naturalBeautification,
  textureSmoothing,
  skinToneLighting,
  blemishReduction,
  faceSlim,
  headSize,
  jaw,
  chin,
  eyes,
  nose,
  mouth,
  bodySlim,
  height,
  shoulders,
  waist,
  legs,
}

class _AdjustmentToolStrip extends StatefulWidget {
  const _AdjustmentToolStrip({
    this.compact = false,
    this.initialMetaOpId,
    this.manualMetaOpIds,
    required this.scope,
    required this.enabled,
    required this.extended,
    required this.photoToolsVisible,
    required this.portraitAvailable,
    required this.faceSlimAvailable,
    required this.faceSlimReason,
    required this.faceSlimTargetCount,
    required this.faceTargetRegions,
    required this.stableFaceTargets,
    required this.bodyAvailable,
    required this.bodyTargetCount,
    required this.bodyTargetRegions,
    required this.photo,
    required this.recipe,
    required this.editorSession,
    required this.onRecipeCommitted,
  });

  final bool compact;
  final String? initialMetaOpId;
  final List<String>? manualMetaOpIds;
  final _AdjustmentToolScope scope;
  final bool enabled;
  final bool extended;
  final bool photoToolsVisible;
  final bool portraitAvailable;
  final bool faceSlimAvailable;
  final PortraitDegradationReason faceSlimReason;
  final int faceSlimTargetCount;
  final List<NormalizedTargetRegion> faceTargetRegions;
  final List<StableEditTarget> stableFaceTargets;
  final bool bodyAvailable;
  final int bodyTargetCount;
  final List<NormalizedTargetRegion> bodyTargetRegions;
  final ProjectPhoto photo;
  final EditRecipe recipe;
  final EditorSession editorSession;
  final VoidCallback onRecipeCommitted;

  @override
  State<_AdjustmentToolStrip> createState() => _AdjustmentToolStripState();
}

class _AdjustmentToolStripState extends State<_AdjustmentToolStrip> {
  late _AdjustmentParameter _selected;
  String? _selectedStableFaceTargetId;

  @override
  void initState() {
    super.initState();
    _selected = _initialSelection();
    _selectedStableFaceTargetId = _preferredStableFaceTargetId();
  }

  @override
  void didUpdateWidget(covariant _AdjustmentToolStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.id != widget.photo.id ||
        !widget.stableFaceTargets.any(
          (target) => target.id == _selectedStableFaceTargetId,
        )) {
      _selectedStableFaceTargetId = null;
    }
    if (oldWidget.scope != widget.scope ||
        oldWidget.initialMetaOpId != widget.initialMetaOpId) {
      _selected = _initialSelection();
      _selectedStableFaceTargetId = _preferredStableFaceTargetId();
    }
  }

  @override
  Widget build(BuildContext context) {
    final parameters = _parameters();
    final selected =
        parameters.contains(_selected) ||
            (widget.photoToolsVisible && _isQualityDetail(_selected)) ||
            (widget.photoToolsVisible && _isNaturalDetail(_selected)) ||
            (widget.photoToolsVisible && _isFaceGeometry(_selected)) ||
            (widget.photoToolsVisible && _isBodyGeometry(_selected))
        ? _selected
        : parameters.first;
    var effectiveRecipe = widget.editorSession.recipe;
    if (widget.faceSlimTargetCount > 0) {
      effectiveRecipe = effectiveRecipe.copyWith(
        portraitGeometryRecipe: effectiveRecipe.portraitGeometryRecipe
            .withFaceTargetCount(widget.faceSlimTargetCount),
      );
    }
    if (widget.bodyTargetCount > 0) {
      effectiveRecipe = effectiveRecipe.copyWith(
        portraitGeometryRecipe: effectiveRecipe.portraitGeometryRecipe
            .withBodyTargetCount(widget.bodyTargetCount),
      );
    }
    final selectedLabel = _visibleLabel(context, selected);
    final selectedValue = _value(effectiveRecipe, selected);
    final selectedIsPortrait = _isPortrait(selected);
    final selectedIsQuality = _isQuality(selected);
    final selectedAvailable = _isSelectedToolAvailable(selected);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final portraitReady =
        widget.photoToolsVisible &&
        (widget.portraitAvailable || widget.bodyAvailable);
    if (widget.compact) {
      return _buildCompact(
        context,
        parameters: parameters,
        selected: selected,
        effectiveRecipe: effectiveRecipe,
        selectedLabel: selectedLabel,
        selectedValue: selectedValue,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              selectedIsPortrait
                  ? Icons.face_retouching_natural
                  : selectedIsQuality
                  ? Icons.auto_fix_high_outlined
                  : Icons.tune,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              selectedIsPortrait
                  ? context.l10n.portraitTools
                  : selectedIsQuality
                  ? context.l10n.qualityTools
                  : context.l10n.lightAndColorTools,
              key: const ValueKey('editor-adjustment-section'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (widget.scope == _AdjustmentToolScope.portrait &&
                portraitReady) ...[
              const Spacer(),
              Flexible(
                child: _PortraitToolStatus(
                  photoToolsVisible: widget.photoToolsVisible,
                  available: true,
                ),
              ),
            ],
          ],
        ),
        if (widget.scope == _AdjustmentToolScope.portrait &&
            !portraitReady) ...[
          const SizedBox(height: 4),
          _PortraitToolStatus(
            photoToolsVisible: widget.photoToolsVisible,
            available: false,
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: largeText ? 104 : 64,
          child: ListView.separated(
            key: const ValueKey('editor-adjustment-tabs'),
            scrollDirection: Axis.horizontal,
            itemCount: parameters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final parameter = parameters[index];
              final label = _label(context, parameter);
              final isSelected =
                  parameter == selected ||
                  (parameter == _AdjustmentParameter.qualityImprovement &&
                      _isQualityDetail(selected)) ||
                  (parameter == _AdjustmentParameter.naturalBeautification &&
                      _isNaturalDetail(selected)) ||
                  (parameter == _AdjustmentParameter.faceSlim &&
                      _isFaceGeometry(selected)) ||
                  (parameter == _AdjustmentParameter.bodySlim &&
                      _isBodyGeometry(selected));
              void select() => setState(() => _selected = parameter);
              return _AdjustmentToolButton(
                key: ValueKey('editor-adjustment-tab-${parameter.name}'),
                enabled: widget.enabled,
                selected: isSelected,
                label: label,
                icon: _icon(parameter),
                largeText: largeText,
                onTap: widget.enabled ? select : null,
              );
            },
          ),
        ),
        if (selected == _AdjustmentParameter.naturalBeautification ||
            _isNaturalDetail(selected)) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: largeText ? 104 : 64,
            child: ListView.separated(
              key: const ValueKey('editor-natural-beautification-tabs'),
              scrollDirection: Axis.horizontal,
              itemCount: _naturalDetailParameters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final parameter = _naturalDetailParameters[index];
                return _AdjustmentToolButton(
                  key: ValueKey('editor-adjustment-tab-${parameter.name}'),
                  enabled: widget.enabled,
                  selected: parameter == selected,
                  label: _label(context, parameter),
                  icon: _icon(parameter),
                  largeText: largeText,
                  onTap: widget.enabled
                      ? () => setState(() => _selected = parameter)
                      : null,
                );
              },
            ),
          ),
        ],
        if (selected == _AdjustmentParameter.qualityImprovement ||
            _isQualityDetail(selected)) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: largeText ? 104 : 64,
            child: ListView.separated(
              key: const ValueKey('editor-quality-improvement-tabs'),
              scrollDirection: Axis.horizontal,
              itemCount: _qualityDetailParameters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final parameter = _qualityDetailParameters[index];
                return _AdjustmentToolButton(
                  key: ValueKey('editor-adjustment-tab-${parameter.name}'),
                  enabled: widget.enabled,
                  selected: parameter == selected,
                  label: _label(context, parameter),
                  icon: _icon(parameter),
                  largeText: largeText,
                  onTap: widget.enabled
                      ? () => setState(() => _selected = parameter)
                      : null,
                );
              },
            ),
          ),
        ],
        if (_isFaceGeometry(selected)) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: largeText ? 104 : 64,
            child: ListView.separated(
              key: const ValueKey('editor-face-geometry-tabs'),
              scrollDirection: Axis.horizontal,
              itemCount: _faceGeometryParameters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final parameter = _faceGeometryParameters[index];
                return _AdjustmentToolButton(
                  key: ValueKey('editor-adjustment-tab-${parameter.name}'),
                  enabled: widget.enabled,
                  selected: parameter == selected,
                  label: _label(context, parameter),
                  icon: _icon(parameter),
                  largeText: largeText,
                  onTap: widget.enabled
                      ? () => setState(() => _selected = parameter)
                      : null,
                );
              },
            ),
          ),
        ],
        if (_isBodyGeometry(selected)) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: largeText ? 104 : 64,
            child: ListView.separated(
              key: const ValueKey('editor-body-geometry-tabs'),
              scrollDirection: Axis.horizontal,
              itemCount: _bodyGeometryParameters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final parameter = _bodyGeometryParameters[index];
                return _AdjustmentToolButton(
                  key: ValueKey('editor-adjustment-tab-${parameter.name}'),
                  enabled: widget.enabled,
                  selected: parameter == selected,
                  label: _label(context, parameter),
                  icon: _icon(parameter),
                  largeText: largeText,
                  onTap: widget.enabled
                      ? () => setState(() => _selected = parameter)
                      : null,
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (!selectedAvailable)
          _SelectedToolUnavailable(
            key: ValueKey(
              _isFaceGeometry(selected)
                  ? 'editor-face-slim-unavailable'
                  : _isBodyGeometry(selected)
                  ? 'editor-body-tools-unavailable'
                  : 'editor-portrait-tools-unavailable',
            ),
            message: _selectedToolUnavailableMessage(context, selected),
          )
        else if (selected == _AdjustmentParameter.qualityImprovement)
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('editor-apply-quality-improvement'),
                  onPressed: widget.enabled
                      ? () {
                          widget.editorSession.apply(
                            widget.recipe.copyWith(
                              qualityEnhancementRecipe:
                                  QualityEnhancementRecipe.safeAutomatic,
                            ),
                          );
                          widget.onRecipeCommitted();
                        }
                      : null,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: Text(context.l10n.applyQualityImprovement),
                ),
              ),
            ],
          )
        else if (selected == _AdjustmentParameter.naturalBeautification)
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey(
                    'editor-apply-one-tap-natural-beautification',
                  ),
                  onPressed: widget.enabled
                      ? () {
                          widget.editorSession.apply(
                            _applyNaturalBeautification(widget.recipe),
                          );
                          widget.onRecipeCommitted();
                        }
                      : null,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(context.l10n.applyNaturalBeautification),
                ),
              ),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isNaturalDetail(selected) &&
                  _currentStableFaceTarget() == null) ...[
                _buildStableFaceTargetSelector(),
                const SizedBox(height: 8),
              ],
              if (_isFaceGeometry(selected) &&
                  widget.faceTargetRegions.length ==
                      widget.faceSlimTargetCount &&
                  widget.faceTargetRegions.isNotEmpty) ...[
                _PortraitTargetSelector(
                  key: const ValueKey('editor-face-target-selector'),
                  photo: widget.photo,
                  regions: widget.faceTargetRegions,
                  selectedIndex:
                      effectiveRecipe.portraitGeometryRecipe.selectedFaceIndex,
                  targetLabel: context.l10n.faceSlimTarget,
                  hint: context.l10n.faceSlimTargetHint,
                  enabled: widget.enabled,
                  onSelected: (index) {
                    widget.editorSession.selectPortraitTarget(
                      effectiveRecipe.copyWith(
                        portraitGeometryRecipe: effectiveRecipe
                            .portraitGeometryRecipe
                            .selectFace(index),
                      ),
                    );
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
              ],
              if (_isBodyGeometry(selected) &&
                  widget.bodyTargetRegions.length == widget.bodyTargetCount &&
                  widget.bodyTargetRegions.isNotEmpty) ...[
                _PortraitTargetSelector(
                  key: const ValueKey('editor-body-target-selector'),
                  photo: widget.photo,
                  regions: widget.bodyTargetRegions,
                  selectedIndex:
                      effectiveRecipe.portraitGeometryRecipe.selectedBodyIndex,
                  targetLabel: context.l10n.bodyTarget,
                  hint: context.l10n.bodyTargetHint,
                  enabled: widget.enabled,
                  onSelected: (index) {
                    widget.editorSession.selectPortraitTarget(
                      effectiveRecipe.copyWith(
                        portraitGeometryRecipe: effectiveRecipe
                            .portraitGeometryRecipe
                            .selectBody(index),
                      ),
                    );
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
              ],
              if (_isFaceGeometry(selected) &&
                  widget.faceSlimTargetCount > 1) ...[
                Text(
                  context.l10n.faceSlimTargetHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (
                      var index = 0;
                      index < widget.faceSlimTargetCount;
                      index++
                    )
                      ChoiceChip(
                        key: ValueKey('editor-face-slim-target-$index'),
                        label: Text(context.l10n.faceSlimTarget(index + 1)),
                        selected:
                            effectiveRecipe
                                .portraitGeometryRecipe
                                .selectedFaceIndex ==
                            index,
                        onSelected: widget.enabled
                            ? (_) {
                                widget.editorSession.selectPortraitTarget(
                                  effectiveRecipe.copyWith(
                                    portraitGeometryRecipe: effectiveRecipe
                                        .portraitGeometryRecipe
                                        .selectFace(index),
                                  ),
                                );
                                setState(() {});
                              }
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_isBodyGeometry(selected) && widget.bodyTargetCount > 1) ...[
                Text(
                  context.l10n.bodyTargetHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var index = 0; index < widget.bodyTargetCount; index++)
                      ChoiceChip(
                        key: ValueKey('editor-body-target-$index'),
                        label: Text(context.l10n.bodyTarget(index + 1)),
                        selected:
                            effectiveRecipe
                                .portraitGeometryRecipe
                                .selectedBodyIndex ==
                            index,
                        onSelected: widget.enabled
                            ? (_) {
                                widget.editorSession.selectPortraitTarget(
                                  effectiveRecipe.copyWith(
                                    portraitGeometryRecipe: effectiveRecipe
                                        .portraitGeometryRecipe
                                        .selectBody(index),
                                  ),
                                );
                                setState(() {});
                              }
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (!_isNaturalDetail(selected) ||
                  _currentStableFaceTarget() != null)
                Row(
                  children: [
                    Expanded(
                      child: _AdjustmentSlider(
                        key: ValueKey('editor-adjustment-${selected.name}'),
                        enabled: widget.enabled,
                        label: selectedLabel,
                        semanticLabel: selectedLabel,
                        value: selectedValue,
                        minimum: _minimum(selected),
                        maximum: _maximum(selected),
                        onStart: widget.editorSession.beginAdjustment,
                        onChanged: (value) =>
                            _previewValue(effectiveRecipe, selected, value),
                        onEnd: () {
                          widget.editorSession.commitAdjustment();
                          widget.onRecipeCommitted();
                        },
                      ),
                    ),
                    if (selectedValue != 0) ...[
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        key: const ValueKey('editor-reset-current-adjustment'),
                        tooltip: context.l10n.resetCurrentAdjustment,
                        onPressed: widget.enabled
                            ? () {
                                _resetValue(effectiveRecipe, selected);
                                widget.onRecipeCommitted();
                              }
                            : null,
                        icon: const Icon(Icons.restart_alt),
                      ),
                    ],
                  ],
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCompact(
    BuildContext context, {
    required List<_AdjustmentParameter> parameters,
    required _AdjustmentParameter selected,
    required EditRecipe effectiveRecipe,
    required String selectedLabel,
    required double selectedValue,
  }) {
    final colors = Theme.of(context).colorScheme;
    if (!_isSelectedToolAvailable(selected)) {
      return Column(
        key: const ValueKey('editor-adjustment-section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            selectedLabel,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _SelectedToolUnavailable(
            key: ValueKey(
              _isFaceGeometry(selected)
                  ? 'editor-face-slim-unavailable'
                  : _isBodyGeometry(selected)
                  ? 'editor-body-tools-unavailable'
                  : 'editor-portrait-tools-unavailable',
            ),
            message: _selectedToolUnavailableMessage(context, selected),
          ),
        ],
      );
    }
    if (_isNaturalDetail(selected) && _currentStableFaceTarget() == null) {
      return Column(
        key: const ValueKey('editor-adjustment-section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_buildStableFaceTargetSelector()],
      );
    }
    final showsFaceTarget =
        _isFaceGeometry(selected) && widget.faceSlimTargetCount > 1;
    final showsBodyTarget =
        _isBodyGeometry(selected) && widget.bodyTargetCount > 1;
    return Column(
      key: const ValueKey('editor-adjustment-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                selectedLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              _displayAdjustmentValue(selectedValue),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: colors.primary),
            ),
            if (selectedValue != 0) ...[
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('editor-reset-current-adjustment'),
                tooltip: context.l10n.resetCurrentAdjustment,
                onPressed: widget.enabled
                    ? () {
                        _resetValue(effectiveRecipe, selected);
                        widget.onRecipeCommitted();
                      }
                    : null,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
            if (_isNaturalDetail(selected) &&
                widget.stableFaceTargets.length > 1)
              PopupMenuButton<String>(
                key: const ValueKey('editor-stable-face-target-menu'),
                tooltip: context.l10n.faceSlimTargetHint,
                onSelected: (targetId) =>
                    setState(() => _selectedStableFaceTargetId = targetId),
                itemBuilder: (context) => [
                  for (
                    var index = 0;
                    index < widget.stableFaceTargets.length;
                    index++
                  )
                    PopupMenuItem(
                      value: widget.stableFaceTargets[index].id,
                      child: Text(context.l10n.faceSlimTarget(index + 1)),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.people_alt_outlined,
                    color: colors.primary,
                    size: 20,
                  ),
                ),
              )
            else if (showsFaceTarget || showsBodyTarget)
              PopupMenuButton<int>(
                key: ValueKey(
                  showsFaceTarget
                      ? 'editor-face-target-selector'
                      : 'editor-body-target-selector',
                ),
                tooltip: showsFaceTarget
                    ? context.l10n.faceSlimTargetHint
                    : context.l10n.bodyTargetHint,
                onSelected: (index) {
                  final geometry = effectiveRecipe.portraitGeometryRecipe;
                  widget.editorSession.selectPortraitTarget(
                    effectiveRecipe.copyWith(
                      portraitGeometryRecipe: showsFaceTarget
                          ? geometry.selectFace(index)
                          : geometry.selectBody(index),
                    ),
                  );
                  setState(() {});
                },
                itemBuilder: (context) => [
                  for (
                    var index = 0;
                    index <
                        (showsFaceTarget
                            ? widget.faceSlimTargetCount
                            : widget.bodyTargetCount);
                    index++
                  )
                    PopupMenuItem(
                      key: ValueKey(
                        showsFaceTarget
                            ? 'editor-face-slim-target-$index'
                            : 'editor-body-target-$index',
                      ),
                      value: index,
                      child: Text(
                        showsFaceTarget
                            ? context.l10n.faceSlimTarget(index + 1)
                            : context.l10n.bodyTarget(index + 1),
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.people_alt_outlined,
                    color: colors.primary,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
        _AdjustmentSlider(
          key: ValueKey('editor-adjustment-${selected.name}'),
          enabled: widget.enabled,
          label: '',
          semanticLabel: selectedLabel,
          value: selectedValue,
          showValue: false,
          minimum: _minimum(selected),
          maximum: _maximum(selected),
          onStart: widget.editorSession.beginAdjustment,
          onChanged: (value) => _previewValue(effectiveRecipe, selected, value),
          onEnd: () {
            widget.editorSession.commitAdjustment();
            widget.onRecipeCommitted();
          },
        ),
        SizedBox(
          height: 68,
          child: ListView.separated(
            key: const ValueKey('editor-adjustment-tabs'),
            scrollDirection: Axis.horizontal,
            itemCount:
                parameters.length +
                (widget.scope == _AdjustmentToolScope.quality ? 1 : 0) +
                (widget.scope == _AdjustmentToolScope.portrait &&
                        widget.portraitAvailable
                    ? 1
                    : 0),
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final qualityQuick =
                  widget.scope == _AdjustmentToolScope.quality && index == 0;
              final portraitQuick =
                  widget.scope == _AdjustmentToolScope.portrait &&
                  widget.portraitAvailable &&
                  index == 0;
              if (qualityQuick || portraitQuick) {
                final parameter = qualityQuick
                    ? _AdjustmentParameter.qualityImprovement
                    : _AdjustmentParameter.naturalBeautification;
                return KeyedSubtree(
                  key: ValueKey(
                    qualityQuick
                        ? 'editor-apply-quality-improvement'
                        : 'editor-apply-one-tap-natural-beautification',
                  ),
                  child: _AdjustmentToolButton(
                    key: ValueKey('editor-adjustment-tab-${parameter.name}'),
                    enabled: widget.enabled,
                    selected: false,
                    label: _label(context, parameter),
                    icon: _icon(parameter),
                    largeText: false,
                    onTap: widget.enabled
                        ? () {
                            widget.editorSession.apply(
                              qualityQuick
                                  ? effectiveRecipe.copyWith(
                                      qualityEnhancementRecipe:
                                          QualityEnhancementRecipe
                                              .safeAutomatic,
                                    )
                                  : _applyNaturalBeautification(
                                      widget.editorSession.recipe,
                                    ),
                            );
                            widget.onRecipeCommitted();
                          }
                        : null,
                  ),
                );
              }
              final quickOffset =
                  (widget.scope == _AdjustmentToolScope.quality ||
                      (widget.scope == _AdjustmentToolScope.portrait &&
                          widget.portraitAvailable))
                  ? 1
                  : 0;
              final parameter = parameters[index - quickOffset];
              return _AdjustmentToolButton(
                key: ValueKey('editor-adjustment-tab-${parameter.name}'),
                enabled: widget.enabled,
                selected: parameter == selected,
                label: _visibleLabel(context, parameter),
                icon: _icon(parameter),
                largeText: false,
                onTap: widget.enabled
                    ? () => setState(() => _selected = parameter)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  String _displayAdjustmentValue(double value) {
    final scaled = (value * 100).round();
    return scaled > 0 ? '+$scaled' : '$scaled';
  }

  void _previewValue(
    EditRecipe recipe,
    _AdjustmentParameter parameter,
    double value,
  ) {
    final metaOpId = _globalMetaOpId(parameter);
    if (metaOpId != null) {
      widget.editorSession.previewMetaOp(_globalMetaOpAddress(metaOpId), value);
      return;
    }
    final qualityMetaOpId = _qualityMetaOpId(parameter);
    if (qualityMetaOpId != null) {
      widget.editorSession.previewMetaOp(
        _qualityMetaOpAddress(qualityMetaOpId),
        (value * 100).round(),
      );
      return;
    }
    if (_portraitMetaOpId(parameter) != null) {
      widget.editorSession.preview(
        _copyWith(widget.editorSession.recipe, parameter, value),
      );
      return;
    }
    widget.editorSession.preview(_copyWith(recipe, parameter, value));
  }

  void _resetValue(EditRecipe recipe, _AdjustmentParameter parameter) {
    final metaOpId = _globalMetaOpId(parameter);
    if (metaOpId != null) {
      widget.editorSession.applyMetaOp(_globalMetaOpAddress(metaOpId), 0.0);
      return;
    }
    final qualityMetaOpId = _qualityMetaOpId(parameter);
    if (qualityMetaOpId != null) {
      widget.editorSession.applyMetaOp(
        _qualityMetaOpAddress(qualityMetaOpId),
        0,
      );
      return;
    }
    if (_portraitMetaOpId(parameter) != null) {
      widget.editorSession.apply(
        _copyWith(widget.editorSession.recipe, parameter, 0),
      );
      return;
    }
    widget.editorSession.apply(_copyWith(recipe, parameter, 0));
  }

  String? _globalMetaOpId(_AdjustmentParameter parameter) =>
      switch (parameter) {
        _AdjustmentParameter.exposure => MetaOpIds.exposure,
        _AdjustmentParameter.highlights => MetaOpIds.highlights,
        _AdjustmentParameter.shadows => MetaOpIds.shadows,
        _AdjustmentParameter.contrast => MetaOpIds.contrast,
        _AdjustmentParameter.warmth => MetaOpIds.warmth,
        _AdjustmentParameter.tint => MetaOpIds.tint,
        _AdjustmentParameter.saturation => MetaOpIds.saturation,
        _AdjustmentParameter.clarity => MetaOpIds.clarity,
        _ => null,
      };

  String? _qualityMetaOpId(_AdjustmentParameter parameter) =>
      switch (parameter) {
        _AdjustmentParameter.noiseReduction => MetaOpIds.noiseReduction,
        _AdjustmentParameter.lowLightRecovery => MetaOpIds.lowLightRecovery,
        _AdjustmentParameter.hazeRemoval => MetaOpIds.hazeRemoval,
        _AdjustmentParameter.detailSharpening => MetaOpIds.detailSharpening,
        _ => null,
      };

  String? _portraitMetaOpId(_AdjustmentParameter parameter) =>
      switch (parameter) {
        _AdjustmentParameter.textureSmoothing => MetaOpIds.skinSmooth,
        _AdjustmentParameter.skinToneLighting => MetaOpIds.skinToneLighting,
        _AdjustmentParameter.blemishReduction => MetaOpIds.blemishReduction,
        _ => null,
      };

  OpAddress _globalMetaOpAddress(String id) => OpAddress(
    metaOpId: id,
    metaOpVersion: 1,
    parameterId: 'value',
    scope: EditScope.group,
  );

  OpAddress _qualityMetaOpAddress(String id) => OpAddress(
    metaOpId: id,
    metaOpVersion: 1,
    parameterId: 'value',
    scope: EditScope.currentPhoto,
    photoId: widget.photo.id,
  );

  _AdjustmentParameter _initialSelection() {
    final requested = _parameterForMetaOp(widget.initialMetaOpId);
    if (requested != null) return requested;
    if (widget.scope == _AdjustmentToolScope.common) {
      return _commonParameters().firstOrNull ?? _AdjustmentParameter.exposure;
    }
    return switch (widget.scope) {
      _AdjustmentToolScope.common => _AdjustmentParameter.exposure,
      _AdjustmentToolScope.color => _AdjustmentParameter.exposure,
      _AdjustmentToolScope.quality =>
        widget.compact
            ? _AdjustmentParameter.noiseReduction
            : _AdjustmentParameter.qualityImprovement,
      _AdjustmentToolScope.portrait =>
        widget.compact
            ? _AdjustmentParameter.textureSmoothing
            : _AdjustmentParameter.naturalBeautification,
    };
  }

  List<_AdjustmentParameter> _parameters() => switch (widget.scope) {
    _AdjustmentToolScope.common => _commonParameters(),
    _AdjustmentToolScope.color =>
      widget.extended
          ? const [
              _AdjustmentParameter.exposure,
              _AdjustmentParameter.highlights,
              _AdjustmentParameter.shadows,
              _AdjustmentParameter.contrast,
              _AdjustmentParameter.warmth,
              _AdjustmentParameter.tint,
              _AdjustmentParameter.saturation,
              _AdjustmentParameter.clarity,
            ]
          : const [
              _AdjustmentParameter.exposure,
              _AdjustmentParameter.contrast,
              _AdjustmentParameter.warmth,
            ],
    _AdjustmentToolScope.quality =>
      widget.compact
          ? _qualityDetailParameters
          : const [_AdjustmentParameter.qualityImprovement],
    _AdjustmentToolScope.portrait => [
      if (widget.compact && widget.photoToolsVisible)
        ..._naturalDetailParameters,
      if (!widget.compact && widget.photoToolsVisible)
        _AdjustmentParameter.naturalBeautification,
      if (widget.photoToolsVisible) _AdjustmentParameter.faceSlim,
      if (widget.photoToolsVisible) _AdjustmentParameter.bodySlim,
    ],
  };

  bool _isSelectedToolAvailable(_AdjustmentParameter parameter) {
    if (_isNaturalDetail(parameter) ||
        parameter == _AdjustmentParameter.naturalBeautification) {
      return widget.portraitAvailable;
    }
    if (_isFaceGeometry(parameter)) return widget.faceSlimAvailable;
    if (_isBodyGeometry(parameter)) return widget.bodyAvailable;
    return true;
  }

  String _selectedToolUnavailableMessage(
    BuildContext context,
    _AdjustmentParameter parameter,
  ) {
    if (_isFaceGeometry(parameter)) {
      return widget.faceSlimReason == PortraitDegradationReason.backgroundRisk
          ? context.l10n.faceSlimBackgroundProtected
          : widget.faceSlimReason == PortraitDegradationReason.multipleFaces
          ? context.l10n.faceSlimMultipleFaces
          : context.l10n.faceSlimUnavailable;
    }
    if (_isBodyGeometry(parameter)) return context.l10n.bodyToolsUnavailable;
    return context.l10n.portraitToolsUnavailable;
  }

  List<_AdjustmentParameter> _commonParameters() {
    final applicability = <String>{
      'photo',
      if (widget.photoToolsVisible && widget.portraitAvailable) 'face',
    };
    final available =
        widget.manualMetaOpIds ??
        widget.editorSession.orderedManualMetaOpIds(
          applicability: applicability,
        );
    final requested = _parameterForMetaOp(widget.initialMetaOpId);
    if (requested != null &&
        widget.initialMetaOpId != null &&
        available.contains(widget.initialMetaOpId)) {
      return [requested];
    }
    final parameters = <_AdjustmentParameter>[];
    for (final id in available) {
      final parameter = _parameterForMetaOp(id);
      if (parameter != null) parameters.add(parameter);
      if (parameters.length == 5) break;
    }
    return parameters;
  }

  _AdjustmentParameter? _parameterForMetaOp(String? id) => switch (id) {
    MetaOpIds.exposure => _AdjustmentParameter.exposure,
    MetaOpIds.highlights => _AdjustmentParameter.highlights,
    MetaOpIds.shadows => _AdjustmentParameter.shadows,
    MetaOpIds.contrast => _AdjustmentParameter.contrast,
    MetaOpIds.warmth => _AdjustmentParameter.warmth,
    MetaOpIds.tint => _AdjustmentParameter.tint,
    MetaOpIds.saturation => _AdjustmentParameter.saturation,
    MetaOpIds.clarity => _AdjustmentParameter.clarity,
    MetaOpIds.noiseReduction => _AdjustmentParameter.noiseReduction,
    MetaOpIds.lowLightRecovery => _AdjustmentParameter.lowLightRecovery,
    MetaOpIds.hazeRemoval => _AdjustmentParameter.hazeRemoval,
    MetaOpIds.detailSharpening => _AdjustmentParameter.detailSharpening,
    MetaOpIds.skinSmooth => _AdjustmentParameter.textureSmoothing,
    MetaOpIds.skinToneLighting => _AdjustmentParameter.skinToneLighting,
    MetaOpIds.blemishReduction => _AdjustmentParameter.blemishReduction,
    MetaOpIds.faceGeometry => _AdjustmentParameter.faceSlim,
    MetaOpIds.bodyGeometry => _AdjustmentParameter.bodySlim,
    _ => null,
  };

  bool _isPortrait(_AdjustmentParameter parameter) =>
      parameter == _AdjustmentParameter.naturalBeautification ||
      parameter == _AdjustmentParameter.textureSmoothing ||
      parameter == _AdjustmentParameter.skinToneLighting ||
      parameter == _AdjustmentParameter.blemishReduction ||
      _isFaceGeometry(parameter) ||
      _isBodyGeometry(parameter);

  String _visibleLabel(BuildContext context, _AdjustmentParameter parameter) {
    if (widget.scope != _AdjustmentToolScope.common) {
      return _label(context, parameter);
    }
    return switch (parameter) {
      _AdjustmentParameter.exposure => context.l10n.manualBrighter,
      _AdjustmentParameter.warmth => context.l10n.manualWarmer,
      _AdjustmentParameter.saturation => context.l10n.manualMoreVivid,
      _AdjustmentParameter.textureSmoothing => context.l10n.manualSmootherSkin,
      _AdjustmentParameter.faceSlim => context.l10n.manualSmallerFace,
      _ => _label(context, parameter),
    };
  }

  bool _isFaceGeometry(_AdjustmentParameter parameter) => const {
    _AdjustmentParameter.faceSlim,
    _AdjustmentParameter.headSize,
    _AdjustmentParameter.jaw,
    _AdjustmentParameter.chin,
    _AdjustmentParameter.eyes,
    _AdjustmentParameter.nose,
    _AdjustmentParameter.mouth,
  }.contains(parameter);

  bool _isBodyGeometry(_AdjustmentParameter parameter) => const {
    _AdjustmentParameter.bodySlim,
    _AdjustmentParameter.height,
    _AdjustmentParameter.shoulders,
    _AdjustmentParameter.waist,
    _AdjustmentParameter.legs,
  }.contains(parameter);

  double _minimum(_AdjustmentParameter parameter) =>
      parameter == _AdjustmentParameter.jaw ||
          parameter == _AdjustmentParameter.chin ||
          parameter == _AdjustmentParameter.eyes ||
          parameter == _AdjustmentParameter.nose ||
          parameter == _AdjustmentParameter.mouth ||
          parameter == _AdjustmentParameter.shoulders ||
          parameter == _AdjustmentParameter.waist
      ? -0.5
      : parameter == _AdjustmentParameter.textureSmoothing ||
            parameter == _AdjustmentParameter.skinToneLighting ||
            parameter == _AdjustmentParameter.blemishReduction ||
            _isQualityDetail(parameter) ||
            _isFaceGeometry(parameter) ||
            _isBodyGeometry(parameter)
      ? 0
      : -1;

  double _maximum(_AdjustmentParameter parameter) =>
      parameter == _AdjustmentParameter.faceSlim ||
          parameter == _AdjustmentParameter.headSize
      ? 0.5
      : parameter == _AdjustmentParameter.bodySlim ||
            parameter == _AdjustmentParameter.height ||
            parameter == _AdjustmentParameter.legs
      ? 0.35
      : parameter == _AdjustmentParameter.jaw ||
            parameter == _AdjustmentParameter.chin ||
            parameter == _AdjustmentParameter.eyes ||
            parameter == _AdjustmentParameter.nose ||
            parameter == _AdjustmentParameter.mouth ||
            parameter == _AdjustmentParameter.shoulders ||
            parameter == _AdjustmentParameter.waist
      ? 0.5
      : 1;

  bool _isQuality(_AdjustmentParameter parameter) =>
      parameter == _AdjustmentParameter.qualityImprovement ||
      _isQualityDetail(parameter);

  static const _qualityDetailParameters = <_AdjustmentParameter>[
    _AdjustmentParameter.noiseReduction,
    _AdjustmentParameter.lowLightRecovery,
    _AdjustmentParameter.hazeRemoval,
    _AdjustmentParameter.detailSharpening,
  ];

  static const _faceGeometryParameters = <_AdjustmentParameter>[
    _AdjustmentParameter.headSize,
    _AdjustmentParameter.jaw,
    _AdjustmentParameter.chin,
    _AdjustmentParameter.eyes,
    _AdjustmentParameter.nose,
    _AdjustmentParameter.mouth,
  ];

  static const _bodyGeometryParameters = <_AdjustmentParameter>[
    _AdjustmentParameter.height,
    _AdjustmentParameter.shoulders,
    _AdjustmentParameter.waist,
    _AdjustmentParameter.legs,
  ];

  bool _isQualityDetail(_AdjustmentParameter parameter) =>
      _qualityDetailParameters.contains(parameter);

  static const _naturalDetailParameters = <_AdjustmentParameter>[
    _AdjustmentParameter.textureSmoothing,
    _AdjustmentParameter.skinToneLighting,
    _AdjustmentParameter.blemishReduction,
  ];

  bool _isNaturalDetail(_AdjustmentParameter parameter) =>
      _naturalDetailParameters.contains(parameter);

  IconData _icon(_AdjustmentParameter parameter) => switch (parameter) {
    _AdjustmentParameter.exposure => Icons.exposure,
    _AdjustmentParameter.highlights => Icons.light_mode_outlined,
    _AdjustmentParameter.shadows => Icons.dark_mode_outlined,
    _AdjustmentParameter.contrast => Icons.contrast,
    _AdjustmentParameter.warmth => Icons.thermostat_outlined,
    _AdjustmentParameter.tint => Icons.colorize_outlined,
    _AdjustmentParameter.saturation => Icons.water_drop_outlined,
    _AdjustmentParameter.clarity => Icons.auto_awesome_outlined,
    _AdjustmentParameter.qualityImprovement => Icons.auto_fix_high_outlined,
    _AdjustmentParameter.noiseReduction => Icons.grain_outlined,
    _AdjustmentParameter.lowLightRecovery => Icons.nights_stay_outlined,
    _AdjustmentParameter.hazeRemoval => Icons.filter_drama_outlined,
    _AdjustmentParameter.detailSharpening => Icons.details_outlined,
    _AdjustmentParameter.naturalBeautification => Icons.auto_awesome,
    _AdjustmentParameter.textureSmoothing => Icons.blur_on_outlined,
    _AdjustmentParameter.skinToneLighting => Icons.light_mode_outlined,
    _AdjustmentParameter.blemishReduction => Icons.healing_outlined,
    _AdjustmentParameter.faceSlim => Icons.face_6_outlined,
    _AdjustmentParameter.headSize => Icons.face_outlined,
    _AdjustmentParameter.jaw => Icons.change_history_outlined,
    _AdjustmentParameter.chin => Icons.keyboard_arrow_down,
    _AdjustmentParameter.eyes => Icons.visibility_outlined,
    _AdjustmentParameter.nose => Icons.air_outlined,
    _AdjustmentParameter.mouth => Icons.sentiment_satisfied_alt_outlined,
    _AdjustmentParameter.bodySlim => Icons.accessibility_new,
    _AdjustmentParameter.height => Icons.height,
    _AdjustmentParameter.shoulders => Icons.open_in_full,
    _AdjustmentParameter.waist => Icons.compress,
    _AdjustmentParameter.legs => Icons.straighten,
  };

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
        _AdjustmentParameter.qualityImprovement =>
          context.l10n.qualityImprovement,
        _AdjustmentParameter.noiseReduction => context.l10n.noiseReduction,
        _AdjustmentParameter.lowLightRecovery => context.l10n.lowLightRecovery,
        _AdjustmentParameter.hazeRemoval => context.l10n.hazeRemoval,
        _AdjustmentParameter.detailSharpening => context.l10n.detailSharpening,
        _AdjustmentParameter.naturalBeautification =>
          context.l10n.oneTapNaturalBeautification,
        _AdjustmentParameter.textureSmoothing => context.l10n.textureSmoothing,
        _AdjustmentParameter.skinToneLighting => context.l10n.skinToneLighting,
        _AdjustmentParameter.blemishReduction => context.l10n.blemishReduction,
        _AdjustmentParameter.faceSlim => context.l10n.faceSlim,
        _AdjustmentParameter.headSize => context.l10n.headSize,
        _AdjustmentParameter.jaw => context.l10n.jaw,
        _AdjustmentParameter.chin => context.l10n.chin,
        _AdjustmentParameter.eyes => context.l10n.eyes,
        _AdjustmentParameter.nose => context.l10n.nose,
        _AdjustmentParameter.mouth => context.l10n.mouth,
        _AdjustmentParameter.bodySlim => context.l10n.bodySlim,
        _AdjustmentParameter.height => context.l10n.heightAdjustment,
        _AdjustmentParameter.shoulders => context.l10n.shoulders,
        _AdjustmentParameter.waist => context.l10n.waist,
        _AdjustmentParameter.legs => context.l10n.legs,
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
        _AdjustmentParameter.qualityImprovement =>
          <int>[
                recipe.qualityEnhancementRecipe.noiseReduction,
                recipe.qualityEnhancementRecipe.lowLightRecovery,
                recipe.qualityEnhancementRecipe.hazeRemoval,
                recipe.qualityEnhancementRecipe.detailSharpening,
              ].reduce((left, right) => left > right ? left : right) /
              100,
        _AdjustmentParameter.noiseReduction =>
          recipe.qualityEnhancementRecipe.noiseReduction / 100,
        _AdjustmentParameter.lowLightRecovery =>
          recipe.qualityEnhancementRecipe.lowLightRecovery / 100,
        _AdjustmentParameter.hazeRemoval =>
          recipe.qualityEnhancementRecipe.hazeRemoval / 100,
        _AdjustmentParameter.detailSharpening =>
          recipe.qualityEnhancementRecipe.detailSharpening / 100,
        _AdjustmentParameter.naturalBeautification =>
          <int>[
                recipe.portraitRecipe.textureSmoothing,
                recipe.portraitRecipe.skinToneLighting,
                recipe.portraitRecipe.blemishReduction,
              ].reduce((left, right) => left > right ? left : right) /
              100,
        _AdjustmentParameter.textureSmoothing =>
          (_currentTargetedAdjustment(recipe)?.textureSmoothing ?? 0) / 100,
        _AdjustmentParameter.skinToneLighting =>
          (_currentTargetedAdjustment(recipe)?.skinToneLighting ?? 0) / 100,
        _AdjustmentParameter.blemishReduction =>
          (_currentTargetedAdjustment(recipe)?.blemishReduction ?? 0) / 100,
        _AdjustmentParameter.faceSlim ||
        _AdjustmentParameter.headSize ||
        _AdjustmentParameter.jaw ||
        _AdjustmentParameter.chin ||
        _AdjustmentParameter.eyes ||
        _AdjustmentParameter.nose ||
        _AdjustmentParameter.mouth => _faceGeometryValue(recipe, parameter),
        _AdjustmentParameter.bodySlim ||
        _AdjustmentParameter.height ||
        _AdjustmentParameter.shoulders ||
        _AdjustmentParameter.waist ||
        _AdjustmentParameter.legs => _bodyGeometryValue(recipe, parameter),
      };

  double _faceGeometryValue(EditRecipe recipe, _AdjustmentParameter parameter) {
    final geometry = recipe.portraitGeometryRecipe;
    final target = geometry.faceTargets[geometry.selectedFaceIndex];
    return switch (parameter) {
      _AdjustmentParameter.faceSlim => target.faceSlim / 100,
      _AdjustmentParameter.headSize => target.headSize / 100,
      _AdjustmentParameter.jaw => target.jaw / 100,
      _AdjustmentParameter.chin => target.chin / 100,
      _AdjustmentParameter.eyes => target.eyes / 100,
      _AdjustmentParameter.nose => target.nose / 100,
      _AdjustmentParameter.mouth => target.mouth / 100,
      _ => 0,
    };
  }

  double _bodyGeometryValue(EditRecipe recipe, _AdjustmentParameter parameter) {
    final geometry = recipe.portraitGeometryRecipe;
    final target = geometry.bodyTargets[geometry.selectedBodyIndex];
    return switch (parameter) {
      _AdjustmentParameter.bodySlim => target.slimming / 100,
      _AdjustmentParameter.height => target.height / 100,
      _AdjustmentParameter.shoulders => target.shoulders / 100,
      _AdjustmentParameter.waist => target.waist / 100,
      _AdjustmentParameter.legs => target.legs / 100,
      _ => 0,
    };
  }

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
    _AdjustmentParameter.qualityImprovement => recipe,
    _AdjustmentParameter.noiseReduction => recipe.copyWith(
      qualityEnhancementRecipe: recipe.qualityEnhancementRecipe.copyWith(
        noiseReduction: (value * 100).round(),
      ),
    ),
    _AdjustmentParameter.lowLightRecovery => recipe.copyWith(
      qualityEnhancementRecipe: recipe.qualityEnhancementRecipe.copyWith(
        lowLightRecovery: (value * 100).round(),
      ),
    ),
    _AdjustmentParameter.hazeRemoval => recipe.copyWith(
      qualityEnhancementRecipe: recipe.qualityEnhancementRecipe.copyWith(
        hazeRemoval: (value * 100).round(),
      ),
    ),
    _AdjustmentParameter.detailSharpening => recipe.copyWith(
      qualityEnhancementRecipe: recipe.qualityEnhancementRecipe.copyWith(
        detailSharpening: (value * 100).round(),
      ),
    ),
    _AdjustmentParameter.naturalBeautification => recipe,
    _AdjustmentParameter.textureSmoothing ||
    _AdjustmentParameter.skinToneLighting ||
    _AdjustmentParameter.blemishReduction => _copyTargetedPortrait(
      recipe,
      parameter,
      value,
    ),
    _AdjustmentParameter.faceSlim ||
    _AdjustmentParameter.headSize ||
    _AdjustmentParameter.jaw ||
    _AdjustmentParameter.chin ||
    _AdjustmentParameter.eyes ||
    _AdjustmentParameter.nose ||
    _AdjustmentParameter.mouth => _copyFaceGeometry(recipe, parameter, value),
    _AdjustmentParameter.bodySlim ||
    _AdjustmentParameter.height ||
    _AdjustmentParameter.shoulders ||
    _AdjustmentParameter.waist ||
    _AdjustmentParameter.legs => _copyBodyGeometry(recipe, parameter, value),
  };

  EditRecipe _copyFaceGeometry(
    EditRecipe recipe,
    _AdjustmentParameter parameter,
    double value,
  ) => recipe.copyWith(
    portraitGeometryRecipe: recipe.portraitGeometryRecipe.updateSelectedFace(
      (target) => switch (parameter) {
        _AdjustmentParameter.faceSlim => target.copyWith(faceSlim: value * 100),
        _AdjustmentParameter.headSize => target.copyWith(headSize: value * 100),
        _AdjustmentParameter.jaw => target.copyWith(jaw: value * 100),
        _AdjustmentParameter.chin => target.copyWith(chin: value * 100),
        _AdjustmentParameter.eyes => target.copyWith(eyes: value * 100),
        _AdjustmentParameter.nose => target.copyWith(nose: value * 100),
        _AdjustmentParameter.mouth => target.copyWith(mouth: value * 100),
        _ => target,
      },
    ),
  );

  EditRecipe _copyBodyGeometry(
    EditRecipe recipe,
    _AdjustmentParameter parameter,
    double value,
  ) => recipe.copyWith(
    portraitGeometryRecipe: recipe.portraitGeometryRecipe.updateSelectedBody(
      (target) => switch (parameter) {
        _AdjustmentParameter.bodySlim => target.copyWith(slimming: value * 100),
        _AdjustmentParameter.height => target.copyWith(height: value * 100),
        _AdjustmentParameter.shoulders => target.copyWith(
          shoulders: value * 100,
        ),
        _AdjustmentParameter.waist => target.copyWith(waist: value * 100),
        _AdjustmentParameter.legs => target.copyWith(legs: value * 100),
        _ => target,
      },
    ),
  );

  StableEditTarget? _currentStableFaceTarget() {
    if (widget.stableFaceTargets.length == 1) {
      return widget.stableFaceTargets.single;
    }
    for (final target in widget.stableFaceTargets) {
      if (target.id == _selectedStableFaceTargetId) return target;
    }
    return null;
  }

  String? _preferredStableFaceTargetId() {
    if (widget.stableFaceTargets.length == 1) {
      return widget.stableFaceTargets.single.id;
    }
    final adjustedIds = widget.stableFaceTargets
        .where(
          (target) => widget.recipe.targetedPortraitRecipe.adjustments
              .containsKey(target.id),
        )
        .map((target) => target.id)
        .toList(growable: false);
    return adjustedIds.length == 1 ? adjustedIds.single : null;
  }

  TargetedPortraitAdjustment? _currentTargetedAdjustment(EditRecipe recipe) {
    final target = _currentStableFaceTarget();
    return target == null
        ? null
        : recipe.targetedPortraitRecipe.adjustments[target.id];
  }

  EditRecipe _copyTargetedPortrait(
    EditRecipe recipe,
    _AdjustmentParameter parameter,
    double value,
  ) {
    final target = _currentStableFaceTarget();
    if (target == null) return recipe;
    final targetedParameter = switch (parameter) {
      _AdjustmentParameter.textureSmoothing =>
        TargetedPortraitParameter.textureSmoothing,
      _AdjustmentParameter.skinToneLighting =>
        TargetedPortraitParameter.skinToneLighting,
      _AdjustmentParameter.blemishReduction =>
        TargetedPortraitParameter.blemishReduction,
      _ => throw ArgumentError.value(parameter, 'parameter'),
    };
    return recipe.copyWith(
      targetedPortraitRecipe: recipe.targetedPortraitRecipe.update(
        targetId: target.id,
        region: target.region,
        parameter: targetedParameter,
        value: (value * 100).round(),
      ),
    );
  }

  EditRecipe _applyNaturalBeautification(EditRecipe recipe) {
    var targeted = recipe.targetedPortraitRecipe;
    for (final target in widget.stableFaceTargets) {
      for (final entry in const {
        TargetedPortraitParameter.textureSmoothing: 50,
        TargetedPortraitParameter.skinToneLighting: 50,
        TargetedPortraitParameter.blemishReduction: 20,
      }.entries) {
        targeted = targeted.update(
          targetId: target.id,
          region: target.region,
          parameter: entry.key,
          value: entry.value,
        );
      }
    }
    return recipe.copyWith(targetedPortraitRecipe: targeted);
  }

  Widget _buildStableFaceTargetSelector() {
    final regions = widget.stableFaceTargets
        .map(
          (target) => NormalizedTargetRegion(
            left: target.region.left,
            top: target.region.top,
            right: target.region.right,
            bottom: target.region.bottom,
          ),
        )
        .toList(growable: false);
    return _PortraitTargetSelector(
      key: const ValueKey('editor-stable-face-target-selector'),
      photo: widget.photo,
      regions: regions,
      selectedIndex: null,
      targetLabel: context.l10n.faceSlimTarget,
      hint: context.l10n.faceSlimTargetHint,
      enabled: widget.enabled,
      onSelected: (index) => setState(
        () => _selectedStableFaceTargetId = widget.stableFaceTargets[index].id,
      ),
    );
  }
}

class _PortraitTargetSelector extends StatelessWidget {
  const _PortraitTargetSelector({
    required this.photo,
    required this.regions,
    required this.selectedIndex,
    required this.targetLabel,
    required this.hint,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final ProjectPhoto photo;
  final List<NormalizedTargetRegion> regions;
  final int? selectedIndex;
  final String Function(int number) targetLabel;
  final String hint;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: hint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: colors.surfaceContainerHighest,
              child: SizedBox(
                height: 180,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final sourceSize = _orientedSourceSize(photo);
                    final imageRect = _containedRect(
                      Size(constraints.maxWidth, constraints.maxHeight),
                      sourceSize,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(photo.localPath),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        for (var index = 0; index < regions.length; index++)
                          _target(
                            context,
                            Size(constraints.maxWidth, constraints.maxHeight),
                            imageRect,
                            regions[index],
                            index,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _target(
    BuildContext context,
    Size canvasSize,
    Rect imageRect,
    NormalizedTargetRegion region,
    int index,
  ) {
    final visualRect = Rect.fromLTRB(
      imageRect.left + region.left * imageRect.width,
      imageRect.top + region.top * imageRect.height,
      imageRect.left + region.right * imageRect.width,
      imageRect.top + region.bottom * imageRect.height,
    );
    final hitWidth = min(canvasSize.width, max(44.0, visualRect.width + 12));
    final hitHeight = min(canvasSize.height, max(44.0, visualRect.height + 12));
    final hitRect = Rect.fromLTWH(
      (visualRect.center.dx - hitWidth / 2)
          .clamp(0, canvasSize.width - hitWidth)
          .toDouble(),
      (visualRect.center.dy - hitHeight / 2)
          .clamp(0, canvasSize.height - hitHeight)
          .toDouble(),
      hitWidth,
      hitHeight,
    );
    final selected = index == selectedIndex;
    final colors = Theme.of(context).colorScheme;
    return Positioned.fromRect(
      rect: hitRect,
      child: Semantics(
        key: ValueKey('portrait-target-overlay-$index'),
        button: true,
        selected: selected,
        label: targetLabel(index + 1),
        hint: selected ? null : hint,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onSelected(index) : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: visualRect.shift(-hitRect.topLeft),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? colors.primary : Colors.white,
                      width: selected ? 3 : 2,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 3),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: max(0, visualRect.left - hitRect.left - 10),
                top: max(0, visualRect.top - hitRect.top - 10),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : Colors.black87,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 17, color: colors.onPrimary)
                      : Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Size _orientedSourceSize(ProjectPhoto photo) {
    final swapsAxes = const {5, 6, 7, 8}.contains(photo.orientation);
    return Size(
      (swapsAxes ? photo.pixelHeight : photo.pixelWidth).toDouble(),
      (swapsAxes ? photo.pixelWidth : photo.pixelHeight).toDouble(),
    );
  }

  static Rect _containedRect(Size available, Size source) {
    if (source.width <= 0 || source.height <= 0) {
      return Offset.zero & available;
    }
    final scale = min(
      available.width / source.width,
      available.height / source.height,
    );
    final rendered = Size(source.width * scale, source.height * scale);
    return Rect.fromLTWH(
      (available.width - rendered.width) / 2,
      (available.height - rendered.height) / 2,
      rendered.width,
      rendered.height,
    );
  }
}

class _PortraitToolStatus extends StatelessWidget {
  const _PortraitToolStatus({
    required this.photoToolsVisible,
    required this.available,
  });

  final bool photoToolsVisible;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final message = available
        ? context.l10n.localPortraitReady
        : context.l10n.portraitToolsUnavailable;
    return Semantics(
      key: const ValueKey('editor-portrait-tool-status'),
      container: true,
      excludeSemantics: true,
      label: message,
      child: Row(
        children: [
          Icon(
            available && photoToolsVisible
                ? Icons.verified_user_outlined
                : Icons.info_outline,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedToolUnavailable extends StatelessWidget {
  const _SelectedToolUnavailable({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    container: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AdjustmentToolButton extends StatelessWidget {
  const _AdjustmentToolButton({
    super.key,
    required this.enabled,
    required this.selected,
    required this.label,
    required this.icon,
    required this.largeText,
    required this.onTap,
  });

  final bool enabled;
  final bool selected;
  final String label;
  final IconData icon;
  final bool largeText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      onTap: onTap,
      child: SizedBox(
        width: 64,
        height: largeText ? 104 : 64,
        child: Material(
          color: selected
              ? colors.secondaryContainer
              : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: largeText ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    final basic = recipe.basicEditingRecipe;
    final hasCompositionChanges =
        !recipe.crop.isOriginal ||
        basic.flipHorizontal ||
        basic.flipVertical ||
        basic.perspectiveHorizontal != 0 ||
        basic.perspectiveVertical != 0;
    return ExpansionTile(
      key: const ValueKey('editor-composition-tools'),
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: const Icon(Icons.crop_rotate),
      title: Text(context.l10n.composition),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: context.l10n.rotateLeft,
              onPressed: enabled ? () => _rotate(-1) : null,
              icon: const Icon(Icons.rotate_left),
            ),
            IconButton.filledTonal(
              tooltip: context.l10n.rotateRight,
              onPressed: enabled ? () => _rotate(1) : null,
              icon: const Icon(Icons.rotate_right),
            ),
            IconButton.filledTonal(
              key: const ValueKey('editor-flip-horizontal'),
              tooltip: context.l10n.flipHorizontal,
              onPressed: enabled
                  ? () => _commit(
                      recipe.copyWith(
                        basicEditingRecipe: recipe.basicEditingRecipe.copyWith(
                          flipHorizontal:
                              !recipe.basicEditingRecipe.flipHorizontal,
                        ),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.flip),
            ),
            IconButton.filledTonal(
              key: const ValueKey('editor-flip-vertical'),
              tooltip: context.l10n.flipVertical,
              onPressed: enabled
                  ? () => _commit(
                      recipe.copyWith(
                        basicEditingRecipe: recipe.basicEditingRecipe.copyWith(
                          flipVertical: !recipe.basicEditingRecipe.flipVertical,
                        ),
                      ),
                    )
                  : null,
              icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
            ),
            TextButton(
              onPressed: enabled && hasCompositionChanges
                  ? () => _commit(
                      recipe.copyWith(
                        crop: CropGeometry.original,
                        basicEditingRecipe: basic.copyWith(
                          flipHorizontal: false,
                          flipVertical: false,
                          perspectiveHorizontal: 0,
                          perspectiveVertical: 0,
                        ),
                      ),
                    )
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
              ActionChip(
                key: const ValueKey('editor-free-crop'),
                avatar: const Icon(Icons.crop_free, size: 18),
                label: Text(context.l10n.freeCrop),
                onPressed: enabled
                    ? () => unawaited(_openFreeCrop(context))
                    : null,
              ),
              const SizedBox(width: 8),
              _cropChip(context.l10n.cropSquare, 1),
              const SizedBox(width: 8),
              _cropChip(context.l10n.cropFourThree, 4 / 3),
              const SizedBox(width: 8),
              _cropChip(
                context.l10n.cropThreeFour,
                3 / 4,
                key: const ValueKey('editor-crop-3-4'),
              ),
              const SizedBox(width: 8),
              _cropChip(context.l10n.cropSixteenNine, 16 / 9),
              const SizedBox(width: 8),
              _cropChip(
                context.l10n.cropNineSixteen,
                9 / 16,
                key: const ValueKey('editor-crop-9-16'),
              ),
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
        const SizedBox(height: 8),
        _AdjustmentSlider(
          key: const ValueKey('editor-perspective-horizontal'),
          enabled: enabled,
          label: context.l10n.perspectiveHorizontal,
          semanticLabel: context.l10n.perspectiveHorizontal,
          value: recipe.basicEditingRecipe.perspectiveHorizontal / 30,
          onStart: editorSession.beginAdjustment,
          onChanged: (value) => editorSession.preview(
            recipe.copyWith(
              basicEditingRecipe: recipe.basicEditingRecipe.copyWith(
                perspectiveHorizontal: value * 30,
              ),
            ),
          ),
          onEnd: () {
            editorSession.commitAdjustment();
            onRecipeCommitted();
          },
        ),
        const SizedBox(height: 8),
        _AdjustmentSlider(
          key: const ValueKey('editor-perspective-vertical'),
          enabled: enabled,
          label: context.l10n.perspectiveVertical,
          semanticLabel: context.l10n.perspectiveVertical,
          value: recipe.basicEditingRecipe.perspectiveVertical / 30,
          onStart: editorSession.beginAdjustment,
          onChanged: (value) => editorSession.preview(
            recipe.copyWith(
              basicEditingRecipe: recipe.basicEditingRecipe.copyWith(
                perspectiveVertical: value * 30,
              ),
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

  Widget _cropChip(String label, double? targetAspectRatio, {Key? key}) {
    return ActionChip(
      key: key,
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

  Future<void> _openFreeCrop(BuildContext context) async {
    final swapsAxes = photo.orientation >= 5;
    final width = swapsAxes ? photo.pixelHeight : photo.pixelWidth;
    final height = swapsAxes ? photo.pixelWidth : photo.pixelHeight;
    await showDialog<void>(
      context: context,
      builder: (context) => _FreeCropDialog(
        sourcePath: photo.localPath,
        sourceAspectRatio: width > 0 && height > 0 ? width / height : 4 / 3,
        initial: recipe.crop,
        previewRecipe: recipe.copyWith(crop: CropGeometry.original),
        onChanged: (crop) => _commit(editorSession.recipe.copyWith(crop: crop)),
      ),
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

class _FreeCropDialog extends StatefulWidget {
  const _FreeCropDialog({
    required this.sourcePath,
    required this.sourceAspectRatio,
    required this.initial,
    required this.previewRecipe,
    required this.onChanged,
  });

  final String sourcePath;
  final double sourceAspectRatio;
  final CropGeometry initial;
  final EditRecipe previewRecipe;
  final ValueChanged<CropGeometry> onChanged;

  @override
  State<_FreeCropDialog> createState() => _FreeCropDialogState();
}

class _FreeCropDialogState extends State<_FreeCropDialog> {
  late double _left = widget.initial.left;
  late double _top = widget.initial.top;
  late double _right = widget.initial.right;
  late double _bottom = widget.initial.bottom;
  int _activeCorner = 0;

  @override
  Widget build(BuildContext context) {
    var canvasWidth = min(MediaQuery.sizeOf(context).width - 128, 360.0);
    var canvasHeight = canvasWidth / widget.sourceAspectRatio;
    if (canvasHeight > 420) {
      canvasHeight = 420;
      canvasWidth = canvasHeight * widget.sourceAspectRatio;
    }
    final canvasSize = Size(canvasWidth, canvasHeight);
    return AlertDialog(
      title: Text(context.l10n.freeCrop),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.freeCropHint),
            const SizedBox(height: 12),
            SizedBox.fromSize(
              size: canvasSize,
              child: Semantics(
                label: context.l10n.freeCropHint,
                child: GestureDetector(
                  key: const ValueKey('free-crop-canvas'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) =>
                      _selectCorner(details.localPosition, canvasSize),
                  onPanUpdate: (details) =>
                      _moveCorner(details.delta, canvasSize),
                  onPanEnd: (_) => widget.onChanged(_crop),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NativePhotoPreview(
                        sourcePath: widget.sourcePath,
                        recipe: widget.previewRecipe,
                        renderer: context.read<PhotoPreviewRenderer>(),
                        errorBuilder: (context) => ColoredBox(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _CropOverlayPainter(
                          crop: Rect.fromLTRB(_left, _top, _right, _bottom),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('free-crop-close'),
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }

  void _selectCorner(Offset position, Size size) {
    final normalized = Offset(
      position.dx / size.width,
      position.dy / size.height,
    );
    final corners = [
      Offset(_left, _top),
      Offset(_right, _top),
      Offset(_right, _bottom),
      Offset(_left, _bottom),
    ];
    var bestDistance = double.infinity;
    for (var index = 0; index < corners.length; index++) {
      final distance = (corners[index] - normalized).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        _activeCorner = index;
      }
    }
  }

  void _moveCorner(Offset delta, Size size) {
    const minimumSpan = 0.08;
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    setState(() {
      if (_activeCorner == 0 || _activeCorner == 3) {
        _left = (_left + dx).clamp(0, _right - minimumSpan);
      } else {
        _right = (_right + dx).clamp(_left + minimumSpan, 1);
      }
      if (_activeCorner == 0 || _activeCorner == 1) {
        _top = (_top + dy).clamp(0, _bottom - minimumSpan);
      } else {
        _bottom = (_bottom + dy).clamp(_top + minimumSpan, 1);
      }
    });
  }

  CropGeometry get _crop => widget.initial.copyWith(
    left: _left,
    top: _top,
    right: _right,
    bottom: _bottom,
  );
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({required this.crop});

  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final cropRect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(cropRect);
    canvas.drawPath(shade, Paint()..color = Colors.black54);
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    final handlePaint = Paint()..color = Colors.white;
    for (final corner in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomRight,
      cropRect.bottomLeft,
    ]) {
      canvas.drawCircle(corner, 7, handlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.crop != crop;
}

enum _FilterHslMode { all, filter, hsl }

class _FilterHslTools extends StatefulWidget {
  const _FilterHslTools({
    required this.enabled,
    required this.recipe,
    required this.editorSession,
    required this.onRecipeCommitted,
    this.mode = _FilterHslMode.all,
    this.initialChannel = HslChannel.red,
  });

  final bool enabled;
  final EditRecipe recipe;
  final EditorSession editorSession;
  final VoidCallback onRecipeCommitted;
  final _FilterHslMode mode;
  final HslChannel initialChannel;

  @override
  State<_FilterHslTools> createState() => _FilterHslToolsState();
}

class _FilterHslToolsState extends State<_FilterHslTools> {
  late HslChannel _selectedChannel = widget.initialChannel;

  @override
  void didUpdateWidget(covariant _FilterHslTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialChannel != widget.initialChannel) {
      _selectedChannel = widget.initialChannel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRecipe = widget.editorSession.recipe;
    final basic = currentRecipe.basicEditingRecipe;
    final hsl = basic.hsl[_selectedChannel] ?? HslAdjustment.neutral;
    return ExpansionTile(
      key: const ValueKey('editor-filter-hsl-tools'),
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: const Icon(Icons.filter_vintage_outlined),
      title: Text(context.l10n.filterAndHsl),
      children: [
        if (widget.mode != _FilterHslMode.hsl) ...[
          SizedBox(
            height: 48,
            child: ListView.separated(
              key: const ValueKey('editor-filter-list'),
              scrollDirection: Axis.horizontal,
              itemCount: PhotoFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = PhotoFilter.values[index];
                return ChoiceChip(
                  key: ValueKey('editor-filter-${filter.name}'),
                  label: Text(_filterLabel(context, filter)),
                  selected: basic.filter == filter,
                  onSelected: widget.enabled
                      ? (_) {
                          widget.editorSession.apply(
                            widget.editorSession.recipe.copyWith(
                              basicEditingRecipe: basic.copyWith(
                                filter: filter,
                                filterStrength: filter == PhotoFilter.none
                                    ? 0
                                    : basic.filterStrength == 0
                                    ? 70
                                    : basic.filterStrength,
                              ),
                            ),
                          );
                          widget.onRecipeCommitted();
                        }
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _AdjustmentSlider(
            key: const ValueKey('editor-filter-strength'),
            enabled: widget.enabled && basic.filter != PhotoFilter.none,
            label: context.l10n.filterStrength,
            semanticLabel: context.l10n.filterStrength,
            value: basic.filterStrength / 100,
            minimum: 0,
            onStart: widget.editorSession.beginAdjustment,
            onChanged: (value) => widget.editorSession.preview(
              widget.editorSession.recipe.copyWith(
                basicEditingRecipe: basic.copyWith(filterStrength: value * 100),
              ),
            ),
            onEnd: _commitAdjustment,
          ),
        ],
        if (widget.mode == _FilterHslMode.all) const SizedBox(height: 12),
        if (widget.mode != _FilterHslMode.filter) ...[
          SizedBox(
            height: 42,
            child: ListView.separated(
              key: const ValueKey('editor-hsl-channels'),
              scrollDirection: Axis.horizontal,
              itemCount: HslChannel.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final channel = HslChannel.values[index];
                return ChoiceChip(
                  key: ValueKey('editor-hsl-${channel.name}'),
                  label: Text(_channelLabel(context, channel)),
                  selected: channel == _selectedChannel,
                  onSelected: (_) => setState(() => _selectedChannel = channel),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _hslSlider(
            context,
            'hue',
            context.l10n.hslHue,
            hsl.hue,
            (value) => HslAdjustment(
              hue: value,
              saturation: hsl.saturation,
              lightness: hsl.lightness,
            ),
          ),
          const SizedBox(height: 6),
          _hslSlider(
            context,
            'saturation',
            context.l10n.hslSaturation,
            hsl.saturation,
            (value) => HslAdjustment(
              hue: hsl.hue,
              saturation: value,
              lightness: hsl.lightness,
            ),
          ),
          const SizedBox(height: 6),
          _hslSlider(
            context,
            'lightness',
            context.l10n.hslLightness,
            hsl.lightness,
            (value) => HslAdjustment(
              hue: hsl.hue,
              saturation: hsl.saturation,
              lightness: value,
            ),
          ),
        ],
      ],
    );
  }

  Widget _hslSlider(
    BuildContext context,
    String id,
    String label,
    double value,
    HslAdjustment Function(double value) update,
  ) => _AdjustmentSlider(
    key: ValueKey('editor-hsl-${_selectedChannel.name}-$id'),
    enabled: widget.enabled,
    label: label,
    semanticLabel: '$label ${_channelLabel(context, _selectedChannel)}',
    value: value / 100,
    onStart: widget.editorSession.beginAdjustment,
    onChanged: (normalized) {
      final nextHsl = Map<HslChannel, HslAdjustment>.of(
        widget.editorSession.recipe.basicEditingRecipe.hsl,
      )..[_selectedChannel] = update(normalized * 100);
      widget.editorSession.preview(
        widget.editorSession.recipe.copyWith(
          basicEditingRecipe: widget.editorSession.recipe.basicEditingRecipe
              .copyWith(hsl: nextHsl),
        ),
      );
    },
    onEnd: _commitAdjustment,
  );

  void _commitAdjustment() {
    widget.editorSession.commitAdjustment();
    widget.onRecipeCommitted();
  }

  String _filterLabel(BuildContext context, PhotoFilter filter) =>
      switch (filter) {
        PhotoFilter.none => context.l10n.filterNone,
        PhotoFilter.clean => context.l10n.filterClean,
        PhotoFilter.portrait => context.l10n.filterPortrait,
        PhotoFilter.cinematic => context.l10n.filterCinematic,
        PhotoFilter.film => context.l10n.filterFilm,
        PhotoFilter.warmSun => context.l10n.filterWarmSun,
        PhotoFilter.coolAir => context.l10n.filterCoolAir,
        PhotoFilter.vivid => context.l10n.filterVivid,
        PhotoFilter.faded => context.l10n.filterFaded,
        PhotoFilter.noir => context.l10n.filterNoir,
        PhotoFilter.food => context.l10n.filterFood,
        PhotoFilter.landscape => context.l10n.filterLandscape,
        PhotoFilter.night => context.l10n.filterNight,
      };

  String _channelLabel(BuildContext context, HslChannel channel) =>
      switch (channel) {
        HslChannel.red => context.l10n.hslRed,
        HslChannel.orange => context.l10n.hslOrange,
        HslChannel.yellow => context.l10n.hslYellow,
        HslChannel.green => context.l10n.hslGreen,
        HslChannel.cyan => context.l10n.hslCyan,
        HslChannel.blue => context.l10n.hslBlue,
        HslChannel.purple => context.l10n.hslPurple,
        HslChannel.magenta => context.l10n.hslMagenta,
      };
}

class _SemanticTools extends StatelessWidget {
  const _SemanticTools({
    required this.enabled,
    required this.subjectAvailable,
    required this.photo,
    required this.recipe,
    required this.editorSession,
    required this.onRecipeCommitted,
  });

  final bool enabled;
  final bool subjectAvailable;
  final ProjectPhoto photo;
  final EditRecipe recipe;
  final EditorSession editorSession;
  final VoidCallback onRecipeCommitted;

  @override
  Widget build(BuildContext context) {
    final semantic = editorSession.recipe.semanticEditingRecipe;
    return ExpansionTile(
      key: const ValueKey('editor-semantic-tools'),
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: const Icon(Icons.layers_outlined),
      title: Text(context.l10n.semanticTools),
      subtitle: Text(
        subjectAvailable
            ? context.l10n.semanticToolsLocalReady
            : context.l10n.semanticSubjectUnavailable,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            context.l10n.backgroundTreatment,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 52,
          child: SingleChildScrollView(
            key: const ValueKey('editor-background-treatment-list'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (
                  var index = 0;
                  index < _legacyBackgroundTreatments.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Builder(
                    builder: (context) {
                      final treatment = _legacyBackgroundTreatments[index];
                      final label = _backgroundLabel(context, treatment);
                      final canSelect =
                          enabled &&
                          (treatment == BackgroundTreatment.original ||
                              subjectAvailable);
                      void selectTreatment() {
                        if (treatment == BackgroundTreatment.image) {
                          unawaited(_pickBackgroundImage(context));
                          return;
                        }
                        _commit(
                          semantic.copyWith(
                            background: treatment,
                            backgroundImagePath: null,
                            backgroundBlur:
                                treatment == BackgroundTreatment.blur &&
                                    semantic.backgroundBlur == 0
                                ? 45
                                : semantic.backgroundBlur,
                          ),
                        );
                      }

                      return Semantics(
                        button: true,
                        selected: semantic.background == treatment,
                        enabled: canSelect,
                        label: label,
                        onTap: canSelect ? selectTreatment : null,
                        child: ExcludeSemantics(
                          child: SizedBox(
                            height: 52,
                            child: ChoiceChip(
                              key: ValueKey(
                                'editor-background-${treatment.name}',
                              ),
                              label: Text(label),
                              selected: semantic.background == treatment,
                              onSelected: canSelect
                                  ? (_) => selectTreatment()
                                  : null,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        if (semantic.background == BackgroundTreatment.blur) ...[
          const SizedBox(height: 6),
          _semanticSlider(
            context: context,
            key: const ValueKey('editor-background-blur'),
            label: context.l10n.backgroundBlur,
            value: semantic.backgroundBlur / 100,
            enabled: enabled && subjectAvailable,
            update: (value) =>
                semantic.copyWith(backgroundBlur: (value * 100).round()),
            minimum: 0,
          ),
        ],
        if (subjectAvailable) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('editor-open-subject-mask-brush'),
                  onPressed: enabled
                      ? () => _openMaskBrush(context, localAdjustment: false)
                      : null,
                  icon: const Icon(Icons.gesture_outlined),
                  label: Text(context.l10n.refineSubjectMask),
                ),
              ),
              if (semantic.subjectMaskStrokes.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const ValueKey('editor-clear-subject-mask'),
                  tooltip: context.l10n.clearMask,
                  onPressed: enabled
                      ? () => _commit(
                          semantic.copyWith(subjectMaskStrokes: const []),
                        )
                      : null,
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 8),
        _semanticSlider(
          context: context,
          key: const ValueKey('editor-subject-exposure'),
          label: context.l10n.subjectExposure,
          value: semantic.subjectExposure / 100,
          enabled: enabled && subjectAvailable,
          update: (value) =>
              semantic.copyWith(subjectExposure: (value * 100).round()),
        ),
        _semanticSlider(
          context: context,
          key: const ValueKey('editor-subject-saturation'),
          label: context.l10n.subjectSaturation,
          value: semantic.subjectSaturation / 100,
          enabled: enabled && subjectAvailable,
          update: (value) =>
              semantic.copyWith(subjectSaturation: (value * 100).round()),
        ),
        _semanticSlider(
          context: context,
          key: const ValueKey('editor-background-exposure'),
          label: context.l10n.backgroundExposure,
          value: semantic.backgroundExposure / 100,
          enabled: enabled && subjectAvailable,
          update: (value) =>
              semantic.copyWith(backgroundExposure: (value * 100).round()),
        ),
        _semanticSlider(
          context: context,
          key: const ValueKey('editor-background-saturation'),
          label: context.l10n.backgroundSaturation,
          value: semantic.backgroundSaturation / 100,
          enabled: enabled && subjectAvailable,
          update: (value) =>
              semantic.copyWith(backgroundSaturation: (value * 100).round()),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            context.l10n.localAdjustment,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        _semanticSlider(
          context: context,
          key: const ValueKey('editor-local-exposure'),
          label: context.l10n.localExposure,
          value: semantic.localExposure / 100,
          enabled: enabled,
          update: (value) =>
              semantic.copyWith(localExposure: (value * 100).round()),
        ),
        _semanticSlider(
          context: context,
          key: const ValueKey('editor-local-saturation'),
          label: context.l10n.localSaturation,
          value: semantic.localSaturation / 100,
          enabled: enabled,
          update: (value) =>
              semantic.copyWith(localSaturation: (value * 100).round()),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('editor-open-local-adjustment-brush'),
                onPressed: enabled
                    ? () => _openMaskBrush(context, localAdjustment: true)
                    : null,
                icon: const Icon(Icons.brush_outlined),
                label: Text(context.l10n.localAdjustment),
              ),
            ),
            if (semantic.localAdjustmentStrokes.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('editor-clear-local-adjustment-mask'),
                tooltip: context.l10n.clearMask,
                onPressed: enabled
                    ? () => _commit(
                        semantic.copyWith(localAdjustmentStrokes: const []),
                      )
                    : null,
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('editor-open-erase-brush'),
                onPressed: enabled ? () => _openEraseBrush(context) : null,
                icon: const Icon(Icons.auto_fix_off_outlined),
                label: Text(context.l10n.eraseBrush),
              ),
            ),
            if (semantic.eraseStrokes.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('editor-clear-erase-brush'),
                tooltip: context.l10n.clearEraseStrokes,
                onPressed: enabled
                    ? () => _commit(semantic.copyWith(eraseStrokes: const []))
                    : null,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _semanticSlider({
    required BuildContext context,
    required Key key,
    required String label,
    required double value,
    required bool enabled,
    required SemanticEditingRecipe Function(double value) update,
    double minimum = -1,
  }) => _AdjustmentSlider(
    key: key,
    enabled: enabled,
    label: label,
    semanticLabel: label,
    value: value,
    minimum: minimum,
    onStart: editorSession.beginAdjustment,
    onChanged: (value) => editorSession.preview(
      editorSession.recipe.copyWith(semanticEditingRecipe: update(value)),
    ),
    onEnd: () {
      editorSession.commitAdjustment();
      onRecipeCommitted();
    },
  );

  Future<void> _openEraseBrush(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _EraseBrushDialog(
        sourcePath: photo.localPath,
        sourceAspectRatio: photo.pixelWidth > 0 && photo.pixelHeight > 0
            ? photo.pixelWidth / photo.pixelHeight
            : 4 / 3,
        initial: editorSession.recipe.semanticEditingRecipe.eraseStrokes,
        previewRecipe: editorSession.recipe,
        onChanged: (strokes) => _commit(
          editorSession.recipe.semanticEditingRecipe.copyWith(
            eraseStrokes: strokes,
          ),
        ),
      ),
    );
  }

  Future<void> _openMaskBrush(
    BuildContext context, {
    required bool localAdjustment,
  }) async {
    final semantic = editorSession.recipe.semanticEditingRecipe;
    await showDialog<void>(
      context: context,
      builder: (context) => _MaskBrushDialog(
        sourcePath: photo.localPath,
        sourceAspectRatio: photo.pixelWidth > 0 && photo.pixelHeight > 0
            ? photo.pixelWidth / photo.pixelHeight
            : 4 / 3,
        initial: localAdjustment
            ? semantic.localAdjustmentStrokes
            : semantic.subjectMaskStrokes,
        previewRecipe: editorSession.recipe,
        localAdjustment: localAdjustment,
        onChanged: (strokes) {
          final current = editorSession.recipe.semanticEditingRecipe;
          _commit(
            localAdjustment
                ? current.copyWith(localAdjustmentStrokes: strokes)
                : current.copyWith(subjectMaskStrokes: strokes),
          );
        },
      ),
    );
  }

  Future<void> _pickBackgroundImage(BuildContext context) async {
    final importer = context.read<PhotoImporter>();
    if (importer is! EditingResourceImporter) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backgroundImageImportFailed)),
      );
      return;
    }
    final imported = await importer.importEditingResource(
      EditingResourceKind.backgroundImage,
    );
    if (imported == null) return;
    _commit(
      editorSession.recipe.semanticEditingRecipe.copyWith(
        background: BackgroundTreatment.image,
        backgroundImagePath: imported.localPath,
        backgroundImageResourceId: imported.descriptor.id,
      ),
    );
  }

  void _commit(SemanticEditingRecipe semantic) {
    editorSession.apply(
      editorSession.recipe.copyWith(semanticEditingRecipe: semantic),
    );
    onRecipeCommitted();
  }

  String _backgroundLabel(
    BuildContext context,
    BackgroundTreatment treatment,
  ) => switch (treatment) {
    BackgroundTreatment.original => context.l10n.backgroundOriginal,
    BackgroundTreatment.blur => context.l10n.backgroundBlur,
    BackgroundTreatment.white => context.l10n.backgroundWhite,
    BackgroundTreatment.black => context.l10n.backgroundBlack,
    BackgroundTreatment.warm => context.l10n.backgroundWarm,
    BackgroundTreatment.cool => context.l10n.backgroundCool,
    BackgroundTreatment.image => context.l10n.backgroundImage,
    BackgroundTreatment.transparent => throw StateError(
      'Transparent background is not exposed by the legacy editor.',
    ),
  };
}

class _MaskBrushDialog extends StatefulWidget {
  const _MaskBrushDialog({
    required this.sourcePath,
    required this.sourceAspectRatio,
    required this.initial,
    required this.previewRecipe,
    required this.localAdjustment,
    required this.onChanged,
  });

  final String sourcePath;
  final double sourceAspectRatio;
  final List<MaskStroke> initial;
  final EditRecipe previewRecipe;
  final bool localAdjustment;
  final ValueChanged<List<MaskStroke>> onChanged;

  @override
  State<_MaskBrushDialog> createState() => _MaskBrushDialogState();
}

class _MaskBrushDialogState extends State<_MaskBrushDialog> {
  late List<MaskStroke> _strokes = widget.initial.toList();
  final List<List<MaskStroke>> _undoHistory = [];
  final List<List<MaskStroke>> _redoHistory = [];
  MaskBrushOperation _operation = MaskBrushOperation.paint;
  double _radius = 0.035;
  List<NormalizedPoint>? _activePoints;

  @override
  Widget build(BuildContext context) {
    var canvasWidth = min(MediaQuery.sizeOf(context).width - 128, 360.0);
    var canvasHeight = canvasWidth / widget.sourceAspectRatio;
    if (canvasHeight > 420) {
      canvasHeight = 420;
      canvasWidth = canvasHeight * widget.sourceAspectRatio;
    }
    final canvasSize = Size(canvasWidth, canvasHeight);
    final semantic = widget.previewRecipe.semanticEditingRecipe;
    final previewSemantic = widget.localAdjustment
        ? semantic.copyWith(
            localExposure: 0,
            localSaturation: 0,
            localAdjustmentStrokes: const [],
          )
        : semantic.copyWith(subjectMaskStrokes: const []);
    final keyPrefix = widget.localAdjustment ? 'local-mask' : 'subject-mask';
    return AlertDialog(
      title: Text(
        widget.localAdjustment
            ? context.l10n.localAdjustment
            : context.l10n.subjectMask,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.maskBrushHint),
            const SizedBox(height: 8),
            SegmentedButton<MaskBrushOperation>(
              key: ValueKey('$keyPrefix-operation'),
              segments: [
                ButtonSegment(
                  value: MaskBrushOperation.paint,
                  icon: const Icon(Icons.brush_outlined),
                  label: Text(context.l10n.paintMask),
                ),
                ButtonSegment(
                  value: MaskBrushOperation.erase,
                  icon: const Icon(Icons.auto_fix_off_outlined),
                  label: Text(context.l10n.eraseMask),
                ),
              ],
              selected: {_operation},
              onSelectionChanged: (selection) =>
                  setState(() => _operation = selection.single),
            ),
            const SizedBox(height: 12),
            SizedBox.fromSize(
              size: canvasSize,
              child: Semantics(
                key: ValueKey('$keyPrefix-canvas-semantics'),
                container: true,
                excludeSemantics: true,
                label: widget.localAdjustment
                    ? context.l10n.localAdjustment
                    : context.l10n.subjectMask,
                hint: context.l10n.maskBrushHint,
                onTap: _strokes.length >= 40
                    ? null
                    : () => _addCenterStamp(canvasSize),
                child: GestureDetector(
                  key: ValueKey('$keyPrefix-canvas'),
                  excludeFromSemantics: true,
                  behavior: HitTestBehavior.opaque,
                  onTapDown: _strokes.length >= 40
                      ? null
                      : (details) =>
                            _startStroke(details.localPosition, canvasSize),
                  onTapUp: _strokes.length >= 40
                      ? null
                      : (_) => _finishStroke(),
                  onPanStart: _strokes.length >= 40
                      ? null
                      : (details) =>
                            _startStroke(details.localPosition, canvasSize),
                  onPanUpdate: _strokes.length >= 40
                      ? null
                      : (details) =>
                            _continueStroke(details.localPosition, canvasSize),
                  onPanEnd: _strokes.length >= 40
                      ? null
                      : (_) => _finishStroke(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NativePhotoPreview(
                        sourcePath: widget.sourcePath,
                        recipe: widget.previewRecipe.copyWith(
                          semanticEditingRecipe: previewSemantic,
                        ),
                        renderer: context.read<PhotoPreviewRenderer>(),
                        errorBuilder: (context) => ColoredBox(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _MaskStrokePainter(
                          strokes: _strokes,
                          activePoints: _activePoints,
                          activeRadius: _radius,
                          activeOperation: _operation,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _AdjustmentSlider(
              key: ValueKey('$keyPrefix-brush-size'),
              enabled: true,
              label: context.l10n.brushSize,
              semanticLabel: context.l10n.brushSize,
              value: _radius,
              minimum: 0.005,
              maximum: 0.12,
              onStart: () {},
              onChanged: (value) => setState(() => _radius = value),
              onEnd: () {},
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  key: ValueKey('$keyPrefix-undo'),
                  tooltip: context.l10n.undo,
                  onPressed: _undoHistory.isEmpty ? null : _undoStrokeChange,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  key: ValueKey('$keyPrefix-redo'),
                  tooltip: context.l10n.redo,
                  onPressed: _redoHistory.isEmpty ? null : _redoStrokeChange,
                  icon: const Icon(Icons.redo),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _strokes.isEmpty ? null : () => _replaceStrokes(const []),
          child: Text(context.l10n.clear),
        ),
        TextButton(
          key: ValueKey('$keyPrefix-close'),
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }

  void _startStroke(Offset position, Size size) {
    setState(() => _activePoints = [_normalized(position, size)]);
  }

  void _continueStroke(Offset position, Size size) {
    final points = _activePoints;
    if (points == null || points.length >= 200) return;
    final next = _normalized(position, size);
    if ((Offset(next.x, next.y) - Offset(points.last.x, points.last.y))
            .distance <
        _radius * 0.25) {
      return;
    }
    setState(() => points.add(next));
  }

  void _finishStroke() {
    final points = _activePoints;
    if (points == null || points.isEmpty) return;
    _replaceStrokes([
      ..._strokes,
      MaskStroke(operation: _operation, radius: _radius, points: points),
    ]);
  }

  void _addCenterStamp(Size canvasSize) {
    _startStroke(canvasSize.center(Offset.zero), canvasSize);
    _finishStroke();
  }

  void _replaceStrokes(List<MaskStroke> next) {
    setState(() {
      _undoHistory.add(List.unmodifiable(_strokes));
      _redoHistory.clear();
      _strokes = List.of(next);
      _activePoints = null;
    });
    widget.onChanged(List.unmodifiable(_strokes));
  }

  void _undoStrokeChange() {
    if (_undoHistory.isEmpty) return;
    setState(() {
      _redoHistory.add(List.unmodifiable(_strokes));
      _strokes = List.of(_undoHistory.removeLast());
      _activePoints = null;
    });
    widget.onChanged(List.unmodifiable(_strokes));
  }

  void _redoStrokeChange() {
    if (_redoHistory.isEmpty) return;
    setState(() {
      _undoHistory.add(List.unmodifiable(_strokes));
      _strokes = List.of(_redoHistory.removeLast());
      _activePoints = null;
    });
    widget.onChanged(List.unmodifiable(_strokes));
  }

  NormalizedPoint _normalized(Offset position, Size size) =>
      NormalizedPoint.checked(
        (position.dx / size.width).clamp(0, 1),
        (position.dy / size.height).clamp(0, 1),
      );
}

class _MaskStrokePainter extends CustomPainter {
  const _MaskStrokePainter({
    required this.strokes,
    required this.activePoints,
    required this.activeRadius,
    required this.activeOperation,
  });

  final List<MaskStroke> strokes;
  final List<NormalizedPoint>? activePoints;
  final double activeRadius;
  final MaskBrushOperation activeOperation;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(
        canvas,
        size,
        stroke.points,
        stroke.radius,
        stroke.operation,
      );
    }
    final active = activePoints;
    if (active != null) {
      _paintStroke(canvas, size, active, activeRadius, activeOperation);
    }
  }

  void _paintStroke(
    Canvas canvas,
    Size size,
    List<NormalizedPoint> points,
    double radius,
    MaskBrushOperation operation,
  ) {
    final offsets = points
        .map((point) => Offset(point.x * size.width, point.y * size.height))
        .toList();
    if (offsets.isEmpty) return;
    final paint = Paint()
      ..color =
          (operation == MaskBrushOperation.paint
                  ? Colors.greenAccent
                  : Colors.redAccent)
              .withValues(alpha: 0.55)
      ..strokeWidth = radius * min(size.width, size.height) * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (offsets.length == 1) {
      canvas.drawCircle(
        offsets.single,
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final point in offsets.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MaskStrokePainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.activePoints != activePoints ||
      oldDelegate.activeRadius != activeRadius ||
      oldDelegate.activeOperation != activeOperation;
}

class _EraseBrushDialog extends StatefulWidget {
  const _EraseBrushDialog({
    required this.sourcePath,
    required this.sourceAspectRatio,
    required this.initial,
    required this.previewRecipe,
    required this.onChanged,
  });

  final String sourcePath;
  final double sourceAspectRatio;
  final List<EraseStroke> initial;
  final EditRecipe previewRecipe;
  final ValueChanged<List<EraseStroke>> onChanged;

  @override
  State<_EraseBrushDialog> createState() => _EraseBrushDialogState();
}

class _EraseBrushDialogState extends State<_EraseBrushDialog> {
  late List<EraseStroke> _strokes = widget.initial.toList();
  final List<List<EraseStroke>> _undoHistory = [];
  final List<List<EraseStroke>> _redoHistory = [];
  double _radius = 0.035;
  List<NormalizedPoint>? _activePoints;

  @override
  Widget build(BuildContext context) {
    var canvasWidth = min(MediaQuery.sizeOf(context).width - 96, 360.0);
    var canvasHeight = canvasWidth / widget.sourceAspectRatio;
    if (canvasHeight > 420) {
      canvasHeight = 420;
      canvasWidth = canvasHeight * widget.sourceAspectRatio;
    }
    final canvasSize = Size(canvasWidth, canvasHeight);
    final previewSemantic = widget.previewRecipe.semanticEditingRecipe.copyWith(
      eraseStrokes: const [],
    );
    return AlertDialog(
      title: Text(context.l10n.eraseBrush),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.eraseBrushHint),
          const SizedBox(height: 12),
          SizedBox.fromSize(
            size: canvasSize,
            child: Semantics(
              key: const ValueKey('erase-brush-canvas-semantics'),
              container: true,
              excludeSemantics: true,
              label: context.l10n.eraseBrush,
              hint: context.l10n.eraseBrushHint,
              onTap: _strokes.length >= 20
                  ? null
                  : () => _addCenterStamp(canvasSize),
              child: GestureDetector(
                key: const ValueKey('erase-brush-canvas'),
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onPanStart: _strokes.length >= 20
                    ? null
                    : (details) =>
                          _startStroke(details.localPosition, canvasSize),
                onPanUpdate: _strokes.length >= 20
                    ? null
                    : (details) =>
                          _continueStroke(details.localPosition, canvasSize),
                onPanEnd: _strokes.length >= 20 ? null : (_) => _finishStroke(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NativePhotoPreview(
                      sourcePath: widget.sourcePath,
                      recipe: widget.previewRecipe.copyWith(
                        semanticEditingRecipe: previewSemantic,
                      ),
                      renderer: context.read<PhotoPreviewRenderer>(),
                      errorBuilder: (context) => ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    CustomPaint(
                      painter: _EraseStrokePainter(
                        strokes: _strokes,
                        activePoints: _activePoints,
                        activeRadius: _radius,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _AdjustmentSlider(
            key: const ValueKey('erase-brush-size'),
            enabled: true,
            label: context.l10n.brushSize,
            semanticLabel: context.l10n.brushSize,
            value: _radius,
            minimum: 0.005,
            maximum: 0.12,
            onStart: () {},
            onChanged: (value) => setState(() => _radius = value),
            onEnd: () {},
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                key: const ValueKey('erase-brush-undo'),
                tooltip: context.l10n.undo,
                onPressed: _undoHistory.isEmpty ? null : _undoStrokeChange,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                key: const ValueKey('erase-brush-redo'),
                tooltip: context.l10n.redo,
                onPressed: _redoHistory.isEmpty ? null : _redoStrokeChange,
                icon: const Icon(Icons.redo),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _strokes.isEmpty ? null : () => _replaceStrokes(const []),
          child: Text(context.l10n.clear),
        ),
        TextButton(
          key: const ValueKey('erase-brush-close'),
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }

  void _startStroke(Offset position, Size size) {
    setState(() {
      _activePoints = [_normalized(position, size)];
    });
  }

  void _continueStroke(Offset position, Size size) {
    final points = _activePoints;
    if (points == null || points.length >= 200) return;
    final next = _normalized(position, size);
    if ((Offset(next.x, next.y) - Offset(points.last.x, points.last.y))
            .distance <
        _radius * 0.25) {
      return;
    }
    setState(() => points.add(next));
  }

  void _finishStroke() {
    final points = _activePoints;
    if (points == null || points.isEmpty) return;
    _replaceStrokes([
      ..._strokes,
      EraseStroke(radius: _radius, points: points),
    ]);
  }

  void _addCenterStamp(Size canvasSize) {
    _startStroke(canvasSize.center(Offset.zero), canvasSize);
    _finishStroke();
  }

  void _replaceStrokes(List<EraseStroke> next) {
    setState(() {
      _undoHistory.add(List.unmodifiable(_strokes));
      _redoHistory.clear();
      _strokes = List.of(next);
      _activePoints = null;
    });
    widget.onChanged(List.unmodifiable(_strokes));
  }

  void _undoStrokeChange() {
    if (_undoHistory.isEmpty) return;
    setState(() {
      _redoHistory.add(List.unmodifiable(_strokes));
      _strokes = List.of(_undoHistory.removeLast());
      _activePoints = null;
    });
    widget.onChanged(List.unmodifiable(_strokes));
  }

  void _redoStrokeChange() {
    if (_redoHistory.isEmpty) return;
    setState(() {
      _undoHistory.add(List.unmodifiable(_strokes));
      _strokes = List.of(_redoHistory.removeLast());
      _activePoints = null;
    });
    widget.onChanged(List.unmodifiable(_strokes));
  }

  NormalizedPoint _normalized(Offset position, Size size) =>
      NormalizedPoint.checked(
        (position.dx / size.width).clamp(0, 1),
        (position.dy / size.height).clamp(0, 1),
      );
}

class _EraseStrokePainter extends CustomPainter {
  const _EraseStrokePainter({
    required this.strokes,
    required this.activePoints,
    required this.activeRadius,
  });

  final List<EraseStroke> strokes;
  final List<NormalizedPoint>? activePoints;
  final double activeRadius;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(canvas, size, stroke.points, stroke.radius);
    }
    final active = activePoints;
    if (active != null) _paintStroke(canvas, size, active, activeRadius);
  }

  void _paintStroke(
    Canvas canvas,
    Size size,
    List<NormalizedPoint> points,
    double radius,
  ) {
    final offsets = points
        .map((point) => Offset(point.x * size.width, point.y * size.height))
        .toList();
    if (offsets.isEmpty) return;
    final paint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.58)
      ..strokeWidth = radius * min(size.width, size.height) * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (offsets.length == 1) {
      canvas.drawCircle(
        offsets.single,
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final point in offsets.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _EraseStrokePainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.activePoints != activePoints ||
      oldDelegate.activeRadius != activeRadius;
}

class _AdjustmentSlider extends StatelessWidget {
  const _AdjustmentSlider({
    super.key,
    required this.enabled,
    required this.label,
    required this.semanticLabel,
    required this.value,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    this.minimum = -1,
    this.maximum = 1,
    this.showValue = true,
  });

  final bool enabled;
  final String label;
  final String semanticLabel;
  final double value;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  final double minimum;
  final double maximum;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (label.isNotEmpty) SizedBox(width: 88, child: Text(label)),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Semantics(
              container: true,
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
        ),
        if (showValue)
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
