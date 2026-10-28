import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/cost_calculator.dart';
import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/primary_supplier.dart';

void main() {
  final suppliers = [
    Supplier(id: 1, name: 'Alpha', createdAt: DateTime(2026)),
    Supplier(id: 2, name: 'Beta', createdAt: DateTime(2026)),
  ];

  test('resolvePrimarySupplierId falls back to first', () {
    expect(resolvePrimarySupplierId(ProjectDocumentation(), suppliers), 1);
  });

  test('resolvePrimarySupplierId uses preferred when present', () {
    final doc = ProjectDocumentation(primarySupplierId: 2);
    expect(resolvePrimarySupplierId(doc, suppliers), 2);
  });

  test('resolvePrimarySupplierId falls back when preferred missing', () {
    final doc = ProjectDocumentation(primarySupplierId: 99);
    expect(resolvePrimarySupplierId(doc, suppliers), 1);
  });

  test('resolvePrimarySupplierId empty list is null', () {
    expect(resolvePrimarySupplierId(ProjectDocumentation(), []), isNull);
  });
}
