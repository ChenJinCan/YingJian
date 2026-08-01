import 'package:flutter/material.dart';
import 'package:yingjian/features/editor/presentation/editor_page.dart';
import 'package:yingjian/features/home/presentation/home_page.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const editor = '/editor';
}

abstract final class AppRouter {
  static Route<void> onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      AppRoutes.home => _page(const HomePage(), settings),
      AppRoutes.editor => _page(const EditorPage(), settings),
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
      appBar: AppBar(title: const Text('页面不存在')),
      body: const Center(child: Text('暂时无法打开这个页面')),
    );
  }
}
