import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/domain/photo_color_transform.dart';
import 'package:yingjian/features/editor/domain/render_plan.dart';

class NativePhotoPreview extends StatefulWidget {
  const NativePhotoPreview({
    required this.sourcePath,
    required this.recipe,
    required this.renderer,
    required this.errorBuilder,
    this.onRendered,
    this.onRenderFailed,
    this.allowLegacyColorFallback = true,
    this.preserveLastFrameOnUpdateFailure = false,
    this.retryToken = 0,
    this.maxEdge = 2048,
    this.sourceId,
    this.editState,
    this.editContext = EditContext.ios,
    super.key,
  }) : assert(maxEdge > 0 && maxEdge <= 2048);

  final String sourcePath;
  final EditRecipe recipe;
  final PhotoPreviewRenderer renderer;
  final WidgetBuilder errorBuilder;
  final ValueChanged<EditRecipe>? onRendered;
  final ValueChanged<EditRecipe>? onRenderFailed;
  final bool allowLegacyColorFallback;
  final bool preserveLastFrameOnUpdateFailure;
  final int retryToken;
  final int maxEdge;
  final String? sourceId;
  final EditState? editState;
  final EditContext editContext;

  @override
  State<NativePhotoPreview> createState() => _NativePhotoPreviewState();
}

