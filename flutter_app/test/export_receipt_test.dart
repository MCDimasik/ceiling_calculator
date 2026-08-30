import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/product_aliases.dart';
import 'package:ceiling_calculator/domain/project_export.dart';
import 'package:ceiling_calculator/domain/receipt_import.dart';

void main() {
  test('ccproj round-trip', () {
    final project = Project(
      name: 'Офис',
      materialsCeiling: 'Армстронг',
      materialsSusp: 'Подвес 0,5',
    );
    project.rooms.add(Room(
      name: 'Зал',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
      lightFixtures: [
        [1, 2],
      ],
      gridOffsetX: 10,
    ));
    final json = encodeProjectFile(project);
    final back = decodeProjectFile(json);
    expect(back.name, 'Офис');
    expect(back.rooms.length, 1);
    expect(back.rooms.first.walls.length, 4);
    expect(back.rooms.first.lightFixtures.first, [1, 2]);
    expect(back.rooms.first.gridOffsetX, 10);
  });

  test('alias matches baikal tile', () {
    final hit = matchProductAlias('Плита Армстронг Байкал 600');
    expect(hit?.itemKey, 'armstrong_baikal');
  });

  test('parse receipt text finds prices', () {
    const text = 'Сатурн\nПлита Армстронг Байкал 1250,00\nПодвес 0,5 м 45.50\nИтого 100';
    final parsed = parseReceiptText(text);
    expect(parsed.supplierName, 'Сатурн');
    expect(parsed.items.length, 2);
    expect(parsed.items.first.unitPrice, 1250);
  });
}
