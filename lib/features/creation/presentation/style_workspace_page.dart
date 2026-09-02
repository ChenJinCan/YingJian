import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/features/creation/application/cleanup_capability_preparer.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/creation/domain/creation_intent.dart';
import 'package:yingjian/features/creation/domain/creation_task.dart';
import 'package:yingjian/features/creation/domain/style_definition.dart';
import 'package:yingjian/features/editor/application/batch_photo_exporter.dart';
import 'package:yingjian/features/editor/application/meta_op_capabilities_provider.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/content_sha256.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';
import 'package:yingjian/features/editor/domain/quality_enhancement_recipe.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';
import 'package:yingjian/features/generation/application/generated_media_actions.dart';
import 'package:yingjian/features/generation/application/mask_removal_input_builder.dart';
import 'package:yingjian/features/generation/application/motion_photo_generator.dart';
import 'package:yingjian/features/generation/application/upscale_photo_generator.dart';
import 'package:yingjian/features/generation/domain/generation_input.dart';
import 'package:yingjian/features/generation/presentation/mask_removal_input_editor.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/photo_analysis/domain/photo_analysis.dart';
import 'package:yingjian/l10n/l10n.dart';

class StyleWorkspacePage extends StatefulWidget {
  StyleWorkspacePage({
    required this.intent,
    CreationTask? task,
    this.projectId,
    super.key,
  }) : task = task ?? CreationTask.fromCreationIntent(intent) {
    if (this.task.creationIntent != intent) {
      throw ArgumentError.value(
        task,
        'task',
        'The task must use the same execution intent as its workspace',
      );
    }
  }

  final CreationIntent intent;
  final CreationTask task;
  final String? projectId;

  @override
  State<StyleWorkspacePage> createState() => _StyleWorkspacePageState();
}

enum _CloudCapabilityDiscovery { notLoaded, loading, loaded, failed }

class _StyleWorkspacePageState extends State<StyleWorkspacePage> {
  PhotoProjectStore? _store;
  PhotoProjectSession? _session;
  PhotoSharer? _photoSharer;
  Future<PhotoProject?>? _project;
  PlatformMetaOpCapabilities? _capabilities;
  late List<_StyleChoice> _officialStyles;
  _StyleChoice? _aiStyle;
  String? _selectedStyleId;
  bool _savingStyle = false;
  bool _applying = false;
  bool _styleApplied = false;
  bool _exporting = false;
  bool _sharing = false;
  bool _preparingShare = false;
  PhotoExportStage _exportStage = PhotoExportStage.preparing;
  bool _explainedPhotoPermission = false;
  bool _photoPermissionDenied = false;
  EditRecipe? _renderedPreviewRecipe;
  EditRecipe? _failedPreviewRecipe;
  int _previewRetryToken = 0;
  int _previewSelectionGeneration = 0;
  int? _pendingAutoApplyGeneration;
  BoundedBatchPhotoExporter? _batchExporter;
  Future<BatchExportSummary>? _batchCompletion;
  Future<void>? _shareCompletion;
  PhotoPreparation? _activeSharePreparation;
  BatchExportSummary? _exportSummary;
  final Map<String, String> _ownedSharePathsByPhotoId = {};
  final Set<String> _supersededSharePaths = {};
  bool? _cleanupSubjectAvailable;
  EditingResourceImporter? _editingResourceImporter;
  GenerationCoordinator? _generationCoordinator;
  GeneratedMediaActions? _generatedMediaActions;
  MaskRemovalInputCreator? _maskRemovalInputCreator;
  MotionPhotoGenerator? _motionPhotoGenerator;
  UpscalePhotoGenerator? _upscalePhotoGenerator;
  ImportedEditingResource? _pendingBackgroundResource;
  bool _choosingBackground = false;
  UpscalePhotoScale? _selectedUpscaleScale;
  UpscalePhotoArtifact? _upscaleArtifact;
  MotionPhotoArtifact? _motionArtifact;
  bool _generatingLocalResult = false;
  bool _localGenerationFailed = false;
  GenerationJob? _cloudGenerationJob;
  bool _creatingCloudResult = false;
  bool _refreshingCloudCapabilities = false;
  _CloudCapabilityDiscovery _cloudCapabilityDiscovery =
      _CloudCapabilityDiscovery.notLoaded;
  bool _cloudGenerationFailed = false;
  GenerationRequestReservation? _cloudReconciliation;
  bool _cancellingCloudResult = false;
  bool _savingGeneratedResult = false;
  bool _previewingMotionResult = false;
  String? _savedGeneratedAssetId;
  OldPhotoColorMode? _oldPhotoColorMode;
  StyleDefinition? _confirmedAiRedrawDefinition;
  MaskRemovalGenerationInput? _maskRemovalInput;

  bool get _isLocalStaticTask =>
      widget.task == CreationTask.optimize ||
      widget.task == CreationTask.cleanup;

  bool get _hasActiveCloudGeneration =>
      _cloudGenerationJob?.state == GenerationJobState.queued ||
      _cloudGenerationJob?.state == GenerationJobState.running;

  bool get _hasCloudReconciliationRequired =>
      _cloudReconciliation?.state ==
      GenerationRequestReservationState.reconciliationRequired;

  bool get _interactionLocked =>
      _savingStyle ||
      _applying ||
      _exporting ||
      _sharing ||
      _choosingBackground ||
      _generatingLocalResult ||
      _creatingCloudResult ||
      _refreshingCloudCapabilities ||
      _cancellingCloudResult ||
      _savingGeneratedResult ||
      _previewingMotionResult;

  List<_StyleChoice> get _styles => [..._officialStyles, ?_aiStyle];

  _StyleChoice? get _selectedStyle =>
      _styles.where((style) => style.id == _selectedStyleId).firstOrNull;

  EditRecipe _projectedStyleRecipe(_StyleChoice style) {
    final session = _session;
    final current = session?.editableRecipe ?? EditRecipe.neutral;
    return switch (widget.task) {
      CreationTask.style =>
        widget.intent != CreationIntent.apply || session?.project == null
            ? style.recipe
            : session!.projectCreationStyle(style.recipe),
      CreationTask.optimize => current.copyWith(
        qualityEnhancementRecipe: QualityEnhancementRecipe.safeAutomatic,
      ),
      CreationTask.cleanup => current.copyWith(
        semanticEditingRecipe: current.semanticEditingRecipe.copyWith(
          background: style.recipe.semanticEditingRecipe.background,
          backgroundImagePath:
              style.recipe.semanticEditingRecipe.backgroundImagePath,
          backgroundImageResourceId:
              style.recipe.semanticEditingRecipe.backgroundImageResourceId,
        ),
      ),
      CreationTask.motion => throw StateError(
        'Motion directions do not use static style recipes',
      ),
    };
  }

  bool get _selectedPreviewReady {
    final selected = _selectedStyle;
    if (selected == null) return false;
    final projected = _projectedStyleRecipe(selected);
    return _renderedPreviewRecipe == projected &&
        _failedPreviewRecipe != projected;
  }

