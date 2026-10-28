import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/finish_model.dart';
import 'package:ceiling_calculator/domain/finish_quantities.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/opening_remap.dart';
import 'package:ceiling_calculator/domain/pdf_plan_import.dart';
import 'package:ceiling_calculator/domain/project_materials.dart';
import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/vedomost_export.dart';

void main() {
  final rect = [
    [0.0, 0.0, 400.0, 0.0],
    [400.0, 0.0, 400.0, 300.0],
    [400.0, 300.0, 0.0, 300.0],
    [0.0, 300.0, 0.0, 0.0],
  ];

  test('hasLayout requires closed contour', () {
    final open = Room(
      name: 'O',
      walls: [
        [0.0, 0.0, 400.0, 0.0],
        [400.0, 0.0, 400.0, 300.0],
        [400.0, 300.0, 0.0, 300.0],
      ],
    );
    expect(open.hasLayout, isFalse);
    expect(wallsFormClosedPolygon(open.walls), isFalse);

    final closed = Room(name: 'C', walls: rect);
    expect(closed.hasLayout, isTrue);
    expect(wallsFormClosedPolygon(closed.walls), isTrue);
  });

  test('remapOpeningsToWalls rebinds mid-point to nearest new wall', () {
    final openings = [
      RoomOpening(
        kind: 'door',
        widthCm: 90,
        heightCm: 210,
        wallIndex: 0,
        offsetAlongWallCm: 100,
      ),
    ];
    // Shrink room — old wall 0 mid should still land near new bottom wall.
    final smaller = [
      [0.0, 0.0, 300.0, 0.0],
      [300.0, 0.0, 300.0, 250.0],
      [250.0, 250.0, 0.0, 250.0],
      [0.0, 250.0, 0.0, 0.0],
    ];
    final mapped = remapOpeningsToWalls(
      openings: openings,
      oldWalls: rect,
      newWalls: smaller,
    );
    expect(mapped.single.wallIndex, isNotNull);
    expect(mapped.single.widthCm, 90);
  });

  test('remapOpeningsToWalls unplaces when wall gone', () {
    final openings = [
      RoomOpening(
        kind: 'window',
        widthCm: 120,
        heightCm: 140,
        wallIndex: 0,
        offsetAlongWallCm: 50,
      ),
    ];
    final mapped = remapOpeningsToWalls(
      openings: openings,
      oldWalls: rect,
      newWalls: const [],
    );
    expect(mapped.single.wallIndex, isNull);
  });

  test('extractEmbeddedJpegsFromPdf empty for non-image pdf bytes', () {
    final fake = List<int>.generate(64, (i) => i);
    expect(extractEmbeddedJpegsFromPdf(fake), isEmpty);
  });

  test('open contour excluded from trusted BOM / finish qty', () {
    final open = Room(
      name: 'O',
      walls: [
        [0.0, 0.0, 400.0, 0.0],
        [400.0, 0.0, 400.0, 300.0],
        [400.0, 300.0, 0.0, 300.0],
      ],
      finishTileWidthCm: 60,
      finishTileHeightCm: 60,
    );
    final project = Project(name: 'P', rooms: [open]);
    expect(open.hasLayout, isFalse);
    expect(calculateRoomMaterials(open, project), isEmpty);
    expect(floorBoardCountForRoom(open), 0);
    expect(aggregateProjectTotals(project).$2, 0);
  });

  test('vedomost text blocks open contour', () {
    final open = Room(
      name: 'O',
      walls: [
        [0.0, 0.0, 400.0, 0.0],
        [400.0, 0.0, 400.0, 300.0],
        [400.0, 300.0, 0.0, 300.0],
      ],
    );
    final project = Project(name: 'P', rooms: [open]);
    final text = buildVedomostText(
      project: project,
      room: open,
      stamp: DocumentationStamp(),
    );
    expect(text, contains('Нет закрытого чертежа'));
    expect(text, isNot(contains('Площадь пола:')));
  });
}
