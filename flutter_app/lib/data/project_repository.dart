import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

/// Persistence layer — parity with Python `database.py`.
class ProjectRepository {
  ProjectRepository(this._db);

  final Database _db;

  List<Project>? _listCache;
  Map<int, double>? _areaCache;

  /// Sync peek for UI — filled by [warmCaches] / prior loads.
  List<Project>? get cachedProjects =>
      _listCache == null ? null : List<Project>.from(_listCache!);
  Map<int, double>? get cachedAreas =>
      _areaCache == null ? null : Map<int, double>.from(_areaCache!);

  void invalidateListCache() {
    _listCache = null;
    _areaCache = null;
  }

  /// Warm caches so first screen open feels instant.
  Future<void> warmCaches() async {
    await Future.wait([listProjects(), projectFloorAreasM2()]);
  }

  Future<List<Project>> listProjects({bool force = false}) async {
    if (!force && _listCache != null) return List<Project>.from(_listCache!);
    final rows = await _db.query(
      'projects',
      columns: ['id', 'name', 'created_at'],
      orderBy: 'created_at DESC',
    );
    final list = rows.map((row) {
      return Project(
        id: row['id'] as int,
        name: row['name'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
    _listCache = list;
    return List<Project>.from(list);
  }

  /// All project floor areas in one rooms query (avoids N+1 getProject).
  Future<Map<int, double>> projectFloorAreasM2({bool force = false}) async {
    if (!force && _areaCache != null) return Map<int, double>.from(_areaCache!);
    final rows = await _db.query(
      'rooms',
      columns: ['project_id', 'walls_json'],
    );
    final out = <int, double>{};
    for (final row in rows) {
      final pid = row['project_id'] as int;
      final wallsRaw = jsonDecode(row['walls_json'] as String? ?? '[]') as List;
      final walls = wallsRaw
          .map((w) => (w as List).map((e) => (e as num).toDouble()).toList())
          .toList();
      out[pid] = (out[pid] ?? 0) + _polygonAreaM2(walls);
    }
    _areaCache = out;
    return Map<int, double>.from(out);
  }

  static double _polygonAreaM2(List<List<double>> walls) {
    if (walls.isEmpty) return 0;
    final pts = <List<double>>[];
    for (final w in walls) {
      pts.add([w[0], w[1]]);
    }
    pts.add([walls.last[2], walls.last[3]]);
    final uniq = <List<double>>[];
    for (final p in pts) {
      if (uniq.isEmpty || uniq.last[0] != p[0] || uniq.last[1] != p[1]) {
        uniq.add(p);
      }
    }
    if (uniq.length >= 2 &&
        uniq.first[0] == uniq.last[0] &&
        uniq.first[1] == uniq.last[1]) {
      uniq.removeLast();
    }
    if (uniq.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0; i < uniq.length; i++) {
      final a = uniq[i];
      final b = uniq[(i + 1) % uniq.length];
      sum += a[0] * b[1] - b[0] * a[1];
    }
    return sum.abs() / 2.0 / 10000.0;
  }

  Future<Project?> getProject(int projectId) async {
    final rows = await _db.query(
      'projects',
      where: 'id = ?',
      whereArgs: [projectId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final project = Project(
      id: row['id'] as int,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      materialsCeiling: row['materials_ceiling'] as String?,
      materialsSusp: row['materials_susp'] as String?,
      materialsCell: row['materials_cell'] as String?,
      masterPlanJson: _decodeJsonMap(row['master_plan_json'] as String?),
    );

    final roomRows = await _db.query(
      'rooms',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'id ASC',
    );
    for (final r in roomRows) {
      project.rooms.add(_roomFromRow(r));
    }
    return project;
  }

  Future<Project> createProject(String name) async {
    invalidateListCache();
    final project = Project(name: name.trim());
    final id = await _db.insert('projects', {
      'name': project.name,
      'created_at': project.createdAt.toIso8601String(),
      'materials_ceiling': project.materialsCeiling,
      'materials_susp': project.materialsSusp,
      'materials_cell': project.materialsCell,
      'master_plan_json':
          project.masterPlanJson == null ? null : jsonEncode(project.masterPlanJson),
    });
    project.id = id;
    return project;
  }

  Future<void> renameProject(int projectId, String name) async {
    invalidateListCache();
    await _db.update(
      'projects',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  /// Full save (project + rooms replace), like Python `save_project`.
  Future<void> saveProject(Project project) async {
    invalidateListCache();
    await _db.transaction((txn) async {
      if (project.id == null) {
        project.id = await txn.insert('projects', {
          'name': project.name,
          'created_at': project.createdAt.toIso8601String(),
          'materials_ceiling': project.materialsCeiling,
          'materials_susp': project.materialsSusp,
          'materials_cell': project.materialsCell,
          'master_plan_json':
              project.masterPlanJson == null ? null : jsonEncode(project.masterPlanJson),
        });
      } else {
        await txn.update(
          'projects',
          {
            'name': project.name,
            'created_at': project.createdAt.toIso8601String(),
            'materials_ceiling': project.materialsCeiling,
            'materials_susp': project.materialsSusp,
            'materials_cell': project.materialsCell,
            'master_plan_json':
                project.masterPlanJson == null ? null : jsonEncode(project.masterPlanJson),
          },
          where: 'id = ?',
          whereArgs: [project.id],
        );
      }

      await txn.delete('rooms', where: 'project_id = ?', whereArgs: [project.id]);
      for (final room in project.rooms) {
        room.projectId = project.id;
        room.id = await txn.insert('rooms', _roomToMap(room, project.id!));
      }
    });
  }

  Future<bool> deleteProject(int projectId) async {
    invalidateListCache();
    return _db.transaction((txn) async {
      await txn.delete('rooms', where: 'project_id = ?', whereArgs: [projectId]);
      final n = await txn.delete('projects', where: 'id = ?', whereArgs: [projectId]);
      return n > 0;
    });
  }

  Future<Room> createRoom(int projectId, String name) async {
    invalidateListCache();
    final room = Room(name: name.trim(), projectId: projectId);
    room.id = await _db.insert('rooms', _roomToMap(room, projectId));
    return room;
  }

  Future<void> renameRoom(int roomId, String name) async {
    invalidateListCache();
    await _db.update(
      'rooms',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [roomId],
    );
  }

  Future<void> updateRoom(Room room) async {
    if (room.id == null || room.projectId == null) {
      throw ArgumentError('Room must have id and projectId');
    }
    invalidateListCache();
    await _db.update(
      'rooms',
      _roomToMap(room, room.projectId!),
      where: 'id = ?',
      whereArgs: [room.id],
    );
  }

  Future<bool> deleteRoom(int projectId, int roomId) async {
    invalidateListCache();
    final n = await _db.delete(
      'rooms',
      where: 'id = ? AND project_id = ?',
      whereArgs: [roomId, projectId],
    );
    return n > 0;
  }

  Future<void> updateMasterPlan(int projectId, Map<String, dynamic>? plan) async {
    invalidateListCache();
    await _db.update(
      'projects',
      {'master_plan_json': plan == null ? null : jsonEncode(plan)},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<void> updateProjectMaterials(
    int projectId, {
    String? ceiling,
    String? susp,
    String? cell,
  }) async {
    await _db.update(
      'projects',
      {
        'materials_ceiling': ceiling,
        'materials_susp': susp,
        'materials_cell': cell,
      },
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<void> updateRoomMaterials(
    int roomId, {
    required bool override,
    String? ceiling,
    String? susp,
    String? cell,
  }) async {
    await _db.update(
      'rooms',
      {
        'materials_override': override ? 1 : 0,
        'materials_ceiling': ceiling,
        'materials_susp': susp,
        'materials_cell': cell,
      },
      where: 'id = ?',
      whereArgs: [roomId],
    );
  }

  Map<String, Object?> _roomToMap(Room room, int projectId) {
    return {
      'project_id': projectId,
      'name': room.name,
      'created_at': room.createdAt.toIso8601String(),
      'walls_json': jsonEncode(room.walls),
      'last_position_json':
          room.lastPosition == null ? null : jsonEncode(room.lastPosition),
      'grid_offset_x': room.gridOffsetX,
      'grid_offset_y': room.gridOffsetY,
      'materials_override': room.materialsOverride ? 1 : 0,
      'materials_ceiling': room.materialsCeiling,
      'materials_susp': room.materialsSusp,
      'materials_cell': room.materialsCell,
      'light_fixtures_json': jsonEncode(room.lightFixtures),
      'layout_view_json':
          room.layoutViewJson == null ? null : jsonEncode(room.layoutViewJson),
      'layout_confirmed': room.layoutConfirmed ? 1 : 0,
      'ceiling_guides_json': jsonEncode(room.ceilingGuides),
      'ceiling_height_cm': room.ceilingHeightCm,
      'finish_tile_size_cm': room.finishTileWidthCm,
      'finish_tile_width_cm': room.finishTileWidthCm,
      'finish_tile_height_cm': room.finishTileHeightCm,
      'floor_grid_offset_x': room.floorGridOffsetX,
      'floor_grid_offset_y': room.floorGridOffsetY,
      'openings_json': jsonEncode(room.openings),
      'wall_finish_layers_json': jsonEncode(room.wallFinishLayers),
      'floor_covering_kind': room.floorCoveringKind,
      'floor_laying_pattern': room.floorLayingPattern,
      'floor_layout_rotation_deg': room.floorLayoutRotationDeg,
    };
  }

  Map<String, dynamic>? _decodeJsonMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Room _roomFromRow(Map<String, Object?> row) {
    final wallsRaw = jsonDecode(row['walls_json'] as String? ?? '[]') as List;
    final walls = wallsRaw
        .map((w) => (w as List).map((e) => (e as num).toDouble()).toList())
        .toList();

    List<double>? lastPosition;
    final lp = row['last_position_json'] as String?;
    if (lp != null && lp.isNotEmpty) {
      final decoded = jsonDecode(lp) as List;
      lastPosition = decoded.map((e) => (e as num).toDouble()).toList();
    }

    List<List<int>> lights = [];
    final lj = row['light_fixtures_json'] as String?;
    if (lj != null && lj.isNotEmpty) {
      try {
        final decoded = jsonDecode(lj) as List;
        lights = decoded
            .map((e) => (e as List).map((n) => (n as num).toInt()).toList())
            .toList();
      } catch (_) {
        lights = [];
      }
    }

    Map<String, dynamic>? layoutView;
    final lv = row['layout_view_json'] as String?;
    if (lv != null && lv.isNotEmpty) {
      try {
        layoutView = Map<String, dynamic>.from(jsonDecode(lv) as Map);
      } catch (_) {
        layoutView = null;
      }
    }

    List<Map<String, dynamic>> openings = [];
    final oj = row['openings_json'] as String?;
    if (oj != null && oj.isNotEmpty) {
      try {
        final decoded = jsonDecode(oj) as List;
        openings = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        openings = [];
      }
    }

    List<Map<String, dynamic>> wallLayers = [];
    final wlj = row['wall_finish_layers_json'] as String?;
    if (wlj != null && wlj.isNotEmpty) {
      try {
        final decoded = jsonDecode(wlj) as List;
        wallLayers = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        wallLayers = [];
      }
    }

    List<Map<String, dynamic>> ceilingGuides = [];
    final cgj = row['ceiling_guides_json'] as String?;
    if (cgj != null && cgj.isNotEmpty) {
      try {
        final decoded = jsonDecode(cgj) as List;
        ceilingGuides = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        ceilingGuides = [];
      }
    }

    final legacyTile = (row['finish_tile_size_cm'] as num?)?.toDouble();
    final tileW =
        (row['finish_tile_width_cm'] as num?)?.toDouble() ?? legacyTile ?? 60;
    final tileH =
        (row['finish_tile_height_cm'] as num?)?.toDouble() ?? legacyTile ?? 60;

    return Room(
      id: row['id'] as int,
      projectId: row['project_id'] as int,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      walls: walls,
      lastPosition: lastPosition,
      gridOffsetX: (row['grid_offset_x'] as int?) ?? 0,
      gridOffsetY: (row['grid_offset_y'] as int?) ?? 0,
      materialsOverride: ((row['materials_override'] as int?) ?? 0) == 1,
      materialsCeiling: row['materials_ceiling'] as String?,
      materialsSusp: row['materials_susp'] as String?,
      materialsCell: row['materials_cell'] as String?,
      lightFixtures: lights,
      layoutViewJson: layoutView,
      layoutConfirmed: ((row['layout_confirmed'] as int?) ?? 0) == 1,
      ceilingGuides: ceilingGuides,
      ceilingHeightCm: (row['ceiling_height_cm'] as num?)?.toDouble() ?? 270,
      finishTileWidthCm: tileW,
      finishTileHeightCm: tileH,
      floorGridOffsetX: (row['floor_grid_offset_x'] as int?) ?? 0,
      floorGridOffsetY: (row['floor_grid_offset_y'] as int?) ?? 0,
      openings: openings,
      wallFinishLayers: wallLayers,
      floorCoveringKind: (row['floor_covering_kind'] as String?) ?? 'tile',
      floorLayingPattern: (row['floor_laying_pattern'] as String?) ?? 'straight',
      floorLayoutRotationDeg: (row['floor_layout_rotation_deg'] as int?) ?? 0,
    );
  }
}
