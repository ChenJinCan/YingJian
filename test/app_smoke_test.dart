import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/app/app.dart';

void main() {
  testWidgets('user can see the Yingjian starting action', (tester) async {
    await tester.pumpWidget(const YingjianApp());

    expect(find.text('映见'), findsOneWidget);
    expect(find.text('一张精修，整组好看'), findsOneWidget);
    expect(find.text('开始修图'), findsOneWidget);

    await tester.tap(find.text('开始修图'));
    await tester.pumpAndSettle();

    expect(find.text('精修工作台'), findsOneWidget);
    expect(find.text('照片预览区域'), findsOneWidget);
  });
}
