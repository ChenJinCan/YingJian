import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yingjian/features/editor/application/natural_language_edit_interpreter.dart';
import 'package:yingjian/features/editor/application/speech_transcriber.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/l10n/l10n.dart';

class VoiceEditSheet extends StatefulWidget {
  const VoiceEditSheet({
    required this.currentRecipe,
    required this.interpreter,
    required this.transcriber,
    required this.onApplied,
    super.key,
  });

  final EditRecipe currentRecipe;
  final NaturalLanguageEditInterpreter interpreter;
  final SpeechTranscriber transcriber;
  final FutureOr<void> Function(NaturalLanguageEditResult result) onApplied;

  @override
  State<VoiceEditSheet> createState() => _VoiceEditSheetState();
}

class _VoiceEditSheetState extends State<VoiceEditSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _listening = false;
  bool _applying = false;
  String? _error;

  @override
  void dispose() {
    if (_listening) unawaited(widget.transcriber.stop());
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await widget.transcriber.stop();
      return;
    }
    setState(() {
      _listening = true;
      _error = null;
    });
    try {
      final transcript = await widget.transcriber.start(
        localeIdentifier: Localizations.localeOf(context).toLanguageTag(),
      );
      if (!mounted) return;
      _controller.text = transcript;
      _controller.selection = TextSelection.collapsed(
        offset: transcript.length,
      );
    } on Object {
      if (mounted) setState(() => _error = context.l10n.voiceEditFailed);
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<void> _submit() async {
    if (_applying || _listening) return;
    final result = widget.interpreter.interpret(
      _controller.text,
      current: widget.currentRecipe,
    );
    if (!result.isApplicable) {
      setState(() => _error = context.l10n.voiceEditUnsupported);
      return;
    }
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await widget.onApplied(result);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.voiceEditTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('voice-edit-text-field'),
                    controller: _controller,
                    minLines: 1,
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => unawaited(_submit()),
                    decoration: InputDecoration(
                      hintText: context.l10n.voiceEditHint,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  key: const ValueKey('voice-edit-record'),
                  tooltip: _listening
                      ? context.l10n.voiceEditStop
                      : context.l10n.voiceEditRecord,
                  onPressed: _applying ? null : _toggleListening,
                  constraints: const BoxConstraints.tightFor(
                    width: 54,
                    height: 54,
                  ),
                  icon: Icon(_listening ? Icons.stop : Icons.mic_outlined),
                ),
              ],
            ),
            if (_listening) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Row(
                  key: const ValueKey('voice-edit-listening'),
                  children: [
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(context.l10n.voiceEditListening),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const ValueKey('voice-edit-error'),
                  style: TextStyle(color: colors.error),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('voice-edit-submit'),
              onPressed: _applying || _listening ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _applying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_outlined),
              label: Text(context.l10n.voiceEditApply),
            ),
          ],
        ),
      ),
    );
  }
}
