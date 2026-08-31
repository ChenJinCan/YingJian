import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/features/creation/domain/creation_intent.dart';
import 'package:yingjian/features/creation/presentation/style_workspace_page.dart';
import 'package:yingjian/features/editor/presentation/editor_page.dart';
import 'package:yingjian/features/home/presentation/home_page.dart';
import 'package:yingjian/features/onboarding/presentation/onboarding_page.dart';
import 'package:yingjian/features/settings/presentation/legal_document_page.dart';
import 'package:yingjian/features/settings/presentation/settings_page.dart';
import 'package:yingjian/l10n/l10n.dart';

abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const home = '/';
  static const editor = '/editor';
  static const applyStyleWorkspace = '/create/apply';
  static const motionStyleWorkspace = '/create/motion';
  static const settings = '/settings';
  static const privacy = '/settings/privacy';
  static const terms = '/settings/terms';
}

abstract final class AppRouter {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static Route<void> onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      AppRoutes.onboarding => _page(const OnboardingPage(), settings),
      AppRoutes.home => _page(_creationSurface(const HomePage()), settings),
      AppRoutes.editor => _page(
        EditorPage(startWithImport: settings.arguments == true),
        settings,
      ),
      AppRoutes.applyStyleWorkspace => _iosPage(
        _creationSurface(
          StyleWorkspacePage(
            intent: CreationIntent.apply,
            projectId: settings.arguments as String?,
          ),
        ),
        settings,
      ),
      AppRoutes.motionStyleWorkspace => _iosPage(
        _creationSurface(
          StyleWorkspacePage(
            intent: CreationIntent.motion,
            projectId: settings.arguments as String?,
          ),
        ),
        settings,
      ),
      AppRoutes.settings => _page(const SettingsPage(), settings),
      AppRoutes.privacy => _page(
        const LegalDocumentPage(type: LegalDocumentType.privacy),
        settings,
      ),
      AppRoutes.terms => _page(
        const LegalDocumentPage(type: LegalDocumentType.terms),
        settings,
      ),
      _ => _page(const UnknownRoutePage(), settings),
    };
  }

  static MaterialPageRoute<void> _page(Widget child, RouteSettings settings) {
    return MaterialPageRoute<void>(settings: settings, builder: (_) => child);
  }

  static CupertinoPageRoute<void> _iosPage(
    Widget child,
    RouteSettings settings,
  ) => CupertinoPageRoute<void>(settings: settings, builder: (_) => child);

  static Widget _creationSurface(Widget child) =>
      Theme(data: AppTheme.dark, child: child);
}

class UnknownRoutePage extends StatelessWidget {
  const UnknownRoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.unknownPageTitle)),
      body: Center(child: Text(context.l10n.unknownPageMessage)),
    );
  }
}
