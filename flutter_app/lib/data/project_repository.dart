import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/documentation_model.dart';
import '../domain/room_documentation_status.dart';
import '../domain/special_space.dart';
import '../domain/sync_revisions.dart';

const _prefsOwnerSplit = 'projects_owner_split_v1';

/// Persistence layer — parity with Python `database.py`.
class ProjectRepository {
  ProjectRepository(this._db);

  final Database _db;

  /// Active local account login — projects are scoped per owner.
  String _activeOwnerLogin = 'admin';

  List<Project>? _listCache;
  Map<int, double>? _areaCache;
  Map<int, (int ready, int total)>? _docReadyCache;
  /// Last fully loaded projects (rooms + docs) for instant screen open.
  final Map<int, Project> _projectCache = {};

  String get activeOwnerLogin => _activeOwnerLogin;

  /// Switch which account's projects are visible; clears caches.
  Future<void> setActiveOwnerLogin(String? login) async {
    final next = (login ?? '').trim().toLowerCase();
    final resolved = next.isEmpty ? '__guest__' : next;
    if (resolved == _activeOwnerLogin) {
      invalidateListCache();
      await warmCaches();
      return;
    }
    _activeOwnerLogin = resolved;
    invalidateListCache();
    invalidateProjectCache();
    await warmCaches();
  }

