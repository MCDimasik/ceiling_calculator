import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/ui/widgets/ks2_closure_legend.dart';

void main() {
  testWidgets('Ks2ClosureLegend shows glyph legend', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Ks2ClosureLegend())),
    );
    expect(find.textContaining('готово'), findsOneWidget);
    expect(find.textContaining('закрыто'), findsOneWidget);
  });
}
