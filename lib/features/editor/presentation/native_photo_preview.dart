import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/domain/photo_color_transform.dart';

class NativePhotoPreview extends StatefulWidget {
  const NativePhotoPreview({
    required this.sourcePath,
    required this.recipe,
    required this.renderer,
    required this.errorBuilder,
    super.key,
  });

  final String sourcePath;
  final EditRecipe recipe;
  final PhotoPreviewRenderer renderer;
  final WidgetBuilder errorBuilder;

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
        if (_handle == null) unawaited(_create());
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_suspendPreview());
    }
  }

  Future<void> _suspendPreview() async {
    if (_suspended) return;
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
        !identical(oldWidget.renderer, widget.renderer)) {
      unawaited(_replacePreview());
      return;
    }
    if (!oldWidget.recipe.crop.hasSameOutputDimensions(widget.recipe.crop)) {
      unawaited(_replacePreview());
      return;
    }
    if (oldWidget.recipe != widget.recipe && !_useFallback) {
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
    try {
      final handle = await widget.renderer.create(
        sourcePath: widget.sourcePath,
        pipeline: imagePipelineForCurrentPlatform(initialRecipe),
      );
      if (!mounted || generation != _generation) {
        await _safeDispose(handle);
        return;
      }
      setState(() => _handle = handle);
      if (widget.recipe != initialRecipe) {
        _pendingRecipe = widget.recipe;
        unawaited(_drainUpdates());
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _useFallback = true);
      }
    }
  }

  Future<void> _drainUpdates() async {
    if (_updateInFlight) {
      return;
    }
    final handle = _handle;
    if (handle == null) {
      return;
    }
    _updateInFlight = true;
    try {
      while (mounted &&
          identical(_handle, handle) &&
          _pendingRecipe != null &&
          !_useFallback) {
        final recipe = _pendingRecipe!;
        _pendingRecipe = null;
        await widget.renderer.update(
          handle: handle,
          pipeline: imagePipelineForCurrentPlatform(recipe),
        );
      }
    } on Object {
      if (mounted && identical(_handle, handle)) {
        setState(() => _useFallback = true);
      }
    } finally {
      _updateInFlight = false;
      if (_pendingRecipe != null &&
          _handle != null &&
          mounted &&
          !_useFallback) {
        unawaited(_drainUpdates());
      }
    }
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
      if (!widget.recipe.isLegacyColorOnly) {
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
