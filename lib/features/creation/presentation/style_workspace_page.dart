import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/features/creation/application/cleanup_capability_preparer.dart';
import 'package:yingjian/features/creation/application/local_reference_style_analyzer.dart';
import 'package:yingjian/features/creation/application/local_style_definition_factory.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/creation/domain/creation_intent.dart';
import 'package:yingjian/features/creation/domain/creation_task.dart';
import 'package:yingjian/features/creation/domain/style_definition.dart';
import 'package:yingjian/features/creation/presentation/style_definition_input_sheet.dart';
import 'package:yingjian/features/editor/application/batch_photo_exporter.dart';
import 'package:yingjian/features/editor/application/meta_op_capabilities_provider.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/application/speech_transcriber.dart';
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
  final TextEditingController _aiRedrawController = TextEditingController();
  String _aiRedrawDraft = '';
  StyleDefinition? _confirmedAiRedrawDefinition;
  String? _aiRedrawValidationError;
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
      _continuingStyle ||
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
    _aiRedrawDraft = '';
    _confirmedAiRedrawDefinition = null;
    _aiRedrawValidationError = null;
    _aiRedrawController.clear();
    if (widget.task == CreationTask.motion) return;
    final storedId = project.creationStyleId;
    final storedName = project.creationStyleName;
    final storedRecipe = project.creationStyleRecipe;
    final storedDefinition = project.creationStyleDefinition;
    if (project.creationCapability == CreationCapability.styleAiRedraw &&
        storedDefinition?.origin == StyleDefinitionOrigin.aiRedraw) {
      _aiRedrawDraft = storedDefinition!.visualIntent;
      _confirmedAiRedrawDefinition = storedDefinition;
      _aiRedrawController.text = storedDefinition.visualIntent;
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
    _aiRedrawController.dispose();
    _batchExporter?.cancel();
    unawaited(_activeSharePreparation?.cancel());
    unawaited(_discardPendingBackgroundResource());
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
    if (_session?.project?.creationCapability !=
        CreationCapability.styleOfficial) {
      return;
    }
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
    if (_isLocalStaticTask) {
      return;
    }
    try {
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
      });
      onFailure?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (mounted) setState(() => _savingStyle = false);
    }
  }

  Future<void> _selectCapability(CreationCapability capability) async {
    final session = _session;
    final project = session?.project;
    if (!_interactionLocked &&
        _hasCloudReconciliationRequired &&
        _isCloudGenerationCapability(capability)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.cloudReconciliationRequired)),
      );
      return;
    }
    if (_interactionLocked ||
        _hasActiveCloudGeneration ||
        session == null ||
        project == null ||
        capability.task != widget.task ||
        project.creationCapability == capability) {
      return;
    }
    setState(() => _savingStyle = true);
    try {
      await _discardPendingBackgroundResource();
      await session.selectCreationCapability(capability);
      if (!mounted) return;
      setState(() {
        _selectedStyleId = _localStyleIdForCapability(capability);
        _aiStyle = null;
        _styleApplied = false;
        _renderedPreviewRecipe = null;
        _failedPreviewRecipe = null;
        _previewSelectionGeneration += 1;
        _cleanupSubjectAvailable = null;
        _selectedUpscaleScale = null;
        _upscaleArtifact = null;
        _motionArtifact = null;
        _localGenerationFailed = false;
        _cloudGenerationJob = null;
        _cloudGenerationFailed = false;
        _savedGeneratedAssetId = null;
        _oldPhotoColorMode = null;
        _aiRedrawDraft = '';
        _confirmedAiRedrawDefinition = null;
        _aiRedrawValidationError = null;
        _aiRedrawController.clear();
        _maskRemovalInput = null;
      });
      if (_isCloudGenerationCapability(capability)) {
        await _refreshCloudCapabilities();
      }
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
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (mounted) setState(() => _savingStyle = false);
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
      unawaited(_observeCloudGeneration(latest, capability));
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
      null =>
        _capabilityChoicesForTask(widget.task)
            .firstWhere((choice) => choice.capability == capability)
            .description(context),
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
      await _observeCloudGeneration(job, capability);
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

  Future<void> _observeCloudGeneration(
    GenerationJob initial,
    CreationCapability capability,
  ) async {
    final coordinator = _generationCoordinator;
    if (coordinator == null) return;
    var job = initial;
    if (job.state == GenerationJobState.succeeded ||
        job.state == GenerationJobState.failed ||
        job.state == GenerationJobState.cancelled) {
      if (mounted &&
          _session?.project?.creationCapability == capability &&
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
        if (!mounted ||
            _session?.project?.creationCapability != capability ||
            _cloudGenerationJob?.id != initial.id) {
          return;
        }
        setState(() => _cloudGenerationJob = job);
      }
      if (mounted &&
          _session?.project?.creationCapability == capability &&
          _cloudGenerationJob?.id == initial.id &&
          (job.state == GenerationJobState.failed ||
              (job.state == GenerationJobState.succeeded &&
                  job.output == null))) {
        setState(() => _cloudGenerationFailed = true);
      }
    } on Object {
      if (mounted &&
          _session?.project?.creationCapability == capability &&
          _cloudGenerationJob?.id == initial.id) {
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
    await _observeCloudGeneration(job, capability);
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
        await _observeCloudGeneration(job, job.capability);
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

  void _updateAiRedrawDraft(String value) {
    setState(() {
      _aiRedrawDraft = value;
      _confirmedAiRedrawDefinition = null;
      _aiRedrawValidationError = null;
      _cloudGenerationJob = null;
      _cloudGenerationFailed = false;
      _savedGeneratedAssetId = null;
    });
  }

  Future<void> _confirmAiRedrawDefinition() async {
    final session = _session;
    if (_interactionLocked ||
        session?.project?.creationCapability !=
            CreationCapability.styleAiRedraw) {
      return;
    }
    late final StyleDefinition definition;
    try {
      definition = StyleDefinition.aiRedraw(
        confirmedVisualIntent: _aiRedrawDraft,
        title: context.l10n.capabilityStyleAiRedraw,
        summary: context.l10n.aiRedrawDefinitionSummary,
      );
    } on ArgumentError {
      setState(
        () => _aiRedrawValidationError = context.l10n.aiRedrawIntentInvalid,
      );
      return;
    }

    setState(() => _savingStyle = true);
    try {
      await session!.selectCreationStyle(
        styleId: definition.styleId,
        styleName: definition.title,
        recipe: definition.recipe,
        definition: definition,
      );
      if (!mounted ||
          session.project?.creationCapability !=
              CreationCapability.styleAiRedraw) {
        return;
      }
      _aiRedrawController.value = TextEditingValue(
        text: definition.visualIntent,
        selection: TextSelection.collapsed(
          offset: definition.visualIntent.length,
        ),
      );
      setState(() {
        _aiRedrawDraft = definition.visualIntent;
        _confirmedAiRedrawDefinition = definition;
        _aiRedrawValidationError = null;
        _cloudGenerationJob = null;
        _cloudGenerationFailed = false;
        _savedGeneratedAssetId = null;
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (mounted) setState(() => _savingStyle = false);
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

  bool _isLocalDefinedStyleCapability(CreationCapability? capability) =>
      capability == CreationCapability.styleText ||
      capability == CreationCapability.styleVoice ||
      capability == CreationCapability.styleReference;

  Future<void> _defineLocalStyle(PhotoProject project) async {
    final capability = project.creationCapability;
    if (_interactionLocked || !_isLocalDefinedStyleCapability(capability)) {
      return;
    }
    final mode = switch (capability!) {
      CreationCapability.styleText => StyleDefinitionInputMode.text,
      CreationCapability.styleVoice => StyleDefinitionInputMode.voice,
      CreationCapability.styleReference => StyleDefinitionInputMode.reference,
      _ => throw StateError('Unsupported local style input capability'),
    };
    final definition = await showModalBottomSheet<StyleDefinition>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StyleDefinitionInputSheet(
        sourcePath: project.photos.single.localPath,
        importer: context.read<PhotoImporter>(),
        transcriber: context.read<SpeechTranscriber>(),
        initialMode: mode,
        allowedModes: {mode},
        preparePrompt: _definitionFromPrompt,
        prepareReference: _definitionFromReference,
      ),
    );
    if (!mounted || definition == null) return;
    if (!_definitionMatchesSelectedCapability(definition, capability)) {
      return;
    }
    setState(() => _savingStyle = true);
    try {
      await _session!.selectCreationStyle(
        styleId: definition.styleId,
        styleName: definition.title,
        recipe: definition.recipe,
        definition: definition,
      );
      if (!mounted) return;
      setState(() {
        _aiStyle = _StyleChoice(
          id: definition.styleId,
          label: (_) => _compactStyleName(definition.title),
          persistedName: definition.title,
          recipe: definition.recipe,
          previewFilter: _Filters.natural,
          definition: definition,
        );
        _selectedStyleId = definition.styleId;
        _styleApplied = false;
        _renderedPreviewRecipe = null;
        _failedPreviewRecipe = null;
        _previewSelectionGeneration += 1;
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectSaveFailed)));
    } finally {
      if (mounted) setState(() => _savingStyle = false);
    }
  }

  Future<StyleDefinition?> _definitionFromPrompt(
    String prompt,
    StyleDefinitionOrigin origin,
  ) async {
    if (origin != StyleDefinitionOrigin.text &&
        origin != StyleDefinitionOrigin.voice) {
      return null;
    }
    final recipe = LocalStyleDefinitionFactory.recipeFromPrompt(prompt);
    if (recipe == null) return null;
    return StyleDefinition(
      styleId: LocalStyleDefinitionFactory.identifierFor(
        origin: origin,
        stableSeed: prompt,
      ),
      revision: 1,
      origin: origin,
      title: prompt,
      summary: origin == StyleDefinitionOrigin.voice
          ? context.l10n.styleVoiceDefinitionSummary
          : context.l10n.styleTextDefinitionSummary,
      recipe: recipe,
      sourceText: prompt,
    );
  }

  Future<StyleDefinition?> _definitionFromReference(
    ImportedEditingResource reference,
  ) async {
    final l10n = context.l10n;
    final analyzer = context.read<ReferenceStyleAnalyzer>();
    final signals = await analyzer.analyze(reference.localPath);
    final temperature = signals.red - signals.blue;
    final title = temperature > 0.08
        ? l10n.styleReferenceWarmTitle
        : temperature < -0.08
        ? l10n.styleReferenceCoolTitle
        : l10n.styleReferenceNaturalTitle;
    return StyleDefinition(
      styleId: LocalStyleDefinitionFactory.identifierFor(
        origin: StyleDefinitionOrigin.reference,
        stableSeed: reference.descriptor.contentSha256,
      ),
      revision: 1,
      origin: StyleDefinitionOrigin.reference,
      title: title,
      summary: l10n.styleReferenceDefinitionSummary,
      recipe: LocalStyleDefinitionFactory.recipeFromReference(signals),
      referenceFingerprint: reference.descriptor.contentSha256,
    );
  }

  bool _definitionMatchesSelectedCapability(
    StyleDefinition definition,
    CreationCapability capability,
  ) => switch (capability) {
    CreationCapability.styleText =>
      definition.origin == StyleDefinitionOrigin.text,
    CreationCapability.styleVoice =>
      definition.origin == StyleDefinitionOrigin.voice,
    CreationCapability.styleReference =>
      definition.origin == StyleDefinitionOrigin.reference,
    _ => false,
  };

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

  Future<void> _returnToCapabilityList() async {
    if (_interactionLocked || _hasActiveCloudGeneration) return;
    setState(() => _continuingStyle = true);
    final completion = _performReturnToCapabilityList();
    _continueStyleCompletion = completion;
    try {
      await completion;
      if (!mounted) return;
      setState(() {
        _selectedStyleId = null;
        _aiStyle = null;
        _styleApplied = false;
        _renderedPreviewRecipe = null;
        _failedPreviewRecipe = null;
        _previewSelectionGeneration += 1;
        _cleanupSubjectAvailable = null;
        _exportSummary = null;
        _photoPermissionDenied = false;
        _aiRedrawDraft = '';
        _confirmedAiRedrawDefinition = null;
        _aiRedrawValidationError = null;
        _aiRedrawController.clear();
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
      _restoreSelectedStyle(project);
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

  Future<void> _performReturnToCapabilityList() async {
    await _discardPendingBackgroundResource();
    await _session!.resumeCreationStyleSelection();
    await _session!.clearCreationCapability();
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
          title: Text(switch (widget.task) {
            CreationTask.style => context.l10n.homeChangeStyle,
            CreationTask.motion => context.l10n.createMotionEffect,
            CreationTask.optimize => context.l10n.optimizePhoto,
            CreationTask.cleanup => context.l10n.removeBackgroundOrObjects,
          }),
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
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context, PhotoProject project) {
    final capability = project.creationCapability;
    final selected = _selectedStyle;
    final showingLegacyResult =
        _styleApplied &&
        project.currentStaticStyleResult != null &&
        selected != null;
    if (!showingLegacyResult &&
        (capability == null ||
            !_hasRuntimeImplementation(capability) ||
            capability == CreationCapability.styleOfficial &&
                selected == null)) {
      return _buildCapabilityWorkspace(context, project);
    }
    if (selected == null) {
      return _buildCapabilityWorkspace(context, project);
    }
    final photo = project.photos.first;
    final textScaler = MediaQuery.textScalerOf(context);
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
                      : _isLocalStaticTask
                      ? _buildLocalTaskControls(
                          context,
                          project,
                          selected,
                          previewFailed,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            styleSummary,
                            if (capability ==
                                CreationCapability.styleOfficial) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                height: styleRailHeight,
                                child: ListView.separated(
                                  key: const ValueKey('style-options'),
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _officialStyles.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 10),
                                  itemBuilder: (context, index) {
                                    final style = _officialStyles[index];
                                    return _StyleOption(
                                      key: ValueKey('style-option-${style.id}'),
                                      style: style,
                                      sourcePath: photo.localPath,
                                      selected: style.id == selected.id,
                                      onTap: _interactionLocked
                                          ? null
                                          : () => unawaited(
                                              _selectStyle(style.id),
                                            ),
                                    );
                                  },
                                ),
                              ),
                            ],
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
                              key: const ValueKey('apply-style-primary-action'),
                              onPressed:
                                  _interactionLocked || !_selectedPreviewReady
                                  ? null
                                  : () => _applyStyle(project),
                              child: _applying
                                  ? Text(context.l10n.applyingStyle)
                                  : Text(context.l10n.applyStyle),
                            ),
                            TextButton(
                              key: const ValueKey('style-choose-capability'),
                              onPressed:
                                  _interactionLocked ||
                                      _hasActiveCloudGeneration
                                  ? null
                                  : _returnToCapabilityList,
                              child: Text(context.l10n.chooseAnotherCapability),
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

  Widget _buildCapabilityWorkspace(BuildContext context, PhotoProject project) {
    final photo = project.photos.single;
    final selectedCapability = project.creationCapability;
    final choices = _capabilityChoicesForTask(widget.task);
    final selectedChoice = choices
        .where((choice) => choice.capability == selectedCapability)
        .firstOrNull;
    final showOfficialStyles =
        selectedCapability == CreationCapability.styleOfficial;
    final showLocalStyleInput = _isLocalDefinedStyleCapability(
      selectedCapability,
    );
    final showReplacementPicker =
        selectedCapability == CreationCapability.cleanupReplaceBackground;
    final showUpscale =
        selectedCapability == CreationCapability.optimizeUpscale &&
        _upscalePhotoGenerator != null;
    final showMotion =
        _motionPhotoGenerator != null &&
        (selectedCapability == CreationCapability.motionSubtle ||
            selectedCapability == CreationCapability.motionCameraPush ||
            selectedCapability == CreationCapability.motionLightFlow);
    final cloudCapabilityAvailable =
        selectedCapability != null &&
        _isCloudGenerationCapability(selectedCapability) &&
        (_generationCoordinator?.availableCapabilities.contains(
              selectedCapability,
            ) ??
            false);
    final showCloudGeneration =
        selectedCapability != null &&
        _isCloudGenerationCapability(selectedCapability) &&
        (cloudCapabilityAvailable ||
            _cloudGenerationJob != null ||
            _hasCloudReconciliationRequired);
    final cloudInput = selectedCapability == null
        ? null
        : _generationInputFor(selectedCapability);
    final cloudInputReady =
        selectedCapability != null &&
        _cloudInputReady(selectedCapability, cloudInput);
    final cloudOutput = _cloudGenerationJob?.output;
    final cloudImageOutput = cloudOutput?.kind == GeneratedMediaKind.image
        ? cloudOutput
        : null;
    final cloudJobIsActive = _hasActiveCloudGeneration;
    final cloudRequestLocked =
        cloudJobIsActive || _hasCloudReconciliationRequired;
    final cloudJobSucceeded =
        _cloudGenerationJob?.state == GenerationJobState.succeeded &&
        cloudOutput != null;
    final generatedMedia = _generatedMediaForCurrentCapability();
    final motionMedia = generatedMedia?.kind == GeneratedMediaKind.imageMotion
        ? generatedMedia
        : null;
    final previewPath =
        cloudImageOutput?.localPath ??
        (showUpscale
            ? _upscaleArtifact?.outputPath ?? photo.localPath
            : photo.localPath);
    final showUnavailable =
        selectedCapability != null &&
        !_hasRuntimeImplementation(selectedCapability) &&
        !_hasCloudReconciliationRequired &&
        generatedMedia == null;
    final unavailableTitle =
        selectedCapability != null &&
            _isCloudGenerationCapability(selectedCapability)
        ? switch (_cloudCapabilityDiscovery) {
            _CloudCapabilityDiscovery.notLoaded =>
              context.l10n.cloudCapabilitiesNotLoaded,
            _CloudCapabilityDiscovery.loading =>
              context.l10n.cloudCapabilitiesLoading,
            _CloudCapabilityDiscovery.failed =>
              context.l10n.cloudCapabilitiesConnectionFailed,
            _CloudCapabilityDiscovery.loaded =>
              context.l10n.cloudCapabilityUnavailable,
          }
        : context.l10n.capabilityUnavailable;
    final unavailableDetail =
        selectedCapability != null &&
            _isCloudGenerationCapability(selectedCapability)
        ? switch (_cloudCapabilityDiscovery) {
            _CloudCapabilityDiscovery.notLoaded =>
              context.l10n.cloudCapabilitiesNotLoadedDetail,
            _CloudCapabilityDiscovery.loading =>
              context.l10n.cloudCapabilitiesLoadingDetail,
            _CloudCapabilityDiscovery.failed =>
              context.l10n.cloudCapabilitiesConnectionFailedDetail,
            _CloudCapabilityDiscovery.loaded =>
              context.l10n.cloudCapabilityUnavailableDetail,
          }
        : context.l10n.capabilityUnavailableDetail;
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
                        label: context.l10n.photoPreviewArea,
                        child: Image.file(
                          File(previewPath),
                          key: ValueKey(
                            _upscaleArtifact == null
                                ? 'capability-source-preview'
                                : 'optimize-generated-result-preview',
                          ),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              Center(child: Text(context.l10n.photoLoadFailed)),
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
                      Text(
                        context.l10n.chooseCapabilityTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.chooseCapabilityHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
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
                                  onTap:
                                      _interactionLocked ||
                                          _hasActiveCloudGeneration
                                      ? null
                                      : () => unawaited(
                                          _selectCapability(choice.capability),
                                        ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (selectedChoice != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          selectedChoice.description(context),
                          key: ValueKey(
                            '${widget.task.name}-capability-description',
                          ),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      if (showOfficialStyles) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          height: styleRailHeight,
                          child: ListView.separated(
                            key: const ValueKey('style-options'),
                            scrollDirection: Axis.horizontal,
                            itemCount: _officialStyles.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final style = _officialStyles[index];
                              return _StyleOption(
                                key: ValueKey('style-option-${style.id}'),
                                style: style,
                                sourcePath: photo.localPath,
                                selected: style.id == _selectedStyleId,
                                onTap: _interactionLocked
                                    ? null
                                    : () => unawaited(_selectStyle(style.id)),
                              );
                            },
                          ),
                        ),
                      ],
                      if (showLocalStyleInput) ...[
                        const SizedBox(height: 14),
                        FilledButton(
                          key: const ValueKey('style-define-primary-action'),
                          onPressed: _interactionLocked
                              ? null
                              : () => _defineLocalStyle(project),
                          child: Text(context.l10n.defineStyle),
                        ),
                      ],
                      if (showReplacementPicker) ...[
                        const SizedBox(height: 14),
                        if (_cleanupSubjectAvailable == false) ...[
                          Semantics(
                            key: const ValueKey('cleanup-task-unavailable'),
                            liveRegion: true,
                            child: Text(
                              context.l10n.cleanupSubjectUnavailable,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        FilledButton(
                          key: const ValueKey(
                            'cleanup-choose-background-action',
                          ),
                          onPressed:
                              _interactionLocked ||
                                  _cleanupSubjectAvailable != true
                              ? null
                              : _chooseReplacementBackground,
                          child: Text(
                            _choosingBackground
                                ? context.l10n.importingBackground
                                : context.l10n.chooseReplacementBackground,
                          ),
                        ),
                      ],
                      if (showUpscale) ...[
                        const SizedBox(height: 14),
                        Text(
                          context.l10n.chooseUpscaleScale,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              key: const ValueKey('upscale-scale-2x'),
                              label: const Text('2×'),
                              selected:
                                  _selectedUpscaleScale ==
                                  UpscalePhotoScale.twoX,
                              onSelected: _interactionLocked
                                  ? null
                                  : (_) => setState(() {
                                      _selectedUpscaleScale =
                                          UpscalePhotoScale.twoX;
                                      _upscaleArtifact = null;
                                      _localGenerationFailed = false;
                                      _savedGeneratedAssetId = null;
                                    }),
                            ),
                            ChoiceChip(
                              key: const ValueKey('upscale-scale-4x'),
                              label: const Text('4×'),
                              selected:
                                  _selectedUpscaleScale ==
                                  UpscalePhotoScale.fourX,
                              onSelected: _interactionLocked
                                  ? null
                                  : (_) => setState(() {
                                      _selectedUpscaleScale =
                                          UpscalePhotoScale.fourX;
                                      _upscaleArtifact = null;
                                      _localGenerationFailed = false;
                                      _savedGeneratedAssetId = null;
                                    }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_upscaleArtifact == null)
                          FilledButton(
                            key: const ValueKey(
                              'optimize-upscale-primary-action',
                            ),
                            onPressed:
                                _interactionLocked ||
                                    _selectedUpscaleScale == null
                                ? null
                                : () => _generateUpscale(project),
                            child: Text(
                              _generatingLocalResult
                                  ? context.l10n.generatingResult
                                  : context.l10n.generateUpscale,
                            ),
                          ),
                        if (_upscaleArtifact != null) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            key: const ValueKey(
                              'optimize-generated-result-ready',
                            ),
                            liveRegion: true,
                            child: Text(context.l10n.upscaleReady),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            key: const ValueKey(
                              'optimize-generated-result-save',
                            ),
                            onPressed:
                                _interactionLocked ||
                                    generatedMedia == null ||
                                    _generatedMediaActions == null
                                ? null
                                : () => _saveGeneratedResult(generatedMedia),
                            icon: const Icon(Icons.save_alt_rounded),
                            label: Text(context.l10n.saveToAlbum),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const ValueKey(
                              'optimize-generated-result-share',
                            ),
                            onPressed: _interactionLocked
                                ? null
                                : () => _shareGeneratedResult(
                                    _upscaleArtifact!.outputPath,
                                  ),
                            icon: const Icon(Icons.ios_share_rounded),
                            label: Text(context.l10n.shareResult),
                          ),
                        ],
                        if (_localGenerationFailed) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            key: const ValueKey(
                              'optimize-generated-result-failed',
                            ),
                            liveRegion: true,
                            child: Text(
                              context.l10n.generationFailed,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                      if (showMotion) ...[
                        const SizedBox(height: 14),
                        if (_motionArtifact == null)
                          FilledButton.icon(
                            key: const ValueKey(
                              'motion-generate-primary-action',
                            ),
                            onPressed: _interactionLocked
                                ? null
                                : () => _generateMotion(project),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(
                              _generatingLocalResult
                                  ? context.l10n.generatingResult
                                  : context.l10n.generateMotion,
                            ),
                          ),
                        if (_motionArtifact != null) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            key: const ValueKey(
                              'motion-generated-result-ready',
                            ),
                            liveRegion: true,
                            child: Text(context.l10n.motionReady),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const ValueKey('motion-generated-result-play'),
                            onPressed:
                                _interactionLocked ||
                                    motionMedia == null ||
                                    _generatedMediaActions == null
                                ? null
                                : () => _previewMotionResult(motionMedia),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(context.l10n.previewMotionResult),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            key: const ValueKey('motion-generated-result-save'),
                            onPressed:
                                _interactionLocked ||
                                    motionMedia == null ||
                                    _generatedMediaActions == null
                                ? null
                                : () => _saveGeneratedResult(motionMedia),
                            icon: const Icon(Icons.save_alt_rounded),
                            label: Text(context.l10n.saveToAlbum),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const ValueKey(
                              'motion-generated-result-share',
                            ),
                            onPressed: _interactionLocked
                                ? null
                                : () => _shareGeneratedResult(
                                    _motionArtifact!.outputPath,
                                  ),
                            icon: const Icon(Icons.ios_share_rounded),
                            label: Text(context.l10n.shareResult),
                          ),
                          TextButton(
                            key: const ValueKey(
                              'motion-choose-another-capability',
                            ),
                            onPressed:
                                _interactionLocked || _hasActiveCloudGeneration
                                ? null
                                : _returnToCapabilityList,
                            child: Text(context.l10n.chooseAnotherCapability),
                          ),
                        ],
                        if (_localGenerationFailed) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            key: const ValueKey(
                              'motion-generated-result-failed',
                            ),
                            liveRegion: true,
                            child: Text(
                              context.l10n.generationFailed,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                      if (showCloudGeneration) ...[
                        const SizedBox(height: 14),
                        if (selectedCapability ==
                            CreationCapability.optimizeOldPhoto) ...[
                          Text(
                            context.l10n.chooseOldPhotoColorMode,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                key: const ValueKey('old-photo-mode-preserve'),
                                label: Text(context.l10n.oldPhotoPreserveColor),
                                selected:
                                    _oldPhotoColorMode ==
                                    OldPhotoColorMode.preserve,
                                onSelected:
                                    _interactionLocked || cloudRequestLocked
                                    ? null
                                    : (_) => setState(() {
                                        _oldPhotoColorMode =
                                            OldPhotoColorMode.preserve;
                                        _cloudGenerationJob = null;
                                        _cloudGenerationFailed = false;
                                        _savedGeneratedAssetId = null;
                                      }),
                              ),
                              ChoiceChip(
                                key: const ValueKey('old-photo-mode-colorize'),
                                label: Text(context.l10n.oldPhotoColorize),
                                selected:
                                    _oldPhotoColorMode ==
                                    OldPhotoColorMode.colorize,
                                onSelected:
                                    _interactionLocked || cloudRequestLocked
                                    ? null
                                    : (_) => setState(() {
                                        _oldPhotoColorMode =
                                            OldPhotoColorMode.colorize;
                                        _cloudGenerationJob = null;
                                        _cloudGenerationFailed = false;
                                        _savedGeneratedAssetId = null;
                                      }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (selectedCapability ==
                            CreationCapability.styleAiRedraw) ...[
                          TextField(
                            key: const ValueKey('ai-redraw-style-definition'),
                            controller: _aiRedrawController,
                            minLines: 2,
                            maxLines: 4,
                            maxLength: StyleDefinition.maxAiRedrawIntentLength,
                            enabled: !_interactionLocked && !cloudRequestLocked,
                            decoration: InputDecoration(
                              labelText: context.l10n.aiRedrawDefinitionLabel,
                              hintText: context.l10n.aiRedrawDefinitionHint,
                              error: _aiRedrawValidationError == null
                                  ? null
                                  : Semantics(
                                      key: const ValueKey(
                                        'ai-redraw-intent-error',
                                      ),
                                      liveRegion: true,
                                      child: Text(_aiRedrawValidationError!),
                                    ),
                            ),
                            onChanged: _updateAiRedrawDraft,
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            key: const ValueKey('ai-redraw-confirm-definition'),
                            onPressed:
                                _interactionLocked ||
                                    cloudRequestLocked ||
                                    _aiRedrawDraft.trim().isEmpty ||
                                    _confirmedAiRedrawDefinition != null
                                ? null
                                : _confirmAiRedrawDefinition,
                            child: Text(context.l10n.aiRedrawConfirmIntent),
                          ),
                          if (_confirmedAiRedrawDefinition
                              case final definition?) ...[
                            const SizedBox(height: 10),
                            Card(
                              key: const ValueKey('ai-redraw-intent-preview'),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      context.l10n.aiRedrawIntentPreviewTitle,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      definition.visualIntent,
                                      key: const ValueKey(
                                        'ai-redraw-confirmed-visual-intent',
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      context.l10n.aiRedrawIntentVersion(
                                        definition.revision,
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      context.l10n.aiRedrawIntentConfirmed,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                        ],
                        if (selectedCapability ==
                                CreationCapability.cleanupRemovePasserby ||
                            selectedCapability ==
                                CreationCapability.cleanupBrushRemove) ...[
                          OutlinedButton.icon(
                            key: const ValueKey('cleanup-mask-input-action'),
                            onPressed: _interactionLocked || cloudRequestLocked
                                ? null
                                : () => _chooseRemovalMask(project),
                            icon: const Icon(Icons.brush_outlined),
                            label: Text(
                              _maskRemovalInput == null
                                  ? context.l10n.markRemovalArea
                                  : context.l10n.changeRemovalArea,
                            ),
                          ),
                          if (_maskRemovalInput != null) ...[
                            const SizedBox(height: 8),
                            Semantics(
                              key: const ValueKey('cleanup-mask-input-ready'),
                              liveRegion: true,
                              child: Text(context.l10n.removalAreaReady),
                            ),
                          ],
                          const SizedBox(height: 10),
                        ],
                        if (!cloudRequestLocked && !cloudJobSucceeded)
                          FilledButton.icon(
                            key: ValueKey(
                              '${widget.task.name}-cloud-primary-action',
                            ),
                            onPressed:
                                _interactionLocked ||
                                    !cloudInputReady ||
                                    !cloudCapabilityAvailable
                                ? null
                                : () => _startCloudGeneration(project),
                            icon: const Icon(Icons.auto_fix_high_rounded),
                            label: Text(
                              _creatingCloudResult
                                  ? context.l10n.generatingResult
                                  : context.l10n.confirmCloudGeneration,
                            ),
                          ),
                        if (cloudJobIsActive) ...[
                          Semantics(
                            key: ValueKey(
                              '${widget.task.name}-cloud-result-progress',
                            ),
                            liveRegion: true,
                            child: Text(
                              _cloudGenerationJob?.state ==
                                      GenerationJobState.queued
                                  ? context.l10n.cloudGenerationQueued
                                  : context.l10n.cloudGenerationRunning,
                            ),
                          ),
                          if (_cloudGenerationJob?.canCancel == true) ...[
                            const SizedBox(height: 8),
                            OutlinedButton(
                              key: ValueKey(
                                '${widget.task.name}-cloud-result-cancel',
                              ),
                              onPressed: _interactionLocked
                                  ? null
                                  : _cancelCloudGeneration,
                              child: Text(context.l10n.cancelGeneration),
                            ),
                          ],
                        ],
                        if (_cloudGenerationJob?.state ==
                            GenerationJobState.cancelled) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            key: ValueKey(
                              '${widget.task.name}-cloud-result-cancelled',
                            ),
                            liveRegion: true,
                            child: Text(
                              _cloudGenerationJob?.usageState ==
                                      GenerationUsageState.released
                                  ? context
                                        .l10n
                                        .generationCancelledCreditReleased
                                  : context.l10n.generationCancelled,
                            ),
                          ),
                        ],
                        if (_hasCloudReconciliationRequired) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            key: ValueKey(
                              '${widget.task.name}-cloud-reconciliation-required',
                            ),
                            container: true,
                            liveRegion: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.cloudReconciliationRequired,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context
                                      .l10n
                                      .cloudReconciliationRequiredDetail,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  key: ValueKey(
                                    '${widget.task.name}-cloud-reconciliation-check',
                                  ),
                                  onPressed: _interactionLocked
                                      ? null
                                      : _reconcileCloudGeneration,
                                  child: Text(
                                    context.l10n.checkCloudGenerationStatus,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (cloudJobSucceeded) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            key: ValueKey(
                              '${widget.task.name}-cloud-result-ready',
                            ),
                            liveRegion: true,
                            child: Text(context.l10n.cloudGenerationReady),
                          ),
                          const SizedBox(height: 8),
                          if (cloudOutput.kind ==
                              GeneratedMediaKind.imageMotion) ...[
                            OutlinedButton.icon(
                              key: ValueKey(
                                '${widget.task.name}-cloud-result-play',
                              ),
                              onPressed:
                                  _interactionLocked ||
                                      _generatedMediaActions == null
                                  ? null
                                  : () => _previewMotionResult(cloudOutput),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(context.l10n.previewMotionResult),
                            ),
                            const SizedBox(height: 8),
                          ],
                          FilledButton.icon(
                            key: ValueKey(
                              '${widget.task.name}-cloud-result-save',
                            ),
                            onPressed:
                                _interactionLocked ||
                                    _generatedMediaActions == null
                                ? null
                                : () => _saveGeneratedResult(cloudOutput),
                            icon: const Icon(Icons.save_alt_rounded),
                            label: Text(context.l10n.saveToAlbum),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: ValueKey(
                              '${widget.task.name}-cloud-result-share',
                            ),
                            onPressed: _interactionLocked
                                ? null
                                : () => _shareGeneratedResult(
                                    cloudOutput.localPath,
                                  ),
                            icon: const Icon(Icons.ios_share_rounded),
                            label: Text(context.l10n.shareResult),
                          ),
                        ],
                        if (_cloudGenerationFailed &&
                            !_hasCloudReconciliationRequired) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            key: ValueKey(
                              '${widget.task.name}-cloud-result-failed',
                            ),
                            liveRegion: true,
                            child: Text(
                              cloudFailureMessage,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                          if (cloudJobIsActive) ...[
                            const SizedBox(height: 8),
                            OutlinedButton(
                              key: ValueKey(
                                '${widget.task.name}-cloud-result-refresh',
                              ),
                              onPressed: _interactionLocked
                                  ? null
                                  : () => unawaited(
                                      _retryCloudGenerationObservation(
                                        selectedCapability,
                                      ),
                                    ),
                              child: Text(context.l10n.retry),
                            ),
                          ],
                        ],
                      ],
                      if (generatedMedia != null &&
                          _savedGeneratedAssetId != null) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          key: const ValueKey('generated-media-saved-state'),
                          liveRegion: true,
                          child: Text(context.l10n.savedToSystemPhotos),
                        ),
                      ],
                      if (generatedMedia != null && _photoPermissionDenied) ...[
                        const SizedBox(height: 8),
                        Text(context.l10n.photoPermissionPurpose),
                        TextButton(
                          key: const ValueKey(
                            'generated-media-open-photo-settings',
                          ),
                          onPressed: _interactionLocked
                              ? null
                              : _openPhotoSettings,
                          child: Text(context.l10n.settings),
                        ),
                      ],
                      if (showUnavailable) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          key: ValueKey(
                            '${widget.task.name}-capability-unavailable-state',
                          ),
                          container: true,
                          liveRegion: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                unavailableTitle,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                unavailableDetail,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              if (_isCloudGenerationCapability(
                                selectedCapability,
                              )) ...[
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  key: ValueKey(
                                    '${widget.task.name}-cloud-capability-refresh',
                                  ),
                                  onPressed: _interactionLocked
                                      ? null
                                      : () => _refreshSelectedCloudCapability(
                                          selectedCapability,
                                        ),
                                  child: Text(context.l10n.retry),
                                ),
                              ],
                            ],
                          ),
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

  Widget _buildLocalTaskControls(
    BuildContext context,
    PhotoProject project,
    _StyleChoice selected,
    bool previewFailed,
  ) {
    final isCleanup = widget.task == CreationTask.cleanup;
    final capability = project.creationCapability;
    final iosLocalTask = _capabilities?.platform == EditPlatform.ios;
    final cleanupUnavailable = isCleanup && _cleanupSubjectAvailable != true;
    final taskUnavailable = !iosLocalTask || cleanupUnavailable;
    final actionLabel = switch (capability) {
      CreationCapability.cleanupWhite => context.l10n.applyWhiteBackground,
      CreationCapability.cleanupTransparent =>
        context.l10n.applyTransparentBackground,
      CreationCapability.cleanupReplaceBackground =>
        context.l10n.applyReplacementBackground,
      _ => context.l10n.applyNaturalOptimization,
    };
    final actionKey = isCleanup
        ? const ValueKey('cleanup-primary-action')
        : const ValueKey('optimize-primary-action');
    final taskTitle = isCleanup
        ? context.l10n.removeBackgroundOrObjects
        : context.l10n.optimizePhoto;
    final taskSubtitle = switch (capability) {
      CreationCapability.cleanupWhite =>
        context.l10n.capabilityCleanupWhiteDescription,
      CreationCapability.cleanupTransparent =>
        context.l10n.capabilityCleanupTransparentDescription,
      CreationCapability.cleanupReplaceBackground =>
        context.l10n.capabilityCleanupReplaceBackgroundDescription,
      _ => context.l10n.capabilityOptimizeNaturalDescription,
    };
    return Column(
      key: ValueKey('${widget.task.name}-task-controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(taskTitle, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          taskSubtitle,
          key: ValueKey('${widget.task.name}-capability-description'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        if (!iosLocalTask) ...[
          Semantics(
            key: ValueKey('${widget.task.name}-task-unavailable'),
            liveRegion: true,
            child: Text(
              context.l10n.localStaticTaskIosOnly,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ] else if (cleanupUnavailable) ...[
          Semantics(
            key: const ValueKey('cleanup-task-unavailable'),
            liveRegion: true,
            child: Text(
              context.l10n.cleanupSubjectUnavailable,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (capability == CreationCapability.cleanupReplaceBackground) ...[
          OutlinedButton(
            key: const ValueKey('cleanup-change-background-action'),
            onPressed: _interactionLocked ? null : _chooseReplacementBackground,
            child: Text(context.l10n.chooseAnotherBackground),
          ),
          const SizedBox(height: 8),
        ],
        if (previewFailed) ...[
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.effectPreviewUnavailable,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: ValueKey('${widget.task.name}-preview-retry'),
                  onPressed: _interactionLocked ? null : _retryPreview,
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton(
          key: actionKey,
          onPressed:
              _interactionLocked || !_selectedPreviewReady || taskUnavailable
              ? null
              : () => _applyStyle(project),
          child: Text(_applying ? context.l10n.applyingStyle : actionLabel),
        ),
        TextButton(
          key: ValueKey('${widget.task.name}-choose-capability'),
          onPressed: _interactionLocked || _hasActiveCloudGeneration
              ? null
              : _returnToCapabilityList,
          child: Text(context.l10n.chooseAnotherCapability),
        ),
        if (project.recoverableStaticStyleResult != null &&
            project.currentStaticStyleResult == null) ...[
          const SizedBox(height: 4),
          TextButton(
            key: ValueKey('${widget.task.name}-restore-previous-result'),
            onPressed: _interactionLocked ? null : _restorePreviousResult,
            child: Text(context.l10n.restorePreviousResult),
          ),
        ],
      ],
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
    final taskResultName = switch (widget.task) {
      CreationTask.style => selected.label(context),
      CreationTask.optimize => context.l10n.optimizeResult,
      CreationTask.cleanup => context.l10n.cleanupResult,
      CreationTask.motion => context.l10n.motionUnavailable,
    };
    final staticResultStatus = switch (widget.task) {
      CreationTask.style => context.l10n.styleApplied,
      CreationTask.optimize => context.l10n.optimizeApplied,
      CreationTask.cleanup => context.l10n.cleanupApplied,
      CreationTask.motion => context.l10n.motionUnavailable,
    };
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
        : staticResultStatus;
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
          widget.task == CreationTask.style
              ? context.l10n.currentStyle
              : context.l10n.currentResult,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 2),
        Text(
          taskResultName,
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
            onPressed: _interactionLocked || _hasActiveCloudGeneration
                ? null
                : _returnToCapabilityList,
            child: Text(context.l10n.chooseAnotherCapability),
          ),
        ],
      ],
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

class _CapabilityChoice {
  const _CapabilityChoice({
    required this.capability,
    required this.keySuffix,
    required this.label,
    required this.description,
  });

  final CreationCapability capability;
  final String keySuffix;
  final _StyleLabel label;
  final _StyleLabel description;
}

List<_CapabilityChoice> _capabilityChoicesForTask(CreationTask task) =>
    switch (task) {
      CreationTask.optimize => [
        _CapabilityChoice(
          capability: CreationCapability.optimizeNatural,
          keySuffix: 'natural',
          label: (context) => context.l10n.capabilityOptimizeNatural,
          description: (context) =>
              context.l10n.capabilityOptimizeNaturalDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.optimizeAiRepair,
          keySuffix: 'ai-repair',
          label: (context) => context.l10n.capabilityOptimizeAiRepair,
          description: (context) =>
              context.l10n.capabilityOptimizeAiRepairDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.optimizeUpscale,
          keySuffix: 'upscale',
          label: (context) => context.l10n.capabilityOptimizeUpscale,
          description: (context) =>
              context.l10n.capabilityOptimizeUpscaleDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.optimizeOldPhoto,
          keySuffix: 'old-photo',
          label: (context) => context.l10n.capabilityOptimizeOldPhoto,
          description: (context) =>
              context.l10n.capabilityOptimizeOldPhotoDescription,
        ),
      ],
      CreationTask.style => [
        _CapabilityChoice(
          capability: CreationCapability.styleOfficial,
          keySuffix: 'official',
          label: (context) => context.l10n.capabilityStyleOfficial,
          description: (context) =>
              context.l10n.capabilityStyleOfficialDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.styleText,
          keySuffix: 'text',
          label: (context) => context.l10n.capabilityStyleText,
          description: (context) => context.l10n.capabilityStyleTextDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.styleVoice,
          keySuffix: 'voice',
          label: (context) => context.l10n.capabilityStyleVoice,
          description: (context) =>
              context.l10n.capabilityStyleVoiceDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.styleReference,
          keySuffix: 'reference',
          label: (context) => context.l10n.capabilityStyleReference,
          description: (context) =>
              context.l10n.capabilityStyleReferenceDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.styleAiRedraw,
          keySuffix: 'ai-redraw',
          label: (context) => context.l10n.capabilityStyleAiRedraw,
          description: (context) =>
              context.l10n.capabilityStyleAiRedrawDescription,
        ),
      ],
      CreationTask.cleanup => [
        _CapabilityChoice(
          capability: CreationCapability.cleanupWhite,
          keySuffix: 'white',
          label: (context) => context.l10n.capabilityCleanupWhite,
          description: (context) =>
              context.l10n.capabilityCleanupWhiteDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.cleanupTransparent,
          keySuffix: 'transparent',
          label: (context) => context.l10n.capabilityCleanupTransparent,
          description: (context) =>
              context.l10n.capabilityCleanupTransparentDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.cleanupReplaceBackground,
          keySuffix: 'replace-background',
          label: (context) => context.l10n.capabilityCleanupReplaceBackground,
          description: (context) =>
              context.l10n.capabilityCleanupReplaceBackgroundDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.cleanupRemovePasserby,
          keySuffix: 'remove-passerby',
          label: (context) => context.l10n.capabilityCleanupRemovePasserby,
          description: (context) =>
              context.l10n.capabilityCleanupRemovePasserbyDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.cleanupBrushRemove,
          keySuffix: 'brush-remove',
          label: (context) => context.l10n.capabilityCleanupBrushRemove,
          description: (context) =>
              context.l10n.capabilityCleanupBrushRemoveDescription,
        ),
      ],
      CreationTask.motion => [
        _CapabilityChoice(
          capability: CreationCapability.motionSubtle,
          keySuffix: 'subtle',
          label: (context) => context.l10n.capabilityMotionSubtle,
          description: (context) =>
              context.l10n.capabilityMotionSubtleDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.motionCameraPush,
          keySuffix: 'camera-push',
          label: (context) => context.l10n.capabilityMotionCameraPush,
          description: (context) =>
              context.l10n.capabilityMotionCameraPushDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.motionLightFlow,
          keySuffix: 'light-flow',
          label: (context) => context.l10n.capabilityMotionLightFlow,
          description: (context) =>
              context.l10n.capabilityMotionLightFlowDescription,
        ),
        _CapabilityChoice(
          capability: CreationCapability.motionAiNatural,
          keySuffix: 'ai-natural',
          label: (context) => context.l10n.capabilityMotionAiNatural,
          description: (context) =>
              context.l10n.capabilityMotionAiNaturalDescription,
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
