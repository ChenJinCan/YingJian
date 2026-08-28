import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/presentation/visual_tracks_page.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/l10n/app_localizations.dart';

import 'support/test_services.dart';

void main() {
  testWidgets(
    'redesigned visual track journey previews, commits, and selects a person',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var committed = EditRecipe.neutral;
      final editorSession = EditorSession();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: ThemeData.dark(useMaterial3: true),
          home: VisualTracksPage(
            photo: const ProjectPhoto(
              id: 'photo-1',
              localPath:
                  'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
                  'Icon-App-1024x1024@1x.png',
              originalName: 'fixture.png',
            ),
            initialRecipe: EditRecipe.neutral,
            editorSession: editorSession,
            previewRenderer: FakePhotoPreviewRenderer.supported(),
            faceTargets: const [
              StableEditTarget(
                id: 'face-1',
                photoId: 'photo-1',
                kind: EditTargetKind.face,
                analysisVersion: 'test-v1',
                bindingFingerprint: 'face-1-binding',
                region: NormalizedEditRegion(
                  left: 0.08,
                  top: 0.18,
                  right: 0.42,
                  bottom: 0.62,
                ),
                status: EditTargetStatus.active,
              ),
              StableEditTarget(
                id: 'face-2',
                photoId: 'photo-1',
                kind: EditTargetKind.face,
                analysisVersion: 'test-v1',
                bindingFingerprint: 'face-2-binding',
                region: NormalizedEditRegion(
                  left: 0.56,
                  top: 0.2,
                  right: 0.9,
                  bottom: 0.64,
                ),
                status: EditTargetStatus.active,
              ),
            ],
            editStateFor: (_) => EditState.empty,
            editContext: const EditContext(
              platform: EditPlatform.ios,
              photoIds: {'photo-1'},
              targetIds: {'face-1', 'face-2'},
              applicability: {'photo', 'face'},
            ),
            onCommit: (recipe) async {
              committed = recipe;
              return recipe;
            },
            onUndo: () async {
              committed = EditRecipe.neutral;
              return committed;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('visual-tracks-page')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('visual-tracks-open-era')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('visual-tracks-open-era')));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey('era-arc-track')),
        const Offset(-90, 0),
      );
      await tester.pumpAndSettle();
      expect(committed, isNot(EditRecipe.neutral));
      expect(
        find.byKey(const ValueKey('visual-tracks-continue')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('visual-tracks-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('visual-track-lighting-tab')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('lighting-overlay-target-0')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('lighting-overlay-target-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lighting-arc-track')), findsOneWidget);
    },
  );
}
