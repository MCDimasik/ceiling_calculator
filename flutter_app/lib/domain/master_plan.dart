/// Master floor plan: rooms placed on one object canvas and optional shared walls.
library;

/// One room instance on the master plan (local room coords + transform).
class MasterRoomPlacement {
  MasterRoomPlacement({
    required this.roomId,
    this.offsetXCm = 0,
    this.offsetYCm = 0,
    this.rotationDeg = 0,
  });

  int roomId;
  double offsetXCm;
  double offsetYCm;

  /// Rotation around room origin, degrees clockwise.
  double rotationDeg;

  Map<String, Object?> toJson() => {
        'room_id': roomId,
        'offset_x_cm': offsetXCm,
        'offset_y_cm': offsetYCm,
        'rotation_deg': rotationDeg,
      };

  static MasterRoomPlacement fromJson(Map<String, dynamic> j) => MasterRoomPlacement(
        roomId: (j['room_id'] as num?)?.toInt() ?? 0,
        offsetXCm: (j['offset_x_cm'] as num?)?.toDouble() ?? 0,
        offsetYCm: (j['offset_y_cm'] as num?)?.toDouble() ?? 0,
        rotationDeg: (j['rotation_deg'] as num?)?.toDouble() ?? 0,
      );
}

/// Shared wall between two placed rooms (not counted twice in finish aggregates).
class MasterSharedWall {
  MasterSharedWall({
    required this.roomIdA,
    required this.wallIndexA,
    required this.roomIdB,
    required this.wallIndexB,
  });

  int roomIdA;
  int wallIndexA;
  int roomIdB;
  int wallIndexB;

  Map<String, Object?> toJson() => {
        'room_id_a': roomIdA,
        'wall_index_a': wallIndexA,
        'room_id_b': roomIdB,
        'wall_index_b': wallIndexB,
      };

  static MasterSharedWall fromJson(Map<String, dynamic> j) => MasterSharedWall(
        roomIdA: (j['room_id_a'] as num?)?.toInt() ?? 0,
        wallIndexA: (j['wall_index_a'] as num?)?.toInt() ?? 0,
        roomIdB: (j['room_id_b'] as num?)?.toInt() ?? 0,
        wallIndexB: (j['wall_index_b'] as num?)?.toInt() ?? 0,
      );
}

/// Project-level master space assembling rooms into one object.
class MasterPlan {
  MasterPlan({
    this.name = 'План объекта',
    List<MasterRoomPlacement>? placements,
    List<MasterSharedWall>? sharedWalls,
  })  : placements = placements ?? [],
        sharedWalls = sharedWalls ?? [];

  String name;
  List<MasterRoomPlacement> placements;
  List<MasterSharedWall> sharedWalls;

  Map<String, Object?> toJson() => {
        'name': name,
        'placements': placements.map((e) => e.toJson()).toList(),
        'shared_walls': sharedWalls.map((e) => e.toJson()).toList(),
      };

  static MasterPlan fromJson(Map<String, dynamic>? j) {
    if (j == null) return MasterPlan();
    final rawP = j['placements'];
    final rawS = j['shared_walls'];
    return MasterPlan(
      name: j['name'] as String? ?? 'План объекта',
      placements: rawP is List
          ? rawP
              .map((e) => MasterRoomPlacement.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : [],
      sharedWalls: rawS is List
          ? rawS
              .map((e) => MasterSharedWall.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : [],
    );
  }
}
