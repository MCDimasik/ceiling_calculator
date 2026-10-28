import 'finish_model.dart';
import 'finish_quantities.dart';
import 'models.dart';
import 'project_materials.dart';
import 'special_space.dart';

/// Resolved finish areas for a room: drawn layout or special space volumes.
({double floorM2, double wallsM2, double ceilingM2, bool fromSpecial})
    resolveRoomFinishAreas(Room room) {
  final special = room.specialSpace;
  if (special != null &&
      (special.kind == SpecialSpaceKind.stairwell || special.hasAnyArea)) {
    if (special.kind == SpecialSpaceKind.stairwell) {
      special.recomputeFromStair();
    }
    return (
      floorM2: special.floorM2 < 0 ? 0 : special.floorM2,
      wallsM2: special.wallsM2 < 0 ? 0 : special.wallsM2,
      ceilingM2: special.ceilingM2 < 0 ? 0 : special.ceilingM2,
      fromSpecial: true,
    );
  }
  if (!room.hasLayout || room.walls.length < 3) {
    return (floorM2: 0.0, wallsM2: 0.0, ceilingM2: 0.0, fromSpecial: false);
  }
  final openings = room.openings.map(RoomOpening.fromJson).toList();
  final wallLayers = room.wallFinishLayers.map(FinishLayer.fromJson).toList();
  final areas = FinishCalculator.compute(
    walls: room.walls,
    heightCm: room.ceilingHeightCm,
    openings: openings,
    tileWidthCm: room.finishTileWidthCm,
    tileHeightCm: room.finishTileHeightCm,
    wallLayers: wallLayers,
  );
  return (
    floorM2: areas.floorM2,
    wallsM2: areas.wallsNetM2,
    ceilingM2: areas.ceilingM2,
    fromSpecial: false,
  );
}

/// Room participates in finish / smeta if it has a plan or manual volumes.
bool roomHasFinishGeometry(Room room) {
  if (room.hasLayout && room.walls.length >= 3) return true;
  final s = room.specialSpace;
  if (s == null) return false;
  if (s.kind == SpecialSpaceKind.stairwell) {
    return s.computeWallsViaStair() > 0 || s.hasAnyArea;
  }
  return s.hasAnyArea;
}

/// Drawn contour **or** special schematic / volumes (ЛК, объём без чертежа).
bool roomHasPlanOrSchematic(Room room) =>
    room.hasLayout || roomHasFinishGeometry(room);

extension on SpecialSpace {
  double computeWallsViaStair() {
    if (kind != SpecialSpaceKind.stairwell) return wallsM2;
    return (stair ?? StairwellParams()).computeWallsM2();
  }
}

/// Full [FinishAreas] for layout rooms or synthetic areas for special spaces.
FinishAreas? finishAreasForRoom(
  Room room, {
  Project? project,
  double? heightCmOverride,
  double? tileWidthCm,
  double? tileHeightCm,
  List<RoomOpening>? openingsOverride,
  List<FinishLayer>? wallLayersOverride,
}) {
  if (!roomHasFinishGeometry(room)) return null;

  final layers = wallLayersOverride ??
      room.wallFinishLayers.map(FinishLayer.fromJson).toList();
  final resolved = resolveRoomFinishAreas(room);

  if (resolved.fromSpecial) {
    final floor = resolved.floorM2;
    final walls = resolved.wallsM2;
    final ceiling = resolved.ceilingM2;
    final tw = tileWidthCm ?? room.finishTileWidthCm;
    final th = tileHeightCm ?? room.finishTileHeightCm;
    var ceilingCell = 60.0;
    if (project != null) {
      final (ceilingCfg, _, cell) = roomEffectiveConfig(room, project);
      ceilingCell = ceilingCellCm(ceilingCfg, cell);
    }
    final layerQtys = FinishCalculator.layerQuantities(
      wallsNetM2: walls,
      layers: layers,
    );
    return FinishAreas(
      floorM2: floor,
      ceilingM2: ceiling,
      wallsGrossM2: walls,
      openingsM2: 0,
      wallsNetM2: walls,
      perimeterM: 0,
      floorTiles: FinishCalculator.tilesForArea(floor, tw, th),
      ceilingTiles:
          FinishCalculator.tilesForArea(ceiling, ceilingCell, ceilingCell),
      wallTiles: FinishCalculator.tilesForArea(walls, tw, th),
      wallLayers: layerQtys,
    );
  }

  final openings =
      openingsOverride ?? room.openings.map(RoomOpening.fromJson).toList();
  final h = heightCmOverride ?? room.ceilingHeightCm;
  final tw = tileWidthCm ?? room.finishTileWidthCm;
  final th = tileHeightCm ?? room.finishTileHeightCm;
  var ceilingCell = 60.0;
  if (project != null) {
    final (ceilingCfg, _, cell) = roomEffectiveConfig(room, project);
    ceilingCell = ceilingCellCm(ceilingCfg, cell);
  }
  final counts = finishLayoutCountsForRoom(room);
  return FinishCalculator.compute(
    walls: room.walls,
    heightCm: h,
    openings: openings,
    tileWidthCm: tw,
    tileHeightCm: th,
    ceilingCellCm: ceilingCell,
    floorLayoutBoardCount: counts.floorBoards,
    wallLayoutTileCount: counts.wallTiles,
    ceilingLayoutTileCount: counts.ceilingTiles,
    wallLayers: layers,
  );
}
