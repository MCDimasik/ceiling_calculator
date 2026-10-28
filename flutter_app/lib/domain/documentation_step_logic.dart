import 'finish_model.dart';
import 'finish_quantities.dart';
import 'models.dart';
import 'room_finish_areas.dart';
import 'special_space.dart';

/// Derived flags for one room — used by checklist, PDF, and UI.
class RoomDocContext {
  RoomDocContext({
    required this.hasLayout,
    required this.isSpecialSpace,
    required this.enabledWallLayers,
    required this.hasGuides,
    required this.hasLights,
    required this.layoutConfirmed,
    required this.hasFloorPlan,
    required this.includeFloor,
    required this.includeWalls,
    required this.includeCeiling,
  });

  /// Drawn polygon **or** special schematic counts as «есть чертёж/схема».
  final bool hasLayout;
  final bool isSpecialSpace;
  final int enabledWallLayers;
  final bool hasGuides;
  final bool hasLights;
  final bool layoutConfirmed;
  final bool hasFloorPlan;
  final bool includeFloor;
  final bool includeWalls;
  final bool includeCeiling;

  factory RoomDocContext.fromRoom(Room room) {
    final layers = room.wallFinishLayers
        .map(FinishLayer.fromJson)
        .where((l) => l.enabled)
        .length;
    final special = room.isSpecialSpace;
    final hasPlan = roomHasPlanOrSchematic(room);
    return RoomDocContext(
      hasLayout: hasPlan,
      isSpecialSpace: special,
      enabledWallLayers: layers,
      hasGuides: room.ceilingGuides.isNotEmpty,
      hasLights: room.lightFixtures.isNotEmpty,
      layoutConfirmed: room.layoutConfirmed,
      hasFloorPlan: !special && room.hasLayout && floorBoardCountForRoom(room) > 0,
      includeFloor: room.finishIncludeFloor,
      includeWalls: room.finishIncludeWalls,
      includeCeiling: room.finishIncludeCeiling,
    );
  }

  bool hiddenWorkApplies(String stepId) => switch (stepId) {
        'hw_walls' => includeWalls && enabledWallLayers > 0,
        'hw_floor' => includeFloor && (hasLayout || isSpecialSpace),
        'hw_ceiling_frame' || 'hw_ceiling_guides' =>
          includeCeiling && hasGuides,
        'hw_ceiling_lights' => includeCeiling && hasLights,
        'hw_ceiling_tiles' => includeCeiling && layoutConfirmed,
        _ => true,
      };

  String hiddenWorkSkipReason(String stepId) => switch (stepId) {
        'hw_walls' => includeWalls
            ? 'Слои стен не заданы'
            : 'Стены не в смете',
        'hw_floor' => includeFloor ? 'Нет площади пола' : 'Пол не в смете',
        'hw_ceiling_frame' || 'hw_ceiling_guides' => includeCeiling
            ? 'Каркас не размечен'
            : 'Потолок не в смете',
        'hw_ceiling_lights' => 'Свет не предусмотрен',
        'hw_ceiling_tiles' => includeCeiling
            ? 'Раскладка не подтверждена'
            : 'Потолок не в смете',
        _ => '',
      };
}

/// Count applicable steps in a phase (for progress chips).
(int done, int total) phaseProgress(
  Iterable<({bool done, bool applies})> items,
) {
  var total = 0;
  var done = 0;
  for (final i in items) {
    if (!i.applies) continue;
    total++;
    if (i.done) done++;
  }
  return (done, total);
}
