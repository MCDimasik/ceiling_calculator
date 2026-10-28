import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/documentation_model.dart';
import '../domain/room_documentation_status.dart';
import '../domain/special_space.dart';

/// Persistence layer — parity with Python `database.py`.
class ProjectRepository {
  ProjectRepository(this._db);

  final Database _db;

  List<Project>? _listCache;
  Map<int, double>? _areaCache;
  Map<int, (int ready, int total)>? _docReadyCache;
  /// Last fully loaded projects (rooms + docs) for instant screen open.
  final Map<int, Project> _projectCache = {};

  /// Sync peek for UI — filled by [warmCaches] / prior loads.
  List<Project>? get cachedProjects =>
      _listCache == null ? null : List<Project>.from(_listCache!);
  Map<int, double>? get cachedAreas =>
      _areaCache == null ? null : Map<int, double>.from(_areaCache!);
  Map<int, (int ready, int total)>? get cachedDocReady =>
      _docReadyCache == null
          ? null
          : Map<int, (int ready, int total)>.from(_docReadyCache!);

  /// Sync peek of a fully loaded project (null if never fetched this session).
  Project? peekCachedProject(int projectId) => _projectCache[projectId];

  void invalidateListCache() {
    _listCache = null;
    _areaCache = null;
    _docReadyCache = null;
    // Keep [_projectCache]: screens peek it for instant open; writers call
    // [invalidateProjectCache] for the touched project.
  }

  void invalidateProjectCache([int? projectId]) {
    if (projectId == null) {
      _projectCache.clear();
    } else {
      _projectCache.remove(projectId);
    }
    _docReadyCache = null;
  }

  /// Warm caches so first screen open feels instant.
  Future<void> warmCaches() async {
    await Future.wait([
      listProjects(),
      projectFloorAreasM2(),
      projectDocumentationReadyCounts(),
    ]);
  }

  Future<List<Project>> listProjects({
    bool force = false,
    bool archived = false,
  }) async {
    if (!force && !archived && _listCache != null) {
      return List<Project>.from(_listCache!);
    }
    final rows = await _db.query(
      'projects',
      columns: ['id', 'name', 'created_at', 'archived_at', 'sort_index'],
      where: archived ? 'archived_at IS NOT NULL' : 'archived_at IS NULL',
      orderBy: archived
          ? 'archived_at DESC'
          : 'sort_index ASC, created_at DESC, id DESC',
    );
    final list = rows.map(_projectFromListRow).toList();
    if (!archived) _listCache = list;
    return List<Project>.from(list);
  }

  Future<int> archivedProjectCount() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM projects WHERE archived_at IS NOT NULL',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Project _projectFromListRow(Map<String, Object?> row) {
    final archivedRaw = row['archived_at'] as String?;
    return Project(
      id: row['id'] as int,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      archivedAt: archivedRaw == null ? null : DateTime.parse(archivedRaw),
      sortIndex: (row['sort_index'] as int?) ?? 0,
    );
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

