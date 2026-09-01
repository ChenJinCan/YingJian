import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/generation/application/mask_removal_input_builder.dart';
import 'package:yingjian/features/generation/domain/generation_input.dart';
import 'package:yingjian/l10n/l10n.dart';

/// Collects a mask drawn directly by the user. It never analyzes the source
/// image and never creates, expands, or recommends a selection.
final class MaskRemovalInputEditor extends StatefulWidget {
  const MaskRemovalInputEditor({
    required this.sourcePath,
    required this.sourcePixelWidth,
    required this.sourcePixelHeight,
    required this.inputCreator,
    required this.onConfirmed,
    super.key,
  });

  final String sourcePath;
  final int sourcePixelWidth;
  final int sourcePixelHeight;
  final MaskRemovalInputCreator inputCreator;
  final ValueChanged<MaskRemovalGenerationInput> onConfirmed;

  @override
  State<MaskRemovalInputEditor> createState() => _MaskRemovalInputEditorState();
}

final class _MaskRemovalInputEditorState extends State<MaskRemovalInputEditor> {
  final List<List<MaskStroke>> _undoHistory = [];
  List<MaskStroke> _strokes = const [];
  List<NormalizedPoint>? _activePoints;
  MaskBrushOperation _operation = MaskBrushOperation.paint;
  double _radius = 0.035;
  bool _creating = false;
  String? _errorMessage;

  bool get _hasExplicitPaint =>
      _strokes.any((stroke) => stroke.operation == MaskBrushOperation.paint);

  @override
  Widget build(BuildContext context) {
    if (widget.sourcePixelWidth <= 0 || widget.sourcePixelHeight <= 0) {
      return Semantics(
        liveRegion: true,
        child: Text(
          context.l10n.generationFailed,
          key: const ValueKey('mask-removal-invalid-source-size'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    return Column(
      key: const ValueKey('mask-removal-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.maskBrushHint),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<MaskBrushOperation>(
            key: const ValueKey('mask-removal-operation'),
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
            onSelectionChanged: _creating
                ? null
                : (selection) => setState(() => _operation = selection.single),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => _buildCanvas(constraints),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: context.l10n.brushSize,
          value: '${(_radius * 1000).round()}',
          child: Row(
            children: [
              Text(context.l10n.brushSize),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  key: const ValueKey('mask-removal-brush-size'),
                  value: _radius,
                  min: 0.005,
                  max: 0.12,
                  onChanged: _creating
                      ? null
                      : (value) => setState(() => _radius = value),
                ),
              ),
            ],
          ),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            IconButton(
              key: const ValueKey('mask-removal-undo'),
              tooltip: context.l10n.undo,
              onPressed: _creating || _undoHistory.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo),
            ),
            TextButton(
              key: const ValueKey('mask-removal-clear'),
              onPressed: _creating || _strokes.isEmpty ? null : _clear,
              child: Text(context.l10n.clearMask),
            ),
            FilledButton(
              key: const ValueKey('mask-removal-confirm'),
              onPressed: _creating || !_hasExplicitPaint ? null : _confirm,
              child: _creating
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        ),
        if (_errorMessage case final message?) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: const ValueKey('mask-removal-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCanvas(BoxConstraints constraints) {
    final aspectRatio = widget.sourcePixelWidth / widget.sourcePixelHeight;
    var width = constraints.hasBoundedWidth ? constraints.maxWidth : 360.0;
    width = min(width, 480);
    var height = width / aspectRatio;
    if (height > 420) {
      height = 420;
      width = height * aspectRatio;
    }
    final size = Size(width, height);
    return Align(
      alignment: Alignment.center,
      child: SizedBox.fromSize(
        size: size,
        child: Semantics(
          key: const ValueKey('mask-removal-canvas-semantics'),
          container: true,
          excludeSemantics: true,
          label: context.l10n.paintMask,
          hint: context.l10n.maskBrushHint,
          onTap: _creating ? null : () => _addCenterStamp(size),
          child: GestureDetector(
            key: const ValueKey('mask-removal-canvas'),
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTapDown: _creating
                ? null
                : (details) => _startStroke(details.localPosition, size),
            onTapUp: _creating ? null : (_) => _finishStroke(),
            onPanStart: _creating
                ? null
                : (details) => _startStroke(details.localPosition, size),
            onPanUpdate: _creating
                ? null
                : (details) => _continueStroke(details.localPosition, size),
            onPanEnd: _creating ? null : (_) => _finishStroke(),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(widget.sourcePath),
                    key: const ValueKey('mask-removal-source-preview'),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: _MaskRemovalStrokePainter(
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
      ),
    );
  }

  void _startStroke(Offset position, Size size) {
    setState(() {
      _errorMessage = null;
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
    _replace([
      ..._strokes,
      MaskStroke(operation: _operation, radius: _radius, points: points),
    ]);
  }

  void _addCenterStamp(Size size) {
    _startStroke(size.center(Offset.zero), size);
    _finishStroke();
  }

  void _undo() {
    if (_undoHistory.isEmpty) return;
    setState(() {
      _strokes = _undoHistory.removeLast();
      _activePoints = null;
      _errorMessage = null;
    });
  }

  void _clear() => _replace(const []);

  void _replace(List<MaskStroke> next) {
    setState(() {
      _undoHistory.add(List.unmodifiable(_strokes));
      _strokes = List.unmodifiable(next);
      _activePoints = null;
      _errorMessage = null;
    });
  }

  Future<void> _confirm() async {
    setState(() {
      _creating = true;
      _errorMessage = null;
    });
    try {
      final input = await widget.inputCreator.create(
        pixelWidth: widget.sourcePixelWidth,
        pixelHeight: widget.sourcePixelHeight,
        strokes: _strokes,
      );
      if (!mounted) return;
      widget.onConfirmed(input);
    } on EmptyMaskSelectionException {
      if (!mounted) return;
      setState(() => _errorMessage = context.l10n.maskBrushHint);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = context.l10n.generationFailed);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  NormalizedPoint _normalized(Offset position, Size size) =>
      NormalizedPoint.checked(
        (position.dx / size.width).clamp(0, 1),
        (position.dy / size.height).clamp(0, 1),
      );
}

final class _MaskRemovalStrokePainter extends CustomPainter {
  const _MaskRemovalStrokePainter({
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
      _draw(canvas, size, stroke.points, stroke.radius, stroke.operation);
    }
    final active = activePoints;
    if (active != null) {
      _draw(canvas, size, active, activeRadius, activeOperation);
    }
  }

  void _draw(
    Canvas canvas,
    Size size,
    List<NormalizedPoint> points,
    double radius,
    MaskBrushOperation operation,
  ) {
    final offsets = points
        .map((point) => Offset(point.x * size.width, point.y * size.height))
        .toList(growable: false);
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
  bool shouldRepaint(covariant _MaskRemovalStrokePainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.activePoints != activePoints ||
      oldDelegate.activeRadius != activeRadius ||
      oldDelegate.activeOperation != activeOperation;
}
