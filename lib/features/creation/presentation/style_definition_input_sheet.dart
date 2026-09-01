import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yingjian/features/creation/domain/style_definition.dart';
import 'package:yingjian/features/editor/application/speech_transcriber.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/l10n/l10n.dart';

enum StyleDefinitionInputMode { text, voice, reference }

/// One entry point for the three supported ways to define a static style.
///
/// It intentionally returns the same [StyleDefinition] for text, a confirmed
/// voice transcript, and a reference image. The reference import is temporary:
/// its aggregate style signal is frozen into the definition and the app-owned
/// temporary file is discarded before the sheet returns.
class StyleDefinitionInputSheet extends StatefulWidget {
  StyleDefinitionInputSheet({
    required this.sourcePath,
    required this.importer,
    required this.transcriber,
    required this.preparePrompt,
    required this.prepareReference,
    this.initialMode = StyleDefinitionInputMode.text,
    this.allowedModes = const {
      StyleDefinitionInputMode.text,
      StyleDefinitionInputMode.voice,
      StyleDefinitionInputMode.reference,
    },
    super.key,
  }) : assert(allowedModes.isNotEmpty),
       assert(allowedModes.contains(initialMode));

  final String sourcePath;
  final PhotoImporter importer;
  final SpeechTranscriber transcriber;
  final Future<StyleDefinition?> Function(
    String prompt,
    StyleDefinitionOrigin origin,
  )
  preparePrompt;
  final Future<StyleDefinition?> Function(ImportedEditingResource reference)
  prepareReference;
  final StyleDefinitionInputMode initialMode;
  final Set<StyleDefinitionInputMode> allowedModes;

  @override
  State<StyleDefinitionInputSheet> createState() =>
      _StyleDefinitionInputSheetState();
}

class _StyleDefinitionInputSheetState extends State<StyleDefinitionInputSheet> {
  final _controller = TextEditingController();
  late StyleDefinitionInputMode _mode;
  ImportedEditingResource? _reference;
  bool _busy = false;
  bool _listening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    if (_listening) unawaited(widget.transcriber.stop());
    final reference = _reference;
    if (reference != null) unawaited(_discard(reference));
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy &&
      !_listening &&
      switch (_mode) {
        StyleDefinitionInputMode.reference => _reference != null,
        StyleDefinitionInputMode.text ||
        StyleDefinitionInputMode.voice => _controller.text.trim().isNotEmpty,
      };

