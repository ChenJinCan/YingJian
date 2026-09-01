import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yingjian/app/navigation/app_router.dart';
import 'package:yingjian/observability/app_observability.dart';

final class AppNavigatorObserver extends NavigatorObserver {
  AppNavigatorObserver(this._observability);

  final AppObservability _observability;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _track(newRoute?.settings.name);
  }

  void _track(String? routeName) {
    final screen = switch (routeName) {
      AppRoutes.home => 'home',
      AppRoutes.applyStyleWorkspace => 'apply_style_workspace',
      AppRoutes.motionStyleWorkspace => 'motion_style_workspace',
      AppRoutes.settings => 'settings',
      AppRoutes.privacy => 'privacy_policy',
      AppRoutes.terms => 'terms_of_use',
      _ => 'unknown',
    };
    unawaited(_observability.trackScreen(screen));
  }
}
