import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/materials_calculator.dart';
import 'package:ceiling_calculator/domain/ceiling_guides.dart';
import 'package:ceiling_calculator/domain/ceiling_grid.dart';
import 'package:ceiling_calculator/domain/project_materials.dart';

void main() {
  final walls4x3 = [
    [0.0, 0.0, 400.0, 0.0],
    [400.0, 0.0, 400.0, 300.0],
    [400.0, 300.0, 0.0, 300.0],
    [0.0, 300.0, 0.0, 0.0],
  ];

  final walls10x10 = [
    [0.0, 0.0, 1000.0, 0.0],
    [1000.0, 0.0, 1000.0, 1000.0],
    [1000.0, 1000.0, 0.0, 1000.0],
    [0.0, 1000.0, 0.0, 0.0],
  ];

  test('supplier-style area count: 10×10 m → 278 cassettes', () {
    expect(MaterialsCalculator.cassetteCountFromArea(walls10x10), 278);
    expect(MaterialsCalculator.roomAreaM2(walls10x10), closeTo(100.0, 0.01));
  });

  test('4×3 m area count is 34 not grid 7×5=35', () {
    expect(MaterialsCalculator.cassetteCountFromArea(walls4x3), 34);
  });

  test('layout pack for 10×10 matches area 278', () {
    final grid = CeilingGrid(cellSizeCm: 60);
    grid.rebuild(
      roomPoints: pointsFromWalls(walls10x10),
      walls: walls10x10,
      lightIds: const {},
    );
    // Naive full+cut is inflated (289).
    expect(grid.fullTiles + grid.cutTiles, greaterThan(278));

    final n = MaterialsCalculator.estimatePurchaseCassettes(
      walls: walls10x10,
      layoutTiles: grid.cells
          .where((c) => c.kind == CellKind.full || c.kind == CellKind.cut)
          .map((c) => (
                isFull: c.kind == CellKind.full,
                cutXCm: c.cutXCm,
                cutYCm: c.cutYCm,
              )),
    );
    expect(n, 278);
  });

  test('crumb cuts under 3 cm are ignored in packing', () {
    final n = MaterialsCalculator.estimatePurchaseCassettes(
      walls: walls4x3,
      layoutTiles: const [
        (isFull: true, cutXCm: 60, cutYCm: 60),
        (isFull: true, cutXCm: 60, cutYCm: 60),
        (isFull: false, cutXCm: 1, cutYCm: 60), // crumb
        (isFull: false, cutXCm: 30, cutYCm: 60), // 0.5 tile
        (isFull: false, cutXCm: 30, cutYCm: 60), // 0.5 tile → 1 packed
      ],
    );
    // area baseline 34 dominates; packing alone would be 2+1=3
    expect(n, 34);
  });

  test('grilyato mama/papa = cassettes × cell factor', () {
    final n = MaterialsCalculator.cassetteCountFromArea(walls4x3);
    expect(n, 34);

    final gl100 = MaterialsCalculator.calcGrilyatoGl(walls4x3, n, '100x100');
    expect(gl100['Профиль Папа'], 34 * 5);
    expect(gl100['Профиль Мама'], 34 * 5);
    expect(gl100['Заглушки'], 34 * 4);

    final gl75 = MaterialsCalculator.calcGrilyatoGl(walls4x3, n, '75x75');
    expect(gl75['Профиль Папа'], 34 * 7);

    final gl50 = MaterialsCalculator.calcGrilyatoGl(walls4x3, n, '50x50');
    expect(gl50['Профиль Папа'], 34 * 11);

    final classic = MaterialsCalculator.calcGrilyatoClassic(walls4x3, n, '100x100');
    expect(classic['Профиль Папа'], 34 * 5);
    expect(classic['Подвес'], classic['Направляющая 2400']! * 3);
  });

  test('guide overrides use ×3 hangers for classic 2400', () {
    final raw = MaterialsCalculator.calcGrilyatoClassic(walls4x3, 34, '100x100');
    final adjusted = applyGuideOverrides(
      raw,
      {'Направляющая 2400': 10, 'Направляющая 1200': 20, 'Направляющая 600': 15},
      type: CeilingType.grilyatoClassic,
    );
    expect(adjusted['Направляющая 2400'], 10);
    expect(adjusted['Подвес'], 30);
    expect(adjusted['Соединитель'], 10);
  });
}
