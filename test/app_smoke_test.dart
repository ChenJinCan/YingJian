import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/main.dart';

void main() {
  testWidgets('user can see the Yingjian starting action', (tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('映见'), findsOneWidget);
    expect(find.text('一张精修，整组好看'), findsOneWidget);
    expect(find.text('开始修图'), findsOneWidget);
  });
}
