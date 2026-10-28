import 'models.dart';

const _designWallsKey = 'design_walls_json';

/// Project wall footprint saved when layout is confirmed or before first fact capture.
List<List<double>>? readDesignWalls(Room room) {
  final raw = room.layoutViewJson?[_designWallsKey];
  if (raw is! List) return null;
  final out = <List<double>>[];
  for (final w in raw) {
    if (w is! List || w.length < 4) continue;
    out.add(w.map((n) => (n as num).toDouble()).toList());
  }
  return out.length >= 3 ? out : null;
}

bool hasDesignWallBaseline(Room room) => readDesignWalls(room) != null;

/// Write-once snapshot of current walls into layout view JSON.
void ensureDesignWallsBaseline(Room room) {
  if (room.walls.length < 3) return;
  final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
  if (view.containsKey(_designWallsKey)) return;
  view[_designWallsKey] = room.walls.map((w) => [w[0], w[1], w[2], w[3]]).toList();
  room.layoutViewJson = view;
}

/// Before overwriting walls with scan/photo, preserve project geometry if missing.
void snapshotDesignWallsIfNeeded(Room room) {
  ensureDesignWallsBaseline(room);
}

List<List<double>> encodeDesignWalls(List<List<double>> walls) =>
    walls.map((w) => [w[0], w[1], w[2], w[3]]).toList();

void resetDesignWallsBaseline(Room room) {
  final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
  if (view.remove(_designWallsKey) != null) {
    room.layoutViewJson = view.isEmpty ? null : view;
  }
}
