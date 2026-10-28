/// Domain models matching the Python/Kivy models + DB columns.
library;

/// One floor (or a typical-floor group shown as a single page).
///
/// When a project has only the implicit first floor, [ProjectFloor] rows may be
/// empty and rooms have `floorId == null` — UI must not show "1 этаж".
class ProjectFloor {
  ProjectFloor({
    this.id,
    required this.projectId,
    required this.name,
    this.sortIndex = 0,
    this.floorNumber = 1,
    this.typicalGroupId,
    this.typicalIndex = 0,
    this.typicalSpanEnd,
  });

  int? id;
  int projectId;
  String name;
  int sortIndex;

  /// Display / sort number (1, 2, …). For typical groups this is the start.
  int floorNumber;

  /// Shared id for a typical block (2–6). Null = unique floor.
  int? typicalGroupId;

  /// 0 = template of the group; >0 = synced copy (hidden in UI pager).
  int typicalIndex;

  /// If set with [floorNumber], label becomes «2–6 типовой».
  int? typicalSpanEnd;

  bool get isTypicalGroup =>
      typicalGroupId != null &&
      typicalSpanEnd != null &&
      typicalSpanEnd! > floorNumber;

  bool get isTypicalTemplate => typicalGroupId != null && typicalIndex == 0;

  /// Shown in floor switcher; copies with typicalIndex>0 are hidden.
  bool get showInPager => typicalIndex == 0;

  String get pagerLabel {
    if (isTypicalGroup) {
      return '$floorNumber–$typicalSpanEnd типовой';
    }
    return name.isNotEmpty ? name : '$floorNumber этаж';
  }

