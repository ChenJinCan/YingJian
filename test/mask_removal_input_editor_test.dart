import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/generation/application/mask_removal_input_builder.dart';
import 'package:yingjian/features/generation/domain/generation_input.dart';
import 'package:yingjian/features/generation/presentation/mask_removal_input_editor.dart';
import 'package:yingjian/l10n/app_localizations.dart';

void main() {
  testWidgets('without an explicit stroke the mask cannot be confirmed', (
    tester,
  ) async {
    final creator = _RecordingInputCreator();
    await tester.pumpWidget(_host(creator));

    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mask-removal-confirm')),
    );
    expect(confirm.onPressed, isNull);
    expect(creator.calls, isEmpty);
  });

  testWidgets('drawing explicitly returns only the user painted stroke', (
    tester,
  ) async {
    final creator = _RecordingInputCreator();
    MaskRemovalGenerationInput? result;
    await tester.pumpWidget(
      _host(creator, onConfirmed: (value) => result = value),
    );

    await tester.tap(find.byKey(const ValueKey('mask-removal-canvas')));
    await tester.pump();
    final confirm = find.byKey(const ValueKey('mask-removal-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(creator.calls, hasLength(1));
    expect(creator.calls.single.pixelWidth, 1200);
    expect(creator.calls.single.pixelHeight, 800);
    expect(creator.calls.single.strokes, hasLength(1));
    expect(
      creator.calls.single.strokes.single.operation,
      MaskBrushOperation.paint,
    );
    expect(result, same(creator.result));
  });

  testWidgets('undo and clear remove confirmation authority', (tester) async {
    final creator = _RecordingInputCreator();
    await tester.pumpWidget(_host(creator));
    final canvas = find.byKey(const ValueKey('mask-removal-canvas'));
    final confirm = find.byKey(const ValueKey('mask-removal-confirm'));

    await tester.tap(canvas);
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('mask-removal-undo')));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(canvas);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mask-removal-clear')));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(creator.calls, isEmpty);
  });

  testWidgets('essential controls remain laid out at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(_RecordingInputCreator(), textScaler: const TextScaler.linear(2)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('mask-removal-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('mask-removal-undo')), findsOneWidget);
    expect(find.byKey(const ValueKey('mask-removal-clear')), findsOneWidget);
    expect(find.byKey(const ValueKey('mask-removal-confirm')), findsOneWidget);
  });
}

Widget _host(
  MaskRemovalInputCreator creator, {
  ValueChanged<MaskRemovalGenerationInput>? onConfirmed,
  TextScaler? textScaler,
}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: textScaler == null
      ? null
      : (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: MaskRemovalInputEditor(
        sourcePath: '/a/read-only/source.jpg',
        sourcePixelWidth: 1200,
        sourcePixelHeight: 800,
        inputCreator: creator,
        onConfirmed: onConfirmed ?? (_) {},
      ),
    ),
  ),
);

final class _RecordingInputCreator implements MaskRemovalInputCreator {
  final calls =
      <({int pixelWidth, int pixelHeight, List<MaskStroke> strokes})>[];
  final result = MaskRemovalGenerationInput(
    maskPath: '/app-support/mask.png',
    maskSha256: 'a' * 64,
  );

  @override
  Future<MaskRemovalGenerationInput> create({
    required int pixelWidth,
    required int pixelHeight,
    required List<MaskStroke> strokes,
  }) async {
    calls.add((
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      strokes: List.unmodifiable(strokes),
    ));
    return result;
  }
}
