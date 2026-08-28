import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:yingjian/app/theme/app_theme.dart';
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

enum _VisualTrackStage { landing, editing, selectingTarget }

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
  _VisualTrackStage _stage = _VisualTrackStage.landing;
  VisualTrackKind _kind = VisualTrackKind.era;
  StableEditTarget? _target;
  double _eraPosition = 0;
  double _azimuth = 0;
  int _intensity = 0;
  bool _adjusting = false;
  bool _committing = false;
  bool _failed = false;
  bool _showApplied = false;
  bool _hasCommitted = false;
  EditRecipe? _pendingCommit;
  EditRecipe? _lastRendered;
  EditRecipe? _retryRecipe;

  @override
  void initState() {
    super.initState();
    _baseline = widget.initialRecipe;
    _draft = _baseline;
    if (widget.faceTargets.length == 1) _target = widget.faceTargets.single;
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
    _showApplied = false;
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
    if (_draft == _baseline) {
      setState(() {});
      return;
    }
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
      _showApplied = true;
      _hasCommitted = true;
      _retryRecipe = null;
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
    final failedDraft = _draft;
    widget.editorSession.load(_baseline);
    setState(() {
      _retryRecipe = failedDraft == _baseline ? null : failedDraft;
      _draft = _baseline;
      _adjusting = false;
      _committing = false;
      _pendingCommit = null;
      _failed = true;
      _showApplied = false;
      _eraPosition = 0;
      _restoreLightingValues();
    });
  }

  void _retry() {
    final retry = _retryRecipe;
    if (retry == null || _committing) return;
    _begin();
    widget.editorSession.preview(retry);
    setState(() => _draft = retry);
    _end();
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
      _showApplied = false;
      _restoreLightingValues();
    });
  }

  void _selectKind(VisualTrackKind value) {
    if (_adjusting || _committing || value == _kind) return;
    setState(() {
      _kind = value;
      _failed = false;
      _showApplied = false;
      _stage =
          value == VisualTrackKind.lighting &&
              widget.faceTargets.length > 1 &&
              _target == null
          ? _VisualTrackStage.selectingTarget
          : _VisualTrackStage.editing;
    });
  }

  void _selectTarget(StableEditTarget target) {
    setState(() {
      _target = target;
      _stage = _VisualTrackStage.editing;
      _restoreLightingValues();
    });
  }

  void _openEra() {
    setState(() {
      _stage = _VisualTrackStage.editing;
      _kind = VisualTrackKind.era;
      _failed = false;
    });
  }

  void _saveAndExit() => Navigator.of(context).pop(_hasCommitted);

  String _title(BuildContext context) {
    if (_failed) return '18 ${_zh(context) ? '失败安全态' : 'Safe failure'}';
    if (_stage == _VisualTrackStage.landing) {
      return '11 ${context.l10n.visualTracksEntry}';
    }
    if (_stage == _VisualTrackStage.selectingTarget) {
      return '15 ${_zh(context) ? '光照·选择人物' : 'Lighting · choose person'}';
    }
    if (_kind == VisualTrackKind.era) {
      if (_adjusting) return '13 ${_zh(context) ? '拖动中' : 'Previewing'}';
      if (_showApplied) return '14 ${_zh(context) ? '松手已提交' : 'Applied'}';
      return '12 ${_zh(context) ? '时代氛围·中性' : 'Era · neutral'}';
    }
    if (_showApplied) {
      return '17 ${_zh(context) ? '光照·提交' : 'Lighting · applied'}';
    }
    return '16 ${_zh(context) ? '光照·方向调整' : 'Lighting direction'}';
  }

  static bool _zh(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, _) {
        if (_adjusting) widget.editorSession.load(_baseline);
      },
      child: Scaffold(
        key: const ValueKey('visual-tracks-page'),
        backgroundColor: AppTheme.canvas,
        body: Stack(
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
            const _BottomReadabilityGradient(),
            if (_stage == _VisualTrackStage.selectingTarget)
              _TargetSelectionOverlay(
                targets: widget.faceTargets,
                onSelected: _selectTarget,
              ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: _TopBar(
                  title: _title(context),
                  canUndo: !_committing && _stage != _VisualTrackStage.landing,
                  onBack: () => Navigator.of(context).pop(_hasCommitted),
                  onUndo: () => unawaited(_undo()),
                  onSave: _saveAndExit,
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 90, 20, 20),
                  child: _buildBottom(context),
                ),
              ),
            ),
            if (_adjusting)
              SafeArea(
                child: Align(
                  alignment: const Alignment(0, -0.72),
                  child: _StatusPill(
                    key: const ValueKey('visual-tracks-previewing'),
                    icon: Icons.circle,
                    label: _zh(context) ? '正在预览' : 'Previewing',
                  ),
                ),
              ),
            if (_committing)
              const SafeArea(
                child: Align(
                  alignment: Alignment(0, -0.72),
                  child: _StatusPill(
                    key: ValueKey('visual-tracks-committing'),
                    icon: Icons.auto_awesome_rounded,
                    label: '正在应用',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottom(BuildContext context) {
    if (_failed) {
      return _FailurePanel(
        canRetry: _retryRecipe != null && !_committing,
        onOther: _openEra,
        onRetry: _retry,
      );
    }
    if (_stage == _VisualTrackStage.landing) {
      return _LandingPanel(onOpen: _openEra, onSave: _saveAndExit);
    }
    if (_stage == _VisualTrackStage.selectingTarget) {
      return _TargetHintPanel(onEra: () => _selectKind(VisualTrackKind.era));
    }
    if (_showApplied) {
      return _AppliedPanel(
        kind: _kind,
        targetIndex: _target == null
            ? null
            : widget.faceTargets.indexOf(_target!) + 1,
        onUndo: () => unawaited(_undo()),
        onContinue: () => setState(() => _showApplied = false),
      );
    }
    return _GlassPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TrackTabs(kind: _kind, onChanged: _selectKind),
          const SizedBox(height: 14),
          if (_kind == VisualTrackKind.era)
            _EraControls(
              value: _eraPosition,
              enabled: !_committing,
              onChanged: _previewEra,
              onChangeEnd: (_) => _end(),
            )
          else
            _LightingControls(
              targets: widget.faceTargets,
              selected: _target,
              azimuth: _azimuth,
              intensity: _intensity,
              enabled: !_committing,
              onTarget: _selectTarget,
              onAzimuth: (value) => _previewLighting(azimuth: value),
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
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.canUndo,
    required this.onBack,
    required this.onUndo,
    required this.onSave,
  });

  final String title;
  final bool canUndo;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    child: Row(
      children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.gold),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        if (canUndo)
          IconButton(
            key: const ValueKey('visual-tracks-undo'),
            tooltip: context.l10n.undo,
            onPressed: onUndo,
            icon: const Icon(Icons.undo_rounded),
          )
        else
          TextButton(
            key: const ValueKey('visual-tracks-save'),
            onPressed: onSave,
            child: Text(
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '保存'
                  : 'Save',
            ),
          ),
      ],
    ),
  );
}

