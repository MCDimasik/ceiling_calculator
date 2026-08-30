/// Domain models matching the Python/Kivy models + DB columns.
library;

class Project {
  Project({
    required this.name,
    DateTime? createdAt,
    this.id,
    List<Room>? rooms,
    this.materialsCeiling,
    this.materialsSusp,
    this.materialsCell,
    this.masterPlanJson,
  })  : createdAt = createdAt ?? DateTime.now(),
        rooms = rooms ?? [];

  int? id;
  String name;
  DateTime createdAt;
  List<Room> rooms;
  String? materialsCeiling;
  String? materialsSusp;
  String? materialsCell;

  /// Master object plan (rooms placed + shared walls). JSON map.
  Map<String, dynamic>? masterPlanJson;

  Project copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    List<Room>? rooms,
    String? materialsCeiling,
    String? materialsSusp,
    String? materialsCell,
    Map<String, dynamic>? masterPlanJson,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      rooms: rooms ?? this.rooms,
      materialsCeiling: materialsCeiling ?? this.materialsCeiling,
      materialsSusp: materialsSusp ?? this.materialsSusp,
      materialsCell: materialsCell ?? this.materialsCell,
      masterPlanJson: masterPlanJson ?? this.masterPlanJson,
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
    this.floorCoveringKind = 'tile',
    this.floorLayingPattern = 'straight',
    this.floorLayoutRotationDeg = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        walls = walls ?? [],
        lightFixtures = lightFixtures ?? [],
        openings = openings ?? [],
        wallFinishLayers = wallFinishLayers ?? [],
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

  /// `tile` | `laminate` (see [FloorCoveringKind]).
  String floorCoveringKind;

  /// See [FloorLayingPattern] ids.
  String floorLayingPattern;

  /// Floor layout rotation: 0 / 90 / 180 / 270.
  int floorLayoutRotationDeg;

  bool get hasLayout => walls.length >= 3;

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
    String? floorCoveringKind,
    String? floorLayingPattern,
    int? floorLayoutRotationDeg,
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
      floorCoveringKind: floorCoveringKind ?? this.floorCoveringKind,
      floorLayingPattern: floorLayingPattern ?? this.floorLayingPattern,
      floorLayoutRotationDeg: floorLayoutRotationDeg ?? this.floorLayoutRotationDeg,
    );
  }
}
