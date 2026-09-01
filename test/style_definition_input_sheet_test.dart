import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/domain/style_definition.dart';
import 'package:yingjian/features/creation/presentation/style_definition_input_sheet.dart';
import 'package:yingjian/features/editor/application/speech_transcriber.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/l10n/app_localizations.dart';

import 'support/test_services.dart';

void main() {
  testWidgets('a production capability can lock the sheet to one input mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        sheet: () => StyleDefinitionInputSheet(
          sourcePath: '/tmp/source.jpg',
          importer: FakePhotoImporter(),
          transcriber: const _FakeSpeechTranscriber(''),
          initialMode: StyleDefinitionInputMode.voice,
          allowedModes: const {StyleDefinitionInputMode.voice},
          preparePrompt: (_, _) async => null,
          prepareReference: (_) async => null,
        ),
        onResult: (_) {},
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('style-input-text')), findsNothing);
    expect(find.byKey(const ValueKey('style-input-voice')), findsNothing);
    expect(find.byKey(const ValueKey('style-input-reference')), findsNothing);
    expect(find.byKey(const ValueKey('style-voice-record')), findsOneWidget);
    expect(find.byKey(const ValueKey('style-reference-choose')), findsNothing);
  });

  testWidgets('confirmed text returns a text StyleDefinition', (tester) async {
    StyleDefinition? result;
    await tester.pumpWidget(
      _host(
        sheet: () => StyleDefinitionInputSheet(
          sourcePath: '/tmp/source.jpg',
          importer: FakePhotoImporter(),
          transcriber: const _FakeSpeechTranscriber(''),
          preparePrompt: (prompt, origin) async =>
              _definition(origin: origin, id: 'text-style-v1', title: prompt),
          prepareReference: (_) async => null,
        ),
        onResult: (value) => result = value,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('style-definition-prompt')),
      '温暖的胶片感',
    );
    await tester.pump();
    final submit = find.byKey(const ValueKey('style-definition-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await _completeSheet(tester);

    expect(result?.origin, StyleDefinitionOrigin.text);
    expect(result?.title, '温暖的胶片感');
  });

  testWidgets('voice transcript is shown and only confirmed on submit', (
    tester,
  ) async {
    StyleDefinition? result;
    await tester.pumpWidget(
      _host(
        sheet: () => StyleDefinitionInputSheet(
          sourcePath: '/tmp/source.jpg',
          importer: FakePhotoImporter(),
          transcriber: const _FakeSpeechTranscriber('rainy cinema'),
          preparePrompt: (prompt, origin) async =>
              _definition(origin: origin, id: 'voice-style-v1', title: prompt),
          prepareReference: (_) async => null,
        ),
        onResult: (value) => result = value,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-input-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style-voice-record')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('style-definition-prompt')),
          )
          .controller!
          .text,
      'rainy cinema',
    );
    expect(result, isNull);

    await tester.tap(find.byKey(const ValueKey('style-definition-submit')));
    await _completeSheet(tester);
    expect(result?.origin, StyleDefinitionOrigin.voice);
    expect(result?.sourceText, 'rainy cinema');
  });

  testWidgets('reference selection keeps source and reference roles separate', (
    tester,
  ) async {
    const referencePath = 'assets/branding/yingjian-app-icon-1024-v5.png';
    final sha = 'a' * 64;
    final importer = FakePhotoImporter([
      ProjectPhoto(
        id: 'reference-photo',
        localPath: referencePath,
        originalName: 'reference.jpg',
        contentSha256: sha,
      ),
    ]);
    StyleDefinition? result;
    await tester.pumpWidget(
      _host(
        sheet: () => StyleDefinitionInputSheet(
          sourcePath: referencePath,
          importer: importer,
          transcriber: const _FakeSpeechTranscriber(''),
          preparePrompt: (_, _) async => null,
          prepareReference: (resource) async => _definition(
            origin: StyleDefinitionOrigin.reference,
            id: 'reference-style-v1',
            title: '参考光色',
            fingerprint: resource.descriptor.contentSha256,
          ),
        ),
        onResult: (value) => result = value,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('style-input-reference')));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('style-reference-choose')));
    await _pumpUi(tester);

    expect(
      find.byKey(const ValueKey('style-reference-source')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('style-reference-image')), findsOneWidget);
    expect(importer.editingResourceImportCount, 1);

    final submit = find.byKey(const ValueKey('style-definition-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await _completeSheet(tester);

    expect(result?.origin, StyleDefinitionOrigin.reference);
    expect(result?.referenceFingerprint, sha);
    expect(importer.discardedEditingResourceIds, hasLength(1));
  });
}

Widget _host({
  required Widget Function() sheet,
  required ValueChanged<StyleDefinition?> onResult,
}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: FilledButton(
          key: const ValueKey('open-sheet'),
          onPressed: () async {
            onResult(
              await showModalBottomSheet<StyleDefinition>(
                context: context,
                isScrollControlled: true,
                builder: (_) => sheet(),
              ),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

StyleDefinition _definition({
  required StyleDefinitionOrigin origin,
  required String id,
  required String title,
  String? fingerprint,
}) => StyleDefinition(
  styleId: id,
  revision: 1,
  origin: origin,
  title: title,
  summary: 'A bounded test style.',
  recipe: EditRecipe.neutral,
  sourceText: switch (origin) {
    StyleDefinitionOrigin.text || StyleDefinitionOrigin.voice => title,
    _ => null,
  },
  referenceFingerprint: fingerprint,
);

Future<void> _completeSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.idle();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

final class _FakeSpeechTranscriber implements SpeechTranscriber {
  const _FakeSpeechTranscriber(this.transcript);

  final String transcript;

  @override
  Future<String> start({required String localeIdentifier}) async => transcript;

  @override
  Future<void> stop() async {}
}
