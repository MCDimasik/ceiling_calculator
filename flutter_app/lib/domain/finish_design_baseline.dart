import 'layout_design_baseline.dart';
import 'design_walls_baseline.dart';
import 'design_ceiling_features_baseline.dart';
import 'models.dart';

const _designFloorGridXKey = 'design_floor_grid_offset_x';
const _designFloorGridYKey = 'design_floor_grid_offset_y';
const _designFloorRotationKey = 'design_floor_layout_rotation_deg';
const _designHeightKey = 'design_ceiling_height_cm';

class DesignFloorGridBaseline {
  const DesignFloorGridBaseline({required this.offsetX, required this.offsetY});

  final int offsetX;
  final int offsetY;
}

DesignFloorGridBaseline readFloorDesignBaseline(Room room) {
  final view = room.layoutViewJson;
  if (view != null) {
    final x = view[_designFloorGridXKey];
    final y = view[_designFloorGridYKey];
    if (x is num && y is num) {
      return DesignFloorGridBaseline(offsetX: x.round(), offsetY: y.round());
    }
  }
  return DesignFloorGridBaseline(
    offsetX: room.floorGridOffsetX,
    offsetY: room.floorGridOffsetY,
  );
}

void ensureFloorDesignBaseline(Room room) {
  final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
  var changed = false;
  if (!view.containsKey(_designFloorGridXKey)) {
    view[_designFloorGridXKey] = room.floorGridOffsetX;
    changed = true;
  }
  if (!view.containsKey(_designFloorGridYKey)) {
    view[_designFloorGridYKey] = room.floorGridOffsetY;
    changed = true;
  }
  if (!view.containsKey(_designFloorRotationKey)) {
    view[_designFloorRotationKey] = room.floorLayoutRotationDeg;
    changed = true;
  }
  if (changed) room.layoutViewJson = view;
}

int readFloorDesignRotation(Room room) {
  final v = room.layoutViewJson?[_designFloorRotationKey];
  if (v is num) return v.round().clamp(0, 270);
  return room.floorLayoutRotationDeg;
}

int floorLayoutRotationDelta(Room room) {
  final base = readFloorDesignRotation(room);
  return (room.floorLayoutRotationDeg - base) % 360;
}

(int dx, int dy) floorGridOffsetDelta(Room room) {
  final base = readFloorDesignBaseline(room);
  return (room.floorGridOffsetX - base.offsetX, room.floorGridOffsetY - base.offsetY);
}

String formatFloorGridDeltaLabel(Room room) {
  final (dx, dy) = floorGridOffsetDelta(room);
  final dr = floorLayoutRotationDelta(room);
  if (dx == 0 && dy == 0 && dr == 0) return 'Сетка пола совпадает с проектом';
  final parts = <String>[];
  if (dx != 0 || dy != 0) parts.add('Δ смещения $dx×$dy см');
  if (dr != 0) parts.add('Δ поворота $dr°');
  return parts.join(' · ');
}

double? readDesignCeilingHeightCm(Room room) {
  final v = room.layoutViewJson?[_designHeightKey];
  if (v is num) return v.toDouble();
  return null;
}

void ensureDesignCeilingHeightBaseline(Room room) {
  if (room.ceilingHeightCm <= 0) return;
  final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
  if (view.containsKey(_designHeightKey)) return;
  view[_designHeightKey] = room.ceilingHeightCm;
  room.layoutViewJson = view;
}

void ensureFinishDesignBaseline(Room room) {
  ensureDesignWallsBaseline(room);
  ensureDesignBaseline(room);
  ensureFloorDesignBaseline(room);
  ensureDesignCeilingHeightBaseline(room);
  ensureDesignCeilingFeaturesBaseline(room);
}

void snapshotFinishDesignIfNeeded(Room room) {
  ensureFinishDesignBaseline(room);
}

bool hasFinishDesignBaseline(Room room) {
  if (hasDesignWallBaseline(room)) return true;
  if (hasDesignGridBaseline(room)) return true;
  final view = room.layoutViewJson;
  if (view == null) return false;
  return view.containsKey(_designFloorGridXKey) || view.containsKey(_designHeightKey);
}

const _baselineHistoryKey = 'baseline_history';
const _maxBaselineHistoryEntries = 8;

class BaselineHistoryEntry {
  const BaselineHistoryEntry({
    required this.capturedAt,
    this.wallCount,
    this.ceilingGridX,
    this.ceilingGridY,
    this.floorGridX,
    this.floorGridY,
    this.ceilingHeightCm,
  });

  final DateTime capturedAt;
  final int? wallCount;
  final int? ceilingGridX;
  final int? ceilingGridY;
  final int? floorGridX;
  final int? floorGridY;
  final double? ceilingHeightCm;

