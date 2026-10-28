import 'documentation_model.dart';
import 'documentation_step_logic.dart';
import 'finish_vedomost.dart';
import 'ks2_room_closure_status.dart';
import 'models.dart';
import 'project_materials.dart';
import 'room_finish_areas.dart';
import 'special_space.dart';

class StepStatus {
  const StepStatus({
    required this.step,
    required this.done,
    required this.applies,
    this.hint = '',
    this.photoCount = 0,
  });

  final DocumentationStep step;
  final bool done;
  final bool applies;
  final String hint;
  final int photoCount;
}

class RoomDocumentationSummary {
  const RoomDocumentationSummary({
    required this.steps,
    required this.completedCount,
    required this.totalCount,
    required this.readyForHandover,
    required this.designDone,
    required this.designTotal,
    required this.hiddenWorksDone,
    required this.hiddenWorksTotal,
    required this.missingItems,
  });

  final List<StepStatus> steps;
  final int completedCount;
  final int totalCount;
  final bool readyForHandover;
  final int designDone;
  final int designTotal;
  final int hiddenWorksDone;
  final int hiddenWorksTotal;
  final List<String> missingItems;

  double get progress =>
      totalCount == 0 ? 0 : completedCount / totalCount;

  String get shortLabel {
    if (readyForHandover) return 'Готово к акту';
    if (completedCount == 0) return 'Не начато';
    return '$completedCount / $totalCount';
  }
}

/// Coarse workflow status for room lists and filters.
enum RoomWorkflowStatus {
  notStarted,
  inProgress,
  handedOver,
}

extension RoomWorkflowStatusX on RoomWorkflowStatus {
  String get labelRu => switch (this) {
        RoomWorkflowStatus.notStarted => 'Не начато',
        RoomWorkflowStatus.inProgress => 'В работе',
        RoomWorkflowStatus.handedOver => 'Сдан',
      };
}

RoomWorkflowStatus roomWorkflowStatus(
  Room room,
  RoomDocumentationSummary summary, {
  RoomDocumentationChecklist? checklist,
  Project? project,
  ProjectDocumentation? documentation,
}) {
  final cl = checklist ?? RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
  if (cl.acceptedForHandover) return RoomWorkflowStatus.handedOver;
  if (project != null &&
      documentation != null &&
      isRoomHandedOverByClosingDocs(
        project: project,
        room: room,
        doc: documentation,
      )) {
    return RoomWorkflowStatus.handedOver;
  }
  // Special spaces (ЛК / объём) are «in work» as soon as created — no contour needed.
  if (room.isSpecialSpace || roomHasPlanOrSchematic(room)) {
    return RoomWorkflowStatus.inProgress;
  }
  if (!room.hasLayout && summary.completedCount == 0) {
    return RoomWorkflowStatus.notStarted;
  }
  return RoomWorkflowStatus.inProgress;
}

