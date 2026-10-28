import 'dart:math' as math;

import 'ceiling_grid.dart';
import 'finish_model.dart';
import 'floor_covering.dart';
import 'floor_layout.dart';
import 'models.dart';
import 'project_materials.dart';
import 'surface_prep_layers.dart';

/// Discrete wall-tile count: sum per-wall elevation layouts (not area estimate).
int wallTileLayoutCountForRoom(Room room) {
  if (!room.hasLayout) return 0;
  FinishLayer? tileLayer;
  for (final raw in room.wallFinishLayers) {
    final l = FinishLayer.fromJson(raw);
    if (l.enabled && l.kind == FinishLayerKind.tile) {
      tileLayer = l;
      break;
    }
  }
  if (tileLayer == null) return 0;

  var total = 0;
  final h = room.ceilingHeightCm;
  for (var wi = 0; wi < room.walls.length; wi++) {
    final w = room.walls[wi];
    final len = math.sqrt(math.pow(w[2] - w[0], 2) + math.pow(w[3] - w[1], 2));
    if (len <= 0 || h <= 0) continue;
    final rect = <List<double>>[
      [0, 0, len, 0],
      [len, 0, len, h],
      [len, h, 0, h],
      [0, h, 0, 0],
    ];
    final grid = CeilingGrid();
    grid.setCellSizeWH(tileLayer.tileWidthCm, tileLayer.tileHeightCm);
    grid.setOffset(tileLayer.tileOffsetX.toDouble(), tileLayer.tileOffsetY.toDouble());
    grid.rebuild(roomPoints: pointsFromWalls(rect), walls: rect);
    total += grid.cells.where((c) => c.kind == CellKind.full || c.kind == CellKind.cut).length;
  }
  return total;
}

/// Ceiling tiles on layout grid (full + cut cells), without purchase waste.
int ceilingLayoutTileCountForRoom(Room room) {
  if (!room.hasLayout) return 0;
  final grid = CeilingGrid(
    offsetXCm: room.gridOffsetX.toDouble(),
    offsetYCm: room.gridOffsetY.toDouble(),
  );
  final lights = <String>{};
  for (final f in room.lightFixtures) {
    if (f.length >= 2) lights.add('${f[0]}:${f[1]}');
  }
  grid.rebuild(
    roomPoints: pointsFromWalls(room.walls),
    walls: room.walls,
    lightIds: lights,
  );
  return grid.cells
      .where((c) => c.kind == CellKind.full || c.kind == CellKind.cut)
      .length;
}

/// Layout-based counts shared by UI, vedomost, and exports.
({int floorBoards, int wallTiles, int ceilingTiles}) finishLayoutCountsForRoom(Room room) => (
      floorBoards: floorBoardCountForRoom(room),
      wallTiles: wallTileLayoutCountForRoom(room),
      ceilingTiles: ceilingLayoutTileCountForRoom(room),
    );

int withWastePercent(int qty, double wasteFraction) {
  if (qty <= 0) return 0;
  return (qty * (1 + wasteFraction)).ceil();
}

/// Skirting / plinth length ≈ perimeter minus door openings on plan.
double skirtingLengthM(Room room) {
  if (!room.hasLayout) return 0;
  var peri = FinishCalculator.perimeterM(room.walls);
  final openings = room.openings.map(RoomOpening.fromJson);
  for (final o in openings) {
    if (o.kind == 'door' && o.wallIndex != null) {
      peri -= (o.widthCm / 100.0) * math.min(o.quantity, 1);
    }
  }
  return math.max(0, peri);
}

