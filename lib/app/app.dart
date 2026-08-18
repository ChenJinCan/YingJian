import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/navigation/app_router.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/l10n/app_localizations.dart';
import 'package:yingjian/observability/app_navigator_observer.dart';
import 'package:yingjian/observability/app_observability.dart';

class YingjianApp extends StatefulWidget {
  const YingjianApp({super.key});

  @override
  State<YingjianApp> createState() => _YingjianAppState();
}

class _YingjianAppState extends State<YingjianApp> {
  AppObservability? _observability;
  AppNavigatorObserver? _navigatorObserver;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observability = context.read<AppObservability>();
    if (!identical(_observability, observability)) {
      _observability = observability;
      _navigatorObserver = AppNavigatorObserver(observability);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return MaterialApp(
      navigatorKey: AppRouter.navigatorKey,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      locale: settings.locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        AppLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      initialRoute: settings.onboardingComplete
          ? AppRoutes.home
          : AppRoutes.onboarding,
      navigatorObservers: [_navigatorObserver!],
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
