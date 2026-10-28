import 'design_ceiling_features_baseline.dart';
import 'design_walls_baseline.dart';
import 'documentation_model.dart';
import 'field_tasks.dart';
import 'finish_design_baseline.dart';
import 'layout_design_baseline.dart';
import 'models.dart';
import 'wall_polygon_diff.dart';

/// Thresholds for auto-generated field tasks from project-vs-fact deltas.
class ProjectFactAlertThresholds {
  const ProjectFactAlertThresholds({
    this.wallAreaDeltaM2 = 0.15,
    this.gridOffsetCm = 3,
    this.ceilingFeaturesDelta = 1,
  });

  final double wallAreaDeltaM2;
  final int gridOffsetCm;
  final int ceilingFeaturesDelta;
}

List<FieldTask> buildProjectFactAlertTasks(
  Project project, {
  ProjectFactAlertThresholds thresholds = const ProjectFactAlertThresholds(),
}) {
  final pid = project.id;
  if (pid == null) return const [];

  final tasks = <FieldTask>[];
  for (final room in project.rooms) {
    final rid = room.id;
    if (rid == null || !room.hasLayout) continue;

    final cl = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
    if (cl.priority == RoomFieldPriority.blocked) continue;

    if (hasFinishDesignBaseline(room)) {
      final grid = readDesignBaseline(room);
      final dx = (room.gridOffsetX - grid.offsetX).abs();
      final dy = (room.gridOffsetY - grid.offsetY).abs();
      if (dx >= thresholds.gridOffsetCm || dy >= thresholds.gridOffsetCm) {
        tasks.add(FieldTask(
          projectId: pid,
          projectName: project.name,
          roomId: rid,
          roomName: room.name,
          message: 'Δ сетка потолка ${dx}×${dy} см vs проект',
          priority: cl.priority == RoomFieldPriority.normal
              ? RoomFieldPriority.urgent
              : cl.priority,
          stepId: 'fact_grid',
          assignee: cl.assignee,
          dueDate: cl.dueDate,
        ));
      }

      final floorBase = readFloorDesignBaseline(room);
      final fdx = (room.floorGridOffsetX - floorBase.offsetX).abs();
      final fdy = (room.floorGridOffsetY - floorBase.offsetY).abs();
      if (fdx >= thresholds.gridOffsetCm || fdy >= thresholds.gridOffsetCm) {
        tasks.add(FieldTask(
          projectId: pid,
          projectName: project.name,
          roomId: rid,
          roomName: room.name,
          message: 'Δ сетка пола ${fdx}×${fdy} см vs проект',
          priority: cl.priority,
          stepId: 'fact_floor',
          assignee: cl.assignee,
          dueDate: cl.dueDate,
        ));
      }

      if (hasDesignCeilingFeaturesBaseline(room)) {
        final (g, l) = ceilingFeaturesDelta(room);
        if (g >= thresholds.ceilingFeaturesDelta || l >= thresholds.ceilingFeaturesDelta) {
          tasks.add(FieldTask(
            projectId: pid,
            projectName: project.name,
            roomId: rid,
            roomName: room.name,
            message: formatCeilingFeaturesDeltaLabel(room),
            priority: cl.priority,
            stepId: 'fact_ceiling_features',
            assignee: cl.assignee,
            dueDate: cl.dueDate,
          ));
        }
      }
    }

    final designWalls = readDesignWalls(room);
    if (designWalls != null) {
      final diff = compareWallPolygons(designWalls, room.walls);
      if (diff.hasSignificantDiff &&
          diff.areaDeltaM2.abs() >= thresholds.wallAreaDeltaM2) {
        tasks.add(FieldTask(
          projectId: pid,
          projectName: project.name,
          roomId: rid,
          roomName: room.name,
          message:
              'Δ контур ${diff.areaDeltaM2 >= 0 ? '+' : ''}${diff.areaDeltaM2.toStringAsFixed(2)} м²',
          priority: cl.priority,
          stepId: 'fact_walls',
          assignee: cl.assignee,
          dueDate: cl.dueDate,
        ));
      }
    }
  }
  return tasks;
}
