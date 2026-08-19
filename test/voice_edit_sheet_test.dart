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