  @override
  void initState() {
    super.initState();
    _officialStyles = _stylesForTask(widget.task);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.read<PhotoProjectStore>();
    final importer = context.read<PhotoImporter>();
    _photoSharer = context.read<PhotoSharer>();
    _editingResourceImporter = importer is EditingResourceImporter
        ? importer
        : null;
    _generationCoordinator = context.read<GenerationCoordinator>();
    _generatedMediaActions = context.read<GeneratedMediaActions?>();
    _maskRemovalInputCreator = context.read<MaskRemovalInputCreator>();
    _motionPhotoGenerator = context.read<MotionPhotoGenerator?>();
    _upscalePhotoGenerator = context.read<UpscalePhotoGenerator?>();
    if (identical(store, _store)) return;
    _session?.dispose();
    _store = store;
    _session = PhotoProjectSession(
      importer: importer,
      store: store,
      creationIntent: widget.intent,
      creationTask: widget.task,
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
    final restoredProject = session.project;
    if (restoredProject == null ||
        restoredProject.creationIntent != widget.intent ||
        restoredProject.creationTask != widget.task) {
      return null;
    }
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
    if (project == null ||
        project.creationIntent != widget.intent ||
        project.creationTask != widget.task) {
      return null;
    }
    if (_isSegmentationCleanupCapability(project.creationCapability)) {
      await _prepareCleanupCapability(session, project);
    }
    final resolvedProject = session.project;
    if (resolvedProject == null ||
        resolvedProject.creationIntent != widget.intent ||
        resolvedProject.creationTask != widget.task) {
      return null;
    }
    _restoreSelectedStyle(resolvedProject);
    _styleApplied = resolvedProject.currentStaticStyleResult != null;
    _restoreExportSummary(resolvedProject);
    await _restoreGeneratedResult(resolvedProject);
    return session.project;
  }

  Future<void> _prepareCleanupCapability(
    PhotoProjectSession session,
    PhotoProject project,
  ) async {
    final capabilities = _capabilities;
    if (capabilities == null) return;
    final available = await CleanupCapabilityPreparer(
      analyzer: context.read<PhotoAnalyzer>(),
    ).prepare(session: session, project: project, capabilities: capabilities);
    if (mounted &&
        session.project?.id == project.id &&
        session.project?.creationCapability == project.creationCapability) {
      setState(() => _cleanupSubjectAvailable = available);
    }
  }

  bool _isSegmentationCleanupCapability(CreationCapability? capability) =>
      capability == CreationCapability.cleanupWhite ||
      capability == CreationCapability.cleanupTransparent ||
      capability == CreationCapability.cleanupReplaceBackground;

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

  void _restoreSelectedStyle(PhotoProject project) {
    _selectedStyleId = null;
    _aiStyle = null;
    _confirmedAiRedrawDefinition = null;
    if (widget.task == CreationTask.motion) return;
    final storedId = project.creationStyleId;
    final storedName = project.creationStyleName;
    final storedRecipe = project.creationStyleRecipe;
    final storedDefinition = project.creationStyleDefinition;
    if (project.creationCapability == CreationCapability.styleAiRedraw &&
        storedDefinition?.origin == StyleDefinitionOrigin.aiRedraw) {
      _confirmedAiRedrawDefinition = storedDefinition;
      return;
    }
    if (_isLocalStaticTask) {
      final localChoice = _officialStyles.where(
        (style) => style.id == storedId,
      );
      if (localChoice.isNotEmpty) {
        _selectedStyleId = localChoice.first.id;
        return;
      }
      if (project.creationCapability ==
              CreationCapability.cleanupReplaceBackground &&
          storedRecipe?.semanticEditingRecipe.background ==
              BackgroundTreatment.image &&
          storedRecipe?.semanticEditingRecipe.backgroundImagePath != null &&
          storedRecipe?.semanticEditingRecipe.backgroundImageResourceId !=
              null) {
        final replacement = _replacementBackgroundChoice(
          path: storedRecipe!.semanticEditingRecipe.backgroundImagePath!,
          resourceId:
              storedRecipe.semanticEditingRecipe.backgroundImageResourceId!,
        );
        _aiStyle = replacement;
        _selectedStyleId = replacement.id;
        return;
      }
      _selectedStyleId = _localStyleIdForCapability(project.creationCapability);
      return;
    }
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
        if ((styleDefinition != null && styleDefinition != official.recipe) ||
            storedDefinition != null) {
          _officialStyles = List.of(_officialStyles)
            ..[officialIndex] = official.copyWith(
              recipe: styleDefinition,
              definition: storedDefinition,
            );
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
          label: _restoredStyleLabel(storedId, storedName),
          persistedName: storedName,
          recipe: storedRecipeIsResult
              ? project.sharedStyle.recipe
              : storedRecipe,
          previewFilter: _Filters.cool,
          definition: storedDefinition,
        );
        _selectedStyleId = storedId;
        return;
      }
    }
  }

  StyleDefinition _definitionForStyle(_StyleChoice style) {
    final definition = style.definition;
    if (definition != null) return definition;
    return StyleDefinition(
      styleId: style.id,
      revision: 1,
      origin: StyleDefinitionOrigin.official,
      title: style.label(context),
      summary: context.l10n.styleOfficialDefinitionSummary,
      recipe: style.recipe,
    );
  }

  String? _localStyleIdForCapability(CreationCapability? capability) =>
      switch (capability) {
        CreationCapability.optimizeNatural => 'local-optimize-automatic-v1',
        CreationCapability.cleanupWhite => 'local-cleanup-white-background-v1',
        CreationCapability.cleanupTransparent =>
          'local-cleanup-transparent-background-v1',
        _ => null,
      };

  _StyleChoice _replacementBackgroundChoice({
    required String path,
    required String resourceId,
  }) => _StyleChoice(
    id: 'local-cleanup-replace-background-v1',
    label: (context) => context.l10n.capabilityCleanupReplaceBackground,
    persistedName: 'replace-background',
    recipe: EditRecipe(
      semanticEditingRecipe: SemanticEditingRecipe(
        background: BackgroundTreatment.image,
        backgroundImagePath: path,
        backgroundImageResourceId: resourceId,
      ),
    ),
    previewFilter: _Filters.natural,
  );

  @override
  void dispose() {
    _batchExporter?.cancel();
    unawaited(_activeSharePreparation?.cancel());
    unawaited(_discardPendingBackgroundResource());
    final session = _session;
    final batchCompletion = _batchCompletion;
    final shareCompletion = _shareCompletion;
    final pending = <Future<void>>[
      if (batchCompletion != null)
        batchCompletion.then<void>((_) {}, onError: (_, _) {}),
      if (shareCompletion != null)
        shareCompletion.then<void>((_) {}, onError: (_, _) {}),
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

  Future<void> _selectStyle(
    String styleId, {
    bool autoApply = false,
    VoidCallback? onFailure,
  }) async {
    if (_session?.project?.creationCapability !=
        CreationCapability.styleOfficial) {
      return;
    }
    final style = _styles.firstWhere((candidate) => candidate.id == styleId);
    final persistedStyleName =
        style.persistedName ?? _definitionForStyle(style).title;
    final selectionAlreadyPersisted =
        _selectedStyleId == styleId &&
        _session?.project?.creationStyleName == persistedStyleName &&
        _session?.project?.creationStyleRecipe == style.recipe;
    if (_interactionLocked) {
      return;
    }
    if (selectionAlreadyPersisted) {
      if (autoApply && !_styleApplied) {
        _queueAutoApplyForCurrentSelection();
      }
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
      _pendingAutoApplyGeneration = autoApply
          ? _previewSelectionGeneration
          : null;
    });
    try {
      await _prepareForDirectSelectionChange();
      await _session!.selectCreationStyle(
        styleId: style.id,
        styleName: style.persistedName,
        recipe: style.recipe,
        definition: _definitionForStyle(style),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _selectedStyleId = previousStyleId;
        _renderedPreviewRecipe = null;
        _failedPreviewRecipe = null;
        _previewSelectionGeneration += 1;
        _pendingAutoApplyGeneration = null;
      });
      onFailure?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (mounted) {
        setState(() => _savingStyle = false);
        _maybeAutoApplyCurrentSelection();
      }
    }
  }

  Future<bool> _selectCapability(
    CreationCapability capability, {
    bool autoApplyLocal = false,
  }) async {
    final session = _session;
    final project = session?.project;
    if (!_interactionLocked &&
        _hasCloudReconciliationRequired &&
        _isCloudGenerationCapability(capability)) {
      if (mounted) setState(() {});
      return false;
    }
    if (_interactionLocked ||
        session == null ||
        project == null ||
        capability.task != widget.task) {
      return false;
    }
    if (project.creationCapability == capability) {
      if (autoApplyLocal && !_styleApplied) {
        _queueAutoApplyForCurrentSelection();
      }
      return true;
    }
    var selected = false;
    setState(() => _savingStyle = true);
    try {
      await _prepareForDirectSelectionChange();
      await _discardPendingBackgroundResource();
      await session.selectCreationCapability(capability);
      if (!mounted) return false;
      setState(() {
        _selectedStyleId = _localStyleIdForCapability(capability);
        _aiStyle = null;
        _styleApplied = false;
        _renderedPreviewRecipe = null;
        _failedPreviewRecipe = null;
        _previewSelectionGeneration += 1;
        _pendingAutoApplyGeneration = autoApplyLocal
            ? _previewSelectionGeneration
            : null;
        _cleanupSubjectAvailable = null;
        _selectedUpscaleScale = null;
        _upscaleArtifact = null;
        _motionArtifact = null;
        _localGenerationFailed = false;
        if (_cloudGenerationJob?.capability != capability &&
            !_hasActiveCloudGeneration) {
          _cloudGenerationJob = null;
          _cloudGenerationFailed = false;
        }
        _savedGeneratedAssetId = null;
        _oldPhotoColorMode = null;
        _confirmedAiRedrawDefinition = null;
        _maskRemovalInput = null;
      });
      if (_isSegmentationCleanupCapability(capability)) {
        final selectedProject = session.project;
        if (selectedProject != null) {
          await _prepareCleanupCapability(session, selectedProject);
        }
      }
      final selectedProject = session.project;
      if (selectedProject != null) {
        await _restoreGeneratedResult(selectedProject);
        if (mounted) setState(() {});
      }
      selected = true;
    } on Object {
      if (!mounted) return false;
      _pendingAutoApplyGeneration = null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (mounted) {
        setState(() => _savingStyle = false);
        _maybeAutoApplyCurrentSelection();
      }
    }
    return selected;
  }

  Future<void> _prepareForDirectSelectionChange() async {
    final session = _session;
    final project = session?.project;
    if (session == null || project == null) return;
    if (project.flowState == PhotoProjectFlowState.editing &&
        project.currentStaticStyleResult == null) {
      return;
    }
    await session.resumeCreationStyleSelection();
    await _discardShareFiles();
    if (!mounted) return;
    setState(() {
      _styleApplied = false;
      _exportSummary = null;
      _photoPermissionDenied = false;
    });
  }

  bool _isDirectLocalStaticCapability(CreationCapability capability) =>
      capability == CreationCapability.optimizeNatural ||
      capability == CreationCapability.cleanupWhite ||
      capability == CreationCapability.cleanupTransparent;

  void _queueAutoApplyForCurrentSelection() {
    if (!mounted || _selectedStyle == null) return;
    setState(() => _pendingAutoApplyGeneration = _previewSelectionGeneration);
    _maybeAutoApplyCurrentSelection();
  }

  void _maybeAutoApplyCurrentSelection() {
    final pendingGeneration = _pendingAutoApplyGeneration;
    final project = _session?.project;
    if (pendingGeneration == null ||
        pendingGeneration != _previewSelectionGeneration ||
        project == null ||
        _interactionLocked ||
        !_selectedPreviewReady) {
      return;
    }
    if (_isLocalStaticTask && _capabilities?.platform != EditPlatform.ios) {
      return;
    }
    if (widget.task == CreationTask.cleanup &&
        _cleanupSubjectAvailable != true) {
      return;
    }
    _pendingAutoApplyGeneration = null;
    unawaited(_applyStyle(project));
  }

  Future<void> _activateOfficialStyle(String styleId) async {
    if (_interactionLocked || widget.task != CreationTask.style) return;
    final capabilitySelected = await _selectCapability(
      CreationCapability.styleOfficial,
    );
    if (!mounted || !capabilitySelected) return;
    await _selectStyle(styleId, autoApply: true);
  }

  Future<void> _activateIllustrationStyle() async {
    if (_interactionLocked || widget.task != CreationTask.style) return;
    if (_hasActiveCloudGeneration || _hasCloudReconciliationRequired) {
      if (mounted) setState(() {});
      return;
    }
    final capabilitySelected = await _selectCapability(
      CreationCapability.styleAiRedraw,
    );
    if (!mounted || !capabilitySelected) return;
    final definition = StyleDefinition.aiRedraw(
      confirmedVisualIntent: context.l10n.styleIllustrationIntent,
      title: context.l10n.styleIllustration,
      summary: context.l10n.aiRedrawDefinitionSummary,
    );
    setState(() => _savingStyle = true);
    try {
      await _session!.selectCreationStyle(
        styleId: definition.styleId,
        styleName: definition.title,
        recipe: definition.recipe,
        definition: definition,
      );
      if (!mounted ||
          _session?.project?.creationCapability !=
              CreationCapability.styleAiRedraw) {
        return;
      }
      setState(() {
        _confirmedAiRedrawDefinition = definition;
        _cloudGenerationJob = null;
        _cloudGenerationFailed = false;
        _savedGeneratedAssetId = null;
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
      return;
    } finally {
      if (mounted) setState(() => _savingStyle = false);
    }
    final project = _session?.project;
    if (mounted && project != null) await _startCloudGeneration(project);
  }

  Future<void> _activateCapability(CreationCapability capability) async {
    if (_interactionLocked) return;
    if (_isCloudGenerationCapability(capability) &&
        (_hasActiveCloudGeneration || _hasCloudReconciliationRequired)) {
      if (mounted) setState(() {});
      return;
    }
    final selected = await _selectCapability(
      capability,
      autoApplyLocal: _isDirectLocalStaticCapability(capability),
    );
    if (!mounted || !selected) return;
    final project = _session?.project;
    if (project == null || project.creationCapability != capability) return;
    switch (capability) {
      case CreationCapability.optimizeNatural ||
          CreationCapability.cleanupWhite ||
          CreationCapability.cleanupTransparent:
        _maybeAutoApplyCurrentSelection();
      case CreationCapability.optimizeUpscale:
        setState(() {
          _selectedUpscaleScale = UpscalePhotoScale.twoX;
          _upscaleArtifact = null;
          _localGenerationFailed = false;
          _savedGeneratedAssetId = null;
        });
        await _generateUpscale(project);
      case CreationCapability.optimizeAiRepair ||
          CreationCapability.motionAiNatural:
        await _startCloudGeneration(project);
      case CreationCapability.optimizeOldPhoto:
        setState(() => _oldPhotoColorMode = OldPhotoColorMode.preserve);
        await _startCloudGeneration(project);
      case CreationCapability.cleanupReplaceBackground:
        await _chooseReplacementBackground();
        if (mounted && _pendingBackgroundResource != null) {
          _queueAutoApplyForCurrentSelection();
        }
      case CreationCapability.cleanupRemovePasserby ||
          CreationCapability.cleanupBrushRemove:
        await _chooseRemovalMask(project);
        if (mounted && _maskRemovalInput != null) {
          await _startCloudGeneration(_session!.project!);
        }
      case CreationCapability.motionSubtle ||
          CreationCapability.motionCameraPush ||
          CreationCapability.motionLightFlow:
        await _generateMotion(project);
      case CreationCapability.styleText ||
          CreationCapability.styleVoice ||
          CreationCapability.styleReference ||
          CreationCapability.styleOfficial ||
          CreationCapability.styleAiRedraw:
        return;
    }
  }

  Future<bool> _refreshCloudCapabilities() async {
    final coordinator = _generationCoordinator;
    if (coordinator == null) return false;
    if (mounted) {
      setState(() {
        _refreshingCloudCapabilities = true;
        _cloudCapabilityDiscovery = _CloudCapabilityDiscovery.loading;
      });
    }
    try {
      await coordinator.refreshCapabilities();
      if (mounted) {
        setState(() {
          _cloudCapabilityDiscovery = _CloudCapabilityDiscovery.loaded;
        });
      }
      return true;
    } on Object {
      if (mounted) {
        setState(() {
          _cloudCapabilityDiscovery = _CloudCapabilityDiscovery.failed;
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _refreshingCloudCapabilities = false);
    }
  }

  GenerationRequestIdentity _generationIdentity(
    PhotoProject project,
    CreationCapability capability, {
    String? inputIdentity,
  }) {
    final photo = project.photos.single;
    return GenerationRequestIdentity(
      projectId: project.id,
      sourcePhotoId: photo.id,
      sourceSha256: photo.contentSha256,
      capability: capability,
      inputIdentity: inputIdentity,
    );
  }

  GenerationSourceSnapshot _generationSnapshot(
    PhotoProject project,
    CreationCapability capability, {
    GenerationInput? input,
  }) {
    final photo = project.photos.single;
    return GenerationSourceSnapshot(
      projectId: project.id,
      sourcePhotoId: photo.id,
      sourcePath: photo.localPath,
      sourceSha256: photo.contentSha256,
      capability: capability,
      createdAt: DateTime.now().toUtc(),
      input: input,
    );
  }

  String _upscaleInputIdentity(UpscalePhotoScale scale) =>
      'local-upscale-v1:${scale.factor}';

  String _motionInputIdentity(MotionPhotoEffect effect) =>
      'local-motion-v1:${effect.id}';

  Future<bool> _verifiedGeneratedFile(GeneratedMedia media) async {
    final file = File(media.localPath);
    if (!await file.exists()) return false;
    final actualSha = ContentSha256.ofBytes(await file.readAsBytes());
    return actualSha == media.contentSha256;
  }

  Future<void> _discardGeneratedFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on Object {
      // An unregistered failed artifact is never surfaced as a saved result.
    }
  }

  Future<void> _restoreGeneratedResult(PhotoProject project) async {
    final coordinator = _generationCoordinator;
    final capability = project.creationCapability;
    if (coordinator == null ||
        capability == null ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(project.photos.single.contentSha256)) {
      return;
    }
    _cloudReconciliation = await coordinator.findReconciliationRequired();
    if (capability == CreationCapability.optimizeUpscale) {
      GenerationJob? latest;
      UpscalePhotoScale? latestScale;
      for (final scale in UpscalePhotoScale.values) {
        final candidate = await coordinator.findLatestForIdentity(
          _generationIdentity(
            project,
            capability,
            inputIdentity: _upscaleInputIdentity(scale),
          ),
          states: const {GenerationJobState.succeeded},
        );
        if (candidate != null &&
            (latest == null || candidate.updatedAt.isAfter(latest.updatedAt))) {
          latest = candidate;
          latestScale = scale;
        }
      }
      final output = latest?.output;
      if (output != null &&
          latestScale != null &&
          output.kind == GeneratedMediaKind.image &&
          await _verifiedGeneratedFile(output)) {
        _selectedUpscaleScale = latestScale;
        _upscaleArtifact = UpscalePhotoArtifact(
          outputPath: output.localPath,
          contentSha256: output.contentSha256,
          scale: latestScale,
          width: output.width,
          height: output.height,
        );
        _savedGeneratedAssetId = output.savedAssetId;
      }
      return;
    }
    final effect = switch (capability) {
      CreationCapability.motionSubtle => MotionPhotoEffect.subtle,
      CreationCapability.motionCameraPush => MotionPhotoEffect.cameraPush,
      CreationCapability.motionLightFlow => MotionPhotoEffect.lightFlow,
      _ => null,
    };
    if (effect != null) {
      final latest = await coordinator.findLatestForIdentity(
        _generationIdentity(
          project,
          capability,
          inputIdentity: _motionInputIdentity(effect),
        ),
        states: const {GenerationJobState.succeeded},
      );
      final output = latest?.output;
      if (output != null &&
          output.kind == GeneratedMediaKind.imageMotion &&
          await _verifiedGeneratedFile(output)) {
        _motionArtifact = MotionPhotoArtifact(
          outputPath: output.localPath,
          contentSha256: output.contentSha256,
          effect: effect,
          width: output.width,
          height: output.height,
          duration: output.duration!,
        );
        _savedGeneratedAssetId = output.savedAssetId;
      }
      return;
    }
    if (!_isCloudGenerationCapability(capability)) return;
    final restoredInput = _generationInputFor(capability);
    if (capability == CreationCapability.styleAiRedraw &&
        restoredInput is! StyleRedrawGenerationInput) {
      return;
    }
    final latest = await coordinator.findLatestForIdentity(
      _generationIdentity(
        project,
        capability,
        inputIdentity: restoredInput?.identity,
      ),
      includeAnyInput: capability != CreationCapability.styleAiRedraw,
    );
    final output = latest?.output;
    if (output != null && !await _verifiedGeneratedFile(output)) return;
    _cloudGenerationJob = latest;
    _savedGeneratedAssetId = output?.savedAssetId;
    if (capability == CreationCapability.optimizeOldPhoto) {
      _oldPhotoColorMode = switch (latest?.inputIdentity) {
        'old-photo-v1:preserve' => OldPhotoColorMode.preserve,
        'old-photo-v1:colorize' => OldPhotoColorMode.colorize,
        _ => null,
      };
    }
    if (latest != null &&
        (latest.state == GenerationJobState.queued ||
            latest.state == GenerationJobState.running)) {
      unawaited(_observeCloudGeneration(latest));
    }
  }

  GeneratedMedia? _generatedMediaForCurrentCapability() {
    final capability = _session?.project?.creationCapability;
    final cloud = _cloudGenerationJob?.output;
    if (cloud != null &&
        _cloudGenerationJob?.capability == capability &&
        _cloudGenerationJob?.state == GenerationJobState.succeeded) {
      return cloud;
    }
    final upscale = _upscaleArtifact;
    if (capability == CreationCapability.optimizeUpscale && upscale != null) {
      return GeneratedMedia(
        id: 'local-upscale-${upscale.contentSha256.substring(0, 20)}',
        kind: GeneratedMediaKind.image,
        localPath: upscale.outputPath,
        contentSha256: upscale.contentSha256,
        width: upscale.width,
        height: upscale.height,
      );
    }
    final motion = _motionArtifact;
    if (motion != null &&
        (capability == CreationCapability.motionSubtle ||
            capability == CreationCapability.motionCameraPush ||
            capability == CreationCapability.motionLightFlow)) {
      return GeneratedMedia(
        id: 'local-motion-${motion.contentSha256.substring(0, 20)}',
        kind: GeneratedMediaKind.imageMotion,
        localPath: motion.outputPath,
        contentSha256: motion.contentSha256,
        width: motion.width,
        height: motion.height,
        duration: motion.duration,
      );
    }
    return null;
  }

  Future<void> _generateUpscale(PhotoProject project) async {
    final generator = _upscalePhotoGenerator;
    final scale = _selectedUpscaleScale;
    if (_interactionLocked ||
        generator == null ||
        scale == null ||
        project.creationCapability != CreationCapability.optimizeUpscale) {
      return;
    }
    setState(() {
      _generatingLocalResult = true;
      _localGenerationFailed = false;
      _savedGeneratedAssetId = null;
    });
    try {
      final artifact = await generator.generate(
        sourcePath: project.photos.single.localPath,
        scale: scale,
      );
      final output = GeneratedMedia(
        id: 'local-upscale-${artifact.contentSha256.substring(0, 20)}',
        kind: GeneratedMediaKind.image,
        localPath: artifact.outputPath,
        contentSha256: artifact.contentSha256,
        width: artifact.width,
        height: artifact.height,
      );
      try {
        await _generationCoordinator!.recordLocalSuccess(
          snapshot: _generationSnapshot(
            project,
            CreationCapability.optimizeUpscale,
          ),
          inputIdentity: _upscaleInputIdentity(scale),
          provider: 'ios-core-image',
          model: 'lanczos-v1',
          output: output,
        );
      } on Object {
        await _discardGeneratedFile(artifact.outputPath);
        rethrow;
      }
      if (!mounted ||
          _session?.project?.creationCapability !=
              CreationCapability.optimizeUpscale ||
          _selectedUpscaleScale != scale) {
        return;
      }
      setState(() => _upscaleArtifact = artifact);
    } on Object {
      if (!mounted) return;
      setState(() => _localGenerationFailed = true);
    } finally {
      if (mounted) setState(() => _generatingLocalResult = false);
    }
  }

  Future<void> _shareGeneratedResult(String path) async {
    final sharer = _photoSharer;
    if (_interactionLocked || sharer == null || path.trim().isEmpty) return;
    setState(() => _sharing = true);
    try {
      await sharer.share(localPaths: [path]);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.photoResultShareFailed)),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _saveGeneratedResult(GeneratedMedia media) async {
    final actions = _generatedMediaActions;
    if (_interactionLocked || actions == null) return;
    if (!_explainedPhotoPermission) {
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
              key: const ValueKey('generated-media-save-continue'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.saveToAlbum),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      _explainedPhotoPermission = true;
    }
    setState(() => _savingGeneratedResult = true);
    try {
      final cloudJob = _cloudGenerationJob;
      final assetId = await actions.saveToPhotoLibrary(media);
      if (mounted) {
        setState(() {
          _savedGeneratedAssetId = assetId;
          _photoPermissionDenied = false;
        });
      }
      final jobId = cloudJob?.output?.id == media.id
          ? cloudJob!.id
          : 'local:${media.id}';
      try {
        final updated = await _generationCoordinator?.markOutputSaved(
          jobId: jobId,
          mediaId: media.id,
          assetId: assetId,
        );
        if (mounted && updated != null && cloudJob?.id == updated.id) {
          setState(() => _cloudGenerationJob = updated);
        }
      } on Object {
        // The system photo-library save is already authoritative. A local
        // metadata write failure must not be reported as a failed save.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.savedToSystemPhotos)));
    } on PlatformException catch (error) {
      if (!mounted) return;
      if (error.code == 'photoAccessDenied') {
        setState(() => _photoPermissionDenied = true);
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (mounted) setState(() => _savingGeneratedResult = false);
    }
  }

  Future<void> _previewMotionResult(GeneratedMedia media) async {
    final actions = _generatedMediaActions;
    if (_interactionLocked ||
        actions == null ||
        media.kind != GeneratedMediaKind.imageMotion) {
      return;
    }
    setState(() => _previewingMotionResult = true);
    try {
      await actions.previewMotion(media);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.generationFailed)));
    } finally {
      if (mounted) setState(() => _previewingMotionResult = false);
    }
  }

  Future<void> _generateMotion(PhotoProject project) async {
    final generator = _motionPhotoGenerator;
    final capability = project.creationCapability;
    final effect = switch (capability) {
      CreationCapability.motionSubtle => MotionPhotoEffect.subtle,
      CreationCapability.motionCameraPush => MotionPhotoEffect.cameraPush,
      CreationCapability.motionLightFlow => MotionPhotoEffect.lightFlow,
      _ => null,
    };
    if (_interactionLocked || generator == null || effect == null) return;
    setState(() {
      _generatingLocalResult = true;
      _localGenerationFailed = false;
      _savedGeneratedAssetId = null;
    });
    try {
      final artifact = await generator.generate(
        sourcePath: project.photos.single.localPath,
        effect: effect,
      );
      final output = GeneratedMedia(
        id: 'local-motion-${artifact.contentSha256.substring(0, 20)}',
        kind: GeneratedMediaKind.imageMotion,
        localPath: artifact.outputPath,
        contentSha256: artifact.contentSha256,
        width: artifact.width,
        height: artifact.height,
        duration: artifact.duration,
      );
      try {
        await _generationCoordinator!.recordLocalSuccess(
          snapshot: _generationSnapshot(project, capability!),
          inputIdentity: _motionInputIdentity(effect),
          provider: 'ios-avfoundation',
          model: 'motion-photo-v1',
          output: output,
        );
      } on Object {
        await _discardGeneratedFile(artifact.outputPath);
        rethrow;
      }
      if (!mounted ||
          _session?.project?.creationCapability != capability ||
          artifact.effect != effect) {
        return;
      }
      setState(() => _motionArtifact = artifact);
    } on Object {
      if (!mounted) return;
      setState(() => _localGenerationFailed = true);
    } finally {
      if (mounted) setState(() => _generatingLocalResult = false);
    }
  }

  Future<void> _startCloudGeneration(PhotoProject project) async {
    final coordinator = _generationCoordinator;
    final capability = project.creationCapability;
    if (_interactionLocked ||
        _hasActiveCloudGeneration ||
        _hasCloudReconciliationRequired ||
        coordinator == null ||
        capability == null) {
      return;
    }
    setState(() => _cloudGenerationFailed = false);
    if (!await _refreshCloudCapabilities()) return;
    if (!mounted ||
        _session?.project?.creationCapability != capability ||
        !coordinator.availableCapabilities.contains(capability)) {
      if (mounted) setState(() => _cloudGenerationFailed = true);
      return;
    }
    final input = _generationInputFor(capability);
    if (!_cloudInputReady(capability, input)) return;
    final inputSummary = switch (input) {
      OldPhotoGenerationInput(:final colorMode) =>
        colorMode == OldPhotoColorMode.preserve
            ? context.l10n.oldPhotoPreserveColor
            : context.l10n.oldPhotoColorize,
      StyleRedrawGenerationInput(:final confirmedDefinition) =>
        confirmedDefinition,
      MaskRemovalGenerationInput() => context.l10n.removalAreaReady,
      null => _capabilityChoicesForTask(
        widget.task,
      ).firstWhere((choice) => choice.capability == capability).label(context),
    };
    final offer = coordinator.offerFor(capability);
    if (!offer.requiresConsent) return;
    var uploadConfirmed = false;
    var costConfirmed = false;
    final consent = await showModalBottomSheet<GenerationConsent>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              key: const ValueKey('generation-consent-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.cloudGenerationConsentTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(context.l10n.cloudGenerationConsentDetail),
                const SizedBox(height: 8),
                Text(
                  inputSummary,
                  key: const ValueKey('generation-confirmed-input-summary'),
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const ValueKey('generation-upload-consent'),
                  contentPadding: EdgeInsets.zero,
                  value: uploadConfirmed,
                  onChanged: (value) =>
                      setSheetState(() => uploadConfirmed = value ?? false),
                  title: Text(context.l10n.cloudUploadConsent),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  key: const ValueKey('generation-cost-consent'),
                  contentPadding: EdgeInsets.zero,
                  value: costConfirmed,
                  onChanged: (value) =>
                      setSheetState(() => costConfirmed = value ?? false),
                  title: Text(context.l10n.cloudCostConsent(offer.creditCost)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('generation-confirm-create'),
                  onPressed: !uploadConfirmed || !costConfirmed
                      ? null
                      : () => Navigator.of(sheetContext).pop(
                          GenerationConsent(
                            offerId: offer.id,
                            uploadConfirmed: true,
                            costConfirmed: true,
                            policyVersion: 1,
                            confirmedAt: DateTime.now().toUtc(),
                          ),
                        ),
                  child: Text(context.l10n.confirmAndGenerate),
                ),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(context.l10n.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || consent == null) return;
    setState(() {
      _creatingCloudResult = true;
      _cloudGenerationFailed = false;
      _savedGeneratedAssetId = null;
    });
    try {
      final snapshot = _generationSnapshot(project, capability, input: input);
      final job = await coordinator.createPersisted(
        snapshot: snapshot,
        consent: consent,
        clientRequestIdFactory: () => [
          project.id,
          project.photos.single.id,
          capability.persistedId,
          DateTime.now().toUtc().microsecondsSinceEpoch,
        ].join(':'),
      );
      if (!mounted || _session?.project?.creationCapability != capability) {
        return;
      }
      setState(() {
        _cloudGenerationJob = job;
        _creatingCloudResult = false;
      });
      await _observeCloudGeneration(job);
    } on GenerationReconciliationRequired catch (error) {
      if (mounted) {
        setState(() {
          _cloudReconciliation = error.reservation;
          _cloudGenerationFailed = false;
        });
      }
    } on Object {
      if (mounted) setState(() => _cloudGenerationFailed = true);
    } finally {
      if (mounted) setState(() => _creatingCloudResult = false);
    }
  }

  Future<void> _observeCloudGeneration(GenerationJob initial) async {
    final coordinator = _generationCoordinator;
    if (coordinator == null) return;
    var job = initial;
    if (job.state == GenerationJobState.succeeded ||
        job.state == GenerationJobState.failed ||
        job.state == GenerationJobState.cancelled) {
      if (mounted &&
          _cloudGenerationJob?.id == initial.id &&
          (job.state == GenerationJobState.failed ||
              (job.state == GenerationJobState.succeeded &&
                  job.output == null))) {
        setState(() => _cloudGenerationFailed = true);
      }
      return;
    }
    try {
      await for (final update in coordinator.observe(job.id)) {
        job = update;
        if (!mounted || _cloudGenerationJob?.id != initial.id) {
          return;
        }
        setState(() => _cloudGenerationJob = job);
      }
      if (mounted &&
          _cloudGenerationJob?.id == initial.id &&
          (job.state == GenerationJobState.failed ||
              (job.state == GenerationJobState.succeeded &&
                  job.output == null))) {
        setState(() => _cloudGenerationFailed = true);
      }
    } on Object {
      if (mounted && _cloudGenerationJob?.id == initial.id) {
        setState(() => _cloudGenerationFailed = true);
      }
    }
  }

  Future<void> _retryCloudGenerationObservation(
    CreationCapability capability,
  ) async {
    final coordinator = _generationCoordinator;
    final job = _cloudGenerationJob;
    if (_interactionLocked ||
        coordinator == null ||
        job == null ||
        job.capability != capability ||
        _session?.project?.creationCapability != capability ||
        (job.state != GenerationJobState.queued &&
            job.state != GenerationJobState.running)) {
      return;
    }
    final jobId = job.id;
    setState(() => _cloudGenerationFailed = false);
    if (!await _refreshCloudCapabilities()) {
      if (mounted && _cloudGenerationJob?.id == jobId) {
        setState(() => _cloudGenerationFailed = true);
      }
      return;
    }
    if (!mounted ||
        _session?.project?.creationCapability != capability ||
        _cloudGenerationJob?.id != jobId ||
        !_hasActiveCloudGeneration) {
      return;
    }
    await _observeCloudGeneration(job);
  }

  Future<void> _cancelCloudGeneration() async {
    final coordinator = _generationCoordinator;
    final job = _cloudGenerationJob;
    if (_interactionLocked ||
        coordinator == null ||
        job == null ||
        !job.canCancel ||
        (job.state != GenerationJobState.queued &&
            job.state != GenerationJobState.running)) {
      return;
    }
    setState(() => _cancellingCloudResult = true);
    try {
      // Cancellation is itself an explicit user action. Reconnect only to the
      // same configured first-party gateway so a restored job can still be
      // cancelled after startup authentication or network recovery.
      if (!await _refreshCloudCapabilities()) return;
      if (!mounted || _cloudGenerationJob?.id != job.id) return;
      final cancelled = await coordinator.cancel(job.id);
      if (!mounted || _cloudGenerationJob?.id != job.id) return;
      setState(() {
        _cloudGenerationJob = cancelled;
        _cloudGenerationFailed =
            cancelled.state != GenerationJobState.cancelled;
      });
    } on Object {
      if (mounted) setState(() => _cloudGenerationFailed = true);
    } finally {
      if (mounted) setState(() => _cancellingCloudResult = false);
    }
  }

  Future<void> _refreshSelectedCloudCapability(
    CreationCapability capability,
  ) async {
    final coordinator = _generationCoordinator;
    if (_interactionLocked ||
        coordinator == null ||
        !_isCloudGenerationCapability(capability)) {
      return;
    }
    setState(() => _cloudGenerationFailed = false);
    await _refreshCloudCapabilities();
  }

  Future<void> _reconcileCloudGeneration() async {
    final coordinator = _generationCoordinator;
    final pending = _cloudReconciliation;
    if (_interactionLocked || coordinator == null || pending == null) return;
    if (!await _refreshCloudCapabilities()) return;
    if (!mounted ||
        _cloudReconciliation?.clientRequestId != pending.clientRequestId) {
      return;
    }
    setState(() => _creatingCloudResult = true);
    try {
      final job = await coordinator.reconcile(pending);
      if (!mounted ||
          _cloudReconciliation?.clientRequestId != pending.clientRequestId) {
        return;
      }
      setState(() {
        _cloudGenerationJob = job;
        _cloudReconciliation = job.requiresReconciliation ? pending : null;
        _cloudGenerationFailed =
            job.state == GenerationJobState.failed &&
            !job.requiresReconciliation;
      });
      if (job.state == GenerationJobState.queued ||
          job.state == GenerationJobState.running) {
        await _observeCloudGeneration(job);
      }
    } on GenerationReconciliationNotFound {
      if (mounted) {
        setState(() {
          _cloudReconciliation = null;
          _cloudGenerationFailed = true;
        });
      }
    } on Object {
      // Keep the pending identity and paid-task lock. A failed status query is
      // not evidence that the original request can be submitted again.
    } finally {
      if (mounted) setState(() => _creatingCloudResult = false);
    }
  }

  GenerationInput? _generationInputFor(CreationCapability capability) =>
      switch (capability) {
        CreationCapability.optimizeOldPhoto =>
          _oldPhotoColorMode == null
              ? null
              : OldPhotoGenerationInput(colorMode: _oldPhotoColorMode!),
        CreationCapability.styleAiRedraw =>
          switch (_confirmedAiRedrawDefinition) {
            final definition?
                when definition.origin == StyleDefinitionOrigin.aiRedraw =>
              StyleRedrawGenerationInput(
                confirmedDefinition: definition.visualIntent,
                definitionFingerprint: definition.contentFingerprint,
              ),
            _ => null,
          },
        CreationCapability.cleanupRemovePasserby ||
        CreationCapability.cleanupBrushRemove => _maskRemovalInput,
        _ => null,
      };

  bool _cloudInputReady(
    CreationCapability capability,
    GenerationInput? input,
  ) => switch (capability) {
    CreationCapability.optimizeAiRepair ||
    CreationCapability.motionAiNatural => input == null,
    CreationCapability.optimizeOldPhoto => input is OldPhotoGenerationInput,
    CreationCapability.styleAiRedraw => input is StyleRedrawGenerationInput,
    CreationCapability.cleanupRemovePasserby ||
    CreationCapability.cleanupBrushRemove =>
      input is MaskRemovalGenerationInput,
    _ => false,
  };

  Future<void> _chooseRemovalMask(PhotoProject project) async {
    final capability = project.creationCapability;
    final creator = _maskRemovalInputCreator;
    if (_interactionLocked ||
        creator == null ||
        (capability != CreationCapability.cleanupRemovePasserby &&
            capability != CreationCapability.cleanupBrushRemove)) {
      return;
    }
    final photo = project.photos.single;
    ({int width, int height}) dimensions;
    try {
      dimensions = await _photoPixelDimensions(photo);
    } on Object {
      if (mounted) setState(() => _cloudGenerationFailed = true);
      return;
    }
    if (!mounted || _session?.project?.creationCapability != capability) return;
    final input = await showModalBottomSheet<MaskRemovalGenerationInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.9,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: MaskRemovalInputEditor(
            sourcePath: photo.localPath,
            sourcePixelWidth: dimensions.width,
            sourcePixelHeight: dimensions.height,
            inputCreator: creator,
            onConfirmed: (confirmed) =>
                Navigator.of(sheetContext).pop(confirmed),
          ),
        ),
      ),
    );
    if (!mounted ||
        input == null ||
        _session?.project?.creationCapability != capability) {
      return;
    }
    setState(() {
      _maskRemovalInput = input;
      _cloudGenerationJob = null;
      _cloudGenerationFailed = false;
      _savedGeneratedAssetId = null;
    });
  }

  Future<({int width, int height})> _photoPixelDimensions(
    ProjectPhoto photo,
  ) async {
    if (photo.pixelWidth > 0 && photo.pixelHeight > 0) {
      final swapsAxes =
          photo.orientation == 5 ||
          photo.orientation == 6 ||
          photo.orientation == 7 ||
          photo.orientation == 8;
      return _boundedMaskDimensions(
        width: swapsAxes ? photo.pixelHeight : photo.pixelWidth,
        height: swapsAxes ? photo.pixelWidth : photo.pixelHeight,
      );
    }
    final bytes = await File(photo.localPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        return _boundedMaskDimensions(
          width: frame.image.width,
          height: frame.image.height,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  ({int width, int height}) _boundedMaskDimensions({
    required int width,
    required int height,
  }) {
    const maximumEdge = 4096;
    final longest = max(width, height);
    if (longest <= maximumEdge) return (width: width, height: height);
    final scale = maximumEdge / longest;
    return (
      width: max(1, (width * scale).round()),
      height: max(1, (height * scale).round()),
    );
  }

  bool _hasRuntimeImplementation(CreationCapability capability) =>
      switch (capability) {
        CreationCapability.optimizeNatural ||
        CreationCapability.styleOfficial ||
        CreationCapability.styleText ||
        CreationCapability.styleVoice ||
        CreationCapability.styleReference ||
        CreationCapability.cleanupWhite ||
        CreationCapability.cleanupTransparent ||
        CreationCapability.cleanupReplaceBackground => true,
        CreationCapability.optimizeUpscale => _upscalePhotoGenerator != null,
        CreationCapability.motionSubtle ||
        CreationCapability.motionCameraPush ||
        CreationCapability.motionLightFlow => _motionPhotoGenerator != null,
        CreationCapability.optimizeAiRepair ||
        CreationCapability.optimizeOldPhoto ||
        CreationCapability.styleAiRedraw ||
        CreationCapability.cleanupRemovePasserby ||
        CreationCapability.cleanupBrushRemove ||
        CreationCapability.motionAiNatural =>
          _generationCoordinator?.availableCapabilities.contains(capability) ??
              false,
      };

  Future<void> _chooseReplacementBackground() async {
    final project = _session?.project;
    if (_interactionLocked ||
        project?.creationCapability !=
            CreationCapability.cleanupReplaceBackground ||
        _cleanupSubjectAvailable != true) {
      return;
    }
    final importer = _editingResourceImporter;
    if (importer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backgroundImageImportFailed)),
      );
      return;
    }
    setState(() => _choosingBackground = true);
    ImportedEditingResource? selected;
    try {
      selected = await importer.importEditingResource(
        EditingResourceKind.backgroundImage,
      );
      if (selected == null) return;
      if (selected.descriptor.kind != EditingResourceKind.backgroundImage) {
        throw StateError('The selected resource is not a background image');
      }
      if (!mounted ||
          _session?.project?.creationCapability !=
              CreationCapability.cleanupReplaceBackground) {
        await importer.discardEditingResource(selected);
        return;
      }
      final previous = _pendingBackgroundResource;
      final choice = _replacementBackgroundChoice(
        path: selected.localPath,
        resourceId: selected.descriptor.id,
      );
      setState(() {
        _pendingBackgroundResource = selected;
        _aiStyle = choice;
        _selectedStyleId = choice.id;
        _styleApplied = false;
        _renderedPreviewRecipe = null;
        _failedPreviewRecipe = null;
        _previewSelectionGeneration += 1;
      });
      if (previous != null &&
          previous.descriptor.id != selected.descriptor.id) {
        await importer.discardEditingResource(previous);
      }
    } on Object {
      if (selected != null &&
          _pendingBackgroundResource?.descriptor.id != selected.descriptor.id) {
        try {
          await importer.discardEditingResource(selected);
        } on Object {
          // The app-owned resource store also removes unreferenced leftovers.
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.backgroundImageImportFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _choosingBackground = false);
    }
  }

  Future<void> _discardPendingBackgroundResource() async {
    final resource = _pendingBackgroundResource;
    _pendingBackgroundResource = null;
    final importer = _editingResourceImporter;
    if (resource == null || importer == null) return;
    try {
      await importer.discardEditingResource(resource);
    } on Object {
      // Cleanup is best effort; unregistered resources are never rendered as
      // an applied project result.
    }
  }

  EditContext _editContext(PhotoProject project) {
    final capabilities = _capabilities!;
    final pendingResource = _pendingBackgroundResource;
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
      resourceIds: {
        ...project.editingResources.resources.keys,
        if (pendingResource != null) pendingResource.descriptor.id,
      },
      resourceByteLengths: {
        for (final resource in project.editingResources.resources.values)
          resource.id: resource.byteLength,
        if (pendingResource != null)
          pendingResource.descriptor.id: pendingResource.descriptor.byteLength,
      },
      metaOpCapabilities: capabilities,
    );
  }

  Future<void> _applyStyle(PhotoProject project) async {
    if (_interactionLocked || !_selectedPreviewReady) return;
    if (widget.task == CreationTask.cleanup &&
        _cleanupSubjectAvailable != true) {
      return;
    }
    final style = _selectedStyle;
    if (style == null) return;
    final localResultName = switch (project.creationCapability) {
      CreationCapability.optimizeNatural => context.l10n.optimizeResult,
      CreationCapability.cleanupWhite => context.l10n.capabilityCleanupWhite,
      CreationCapability.cleanupTransparent =>
        context.l10n.capabilityCleanupTransparent,
      CreationCapability.cleanupReplaceBackground =>
        context.l10n.capabilityCleanupReplaceBackground,
      _ => context.l10n.cleanupResult,
    };
    setState(() => _applying = true);
    try {
      final commit = switch (widget.task) {
        CreationTask.style => await _session!.applyCreationStyle(
          styleId: style.id,
          styleName: style.persistedName,
          recipe: style.recipe,
          context: _editContext(project),
        ),
        CreationTask.optimize ||
        CreationTask.cleanup => await _session!.applyLocalStaticTaskResult(
          task: widget.task,
          resultId: style.id,
          resultName: localResultName,
          desiredRecipe: _projectedStyleRecipe(style),
          context: _editContext(project),
          resourceImporter:
              project.creationCapability ==
                  CreationCapability.cleanupReplaceBackground
              ? _editingResourceImporter
              : null,
        ),
        CreationTask.motion => throw StateError(
          'Motion is unavailable without a generation service.',
        ),
      };
      if (!mounted) return;
      final accepted = commit.result is AcceptedEdit;
      final alreadyApplied =
          _session!.project!.currentStaticStyleResult != null;
      if (!accepted && !alreadyApplied) {
        throw StateError('The style was not admitted by the editing core');
      }
      final updatedProject = _session!.project!;
      final pendingResource = _pendingBackgroundResource;
      setState(() {
        if (pendingResource != null &&
            updatedProject.editingResources.resources.containsKey(
              pendingResource.descriptor.id,
            )) {
          _pendingBackgroundResource = null;
        }
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
      final selected = _selectedStyle;
      if (!mounted ||
          selected == null ||
          selectionGeneration != _previewSelectionGeneration ||
          _projectedStyleRecipe(selected) != recipe) {
        return;
      }
      setState(() {
        _renderedPreviewRecipe = recipe;
        if (_failedPreviewRecipe == recipe) _failedPreviewRecipe = null;
      });
      _maybeAutoApplyCurrentSelection();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _onPreviewFailed(EditRecipe recipe, int selectionGeneration) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selected = _selectedStyle;
      if (!mounted ||
          selected == null ||
          selectionGeneration != _previewSelectionGeneration ||
          _projectedStyleRecipe(selected) != recipe) {
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
    final resultIdentity = _session?.project?.currentStaticStyleResult;
    if (resultIdentity == null) return;
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
        options: _photoExportOptions(resultIdentity),
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
        options: _photoExportOptions(resultIdentity),
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

  PhotoExportOptions _photoExportOptions(
    StaticStyleResultIdentity resultIdentity,
  ) => resultIdentity.capability == CreationCapability.cleanupTransparent
      ? PhotoExportOptions(format: PhotoExportFormat.png)
      : PhotoExportOptions.defaults;

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

  Widget _buildPhotoCanvas(
    BuildContext context, {
    required PhotoProject project,
    required ProjectPhoto photo,
    required String previewPath,
    required bool generatedImageVisible,
  }) {
    if (generatedImageVisible) {
      return Image.file(
        File(previewPath),
        key: const ValueKey('style-workspace-generated-image'),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Center(
          child: Text(
            context.l10n.photoLoadFailed,
            style: const TextStyle(color: AppTheme.softWhite),
          ),
        ),
      );
    }

    final selected = _selectedStyle;
    final recipe = selected == null
        ? project.effectiveRecipeFor(photo.id)
        : _projectedStyleRecipe(selected);
    final selectionGeneration = _previewSelectionGeneration;
    return NativePhotoPreview(
      key: ValueKey('style-workspace-preview-${photo.id}'),
      sourcePath: photo.localPath,
      sourceId: photo.id,
      recipe: recipe,
      renderer: context.read<PhotoPreviewRenderer>(),
      editState: project.renderStateFor(photo.id, recipe: recipe),
      editContext: _editContext(project),
      retryToken: _previewRetryToken,
      allowLegacyColorFallback: false,
      preserveLastFrameOnUpdateFailure: true,
      onRendered: selected == null
          ? null
          : (rendered) => _onPreviewRendered(rendered, selectionGeneration),
      onRenderFailed: selected == null
          ? null
          : (failed) => _onPreviewFailed(failed, selectionGeneration),
      errorBuilder: (_) => Image.file(
        File(photo.localPath),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Center(
          child: Text(
            context.l10n.photoLoadFailed,
            style: const TextStyle(color: AppTheme.softWhite),
          ),
        ),
      ),
    );
  }

  Widget? _buildWorkspaceStatus(
    BuildContext context, {
    required PhotoProject project,
    required CreationCapability? selectedCapability,
    required bool showUnavailable,
    required String unavailableTitle,
    required String cloudFailureMessage,
  }) {
    String? message;
    VoidCallback? action;
    String? actionLabel;
    Key? actionKey;
    Key? key;

    if (_hasCloudReconciliationRequired) {
      message = context.l10n.cloudReconciliationRequired;
      action = _interactionLocked ? null : _reconcileCloudGeneration;
      actionLabel = context.l10n.checkCloudGenerationStatus;
      actionKey = ValueKey('${widget.task.name}-cloud-reconciliation-check');
      key = ValueKey('${widget.task.name}-cloud-reconciliation-required');
    } else if (_hasActiveCloudGeneration) {
      message = _cloudGenerationFailed
          ? cloudFailureMessage
          : _cloudGenerationJob?.state == GenerationJobState.queued
          ? context.l10n.cloudGenerationQueued
          : context.l10n.cloudGenerationRunning;
      if (_cloudGenerationFailed && selectedCapability != null) {
        action = _interactionLocked
            ? null
            : () => unawaited(
                _retryCloudGenerationObservation(selectedCapability),
              );
        actionLabel = context.l10n.retry;
        actionKey = ValueKey('${widget.task.name}-cloud-result-refresh');
      } else if (_cloudGenerationJob?.canCancel == true) {
        action = _interactionLocked ? null : _cancelCloudGeneration;
        actionLabel = context.l10n.cancelGeneration;
        actionKey = ValueKey('${widget.task.name}-cloud-result-cancel');
      }
      key = ValueKey('${widget.task.name}-cloud-result-progress');
    } else if (_creatingCloudResult || _refreshingCloudCapabilities) {
      message = context.l10n.generatingResult;
      key = ValueKey('${widget.task.name}-cloud-result-progress');
    } else if (_generatingLocalResult) {
      message = context.l10n.generatingResult;
      key = ValueKey('${widget.task.name}-local-result-progress');
    } else if (_cloudGenerationFailed) {
      message = cloudFailureMessage;
      if (selectedCapability != null &&
          _isCloudGenerationCapability(selectedCapability)) {
        action = _interactionLocked
            ? null
            : () => unawaited(_startCloudGeneration(project));
        actionLabel = context.l10n.retry;
        actionKey = ValueKey('${widget.task.name}-cloud-result-retry');
      }
      key = ValueKey('${widget.task.name}-cloud-result-failed');
    } else if (_localGenerationFailed) {
      message = context.l10n.generationFailed;
      action = _interactionLocked || selectedCapability == null
          ? null
          : () => unawaited(_activateCapability(selectedCapability));
      actionLabel = context.l10n.retry;
      actionKey = ValueKey('${widget.task.name}-local-result-retry');
      key = ValueKey('${widget.task.name}-local-result-failed');
    } else if (_failedPreviewRecipe != null) {
      message = context.l10n.effectPreviewUnavailable;
      action = _interactionLocked ? null : _retryPreview;
      actionLabel = context.l10n.retry;
      actionKey = ValueKey('${widget.task.name}-preview-retry');
      key = ValueKey('${widget.task.name}-preview-failed');
    } else if (showUnavailable) {
      message = unavailableTitle;
      if (selectedCapability != null &&
          _isCloudGenerationCapability(selectedCapability)) {
        action = _interactionLocked
            ? null
            : () => unawaited(
                _refreshSelectedCloudCapability(selectedCapability),
              );
        actionLabel = context.l10n.retry;
        actionKey = ValueKey('${widget.task.name}-cloud-capability-refresh');
      }
      key = ValueKey('${widget.task.name}-capability-unavailable-state');
    }

    if (message == null) return null;
    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.paddingOf(context).top + 58,
      child: Align(
        alignment: Alignment.topCenter,
        child: _WorkspaceStatusPill(
          key: key,
          message: message,
          actionLabel: actionLabel,
          actionKey: actionKey,
          onAction: action,
        ),
      ),
    );
  }

  Widget _buildCompactResultActions(
    BuildContext context, {
    required PhotoProject project,
    required GeneratedMedia? generatedMedia,
  }) {
    final staticResultReady =
        _styleApplied && project.currentStaticStyleResult != null;
    if (!staticResultReady && generatedMedia == null) {
      return const SizedBox.shrink();
    }

    if (generatedMedia case final media?) {
      final isCloudResult = _cloudGenerationJob?.output?.id == media.id;
      final saveKey = isCloudResult
          ? ValueKey('${widget.task.name}-cloud-result-save')
          : widget.task == CreationTask.motion
          ? const ValueKey('motion-generated-result-save')
          : const ValueKey('optimize-generated-result-save');
      final shareKey = isCloudResult
          ? ValueKey('${widget.task.name}-cloud-result-share')
          : widget.task == CreationTask.motion
          ? const ValueKey('motion-generated-result-share')
          : const ValueKey('optimize-generated-result-share');
      final playKey = isCloudResult
          ? ValueKey('${widget.task.name}-cloud-result-play')
          : const ValueKey('motion-generated-result-play');
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          key: ValueKey('${widget.task.name}-result-actions'),
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (media.kind == GeneratedMediaKind.imageMotion)
              OutlinedButton.icon(
                key: playKey,
                onPressed: _interactionLocked || _generatedMediaActions == null
                    ? null
                    : () => _previewMotionResult(media),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(context.l10n.previewMotionResult),
              ),
            FilledButton.icon(
              key: saveKey,
              onPressed: _interactionLocked || _generatedMediaActions == null
                  ? null
                  : () => _saveGeneratedResult(media),
              icon: Icon(
                _savedGeneratedAssetId == null
                    ? Icons.save_alt_rounded
                    : Icons.check_rounded,
              ),
              label: Text(
                _savedGeneratedAssetId == null
                    ? context.l10n.saveToAlbum
                    : context.l10n.savedToSystemPhotos,
              ),
            ),
            OutlinedButton.icon(
              key: shareKey,
              onPressed: _interactionLocked
                  ? null
                  : () => _shareGeneratedResult(media.localPath),
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(context.l10n.shareResult),
            ),
          ],
        ),
      );
    }

    final summary = _exportSummary;
    final saved = summary?.savedCount == 1 && summary?.failedCount == 0;
    final failed = summary != null && !saved;
    final canShare =
        _capabilities?.platform == EditPlatform.ios &&
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
        : context.l10n.styleApplied;
    return Semantics(
      key: const ValueKey('style-result-status'),
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: status,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          key: const ValueKey('style-static-result-controls'),
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
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
            else if (saved)
              Chip(
                key: const ValueKey('style-result-saved-state'),
                avatar: const Icon(Icons.check_rounded, size: 18),
                label: Text(context.l10n.savedToSystemPhotos),
              )
            else if (_photoPermissionDenied)
              FilledButton.icon(
                key: const ValueKey('style-result-open-settings'),
                onPressed: _interactionLocked ? null : _openPhotoSettings,
                icon: const Icon(Icons.settings_outlined),
                label: Text(context.l10n.goToSystemSettings),
              )
            else
              FilledButton.icon(
                key: failed
                    ? const ValueKey('style-result-retry')
                    : const ValueKey('style-result-save'),
                onPressed: _interactionLocked
                    ? null
                    : failed
                    ? () => _exportStyleResult(project.photos.single.id)
                    : _saveStyleResult,
                icon: _exporting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt_rounded),
                label: Text(
                  failed ? context.l10n.retry : context.l10n.saveToAlbum,
                ),
              ),
            if (canShare)
              if (saved)
                FilledButton.icon(
                  key: const ValueKey('style-result-share'),
                  onPressed: _interactionLocked ? null : _shareStyleResult,
                  icon: _sharing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_rounded),
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
                      : const Icon(Icons.ios_share_rounded),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageKey = widget.intent == CreationIntent.apply
        ? const ValueKey('apply-style-workspace')
        : const ValueKey('motion-style-workspace');
    return PopScope(
      canPop: !_interactionLocked,
      child: Scaffold(
        key: pageKey,
        backgroundColor: AppTheme.canvas,
        body: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<PhotoProject?>(
              future: _project,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const ColoredBox(
                    color: AppTheme.canvas,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final project = snapshot.data;
                if (snapshot.hasError ||
                    project == null ||
                    project.creationIntent != widget.intent ||
                    project.creationTask != widget.task) {
                  return _WorkspaceFailure(
                    onRetry: _retryRestore,
                    onBack: () => Navigator.of(context).maybePop(),
                  );
                }
                return _buildWorkspace(context, _session?.project ?? project);
              },
            ),
            _FloatingWorkspaceNavigation(
              title: switch (widget.task) {
                CreationTask.style => context.l10n.homeChangeStyle,
                CreationTask.motion => context.l10n.createMotionEffect,
                CreationTask.optimize => context.l10n.optimizePhoto,
                CreationTask.cleanup => context.l10n.removeBackgroundOrObjects,
              },
              enabled: !_interactionLocked,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context, PhotoProject project) =>
      _buildCapabilityWorkspace(context, project);

  Widget _buildCapabilityWorkspace(BuildContext context, PhotoProject project) {
    final photo = project.photos.single;
    final selectedCapability = project.creationCapability;
    final choices = widget.task == CreationTask.style
        ? const <_CapabilityChoice>[]
        : _capabilityChoicesForTask(widget.task);
    final showOfficialStyles = widget.task == CreationTask.style;
    final cloudJobIsActive = _hasActiveCloudGeneration;
    final generatedMedia = _generatedMediaForCurrentCapability();
    final motionMedia = generatedMedia?.kind == GeneratedMediaKind.imageMotion
        ? generatedMedia
        : null;
    final generatedImage = generatedMedia?.kind == GeneratedMediaKind.image
        ? generatedMedia
        : null;
    final previewPath = generatedImage?.localPath ?? photo.localPath;
    final staticResult = project.currentStaticStyleResult;
    final staticResultName = staticResult == null
        ? null
        : switch (widget.task) {
            CreationTask.style =>
              staticResult.styleName ?? _selectedStyle?.label(context),
            CreationTask.optimize => context.l10n.optimizeResult,
            CreationTask.cleanup => context.l10n.cleanupResult,
            CreationTask.motion => null,
          };
    final staticResultStatus = staticResult == null
        ? null
        : switch (widget.task) {
            CreationTask.style => context.l10n.styleApplied,
            CreationTask.optimize => context.l10n.optimizeApplied,
            CreationTask.cleanup => context.l10n.cleanupApplied,
            CreationTask.motion => null,
          };
    final photoSemanticsLabel = [
      context.l10n.photoPreviewArea,
      ?staticResultName,
      ?staticResultStatus,
    ].join(', ');
    final showUnavailable =
        selectedCapability != null &&
        !_hasRuntimeImplementation(selectedCapability) &&
        !_hasCloudReconciliationRequired &&
        generatedMedia == null;
    late final String unavailableTitle;
    if (selectedCapability != null &&
        _isCloudGenerationCapability(selectedCapability)) {
      unavailableTitle = switch (_cloudCapabilityDiscovery) {
        _CloudCapabilityDiscovery.notLoaded =>
          context.l10n.cloudCapabilitiesNotLoaded,
        _CloudCapabilityDiscovery.loading =>
          context.l10n.cloudCapabilitiesLoading,
        _CloudCapabilityDiscovery.failed =>
          context.l10n.cloudCapabilitiesConnectionFailed,
        _CloudCapabilityDiscovery.loaded =>
          context.l10n.cloudCapabilityUnavailable,
      };
    } else {
      unavailableTitle = context.l10n.capabilityUnavailable;
    }
    final cloudFailureMessage = switch (_cloudGenerationJob?.errorCode) {
      'generation_concurrency_exceeded' =>
        context.l10n.generationConcurrencyExceeded,
      'generation_credit_exhausted' => context.l10n.generationCreditExhausted,
      'capability_disabled' ||
      'capability_not_configured' => context.l10n.generationCapabilityDisabled,
      'provider_failed' ||
      'result_import_failed' => context.l10n.generationProviderFailed,
      _
          when cloudJobIsActive &&
              _cloudGenerationJob?.usageDisposition ==
                  GenerationUsageDisposition.hold &&
              _cloudGenerationJob?.cancellationDisposition ==
                  GenerationCancellationDisposition.unavailable =>
        context.l10n.generationCancellationStillRunning,
      _
          when _cloudGenerationJob?.usageDisposition ==
              GenerationUsageDisposition.hold =>
        context.l10n.generationStatusCreditHeld,
      _ => context.l10n.generationFailed,
    };
    final textScaler = MediaQuery.textScalerOf(context);
    final styleRailHeight = 82 + textScaler.scale(16);
    final visibleStyles = <_StyleChoice>[
      ..._officialStyles,
      if (_aiStyle case final restoredStyle?)
        if (!_officialStyles.any((style) => style.id == restoredStyle.id))
          restoredStyle,
    ];
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
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Semantics(
                        key: const ValueKey('style-workspace-source-photo'),
                        image: true,
                        label: photoSemanticsLabel,
                        child: _buildPhotoCanvas(
                          context,
                          project: project,
                          photo: photo,
                          previewPath: previewPath,
                          generatedImageVisible: generatedImage != null,
                        ),
                      ),
                      if (motionMedia != null)
                        Center(
                          child: IconButton.filled(
                            key: const ValueKey(
                              'motion-generated-result-preview',
                            ),
                            tooltip: context.l10n.previewMotionResult,
                            iconSize: 42,
                            onPressed:
                                _interactionLocked ||
                                    _generatedMediaActions == null
                                ? null
                                : () => _previewMotionResult(motionMedia),
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                        ),
                      ?_buildWorkspaceStatus(
                        context,
                        project: project,
                        selectedCapability: selectedCapability,
                        showUnavailable: showUnavailable,
                        unavailableTitle: unavailableTitle,
                        cloudFailureMessage: cloudFailureMessage,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 286),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF151719),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(color: Color(0xFF2B2D2F), width: 0.5),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (choices.isNotEmpty)
                        SingleChildScrollView(
                          key: ValueKey('${widget.task.name}-capability-rail'),
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final choice in choices)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _CapabilityOption(
                                    key: ValueKey(
                                      '${widget.task.name}-capability-'
                                      '${choice.keySuffix}',
                                    ),
                                    label: choice.label(context),
                                    selected:
                                        choice.capability == selectedCapability,
                                    onTap: _interactionLocked
                                        ? null
                                        : () => unawaited(
                                            _activateCapability(
                                              choice.capability,
                                            ),
                                          ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (showOfficialStyles) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          height: styleRailHeight,
                          child: ListView.separated(
                            key: const ValueKey('style-options'),
                            scrollDirection: Axis.horizontal,
                            itemCount: visibleStyles.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final style = visibleStyles[index];
                              return _StyleOption(
                                key: ValueKey('style-option-${style.id}'),
                                style: style,
                                sourcePath: photo.localPath,
                                selected: style.id == _illustrationStyleId
                                    ? selectedCapability ==
                                          CreationCapability.styleAiRedraw
                                    : selectedCapability ==
                                              CreationCapability
                                                  .styleOfficial &&
                                          style.id == _selectedStyleId,
                                onTap: _interactionLocked
                                    ? null
                                    : () => unawaited(
                                        style.id == _illustrationStyleId
                                            ? _activateIllustrationStyle()
                                            : _activateOfficialStyle(style.id),
                                      ),
                              );
                            },
                          ),
                        ),
                      ],
                      _buildCompactResultActions(
                        context,
                        project: project,
                        generatedMedia: generatedMedia,
                      ),
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
}

class _FloatingWorkspaceNavigation extends StatelessWidget {
  const _FloatingWorkspaceNavigation({
    required this.title,
    required this.enabled,
    required this.onPressed,
  });

  final String title;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: Colors.black.withValues(alpha: 0.58),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  key: const ValueKey('style-workspace-back'),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: enabled ? onPressed : null,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                ),
              ),
            ),
            IgnorePointer(
              child: Material(
                key: const ValueKey('style-workspace-title'),
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.softWhite,
                      fontWeight: FontWeight.w600,
                    ),
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

class _WorkspaceStatusPill extends StatelessWidget {
  const _WorkspaceStatusPill({
    required this.message,
    required this.actionLabel,
    required this.actionKey,
    required this.onAction,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 7, onAction == null ? 12 : 4, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.softWhite),
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(width: 4),
              TextButton(
                key: actionKey,
                onPressed: onAction,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    ),
  );
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
              key: selected ? const ValueKey('current-style-name') : null,
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

class _CapabilityOption extends StatelessWidget {
  const _CapabilityOption({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    selected: selected,
    label: label,
    child: OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: selected ? AppTheme.gold : AppTheme.softWhite,
        side: BorderSide(
          color: selected ? AppTheme.gold : const Color(0xFF45484C),
        ),
      ),
      icon: selected
          ? const Icon(Icons.check_rounded, size: 18)
          : const SizedBox.shrink(),
      label: Text(label),
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

bool _isCloudGenerationCapability(CreationCapability capability) =>
    switch (capability) {
      CreationCapability.optimizeAiRepair ||
      CreationCapability.optimizeOldPhoto ||
      CreationCapability.styleAiRedraw ||
      CreationCapability.cleanupRemovePasserby ||
      CreationCapability.cleanupBrushRemove ||
      CreationCapability.motionAiNatural => true,
      _ => false,
    };

typedef _StyleLabel = String Function(BuildContext context);

const _illustrationStyleId = 'illustration-v1';

class _CapabilityChoice {
  const _CapabilityChoice({
    required this.capability,
    required this.keySuffix,
    required this.label,
  });

  final CreationCapability capability;
  final String keySuffix;
  final _StyleLabel label;
}

List<_CapabilityChoice> _capabilityChoicesForTask(CreationTask task) =>
    switch (task) {
      CreationTask.optimize => [
        _CapabilityChoice(
          capability: CreationCapability.optimizeNatural,
          keySuffix: 'natural',
          label: (context) => context.l10n.capabilityOptimizeNatural,
        ),
        _CapabilityChoice(
          capability: CreationCapability.optimizeAiRepair,
          keySuffix: 'ai-repair',
          label: (context) => context.l10n.capabilityOptimizeAiRepair,
        ),
        _CapabilityChoice(
          capability: CreationCapability.optimizeUpscale,
          keySuffix: 'upscale',
          label: (context) => context.l10n.capabilityOptimizeUpscale,
        ),
        _CapabilityChoice(
          capability: CreationCapability.optimizeOldPhoto,
          keySuffix: 'old-photo',
          label: (context) => context.l10n.capabilityOptimizeOldPhoto,
        ),
      ],
      CreationTask.style => const [],
      CreationTask.cleanup => [
        _CapabilityChoice(
          capability: CreationCapability.cleanupWhite,
          keySuffix: 'white',
          label: (context) => context.l10n.capabilityCleanupWhite,
        ),
        _CapabilityChoice(
          capability: CreationCapability.cleanupTransparent,
          keySuffix: 'transparent',
          label: (context) => context.l10n.capabilityCleanupTransparent,
        ),
        _CapabilityChoice(
          capability: CreationCapability.cleanupReplaceBackground,
          keySuffix: 'replace-background',
          label: (context) => context.l10n.capabilityCleanupReplaceBackground,
        ),
        _CapabilityChoice(
          capability: CreationCapability.cleanupRemovePasserby,
          keySuffix: 'remove-passerby',
          label: (context) => context.l10n.capabilityCleanupRemovePasserby,
        ),
        _CapabilityChoice(
          capability: CreationCapability.cleanupBrushRemove,
          keySuffix: 'brush-remove',
          label: (context) => context.l10n.capabilityCleanupBrushRemove,
        ),
      ],
      CreationTask.motion => [
        _CapabilityChoice(
          capability: CreationCapability.motionSubtle,
          keySuffix: 'subtle',
          label: (context) => context.l10n.capabilityMotionSubtle,
        ),
        _CapabilityChoice(
          capability: CreationCapability.motionCameraPush,
          keySuffix: 'camera-push',
          label: (context) => context.l10n.capabilityMotionCameraPush,
        ),
        _CapabilityChoice(
          capability: CreationCapability.motionLightFlow,
          keySuffix: 'light-flow',
          label: (context) => context.l10n.capabilityMotionLightFlow,
        ),
        _CapabilityChoice(
          capability: CreationCapability.motionAiNatural,
          keySuffix: 'ai-natural',
          label: (context) => context.l10n.capabilityMotionAiNatural,
        ),
      ],
    };

class _StyleChoice {
  const _StyleChoice({
    required this.id,
    required this.label,
    required this.recipe,
    required this.previewFilter,
    this.persistedName,
    this.definition,
  });

  final String id;
  final _StyleLabel label;
  final String? persistedName;
  final EditRecipe recipe;
  final ColorFilter previewFilter;
  final StyleDefinition? definition;

  _StyleChoice copyWith({EditRecipe? recipe, StyleDefinition? definition}) =>
      _StyleChoice(
        id: id,
        label: label,
        persistedName: persistedName,
        recipe: recipe ?? this.recipe,
        previewFilter: previewFilter,
        definition: definition ?? this.definition,
      );
}

String _compactStyleName(String name) =>
    name.length > 10 ? '${name.substring(0, 10)}…' : name;

_StyleLabel _restoredStyleLabel(String styleId, String? storedName) {
  if (storedName != null) return (_) => _compactStyleName(storedName);
  return switch (styleId) {
    'natural' => (context) => context.l10n.styleNatural,
    'soft-light' => (context) => context.l10n.styleSoftLight,
    'night' => (context) => context.l10n.styleNight,
    'cool' => (context) => context.l10n.styleCool,
    'warm-sun' => (context) => context.l10n.styleWarmSun,
    'mono' => (context) => context.l10n.styleMono,
    'ai-custom' => (context) => context.l10n.styleAiCustom,
    _ => (context) => context.l10n.styleSavedCustom,
  };
}

List<_StyleChoice> _stylesForTask(CreationTask task) => switch (task) {
  CreationTask.optimize => [
    _StyleChoice(
      id: 'local-optimize-automatic-v1',
      label: (context) => context.l10n.optimizeResult,
      recipe: EditRecipe(
        qualityEnhancementRecipe: QualityEnhancementRecipe.safeAutomatic,
      ),
      previewFilter: _Filters.natural,
    ),
  ],
  CreationTask.cleanup => [
    _StyleChoice(
      id: 'local-cleanup-white-background-v1',
      label: (context) => context.l10n.capabilityCleanupWhite,
      recipe: EditRecipe(
        semanticEditingRecipe: SemanticEditingRecipe(
          background: BackgroundTreatment.white,
        ),
      ),
      previewFilter: _Filters.natural,
    ),
    _StyleChoice(
      id: 'local-cleanup-transparent-background-v1',
      label: (context) => context.l10n.capabilityCleanupTransparent,
      recipe: EditRecipe(
        semanticEditingRecipe: SemanticEditingRecipe(
          background: BackgroundTreatment.transparent,
        ),
      ),
      previewFilter: _Filters.natural,
    ),
  ],
  CreationTask.style => _stylesFor(task.creationIntent),
  CreationTask.motion => const <_StyleChoice>[],
};

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
      'japanese-v1',
      (c) => c.l10n.styleJapanese,
      PhotoFilter.faded,
      34,
      _Filters.japanese,
      exposure: 0.04,
      saturation: -0.04,
    ),
    choice(
      'film-v1',
      (c) => c.l10n.styleFilm,
      PhotoFilter.film,
      58,
      _Filters.film,
      warmth: 0.02,
      contrast: 0.03,
    ),
    choice(
      _illustrationStyleId,
      (c) => c.l10n.styleIllustration,
      PhotoFilter.vivid,
      44,
      _Filters.illustration,
      saturation: 0.08,
      contrast: 0.04,
    ),
    choice(
      'cinematic-v1',
      (c) => c.l10n.styleCinematic,
      PhotoFilter.cinematic,
      56,
      _Filters.cinema,
      saturation: -0.05,
      contrast: 0.08,
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
  static const japanese = ColorFilter.matrix(<double>[
    1.04,
    0.02,
    0,
    0,
    6,
    0.01,
    1.03,
    0.01,
    0,
    5,
    0.01,
    0.02,
    0.96,
    0,
    4,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const film = ColorFilter.matrix(<double>[
    1.06,
    0.03,
    0.01,
    0,
    2,
    0.02,
    1.0,
    0.02,
    0,
    1,
    0.02,
    0.03,
    0.9,
    0,
    -2,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const illustration = ColorFilter.matrix(<double>[
    1.14,
    -0.02,
    -0.02,
    0,
    1,
    -0.03,
    1.12,
    -0.03,
    0,
    1,
    -0.02,
    -0.02,
    1.14,
    0,
    1,
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