RoomDocumentationSummary roomDocumentationSummary(
  Room room,
  Project project, {
  RoomDocumentationChecklist? checklist,
}) {
  final cl = checklist ?? RoomDocumentationChecklist();
  final ctx = RoomDocContext.fromRoom(room);
  final ceilingMaterials = calculateRoomMaterials(room, project);
  final finishLines = buildFinishVedomostLines(room);

  bool hwDone(String stepId) {
    if (!ctx.hiddenWorkApplies(stepId)) return true;
    return cl.hiddenWorkDone(stepId);
  }

  final auto = <String, (bool done, bool applies, String hint)>{
    DocumentationStep.drawing.id: (
      ctx.hasLayout,
      true,
      ctx.isSpecialSpace
          ? (ctx.hasLayout
              ? 'Схема / параметры заданы'
              : 'Откройте ЛК или объём и задайте размеры')
          : (ctx.hasLayout
              ? 'Контур готов'
              : 'Нарисуйте стены в редакторе'),
    ),
    DocumentationStep.wallsPlan.id: (
      ctx.enabledWallLayers > 0,
      ctx.includeWalls,
      ctx.enabledWallLayers == 0
          ? (ctx.isSpecialSpace
              ? 'ЛК → Слои стен — добавьте слой и цену'
              : 'Отделка → Стены → добавьте слой')
          : 'Слоёв: ${ctx.enabledWallLayers}',
    ),
    DocumentationStep.floorPlan.id: (
      ctx.isSpecialSpace
          ? resolveRoomFinishAreas(room).floorM2 > 0
          : ctx.hasFloorPlan,
      ctx.includeFloor && (ctx.hasLayout || ctx.isSpecialSpace),
      ctx.isSpecialSpace
          ? (resolveRoomFinishAreas(room).floorM2 > 0
              ? 'Площадь пола задана'
              : 'Площадь пола не задана (необяз.)')
          : (ctx.hasFloorPlan
              ? 'Раскладка пола построена в «Отделка → Пол»'
              : 'Задайте модуль и раскладку пола'),
    ),
    DocumentationStep.ceilingFrame.id: (
      ctx.hasGuides || ctx.layoutConfirmed,
      ctx.includeCeiling && !ctx.isSpecialSpace && room.hasLayout,
      ctx.hasGuides
          ? 'Направляющих: ${room.ceilingGuides.length}'
          : 'Разметьте в раскладке или подтвердите раскладку',
    ),
    DocumentationStep.ceilingLayout.id: (
      ctx.layoutConfirmed,
      ctx.includeCeiling && !ctx.isSpecialSpace && room.hasLayout,
      ctx.layoutConfirmed
          ? 'Раскладка подтверждена'
          : 'Выйдите из раскладки в режиме панорамы',
    ),
    DocumentationStep.ceilingLights.id: (
      ctx.hasLights,
      ctx.includeCeiling && !ctx.isSpecialSpace && ctx.hasLights,
      ctx.hasLights ? 'Свет: ${room.lightFixtures.length}' : 'Не предусмотрен',
    ),
    DocumentationStep.materials.id: (
      ceilingMaterials.isNotEmpty || finishLines.isNotEmpty,
      ctx.hasLayout || ctx.isSpecialSpace,
      'Потолок: ${ceilingMaterials.length} поз. · отделка: ${finishLines.length} поз.',
    ),
    DocumentationStep.hwWalls.id: (
      hwDone(DocumentationStep.hwWalls.id),
      ctx.hiddenWorkApplies(DocumentationStep.hwWalls.id),
      _photoHint(cl, DocumentationStep.hwWalls.id, ctx),
    ),
    DocumentationStep.hwFloor.id: (
      hwDone(DocumentationStep.hwFloor.id),
      ctx.hiddenWorkApplies(DocumentationStep.hwFloor.id),
      _photoHint(cl, DocumentationStep.hwFloor.id, ctx),
    ),
    DocumentationStep.hwCeilingFrame.id: (
      hwDone(DocumentationStep.hwCeilingFrame.id),
      ctx.hiddenWorkApplies(DocumentationStep.hwCeilingFrame.id),
      ctx.hiddenWorkApplies(DocumentationStep.hwCeilingFrame.id)
          ? _photoHint(cl, DocumentationStep.hwCeilingFrame.id, ctx)
          : ctx.hiddenWorkSkipReason(DocumentationStep.hwCeilingFrame.id),
    ),
    DocumentationStep.hwCeilingGuides.id: (
      hwDone(DocumentationStep.hwCeilingGuides.id),
      ctx.hiddenWorkApplies(DocumentationStep.hwCeilingGuides.id),
      ctx.hiddenWorkApplies(DocumentationStep.hwCeilingGuides.id)
          ? _photoHint(cl, DocumentationStep.hwCeilingGuides.id, ctx)
          : ctx.hiddenWorkSkipReason(DocumentationStep.hwCeilingGuides.id),
    ),
    DocumentationStep.hwCeilingLights.id: (
      hwDone(DocumentationStep.hwCeilingLights.id),
      ctx.hiddenWorkApplies(DocumentationStep.hwCeilingLights.id),
      ctx.hiddenWorkApplies(DocumentationStep.hwCeilingLights.id)
          ? _photoHint(cl, DocumentationStep.hwCeilingLights.id, ctx)
          : ctx.hiddenWorkSkipReason(DocumentationStep.hwCeilingLights.id),
    ),
    DocumentationStep.hwCeilingTiles.id: (
      hwDone(DocumentationStep.hwCeilingTiles.id),
      ctx.hiddenWorkApplies(DocumentationStep.hwCeilingTiles.id),
      ctx.hiddenWorkApplies(DocumentationStep.hwCeilingTiles.id)
          ? _photoHint(cl, DocumentationStep.hwCeilingTiles.id, ctx)
          : ctx.hiddenWorkSkipReason(DocumentationStep.hwCeilingTiles.id),
    ),
    DocumentationStep.accepted.id: (
      cl.acceptedForHandover,
      true,
      cl.acceptedForHandover ? 'Отмечено' : 'После проверки на объекте',
    ),
  };

  final steps = DocumentationStep.all
      .map(
        (s) {
          final row = auto[s.id]!;
          return StepStatus(
            step: s,
            done: row.$1,
            applies: row.$2,
            hint: row.$3,
            photoCount: cl.photosFor(s.id).length,
          );
        },
      )
      .toList();

  // Progress / «к акту» count design only — hidden works are optional.
  final designItems = steps.where((s) => s.step.phase == DocumentationPhase.design);
  final (designDone, designTotal) = phaseProgress(
    designItems.map((s) => (done: s.done, applies: s.applies)),
  );
  final hwItems = steps.where((s) => s.step.phase == DocumentationPhase.hiddenWorks);
  final (hwDoneCount, hwTotal) = phaseProgress(
    hwItems.map((s) => (done: s.done, applies: s.applies)),
  );

  final missing = <String>[];
  for (final s in designItems) {
    if (!s.applies) continue;
    if (!s.done) missing.add(s.step.title);
  }

  return RoomDocumentationSummary(
    steps: steps,
    completedCount: designDone,
    totalCount: designTotal,
    designDone: designDone,
    designTotal: designTotal,
    hiddenWorksDone: hwDoneCount,
    hiddenWorksTotal: hwTotal,
    missingItems: missing,
    readyForHandover:
        cl.acceptedForHandover && (ctx.hasLayout || ctx.isSpecialSpace),
  );
}

String _photoHint(RoomDocumentationChecklist cl, String stepId, RoomDocContext ctx) {
  if (!ctx.hiddenWorkApplies(stepId)) return ctx.hiddenWorkSkipReason(stepId);
  final n = cl.photosFor(stepId).length;
  if (n > 0) return 'Фото: $n';
  if (cl.hiddenWorksConfirmed[stepId] == true) return 'Подтверждено без фото';
  return 'Сфотографируйте этап или отметьте «без фото»';
}

(int ready, int total) projectDocumentationCounts(Project project) {
  var ready = 0;
  for (final room in project.rooms) {
    final summary = roomDocumentationSummary(
      room,
      project,
      checklist: RoomDocumentationChecklist.fromJson(room.documentationChecklistJson),
    );
    if (summary.readyForHandover) ready++;
  }
  return (ready, project.rooms.length);
}
