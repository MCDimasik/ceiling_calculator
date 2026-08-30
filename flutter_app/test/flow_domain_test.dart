import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/admin_access.dart';
import 'package:ceiling_calculator/domain/cost_calculator.dart';
import 'package:ceiling_calculator/domain/finish_model.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/project_materials.dart';
import 'package:ceiling_calculator/domain/room_draft.dart';

void main() {
  test('RoomDraft builds closed rectangle', () {
    final d = RoomDraft();
    d.addWall('right', 400);
    d.addWall('up', 300);
    d.addWall('left', 400);
    d.addWall('down', 300);
    expect(d.isClosed, isTrue);
    expect(d.walls.length, 4);
  });

  test('aggregate materials for armstrong room', () {
    final project = Project(name: 'P', materialsCeiling: 'Армстронг', materialsSusp: 'Подвес 0,5');
    final room = Room(
      name: 'R',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
    );
    project.rooms.add(room);
    final mats = calculateRoomMaterials(room, project);
    expect(mats.containsKey('Плиты/кассеты (Армстронг)'), isTrue);
    expect(mats['Подвес (0,5)'], greaterThan(0));
  });

  test('cost marks missing prices', () {
    final project = Project(name: 'P', materialsCeiling: 'Армстронг');
    project.rooms.add(Room(
      name: 'R',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
    ));
    final cost = calculateProjectCost(project, {});
    expect(cost.missingCount, greaterThan(0));
    expect(cost.total, 0);
  });

  test('admin rejects wrong password', () async {
    final admin = AdminAccess();
    expect(await admin.tryUnlock('wrong'), isFalse);
  });

  test('finish areas subtract openings', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final areas = FinishCalculator.compute(
      walls: walls,
      heightCm: 270,
      openings: [
        RoomOpening(kind: 'door', widthCm: 90, heightCm: 210, quantity: 2),
      ],
    );
    expect(areas.floorM2, closeTo(12.0, 0.01));
    expect(areas.ceilingM2, closeTo(12.0, 0.01));
    expect(areas.openingsM2, closeTo(3.78, 0.01));
    expect(areas.wallsNetM2, lessThan(areas.wallsGrossM2));
  });

  test('wall finish layers paint coats and tile', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final areas = FinishCalculator.compute(
      walls: walls,
      heightCm: 270,
      openings: const [],
      wallLayers: [
        FinishLayer(kind: FinishLayerKind.plaster),
        FinishLayer(kind: FinishLayerKind.paint, paintCoats: 2),
        FinishLayer(kind: FinishLayerKind.tile, tileWidthCm: 30, tileHeightCm: 30),
      ],
    );
    expect(areas.wallLayers.length, 3);
    expect(areas.wallLayers[0].areaM2, closeTo(areas.wallsNetM2, 0.01));
    expect(areas.wallLayers[1].areaM2, closeTo(areas.wallsNetM2 * 2, 0.01));
    expect(areas.wallLayers[2].tilesEstimate, greaterThan(0));
  });
}
