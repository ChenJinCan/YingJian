import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/features/creation/domain/creation_intent.dart';
import 'package:yingjian/features/creation/domain/creation_task.dart';
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
  static const optimizeWorkspace = '/create/optimize';
  static const applyStyleWorkspace = '/create/apply';
  static const cleanupWorkspace = '/create/cleanup';
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
      AppRoutes.optimizeWorkspace => _iosPage(
        _creationSurface(
          EditorPage(
            projectId: _projectIdForTask(
              settings.arguments,
              CreationTask.optimize,
            ),
            entryPoint: EditorEntryPoint.optimize,
          ),
        ),
        settings,
      ),
      AppRoutes.applyStyleWorkspace => _iosPage(
        _creationSurface(
          StyleWorkspacePage(
            intent: CreationIntent.apply,
            task: CreationTask.style,
            projectId: _projectIdForTask(
              settings.arguments,
              CreationTask.style,
            ),
          ),
        ),
        settings,
      ),
      AppRoutes.cleanupWorkspace => _iosPage(
        _creationSurface(
          EditorPage(
            projectId: _projectIdForTask(
              settings.arguments,
              CreationTask.cleanup,
            ),
            entryPoint: EditorEntryPoint.cleanup,
          ),
        ),
        settings,
      ),
      AppRoutes.motionStyleWorkspace => _iosPage(
        _creationSurface(
          StyleWorkspacePage(
            intent: CreationIntent.motion,
            task: CreationTask.motion,
            projectId: _projectIdForTask(
              settings.arguments,
              CreationTask.motion,
            ),
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

  /// Binds each task route to one concrete user goal.
  ///
  /// A [CreationRouteArguments] object is created by Home when resuming a
  /// draft. Reject a mismatched goal here instead of letting an arbitrary
  /// route argument change the destination workspace. The string case keeps
  /// old in-process callers working; [EditorPage] validates the restored
  /// project against its entry point as a second boundary.
  static String? _projectIdForTask(
    Object? arguments,
    CreationTask expectedTask,
  ) => switch (arguments) {
    CreationRouteArguments(:final projectId, :final task)
        when task == expectedTask =>
      projectId,
    CreationRouteArguments(:final task) => throw ArgumentError.value(
      task,
      'task',
      'The task does not match this creation route.',
    ),
    String projectId => projectId,
    _ => null,
  };
}

class CreationRouteArguments {
  const CreationRouteArguments({required this.projectId, required this.task});

  final String projectId;
  final CreationTask task;
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
