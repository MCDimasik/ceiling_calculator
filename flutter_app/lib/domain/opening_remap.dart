import 'dart:math' as math;

import 'finish_model.dart';
import 'models.dart';
import 'wall_geometry.dart';

/// True when wall chain closes within [epsCm] (start of first ≈ end of last).
bool wallsFormClosedPolygon(List<List<double>> walls, {double epsCm = 0.1}) {
  if (walls.length < 3) return false;
  final start = (walls.first[0], walls.first[1]);
  final end = (walls.last[2], walls.last[3]);
  final dx = end.$1 - start.$1;
  final dy = end.$2 - start.$2;
  return math.sqrt(dx * dx + dy * dy) <= epsCm;
}

/// Re-bind placed openings from [oldWalls] onto [newWalls] by mid-point nearest wall.
/// Unplace openings that no longer fit.
List<RoomOpening> remapOpeningsToWalls({
  required List<RoomOpening> openings,
  required List<List<double>> oldWalls,
  required List<List<double>> newWalls,
}) {
  if (openings.isEmpty) return openings;
  if (newWalls.isEmpty) {
    return [
      for (final o in openings)
        RoomOpening(
          kind: o.kind,
          widthCm: o.widthCm,
          heightCm: o.heightCm,
          quantity: o.quantity,
          label: o.label,
          sillHeightCm: o.sillHeightCm,
        ),
    ];
  }

  final out = <RoomOpening>[];
  for (final o in openings) {
    if (o.wallIndex == null) {
      out.add(o);
      continue;
    }
    final wi = o.wallIndex!;
    if (wi < 0 || wi >= oldWalls.length || oldWalls[wi].length < 4) {
      out.add(
        RoomOpening(
          kind: o.kind,
          widthCm: o.widthCm,
          heightCm: o.heightCm,
          quantity: o.quantity,
          label: o.label,
          sillHeightCm: o.sillHeightCm,
        ),
      );
      continue;
    }
    final w = oldWalls[wi];
    final ax = w[0], ay = w[1], bx = w[2], by = w[3];
    final abx = bx - ax, aby = by - ay;
    final len = math.sqrt(abx * abx + aby * aby);
    if (len < 1e-6) {
      out.add(
        RoomOpening(
          kind: o.kind,
          widthCm: o.widthCm,
          heightCm: o.heightCm,
          quantity: o.quantity,
          label: o.label,
          sillHeightCm: o.sillHeightCm,
        ),
      );
      continue;
    }
    final mid = (o.offsetAlongWallCm + o.widthCm / 2).clamp(0.0, len);
    final t = mid / len;
    final px = ax + abx * t;
    final py = ay + aby * t;
    final hit = nearestWallHit(newWalls, px, py, maxDistCm: 120);
    if (hit == null || hit.wallLengthCm + 1e-6 < o.widthCm) {
      out.add(
        RoomOpening(
          kind: o.kind,
          widthCm: o.widthCm,
          heightCm: o.heightCm,
          quantity: o.quantity,
          label: o.label,
          sillHeightCm: o.sillHeightCm,
        ),
      );
      continue;
    }
    final start = (hit.offsetAlongCm - o.widthCm / 2)
        .clamp(0.0, math.max(0.0, hit.wallLengthCm - o.widthCm))
        .toDouble();
    out.add(
      RoomOpening(
        kind: o.kind,
        widthCm: o.widthCm,
        heightCm: o.heightCm,
        quantity: o.quantity,
        label: o.label,
        wallIndex: hit.wallIndex,
        offsetAlongWallCm: start,
        sillHeightCm: o.sillHeightCm,
      ),
    );
  }
  return out;
}

/// Apply [remapOpeningsToWalls] onto [room.openings] JSON in place.
void remapRoomOpeningsAfterWallChange(
  Room room, {
  required List<List<double>> oldWalls,
}) {
  if (room.openings.isEmpty) return;
  final mapped = remapOpeningsToWalls(
    openings: room.openings.map(RoomOpening.fromJson).toList(),
    oldWalls: oldWalls,
    newWalls: room.walls,
  );
  room.openings = mapped.map((o) => o.toJson()).toList();
}
