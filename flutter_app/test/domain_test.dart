import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/ceiling_grid.dart';
import 'package:ceiling_calculator/domain/materials_calculator.dart';

void main() {
  group('MaterialsCalculator', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];

    test('room area 4x3 m = 12 m2', () {
      expect(MaterialsCalculator.roomAreaM2(walls), closeTo(12.0, 1e-6));
    });

    test('armstrong has plates and guides', () {
      final r = MaterialsCalculator.calculate(
        type: CeilingType.armstrong,
        walls: walls,
        cassetteCount: 34,
        lightCount: 2,
      );
      expect(r['Светильники'], 2);
      expect(r['Плиты/кассеты'], 32);
      expect(r.containsKey('Направляющая 3600'), isTrue);
    });
  });

  group('CeilingGrid', () {
    test('rebuilds cells for rectangle room', () {
      final walls = [
        [0.0, 0.0, 300.0, 0.0],
        [300.0, 0.0, 300.0, 240.0],
        [300.0, 240.0, 0.0, 240.0],
        [0.0, 240.0, 0.0, 0.0],
      ];
      final grid = CeilingGrid(cellSizeCm: 60);
      grid.rebuild(roomPoints: [
        (0, 0),
        (300, 0),
        (300, 240),
        (0, 240),
      ], walls: walls);
      expect(grid.cells, isNotEmpty);
      expect(grid.fullTiles + grid.cutTiles, grid.cells.length);
      expect(grid.verticalLines, isNotEmpty);
    });

    test('toggle light reduces effective tiles', () {
      final walls = [
        [0.0, 0.0, 120.0, 0.0],
        [120.0, 0.0, 120.0, 120.0],
        [120.0, 120.0, 0.0, 120.0],
        [0.0, 120.0, 0.0, 0.0],
      ];
      final grid = CeilingGrid(cellSizeCm: 60);
      grid.rebuild(roomPoints: [
        (0, 0),
        (120, 0),
        (120, 120),
        (0, 120),
      ], walls: walls);
      final before = grid.effectiveTileCounts;
      final cell = grid.cells.firstWhere((c) => c.kind == CellKind.full);
      grid.toggleLight(cell.col, cell.row);
      final after = grid.effectiveTileCounts;
      expect(after.$1 + after.$2, before.$1 + before.$2 - 1);
      expect(grid.lightCount, 1);
    });

    test('rebuild LRU returns identical counts', () {
      CeilingGrid.clearRebuildCache();
      final points = <(double, double)>[(0, 0), (300, 0), (300, 240), (0, 240)];
      final walls = [
        [0.0, 0.0, 300.0, 0.0],
        [300.0, 0.0, 300.0, 240.0],
        [300.0, 240.0, 0.0, 240.0],
        [0.0, 240.0, 0.0, 0.0],
      ];
      final a = CeilingGrid(cellSizeCm: 60, offsetXCm: 10, offsetYCm: 20);
      a.rebuild(roomPoints: points, walls: walls);
      final full = a.fullTiles;
      final cut = a.cutTiles;
      final cellCount = a.cells.length;
      expect(CeilingGrid.rebuildCacheLength, 1);

      final b = CeilingGrid(cellSizeCm: 60, offsetXCm: 10, offsetYCm: 20);
      b.rebuild(roomPoints: points, walls: walls);
      expect(b.fullTiles, full);
      expect(b.cutTiles, cut);
      expect(b.cells.length, cellCount);
      expect(CeilingGrid.rebuildCacheLength, 1);
    });
  });
}