class _NativePhotoPreviewState extends State<NativePhotoPreview>
    with WidgetsBindingObserver {
  PhotoPreviewHandle? _handle;
  EditRecipe? _pendingRecipe;
  bool _updateInFlight = false;
  bool _useFallback = false;
  bool _suspended = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_create());
  }

  @override
  void didHaveMemoryPressure() {
    if (!_suspended) unawaited(_replacePreview());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_suspended) return;
        _suspended = false;
        if (_handle == null) {
          unawaited(_create());
        } else {
          _pendingRecipe = widget.recipe;
          unawaited(_drainUpdates());
        }
        return;
      case AppLifecycleState.inactive:
        return;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _pausePreview();
        return;
      case AppLifecycleState.detached:
        unawaited(_detachPreview());
    }
  }

  void _pausePreview() {
    if (_suspended) return;
    _suspended = true;
    if (_handle == null) {
      _generation += 1;
    }
  }

  Future<void> _detachPreview() async {
    if (_suspended && _handle == null) return;
    _suspended = true;
    _generation += 1;
    final previous = _handle;
    _handle = null;
    _pendingRecipe = null;
    _useFallback = false;
    if (mounted) setState(() {});
    if (previous != null) await _safeDispose(previous);
  }

  @override
  void didUpdateWidget(covariant NativePhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourcePath != widget.sourcePath ||
        oldWidget.sourceId != widget.sourceId ||
        oldWidget.maxEdge != widget.maxEdge ||
        !identical(oldWidget.renderer, widget.renderer)) {
      unawaited(_replacePreview());
      return;
    }
    if (oldWidget.retryToken != widget.retryToken) {
      if (widget.preserveLastFrameOnUpdateFailure &&
          _handle != null &&
          !_useFallback) {
        _pendingRecipe = widget.recipe;
        unawaited(_drainUpdates());
      } else {
        unawaited(_replacePreview());
      }
      return;
    }
    if (!oldWidget.recipe.crop.hasSameOutputDimensions(widget.recipe.crop)) {
      unawaited(_replacePreview());
      return;
    }
    if (oldWidget.recipe != widget.recipe && _useFallback) {
      unawaited(_replacePreview());
      return;
    }
    if (oldWidget.recipe != widget.recipe ||
        oldWidget.editState != widget.editState) {
      _pendingRecipe = widget.recipe;
      unawaited(_drainUpdates());
    }
  }

  Future<void> _replacePreview() async {
    final previous = _handle;
    _handle = null;
    _pendingRecipe = null;
    _useFallback = false;
    _generation += 1;
    if (mounted) {
      setState(() {});
    }
    if (previous != null) {
      await _safeDispose(previous);
    }
    await _create();
  }

  Future<void> _create() async {
    if (_suspended) return;
    final generation = ++_generation;
    final initialRecipe = widget.recipe;
    final onRendered = widget.onRendered;
    final onRenderFailed = widget.onRenderFailed;
    try {
      final handle = await widget.renderer.create(
        sourcePath: widget.sourcePath,
        pipeline: _pipeline(initialRecipe),
        maxEdge: widget.maxEdge,
      );
      if (!mounted || generation != _generation) {
        await _safeDispose(handle);
        return;
      }
      setState(() => _handle = handle);
      onRendered?.call(initialRecipe);
      if (widget.recipe != initialRecipe) {
        _pendingRecipe = widget.recipe;
        unawaited(_drainUpdates());
      }
    } on Object {
      if (mounted && generation == _generation) {
        if (widget.recipe != initialRecipe) {
          _pendingRecipe = null;
          unawaited(_create());
          return;
        }
        setState(() => _useFallback = true);
        onRenderFailed?.call(initialRecipe);
      }
    }
  }

  Future<void> _drainUpdates() async {
    if (_updateInFlight || _suspended) {
      return;
    }
    final handle = _handle;
    if (handle == null) {
      return;
    }
    _updateInFlight = true;
    EditRecipe? failedRecipe;
    ValueChanged<EditRecipe>? failedCallback;
    try {
      while (mounted &&
          identical(_handle, handle) &&
          _pendingRecipe != null &&
          !_suspended &&
          !_useFallback) {
        final recipe = _pendingRecipe!;
        failedRecipe = recipe;
        final onRendered = widget.onRendered;
        failedCallback = widget.onRenderFailed;
        _pendingRecipe = null;
        await widget.renderer.update(
          handle: handle,
          pipeline: _pipeline(recipe),
        );
        if (!mounted ||
            !identical(_handle, handle) ||
            _suspended ||
            _useFallback) {
          return;
        }
        onRendered?.call(recipe);
        failedRecipe = null;
        failedCallback = null;
      }
    } on Object {
      if (mounted && identical(_handle, handle)) {
        if (!widget.preserveLastFrameOnUpdateFailure) {
          setState(() => _useFallback = true);
        }
        if (failedRecipe case final recipe?) {
          failedCallback?.call(recipe);
        }
      }
    } finally {
      _updateInFlight = false;
      if (_pendingRecipe != null &&
          _handle != null &&
          mounted &&
          !_suspended &&
          !_useFallback) {
        unawaited(_drainUpdates());
      }
    }
  }

  ImagePipeline _pipeline(EditRecipe recipe) => imagePipelineForCurrentPlatform(
    recipe,
    sourceId: widget.sourceId ?? widget.sourcePath,
    editState: widget.editState,
    context: _contextFor(recipe),
    outputRequirements: RenderOutputRequirements.preview(
      maxEdge: widget.maxEdge,
    ),
  );

  EditContext _contextFor(EditRecipe recipe) {
    final semantic = recipe.semanticEditingRecipe;
    final resourceId = semantic.backgroundImageResourceId;
    final resourcePath = semantic.backgroundImagePath;
    if (resourceId == null ||
        resourcePath == null ||
        widget.editContext.resourceIds.contains(resourceId)) {
      return widget.editContext;
    }
    final resourceFile = File(resourcePath);
    if (!resourceFile.existsSync()) {
      return widget.editContext;
    }
    return EditContext(
      platform: widget.editContext.platform,
      photoIds: widget.editContext.photoIds,
      targetIds: widget.editContext.targetIds,
      capabilities: widget.editContext.capabilities,
      applicability: widget.editContext.applicability,
      resourceIds: {...widget.editContext.resourceIds, resourceId},
      resourceByteLengths: {
        ...widget.editContext.resourceByteLengths,
        resourceId: resourceFile.lengthSync(),
      },
      metaOpCapabilities: widget.editContext.metaOpCapabilities,
    );
  }

  Future<void> _safeDispose(PhotoPreviewHandle handle) async {
    try {
      await widget.renderer.dispose(handle);
    } on Object {
      // Disposal is best effort because the platform engine may already be gone.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation += 1;
    final handle = _handle;
    if (handle != null) {
      unawaited(_safeDispose(handle));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle;
    if (_useFallback) {
      if (!widget.allowLegacyColorFallback ||
          !widget.recipe.isLegacyColorOnly) {
        return widget.errorBuilder(context);
      }
      final matrix = PhotoColorTransform.fromRecipe(
        widget.recipe,
      ).flutterMatrix;
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: Image.file(
          File(widget.sourcePath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              widget.errorBuilder(context),
        ),
      );
    }
    if (handle == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: handle.width / handle.height,
        child: Texture(textureId: handle.textureId),
      ),
    );
  }
}