  /// Rooms ready for handover per project (documentation module list).
  Future<Map<int, (int ready, int total)>> projectDocumentationReadyCounts({
    bool force = false,
  }) async {
    if (!force && _docReadyCache != null) {
      return Map<int, (int ready, int total)>.from(_docReadyCache!);
    }
    final projectRows = await _db.query('projects');
    final projects = <int, Project>{
      for (final row in projectRows)
        row['id'] as int: Project(
          id: row['id'] as int,
          name: row['name'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          materialsCeiling: row['materials_ceiling'] as String?,
          materialsSusp: row['materials_susp'] as String?,
          materialsCell: row['materials_cell'] as String?,
        ),
    };
    final roomRows = await _db.query('rooms', orderBy: 'project_id ASC, created_at DESC, id DESC');
    final out = <int, (int ready, int total)>{};
    for (final pid in projects.keys) {
      out[pid] = (0, 0);
    }
    for (final row in roomRows) {
      final pid = row['project_id'] as int;
      final project = projects[pid];
      if (project == null) continue;
      final room = _roomFromRow(row);
      final summary = roomDocumentationSummary(
        room,
        project,
        checklist: RoomDocumentationChecklist.fromJson(room.documentationChecklistJson),
      );
      final prev = out[pid] ?? (0, 0);
      out[pid] = (
        prev.$1 + (summary.readyForHandover ? 1 : 0),
        prev.$2 + 1,
      );
    }
    _docReadyCache = out;
    return Map<int, (int ready, int total)>.from(out);
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
    if (rows.isEmpty) {
      _projectCache.remove(projectId);
      return null;
    }
    final row = rows.first;
    final archivedRaw = row['archived_at'] as String?;
    final project = Project(
      id: row['id'] as int,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      materialsCeiling: row['materials_ceiling'] as String?,
      materialsSusp: row['materials_susp'] as String?,
      materialsCell: row['materials_cell'] as String?,
      masterPlanJson: _decodeJsonMap(row['master_plan_json'] as String?),
      documentationJson: _decodeJsonMap(row['documentation_json'] as String?),
      finishExtraWorksJson:
          _decodeJsonMap(row['finish_extra_works_json'] as String?),
      archivedAt: archivedRaw == null ? null : DateTime.parse(archivedRaw),
      sortIndex: (row['sort_index'] as int?) ?? 0,
    );

    final roomRows = await _db.query(
      'rooms',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'sort_index ASC, created_at DESC, id DESC',
    );
    for (final r in roomRows) {
      project.rooms.add(_roomFromRow(r));
    }
    project.floors.addAll(await getFloors(projectId));
    // One-shot cleanup: orphan floor_ids after deleted typical floors.
    if (project.floors.isNotEmpty) {
      final valid = project.floors.map((f) => f.id).whereType<int>().toSet();
      final needsFix = project.rooms.any(
        (r) => r.floorId == null || !valid.contains(r.floorId),
      );
      if (needsFix) {
        await _reconcileRoomFloors(projectId);
        project.rooms.clear();
        final roomRows2 = await _db.query(
          'rooms',
          where: 'project_id = ?',
          whereArgs: [projectId],
          orderBy: 'sort_index ASC, created_at DESC, id DESC',
        );
        for (final r in roomRows2) {
          project.rooms.add(_roomFromRow(r));
        }
      }
    }
    _projectCache[projectId] = project;
    return project;
  }

  Future<int> _nextProjectSortIndex() async {
    final rows = await _db.rawQuery(
      'SELECT MAX(sort_index) AS m FROM projects WHERE archived_at IS NULL',
    );
    return ((rows.first['m'] as int?) ?? -1) + 1;
  }

  Future<int> _nextRoomSortIndex(int projectId) async {
    final rows = await _db.rawQuery(
      'SELECT MAX(sort_index) AS m FROM rooms WHERE project_id = ?',
      [projectId],
    );
    return ((rows.first['m'] as int?) ?? -1) + 1;
  }

  Future<Project> createProject(String name) async {
    invalidateListCache();
    final project = Project(name: name.trim(), sortIndex: await _nextProjectSortIndex());
    final id = await _db.insert('projects', {
      'name': project.name,
      'created_at': project.createdAt.toIso8601String(),
      'materials_ceiling': project.materialsCeiling,
      'materials_susp': project.materialsSusp,
      'materials_cell': project.materialsCell,
      'master_plan_json':
          project.masterPlanJson == null ? null : jsonEncode(project.masterPlanJson),
      'documentation_json':
          project.documentationJson == null ? null : jsonEncode(project.documentationJson),
      'finish_extra_works_json': project.finishExtraWorksJson == null
          ? null
          : jsonEncode(project.finishExtraWorksJson),
      'sort_index': project.sortIndex,
    });
    project.id = id;
    return project;
  }

  /// Persist project list order (ids from top to bottom).
  Future<void> reorderProjects(List<int> projectIdsInOrder) async {
    invalidateListCache();
    final batch = _db.batch();
    for (var i = 0; i < projectIdsInOrder.length; i++) {
      batch.update(
        'projects',
        {'sort_index': i},
        where: 'id = ?',
        whereArgs: [projectIdsInOrder[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Persist room list order within a project.
  Future<void> reorderRooms(int projectId, List<int> roomIdsInOrder) async {
    invalidateListCache();
    final batch = _db.batch();
    for (var i = 0; i < roomIdsInOrder.length; i++) {
      batch.update(
        'rooms',
        {'sort_index': i},
        where: 'id = ? AND project_id = ?',
        whereArgs: [roomIdsInOrder[i], projectId],
      );
    }
    await batch.commit(noResult: true);
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
          'finish_extra_works_json': project.finishExtraWorksJson == null
              ? null
              : jsonEncode(project.finishExtraWorksJson),
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
            'documentation_json': project.documentationJson == null
                ? null
                : jsonEncode(project.documentationJson),
            'finish_extra_works_json': project.finishExtraWorksJson == null
                ? null
                : jsonEncode(project.finishExtraWorksJson),
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
    invalidateProjectCache(projectId);
    return _db.transaction((txn) async {
      await txn.delete('rooms', where: 'project_id = ?', whereArgs: [projectId]);
      final n = await txn.delete('projects', where: 'id = ?', whereArgs: [projectId]);
      return n > 0;
    });
  }

  Future<void> archiveProject(int projectId) async {
    invalidateListCache();
    invalidateProjectCache(projectId);
    await _db.update(
      'projects',
      {'archived_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<void> unarchiveProject(int projectId) async {
    invalidateListCache();
    invalidateProjectCache(projectId);
    await _db.update(
      'projects',
      {'archived_at': null},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<Room> createRoom(
    int projectId,
    String name, {
    int? floorId,
    bool mirrorToTypicalGroup = true,
  }) async {
    return createRoomOnFloor(
      projectId,
      name,
      floorId: floorId,
      mirrorToTypicalGroup: mirrorToTypicalGroup,
    );
  }

  /// Create rectangular rooms (walls in cm) in one batch.
  Future<List<Room>> createRectRooms(
    int projectId,
    List<({String name, double lengthCm, double widthCm})> specs, {
    int? floorId,
  }) async {
    invalidateListCache();
    invalidateProjectCache(projectId);
    final out = <Room>[];
    var sort = await _nextRoomSortIndex(projectId);
    for (final spec in specs) {
      final name = spec.name.trim();
      if (name.isEmpty || spec.lengthCm <= 0 || spec.widthCm <= 0) continue;
      final l = spec.lengthCm;
      final w = spec.widthCm;
      final room = Room(
        name: name,
        projectId: projectId,
        sortIndex: sort++,
        floorId: floorId,
        walls: [
          [0, 0, l, 0],
          [l, 0, l, w],
          [l, w, 0, w],
          [0, w, 0, 0],
        ],
      );
      room.id = await _db.insert('rooms', _roomToMap(room, projectId));
      out.add(room);
    }
    return out;
  }

  /// Copy geometry, finish layers, ceiling layout; checklist/photos are not copied.
  Future<Room> duplicateRoom(int projectId, Room source, String newName) async {
    invalidateListCache();
    invalidateProjectCache(projectId);
    final copy = source.duplicateAs(newName.trim());
    copy.projectId = projectId;
    copy.sortIndex = await _nextRoomSortIndex(projectId);
    copy.id = await _db.insert('rooms', _roomToMap(copy, projectId));
    return copy;
  }

  /// Typical floor: copy one room to many names at once.
  Future<List<Room>> duplicateRoomBulk(
    int projectId,
    Room source,
    List<String> names,
  ) async {
    invalidateListCache();
    final out = <Room>[];
    var sort = await _nextRoomSortIndex(projectId);
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      final copy = source.duplicateAs(trimmed);
      copy.projectId = projectId;
      copy.sortIndex = sort++;
      copy.id = await _db.insert('rooms', _roomToMap(copy, projectId));
      out.add(copy);
    }
    return out;
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
    invalidateProjectCache(room.projectId);
    await _db.update(
      'rooms',
      _roomToMap(room, room.projectId!),
      where: 'id = ?',
      whereArgs: [room.id],
    );
  }

  Future<bool> deleteRoom(int projectId, int roomId) async {
    invalidateListCache();
    invalidateProjectCache(projectId);
    final n = await _db.delete(
      'rooms',
      where: 'id = ? AND project_id = ?',
      whereArgs: [roomId, projectId],
    );
    return n > 0;
  }

  Future<void> updateMasterPlan(int projectId, Map<String, dynamic>? plan) async {
    invalidateListCache();
    invalidateProjectCache(projectId);
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

  Future<void> updateProjectDocumentation(
    int projectId, {
    required Map<String, dynamic>? documentationJson,
  }) async {
    invalidateListCache();
    invalidateProjectCache(projectId);
    await _db.update(
      'projects',
      {'documentation_json': documentationJson == null ? null : jsonEncode(documentationJson)},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<void> updateFinishExtraWorks(
    int projectId, {
    required Map<String, dynamic>? finishExtraWorksJson,
  }) async {
    invalidateListCache();
    invalidateProjectCache(projectId);
    await _db.update(
      'projects',
      {
        'finish_extra_works_json': finishExtraWorksJson == null
            ? null
            : jsonEncode(finishExtraWorksJson),
      },
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<void> updateRoomChecklist(
    int roomId, {
    required Map<String, dynamic>? checklistJson,
  }) async {
    invalidateListCache();
    final pidRows = await _db.query(
      'rooms',
      columns: ['project_id'],
      where: 'id = ?',
      whereArgs: [roomId],
      limit: 1,
    );
    if (pidRows.isNotEmpty) {
      invalidateProjectCache(pidRows.first['project_id'] as int);
    }
    await _db.update(
      'rooms',
      {
        'documentation_checklist_json':
            checklistJson == null ? null : jsonEncode(checklistJson),
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
      'floor_prep_layers_json': jsonEncode(room.floorPrepLayers),
      'ceiling_prep_layers_json': jsonEncode(room.ceilingPrepLayers),
      'floor_covering_kind': room.floorCoveringKind,
      'floor_laying_pattern': room.floorLayingPattern,
      'floor_layout_rotation_deg': room.floorLayoutRotationDeg,
      'floor_screed_depth_cm': room.floorScreedDepthCm,
      'floor_covering_unit_price': room.floorCoveringUnitPrice,
      'ceiling_system_unit_price': room.ceilingSystemUnitPrice,
      'floor_covering_rate_match_key': room.floorCoveringRateMatchKey,
      'floor_covering_rate_name': room.floorCoveringRateName,
      'ceiling_system_rate_match_key': room.ceilingSystemRateMatchKey,
      'ceiling_system_rate_name': room.ceilingSystemRateName,
      'floor_covering_materials_json':
          jsonEncode(room.floorCoveringMaterials),
      'ceiling_system_materials_json':
          jsonEncode(room.ceilingSystemMaterials),
      'documentation_checklist_json': room.documentationChecklistJson == null
          ? null
          : jsonEncode(room.documentationChecklistJson),
      'finish_include_floor': room.finishIncludeFloor ? 1 : 0,
      'finish_include_walls': room.finishIncludeWalls ? 1 : 0,
      'finish_include_ceiling': room.finishIncludeCeiling ? 1 : 0,
      'finish_include_extra_works': room.finishIncludeExtraWorks ? 1 : 0,
      'sort_index': room.sortIndex,
      'floor_id': room.floorId,
      'special_space_json': room.specialSpaceJson,
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

    List<Map<String, dynamic>> decodeLayerList(String? raw) {
      if (raw == null || raw.isEmpty) return [];
      try {
        final decoded = jsonDecode(raw) as List;
        return decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        return [];
      }
    }

    final floorPrep = decodeLayerList(row['floor_prep_layers_json'] as String?);
    final ceilingPrep =
        decodeLayerList(row['ceiling_prep_layers_json'] as String?);

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
      floorPrepLayers: floorPrep,
      ceilingPrepLayers: ceilingPrep,
      floorCoveringKind: (row['floor_covering_kind'] as String?) ?? 'tile',
      floorLayingPattern: (row['floor_laying_pattern'] as String?) ?? 'straight',
      floorLayoutRotationDeg: (row['floor_layout_rotation_deg'] as int?) ?? 0,
      floorScreedDepthCm: (row['floor_screed_depth_cm'] as num?)?.toDouble() ?? 5,
      floorCoveringUnitPrice:
          (row['floor_covering_unit_price'] as num?)?.toDouble(),
      ceilingSystemUnitPrice:
          (row['ceiling_system_unit_price'] as num?)?.toDouble(),
      floorCoveringRateMatchKey:
          row['floor_covering_rate_match_key'] as String?,
      floorCoveringRateName: row['floor_covering_rate_name'] as String?,
      ceilingSystemRateMatchKey:
          row['ceiling_system_rate_match_key'] as String?,
      ceilingSystemRateName: row['ceiling_system_rate_name'] as String?,
      floorCoveringMaterials: decodeLayerList(
        row['floor_covering_materials_json'] as String?,
      ),
      ceilingSystemMaterials: decodeLayerList(
        row['ceiling_system_materials_json'] as String?,
      ),
      documentationChecklistJson:
          _decodeJsonMap(row['documentation_checklist_json'] as String?),
      finishIncludeFloor: ((row['finish_include_floor'] as int?) ?? 1) == 1,
      finishIncludeWalls: ((row['finish_include_walls'] as int?) ?? 1) == 1,
      finishIncludeCeiling: ((row['finish_include_ceiling'] as int?) ?? 1) == 1,
      finishIncludeExtraWorks:
          ((row['finish_include_extra_works'] as int?) ?? 1) == 1,
      sortIndex: (row['sort_index'] as int?) ?? 0,
      floorId: row['floor_id'] as int?,
      specialSpaceJson: row['special_space_json'] as String?,
    );
  }

  // --- Floors ---

  Future<List<ProjectFloor>> getFloors(int projectId) async {
    final rows = await _db.query(
      'project_floors',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'sort_index ASC, floor_number ASC, id ASC',
    );
    return rows.map(_floorFromRow).toList();
  }

  Future<ProjectFloor> insertFloor(ProjectFloor floor) async {
    final id = await _db.insert('project_floors', _floorToMap(floor));
    return floor.copyWith(id: id);
  }

  Future<void> updateFloor(ProjectFloor floor) async {
    if (floor.id == null) return;
    await _db.update(
      'project_floors',
      _floorToMap(floor),
      where: 'id = ?',
      whereArgs: [floor.id],
    );
  }

  /// Deletes a floor and its rooms (avoids orphan copies counting as «1 этаж»).
  Future<void> deleteFloor(int floorId) async {
    invalidateListCache();
    final rows = await _db.query(
      'project_floors',
      columns: ['project_id'],
      where: 'id = ?',
      whereArgs: [floorId],
      limit: 1,
    );
    final projectId = rows.isEmpty ? null : rows.first['project_id'] as int?;
    await _db.delete('rooms', where: 'floor_id = ?', whereArgs: [floorId]);
    await _db.delete(
      'project_floors',
      where: 'id = ?',
      whereArgs: [floorId],
    );
    if (projectId != null) {
      invalidateProjectCache(projectId);
      await _reconcileRoomFloors(projectId);
    }
  }

  /// Fix floor assignments after deletes:
  /// - no floors → clear floor_id
  /// - orphan floor_id / null: drop typical copies (same name+walls as a kept room),
  ///   otherwise bind unique rooms to floor 1.
  Future<void> _reconcileRoomFloors(int projectId) async {
    final floors = await getFloors(projectId);
    if (floors.isEmpty) {
      await _db.update(
        'rooms',
        {'floor_id': null},
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
      return;
    }
    final validIds = floors.map((f) => f.id).whereType<int>().toSet();
    ProjectFloor lead = floors.first;
    for (final f in floors) {
      if (f.floorNumber == 1 && f.typicalIndex == 0) {
        lead = f;
        break;
      }
    }
    final leadId = lead.id;
    if (leadId == null) return;

    final roomRows = await _db.query(
      'rooms',
      where: 'project_id = ?',
      whereArgs: [projectId],
    );
    final rooms = roomRows.map(_roomFromRow).toList();
    String fp(Room r) =>
        '${r.name.trim().toLowerCase()}|${r.walls.length}|'
        '${r.walls.isEmpty ? 0 : r.walls.first.join(",")}';

    final keptKeys = <String>{};
    for (final r in rooms) {
      final fid = r.floorId;
      if (fid != null && validIds.contains(fid)) {
        keptKeys.add(fp(r));
      }
    }

    for (final r in rooms) {
      final fid = r.floorId;
      final orphan = fid == null || !validIds.contains(fid);
      if (!orphan || r.id == null) continue;
      if (keptKeys.contains(fp(r))) {
        // Typical copy left after floor delete — remove.
        await _db.delete('rooms', where: 'id = ?', whereArgs: [r.id]);
      } else {
        await _db.update(
          'rooms',
          {'floor_id': leadId},
          where: 'id = ?',
          whereArgs: [r.id],
        );
        keptKeys.add(fp(r));
      }
    }
  }

  /// Turns an existing unique floor into a typical block of [totalCount] floors.
  /// Rooms on [floorId] become the template; copies are cloned onto new floors.
  Future<List<ProjectFloor>> makeFloorTypical({
    required int projectId,
    required int floorId,
    required int totalCount,
  }) async {
    invalidateListCache();
    invalidateProjectCache(projectId);
    final floors = await getFloors(projectId);
    ProjectFloor? template;
    for (final f in floors) {
      if (f.id == floorId) {
        template = f;
        break;
      }
    }
    if (template == null || template.id == null) return const [];
    if (template.isTypicalGroup) {
      // Already typical — nothing to do (extend via addFloors if needed).
      return [template];
    }
    final n = totalCount < 2 ? 2 : totalCount;
    final start = template.floorNumber;
    final spanEnd = start + n - 1;
    final groupId = DateTime.now().millisecondsSinceEpoch;

    template
      ..name = '$start–$spanEnd типовой'
      ..typicalGroupId = groupId
      ..typicalIndex = 0
      ..typicalSpanEnd = spanEnd;
    await updateFloor(template);

    final project = await getProject(projectId);
    final sources = (project?.rooms ?? [])
        .where((r) => r.floorId == floorId)
        .toList();

    final nextSort =
        floors.map((f) => f.sortIndex).fold<int>(0, (a, b) => a > b ? a : b) +
            1;
    final created = <ProjectFloor>[template];
    for (var i = 1; i < n; i++) {
      final num = start + i;
      final floor = await insertFloor(
        ProjectFloor(
          projectId: projectId,
          name: '$num этаж',
          sortIndex: nextSort + i - 1,
          floorNumber: num,
          typicalGroupId: groupId,
          typicalIndex: i,
        ),
      );
      created.add(floor);
      var sort = await _nextRoomSortIndex(projectId);
      for (final src in sources) {
        // Special spaces already encode multi-storey / one-off volumes.
        if (src.isSpecialSpace) continue;
        final copy = src.duplicateAs(src.name);
        copy.projectId = projectId;
        copy.floorId = floor.id;
        copy.sortIndex = sort++;
        copy.id = await _db.insert('rooms', _roomToMap(copy, projectId));
      }
    }
    invalidateProjectCache(projectId);
    return created;
  }

  /// Creates one or more floors. For typical: [count] floors sharing a group,
  /// with room copies from [sourceRoomIds] onto each new floor.
  Future<List<ProjectFloor>> addFloors({
    required int projectId,
    required int startNumber,
    required int count,
    required bool typical,
    List<int> sourceRoomIds = const [],
  }) async {
    invalidateListCache();
    invalidateProjectCache(projectId);

    // Promote implicit floor-1 rooms when first explicit floor is created.
    var existing = await getFloors(projectId);
    if (existing.isEmpty) {
      final first = await insertFloor(
        ProjectFloor(
          projectId: projectId,
          name: '1 этаж',
          sortIndex: 0,
          floorNumber: 1,
        ),
      );
      await _db.update(
        'rooms',
        {'floor_id': first.id},
        where: 'project_id = ? AND floor_id IS NULL',
        whereArgs: [projectId],
      );
      existing = [first];
    }

    final nextSort =
        existing.map((f) => f.sortIndex).fold<int>(0, (a, b) => a > b ? a : b) +
            1;
    final maxNum =
        existing.map((f) => f.floorNumber).fold<int>(0, (a, b) => a > b ? a : b);
    final start = startNumber > 0 ? startNumber : maxNum + 1;
    final n = count < 1 ? 1 : count;
    final isTypical = typical && n > 1;
    final groupId = isTypical ? DateTime.now().millisecondsSinceEpoch : null;
    final spanEnd = isTypical ? start + n - 1 : null;

    final project = await getProject(projectId);
    final allRooms = project?.rooms ?? [];
    final sources = <Room>[
      for (final rid in sourceRoomIds)
        ...allRooms.where((r) => r.id == rid),
    ];

    final created = <ProjectFloor>[];
    for (var i = 0; i < n; i++) {
      final num = start + i;
      final floor = await insertFloor(
        ProjectFloor(
          projectId: projectId,
          name: isTypical && i == 0
              ? '$start–$spanEnd типовой'
              : '$num этаж',
          sortIndex: nextSort + i,
          floorNumber: num,
          typicalGroupId: groupId,
          typicalIndex: i,
          typicalSpanEnd: i == 0 ? spanEnd : null,
        ),
      );
      created.add(floor);

      var sort = await _nextRoomSortIndex(projectId);
      for (final src in sources) {
        if (src.isSpecialSpace) continue;
        final copy = src.duplicateAs(src.name);
        copy.projectId = projectId;
        copy.floorId = floor.id;
        copy.sortIndex = sort++;
        copy.id = await _db.insert('rooms', _roomToMap(copy, projectId));
      }
    }

    invalidateProjectCache(projectId);
    return created;
  }

  Future<Room> createRoomOnFloor(
    int projectId,
    String name, {
    int? floorId,
    bool mirrorToTypicalGroup = true,
  }) async {
    invalidateListCache();
    invalidateProjectCache(projectId);
    final room = Room(
      name: name.trim(),
      projectId: projectId,
      sortIndex: await _nextRoomSortIndex(projectId),
      floorId: floorId,
    );
    room.id = await _db.insert('rooms', _roomToMap(room, projectId));

    // Mirror new room onto typical copies of this floor's group.
    // Special spaces (ЛК) must not be mirrored — they span floors in params.
    if (mirrorToTypicalGroup && floorId != null) {
      final floors = await getFloors(projectId);
      ProjectFloor? template;
      for (final f in floors) {
        if (f.id == floorId) {
          template = f;
          break;
        }
      }
      if (template != null &&
          template.typicalGroupId != null &&
          template.typicalIndex == 0) {
        final copies = floors.where(
          (f) =>
              f.typicalGroupId == template!.typicalGroupId &&
              f.typicalIndex > 0,
        );
        var sort = await _nextRoomSortIndex(projectId);
        for (final f in copies) {
          final copy = room.duplicateAs(room.name);
          copy.projectId = projectId;
          copy.floorId = f.id;
          copy.sortIndex = sort++;
          copy.id = await _db.insert('rooms', _roomToMap(copy, projectId));
        }
      }
    }
    return room;
  }

  Map<String, Object?> _floorToMap(ProjectFloor floor) {
    return {
      'project_id': floor.projectId,
      'name': floor.name,
      'sort_index': floor.sortIndex,
      'floor_number': floor.floorNumber,
      'typical_group_id': floor.typicalGroupId,
      'typical_index': floor.typicalIndex,
      'typical_span_end': floor.typicalSpanEnd,
    };
  }

  ProjectFloor _floorFromRow(Map<String, Object?> row) {
    return ProjectFloor(
      id: row['id'] as int,
      projectId: row['project_id'] as int,
      name: row['name'] as String,
      sortIndex: (row['sort_index'] as int?) ?? 0,
      floorNumber: (row['floor_number'] as int?) ?? 1,
      typicalGroupId: row['typical_group_id'] as int?,
      typicalIndex: (row['typical_index'] as int?) ?? 0,
      typicalSpanEnd: row['typical_span_end'] as int?,
    );
  }
}
