import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/speech_transcriber.dart';
import 'package:yingjian/features/editor/presentation/voice_edit_sheet.dart';
import 'package:yingjian/l10n/app_localizations.dart';

void main() {
  testWidgets('typed request applies a visible recipe result', (tester) async {
    String? applied;
    await tester.pumpWidget(
      _TestHost(
        child: VoiceEditSheet(
          transcriber: _FakeSpeechTranscriber(),
          onSubmit: (intent) {
            applied = intent;
            return true;
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('voice-edit-text-field')),
      '照片亮一点',
    );
    await tester.tap(find.byKey(const ValueKey('voice-edit-submit')));
    await tester.pump();

    expect(applied, '照片亮一点');
  });

  testWidgets('voice result remains editable before the user applies it', (
    tester,
  ) async {
    final transcriber = _FakeSpeechTranscriber();
    await tester.pumpWidget(
      _TestHost(
        child: VoiceEditSheet(transcriber: transcriber, onSubmit: (_) => true),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('voice-edit-record')));
    await tester.pump();
    expect(find.byKey(const ValueKey('voice-edit-listening')), findsOneWidget);

    transcriber.complete('照片亮一点');
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('voice-edit-text-field')),
    );
    expect(field.controller?.text, '照片亮一点');
  });

  testWidgets('apply waits for the Chinese IME to commit its composition', (
    tester,
  ) async {
    String? applied;
    await tester.pumpWidget(
      _TestHost(
        child: VoiceEditSheet(
          transcriber: _FakeSpeechTranscriber(),
          onSubmit: (intent) {
            applied = intent;
            return true;
          },
        ),
      ),
    );

    final field = find.byKey(const ValueKey('voice-edit-text-field'));
    await tester.tap(field);
    await tester.showKeyboard(field);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '白yid',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 1, end: 4),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('voice-edit-submit')));
    tester.widget<TextField>(field).controller!.value = const TextEditingValue(
      text: '白一点',
      selection: TextSelection.collapsed(offset: 3),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-clarification')), findsOneWidget);
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('voice-clarify-photo')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(applied, '白一点，调整整张照片');
  });

  testWidgets('the compact sheet keeps one clear text and voice entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestHost(
        child: VoiceEditSheet(
          transcriber: _FakeSpeechTranscriber(),
          onSubmit: (_) => true,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('voice-edit-text-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-edit-record')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-edit-submit')), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('ambiguous brightness asks for the smallest safe clarification', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestHost(
        child: VoiceEditSheet(
          transcriber: _FakeSpeechTranscriber(),
          onSubmit: (_) => true,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('voice-edit-text-field')),
      '亮一点',
    );
    await tester.tap(find.byKey(const ValueKey('voice-edit-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-clarification')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-clarify-person')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-clarify-photo')), findsOneWidget);
  });
}

class _TestHost extends StatelessWidget {
  const _TestHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: child),
  );
}

class _FakeSpeechTranscriber implements SpeechTranscriber {
  Completer<String>? _completion;

  @override
  Future<String> start({required String localeIdentifier}) {
    _completion = Completer<String>();
    return _completion!.future;
  }

  @override
  Future<void> stop() async {}

  void complete(String transcript) => _completion!.complete(transcript);
}