  /// One-shot: assign legacy rows to admin, clone admin → director.
  Future<void> ensureOwnerPartition() async {
    try {
      await _db.execute('ALTER TABLE projects ADD COLUMN owner_login TEXT');
    } catch (_) {}

    await _db.rawUpdate(
      "UPDATE projects SET owner_login = 'admin' "
      "WHERE owner_login IS NULL OR trim(owner_login) = ''",
    );

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsOwnerSplit) == true) return;

    final directorRows = await _db.rawQuery(
      "SELECT COUNT(*) AS c FROM projects WHERE owner_login = 'director'",
    );
    final directorCount = (directorRows.first['c'] as int?) ?? 0;
    if (directorCount == 0) {
      final adminRows = await _db.query(
        'projects',
        columns: ['id'],
        where: "owner_login = ?",
        whereArgs: const ['admin'],
      );
      for (final row in adminRows) {
        final id = row['id'] as int?;
        if (id != null) await cloneProjectToOwner(id, 'director');
      }
    }

    await prefs.setBool(_prefsOwnerSplit, true);
  }

  /// Deep-copy project (rooms + floors + docs JSON) to [ownerLogin].
  Future<int?> cloneProjectToOwner(int sourceId, String ownerLogin) async {
    final src = await _getProjectUnchecked(sourceId);
    if (src == null) return null;
    final owner = ownerLogin.trim().toLowerCase();
    final newId = await _db.insert('projects', {
      'name': src.name,
      'created_at': DateTime.now().toIso8601String(),
      'materials_ceiling': src.materialsCeiling,
      'materials_susp': src.materialsSusp,
      'materials_cell': src.materialsCell,
      'master_plan_json':
          src.masterPlanJson == null ? null : jsonEncode(src.masterPlanJson),
      'documentation_json': src.documentationJson == null
          ? null
          : jsonEncode(src.documentationJson),
      'finish_extra_works_json': src.finishExtraWorksJson == null
          ? null
          : jsonEncode(src.finishExtraWorksJson),
      // Recipient always gets an active project, even if source was archived.
      'archived_at': null,
      'sort_index': src.sortIndex,
      'owner_login': owner,
    });

    final floorMap = <int, int>{};
    for (final f in src.floors) {
      final oldId = f.id;
      final inserted = await insertFloor(
        ProjectFloor(
          projectId: newId,
          name: f.name,
          sortIndex: f.sortIndex,
          floorNumber: f.floorNumber,
          typicalGroupId: f.typicalGroupId,
          typicalIndex: f.typicalIndex,
          typicalSpanEnd: f.typicalSpanEnd,
        ),
      );
      if (oldId != null && inserted.id != null) {
        floorMap[oldId] = inserted.id!;
      }
    }

    var sort = 0;
    for (final room in src.rooms) {
      final copy = room.duplicateAs(room.name);
      copy.projectId = newId;
      copy.sortIndex = sort++;
      final oldFloor = room.floorId;
      if (oldFloor != null && floorMap.containsKey(oldFloor)) {
        copy.floorId = floorMap[oldFloor];
      } else {
        copy.floorId = room.floorId;
      }
      copy.id = await _db.insert('rooms', _roomToMap(copy, newId));
    }
    invalidateListCache();
    return newId;
  }

  /// Build inbox payload with embedded room snapshot (server carries data).
  ///
  /// [roomIds] null/empty → all rooms; otherwise only selected rooms + their floors.
  Future<Map<String, dynamic>> buildProjectSharePayload(
    int projectId, {
    Iterable<int>? roomIds,
  }) async {
    final src = await _getProjectUnchecked(projectId);
    if (src == null) {
      throw StateError('Проект #$projectId не найден на устройстве');
    }
    final idFilter = roomIds == null
        ? null
        : roomIds.map((e) => e).where((e) => e > 0).toSet();
    final rooms = (idFilter == null || idFilter.isEmpty)
        ? List<Room>.from(src.rooms)
        : src.rooms.where((r) => r.id != null && idFilter.contains(r.id)).toList();
    if (rooms.isEmpty) {
      throw StateError('Не выбрано ни одного помещения');
    }

    final floorById = <int, ProjectFloor>{
      for (final f in src.floors)
        if (f.id != null) f.id!: f,
    };
    final usedFloorIds = <int>{
      for (final r in rooms)
        if (r.floorId != null) r.floorId!,
    };
    final floors = src.floors
        .where((f) => f.id != null && usedFloorIds.contains(f.id))
        .toList();
    // If rooms have no floor_id but project has floors, still send none —
    // importer places them on first floor / null.

    final preview = <Map<String, dynamic>>[];
    for (final r in rooms) {
      final floor = r.floorId == null ? null : floorById[r.floorId!];
      preview.add({
        'name': r.name,
        if (floor != null) 'floor': floor.name,
        'area_m2': double.parse(
          _polygonAreaM2(r.walls).toStringAsFixed(2),
        ),
      });
    }

    final updatedAt = await SyncRevisions.get(SyncRevisions.projectKey(src.name));
    return {
      'stub': false,
      'kind': 'project',
      'project_id': projectId,
      'project_name': src.name,
      'from_owner': _activeOwnerLogin,
      'room_count': rooms.length,
      'rooms_preview': preview,
      if (updatedAt != null) 'updated_at': updatedAt.toIso8601String(),
      'snapshot': {
        'name': src.name,
        'materials_ceiling': src.materialsCeiling,
        'materials_susp': src.materialsSusp,
        'materials_cell': src.materialsCell,
        'floors': [
          for (final f in floors) f.toJson(),
        ],
        'rooms': [
          for (final r in rooms)
            _roomToSyncJson(
              r,
              floorName: r.floorId == null ? null : floorById[r.floorId!]?.name,
            ),
        ],
      },
    };
  }

  /// Apply a share payload into a new or existing project for the active owner.
  ///
  /// Prefers embedded [snapshot]; falls back to local [cloneProjectToOwner] by id.
  /// Returns the target project id.
  Future<int> applyProjectSharePayload(
    Map<String, dynamic> payload, {
    int? intoProjectId,
    String? createAsName,
  }) async {
    final snapshotRaw = payload['snapshot'];
    if (snapshotRaw is Map) {
      final snapshot = Map<String, dynamic>.from(snapshotRaw);
      if (intoProjectId != null) {
        await _mergeSnapshotIntoProject(intoProjectId, snapshot);
        invalidateListCache();
        invalidateProjectCache(intoProjectId);
        await warmCaches();
        await _touchProjectRevision(intoProjectId);
        final remoteAt = SyncRevisions.parse(payload['updated_at']);
        if (remoteAt != null) {
          final rows = await _db.query(
            'projects',
            columns: ['name'],
            where: 'id = ?',
            whereArgs: [intoProjectId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            await SyncRevisions.set(
              SyncRevisions.projectKey(rows.first['name'] as String),
              remoteAt,
            );
          }
        }
        return intoProjectId;
      }
      final name = (createAsName ??
              payload['project_name'] as String? ??
              snapshot['name'] as String? ??
              'Объект')
          .trim();
      final created = await createProject(name.isEmpty ? 'Объект' : name);
      final newId = created.id!;
      // createProject already set materials empty — apply snapshot materials.
      await _db.update(
        'projects',
        {
          'materials_ceiling': snapshot['materials_ceiling'] as String?,
          'materials_susp': snapshot['materials_susp'] as String?,
          'materials_cell': snapshot['materials_cell'] as String?,
        },
        where: 'id = ?',
        whereArgs: [newId],
      );
      await _mergeSnapshotIntoProject(newId, snapshot);
      invalidateListCache();
      invalidateProjectCache(newId);
      await warmCaches();
      final remoteAt = SyncRevisions.parse(payload['updated_at']);
      if (remoteAt != null) {
        await SyncRevisions.set(SyncRevisions.projectKey(created.name), remoteAt);
      }
      return newId;
    }

    // Legacy offers: only project_id on same device.
    final pid = payload['project_id'];
    final srcId = pid is num ? pid.toInt() : int.tryParse('$pid');
    if (srcId == null) {
      throw StateError('В сообщении нет данных объекта (snapshot / project_id)');
    }
    if (intoProjectId != null) {
      final src = await _getProjectUnchecked(srcId);
      if (src == null) {
        throw StateError(
          'Локальная копия объекта #$srcId не найдена — '
          'нужен снимок в сообщении или тот же объект на устройстве',
        );
      }
      final fakeSnapshot = {
        'name': src.name,
        'materials_ceiling': src.materialsCeiling,
        'materials_susp': src.materialsSusp,
        'materials_cell': src.materialsCell,
        'floors': [for (final f in src.floors) f.toJson()],
        'rooms': [
          for (final r in src.rooms)
            _roomToSyncJson(
              r,
              floorName: () {
                for (final f in src.floors) {
                  if (f.id == r.floorId) return f.name;
                }
                return null;
              }(),
            ),
        ],
      };
      await _mergeSnapshotIntoProject(intoProjectId, fakeSnapshot);
      invalidateListCache();
      invalidateProjectCache(intoProjectId);
      await warmCaches();
      return intoProjectId;
    }
    final nameHint =
        (createAsName ?? payload['project_name'] as String?)?.trim();
    final newId = await cloneProjectToOwner(srcId, _activeOwnerLogin);
    if (newId == null) {
      throw StateError(
        'Не удалось скопировать объект #$srcId — его нет на этом устройстве',
      );
    }
    if (nameHint != null && nameHint.isNotEmpty) {
      await renameProject(newId, nameHint);
    }
    await warmCaches();
    return newId;
  }

  Future<void> _mergeSnapshotIntoProject(
    int projectId,
    Map<String, dynamic> snapshot,
  ) async {
    final existingFloors = await getFloors(projectId);
    final floorIdByName = <String, int>{
      for (final f in existingFloors)
        if (f.id != null) f.name: f.id!,
    };
    // Map snapshot floor id → local floor id (by recreating / matching name).
    final snapFloorIdToLocal = <int, int>{};
    final floorsRaw = snapshot['floors'];
    if (floorsRaw is List) {
      for (final raw in floorsRaw) {
        if (raw is! Map) continue;
        final fj = Map<String, dynamic>.from(raw);
        final oldId = (fj['id'] as num?)?.toInt();
        final name = (fj['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        var localId = floorIdByName[name];
        if (localId == null) {
          final inserted = await insertFloor(
            ProjectFloor(
              projectId: projectId,
              name: name,
              sortIndex: (fj['sort_index'] as num?)?.toInt() ??
                  existingFloors.length,
              floorNumber: (fj['floor_number'] as num?)?.toInt() ?? 1,
              typicalGroupId: (fj['typical_group_id'] as num?)?.toInt(),
              typicalIndex: (fj['typical_index'] as num?)?.toInt() ?? 0,
              typicalSpanEnd: (fj['typical_span_end'] as num?)?.toInt(),
            ),
          );
          localId = inserted.id;
          if (localId != null) {
            floorIdByName[name] = localId;
            existingFloors.add(inserted);
          }
        }
        if (oldId != null && localId != null) {
          snapFloorIdToLocal[oldId] = localId;
        }
      }
    }

    final roomsRaw = snapshot['rooms'];
    if (roomsRaw is! List || roomsRaw.isEmpty) return;

    var sort = await _nextRoomSortIndex(projectId);
    for (final raw in roomsRaw) {
      if (raw is! Map) continue;
      final rj = Map<String, dynamic>.from(raw);
      final room = _roomFromSyncJson(rj);
      room.projectId = projectId;
      room.id = null;
      room.sortIndex = sort++;
      final floorName = rj['floor_name'] as String?;
      final snapFloorId = (rj['floor_id'] as num?)?.toInt();
      if (floorName != null && floorIdByName.containsKey(floorName)) {
        room.floorId = floorIdByName[floorName];
      } else if (snapFloorId != null &&
          snapFloorIdToLocal.containsKey(snapFloorId)) {
        room.floorId = snapFloorIdToLocal[snapFloorId];
      } else if (existingFloors.isNotEmpty) {
        room.floorId = existingFloors.first.id;
      } else {
        room.floorId = null;
      }
      room.id = await _db.insert('rooms', _roomToMap(room, projectId));
    }
  }

  Map<String, dynamic> _roomToSyncJson(Room room, {String? floorName}) {
    final row = _roomToMap(room, room.projectId ?? 0);
    return {
      for (final e in row.entries)
        if (e.key != 'project_id') e.key: e.value,
      if (room.id != null) 'source_room_id': room.id,
      if (floorName != null) 'floor_name': floorName,
    };
  }

  Room _roomFromSyncJson(Map<String, dynamic> j) {
    // Reuse row parser: sync map already uses *_json string fields.
    final row = <String, Object?>{
      for (final e in j.entries) e.key: e.value,
      'id': null,
      'project_id': 0,
    };
    return _roomFromRow(row);
  }

  Future<Project?> _getProjectUnchecked(int projectId) async {
    final previous = _activeOwnerLogin;
    _activeOwnerLogin = ''; // empty → skip owner filter in getProject
    try {
      // Direct load without ownership gate:
      final rows = await _db.query(
        'projects',
        where: 'id = ?',
        whereArgs: [projectId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
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
        documentationJson:
            _decodeJsonMap(row['documentation_json'] as String?),
        finishExtraWorksJson:
            _decodeJsonMap(row['finish_extra_works_json'] as String?),
        archivedAt:
            archivedRaw == null ? null : DateTime.parse(archivedRaw),
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
      return project;
    } finally {
      _activeOwnerLogin = previous;
    }
  }

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
      where: archived
          ? 'archived_at IS NOT NULL AND owner_login = ?'
          : 'archived_at IS NULL AND owner_login = ?',
      whereArgs: [_activeOwnerLogin],
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
      'SELECT COUNT(*) AS c FROM projects '
      'WHERE archived_at IS NOT NULL AND owner_login = ?',
      [_activeOwnerLogin],
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
    final owned = await _db.query(
      'projects',
      columns: ['id'],
      where: 'owner_login = ?',
      whereArgs: [_activeOwnerLogin],
    );
    final ownedIds = {for (final r in owned) r['id'] as int};
    final rows = await _db.query(
      'rooms',
      columns: ['project_id', 'walls_json'],
    );
    final out = <int, double>{};
    for (final row in rows) {
      final pid = row['project_id'] as int;
      if (!ownedIds.contains(pid)) continue;
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
    final projectRows = await _db.query(
      'projects',
      where: 'owner_login = ?',
      whereArgs: [_activeOwnerLogin],
    );
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
      where: _activeOwnerLogin.isEmpty
          ? 'id = ?'
          : 'id = ? AND owner_login = ?',
      whereArgs: _activeOwnerLogin.isEmpty
          ? [projectId]
          : [projectId, _activeOwnerLogin],
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
      'SELECT MAX(sort_index) AS m FROM projects '
      'WHERE archived_at IS NULL AND owner_login = ?',
      [_activeOwnerLogin],
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
      'owner_login': _activeOwnerLogin,
    });
    project.id = id;
    await SyncRevisions.touch(SyncRevisions.projectKey(project.name));
    return project;
  }

  Future<void> _touchProjectRevision(int? projectId) async {
    if (projectId == null) return;
    final rows = await _db.query(
      'projects',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [projectId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await SyncRevisions.touch(
      SyncRevisions.projectKey(rows.first['name'] as String),
    );
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
          'owner_login': _activeOwnerLogin,
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
    await _touchProjectRevision(room.projectId);
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
      id: (row['id'] as num?)?.toInt(),
      projectId: (row['project_id'] as num?)?.toInt(),
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