class _BottomReadabilityGradient extends StatelessWidget {
  const _BottomReadabilityGradient();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0x220B0D0E), Color(0xFA0B0D0E)],
          stops: [0.42, 0.63, 1],
        ),
      ),
    ),
  );
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: const Color(0xE618191A),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: child,
      ),
    ),
  );
}

class _LandingPanel extends StatelessWidget {
  const _LandingPanel({required this.onOpen, required this.onSave});

  final VoidCallback onOpen;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _GlassPanel(
        child: InkWell(
          key: const ValueKey('visual-tracks-open-era'),
          onTap: onOpen,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.visualTracksTitle,
                        style: const TextStyle(
                          color: AppTheme.gold,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        Localizations.localeOf(context).languageCode == 'zh'
                            ? '时代氛围与光照探索'
                            : 'Explore era and lighting',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: AppTheme.gold),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: onOpen,
                  icon: const Icon(Icons.explore_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      _CommandCapsule(onSubmit: onOpen, onSave: onSave),
    ],
  );
}

class _CommandCapsule extends StatelessWidget {
  const _CommandCapsule({required this.onSubmit, required this.onSave});

  final VoidCallback onSubmit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Container(
    height: 62,
    decoration: BoxDecoration(
      color: const Color(0xD9161819),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppTheme.gold.withValues(alpha: 0.28)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      children: [
        IconButton(
          tooltip: context.l10n.voiceEditRecord,
          onPressed: onSubmit,
          icon: const Icon(Icons.mic_rounded, color: AppTheme.gold),
        ),
        Expanded(
          child: InkWell(
            onTap: onSubmit,
            child: Text(
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '帮我调亮一点…'
                  : 'Make it a little brighter…',
              style: const TextStyle(
                color: AppTheme.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: context.l10n.apply,
          onPressed: onSubmit,
          icon: const Icon(Icons.send_rounded),
        ),
      ],
    ),
  );
}

class _TrackTabs extends StatelessWidget {
  const _TrackTabs({required this.kind, required this.onChanged});

  final VisualTrackKind kind;
  final ValueChanged<VisualTrackKind> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _TrackTab(
        key: const ValueKey('visual-track-era-tab'),
        label: context.l10n.eraAtmosphereTrack,
        selected: kind == VisualTrackKind.era,
        onTap: () => onChanged(VisualTrackKind.era),
      ),
      const SizedBox(width: 8),
      _TrackTab(
        key: const ValueKey('visual-track-lighting-tab'),
        label: context.l10n.lightingTrack,
        selected: kind == VisualTrackKind.lighting,
        onTap: () => onChanged(VisualTrackKind.lighting),
      ),
    ],
  );
}

class _TrackTab extends StatelessWidget {
  const _TrackTab({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minWidth: 88, minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: selected ? AppTheme.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppTheme.gold : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF241A00) : AppTheme.softWhite,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

class _EraControls extends StatelessWidget {
  const _EraControls({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final valueLabel = value < -0.12
        ? '${context.l10n.currentEffect} ${(value * 100).round()}'
        : value > 0.12
        ? '${context.l10n.nearFuture} +${(value * 100).round()}'
        : context.l10n.currentEffect;
    return Column(
      children: [
        Text(
          valueLabel,
          key: const ValueKey('era-track-value'),
          style: const TextStyle(
            color: AppTheme.gold,
            fontWeight: FontWeight.w700,
          ),
        ),
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
            Text(context.l10n.currentEffect),
            Text(context.l10n.nearFuture),
          ],
        ),
      ],
    );
  }
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
    if (targets.isEmpty || selected == null) {
      return Padding(
        key: const ValueKey('lighting-track-unavailable'),
        padding: const EdgeInsets.symmetric(vertical: 22),
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
                  label: Text('人物 ${index + 1}'),
                  selected: selected?.id == targets[index].id,
                  onSelected: enabled ? (_) => onTarget(targets[index]) : null,
                ),
            ],
          ),
        Text(
          '${_direction(context, azimuth)} · ${azimuth >= 0 ? '+' : ''}${azimuth.round()}',
          style: const TextStyle(
            color: AppTheme.gold,
            fontWeight: FontWeight.w700,
          ),
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
            const Icon(Icons.light_mode_outlined, size: 20),
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
            Text('$intensity'),
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

  static String _direction(BuildContext context, double value) {
    if (value < -18) return context.l10n.leftLight;
    if (value > 18) return context.l10n.rightLight;
    return context.l10n.frontLight;
  }
}

class _TargetSelectionOverlay extends StatelessWidget {
  const _TargetSelectionOverlay({
    required this.targets,
    required this.onSelected,
  });

