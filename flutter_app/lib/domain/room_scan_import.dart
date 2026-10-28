import 'dart:math' as math;

import 'package:roomplan_flutter/roomplan_flutter.dart';

import 'finish_model.dart';
import 'geometry_polygon.dart';
import 'wall_geometry.dart';

/// Result of importing a RoomPlan / ARCore scan into app geometry.
class RoomScanImportResult {
  const RoomScanImportResult({
    required this.walls,
    this.ceilingHeightCm,
    this.wallCount = 0,
    this.openingCount = 0,
    this.openings = const [],
    this.source = 'roomplan',
  });

  final List<List<double>> walls;
  final double? ceilingHeightCm;
  final int wallCount;
  final int openingCount;
  final List<RoomOpening> openings;
  final String source;

  PolygonFootprint get footprint => footprintFromWalls(walls);
}

/// Convert RoomPlan [ScanResult] → editor walls (cm, Y-up 2D footprint).
RoomScanImportResult importFromRoomPlanScan(ScanResult scan) {
  return importFromRoomData(scan.room);
}

RoomScanImportResult importFromRoomData(RoomData room) {
  final heightCm = room.dimensions != null && room.dimensions!.height > 0
      ? room.dimensions!.height * 100
      : null;

  final fromDims = _wallsFromDimensions(room.dimensions);
  final walls = fromDims ?? _wallsFromWallData(room.walls);
  final openings = openingsFromRoomData(room, walls);

  return RoomScanImportResult(
    walls: walls,
    ceilingHeightCm: heightCm,
    wallCount: room.walls.length,
    openingCount: openings.length,
    openings: openings,
  );
}

/// Map RoomPlan doors/windows → [RoomOpening] on imported walls.
List<RoomOpening> openingsFromRoomData(RoomData room, List<List<double>> walls) {
  if (walls.length < 3) return const [];
  final out = <RoomOpening>[];
  final seen = <String>{};

  void add(OpeningData o, String kind) {
    if (o.width <= 0.05 || o.height <= 0.05) return;
    if (o.uuid.isNotEmpty) {
      if (seen.contains(o.uuid)) return;
      seen.add(o.uuid);
    }
    final x = o.position.x * 100;
    final y = o.position.z * 100;
    final hit = nearestWallHit(walls, x, y, maxDistCm: 120);
    final widthCm = o.width * 100;
    final heightCm = o.height * 100;
    var offset = (hit?.offsetAlongCm ?? 0) - widthCm / 2;
    if (hit != null) {
      offset = offset.clamp(0.0, math.max(0.0, hit.wallLengthCm - widthCm));
    }
    final sillFromPos = o.position.y * 100;
    out.add(
      RoomOpening(
        kind: kind,
        widthCm: widthCm,
        heightCm: heightCm,
        wallIndex: hit?.wallIndex,
        offsetAlongWallCm: offset,
        sillHeightCm: kind == 'door' ? 0 : sillFromPos.clamp(0, 400),
      ),
    );
  }

  for (final d in room.doors) {
    add(d, 'door');
  }
  for (final w in room.windows) {
    add(w, 'window');
  }
  for (final o in room.openings) {
    add(o, 'opening');
  }
  for (final wall in room.walls) {
    for (final o in wall.openings) {
      final kind = switch (o.type) {
        OpeningType.door => 'door',
        OpeningType.window => 'window',
        OpeningType.opening => 'opening',
      };
      add(o, kind);
    }
  }
  return out;
}

List<List<double>>? _wallsFromDimensions(RoomDimensions? dims) {
  if (dims == null || dims.length < 0.3 || dims.width < 0.3) return null;
  final l = dims.length * 100;
  final w = dims.width * 100;
  return [
    [0, 0, l, 0],
    [l, 0, l, w],
    [l, w, 0, w],
    [0, w, 0, 0],
  ];
}

/// Project wall centers/endpoints from AR (X-Z floor) to cm footprint (X-Y).
List<List<double>> _wallsFromWallData(List<WallData> walls) {
  if (walls.isEmpty) return const [];

  final segments = <List<double>>[];
  for (final wall in walls) {
    final seg = _wallSegmentXZ(wall);
    if (seg != null) segments.add(seg);
  }
  if (segments.length >= 3) return normalizeWallsToOrigin(segments);

  final centers = <List<double>>[];
  for (final wall in walls) {
    centers.add([
      wall.position.x * 100,
      wall.position.z * 100,
    ]);
  }
  if (centers.length < 3) return segments;

  final cx = centers.map((p) => p[0]).reduce((a, b) => a + b) / centers.length;
  final cy = centers.map((p) => p[1]).reduce((a, b) => a + b) / centers.length;
  centers.sort((a, b) {
    final aa = math.atan2(a[1] - cy, a[0] - cx);
    final bb = math.atan2(b[1] - cy, b[0] - cx);
    return aa.compareTo(bb);
  });

  final out = <List<double>>[];
  for (var i = 0; i < centers.length; i++) {
    final p1 = centers[i];
    final p2 = centers[(i + 1) % centers.length];
    out.add([p1[0], p1[1], p2[0], p2[1]]);
  }
  return normalizeWallsToOrigin(out);
}

List<double>? _wallSegmentXZ(WallData wall) {
  if (wall.width <= 0) return null;
  final half = wall.width / 2 * 100;
  var dx = 1.0;
  var dz = 0.0;
  if (wall.transform != null) {
    final m = wall.transform!;
    dx = m.entry(0, 0);
    dz = m.entry(2, 0);
    final len = math.sqrt(dx * dx + dz * dz);
    if (len > 1e-6) {
      dx /= len;
      dz /= len;
    }
  }
  final cx = wall.position.x * 100;
  final cz = wall.position.z * 100;
  return [
    cx - dx * half,
    cz - dz * half,
    cx + dx * half,
    cz + dz * half,
  ];
}

/// Parse saved RoomPlan JSON (for tests / re-import).
RoomScanImportResult importFromRoomPlanJson(Map<String, dynamic> json) {
  final scan = ScanResult.fromJson(json);
  return importFromRoomPlanScan(scan);
}

/// ARCore corner polygon (meters X-Z) → walls in cm.
RoomScanImportResult importFromArCorners(List<(double, double)> cornersMeters) {
  if (cornersMeters.length < 3) {
    return const RoomScanImportResult(walls: [], source: 'arcore');
  }
  final cm = cornersMeters.map((p) => (p.$1 * 100, p.$2 * 100)).toList();
  final walls = normalizeWallsToOrigin(wallsFromPoints2d(cm));
  return RoomScanImportResult(
    walls: walls,
    source: 'arcore',
    wallCount: walls.length,
  );
}
