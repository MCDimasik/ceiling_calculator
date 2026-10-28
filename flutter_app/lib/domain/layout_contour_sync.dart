import 'ceiling_grid.dart';
import 'ceiling_guides.dart';
import 'models.dart';
import 'project_materials.dart';

/// Result of dropping ceiling features that no longer fit the room contour.
class LayoutContourSyncResult {
  const LayoutContourSyncResult({
    this.removedLights = 0,
    this.removedGuides = 0,
    this.clearedLayoutConfirm = false,
  });

  final int removedLights;
  final int removedGuides;
  final bool clearedLayoutConfirm;

  bool get changed =>
      removedLights > 0 || removedGuides > 0 || clearedLayoutConfirm;

  String get summaryRu {
    if (!changed) return '';
    final parts = <String>[];
    if (removedLights > 0) parts.add('свет −$removedLights');
    if (removedGuides > 0) parts.add('направл. −$removedGuides');
    if (clearedLayoutConfirm) parts.add('раскладка сброшена');
    return parts.join(' · ');
  }
}

/// After walls change: prune lights/guides outside the contour.
/// If contour is incomplete/open (![Room.hasLayout]), clears lights, guides and
/// [Room.layoutConfirmed] so wipe / open draft matches editor promises.
LayoutContourSyncResult syncLayoutFeaturesToContour(
  Room room, {
  double? cellCm,
}) {
  if (!room.hasLayout) {
    final removedLights = room.lightFixtures.length;
    final removedGuides = room.ceilingGuides.length;
    final cleared = room.layoutConfirmed;
    room.lightFixtures = [];
    room.ceilingGuides = [];
    room.layoutConfirmed = false;
    return LayoutContourSyncResult(
      removedLights: removedLights,
      removedGuides: removedGuides,
      clearedLayoutConfirm: cleared,
    );
  }

  final ceiling = room.materialsCeiling ?? 'Армстронг';
  final cell = room.materialsCell ?? '50x50';
  final size = cellCm ?? ceilingCellCm(ceiling, cell);

  final beforeLights = room.lightFixtures.length;
  final lights = <String>{};
  for (final f in room.lightFixtures) {
    if (f.length >= 2) lights.add('${f[0]}:${f[1]}');
  }

  final grid = CeilingGrid(
    offsetXCm: room.gridOffsetX.toDouble(),
    offsetYCm: room.gridOffsetY.toDouble(),
    cellWidthCm: size,
    cellHeightCm: size,
  );
  grid.rebuild(
    roomPoints: pointsFromWalls(room.walls),
    walls: room.walls,
    lightIds: lights,
  );
  grid.pruneLights();
  room.lightFixtures = [
    for (final c in grid.cells)
      if (c.hasLight) [c.col, c.row],
  ];
  final removedLights = beforeLights - room.lightFixtures.length;

  final beforeGuides = room.ceilingGuides.length;
  if (room.ceilingGuides.isNotEmpty) {
    final ox = room.gridOffsetX.toDouble();
    final oy = room.gridOffsetY.toDouble();
    final kept = <Map<String, dynamic>>[];
    for (final raw in room.ceilingGuides) {
      final g = CeilingGuideMark.fromJson(
        raw,
        offsetX: ox,
        offsetY: oy,
        cellSize: size,
      );
      if (g == null) continue;
      if (_guideTouchesInsideCells(g, grid, size, ox, oy)) {
        kept.add(Map<String, dynamic>.from(raw));
      }
    }
    room.ceilingGuides = kept;
  }
  final removedGuides = beforeGuides - room.ceilingGuides.length;

  return LayoutContourSyncResult(
    removedLights: removedLights < 0 ? 0 : removedLights,
    removedGuides: removedGuides < 0 ? 0 : removedGuides,
  );
}

/// Keep guide only if its grid line crosses a non-outside cell (true polygon).
bool _guideTouchesInsideCells(
  CeilingGuideMark g,
  CeilingGrid grid,
  double cellSize,
  double ox,
  double oy,
) {
  final coord = g.worldCoord(offsetX: ox, offsetY: oy, cellSize: cellSize);
  const pad = 0.5;
  for (final c in grid.cells) {
    if (c.kind == CellKind.outside) continue;
    if (g.axis == GuideAxis.horizontal) {
      if (coord >= c.yCm - pad && coord <= c.yCm + cellSize + pad) return true;
    } else {
      if (coord >= c.xCm - pad && coord <= c.xCm + cellSize + pad) return true;
    }
  }
  return false;
}
