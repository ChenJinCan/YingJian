import 'package:flutter/material.dart';
import 'package:yingjian/features/editor/presentation/editor_page.dart';
import 'package:yingjian/features/home/presentation/home_page.dart';
import 'package:yingjian/features/settings/presentation/legal_document_page.dart';
import 'package:yingjian/features/settings/presentation/settings_page.dart';
import 'package:yingjian/l10n/l10n.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const editor = '/editor';
  static const settings = '/settings';
  static const privacy = '/settings/privacy';
  static const terms = '/settings/terms';
}

abstract final class AppRouter {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static Route<void> onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      AppRoutes.home => _page(const HomePage(), settings),
      AppRoutes.editor => _page(const EditorPage(), settings),
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
