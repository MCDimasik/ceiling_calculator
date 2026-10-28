import 'finish_model.dart';
import 'finish_quantities.dart';
import 'models.dart';

/// How capture changes finish quantities (walls + floor + ceiling).
class FinishCaptureImpact {
  const FinishCaptureImpact({
    required this.before,
    required this.after,
  });

  final FinishAreas before;
  final FinishAreas after;

  double get floorDeltaM2 => after.floorM2 - before.floorM2;
  double get ceilingDeltaM2 => after.ceilingM2 - before.ceilingM2;
  double get wallsNetDeltaM2 => after.wallsNetM2 - before.wallsNetM2;
  double get totalFinishDeltaM2 => after.totalFinishM2 - before.totalFinishM2;
  double get perimeterDeltaM => after.perimeterM - before.perimeterM;

  bool get hasSignificantChange =>
      floorDeltaM2.abs() > 0.05 ||
      wallsNetDeltaM2.abs() > 0.05 ||
      totalFinishDeltaM2.abs() > 0.1;
}

FinishCaptureImpact computeFinishCaptureImpact({
  required Room room,
  required List<List<double>> newWalls,
  double? newHeightCm,
  List<RoomOpening>? newOpenings,
}) {
  final layers = room.wallFinishLayers.map(FinishLayer.fromJson).toList();
  final beforeOpenings = room.openings.map(RoomOpening.fromJson).toList();
  final afterOpenings = newOpenings ?? beforeOpenings;
  final afterHeight = newHeightCm ?? room.ceilingHeightCm;

  Room geometrySnapshot(
    List<List<double>> walls,
    double heightCm,
    List<Map<String, dynamic>> openingsJson,
  ) {
    return Room(
      name: room.name,
      walls: walls,
      ceilingHeightCm: heightCm,
      openings: openingsJson,
      wallFinishLayers: room.wallFinishLayers,
      finishTileWidthCm: room.finishTileWidthCm,
      finishTileHeightCm: room.finishTileHeightCm,
      floorCoveringKind: room.floorCoveringKind,
      floorLayingPattern: room.floorLayingPattern,
      floorGridOffsetX: room.floorGridOffsetX,
      floorGridOffsetY: room.floorGridOffsetY,
      floorLayoutRotationDeg: room.floorLayoutRotationDeg,
      gridOffsetX: room.gridOffsetX,
      gridOffsetY: room.gridOffsetY,
      lightFixtures: room.lightFixtures,
    );
  }

  final beforeSnap = geometrySnapshot(room.walls, room.ceilingHeightCm, room.openings);
  final afterSnap = geometrySnapshot(
    newWalls,
    afterHeight,
    afterOpenings.map((o) => o.toJson()).toList(),
  );
  final beforeCounts = finishLayoutCountsForRoom(beforeSnap);
  final afterCounts = finishLayoutCountsForRoom(afterSnap);

  final before = FinishCalculator.compute(
    walls: room.walls,
    heightCm: room.ceilingHeightCm,
    openings: beforeOpenings,
    tileWidthCm: room.finishTileWidthCm,
    tileHeightCm: room.finishTileHeightCm,
    floorLayoutBoardCount: beforeCounts.floorBoards,
    wallLayoutTileCount: beforeCounts.wallTiles,
    ceilingLayoutTileCount: beforeCounts.ceilingTiles,
    wallLayers: layers,
  );
  final after = FinishCalculator.compute(
    walls: newWalls,
    heightCm: afterHeight,
    openings: afterOpenings,
    tileWidthCm: room.finishTileWidthCm,
    tileHeightCm: room.finishTileHeightCm,
    floorLayoutBoardCount: afterCounts.floorBoards,
    wallLayoutTileCount: afterCounts.wallTiles,
    ceilingLayoutTileCount: afterCounts.ceilingTiles,
    wallLayers: layers,
  );
  return FinishCaptureImpact(before: before, after: after);
}

String formatFinishCaptureImpactSummary(FinishCaptureImpact impact) {
  if (!impact.hasSignificantChange) {
    return 'Объёмы отделки почти не изменятся.';
  }
  String d(double v, String unit) {
    if (v.abs() < 0.01) return '0';
    final sign = v >= 0 ? '+' : '';
    return '$sign${v.toStringAsFixed(2)} $unit';
  }

  return 'Влияние на комплекс отделки:\n'
      '· Пол: ${d(impact.floorDeltaM2, 'м²')}\n'
      '· Потолок: ${d(impact.ceilingDeltaM2, 'м²')}\n'
      '· Стены: ${d(impact.wallsNetDeltaM2, 'м²')}\n'
      '· Всего отделка: ${d(impact.totalFinishDeltaM2, 'м²')}';
}

String formatFinishCaptureCompact(FinishCaptureImpact impact) =>
    'Пол ${impact.after.floorM2.toStringAsFixed(1)} · '
    'потолок ${impact.after.ceilingM2.toStringAsFixed(1)} · '
    'стены ${impact.after.wallsNetM2.toStringAsFixed(1)} м²';
