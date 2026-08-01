import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/app.dart';
import 'package:yingjian/app/settings/app_settings.dart';

void main() {
  testWidgets('user can see the Yingjian starting action', (tester) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: const YingjianApp(),
      ),
    );

    expect(find.text('映见'), findsOneWidget);
    expect(find.text('一张精修，整组好看'), findsOneWidget);
    expect(find.text('开始修图'), findsOneWidget);

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    expect(find.text('精修工作台'), findsOneWidget);
    expect(find.text('照片预览区域'), findsOneWidget);
  });

  testWidgets('follows a persisted English locale', (tester) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'en'});
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: const YingjianApp(),
      ),
    );

    expect(find.text('Yingjian'), findsOneWidget);
    expect(find.text('Start editing'), findsOneWidget);
  });
}
