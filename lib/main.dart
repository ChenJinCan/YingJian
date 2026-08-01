import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/app.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/startup/startup_coordinator.dart';

void main() {
  runZonedGuarded(_startApplication, _reportStartupError);
}

Future<void> _startApplication() async {
  WidgetsFlutterBinding.ensureInitialized();
  late AppSettings settings;

  final startup = StartupCoordinator(
    prepareApp: () async {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
      );
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
      settings = await AppSettings.load();
    },
    showApp: () {
      runApp(
        ChangeNotifierProvider<AppSettings>.value(
          value: settings,
          child: const YingjianApp(),
        ),
      );
    },
  );

  await startup.start();
}

void _reportStartupError(Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'application_startup',
    ),
  );
}
