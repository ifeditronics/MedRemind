// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:MedRemind/services/ble_service.dart';
import 'package:MedRemind/screens/home_screen.dart';
import 'package:MedRemind/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BLEService()),
        ],
        child: const MedRemindApp(),
      ),
    );

    // Verify that the title or initial screen loads
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
