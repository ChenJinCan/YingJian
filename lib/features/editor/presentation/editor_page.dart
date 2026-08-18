import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/features/editor/application/batch_photo_exporter.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/application/natural_language_edit_interpreter.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/application/speech_transcriber.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';
import 'package:yingjian/features/editor/domain/quality_enhancement_recipe.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_speech_transcriber.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';
import 'package:yingjian/features/editor/presentation/voice_edit_sheet.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/recommendations/application/local_recommendation_coordinator.dart';
import 'package:yingjian/features/recommendations/application/photo_analysis_cache.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';
import 'package:yingjian/features/recommendations/domain/recipe_catalog.dart';
import 'package:yingjian/l10n/l10n.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    this.speechTranscriber = const MethodChannelSpeechTranscriber(),
    this.startWithImport = false,
    super.key,
  });

  final SpeechTranscriber speechTranscriber;
  final bool startWithImport;

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
  final PhotoExportOptions _exportOptions = PhotoExportOptions(
    size: PhotoExportSize.longEdge,
    longEdgePixels: 2048,
    quality: PhotoExportQuality.standard,
  );
  final Map<String, String> _ownedSharePathsByPhotoId = {};
  final Set<String> _supersededSharePaths = {};
  bool _preparingRecommendations = false;
  RecommendationPreparation? _recommendationPreparation;
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
  int _previewRecommendationIndex = -1;
  double? _previewSharedIntensity;
  double? _pendingPhotoStripOffset;
  bool _savingPhotoStripPosition = false;
  PhotoAnalysisCancellationToken? _analysisCancellation;
  Future<void>? _analysisCompletion;
  Future<void> _lifecycleAnalysisUpdates = Future.value();
  _EditFeedback? _editFeedback;
  bool _handledStartWithImport = false;

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
    unawaited(_initializeSession(session));
  }

  Future<void> _initializeSession(PhotoProjectSession session) async {
    await _restoreProject(session);
    if (!mounted ||
        _handledStartWithImport ||
        !widget.startWithImport ||
        session.photos.isNotEmpty) {
      return;
    }
    _handledStartWithImport = true;
    await _importPhotos();
  }

  Future<void> _restoreProject(PhotoProjectSession session) async {
    await session.restore();
    final recoveredSummary = await BoundedBatchPhotoExporter.recoverInterrupted(
      session,
    );
    final project = session.project;
    final analysisRefreshRequired = await _restoreCachedPortraitApplicability(
      session,
    );
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
    } else if (project != null &&
        project.flowState == PhotoProjectFlowState.editing &&
        analysisRefreshRequired) {
      await _prepareRecommendations(
        persistAnalysisStates: false,
        exposeRecommendations: false,
      );
    }
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

  Future<void> _prepareRecommendations({
    required bool persistAnalysisStates,
    bool exposeRecommendations = true,
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
          if (exposeRecommendations) {
            _recommendationPreparation = preparation;
          }
          _portraitApplicabilityByPhotoId.addAll({
            for (final entry in preparation.analyses.entries)
              entry.key: entry.value.portrait,
          });
          _faceSlimApplicabilityByPhotoId.addAll({
            for (final entry in preparation.analyses.entries)
              entry.key: entry.value.faceSlim,
          });
          _faceSlimReasonByPhotoId.addAll({
            for (final entry in preparation.analyses.entries)
              entry.key: entry.value.faceSlimReason,
          });
          _faceSlimTargetCountByPhotoId.addAll({
            for (final entry in preparation.analyses.entries)
              entry.key: entry.value.faceSlimTargetCount,
          });
          _faceTargetRegionsByPhotoId.addAll({
            for (final entry in preparation.analyses.entries)
              entry.key: entry.value.faceTargetRegions,
          });
          _bodyApplicabilityByPhotoId.addAll({
            for (final entry in preparation.analyses.entries)
              entry.key: entry.value.body,
          });
          _bodyTargetCountByPhotoId.addAll({
            for (final entry in preparation.analyses.entries)
              entry.key: entry.value.bodyTargetCount,
          });
          _bodyTargetRegionsByPhotoId.addAll({
            for (final entry in preparation.analyses.entries)
              entry.key: entry.value.bodyTargetRegions,
          });
          if (exposeRecommendations) {
            _previewRecommendationIndex = preparation.recommendations.isEmpty
                ? -1
                : 0;
          }
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
      if (mounted) setState(() => _editFeedback = null);
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
    try {
      await _session?.resetScopedEdit();
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

  Future<void> _showVoiceEditSheet() async {
    if (_exportSummary != null || _exporting || _sharing) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheetContext) => VoiceEditSheet(
        currentRecipe: _editorSession.recipe,
        interpreter: const LocalNaturalLanguageEditInterpreter(),
        transcriber: widget.speechTranscriber,
        onApplied: (result) async {
          await _commitNaturalLanguageResult(result);
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    );
  }

  Future<void> _applyQuickInstruction(String instruction) async {
    if (_exportSummary != null || _exporting || _sharing) return;
    final result = const LocalNaturalLanguageEditInterpreter().interpret(
      instruction,
      current: _editorSession.recipe,
    );
    if (!result.isApplicable) return;
    await _commitNaturalLanguageResult(result);
  }

  Future<void> _commitNaturalLanguageResult(
    NaturalLanguageEditResult result,
  ) async {
    _editorSession.apply(result.recipe);
    await _persistRecipe();
    if (!mounted) return;
    setState(
      () => _editFeedback = _EditFeedback(
        message:
            result.changes.any(
              (change) => change.parameter == EditableParameter.exposure,
            )
            ? context.l10n.editResultBrighter
            : context.l10n.editResultApplied,
      ),
    );
  }

  Future<void> _applyManualPreset(_ManualPreset preset) async {
    if (_exportSummary != null || _exporting || _sharing) return;
    if (!await _selectManualTargetIfNeeded(preset)) return;
    final current = _editorSession.recipe;
    EditRecipe next;
    switch (preset) {
      case _ManualPreset.brighter:
        await _applyQuickInstruction('照片亮一点');
        return;
      case _ManualPreset.warmer:
        await _applyQuickInstruction('照片暖一点');
        return;
      case _ManualPreset.naturalSkin:
        await _applyQuickInstruction('皮肤自然一点');
        return;
      case _ManualPreset.smootherSkin:
        final portrait = current.portraitRecipe;
        next = current.copyWith(
          portraitRecipe: portrait.copyWith(
            textureSmoothing: min(60, portrait.textureSmoothing + 10),
          ),
        );
      case _ManualPreset.smallerFace:
        next = current.copyWith(
          faceSlimStrength: min(0.30, current.faceSlimStrength + 0.05),
        );
      case _ManualPreset.naturalBody:
        next = current.copyWith(
          bodySlimStrength: min(0.24, current.bodySlimStrength + 0.04),
        );
    }
    _editorSession.apply(next);
    await _persistRecipe();
    if (mounted) {
      setState(
        () => _editFeedback = _EditFeedback(
          message: context.l10n.editResultApplied,
        ),
      );
    }
  }

  Future<bool> _selectManualTargetIfNeeded(_ManualPreset preset) async {
    final session = _session;
    if (session == null || session.photos.isEmpty) return false;
    final photo = session.photos[_selectedIndex];
    final isFace = preset == _ManualPreset.smallerFace;
    final isBody = preset == _ManualPreset.naturalBody;
    if (!isFace && !isBody) return true;
    final regions = isFace
        ? (_faceTargetRegionsByPhotoId[photo.id] ?? const [])
        : (_bodyTargetRegionsByPhotoId[photo.id] ?? const []);
    if (regions.length <= 1) return true;
    final selected = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final recipe = _editorSession.recipe;
        final selectedIndex = isFace
            ? recipe.portraitGeometryRecipe.selectedFaceIndex
            : recipe.portraitGeometryRecipe.selectedBodyIndex;
        return Padding(
          key: const ValueKey('editor-portrait-target-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.choosePersonTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              _PortraitTargetSelector(
                photo: photo,
                regions: regions,
                selectedIndex: selectedIndex,
                targetLabel: isFace
                    ? context.l10n.faceSlimTarget
                    : context.l10n.bodyTarget,
                hint: context.l10n.choosePersonHint,
                enabled: true,
                onSelected: (index) {
                  final geometry = recipe.portraitGeometryRecipe;
                  _editorSession.selectPortraitTarget(
                    recipe.copyWith(
                      portraitGeometryRecipe: isFace
                          ? geometry.selectFace(index)
                          : geometry.selectBody(index),
                    ),
                  );
                  Navigator.pop(sheetContext, true);
                },
              ),
            ],
          ),
        );
      },
    );
    return selected == true;
  }

  Future<void> _showBeginnerAdjustSheet() async {
    if (_exportSummary != null || _exporting || _sharing) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _BeginnerAdjustSheet(
        onSelected: (preset) async {
          Navigator.pop(sheetContext);
          await _applyManualPreset(preset);
        },
      ),
    );
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
    _previewSharedIntensity = null;
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

  void _beginSharedIntensityAdjustment() {
    final project = _session?.project;
    if (project == null ||
        project.editingScope != ProjectEditingScope.group ||
        _previewSharedIntensity != null) {
      return;
    }
    setState(() => _previewSharedIntensity = project.sharedStyle.intensity);
  }

  void _previewSharedIntensityAdjustment(double intensity) {
    if (_previewSharedIntensity == null) return;
    setState(() => _previewSharedIntensity = intensity);
  }

  Future<void> _commitSharedIntensityAdjustment() async {
    final intensity = _previewSharedIntensity;
    if (intensity == null || _exportSummary != null || _exporting || _sharing) {
      return;
    }
    try {
      await _session?.commitSharedIntensity(intensity);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _previewSharedIntensity = null);
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
      _faceSlimApplicabilityByPhotoId.remove(photo.id);
      _faceSlimReasonByPhotoId.remove(photo.id);
      _faceSlimTargetCountByPhotoId.remove(photo.id);
      _bodyApplicabilityByPhotoId.remove(photo.id);
      _bodyTargetCountByPhotoId.remove(photo.id);
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
      _faceSlimApplicabilityByPhotoId.clear();
      _faceSlimReasonByPhotoId.clear();
      _faceSlimTargetCountByPhotoId.clear();
      _bodyApplicabilityByPhotoId.clear();
      _bodyTargetCountByPhotoId.clear();
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

  Future<void> _showSaveOptions() async {
    final project = _session?.project;
    if (project == null || _exporting || _sharing) return;
    final scope = await showModalBottomSheet<_SaveScope>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) =>
          _SaveOptionsSheet(photoCount: project.photos.length),
    );
    if (scope == null) return;
    final photoIds = scope == _SaveScope.current
        ? <String>{project.photos[_selectedIndex].id}
        : null;
    await _exportBatch(photoIds: photoIds);
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
    setState(() => _exporting = true);
    final attemptPhotoIds = <String>{};
    Future<BatchExportSummary>? completion;
    try {
      final batch = BoundedBatchPhotoExporter(
        session: _session!,
        exporter: context.read<PhotoExporter>(),
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

  // Detailed format and quality controls stay in the recipe/export contract,
  // but the beginner save path deliberately uses the safe defaults.
  /* Future<PhotoExportOptions?> _confirmBatchExport() async {
    final project = _session?.project;
    if (project == null) return null;
    final count = project.photos.length;
    var selected = _exportOptions;
    return showDialog<PhotoExportOptions>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.batchExportPhotos(count)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.l10n.exportConfirmationMessage(count)),
                const SizedBox(height: 16),
                Text(
                  context.l10n.exportPhotoPlan,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Semantics(
                  key: const ValueKey('export-photo-plan'),
                  container: true,
                  explicitChildNodes: true,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < project.photos.length;
                        index++
                      )
                        Builder(
                          builder: (context) {
                            final photo = project.photos[index];
                            final status = _exportPlanStatus(
                              context,
                              project,
                              photo.id,
                            );
                            return ListTile(
                              key: ValueKey('export-preview-photo-${photo.id}'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(status.$1, size: 20),
                              title: Text(
                                photo.originalName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${index + 1}/$count · ${status.$2}',
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                Text(
                  context.l10n.exportProcessingEstimate,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.exportFormat,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                SegmentedButton<PhotoExportFormat>(
                  key: const ValueKey('export-format'),
                  segments: [
                    ButtonSegment(
                      value: PhotoExportFormat.jpeg,
                      label: Text(context.l10n.exportFormatJpeg),
                    ),
                    ButtonSegment(
                      value: PhotoExportFormat.heif,
                      label: Text(context.l10n.exportFormatHeif),
                    ),
                  ],
                  selected: {selected.format},
                  onSelectionChanged: (selection) => setDialogState(
                    () => selected = PhotoExportOptions(
                      format: selection.single,
                      size: selected.size,
                      longEdgePixels: selected.longEdgePixels,
                      quality: selected.quality,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const ValueKey('export-size'),
                  initialValue: selected.size == PhotoExportSize.original
                      ? 0
                      : selected.longEdgePixels,
                  decoration: InputDecoration(
                    labelText: context.l10n.exportSize,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(context.l10n.exportSizeOriginal),
                    ),
                    const DropdownMenuItem(value: 4096, child: Text('4096 px')),
                    const DropdownMenuItem(value: 2048, child: Text('2048 px')),
                    const DropdownMenuItem(value: 1080, child: Text('1080 px')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(
                      () => selected = PhotoExportOptions(
                        format: selected.format,
                        size: value == 0
                            ? PhotoExportSize.original
                            : PhotoExportSize.longEdge,
                        longEdgePixels: value == 0 ? null : value,
                        quality: selected.quality,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PhotoExportQuality>(
                  key: const ValueKey('export-quality'),
                  initialValue: selected.quality,
                  decoration: InputDecoration(
                    labelText: context.l10n.exportQuality,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: PhotoExportQuality.high,
                      child: Text(context.l10n.exportQualityHigh),
                    ),
                    DropdownMenuItem(
                      value: PhotoExportQuality.standard,
                      child: Text(context.l10n.exportQualityStandard),
                    ),
                    DropdownMenuItem(
                      value: PhotoExportQuality.compact,
                      child: Text(context.l10n.exportQualityCompact),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(
                      () => selected = PhotoExportOptions(
                        format: selected.format,
                        size: selected.size,
                        longEdgePixels: selected.longEdgePixels,
                        quality: value,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.exportColorSpaceNotice,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey('export-confirm'),
              onPressed: () => Navigator.pop(context, selected),
              child: Text(context.l10n.startExport),
            ),
          ],
        ),
      ),
    );
  } */

  /* (IconData, String) _exportPlanStatus(
    BuildContext context,
    PhotoProject project,
    String photoId,
  ) {
    final exportState =
        project.exportStates[photoId] ?? PhotoExportState.notQueued;
    switch (exportState) {
      case PhotoExportState.queued:
        return (Icons.outbox_outlined, context.l10n.photoStatusQueued);
      case PhotoExportState.running:
        return (Icons.sync, context.l10n.photoStatusExporting);
      case PhotoExportState.saved:
        return (Icons.check_circle_outline, context.l10n.photoStatusExported);
      case PhotoExportState.failed:
        return (Icons.error_outline, context.l10n.photoStatusExportFailed);
      case PhotoExportState.cancelled:
        return (Icons.cancel_outlined, context.l10n.photoStatusExportCancelled);
      case PhotoExportState.notQueued:
        if (project.analysisStates[photoId] == PhotoAnalysisState.failed) {
          return (Icons.shield_outlined, context.l10n.exportWithSafeFallback);
        }
        return (Icons.check_circle_outline, context.l10n.exportWillExport);
    }
  } */

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
            ? _previewSharedIntensity == null
                  ? session.previewRecipeFor(
                      photos[_selectedIndex].id,
                      _editorSession.recipe,
                    )
                  : session.project!
                        .copyWith(
                          sharedStyle: SharedStyle(
                            family: session.project!.sharedStyle.family,
                            intensity: _previewSharedIntensity!,
                            recipe:
                                session.project!.editingScope ==
                                    ProjectEditingScope.group
                                ? _editorSession.recipe
                                : session.project!.sharedStyle.recipe,
                          ),
                        )
                        .effectiveRecipeFor(
                          photos[_selectedIndex].id,
                          photoOverride:
                              session.project!.editingScope ==
                                  ProjectEditingScope.currentPhoto
                              ? _editorSession.recipe
                              : null,
                        )
            : session.project!
                  .copyWith(
                    sharedStyle: previewRecommendation.sharedStyle,
                    adaptiveCompensations:
                        previewRecommendation.adaptiveCompensations,
                  )
                  .effectiveRecipeFor(photos[_selectedIndex].id);
        final editingEnabled =
            session.canEdit && !_sharing && _exportSummary == null;
        final recommendationFlow =
            session.flowState == PhotoProjectFlowState.analyzing ||
            session.flowState == PhotoProjectFlowState.choosingRecommendation;
        final hasPhotosReadyToExport =
            session.project?.exportStates.values.any(
              (state) => state == PhotoExportState.notQueued,
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
        final photoToolsVisible =
            photos.length == 1 ||
            session.project?.editingScope == ProjectEditingScope.currentPhoto;
        return Scaffold(
          key: const ValueKey('editor-page'),
          appBar: AppBar(
            title: MediaQuery.sizeOf(context).width < 700
                ? null
                : Text(
                    context.l10n.appTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
            actions: photos.isEmpty
                ? null
                : [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: FilledButton(
                        key: const ValueKey('editor-batch-export'),
                        onPressed:
                            editingEnabled &&
                                !recommendationFlow &&
                                hasPhotosReadyToExport
                            ? () => unawaited(_showSaveOptions())
                            : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(72, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
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
                          case 'addPhoto':
                            unawaited(_importPhotos());
                          case 'removePhoto':
                            if (selectedPhoto != null) {
                              unawaited(_removePhoto(selectedPhoto));
                            }
                          case 'undo':
                            unawaited(_undoEdit());
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
                          value: 'addPhoto',
                          enabled:
                              !_exporting &&
                              !_sharing &&
                              photos.length < PhotoProject.maxPhotoCount,
                          child: Text(context.l10n.addPhotos),
                        ),
                        PopupMenuItem(
                          value: 'removePhoto',
                          enabled:
                              !_exporting && !_sharing && selectedPhoto != null,
                          child: Text(context.l10n.removePhoto),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'undo',
                          enabled: editingEnabled && session.canUndo,
                          child: Text(context.l10n.undo),
                        ),
                        PopupMenuItem(
                          value: 'redo',
                          enabled: editingEnabled && session.canRedo,
                          child: Text(context.l10n.redo),
                        ),
                        PopupMenuItem(
                          value: 'reset',
                          enabled: editingEnabled && session.canResetScopedEdit,
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
              (_exportSummary?.failedCount == 0 &&
                  _exportSummary?.cancelledCount == 0)
              ? null
              : photos.isEmpty ||
                    session.isRestoring ||
                    session.restoreError != null
              ? null
              : _EditorCommandBar(
                  recommendationFlow: recommendationFlow,
                  preparingRecommendations: _preparingRecommendations,
                  selectedRecommendation: previewRecommendation,
                  editingEnabled: editingEnabled,
                  canUndo: session.canUndo,
                  canRedo: session.canRedo,
                  isEdited: session.canResetScopedEdit,
                  exporting: _exporting,
                  sharing: _sharing,
                  exportSummary: _exportSummary,
                  feedback: _editFeedback,
                  canSyncFeedback:
                      session.canSyncCurrentPhotoAdjustmentsToGroup,
                  onVoiceEdit: () => unawaited(_showVoiceEditSheet()),
                  onManualEdit: () => unawaited(_showBeginnerAdjustSheet()),
                  onSyncFeedback: () =>
                      unawaited(_syncCurrentPhotoAdjustmentsToGroup()),
                  onUndo: () => unawaited(_undoEdit()),
                  onRedo: () => unawaited(_redoEdit()),
                  onReset: () => unawaited(_resetEdit()),
                  onQuickEdit: (instruction) =>
                      unawaited(_applyQuickInstruction(instruction)),
                  onRecommendationSelected: (recommendation) =>
                      unawaited(_selectRecommendation(recommendation)),
                  onCancelExport: _cancelBatchExport,
                  onContinueEditing: () => unawaited(_continueEditing()),
                ),
          body: SafeArea(
            child:
                _exportSummary != null &&
                    _exportSummary!.failedCount == 0 &&
                    _exportSummary!.cancelledCount == 0
                ? _SaveSuccessView(
                    count: _exportSummary!.savedCount,
                    onFinish: _finishSaving,
                    onShare: _exportSummary!.canShare
                        ? () => unawaited(_shareExportedPhotos())
                        : null,
                    sharing: _sharing,
                  )
                : session.isRestoring
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
                    editingEnabled: editingEnabled,
                    previewRecipe: previewRecipe,
                    flowState: session.flowState,
                    preparingRecommendations: _preparingRecommendations,
                    recommendations: recommendations ?? const [],
                    selectedRecommendationIndex: _previewRecommendationIndex,
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
                    onRetryExport: () =>
                        unawaited(_exportBatch(retryFailuresOnly: true)),
                    sharing: _sharing,
                    onShareExport: () => unawaited(_shareExportedPhotos()),
                    onRecipeCommitted: () => unawaited(_persistRecipe()),
                    onSyncCurrentPhotoToGroup: () =>
                        unawaited(_syncCurrentPhotoAdjustmentsToGroup()),
                    onPhotoStripScrollEnd: _savePhotoStripPosition,
                    onRecommendationPreviewed: (index) =>
                        setState(() => _previewRecommendationIndex = index),
                    previewSharedIntensity: _previewSharedIntensity,
                    onSharedIntensityStart: _beginSharedIntensityAdjustment,
                    onSharedIntensityChanged: _previewSharedIntensityAdjustment,
                    onSharedIntensityEnd: () =>
                        unawaited(_commitSharedIntensityAdjustment()),
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
    required this.faceSlimApplicable,
    required this.faceSlimReason,
    required this.faceSlimTargetCount,
    required this.faceTargetRegions,
    required this.bodyApplicable,
    required this.bodyTargetCount,
    required this.bodyTargetRegions,
    required this.photoToolsVisible,
    required this.canSyncCurrentPhoto,
    required this.photoStripController,
    required this.onSelected,
    required this.onMove,
    required this.onRemove,
    required this.onImport,
    required this.onRetryExport,
    required this.sharing,
    required this.onShareExport,
    required this.onRecipeCommitted,
    required this.onSyncCurrentPhotoToGroup,
    required this.onPhotoStripScrollEnd,
    required this.onRecommendationPreviewed,
    required this.previewSharedIntensity,
    required this.onSharedIntensityStart,
    required this.onSharedIntensityChanged,
    required this.onSharedIntensityEnd,
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
  final bool faceSlimApplicable;
  final PortraitDegradationReason faceSlimReason;
  final int faceSlimTargetCount;
  final List<NormalizedTargetRegion> faceTargetRegions;
  final bool bodyApplicable;
  final int bodyTargetCount;
  final List<NormalizedTargetRegion> bodyTargetRegions;
  final bool photoToolsVisible;
  final bool canSyncCurrentPhoto;
  final ScrollController photoStripController;
  final ValueChanged<int> onSelected;
  final void Function(ProjectPhoto photo, int destination) onMove;
  final ValueChanged<ProjectPhoto> onRemove;
  final VoidCallback onImport;
  final VoidCallback onRetryExport;
  final bool sharing;
  final VoidCallback onShareExport;
  final VoidCallback onRecipeCommitted;
  final VoidCallback onSyncCurrentPhotoToGroup;
  final VoidCallback onPhotoStripScrollEnd;
  final ValueChanged<int> onRecommendationPreviewed;
  final double? previewSharedIntensity;
  final VoidCallback onSharedIntensityStart;
  final ValueChanged<double> onSharedIntensityChanged;
  final VoidCallback onSharedIntensityEnd;
  final ValueChanged<ProjectEditingScope> onEditingScopeChanged;

  @override
  Widget build(BuildContext context) {
    final selected = photos[selectedIndex];
    final recipe = editorSession.recipe;
    final previewRenderer = context.read<PhotoPreviewRenderer>();
    final interactionsBlocked = exporting || sharing || exportSummary != null;
    final recommendationFlow =
        flowState == PhotoProjectFlowState.analyzing ||
        flowState == PhotoProjectFlowState.choosingRecommendation;
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
          renderer: previewRenderer,
          recommendationMode:
              flowState == PhotoProjectFlowState.choosingRecommendation,
        ),
      ),
    );
    return Column(
      children: [
        Expanded(
          flex: exportSummary == null
              ? recommendationFlow || compactHeight
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
                          GestureDetector(
                            key: const ValueKey('editor-swipe-photos'),
                            onHorizontalDragEnd: photos.length <= 1
                                ? null
                                : (details) {
                                    final velocity =
                                        details.primaryVelocity ?? 0;
                                    if (velocity < -250 &&
                                        selectedIndex < photos.length - 1) {
                                      onSelected(selectedIndex + 1);
                                    } else if (velocity > 250 &&
                                        selectedIndex > 0) {
                                      onSelected(selectedIndex - 1);
                                    }
                                  },
                            child: SizedBox.expand(child: previewCard),
                          ),
                          if (!recommendationFlow && exportSummary == null)
                            Positioned(
                              left: 12,
                              bottom: 12,
                              child: FilledButton.tonalIcon(
                                key: const ValueKey('editor-open-tools'),
                                onPressed:
                                    editingEnabled && !interactionsBlocked
                                    ? () => _showMobileTools(
                                        context,
                                        selected: selected,
                                        recipe: recipe,
                                        interactionsBlocked:
                                            interactionsBlocked,
                                      )
                                    : null,
                                icon: const Icon(Icons.tune, size: 20),
                                label: Text(context.l10n.allTools),
                              ),
                            ),
                          if (photos.length > 1)
                            Positioned(
                              bottom: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface
                                        .withValues(alpha: 0.88),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      '${selectedIndex + 1} / ${photos.length}',
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
        if (!simplifiedMobile)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected.originalName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
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
                if (interactionsBlocked)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(context.l10n.addPhotos),
                  )
                else
                  IconButton(
                    tooltip: context.l10n.addPhotos,
                    onPressed:
                        busy || photos.length >= PhotoProject.maxPhotoCount
                        ? null
                        : onImport,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                IconButton(
                  tooltip: context.l10n.removePhoto,
                  onPressed: interactionsBlocked
                      ? null
                      : () => onRemove(selected),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
        if (!simplifiedMobile && photos.length > 1)
          NotificationListener<ScrollEndNotification>(
            key: const Key('photo-strip-scroll'),
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.horizontal) {
                onPhotoStripScrollEnd();
              }
              return false;
            },
            child: SizedBox(
              height: MediaQuery.textScalerOf(context).scale(1) > 1.3
                  ? 116
                  : 88,
              child: ListView.separated(
                controller: photoStripController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      key: ValueKey('editor-photo-${photo.id}'),
                      onTap: () => onSelected(index),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SizedBox(
                          width: 88,
                          child: Column(
                            children: [
                              Container(
                                width: 58,
                                height: 58,
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
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(status.$1, size: 12),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      status.$2,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        if (!simplifiedMobile || recommendationFlow || exportSummary != null)
          Expanded(
            flex: exportSummary == null
                ? recommendationFlow || compactHeight
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
                  if (importFailures.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ImportFailures(failures: importFailures),
                  ],
                  if (photos.length > 1 &&
                      editingEnabled &&
                      exportSummary == null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ProjectEditingScope>(
                        segments: [
                          ButtonSegment(
                            value: ProjectEditingScope.group,
                            icon: const Icon(Icons.collections_outlined),
                            label: Text(
                              context.l10n.editWholeGroup,
                              key: const ValueKey('editor-scope-group'),
                            ),
                          ),
                          ButtonSegment(
                            value: ProjectEditingScope.currentPhoto,
                            icon: const Icon(Icons.photo_outlined),
                            label: Text(
                              context.l10n.editCurrentPhoto,
                              key: const ValueKey('editor-scope-currentPhoto'),
                            ),
                          ),
                        ],
                        selected: {project.editingScope},
                        onSelectionChanged: (selection) =>
                            onEditingScopeChanged(selection.single),
                      ),
                    ),
                  ],
                  if (editingEnabled &&
                      exportSummary == null &&
                      !recommendationFlow &&
                      project.editingScope == ProjectEditingScope.group) ...[
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.groupStyleIntensityHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    _AdjustmentSlider(
                      key: const ValueKey('editor-group-style-intensity'),
                      enabled: !interactionsBlocked,
                      label: context.l10n.groupStyleIntensity,
                      semanticLabel: context.l10n.groupStyleIntensity,
                      value:
                          previewSharedIntensity ??
                          project.sharedStyle.intensity,
                      minimum: 0,
                      maximum: 1,
                      onStart: onSharedIntensityStart,
                      onChanged: onSharedIntensityChanged,
                      onEnd: onSharedIntensityEnd,
                    ),
                  ],
                  if (exportSummary == null && recommendationFlow) ...[
                    const SizedBox(height: 12),
                    _RecommendationPanel(
                      preparing: preparingRecommendations,
                      recommendations: recommendations,
                      sourcePath: selected.localPath,
                      previewRecipes: [
                        for (final recommendation in recommendations)
                          project
                              .copyWith(
                                sharedStyle: recommendation.sharedStyle,
                                adaptiveCompensations:
                                    recommendation.adaptiveCompensations,
                              )
                              .effectiveRecipeFor(selected.id),
                      ],
                      previewRenderer: previewRenderer,
                      selectedIndex: selectedRecommendationIndex,
                      onPreviewed: onRecommendationPreviewed,
                    ),
                  ] else if (exportSummary == null) ...[
                    const SizedBox(height: 8),
                    if (MediaQuery.sizeOf(context).width >= 700 &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.3)
                      _MobileToolWorkspace(
                        enabled: editingEnabled,
                        photoToolsVisible: photoToolsVisible,
                        portraitAvailable: portraitApplicable,
                        faceSlimAvailable: faceSlimApplicable,
                        faceSlimReason: faceSlimReason,
                        faceSlimTargetCount: faceSlimTargetCount,
                        faceTargetRegions: faceTargetRegions,
                        bodyAvailable: bodyApplicable,
                        bodyTargetCount: bodyTargetCount,
                        bodyTargetRegions: bodyTargetRegions,
                        subjectAvailable: portraitApplicable || bodyApplicable,
                        allowDetailedTools: photoToolsVisible,
                        photo: selected,
                        recipe: recipe,
                        editorSession: editorSession,
                        onRecipeCommitted: onRecipeCommitted,
                      )
                    else
                      Card(
                        child: ExpansionTile(
                          key: const ValueKey('editor-manual-adjustments'),
                          maintainState: true,
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          leading: const Icon(Icons.tune),
                          title: Text(
                            context.l10n.manualAdjustments,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(context.l10n.manualAdjustmentsHint),
                          children: [
                            _MobileToolWorkspace(
                              enabled: editingEnabled,
                              photoToolsVisible: photoToolsVisible,
                              portraitAvailable: portraitApplicable,
                              faceSlimAvailable: faceSlimApplicable,
                              faceSlimReason: faceSlimReason,
                              faceSlimTargetCount: faceSlimTargetCount,
                              faceTargetRegions: faceTargetRegions,
                              bodyAvailable: bodyApplicable,
                              bodyTargetCount: bodyTargetCount,
                              bodyTargetRegions: bodyTargetRegions,
                              subjectAvailable:
                                  portraitApplicable || bodyApplicable,
                              allowDetailedTools: photoToolsVisible,
                              photo: selected,
                              recipe: recipe,
                              editorSession: editorSession,
                              onRecipeCommitted: onRecipeCommitted,
                            ),
                          ],
                        ),
                      ),
                    if (canSyncCurrentPhoto) ...[
                      OutlinedButton.icon(
                        onPressed: editingEnabled
                            ? onSyncCurrentPhotoToGroup
                            : null,
                        icon: const Icon(Icons.sync_alt),
                        label: Text(context.l10n.syncCurrentAdjustments),
                      ),
                    ],
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
                  if (!interactionsBlocked) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          busy || photos.length >= PhotoProject.maxPhotoCount
                          ? null
                          : onImport,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(context.l10n.addPhotos),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showMobileTools(
    BuildContext context, {
    required ProjectPhoto selected,
    required EditRecipe recipe,
    required bool interactionsBlocked,
  }) async {
    var sheetRecipe = recipe;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: 0.78,
          child: _EditorToolsSheet(
            photos: photos,
            project: project,
            selected: selected,
            recipe: sheetRecipe,
            editingEnabled: editingEnabled,
            interactionsBlocked: interactionsBlocked,
            portraitApplicable: portraitApplicable,
            faceSlimApplicable: faceSlimApplicable,
            faceSlimReason: faceSlimReason,
            faceSlimTargetCount: faceSlimTargetCount,
            faceTargetRegions: faceTargetRegions,
            bodyApplicable: bodyApplicable,
            bodyTargetCount: bodyTargetCount,
            bodyTargetRegions: bodyTargetRegions,
            photoToolsVisible: photoToolsVisible,
            canSyncCurrentPhoto: canSyncCurrentPhoto,
            editorSession: editorSession,
            previewSharedIntensity: previewSharedIntensity,
            onSharedIntensityStart: onSharedIntensityStart,
            onSharedIntensityChanged: onSharedIntensityChanged,
            onSharedIntensityEnd: onSharedIntensityEnd,
            onRecipeCommitted: () {
              setSheetState(() => sheetRecipe = editorSession.recipe);
              onRecipeCommitted();
            },
            onSyncCurrentPhotoToGroup: onSyncCurrentPhotoToGroup,
            onEditingScopeChanged: (scope) {
              Navigator.pop(sheetContext);
              onEditingScopeChanged(scope);
            },
          ),
        ),
      ),
    );
  }
}

class _EditorToolsSheet extends StatelessWidget {
  const _EditorToolsSheet({
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
    required this.bodyApplicable,
    required this.bodyTargetCount,
    required this.bodyTargetRegions,
    required this.photoToolsVisible,
    required this.canSyncCurrentPhoto,
    required this.editorSession,
    required this.previewSharedIntensity,
    required this.onSharedIntensityStart,
    required this.onSharedIntensityChanged,
    required this.onSharedIntensityEnd,
    required this.onRecipeCommitted,
    required this.onSyncCurrentPhotoToGroup,
    required this.onEditingScopeChanged,
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
  final bool bodyApplicable;
  final int bodyTargetCount;
  final List<NormalizedTargetRegion> bodyTargetRegions;
  final bool photoToolsVisible;
  final bool canSyncCurrentPhoto;
  final EditorSession editorSession;
  final double? previewSharedIntensity;
  final VoidCallback onSharedIntensityStart;
  final ValueChanged<double> onSharedIntensityChanged;
  final VoidCallback onSharedIntensityEnd;
  final VoidCallback onRecipeCommitted;
  final VoidCallback onSyncCurrentPhotoToGroup;
  final ValueChanged<ProjectEditingScope> onEditingScopeChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('editor-tools-sheet'),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  context.l10n.adjustPhoto,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const Key('photo-workspace-scroll'),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                if (photos.length > 1) ...[
                  SegmentedButton<ProjectEditingScope>(
                    segments: [
                      ButtonSegment(
                        value: ProjectEditingScope.group,
                        label: Text(
                          context.l10n.editWholeGroup,
                          key: const ValueKey('editor-scope-group'),
                        ),
                      ),
                      ButtonSegment(
                        value: ProjectEditingScope.currentPhoto,
                        label: Text(
                          context.l10n.editCurrentPhoto,
                          key: const ValueKey('editor-scope-currentPhoto'),
                        ),
                      ),
                    ],
                    selected: {project.editingScope},
                    onSelectionChanged: editingEnabled
                        ? (selection) => onEditingScopeChanged(selection.single)
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                if (project.editingScope == ProjectEditingScope.group) ...[
                  _AdjustmentSlider(
                    key: const ValueKey('editor-group-style-intensity'),
                    enabled: !interactionsBlocked,
                    label: context.l10n.groupStyleIntensity,
                    semanticLabel: context.l10n.groupStyleIntensity,
                    value:
                        previewSharedIntensity ?? project.sharedStyle.intensity,
                    minimum: 0,
                    maximum: 1,
                    onStart: onSharedIntensityStart,
                    onChanged: onSharedIntensityChanged,
                    onEnd: onSharedIntensityEnd,
                  ),
                  const SizedBox(height: 12),
                ],
                _MobileToolWorkspace(
                  enabled: editingEnabled,
                  photoToolsVisible: photoToolsVisible,
                  portraitAvailable: portraitApplicable,
                  faceSlimAvailable: faceSlimApplicable,
                  faceSlimReason: faceSlimReason,
                  faceSlimTargetCount: faceSlimTargetCount,
                  faceTargetRegions: faceTargetRegions,
                  bodyAvailable: bodyApplicable,
                  bodyTargetCount: bodyTargetCount,
                  bodyTargetRegions: bodyTargetRegions,
                  subjectAvailable: portraitApplicable || bodyApplicable,
                  allowDetailedTools: photoToolsVisible,
                  photo: selected,
                  recipe: recipe,
                  editorSession: editorSession,
                  onRecipeCommitted: onRecipeCommitted,
                ),
                if (canSyncCurrentPhoto) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: editingEnabled
                        ? onSyncCurrentPhotoToGroup
                        : null,
                    icon: const Icon(Icons.sync_alt),
                    label: Text(context.l10n.syncCurrentAdjustments),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ManualPreset {
  brighter,
  warmer,
  naturalSkin,
  smootherSkin,
  smallerFace,
  naturalBody,
}

enum _SaveScope { all, current }

class _EditFeedback {
  const _EditFeedback({required this.message});

  final String message;
}

class _ResultFeedbackPill extends StatelessWidget {
  const _ResultFeedbackPill({
    required this.feedback,
    required this.canSync,
    required this.onSync,
    required this.onUndo,
  });

  final _EditFeedback feedback;
  final bool canSync;
  final VoidCallback onSync;
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
              if (canSync)
                TextButton(
                  key: const ValueKey('editor-feedback-sync'),
                  onPressed: onSync,
                  child: Text(context.l10n.syncAllPhotos),
                ),
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

class _BeginnerAdjustSheet extends StatelessWidget {
  const _BeginnerAdjustSheet({required this.onSelected});

  final ValueChanged<_ManualPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = <(_ManualPreset, IconData, String)>[
      (
        _ManualPreset.brighter,
        Icons.light_mode_outlined,
        context.l10n.manualBrighter,
      ),
      (
        _ManualPreset.warmer,
        Icons.wb_sunny_outlined,
        context.l10n.manualWarmer,
      ),
      (
        _ManualPreset.naturalSkin,
        Icons.face_retouching_natural,
        context.l10n.manualNaturalSkin,
      ),
      (
        _ManualPreset.smootherSkin,
        Icons.blur_on_outlined,
        context.l10n.manualSmootherSkin,
      ),
      (
        _ManualPreset.smallerFace,
        Icons.face_outlined,
        context.l10n.manualSmallerFace,
      ),
      (
        _ManualPreset.naturalBody,
        Icons.accessibility_new,
        context.l10n.manualNaturalBody,
      ),
    ];
    return Padding(
      key: const ValueKey('editor-manual-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.quickAdjust,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.manualSimpleHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.15,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return OutlinedButton.icon(
                key: ValueKey('manual-action-${item.$1.name}'),
                onPressed: () => onSelected(item.$1),
                icon: Icon(item.$2),
                label: Text(item.$3, textAlign: TextAlign.center),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SaveOptionsSheet extends StatelessWidget {
  const _SaveOptionsSheet({required this.photoCount});

  final int photoCount;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('editor-save-options'),
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.savePhotos,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 18),
        FilledButton(
          key: const ValueKey('save-all'),
          onPressed: () => Navigator.pop(context, _SaveScope.all),
          child: Text(context.l10n.saveAllPhotos(photoCount)),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const ValueKey('save-current'),
          onPressed: () => Navigator.pop(context, _SaveScope.current),
          child: Text(context.l10n.saveCurrentPhoto),
        ),
        TextButton(
          key: const ValueKey('save-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
      ],
    ),
  );
}

class _SaveSuccessView extends StatelessWidget {
  const _SaveSuccessView({
    required this.count,
    required this.onFinish,
    required this.onShare,
    required this.sharing,
  });

  final int count;
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
              context.l10n.saveSuccess(count),
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
    required this.recommendationFlow,
    required this.preparingRecommendations,
    required this.selectedRecommendation,
    required this.editingEnabled,
    required this.canUndo,
    required this.canRedo,
    required this.isEdited,
    required this.exporting,
    required this.sharing,
    required this.exportSummary,
    required this.feedback,
    required this.canSyncFeedback,
    required this.onVoiceEdit,
    required this.onManualEdit,
    required this.onSyncFeedback,
    required this.onUndo,
    required this.onRedo,
    required this.onReset,
    required this.onQuickEdit,
    required this.onRecommendationSelected,
    required this.onCancelExport,
    required this.onContinueEditing,
  });

  final bool recommendationFlow;
  final bool preparingRecommendations;
  final LocalRecommendation? selectedRecommendation;
  final bool editingEnabled;
  final bool canUndo;
  final bool canRedo;
  final bool isEdited;
  final bool exporting;
  final bool sharing;
  final BatchExportSummary? exportSummary;
  final _EditFeedback? feedback;
  final bool canSyncFeedback;
  final VoidCallback onVoiceEdit;
  final VoidCallback onManualEdit;
  final VoidCallback onSyncFeedback;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onReset;
  final ValueChanged<String> onQuickEdit;
  final ValueChanged<LocalRecommendation> onRecommendationSelected;
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: recommendationFlow || interactionsBlocked
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
                          canSync: canSyncFeedback,
                          onSync: onSyncFeedback,
                          onUndo: onUndo,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (MediaQuery.sizeOf(context).width >= 700 &&
                          MediaQuery.textScalerOf(context).scale(1) <= 1.3)
                        Row(
                          children: [
                            TextButton(
                              onPressed: editingEnabled && canUndo
                                  ? onUndo
                                  : null,
                              child: Text(context.l10n.undo),
                            ),
                            TextButton(
                              onPressed: editingEnabled && canRedo
                                  ? onRedo
                                  : null,
                              child: Text(context.l10n.redo),
                            ),
                            TextButton(
                              onPressed: editingEnabled && isEdited
                                  ? onReset
                                  : null,
                              child: Text(context.l10n.reset),
                            ),
                            const Spacer(),
                            OutlinedButton.icon(
                              key: const ValueKey('voice-edit-entry'),
                              onPressed: editingEnabled ? onVoiceEdit : null,
                              icon: const Icon(Icons.mic_none_outlined),
                              label: Text(context.l10n.voiceEditEntry),
                            ),
                          ],
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const ValueKey('voice-edit-entry'),
                                onPressed: editingEnabled ? onVoiceEdit : null,
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  foregroundColor: colors.onSurfaceVariant,
                                  minimumSize: const Size.fromHeight(54),
                                ),
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: Text(context.l10n.voiceEditPrompt),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              key: const ValueKey('voice-edit-microphone'),
                              tooltip: context.l10n.voiceEditEntry,
                              onPressed: editingEnabled ? onVoiceEdit : null,
                              constraints: const BoxConstraints.tightFor(
                                width: 54,
                                height: 54,
                              ),
                              icon: const Icon(Icons.mic_none_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.center,
                          child: TextButton.icon(
                            key: const ValueKey('editor-manual-entry'),
                            onPressed: editingEnabled ? onManualEdit : null,
                            icon: const Icon(Icons.tune, size: 18),
                            label: Text(context.l10n.quickAdjust),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _statusAction(BuildContext context) {
    if (recommendationFlow) {
      return FilledButton.icon(
        key: const ValueKey('recommendation-use'),
        onPressed: preparingRecommendations || selectedRecommendation == null
            ? null
            : () => onRecommendationSelected(selectedRecommendation!),
        icon: const Icon(Icons.check),
        label: Text(
          preparingRecommendations
              ? context.l10n.analysisPreparing
              : context.l10n.useThisLook,
        ),
      );
    }
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

(IconData, String) _photoStatus(
  BuildContext context,
  PhotoProject project,
  String photoId,
) {
  switch (project.exportStates[photoId] ?? PhotoExportState.notQueued) {
    case PhotoExportState.queued:
      return (Icons.outbox_outlined, context.l10n.photoStatusQueued);
    case PhotoExportState.running:
      return (Icons.sync, context.l10n.photoStatusExporting);
    case PhotoExportState.saved:
      return (Icons.check_circle_outline, context.l10n.photoStatusExported);
    case PhotoExportState.failed:
      return (Icons.error_outline, context.l10n.photoStatusExportFailed);
    case PhotoExportState.cancelled:
      return (Icons.cancel_outlined, context.l10n.photoStatusExportCancelled);
    case PhotoExportState.notQueued:
      break;
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
    required this.sourcePath,
    required this.previewRecipes,
    required this.previewRenderer,
    required this.selectedIndex,
    required this.onPreviewed,
  });

  final bool preparing;
  final List<LocalRecommendation> recommendations;
  final String sourcePath;
  final List<EditRecipe> previewRecipes;
  final PhotoPreviewRenderer previewRenderer;
  final int selectedIndex;
  final ValueChanged<int> onPreviewed;

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
              height: 224,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < recommendations.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          right: index == recommendations.length - 1 ? 0 : 10,
                        ),
                        child: Builder(
                          builder: (context) {
                            final recommendation = recommendations[index];
                            final isSelected = index == safeIndex;
                            return Semantics(
                              selected: isSelected,
                              button: true,
                              child: InkWell(
                                key: ValueKey(
                                  'recommendation-${recommendation.family.name}',
                                ),
                                onTap: () => onPreviewed(index),
                                borderRadius: BorderRadius.circular(16),
                                child: AnimatedContainer(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 160),
                                  width: 156,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: isSelected
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer
                                        : Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHigh,
                                    border: Border.all(
                                      color: isSelected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: SizedBox(
                                          key: ValueKey(
                                            'recommendation-preview-'
                                            '${recommendation.family.name}',
                                          ),
                                          width: double.infinity,
                                          height: 82,
                                          child: ExcludeSemantics(
                                            child: NativePhotoPreview(
                                              sourcePath: sourcePath,
                                              recipe: previewRecipes[index],
                                              renderer: previewRenderer,
                                              maxEdge: 384,
                                              errorBuilder: (context) =>
                                                  ColoredBox(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest,
                                                    child: Center(
                                                      child: Icon(
                                                        _recommendationIcon(
                                                          recommendation.family,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _recommendationLabel(
                                          context,
                                          recommendation.family,
                                        ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      Text(
                                        index == 0
                                            ? context.l10n.primaryRecommendation
                                            : context
                                                  .l10n
                                                  .alternativeRecommendation,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                      Text(
                                        _recommendationReason(
                                          context,
                                          recommendation.reason,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
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
              child: SingleChildScrollView(
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
    );
  }
}

enum _MobileToolCategory {
  composition,
  color,
  filters,
  quality,
  retouch,
  semantic,
}

enum _AdjustmentToolScope { color, quality, portrait }

class _MobileToolWorkspace extends StatefulWidget {
  const _MobileToolWorkspace({
    required this.enabled,
    required this.photoToolsVisible,
    required this.portraitAvailable,
    required this.faceSlimAvailable,
    required this.faceSlimReason,
    required this.faceSlimTargetCount,
    required this.faceTargetRegions,
    required this.bodyAvailable,
    required this.bodyTargetCount,
    required this.bodyTargetRegions,
    required this.subjectAvailable,
    required this.allowDetailedTools,
    required this.photo,
    required this.recipe,
    required this.editorSession,
    required this.onRecipeCommitted,
  });

  final bool enabled;
  final bool photoToolsVisible;
  final bool portraitAvailable;
  final bool faceSlimAvailable;
  final PortraitDegradationReason faceSlimReason;
  final int faceSlimTargetCount;
  final List<NormalizedTargetRegion> faceTargetRegions;
  final bool bodyAvailable;
  final int bodyTargetCount;
  final List<NormalizedTargetRegion> bodyTargetRegions;
  final bool subjectAvailable;
  final bool allowDetailedTools;
  final ProjectPhoto photo;
  final EditRecipe recipe;
  final EditorSession editorSession;
  final VoidCallback onRecipeCommitted;

  @override
  State<_MobileToolWorkspace> createState() => _MobileToolWorkspaceState();
}

class _MobileToolWorkspaceState extends State<_MobileToolWorkspace> {
  late _MobileToolCategory _selected;

  @override
  void initState() {
    super.initState();
    _selected =
        widget.photoToolsVisible &&
            (widget.portraitAvailable || widget.bodyAvailable)
        ? _MobileToolCategory.retouch
        : _MobileToolCategory.color;
  }

  @override
  void didUpdateWidget(covariant _MobileToolWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final portraitBecameAvailable =
        (!oldWidget.portraitAvailable && widget.portraitAvailable) ||
        (!oldWidget.bodyAvailable && widget.bodyAvailable);
    if (_selected == _MobileToolCategory.color &&
        widget.photoToolsVisible &&
        portraitBecameAvailable) {
      _selected = _MobileToolCategory.retouch;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = <_MobileToolCategory>[
      if (widget.allowDetailedTools && supportsImagePipelineV2)
        _MobileToolCategory.composition,
      _MobileToolCategory.color,
      if (defaultTargetPlatform == TargetPlatform.iOS)
        _MobileToolCategory.filters,
      if (widget.allowDetailedTools &&
          defaultTargetPlatform == TargetPlatform.iOS) ...[
        _MobileToolCategory.quality,
        if (widget.photoToolsVisible &&
            (widget.portraitAvailable || widget.bodyAvailable))
          _MobileToolCategory.retouch,
        _MobileToolCategory.semantic,
      ],
    ];
    final selected = categories.contains(_selected)
        ? _selected
        : _MobileToolCategory.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: SingleChildScrollView(
            key: const ValueKey('editor-tool-categories'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < categories.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  ChoiceChip(
                    key: ValueKey(
                      'editor-tool-category-${categories[index].name}',
                    ),
                    avatar: Icon(_icon(categories[index]), size: 18),
                    label: Text(_label(context, categories[index])),
                    selected: categories[index] == selected,
                    onSelected: (_) =>
                        setState(() => _selected = categories[index]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(
            key: ValueKey('editor-tool-panel-${selected.name}'),
            child: switch (selected) {
              _MobileToolCategory.color => _AdjustmentToolStrip(
                scope: _AdjustmentToolScope.color,
                enabled: widget.enabled,
                extended: supportsImagePipelineV2,
                photoToolsVisible: widget.photoToolsVisible,
                portraitAvailable: widget.portraitAvailable,
                faceSlimAvailable: widget.faceSlimAvailable,
                faceSlimReason: widget.faceSlimReason,
                faceSlimTargetCount: widget.faceSlimTargetCount,
                faceTargetRegions: widget.faceTargetRegions,
                bodyAvailable: widget.bodyAvailable,
                bodyTargetCount: widget.bodyTargetCount,
                bodyTargetRegions: widget.bodyTargetRegions,
                photo: widget.photo,
                recipe: widget.recipe,
                editorSession: widget.editorSession,
                onRecipeCommitted: widget.onRecipeCommitted,
              ),
              _MobileToolCategory.quality => _AdjustmentToolStrip(
                scope: _AdjustmentToolScope.quality,
                enabled: widget.enabled,
                extended: supportsImagePipelineV2,
                photoToolsVisible: widget.photoToolsVisible,
                portraitAvailable: widget.portraitAvailable,
                faceSlimAvailable: widget.faceSlimAvailable,
                faceSlimReason: widget.faceSlimReason,
                faceSlimTargetCount: widget.faceSlimTargetCount,
                faceTargetRegions: widget.faceTargetRegions,
                bodyAvailable: widget.bodyAvailable,
                bodyTargetCount: widget.bodyTargetCount,
                bodyTargetRegions: widget.bodyTargetRegions,
                photo: widget.photo,
                recipe: widget.recipe,
                editorSession: widget.editorSession,
                onRecipeCommitted: widget.onRecipeCommitted,
              ),
              _MobileToolCategory.retouch => _AdjustmentToolStrip(
                scope: _AdjustmentToolScope.portrait,
                enabled: widget.enabled,
                extended: supportsImagePipelineV2,
                photoToolsVisible: widget.photoToolsVisible,
                portraitAvailable: widget.portraitAvailable,
                faceSlimAvailable: widget.faceSlimAvailable,
                faceSlimReason: widget.faceSlimReason,
                faceSlimTargetCount: widget.faceSlimTargetCount,
                faceTargetRegions: widget.faceTargetRegions,
                bodyAvailable: widget.bodyAvailable,
                bodyTargetCount: widget.bodyTargetCount,
                bodyTargetRegions: widget.bodyTargetRegions,
                photo: widget.photo,
                recipe: widget.recipe,
                editorSession: widget.editorSession,
                onRecipeCommitted: widget.onRecipeCommitted,
              ),
              _MobileToolCategory.composition => _CompositionTools(
                enabled: widget.enabled,
                photo: widget.photo,
                recipe: widget.recipe,
                editorSession: widget.editorSession,
                onRecipeCommitted: widget.onRecipeCommitted,
              ),
              _MobileToolCategory.filters => _FilterHslTools(
                enabled: widget.enabled,
                recipe: widget.recipe,
                editorSession: widget.editorSession,
                onRecipeCommitted: widget.onRecipeCommitted,
              ),
              _MobileToolCategory.semantic => _SemanticTools(
                enabled: widget.enabled,
                subjectAvailable: widget.subjectAvailable,
                photo: widget.photo,
                recipe: widget.recipe,
                editorSession: widget.editorSession,
                onRecipeCommitted: widget.onRecipeCommitted,
              ),
            },
          ),
        ),
      ],
    );
  }

  IconData _icon(_MobileToolCategory category) => switch (category) {
    _MobileToolCategory.composition => Icons.crop_rotate,
    _MobileToolCategory.color => Icons.tune,
    _MobileToolCategory.filters => Icons.filter_vintage_outlined,
    _MobileToolCategory.quality => Icons.auto_fix_high_outlined,
    _MobileToolCategory.retouch => Icons.face_retouching_natural,
    _MobileToolCategory.semantic => Icons.layers_outlined,
  };

  String _label(BuildContext context, _MobileToolCategory category) =>
      switch (category) {
        _MobileToolCategory.composition => context.l10n.composition,
        _MobileToolCategory.color => context.l10n.lightAndColorTools,
        _MobileToolCategory.filters => context.l10n.filterAndHsl,
        _MobileToolCategory.quality => context.l10n.qualityTools,
        _MobileToolCategory.retouch => context.l10n.mobileToolRetouch,
        _MobileToolCategory.semantic => context.l10n.semanticTools,
      };
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
    required this.scope,
    required this.enabled,
    required this.extended,
    required this.photoToolsVisible,
    required this.portraitAvailable,
    required this.faceSlimAvailable,
    required this.faceSlimReason,
    required this.faceSlimTargetCount,
    required this.faceTargetRegions,
    required this.bodyAvailable,
    required this.bodyTargetCount,
    required this.bodyTargetRegions,
    required this.photo,
    required this.recipe,
    required this.editorSession,
    required this.onRecipeCommitted,
  });

  final _AdjustmentToolScope scope;
  final bool enabled;
  final bool extended;
  final bool photoToolsVisible;
  final bool portraitAvailable;
  final bool faceSlimAvailable;
  final PortraitDegradationReason faceSlimReason;
  final int faceSlimTargetCount;
  final List<NormalizedTargetRegion> faceTargetRegions;
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

  @override
  void initState() {
    super.initState();
    _selected = _initialSelection();
  }

  @override
  void didUpdateWidget(covariant _AdjustmentToolStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _selected = _initialSelection();
      return;
    }
    if ((!oldWidget.portraitAvailable || !oldWidget.photoToolsVisible) &&
        widget.portraitAvailable &&
        widget.photoToolsVisible) {
      _selected = _AdjustmentParameter.naturalBeautification;
    } else if ((oldWidget.portraitAvailable || oldWidget.photoToolsVisible) &&
        (!widget.portraitAvailable || !widget.photoToolsVisible) &&
        (_selected == _AdjustmentParameter.naturalBeautification ||
            _selected == _AdjustmentParameter.textureSmoothing ||
            _selected == _AdjustmentParameter.skinToneLighting ||
            _selected == _AdjustmentParameter.blemishReduction ||
            _selected == _AdjustmentParameter.faceSlim)) {
      _selected = widget.photoToolsVisible && widget.bodyAvailable
          ? _AdjustmentParameter.bodySlim
          : _AdjustmentParameter.exposure;
    }
    if ((!oldWidget.bodyAvailable || !oldWidget.photoToolsVisible) &&
        widget.bodyAvailable &&
        widget.photoToolsVisible &&
        !widget.portraitAvailable) {
      _selected = _AdjustmentParameter.bodySlim;
    } else if ((oldWidget.bodyAvailable || oldWidget.photoToolsVisible) &&
        (!widget.bodyAvailable || !widget.photoToolsVisible) &&
        _selected == _AdjustmentParameter.bodySlim) {
      _selected = widget.photoToolsVisible && widget.portraitAvailable
          ? _AdjustmentParameter.naturalBeautification
          : _AdjustmentParameter.exposure;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parameters = _parameters();
    final selected =
        parameters.contains(_selected) ||
            (widget.photoToolsVisible && _isQualityDetail(_selected)) ||
            (widget.photoToolsVisible &&
                widget.portraitAvailable &&
                _isNaturalDetail(_selected)) ||
            (widget.photoToolsVisible &&
                widget.faceSlimAvailable &&
                _isFaceGeometry(_selected)) ||
            (widget.photoToolsVisible &&
                widget.bodyAvailable &&
                _isBodyGeometry(_selected))
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
    final selectedLabel = _label(context, selected);
    final selectedValue = _value(effectiveRecipe, selected);
    final selectedIsPortrait = _isPortrait(selected);
    final selectedIsQuality = _isQuality(selected);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final portraitReady =
        widget.photoToolsVisible &&
        (widget.portraitAvailable || widget.bodyAvailable);
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
        if (widget.scope == _AdjustmentToolScope.portrait &&
            widget.photoToolsVisible &&
            widget.portraitAvailable &&
            !widget.faceSlimAvailable) ...[
          const SizedBox(height: 6),
          Text(
            widget.faceSlimReason == PortraitDegradationReason.backgroundRisk
                ? context.l10n.faceSlimBackgroundProtected
                : widget.faceSlimReason ==
                      PortraitDegradationReason.multipleFaces
                ? context.l10n.faceSlimMultipleFaces
                : context.l10n.faceSlimUnavailable,
            key: const ValueKey('editor-face-slim-unavailable'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
        if (selected == _AdjustmentParameter.qualityImprovement)
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
                            widget.recipe.copyWith(
                              portraitRecipe: PortraitRetouchRecipe
                                  .naturalBeautificationRecommended,
                            ),
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
                      onChanged: (value) => widget.editorSession.preview(
                        _copyWith(effectiveRecipe, selected, value),
                      ),
                      onEnd: () {
                        widget.editorSession.commitAdjustment();
                        widget.onRecipeCommitted();
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    key: const ValueKey('editor-reset-current-adjustment'),
                    tooltip: context.l10n.resetCurrentAdjustment,
                    onPressed: widget.enabled && selectedValue != 0
                        ? () {
                            widget.editorSession.apply(
                              _copyWith(effectiveRecipe, selected, 0),
                            );
                            widget.onRecipeCommitted();
                          }
                        : null,
                    icon: const Icon(Icons.restart_alt),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  _AdjustmentParameter _initialSelection() => switch (widget.scope) {
    _AdjustmentToolScope.color => _AdjustmentParameter.exposure,
    _AdjustmentToolScope.quality => _AdjustmentParameter.qualityImprovement,
    _AdjustmentToolScope.portrait =>
      widget.photoToolsVisible && widget.portraitAvailable
          ? _AdjustmentParameter.naturalBeautification
          : _AdjustmentParameter.bodySlim,
  };

  List<_AdjustmentParameter> _parameters() => switch (widget.scope) {
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
    _AdjustmentToolScope.quality => const [
      _AdjustmentParameter.qualityImprovement,
    ],
    _AdjustmentToolScope.portrait => [
      if (widget.photoToolsVisible && widget.portraitAvailable)
        _AdjustmentParameter.naturalBeautification,
      if (widget.photoToolsVisible && widget.faceSlimAvailable)
        _AdjustmentParameter.faceSlim,
      if (widget.photoToolsVisible && widget.bodyAvailable)
        _AdjustmentParameter.bodySlim,
    ],
  };

  bool _isPortrait(_AdjustmentParameter parameter) =>
      parameter == _AdjustmentParameter.naturalBeautification ||
      parameter == _AdjustmentParameter.textureSmoothing ||
      parameter == _AdjustmentParameter.skinToneLighting ||
      parameter == _AdjustmentParameter.blemishReduction ||
      _isFaceGeometry(parameter) ||
      _isBodyGeometry(parameter);

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
          recipe.portraitRecipe.textureSmoothing / 100,
        _AdjustmentParameter.skinToneLighting =>
          recipe.portraitRecipe.skinToneLighting / 100,
        _AdjustmentParameter.blemishReduction =>
          recipe.portraitRecipe.blemishReduction / 100,
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
    _AdjustmentParameter.textureSmoothing => recipe.copyWith(
      portraitRecipe: recipe.portraitRecipe.copyWith(
        textureSmoothing: (value * 100).round(),
      ),
    ),
    _AdjustmentParameter.skinToneLighting => recipe.copyWith(
      portraitRecipe: recipe.portraitRecipe.copyWith(
        skinToneLighting: (value * 100).round(),
      ),
    ),
    _AdjustmentParameter.blemishReduction => recipe.copyWith(
      portraitRecipe: recipe.portraitRecipe.copyWith(
        blemishReduction: (value * 100).round(),
      ),
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
  final int selectedIndex;
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
    final message = !photoToolsVisible
        ? context.l10n.switchToCurrentPhotoForPortrait
        : available
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
    final result = await showDialog<CropGeometry>(
      context: context,
      builder: (context) => _FreeCropDialog(
        sourcePath: photo.localPath,
        sourceAspectRatio: width > 0 && height > 0 ? width / height : 4 / 3,
        initial: recipe.crop,
        previewRecipe: recipe.copyWith(crop: CropGeometry.original),
      ),
    );
    if (result != null) _commit(recipe.copyWith(crop: result));
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
  });

  final String sourcePath;
  final double sourceAspectRatio;
  final CropGeometry initial;
  final EditRecipe previewRecipe;

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
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('free-crop-apply'),
          onPressed: () => Navigator.pop(
            context,
            widget.initial.copyWith(
              left: _left,
              top: _top,
              right: _right,
              bottom: _bottom,
            ),
          ),
          child: Text(context.l10n.applyCrop),
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

class _FilterHslTools extends StatefulWidget {
  const _FilterHslTools({
    required this.enabled,
    required this.recipe,
    required this.editorSession,
    required this.onRecipeCommitted,
  });

  final bool enabled;
  final EditRecipe recipe;
  final EditorSession editorSession;
  final VoidCallback onRecipeCommitted;

  @override
  State<_FilterHslTools> createState() => _FilterHslToolsState();
}

class _FilterHslToolsState extends State<_FilterHslTools> {
  HslChannel _selectedChannel = HslChannel.red;

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
        const SizedBox(height: 12),
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
                  index < BackgroundTreatment.values.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Builder(
                    builder: (context) {
                      final treatment = BackgroundTreatment.values[index];
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
    final result = await showDialog<List<EraseStroke>>(
      context: context,
      builder: (context) => _EraseBrushDialog(
        sourcePath: photo.localPath,
        sourceAspectRatio: photo.pixelWidth > 0 && photo.pixelHeight > 0
            ? photo.pixelWidth / photo.pixelHeight
            : 4 / 3,
        initial: editorSession.recipe.semanticEditingRecipe.eraseStrokes,
        previewRecipe: editorSession.recipe,
      ),
    );
    if (result != null) {
      _commit(
        editorSession.recipe.semanticEditingRecipe.copyWith(
          eraseStrokes: result,
        ),
      );
    }
  }

  Future<void> _openMaskBrush(
    BuildContext context, {
    required bool localAdjustment,
  }) async {
    final semantic = editorSession.recipe.semanticEditingRecipe;
    final result = await showDialog<List<MaskStroke>>(
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
      ),
    );
    if (result == null) return;
    _commit(
      localAdjustment
          ? semantic.copyWith(localAdjustmentStrokes: result)
          : semantic.copyWith(subjectMaskStrokes: result),
    );
  }

  Future<void> _pickBackgroundImage(BuildContext context) async {
    final batch = await context.read<PhotoImporter>().importPhotos(limit: 1);
    if (!context.mounted) return;
    if (batch.photos.isEmpty) {
      if (batch.failures.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.backgroundImageImportFailed)),
        );
      }
      return;
    }
    _commit(
      editorSession.recipe.semanticEditingRecipe.copyWith(
        background: BackgroundTreatment.image,
        backgroundImagePath: batch.photos.single.localPath,
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
  };
}

class _MaskBrushDialog extends StatefulWidget {
  const _MaskBrushDialog({
    required this.sourcePath,
    required this.sourceAspectRatio,
    required this.initial,
    required this.previewRecipe,
    required this.localAdjustment,
  });

  final String sourcePath;
  final double sourceAspectRatio;
  final List<MaskStroke> initial;
  final EditRecipe previewRecipe;
  final bool localAdjustment;

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
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: ValueKey('$keyPrefix-apply'),
          onPressed: () => Navigator.pop(context, _strokes),
          child: Text(context.l10n.apply),
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
  }

  void _undoStrokeChange() {
    if (_undoHistory.isEmpty) return;
    setState(() {
      _redoHistory.add(List.unmodifiable(_strokes));
      _strokes = List.of(_undoHistory.removeLast());
      _activePoints = null;
    });
  }

  void _redoStrokeChange() {
    if (_redoHistory.isEmpty) return;
    setState(() {
      _undoHistory.add(List.unmodifiable(_strokes));
      _strokes = List.of(_redoHistory.removeLast());
      _activePoints = null;
    });
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
  });

  final String sourcePath;
  final double sourceAspectRatio;
  final List<EraseStroke> initial;
  final EditRecipe previewRecipe;

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
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('erase-brush-apply'),
          onPressed: () => Navigator.pop(context, _strokes),
          child: Text(context.l10n.apply),
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
  }

  void _undoStrokeChange() {
    if (_undoHistory.isEmpty) return;
    setState(() {
      _redoHistory.add(List.unmodifiable(_strokes));
      _strokes = List.of(_undoHistory.removeLast());
      _activePoints = null;
    });
  }

  void _redoStrokeChange() {
    if (_redoHistory.isEmpty) return;
    setState(() {
      _undoHistory.add(List.unmodifiable(_strokes));
      _strokes = List.of(_redoHistory.removeLast());
      _activePoints = null;
    });
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
