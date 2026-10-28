import '../domain/ceiling_guides.dart';
import '../domain/models.dart';

const _designGridXKey = 'design_grid_offset_x';
const _designGridYKey = 'design_grid_offset_y';

/// Baseline grid offset saved when layout is first confirmed (= «проект»).
class DesignGridBaseline {
  const DesignGridBaseline({required this.offsetX, required this.offsetY});

  final int offsetX;
  final int offsetY;

  bool get hasBaseline => offsetX != 0 || offsetY != 0;
}

DesignGridBaseline readDesignBaseline(Room room) {
  final view = room.layoutViewJson;
  if (view == null) {
    return DesignGridBaseline(offsetX: room.gridOffsetX, offsetY: room.gridOffsetY);
  }
  final x = view[_designGridXKey];
  final y = view[_designGridYKey];
  if (x is num && y is num) {
    return DesignGridBaseline(offsetX: x.round(), offsetY: y.round());
  }
  return DesignGridBaseline(offsetX: room.gridOffsetX, offsetY: room.gridOffsetY);
}

bool hasDesignGridBaseline(Room room) {
  final view = room.layoutViewJson;
  return view != null &&
      view.containsKey(_designGridXKey) &&
      view.containsKey(_designGridYKey);
}

/// Persist project grid offset into layout view JSON (once or on re-confirm).
void ensureDesignBaseline(Room room) {
  final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
  if (view.containsKey(_designGridXKey) && view.containsKey(_designGridYKey)) return;
  view[_designGridXKey] = room.gridOffsetX;
  view[_designGridYKey] = room.gridOffsetY;
  room.layoutViewJson = view;
}

(int dx, int dy) gridOffsetDelta(Room room) {
  final base = readDesignBaseline(room);
  return (room.gridOffsetX - base.offsetX, room.gridOffsetY - base.offsetY);
}

String formatGridDeltaLabel(Room room) {
  final (dx, dy) = gridOffsetDelta(room);
  if (dx == 0 && dy == 0) return 'Совпадает с проектом';
  return 'Δ сетки: $dx×$dy см (факт vs проект)';
}

/// Optional: store guide count at confirm for future diff (stub for CAD backlog).
int guideCount(Room room) => room.ceilingGuides.length;

Map<String, dynamic> guidesToJson(Map<String, CeilingGuideMark> guides) =>
    guides.map((k, v) => MapEntry(k, v.toJson()));

void resetDesignBaseline(Room room) {
  final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
  final removed = view.remove(_designGridXKey) != null || view.remove(_designGridYKey) != null;
  if (removed) {
    room.layoutViewJson = view.isEmpty ? null : view;
  }
}

Map<String, CeilingGuideMark> guidesFromJson(Map<String, dynamic> raw) {
  final out = <String, CeilingGuideMark>{};
  for (final e in raw.entries) {
    final m = CeilingGuideMark.fromJson(Map<String, dynamic>.from(e.value as Map));
    if (m != null) out[e.key] = m;
  }
  return out;
}
