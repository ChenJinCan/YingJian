import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/visual_track_resolver.dart';
import 'package:yingjian/features/editor/presentation/native_photo_preview.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/l10n/l10n.dart';

enum VisualTrackKind { era, lighting }

class VisualTracksPage extends StatefulWidget {
  const VisualTracksPage({
    required this.photo,
    required this.initialRecipe,
    required this.editorSession,
    required this.previewRenderer,
    required this.faceTargets,
    required this.editStateFor,
    required this.editContext,
    required this.onCommit,
    required this.onUndo,
    super.key,
  });

  final ProjectPhoto photo;
  final EditRecipe initialRecipe;
  final EditorSession editorSession;
  final PhotoPreviewRenderer previewRenderer;
  final List<StableEditTarget> faceTargets;
  final EditState Function(EditRecipe recipe) editStateFor;
  final EditContext editContext;
  final Future<EditRecipe?> Function(EditRecipe recipe) onCommit;
  final Future<EditRecipe?> Function() onUndo;

  @override
  State<VisualTracksPage> createState() => _VisualTracksPageState();
}

class _VisualTracksPageState extends State<VisualTracksPage> {
  late EditRecipe _baseline;
  late EditRecipe _draft;
  VisualTrackKind _kind = VisualTrackKind.era;
  StableEditTarget? _target;
  double _eraPosition = 0;
  double _azimuth = 0;
  int _intensity = 0;
  bool _adjusting = false;
  bool _committing = false;
  bool _failed = false;
  EditRecipe? _pendingCommit;
  EditRecipe? _lastRendered;

  @override
  void initState() {
    super.initState();
    _baseline = widget.initialRecipe;
    _draft = _baseline;
    _target = widget.faceTargets.firstOrNull;
    _restoreLightingValues();
  }

  void _restoreLightingValues() {
    final value = _target == null
        ? null
        : _draft.directionalLightingRecipe.adjustments[_target!.id];
    _azimuth = value?.azimuth ?? 0;
    _intensity = value?.intensity ?? 0;
  }

  void _begin() {
    if (_adjusting || _committing) return;
    _failed = false;
    _adjusting = true;
    widget.editorSession.beginAdjustment();
  }

  void _previewEra(double value) {
    _begin();
    final next = VisualTrackResolver.era(_baseline, value);
    widget.editorSession.preview(next);
    setState(() {
      _eraPosition = value;
      _draft = next;
    });
  }

  void _previewLighting({double? azimuth, int? intensity}) {
    final target = _target;
    if (target == null) return;
    _begin();
    final nextAzimuth = azimuth ?? _azimuth;
    var nextIntensity = intensity ?? _intensity;
    if (azimuth != null && nextIntensity == 0) nextIntensity = 25;
    final next = VisualTrackResolver.lighting(
      _baseline,
      target: target,
      azimuth: nextAzimuth,
      intensity: nextIntensity,
    );
    widget.editorSession.preview(next);
    setState(() {
      _azimuth = nextAzimuth;
      _intensity = nextIntensity;
      _draft = next;
    });
  }

  void _end() {
    if (!_adjusting || _committing) return;
    _adjusting = false;
    widget.editorSession.commitAdjustment();
    if (_draft == _baseline) return;
    setState(() {
      _committing = true;
      _pendingCommit = _draft;
    });
    if (_lastRendered == _pendingCommit) unawaited(_commitRenderedDraft());
  }

  Future<void> _commitRenderedDraft() async {
    final pending = _pendingCommit;
    if (pending == null || !_committing) return;
    _pendingCommit = null;
    final committed = await widget.onCommit(pending);
    if (!mounted) return;
    if (committed == null) {
      _restoreAfterFailure();
      return;
    }
    widget.editorSession.load(committed);
    setState(() {
      _baseline = committed;
      _draft = committed;
      _committing = false;
    });
  }

  void _onRendered(EditRecipe recipe) {
    _lastRendered = recipe;
    if (_pendingCommit == recipe) unawaited(_commitRenderedDraft());
  }

  void _onRenderFailed(EditRecipe recipe) {
    if (recipe != _draft) return;
    _restoreAfterFailure();
  }