/// Rough consumables from net areas (kg / L estimates).
Map<String, String> finishConsumablesEstimate(Room room) {
  if (!room.hasLayout) return {};
  final openings = room.openings.map(RoomOpening.fromJson).toList();
  final layers = room.wallFinishLayers.map(FinishLayer.fromJson).toList();
  final areas = FinishCalculator.compute(
    walls: room.walls,
    heightCm: room.ceilingHeightCm,
    openings: openings,
    tileWidthCm: room.finishTileWidthCm,
    tileHeightCm: room.finishTileHeightCm,
    floorLayoutBoardCount: floorBoardCountForRoom(room),
    wallLayers: layers,
  );

  final out = <String, String>{};
  final skirting = skirtingLengthM(room);
  if (skirting > 0) {
    out['Плинтус напольный'] = '${skirting.toStringAsFixed(1)} п.м.';
  }

  final floorBoards = floorBoardCountForRoom(room);
  final prepFloor = room.floorPrepLayers.map(SurfacePrepLayer.fromJson).toList();
  final hasPrepUnderlay = prepFloor.any(
    (l) =>
        l.enabled && FloorPrepKind.parse(l.kindId) == FloorPrepKind.underlay,
  );
  if (floorBoards > 0) {
    out['Пол · запас 5%'] = '${withWastePercent(floorBoards, 0.05)} шт';
    if (FloorCoveringKindX.parse(room.floorCoveringKind) ==
            FloorCoveringKind.laminate &&
        !hasPrepUnderlay) {
      out['Подложка'] = '${areas.floorM2.toStringAsFixed(1)} м²';
    }
  } else if (FloorCoveringKindX.parse(room.floorCoveringKind) ==
      FloorCoveringKind.screed) {
    final depth = room.floorScreedDepthCm <= 0
        ? defaultScreedDepthCm
        : room.floorScreedDepthCm;
    final vol = screedVolumeM3(areas.floorM2, depth);
    out['Стяжка'] =
        '${vol.toStringAsFixed(2)} м³ · ${depth.toStringAsFixed(0)} см';
  }

  for (final layer in prepFloor) {
    if (!layer.enabled) continue;
    final name = layer.displayName(floor: true);
    final (qty, unit) = layer.materialQty(areas.floorM2, floor: true);
    out['Пол · $name'] = '$qty $unit';
  }
  for (final raw in room.ceilingPrepLayers) {
    final layer = SurfacePrepLayer.fromJson(raw);
    if (!layer.enabled) continue;
    final name = layer.displayName(floor: false);
    final (qty, unit) = layer.materialQty(areas.ceilingM2, floor: false);
    out['Потолок · $name'] = '$qty $unit';
  }

  var tileM2 = 0.0;
  var paintM2 = 0.0;
  for (final q in areas.wallLayers) {
    if (q.layer.kind == FinishLayerKind.tile) {
      tileM2 += q.areaM2;
    } else if (q.layer.kind == FinishLayerKind.paint) {
      paintM2 += q.areaM2;
    }
  }
  if (tileM2 > 0) {
    out['Клей плитка'] = '${(tileM2 * 0.35).toStringAsFixed(1)} кг';
    out['Затирка'] = '${(tileM2 * 0.15).toStringAsFixed(1)} кг';
  }
  if (paintM2 > 0) {
    out['Грунтовка'] = '${(paintM2 * 0.12).toStringAsFixed(1)} л';
  }

  final wallTiles = wallTileLayoutCountForRoom(room);
  if (wallTiles > 0) {
    out['Стены · плитка (раскладка)'] = '${withWastePercent(wallTiles, 0.07)} шт';
  }

  return out;
}

int floorBoardCountForRoom(Room room) {
  if (!room.hasLayout) return 0;
  if (FloorCoveringKindX.parse(room.floorCoveringKind) == FloorCoveringKind.screed) {
    return 0;
  }
  final snap = FloorLayoutBuilder.build(
    walls: room.walls,
    covering: FloorCoveringKindX.parse(room.floorCoveringKind),
    pattern: FloorLayingPatternX.parse(room.floorLayingPattern),
    boardW: room.finishTileWidthCm,
    boardL: room.finishTileHeightCm,
    offsetX: room.floorGridOffsetX.toDouble(),
    offsetY: room.floorGridOffsetY.toDouble(),
    rotationDeg: room.floorLayoutRotationDeg,
  );
  return snap.fullCount + snap.cutCount;
}

double ceilingCellForRoom(Room room, Project project) {
  final (ceiling, _, cell) = roomEffectiveConfig(room, project);
  return ceilingCellCm(ceiling, cell);
}
