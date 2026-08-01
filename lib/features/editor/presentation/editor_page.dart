import 'package:flutter/material.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/l10n/l10n.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final EditorSession _session = EditorSession();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final recipe = _session.recipe;
        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.editorTitle),
            actions: [
              IconButton(
                tooltip: context.l10n.undo,
                onPressed: _session.canUndo ? _session.undo : null,
                icon: const Icon(Icons.undo),
              ),
              TextButton(
                onPressed: _session.isEdited ? _session.reset : null,
                child: Text(context.l10n.reset),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(child: Text(context.l10n.photoPreviewArea)),
                ),
              ),
              const SizedBox(height: 32),
              _AdjustmentSlider(
                label: context.l10n.exposure,
                value: recipe.exposure,
                onChangeStart: _session.beginAdjustment,
                onChanged: (value) {
                  _session.preview(recipe.copyWith(exposure: value));
                },
                onChangeEnd: _session.commitAdjustment,
              ),
              _AdjustmentSlider(
                label: context.l10n.contrast,
                value: recipe.contrast,
                onChangeStart: _session.beginAdjustment,
                onChanged: (value) {
                  _session.preview(recipe.copyWith(contrast: value));
                },
                onChangeEnd: _session.commitAdjustment,
              ),
              _AdjustmentSlider(
                label: context.l10n.warmth,
                value: recipe.warmth,
                onChangeStart: _session.beginAdjustment,
                onChanged: (value) {
                  _session.preview(recipe.copyWith(warmth: value));
                },
                onChangeEnd: _session.commitAdjustment,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AdjustmentSlider extends StatelessWidget {
  const _AdjustmentSlider({
    required this.label,
    required this.value,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: value.toStringAsFixed(2),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: -1,
              max: 1,
              onChangeStart: (_) => onChangeStart(),
              onChanged: onChanged,
              onChangeEnd: (_) => onChangeEnd(),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(value.toStringAsFixed(1), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