  ProjectFloor copyWith({
    int? id,
    int? projectId,
    String? name,
    int? sortIndex,
    int? floorNumber,
    int? typicalGroupId,
    int? typicalIndex,
    int? typicalSpanEnd,
  }) {
    return ProjectFloor(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      sortIndex: sortIndex ?? this.sortIndex,
      floorNumber: floorNumber ?? this.floorNumber,
      typicalGroupId: typicalGroupId ?? this.typicalGroupId,
      typicalIndex: typicalIndex ?? this.typicalIndex,
      typicalSpanEnd: typicalSpanEnd ?? this.typicalSpanEnd,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'project_id': projectId,
        'name': name,
        'sort_index': sortIndex,
        'floor_number': floorNumber,
        if (typicalGroupId != null) 'typical_group_id': typicalGroupId,
        'typical_index': typicalIndex,
        if (typicalSpanEnd != null) 'typical_span_end': typicalSpanEnd,
      };

  static ProjectFloor fromJson(Map<String, dynamic> json) => ProjectFloor(
        id: (json['id'] as num?)?.toInt(),
        projectId: (json['project_id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        sortIndex: (json['sort_index'] as num?)?.toInt() ?? 0,
        floorNumber: (json['floor_number'] as num?)?.toInt() ?? 1,
        typicalGroupId: (json['typical_group_id'] as num?)?.toInt(),
        typicalIndex: (json['typical_index'] as num?)?.toInt() ?? 0,
        typicalSpanEnd: (json['typical_span_end'] as num?)?.toInt(),
      );
}

class Project {
  Project({
    required this.name,
    DateTime? createdAt,
    this.id,
    List<Room>? rooms,
    List<ProjectFloor>? floors,
    this.materialsCeiling,
    this.materialsSusp,
    this.materialsCell,
    this.masterPlanJson,
    this.documentationJson,
    this.finishExtraWorksJson,
    this.archivedAt,
    this.sortIndex = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        rooms = rooms ?? [],
        floors = floors ?? [];

  int? id;
  String name;
  DateTime createdAt;
  DateTime? archivedAt;
  List<Room> rooms;

  /// Explicit floors. Empty = single implicit floor (no «1 этаж» label).
  List<ProjectFloor> floors;

  /// Manual list order (lower first). Ties broken by created_at.
  int sortIndex;
  String? materialsCeiling;
  String? materialsSusp;
  String? materialsCell;

  /// Master object plan (rooms placed + shared walls). JSON map.
  Map<String, dynamic>? masterPlanJson;

  /// Stamp, certificates, vedomost template path.
  Map<String, dynamic>? documentationJson;

  /// Extra finish works + user templates (JSON map). See [FinishExtraWorksState].
  Map<String, dynamic>? finishExtraWorksJson;

  Project copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    List<Room>? rooms,
    List<ProjectFloor>? floors,
    String? materialsCeiling,
    String? materialsSusp,
    String? materialsCell,
    Map<String, dynamic>? masterPlanJson,
    Map<String, dynamic>? documentationJson,
    Map<String, dynamic>? finishExtraWorksJson,
    DateTime? archivedAt,
    int? sortIndex,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      rooms: rooms ?? this.rooms,
      floors: floors ?? this.floors,
      materialsCeiling: materialsCeiling ?? this.materialsCeiling,
      materialsSusp: materialsSusp ?? this.materialsSusp,
      materialsCell: materialsCell ?? this.materialsCell,
      masterPlanJson: masterPlanJson ?? this.masterPlanJson,
      documentationJson: documentationJson ?? this.documentationJson,
      finishExtraWorksJson: finishExtraWorksJson ?? this.finishExtraWorksJson,
      archivedAt: archivedAt ?? this.archivedAt,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }
}

class Room {
  Room({
    required this.name,
    DateTime? createdAt,
    this.id,
    this.projectId,
    List<List<double>>? walls,
    this.lastPosition,
    this.gridOffsetX = 0,
    this.gridOffsetY = 0,
    this.materialsOverride = false,
    this.materialsCeiling,
    this.materialsSusp,
    this.materialsCell,
    List<List<int>>? lightFixtures,
    this.layoutViewJson,
    List<Map<String, dynamic>>? ceilingGuides,
    this.layoutConfirmed = false,
    this.ceilingHeightCm = 270,
    this.floorGridOffsetX = 0,
    this.floorGridOffsetY = 0,
    double finishTileWidthCm = 60,
    double finishTileHeightCm = 60,
    double? finishTileSizeCm,
    List<Map<String, dynamic>>? openings,
    List<Map<String, dynamic>>? wallFinishLayers,
    List<Map<String, dynamic>>? floorPrepLayers,
    List<Map<String, dynamic>>? ceilingPrepLayers,
    this.floorCoveringKind = 'tile',
    this.floorLayingPattern = 'straight',
    this.floorLayoutRotationDeg = 0,
    this.floorScreedDepthCm = 5,
    this.floorCoveringUnitPrice,
    this.ceilingSystemUnitPrice,
    this.floorCoveringRateMatchKey,
    this.floorCoveringRateName,
    this.ceilingSystemRateMatchKey,
    this.ceilingSystemRateName,
    List<Map<String, dynamic>>? floorCoveringMaterials,
    List<Map<String, dynamic>>? ceilingSystemMaterials,
    this.documentationChecklistJson,
    this.finishIncludeFloor = true,
    this.finishIncludeWalls = true,
    this.finishIncludeCeiling = true,
    this.finishIncludeExtraWorks = true,
    this.sortIndex = 0,
    this.floorId,
    this.specialSpaceJson,
  })  : createdAt = createdAt ?? DateTime.now(),
        walls = walls ?? [],
        lightFixtures = lightFixtures ?? [],
        openings = openings ?? [],
        wallFinishLayers = wallFinishLayers ?? [],
        floorPrepLayers = floorPrepLayers ?? [],
        ceilingPrepLayers = ceilingPrepLayers ?? [],
        floorCoveringMaterials = floorCoveringMaterials ?? [],
        ceilingSystemMaterials = ceilingSystemMaterials ?? [],
        ceilingGuides = ceilingGuides ?? [],
        finishTileWidthCm = finishTileSizeCm ?? finishTileWidthCm,
        finishTileHeightCm = finishTileSizeCm ?? finishTileHeightCm;

  int? id;
  int? projectId;
  String name;
  DateTime createdAt;

  /// Walls as [[x1, y1, x2, y2], ...] in cm.
  List<List<double>> walls;

  /// Last editor cursor position [x, y] or null.
  List<double>? lastPosition;

  int gridOffsetX;
  int gridOffsetY;

  bool materialsOverride;
  String? materialsCeiling;
  String? materialsSusp;
  String? materialsCell;

  /// Light fixture cell indices [[ix, iy], ...].
  List<List<int>> lightFixtures;

  /// Saved layout camera: `{scale, tx, ty}`.
  Map<String, dynamic>? layoutViewJson;

  /// After the operator leaves layout once, reopen in Pan mode (grid shift locked).
  bool layoutConfirmed;

  /// Marked ceiling guide lines on layout (`axis`, `pos`, `kind`).
  List<Map<String, dynamic>> ceilingGuides;

  /// Finish module: room height to ceiling (cm).
  double ceilingHeightCm;

  /// Floor tile layout offset (separate from ceiling [gridOffsetX]/[gridOffsetY]).
  int floorGridOffsetX;
  int floorGridOffsetY;

  /// Floor tile / module size (cm) — may be rectangular.
  double finishTileWidthCm;
  double finishTileHeightCm;

  /// Finish module: opening types as JSON maps (see [RoomOpening]).
  List<Map<String, dynamic>> openings;

  /// Ordered wall finish layers (see [FinishLayer]).
  List<Map<String, dynamic>> wallFinishLayers;

  /// Optional preparatory floor layers under the main covering (see [SurfacePrepLayer]).
  List<Map<String, dynamic>> floorPrepLayers;

  /// Optional preparatory ceiling layers under the main ceiling finish.
  List<Map<String, dynamic>> ceilingPrepLayers;

  /// `tile` | `laminate` | `screed` (see [FloorCoveringKind]).
  String floorCoveringKind;

  /// See [FloorLayingPattern] ids.
  String floorLayingPattern;

  /// Floor layout rotation in degrees (any angle; UI nudges by 1°).
  int floorLayoutRotationDeg;

  /// Screed thickness (cm) when [floorCoveringKind] is screed.
  double floorScreedDepthCm;

  /// Work rate for the main floor covering: ₽/м³ for screed, ₽/м² otherwise.
  double? floorCoveringUnitPrice;
  String? floorCoveringRateMatchKey;
  String? floorCoveringRateName;

  /// Optional purchase materials for the main floor covering (see [FinishMaterialLink]).
  List<Map<String, dynamic>> floorCoveringMaterials;

  /// Work ₽/м² for the main ceiling system (Armstrong / Grilyato / …).
  double? ceilingSystemUnitPrice;
  String? ceilingSystemRateMatchKey;
  String? ceilingSystemRateName;

  /// Optional purchase materials for ceiling system mount (see [FinishMaterialLink]).
  List<Map<String, dynamic>> ceilingSystemMaterials;

  /// Manual checklist / acceptance flags for documentation module.
  Map<String, dynamic>? documentationChecklistJson;

  /// Include floor finish in vedomost / docs / KS readiness (default on).
  bool finishIncludeFloor;

  /// Include wall finish in vedomost / docs / KS readiness (default on).
  bool finishIncludeWalls;

  /// Include ceiling finish + layout purchase in vedomost / docs (default on).
  bool finishIncludeCeiling;

  /// Include room-scoped «другие работы» in aggregates (default on).
  bool finishIncludeExtraWorks;

  /// Manual list order within the project (lower first).
  int sortIndex;

  /// Floor this room belongs to (`project_floors.id`). Null = implicit 1st floor.
  int? floorId;

  /// JSON for volume-only / stairwell spaces (see [SpecialSpace] in special_space.dart).
  String? specialSpaceJson;

  /// Whether [section] label from finish vedomost is enabled for this room.
  bool includesFinishSection(String section) {
    switch (section) {
      case 'Пол':
        return finishIncludeFloor;
      case 'Стены':
        return finishIncludeWalls;
      case 'Потолок':
        return finishIncludeCeiling;
      case 'Расходники':
        return finishIncludeFloor || finishIncludeWalls || finishIncludeCeiling;
      case 'Другие работы':
        // Extra works: include whenever lines exist (no per-room switch).
        return true;
      default:
        return true;
    }
  }

  /// Contour usable for layout/BOM: ≥3 walls and closed polygon.
  bool get hasLayout {
    if (walls.length < 3) return false;
    final start = (walls.first[0], walls.first[1]);
    final end = (walls.last[2], walls.last[3]);
    final dx = end.$1 - start.$1;
    final dy = end.$2 - start.$2;
    return dx * dx + dy * dy <= 0.01; // ≤0.1 cm
  }

  /// Deep copy for «типовой этаж» / duplicate room (geometry + finish, без акта).
  Room duplicateAs(String newName) {
    return Room(
      name: newName,
      projectId: projectId,
      walls: walls.map((w) => List<double>.from(w)).toList(),
      lastPosition: lastPosition == null ? null : List<double>.from(lastPosition!),
      gridOffsetX: gridOffsetX,
      gridOffsetY: gridOffsetY,
      materialsOverride: materialsOverride,
      materialsCeiling: materialsCeiling,
      materialsSusp: materialsSusp,
      materialsCell: materialsCell,
      lightFixtures: lightFixtures.map((c) => List<int>.from(c)).toList(),
      layoutViewJson: layoutViewJson == null
          ? null
          : Map<String, dynamic>.from(layoutViewJson!),
      layoutConfirmed: layoutConfirmed,
      ceilingGuides: ceilingGuides.map((g) => Map<String, dynamic>.from(g)).toList(),
      ceilingHeightCm: ceilingHeightCm,
      floorGridOffsetX: floorGridOffsetX,
      floorGridOffsetY: floorGridOffsetY,
      finishTileWidthCm: finishTileWidthCm,
      finishTileHeightCm: finishTileHeightCm,
      openings: openings.map((o) => Map<String, dynamic>.from(o)).toList(),
      wallFinishLayers: wallFinishLayers.map((l) => Map<String, dynamic>.from(l)).toList(),
      floorPrepLayers: floorPrepLayers.map((l) => Map<String, dynamic>.from(l)).toList(),
      ceilingPrepLayers:
          ceilingPrepLayers.map((l) => Map<String, dynamic>.from(l)).toList(),
      floorCoveringKind: floorCoveringKind,
      floorLayingPattern: floorLayingPattern,
      floorLayoutRotationDeg: floorLayoutRotationDeg,
      floorScreedDepthCm: floorScreedDepthCm,
      floorCoveringUnitPrice: floorCoveringUnitPrice,
      ceilingSystemUnitPrice: ceilingSystemUnitPrice,
      floorCoveringRateMatchKey: floorCoveringRateMatchKey,
      floorCoveringRateName: floorCoveringRateName,
      ceilingSystemRateMatchKey: ceilingSystemRateMatchKey,
      ceilingSystemRateName: ceilingSystemRateName,
      floorCoveringMaterials:
          floorCoveringMaterials.map((m) => Map<String, dynamic>.from(m)).toList(),
      ceilingSystemMaterials:
          ceilingSystemMaterials.map((m) => Map<String, dynamic>.from(m)).toList(),
      finishIncludeFloor: finishIncludeFloor,
      finishIncludeWalls: finishIncludeWalls,
      finishIncludeCeiling: finishIncludeCeiling,
      finishIncludeExtraWorks: finishIncludeExtraWorks,
      sortIndex: sortIndex,
      floorId: floorId,
      specialSpaceJson: specialSpaceJson,
    );
  }

  Room copyWith({
    int? id,
    int? projectId,
    String? name,
    DateTime? createdAt,
    List<List<double>>? walls,
    List<double>? lastPosition,
    int? gridOffsetX,
    int? gridOffsetY,
    bool? materialsOverride,
    String? materialsCeiling,
    String? materialsSusp,
    String? materialsCell,
    List<List<int>>? lightFixtures,
    Map<String, dynamic>? layoutViewJson,
    bool? layoutConfirmed,
    List<Map<String, dynamic>>? ceilingGuides,
    double? ceilingHeightCm,
    int? floorGridOffsetX,
    int? floorGridOffsetY,
    double? finishTileWidthCm,
    double? finishTileHeightCm,
    List<Map<String, dynamic>>? openings,
    List<Map<String, dynamic>>? wallFinishLayers,
    List<Map<String, dynamic>>? floorPrepLayers,
    List<Map<String, dynamic>>? ceilingPrepLayers,
    String? floorCoveringKind,
    String? floorLayingPattern,
    int? floorLayoutRotationDeg,
    double? floorScreedDepthCm,
    double? floorCoveringUnitPrice,
    double? ceilingSystemUnitPrice,
    String? floorCoveringRateMatchKey,
    String? floorCoveringRateName,
    String? ceilingSystemRateMatchKey,
    String? ceilingSystemRateName,
    List<Map<String, dynamic>>? floorCoveringMaterials,
    List<Map<String, dynamic>>? ceilingSystemMaterials,
    Map<String, dynamic>? documentationChecklistJson,
    bool? finishIncludeFloor,
    bool? finishIncludeWalls,
    bool? finishIncludeCeiling,
    bool? finishIncludeExtraWorks,
    int? sortIndex,
    int? floorId,
    String? specialSpaceJson,
  }) {
    return Room(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      walls: walls ?? this.walls,
      lastPosition: lastPosition ?? this.lastPosition,
      gridOffsetX: gridOffsetX ?? this.gridOffsetX,
      gridOffsetY: gridOffsetY ?? this.gridOffsetY,
      materialsOverride: materialsOverride ?? this.materialsOverride,
      materialsCeiling: materialsCeiling ?? this.materialsCeiling,
      materialsSusp: materialsSusp ?? this.materialsSusp,
      materialsCell: materialsCell ?? this.materialsCell,
      lightFixtures: lightFixtures ?? this.lightFixtures,
      layoutViewJson: layoutViewJson ?? this.layoutViewJson,
      layoutConfirmed: layoutConfirmed ?? this.layoutConfirmed,
      ceilingGuides: ceilingGuides ?? this.ceilingGuides,
      ceilingHeightCm: ceilingHeightCm ?? this.ceilingHeightCm,
      floorGridOffsetX: floorGridOffsetX ?? this.floorGridOffsetX,
      floorGridOffsetY: floorGridOffsetY ?? this.floorGridOffsetY,
      finishTileWidthCm: finishTileWidthCm ?? this.finishTileWidthCm,
      finishTileHeightCm: finishTileHeightCm ?? this.finishTileHeightCm,
      openings: openings ?? this.openings,
      wallFinishLayers: wallFinishLayers ?? this.wallFinishLayers,
      floorPrepLayers: floorPrepLayers ?? this.floorPrepLayers,
      ceilingPrepLayers: ceilingPrepLayers ?? this.ceilingPrepLayers,
      floorCoveringKind: floorCoveringKind ?? this.floorCoveringKind,
      floorLayingPattern: floorLayingPattern ?? this.floorLayingPattern,
      floorLayoutRotationDeg: floorLayoutRotationDeg ?? this.floorLayoutRotationDeg,
      floorScreedDepthCm: floorScreedDepthCm ?? this.floorScreedDepthCm,
      floorCoveringUnitPrice:
          floorCoveringUnitPrice ?? this.floorCoveringUnitPrice,
      ceilingSystemUnitPrice:
          ceilingSystemUnitPrice ?? this.ceilingSystemUnitPrice,
      floorCoveringRateMatchKey:
          floorCoveringRateMatchKey ?? this.floorCoveringRateMatchKey,
      floorCoveringRateName:
          floorCoveringRateName ?? this.floorCoveringRateName,
      ceilingSystemRateMatchKey:
          ceilingSystemRateMatchKey ?? this.ceilingSystemRateMatchKey,
      ceilingSystemRateName:
          ceilingSystemRateName ?? this.ceilingSystemRateName,
      floorCoveringMaterials:
          floorCoveringMaterials ?? this.floorCoveringMaterials,
      ceilingSystemMaterials:
          ceilingSystemMaterials ?? this.ceilingSystemMaterials,
      documentationChecklistJson:
          documentationChecklistJson ?? this.documentationChecklistJson,
      finishIncludeFloor: finishIncludeFloor ?? this.finishIncludeFloor,
      finishIncludeWalls: finishIncludeWalls ?? this.finishIncludeWalls,
      finishIncludeCeiling: finishIncludeCeiling ?? this.finishIncludeCeiling,
      finishIncludeExtraWorks:
          finishIncludeExtraWorks ?? this.finishIncludeExtraWorks,
      sortIndex: sortIndex ?? this.sortIndex,
      floorId: floorId ?? this.floorId,
      specialSpaceJson: specialSpaceJson ?? this.specialSpaceJson,
    );
  }
}