  void _selectMode(StyleDefinitionInputMode mode) {
    if (_busy ||
        _listening ||
        _mode == mode ||
        !widget.allowedModes.contains(mode)) {
      return;
    }
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _toggleRecording() async {
    if (_busy) return;
    if (_listening) {
      await widget.transcriber.stop();
      return;
    }
    final localeIdentifier = Localizations.localeOf(context).toLanguageTag();
    setState(() {
      _listening = true;
      _error = null;
    });
    try {
      final transcript = await widget.transcriber.start(
        localeIdentifier: localeIdentifier,
      );
      if (!mounted) return;
      _controller
        ..text = transcript
        ..selection = TextSelection.collapsed(offset: transcript.length);
    } on Object {
      if (mounted) setState(() => _error = context.l10n.styleVoiceFailed);
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<void> _chooseReference() async {
    if (_busy || _listening) return;
    final importer = widget.importer;
    if (importer is! EditingResourceImporter) {
      setState(() => _error = context.l10n.styleReferenceUnavailable);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    ImportedEditingResource? selected;
    try {
      selected = await importer.importEditingResource(
        EditingResourceKind.backgroundImage,
      );
      if (!mounted) {
        if (selected != null) await importer.discardEditingResource(selected);
        return;
      }
      if (selected == null) return;
      final previous = _reference;
      setState(() => _reference = selected);
      if (previous != null) await importer.discardEditingResource(previous);
    } on Object {
      if (mounted) setState(() => _error = context.l10n.styleReferenceFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeReference() async {
    final reference = _reference;
    if (reference == null || _busy) return;
    setState(() => _reference = null);
    await _discard(reference);
  }

  Future<void> _discard(ImportedEditingResource reference) async {
    final importer = widget.importer;
    if (importer is! EditingResourceImporter) return;
    try {
      await importer.discardEditingResource(reference);
    } on Object {
      // A failed cleanup must never turn the reference into project content.
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    StyleDefinition? definition;
    try {
      final reference = _reference;
      final prepared = switch (_mode) {
        StyleDefinitionInputMode.text => widget.preparePrompt(
          _controller.text.trim(),
          StyleDefinitionOrigin.text,
        ),
        StyleDefinitionInputMode.voice => widget.preparePrompt(
          _controller.text.trim(),
          StyleDefinitionOrigin.voice,
        ),
        StyleDefinitionInputMode.reference when reference != null =>
          widget.prepareReference(reference),
        StyleDefinitionInputMode.reference => Future.value(null),
      };
      definition = await prepared;
      if (definition == null) {
        if (mounted) setState(() => _error = context.l10n.styleNotUnderstood);
        return;
      }
      final selectedReference = _reference;
      if (selectedReference != null) {
        _reference = null;
        await _discard(selectedReference);
      }
      if (mounted) Navigator.of(context).pop(definition);
    } on Object {
      if (mounted) {
        setState(
          () => _error = _mode == StyleDefinitionInputMode.reference
              ? context.l10n.styleReferenceFailed
              : context.l10n.styleNotUnderstood,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: const ValueKey('style-definition-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.describeStyleTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.styleDefinitionInputHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.allowedModes.length > 1) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.allowedModes.contains(
                      StyleDefinitionInputMode.text,
                    ))
                      _modeChip(
                        context,
                        StyleDefinitionInputMode.text,
                        key: const ValueKey('style-input-text'),
                        icon: Icons.keyboard_alt_outlined,
                        label: context.l10n.styleInputText,
                      ),
                    if (widget.allowedModes.contains(
                      StyleDefinitionInputMode.voice,
                    ))
                      _modeChip(
                        context,
                        StyleDefinitionInputMode.voice,
                        key: const ValueKey('style-input-voice'),
                        icon: Icons.mic_none_rounded,
                        label: context.l10n.styleInputVoice,
                      ),
                    if (widget.allowedModes.contains(
                      StyleDefinitionInputMode.reference,
                    ))
                      _modeChip(
                        context,
                        StyleDefinitionInputMode.reference,
                        key: const ValueKey('style-input-reference'),
                        icon: Icons.photo_outlined,
                        label: context.l10n.styleInputReference,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              switch (_mode) {
                StyleDefinitionInputMode.text => _buildPrompt(context),
                StyleDefinitionInputMode.voice => _buildVoice(context),
                StyleDefinitionInputMode.reference => _buildReference(context),
              },
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    key: const ValueKey('style-definition-input-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                key: const ValueKey('style-definition-submit'),
                onPressed: _canSubmit ? _submit : null,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.l10n.defineStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeChip(
    BuildContext context,
    StyleDefinitionInputMode mode, {
    required Key key,
    required IconData icon,
    required String label,
  }) => ChoiceChip(
    key: key,
    selected: _mode == mode,
    onSelected: _busy || _listening ? null : (_) => _selectMode(mode),
    avatar: Icon(icon, size: 18),
    label: Text(label),
  );

  Widget _buildPrompt(BuildContext context) => TextField(
    key: const ValueKey('style-definition-prompt'),
    controller: _controller,
    autofocus: true,
    enabled: !_busy,
    maxLength: 120,
    maxLines: 3,
    minLines: 2,
    textInputAction: TextInputAction.done,
    decoration: InputDecoration(hintText: context.l10n.describeStyleHint),
    onSubmitted: (_) => _submit(),
    onChanged: (_) => setState(() {}),
  );

  Widget _buildVoice(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.l10n.styleVoiceTranscriptHint,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 10),
      _buildPrompt(context),
      const SizedBox(height: 12),
      if (_listening)
        Semantics(
          key: const ValueKey('style-voice-listening'),
          liveRegion: true,
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(context.l10n.styleVoiceListening),
            ],
          ),
        ),
      OutlinedButton.icon(
        key: const ValueKey('style-voice-record'),
        onPressed: _busy ? null : _toggleRecording,
        icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
        label: Text(
          _listening
              ? context.l10n.styleVoiceStop
              : context.l10n.styleVoiceRecord,
        ),
      ),
    ],
  );

  Widget _buildReference(BuildContext context) {
    final reference = _reference;
    if (reference == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.styleReferenceHint,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('style-reference-choose'),
            onPressed: _busy || _listening ? null : _chooseReference,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(context.l10n.styleReferenceChoose),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.styleReferenceKeptLocal,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _rolePreview(
                key: const ValueKey('style-reference-source'),
                path: widget.sourcePath,
                label: context.l10n.styleReferenceSource,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _rolePreview(
                key: const ValueKey('style-reference-image'),
                path: reference.localPath,
                label: context.l10n.styleReferenceImage,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const ValueKey('style-reference-remove'),
          onPressed: _busy ? null : _removeReference,
          icon: const Icon(Icons.close_rounded),
          label: Text(context.l10n.styleReferenceRemove),
        ),
      ],
    );
  }

  Widget _rolePreview({
    required Key key,
    required String path,
    required String label,
  }) => Semantics(
    key: key,
    label: label,
    image: true,
    child: Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Color(0xFF2C2C2E),
                child: Icon(Icons.photo_outlined),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}