  static BaselineHistoryEntry? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['captured_at'] as String? ?? '');
    if (at == null) return null;
    return BaselineHistoryEntry(
      capturedAt: at,
      wallCount: (json['wall_count'] as num?)?.toInt(),
      ceilingGridX: (json['ceiling_grid_x'] as num?)?.toInt(),
      ceilingGridY: (json['ceiling_grid_y'] as num?)?.toInt(),
      floorGridX: (json['floor_grid_x'] as num?)?.toInt(),
      floorGridY: (json['floor_grid_y'] as num?)?.toInt(),
      ceilingHeightCm: (json['ceiling_height_cm'] as num?)?.toDouble(),
    );
  }
}

List<BaselineHistoryEntry> readBaselineHistory(Room room) {
  final raw = room.layoutViewJson?[_baselineHistoryKey];
  if (raw is! List) return const [];
  final out = raw
      .whereType<Map>()
      .map((e) => BaselineHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
      .whereType<BaselineHistoryEntry>()
      .toList();
  out.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  return out;
}

void archiveBaselineSnapshot(Room room) {
  if (!hasFinishDesignBaseline(room)) return;
  final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
  final history = (view[_baselineHistoryKey] as List?)?.toList() ?? <dynamic>[];
  final walls = readDesignWalls(room);
  history.add({
    'captured_at': DateTime.now().toIso8601String(),
    'wall_count': walls?.length,
    'ceiling_grid_x': readDesignBaseline(room).offsetX,
    'ceiling_grid_y': readDesignBaseline(room).offsetY,
    'floor_grid_x': readFloorDesignBaseline(room).offsetX,
    'floor_grid_y': readFloorDesignBaseline(room).offsetY,
    'ceiling_height_cm': readDesignCeilingHeightCm(room),
  });
  while (history.length > _maxBaselineHistoryEntries) {
    history.removeAt(0);
  }
  view[_baselineHistoryKey] = history;
  room.layoutViewJson = view;
}

String formatBaselineHistoryLine(BaselineHistoryEntry e) {
  final d =
      '${e.capturedAt.day.toString().padLeft(2, '0')}.${e.capturedAt.month.toString().padLeft(2, '0')}.${e.capturedAt.year} '
      '${e.capturedAt.hour.toString().padLeft(2, '0')}:${e.capturedAt.minute.toString().padLeft(2, '0')}';
  final parts = <String>[];
  if (e.wallCount != null) parts.add('${e.wallCount} стен');
  if (e.ceilingGridX != null && e.ceilingGridY != null) {
    parts.add('потолок ${e.ceilingGridX}×${e.ceilingGridY}');
  }
  if (e.floorGridX != null && e.floorGridY != null) {
    parts.add('пол ${e.floorGridX}×${e.floorGridY}');
  }
  if (e.ceilingHeightCm != null) parts.add('h ${e.ceilingHeightCm!.round()} см');
  return '$d · ${parts.join(' · ')}';
}

void resetFinishDesignBaseline(Room room) {
  resetDesignWallsBaseline(room);
  resetDesignBaseline(room);
  resetDesignCeilingFeaturesBaseline(room);
  final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
  view.remove(_designFloorGridXKey);
  view.remove(_designFloorGridYKey);
  view.remove(_designFloorRotationKey);
  view.remove(_designHeightKey);
  room.layoutViewJson = view.isEmpty ? null : view;
}

/// Replace project baseline with the current room state (re-confirm / as-built update).
void rebaselineFinishDesign(Room room) {
  archiveBaselineSnapshot(room);
  resetFinishDesignBaseline(room);
  ensureFinishDesignBaseline(room);
}

/// Re-baseline all rooms that have a layout contour.
List<String> rebaselineRoomsWithLayout(Iterable<Room> rooms) {
  final names = <String>[];
  for (final room in rooms) {
    if (!room.hasLayout) continue;
    rebaselineFinishDesign(room);
    names.add(room.name);
  }
  return names;
}

String formatFinishBaselineStatus(Room room) {
  final parts = <String>[];
  if (hasDesignWallBaseline(room)) parts.add('контур');
  final (cgx, cgy) = gridOffsetDelta(room);
  final (fgx, fgy) = floorGridOffsetDelta(room);
  if (cgx != 0 || cgy != 0) parts.add('сетка потолка Δ$cgx×$cgy');
  if (fgx != 0 || fgy != 0) parts.add('сетка пола Δ$fgx×$fgy');
  final fRot = floorLayoutRotationDelta(room);
  if (fRot != 0) parts.add('поворот пола Δ$fRot°');
  final designH = readDesignCeilingHeightCm(room);
  if (designH != null && (designH - room.ceilingHeightCm).abs() > 1) {
    parts.add('высота Δ${(room.ceilingHeightCm - designH).round()} см');
  }
  if (hasDesignCeilingFeaturesBaseline(room)) {
    final feat = formatCeilingFeaturesDeltaLabel(room);
    if (!feat.startsWith('Направляющие и свет совпадают')) parts.add(feat);
  }
  if (parts.isEmpty) return 'Проект отделки совпадает с фактом';
  return 'Факт vs проект: ${parts.join(' · ')}';
}