  void _restoreAfterFailure() {
    widget.editorSession.load(_baseline);
    setState(() {
      _draft = _baseline;
      _adjusting = false;
      _committing = false;
      _pendingCommit = null;
      _failed = true;
      _eraPosition = 0;
      _restoreLightingValues();
    });
  }

  Future<void> _undo() async {
    if (_adjusting || _committing) return;
    final recipe = await widget.onUndo();
    if (!mounted || recipe == null) return;
    widget.editorSession.load(recipe);
    setState(() {
      _baseline = recipe;
      _draft = recipe;
      _eraPosition = 0;
      _failed = false;
      _restoreLightingValues();
    });
  }

  void _selectKind(VisualTrackKind value) {
    if (_adjusting || _committing || value == _kind) return;
    setState(() {
      _kind = value;
      _failed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      onPopInvokedWithResult: (_, _) {
        if (_adjusting) widget.editorSession.load(_baseline);
      },
      child: Scaffold(
        key: const ValueKey('visual-tracks-page'),
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(context.l10n.visualTracksTitle),
          actions: [
            IconButton(
              key: const ValueKey('visual-tracks-undo'),
              tooltip: context.l10n.undo,
              onPressed: _committing ? null : () => unawaited(_undo()),
              icon: const Icon(Icons.undo_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NativePhotoPreview(
                      key: const ValueKey('visual-tracks-preview'),
                      sourcePath: widget.photo.localPath,
                      sourceId: widget.photo.id,
                      recipe: _draft,
                      editState: widget.editStateFor(_draft),
                      editContext: widget.editContext,
                      renderer: widget.previewRenderer,
                      onRendered: _onRendered,
                      onRenderFailed: _onRenderFailed,
                      errorBuilder: (_) => const ColoredBox(
                        color: Colors.black,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                    if (_failed)
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          key: const ValueKey('visual-tracks-failure'),
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(context.l10n.visualTracksNotApplied),
                        ),
                      ),
                    if (_committing)
                      const Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Material(
                color: const Color(0xFF101010),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedButton<VisualTrackKind>(
                        key: const ValueKey('visual-track-tabs'),
                        segments: [
                          ButtonSegment(
                            value: VisualTrackKind.era,
                            label: Text(context.l10n.eraAtmosphereTrack),
                          ),
                          ButtonSegment(
                            value: VisualTrackKind.lighting,
                            label: Text(context.l10n.lightingTrack),
                          ),
                        ],
                        selected: {_kind},
                        onSelectionChanged: (value) =>
                            _selectKind(value.single),
                      ),
                      const SizedBox(height: 12),
                      if (_kind == VisualTrackKind.era)
                        _EraControls(
                          value: _eraPosition,
                          enabled: !_committing,
                          onChanged: _previewEra,
                          onChangeEnd: (_) => _end(),
                          onReset: () {
                            _previewEra(0);
                            _end();
                          },
                        )
                      else
                        _LightingControls(
                          targets: widget.faceTargets,
                          selected: _target,
                          azimuth: _azimuth,
                          intensity: _intensity,
                          enabled: !_committing,
                          onTarget: (target) => setState(() {
                            _target = target;
                            _restoreLightingValues();
                          }),
                          onAzimuth: (value) =>
                              _previewLighting(azimuth: value),
                          onAzimuthEnd: (_) => _end(),
                          onIntensity: (value) =>
                              _previewLighting(intensity: value.round()),
                          onIntensityEnd: (_) => _end(),
                          onReset: () {
                            _previewLighting(intensity: 0);
                            _end();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EraControls extends StatelessWidget {
  const _EraControls({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ArcTrack(
        key: const ValueKey('era-arc-track'),
        value: value,
        enabled: enabled,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(context.l10n.vintageFilm),
          TextButton(
            key: const ValueKey('era-track-reset'),
            onPressed: enabled ? onReset : null,
            child: Text(context.l10n.currentEffect),
          ),
          Text(context.l10n.nearFuture),
        ],
      ),
    ],
  );
}

class _LightingControls extends StatelessWidget {
  const _LightingControls({
    required this.targets,
    required this.selected,
    required this.azimuth,
    required this.intensity,
    required this.enabled,
    required this.onTarget,
    required this.onAzimuth,
    required this.onAzimuthEnd,
    required this.onIntensity,
    required this.onIntensityEnd,
    required this.onReset,
  });

  final List<StableEditTarget> targets;
  final StableEditTarget? selected;
  final double azimuth;
  final int intensity;
  final bool enabled;
  final ValueChanged<StableEditTarget> onTarget;
  final ValueChanged<double> onAzimuth;
  final ValueChanged<double> onAzimuthEnd;
  final ValueChanged<double> onIntensity;
  final ValueChanged<double> onIntensityEnd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty) {
      return Padding(
        key: const ValueKey('lighting-track-unavailable'),
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Text(context.l10n.lightingNeedsPerson),
      );
    }
    return Column(
      children: [
        if (targets.length > 1)
          Wrap(
            key: const ValueKey('lighting-target-selector'),
            spacing: 8,
            children: [
              for (var index = 0; index < targets.length; index++)
                ChoiceChip(
                  key: ValueKey('lighting-target-$index'),
                  label: Text(context.l10n.personNumber(index + 1)),
                  selected: selected?.id == targets[index].id,
                  onSelected: enabled ? (_) => onTarget(targets[index]) : null,
                ),
            ],
          ),
        _ArcTrack(
          key: const ValueKey('lighting-arc-track'),
          value: azimuth / 90,
          enabled: enabled,
          onChanged: (value) => onAzimuth(value * 90),
          onChangeEnd: (value) => onAzimuthEnd(value * 90),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.l10n.leftLight),
            Text(context.l10n.frontLight),
            Text(context.l10n.rightLight),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                key: const ValueKey('lighting-intensity'),
                value: intensity.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '$intensity',
                onChanged: enabled ? onIntensity : null,
                onChangeEnd: enabled ? onIntensityEnd : null,
              ),
            ),
            TextButton(
              key: const ValueKey('lighting-reset'),
              onPressed: enabled ? onReset : null,
              child: Text(context.l10n.reset),
            ),
          ],
        ),
      ],
    );
  }
}

class _ArcTrack extends StatelessWidget {
  const _ArcTrack({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  double _valueFor(Offset local, Size size) =>
      ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);

  @override
  Widget build(BuildContext context) => Semantics(
    slider: true,
    value: '${(value * 100).round()}',
    increasedValue: '${((value + .25).clamp(-1, 1) * 100).round()}',
    decreasedValue: '${((value - .25).clamp(-1, 1) * 100).round()}',
    onIncrease: enabled
        ? () {
            final next = (value + .25).clamp(-1.0, 1.0);
            onChanged(next);
            onChangeEnd(next);
          }
        : null,
    onDecrease: enabled
        ? () {
            final next = (value - .25).clamp(-1.0, 1.0);
            onChanged(next);
            onChangeEnd(next);
          }
        : null,
    child: SizedBox(
      height: 92,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: enabled
              ? (details) => onChanged(
                  _valueFor(details.localPosition, constraints.biggest),
                )
              : null,
          onHorizontalDragUpdate: enabled
              ? (details) => onChanged(
                  _valueFor(details.localPosition, constraints.biggest),
                )
              : null,
          onHorizontalDragEnd: enabled ? (_) => onChangeEnd(value) : null,
          onTapUp: enabled
              ? (details) {
                  final next = _valueFor(
                    details.localPosition,
                    constraints.biggest,
                  );
                  onChanged(next);
                  onChangeEnd(next);
                }
              : null,
          child: CustomPaint(painter: _ArcTrackPainter(value: value)),
        ),
      ),
    ),
  );
}

class _ArcTrackPainter extends CustomPainter {
  const _ArcTrackPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(12, 12, size.width - 24, size.height * 1.55);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = const LinearGradient(
        colors: [Color(0xFFB4773A), Color(0xFFE9C35A), Color(0xFF66A6FF)],
      ).createShader(Offset.zero & size);
    canvas.drawArc(rect, math.pi, math.pi, false, paint);
    final angle = math.pi + (value + 1) * math.pi / 2;
    final center = rect.center;
    final point = Offset(
      center.dx + rect.width / 2 * math.cos(angle),
      center.dy + rect.height / 2 * math.sin(angle),
    );
    canvas.drawCircle(point, 8, Paint()..color = const Color(0xFFECC95B));
  }

  @override
  bool shouldRepaint(covariant _ArcTrackPainter oldDelegate) =>
      oldDelegate.value != value;
}