  final List<StableEditTarget> targets;
  final ValueChanged<StableEditTarget> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      children: [
        for (var index = 0; index < targets.length; index++)
          Positioned(
            left: targets[index].region.left * constraints.maxWidth,
            top: targets[index].region.top * constraints.maxHeight,
            width:
                (targets[index].region.right - targets[index].region.left) *
                constraints.maxWidth,
            height:
                (targets[index].region.bottom - targets[index].region.top) *
                constraints.maxHeight,
            child: Semantics(
              button: true,
              label: '人物 ${index + 1}',
              child: InkWell(
                key: ValueKey('lighting-overlay-target-$index'),
                onTap: () => onSelected(targets[index]),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.gold, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: CircleAvatar(
                    backgroundColor: const Color(0xCC3A3226),
                    foregroundColor: AppTheme.softWhite,
                    child: Text('${index + 1}'),
                  ),
                ),
              ),
            ),
          ),
        SafeArea(
          child: Align(
            alignment: const Alignment(0, -0.66),
            child: _StatusPill(
              icon: Icons.person_search_outlined,
              label: Localizations.localeOf(context).languageCode == 'zh'
                  ? '光照只作用当前照片中的所选人物'
                  : 'Lighting applies only to the selected person',
            ),
          ),
        ),
      ],
    ),
  );
}

