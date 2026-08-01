import 'package:flutter/material.dart';
import 'package:yingjian/app/navigation/app_router.dart';
import 'package:yingjian/app/theme/app_theme.dart';

class YingjianApp extends StatelessWidget {
  const YingjianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '映见',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
