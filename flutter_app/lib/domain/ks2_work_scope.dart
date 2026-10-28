import 'documentation_model.dart';
import 'models.dart';
import 'room_finish_areas.dart';

/// Top-level work types for intermediate KS-2 closure (floor → walls → ceiling).
enum WorkScope {
  floor,
  walls,
  ceiling;

  String get labelRu => switch (this) {
        WorkScope.floor => 'Пол',
        WorkScope.walls => 'Стены',
        WorkScope.ceiling => 'Потолок',
      };

  /// Finish vedomost / KS-2 table section names included in this scope.
  List<String> get tableSections => switch (this) {
        WorkScope.floor => ['Пол'],
        WorkScope.walls => ['Стены'],
        WorkScope.ceiling => ['Потолок'],
      };

  /// Optional hidden-works steps associated with this scope (photos not required).
  List<DocumentationStep> get hiddenWorkSteps => switch (this) {
        WorkScope.floor => [DocumentationStep.hwFloor],
        WorkScope.walls => [DocumentationStep.hwWalls],
        WorkScope.ceiling => [
            DocumentationStep.hwCeilingFrame,
            DocumentationStep.hwCeilingGuides,
            DocumentationStep.hwCeilingLights,
            DocumentationStep.hwCeilingTiles,
          ],
      };

  /// Checklist step id → scope (for «suggest KS-2» after photo upload).
  static WorkScope? forHiddenStepId(String stepId) {
    for (final scope in WorkScope.values) {
      if (scope.hiddenWorkSteps.any((s) => s.id == stepId)) return scope;
    }
    return null;
  }

  static WorkScope? parse(String? raw) => switch (raw) {
        'floor' => WorkScope.floor,
        'walls' => WorkScope.walls,
        'ceiling' => WorkScope.ceiling,
        _ => null,
      };

  static List<WorkScope> parseList(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return List.of(values);
    final out = <WorkScope>[];
    for (final e in raw) {
      final s = parse(e.toString());
      if (s != null && !out.contains(s)) out.add(s);
    }
    return out.isEmpty ? List.of(values) : out;
  }

  static List<String> names(Iterable<WorkScope> scopes) =>
      scopes.map((s) => s.name).toList();

  /// Stable key for one or more scopes, e.g. `floor+walls`.
  static String encodeKey(Iterable<WorkScope> scopes) {
    final list = scopes.toList()..sort((a, b) => a.index.compareTo(b.index));
    return list.map((s) => s.name).join('+');
  }
}

/// Parse scope key (`floor`, `floor+walls`, legacy single names).
List<WorkScope> parseScopeKey(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  if (!raw.contains('+')) {
    final s = WorkScope.parse(raw);
    return s != null ? [s] : const [];
  }
  return raw
      .split('+')
      .map(WorkScope.parse)
      .whereType<WorkScope>()
      .toList();
}

String scopeKeyLabel(String scopeKey) =>
    parseScopeKey(scopeKey).map((s) => s.labelRu).join(' + ');

bool actScopeCovers(String actScopeKey, WorkScope scope) =>
    parseScopeKey(actScopeKey).contains(scope);

bool ks2RowMatchesScopes(Map<String, String> row, Iterable<WorkScope> scopes) =>
    scopes.any((s) => ks2RowMatchesScope(row, s));

bool isRoomMultiScopeReady(
  Room room,
  Project project,
  Iterable<WorkScope> scopes,
  RoomDocumentationChecklist checklist,
) {
  for (final scope in scopes) {
    if (!isRoomScopeReady(room, project, scope, checklist)) return false;
  }
  return scopes.isNotEmpty;
}

/// Whether this room includes work for [scope] (finish include flags + geometry).
bool isScopeApplicableToRoom(Room room, Project project, WorkScope scope) {
  if (!roomHasFinishGeometry(room)) return false;
  return switch (scope) {
    WorkScope.floor => room.finishIncludeFloor,
    WorkScope.walls => room.finishIncludeWalls,
    WorkScope.ceiling => room.finishIncludeCeiling,
  };
}

/// Scopes enabled on the project and relevant to at least one room.
List<WorkScope> projectActiveWorkScopes({
  required Project project,
  required ProjectDocumentation doc,
}) {
  final enabled = WorkScope.parseList(doc.enabledWorkScopes);
  return enabled
      .where(
        (scope) => project.rooms.any(
          (r) => isScopeApplicableToRoom(r, project, scope),
        ),
      )
      .toList();
}

/// Infer contract scopes from imported smeta / price lines.
List<WorkScope> inferWorkScopesFromPriceLines(Iterable<ProjectPriceLine> prices) {
  final found = <WorkScope>{};
  for (final line in prices) {
    final key = line.matchKey.toLowerCase();
    if (key.contains('finish_floor') || key == 'floor') {
      found.add(WorkScope.floor);
    } else if (key.contains('finish_wall') || key == 'walls') {
      found.add(WorkScope.walls);
    } else if (key.contains('finish_ceiling') || key == 'ceiling') {
      found.add(WorkScope.ceiling);
    }
  }
  return found.toList()..sort((a, b) => a.index.compareTo(b.index));
}

/// Infer contract scopes from room layouts (first-time hint).
List<WorkScope> inferWorkScopesFromProject(Project project) {
  final out = <WorkScope>[];
  for (final scope in WorkScope.values) {
    if (project.rooms.any((r) => isScopeApplicableToRoom(r, project, scope))) {
      out.add(scope);
    }
  }
  return out.isEmpty ? List.of(WorkScope.values) : out;
}

/// Scopes toggled on for this contract (any subset of floor / walls / ceiling).
List<WorkScope> projectEnabledWorkScopes(ProjectDocumentation doc) =>
    WorkScope.parseList(doc.enabledWorkScopes);

/// Whether a KS-2 table row belongs to [scope].
bool ks2RowMatchesScope(Map<String, String> row, WorkScope scope) {
  final section = row['section'] ?? '';
  // Legacy rows used section «Помещение» for floor/ceiling areas.
  if (section == 'Помещение') {
    final name = (row['name'] ?? '').toLowerCase();
    if (scope == WorkScope.floor && name.contains('пол')) return true;
    if (scope == WorkScope.ceiling && name.contains('потолок')) return true;
    return false;
  }
  return scope.tableSections.contains(section);
}

/// Room can be closed for [scope] in KS-2 (layout + scope applicable).
/// Hidden-works photos are optional and do not gate readiness.
bool isRoomScopeReady(
  Room room,
  Project project,
  WorkScope scope,
  RoomDocumentationChecklist checklist,
) {
  if (!isScopeApplicableToRoom(room, project, scope)) return false;
  return true;
}