class _TargetHintPanel extends StatelessWidget {
  const _TargetHintPanel({required this.onEra});

  final VoidCallback onEra;

  @override
  Widget build(BuildContext context) => _GlassPanel(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Localizations.localeOf(context).languageCode == 'zh'
              ? '点选要调整光照的人物'
              : 'Choose the person to relight',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onEra,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(context.l10n.eraAtmosphereTrack),
        ),
      ],
    ),
  );
}

class _AppliedPanel extends StatelessWidget {
  const _AppliedPanel({
    required this.kind,
    required this.targetIndex,
    required this.onUndo,
    required this.onContinue,
  });

  final VisualTrackKind kind;
  final int? targetIndex;
  final VoidCallback onUndo;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final message = kind == VisualTrackKind.era
        ? (zh ? '已应用时代氛围' : 'Era atmosphere applied')
        : (zh
              ? '已调整人物 ${targetIndex ?? 1} 的光照'
              : 'Lighting adjusted for person ${targetIndex ?? 1}');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassPanel(
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppTheme.gold),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
              TextButton(onPressed: onUndo, child: Text(context.l10n.undo)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('visual-tracks-continue'),
          onPressed: onContinue,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.tune_rounded),
          label: Text(zh ? '继续精调' : 'Keep refining'),
        ),
      ],
    );
  }
}

class _FailurePanel extends StatelessWidget {
  const _FailurePanel({
    required this.canRetry,
    required this.onOther,
    required this.onRetry,
  });

  final bool canRetry;
  final VoidCallback onOther;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('visual-tracks-failure'),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFB5101D),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                context.l10n.visualTracksNotApplied,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: onOther,
                icon: const Icon(Icons.alt_route_rounded),
                label: Text(zh ? '选择其他轨道' : 'Choose another track'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('visual-tracks-retry'),
                onPressed: canRetry ? onRetry : null,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.retry),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xCC343536),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.gold),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
      height: 72,
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
    final rect = Rect.fromLTWH(8, 14, size.width - 16, size.height * 1.34);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawArc(rect, math.pi, math.pi, false, base);
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.gold;
    final sweep = (value + 1) * math.pi / 2;
    canvas.drawArc(rect, math.pi, sweep, false, active);
    final angle = math.pi + sweep;
    final center = rect.center;
    final point = Offset(
      center.dx + rect.width / 2 * math.cos(angle),
      center.dy + rect.height / 2 * math.sin(angle),
    );
    canvas.drawCircle(point, 12, Paint()..color = const Color(0xFF2E2F30));
    canvas.drawCircle(point, 8, Paint()..color = AppTheme.gold);
  }

  @override
  bool shouldRepaint(covariant _ArcTrackPainter oldDelegate) =>
      oldDelegate.value != value;
}
