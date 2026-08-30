import 'dart:convert';

import '../domain/models.dart';

const formatVersion = 1;
const fileExtension = '.ccproj';

Map<String, dynamic> buildExportPayload(Project project, {List<Room>? rooms}) {
  final roomList = rooms ?? project.rooms;
  final exportName = rooms != null && rooms.length == 1 ? rooms.first.name : project.name;
  return {
    'format_version': formatVersion,
    'exported_at': DateTime.now().toIso8601String(),
    'project': {
      'name': exportName,
      'created_at': project.createdAt.toIso8601String(),
      'materials_ceiling': project.materialsCeiling,
      'materials_susp': project.materialsSusp,
      'materials_cell': project.materialsCell,
      'master_plan': project.masterPlanJson,
      'rooms': roomList.map(_roomExportDict).toList(),
    },
  };
}

String encodeProjectFile(Project project, {List<Room>? rooms}) {
  return const JsonEncoder.withIndent('  ').convert(buildExportPayload(project, rooms: rooms));
}

Project decodeProjectFile(String raw) {
  final payload = jsonDecode(raw) as Map<String, dynamic>;
  final version = payload['format_version'] as int? ?? 0;
  if (version > formatVersion) {
    throw FormatException('Файл создан в более новой версии приложения.');
  }
  final data = payload['project'] as Map<String, dynamic>?;
  if (data == null) throw FormatException('Некорректный файл проекта.');

  final project = Project(
    name: data['name'] as String,
    createdAt: DateTime.parse(data['created_at'] as String? ?? DateTime.now().toIso8601String()),
    materialsCeiling: data['materials_ceiling'] as String?,
    materialsSusp: data['materials_susp'] as String?,
    materialsCell: data['materials_cell'] as String?,
    masterPlanJson: data['master_plan'] is Map
        ? Map<String, dynamic>.from(data['master_plan'] as Map)
        : null,
  );
  final roomsRaw = data['rooms'] as List? ?? [];
  project.rooms = roomsRaw.map((e) => _roomFromExport(e as Map<String, dynamic>)).toList();
  return project;
}

String safeExportBasename(String name) {
  final forbidden = RegExp(r'[<>:"/\\|?*]');
  final cleaned = name.trim().replaceAll(forbidden, '');
  if (cleaned.isEmpty) return 'project';
  return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
}

Map<String, dynamic> _roomExportDict(Room room) => {
      'name': room.name,
      'created_at': room.createdAt.toIso8601String(),
      'walls': room.walls,
      'last_position': room.lastPosition,
      'grid_offset_x': room.gridOffsetX,
      'grid_offset_y': room.gridOffsetY,
      'light_fixtures': room.lightFixtures,
      'materials_override': room.materialsOverride,
      'materials_ceiling': room.materialsCeiling,
      'materials_susp': room.materialsSusp,
      'materials_cell': room.materialsCell,
      'layout_view': room.layoutViewJson,
      'layout_confirmed': room.layoutConfirmed,
      'ceiling_guides': room.ceilingGuides,
      'ceiling_height_cm': room.ceilingHeightCm,
      'finish_tile_width_cm': room.finishTileWidthCm,
      'finish_tile_height_cm': room.finishTileHeightCm,
      'finish_tile_size_cm': room.finishTileWidthCm,
      'floor_grid_offset_x': room.floorGridOffsetX,
      'floor_grid_offset_y': room.floorGridOffsetY,
      'openings': room.openings,
      'wall_finish_layers': room.wallFinishLayers,
      'floor_covering_kind': room.floorCoveringKind,
      'floor_laying_pattern': room.floorLayingPattern,
      'floor_layout_rotation_deg': room.floorLayoutRotationDeg,
    };

Room _roomFromExport(Map<String, dynamic> data) {
  final wallsRaw = data['walls'] as List? ?? [];
  final walls = wallsRaw
      .map((w) => (w as List).map((e) => (e as num).toDouble()).toList())
      .toList();
  List<double>? lastPosition;
  final lp = data['last_position'];
  if (lp is List) {
    lastPosition = lp.map((e) => (e as num).toDouble()).toList();
  }
  List<List<int>> lights = [];
  final lf = data['light_fixtures'];
  if (lf is List) {
    lights = lf.map((e) => (e as List).map((n) => (n as num).toInt()).toList()).toList();
  }
  Map<String, dynamic>? layoutView;
  final lv = data['layout_view'];
  if (lv is Map) {
    layoutView = Map<String, dynamic>.from(lv);
  }
  List<Map<String, dynamic>> openings = [];
  final op = data['openings'];
  if (op is List) {
    openings = op.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  List<Map<String, dynamic>> wallLayers = [];
  final wl = data['wall_finish_layers'];
  if (wl is List) {
    wallLayers = wl.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  List<Map<String, dynamic>> ceilingGuides = [];
  final cg = data['ceiling_guides'];
  if (cg is List) {
    ceilingGuides = cg.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  return Room(
    name: data['name'] as String,
    createdAt: DateTime.parse(data['created_at'] as String? ?? DateTime.now().toIso8601String()),
    walls: walls,
    lastPosition: lastPosition,
    gridOffsetX: (data['grid_offset_x'] as num?)?.toInt() ?? 0,
    gridOffsetY: (data['grid_offset_y'] as num?)?.toInt() ?? 0,
    lightFixtures: lights,
    materialsOverride: data['materials_override'] as bool? ?? false,
    materialsCeiling: data['materials_ceiling'] as String?,
    materialsSusp: data['materials_susp'] as String?,
    materialsCell: data['materials_cell'] as String?,
    layoutViewJson: layoutView,
    layoutConfirmed: data['layout_confirmed'] as bool? ?? false,
    ceilingGuides: ceilingGuides,
    ceilingHeightCm: (data['ceiling_height_cm'] as num?)?.toDouble() ?? 270,
    finishTileWidthCm: (data['finish_tile_width_cm'] as num?)?.toDouble() ??
        (data['finish_tile_size_cm'] as num?)?.toDouble() ??
        60,
    finishTileHeightCm: (data['finish_tile_height_cm'] as num?)?.toDouble() ??
        (data['finish_tile_size_cm'] as num?)?.toDouble() ??
        60,
    floorGridOffsetX: (data['floor_grid_offset_x'] as num?)?.toInt() ?? 0,
    floorGridOffsetY: (data['floor_grid_offset_y'] as num?)?.toInt() ?? 0,
    openings: openings,
    wallFinishLayers: wallLayers,
    floorCoveringKind: data['floor_covering_kind'] as String? ?? 'tile',
    floorLayingPattern: data['floor_laying_pattern'] as String? ?? 'straight',
    floorLayoutRotationDeg: (data['floor_layout_rotation_deg'] as num?)?.toInt() ?? 0,
  );
}
