import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/finish_model.dart';
import 'package:ceiling_calculator/domain/finish_vedomost.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/project_materials.dart';
import 'package:ceiling_calculator/domain/vedomost_export.dart';

void main() {
  final rectWalls = [
    [0.0, 0.0, 600.0, 0.0],
    [600.0, 0.0, 600.0, 600.0],
    [600.0, 600.0, 0.0, 600.0],
    [0.0, 600.0, 0.0, 0.0],
  ];

  test('opening effective area caps quantity on short wall', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 400.0],
      [400.0, 400.0, 0.0, 400.0],
      [0.0, 400.0, 0.0, 0.0],
    ];
    final opening = RoomOpening(
      kind: 'door',
      widthCm: 100,
      heightCm: 210,
      quantity: 5,
      wallIndex: 0,
      offsetAlongWallCm: 0,
    );
    expect(opening.areaM2, closeTo(10.5, 0.01));
    final area = opening.effectiveAreaM2(walls);
    expect(area, closeTo(8.4, 0.01));
  });

  test('floor tile count matches layout builder', () {
    final room = Room(
      name: 'R',
      walls: rectWalls,
      finishTileWidthCm: 60,
      finishTileHeightCm: 60,
    );
    final layoutCount = floorBoardCountForRoom(room);
    final areas = FinishCalculator.compute(
      walls: room.walls,
      heightCm: 270,
      openings: const [],
      tileWidthCm: 60,
      tileHeightCm: 60,
      floorLayoutBoardCount: layoutCount,
    );
    expect(areas.floorTiles, layoutCount);
    expect(layoutCount, greaterThan(0));
  });

  test('ceiling tile estimate uses grilyato cell size', () {
    final areas = FinishCalculator.compute(
      walls: rectWalls,
      heightCm: 270,
      openings: const [],
      ceilingCellCm: 50,
    );
    final armstrong = FinishCalculator.compute(
      walls: rectWalls,
      heightCm: 270,
      openings: const [],
      ceilingCellCm: 60,
    );
    expect(areas.ceilingTiles, greaterThan(armstrong.ceilingTiles));
  });

  test('vedomost does not duplicate ceiling purchase line', () {
    final project = Project(name: 'P', materialsCeiling: 'Армстронг');
    final room = Room(name: 'R', walls: rectWalls, layoutConfirmed: true);
    final text = buildVedomostText(
      project: project,
      room: room,
      stamp: DocumentationStamp(),
    );
    final finishPart = text.split('=== ОТДЕЛКА').last;
    expect(finishPart, isNot(contains('Кассеты/плиты (закупка)')));
    expect(text, contains('=== ПОТОЛОК'));
    expect(text, contains('=== ОТДЕЛКА'));
  });

  test('layout tile is always 600 mm; grilyato inner cell is in mm label', () {
    expect(ceilingCellCm('Грильято', '50x50'), layoutTileCm);
    expect(ceilingCellCm('Армстронг', '50x50'), layoutTileCm);
    expect(grilyatoSubdivisionsPerTile('75x75'), 8);
    expect(grilyatoSubdivisionsPerTile('50x50'), 12);
  });

  test('aggregateFinishVedomostLines sums floor area across rooms', () {
    Room rectRoom(String name) => Room(
          name: name,
          walls: rectWalls,
        );
    final project = Project(
      name: 'P',
      rooms: [rectRoom('A'), rectRoom('B')],
    );
    final lines = aggregateFinishVedomostLines(project);
    final floorArea = lines.firstWhere(
      (l) => l.section == 'Пол' && l.name == 'Площадь',
    );
    expect(double.parse(floorArea.quantity.replaceAll(',', '.')), closeTo(72, 0.1));
  });
}
