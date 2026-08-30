import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Material smoke', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Ceiling Calculator'))),
    );
    expect(find.text('Ceiling Calculator'), findsOneWidget);
  });
}
