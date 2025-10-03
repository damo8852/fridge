// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fridge/main.dart'; // adjust to your actual package name

void main() {
  testWidgets('app builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const FridgeApp());
    expect(find.text('Fridge'), findsOneWidget); // From AppBar title in HomePage
  });
}
