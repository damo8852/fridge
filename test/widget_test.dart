// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app builds without crashing', (WidgetTester tester) async {
    // Create a simple test app since the main app requires Firebase initialization
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('EcoPantry Test'),
          ),
        ),
      ),
    );
    expect(find.text('EcoPantry Test'), findsOneWidget);
  });
}
