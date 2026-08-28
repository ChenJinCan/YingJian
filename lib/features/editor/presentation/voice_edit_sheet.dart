import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/features/editor/application/speech_transcriber.dart';
import 'package:yingjian/l10n/l10n.dart';

enum _VoiceStage { compose, clarification }

class VoiceEditSheet extends StatefulWidget {
  const VoiceEditSheet({
    required this.transcriber,
    required this.onSubmit,
    super.key,
  });

  final SpeechTranscriber transcriber;
  final FutureOr<bool> Function(String intent) onSubmit;

  @override
  State<VoiceEditSheet> createState() => _VoiceEditSheetState();
}

class _VoiceEditSheetState extends State<VoiceEditSheet> {
  final TextEditingController _controller = TextEditingController();
  _VoiceStage _stage = _VoiceStage.compose;
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
      _stage = _VoiceStage.compose;
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

  void _prepare() {
    if (_applying || _listening) return;
    final intent = _controller.text.trim();
    if (intent.isEmpty) {
      setState(() => _error = context.l10n.voiceEditUnsupported);
      return;
    }
    if (_needsBrightnessClarification(intent)) {
      setState(() {
        _stage = _VoiceStage.clarification;
        _error = null;
      });
      return;
    }
    unawaited(_apply());
  }

  bool _needsBrightnessClarification(String intent) {
    final lower = intent.toLowerCase();
    final brightness = lower.contains('亮') || lower.contains('brighter');
    final scoped = [
      '人物',
      '人像',
      '脸',
      '照片',
      '整张',
      '整体',
      'person',
      'face',
      'photo',
      'whole',
    ].any(lower.contains);
    return brightness && !scoped;
  }

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  void _resolveClarification({required bool portraitOnly}) {
    final base = _controller.text.trim();
    _controller.text = portraitOnly
        ? '$base，${_zh ? '只调整人物' : 'only adjust the person'}'
        : '$base，${_zh ? '调整整张照片' : 'adjust the whole photo'}';
    setState(() => _stage = _VoiceStage.compose);
    unawaited(_apply());
  }

  Future<void> _apply() async {
    if (_applying || _listening) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final applied = await widget.onSubmit(_controller.text.trim());
      if (!applied && mounted) {
        setState(() {
          _stage = _VoiceStage.compose;
          _error = context.l10n.voiceEditUnsupported;
        });
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _restart() {
    setState(() {
      _stage = _VoiceStage.compose;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: Material(
            color: AppTheme.canvas,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_stage) {
                  _VoiceStage.compose => _buildCompose(context),
                  _VoiceStage.clarification => _buildClarification(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle(BuildContext context) => Column(
    children: [
      Container(
        width: 38,
        height: 5,
        decoration: BoxDecoration(
          color: AppTheme.muted.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        _zh ? '语音调整' : 'Voice adjustment',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _buildCompose(BuildContext context) => Column(
    key: const ValueKey('voice-compose'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _handle(context),
      const SizedBox(height: 22),
      TextField(
        key: const ValueKey('voice-edit-text-field'),
        controller: _controller,
        minLines: 2,
        maxLines: 4,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _prepare(),
        decoration: InputDecoration(
          hintText: context.l10n.voiceEditHint,
          prefixIcon: const Icon(Icons.keyboard_alt_outlined),
        ),
      ),
      const SizedBox(height: 12),
      if (_listening)
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
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(
          _error!,
          key: const ValueKey('voice-edit-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 18),
      Row(
        children: [
          IconButton.filledTonal(
            key: const ValueKey('voice-edit-record'),
            tooltip: _listening
                ? context.l10n.voiceEditStop
                : context.l10n.voiceEditRecord,
            onPressed: _applying ? null : _toggleListening,
            constraints: const BoxConstraints.tightFor(width: 54, height: 54),
            icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('voice-edit-submit'),
              onPressed: _applying || _listening ? null : _prepare,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: Text(_zh ? '应用调整' : 'Apply adjustment'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.undo_rounded, size: 15, color: AppTheme.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _zh
                  ? '应用前会先验证预览，应用后可随时撤销'
                  : 'Preview is validated first; applied edits remain undoable',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildClarification(BuildContext context) => Column(
    key: const ValueKey('voice-clarification'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _handle(context),
      const SizedBox(height: 30),
      Text(
        _zh
            ? '你想让人物更亮，\n还是整张照片更亮？'
            : 'Should the person be brighter,\nor the whole photo?',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.38,
        ),
      ),
      const SizedBox(height: 28),
      FilledButton(
        key: const ValueKey('voice-clarify-person'),
        onPressed: () => _resolveClarification(portraitOnly: true),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        child: Text(_zh ? '只调整人物' : 'Person only'),
      ),
      const SizedBox(height: 12),
      FilledButton.tonal(
        key: const ValueKey('voice-clarify-photo'),
        onPressed: () => _resolveClarification(portraitOnly: false),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        child: Text(_zh ? '调整整张' : 'Whole photo'),
      ),
      const SizedBox(height: 16),
      Text(
        _zh ? '没有听清？可以重新说一次' : 'Not quite right? Try speaking again.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _toggleListening,
            icon: const Icon(Icons.mic_rounded),
            label: Text(_zh ? '重新说' : 'Speak again'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.keyboard_alt_outlined),
            label: Text(_zh ? '改用文字' : 'Use text'),
          ),
        ],
      ),
    ],
  );
}
