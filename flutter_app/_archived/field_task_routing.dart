import 'package:flutter/material.dart';

import '../ui/contract_workspace_screen.dart';
import '../ui/field_checklist_screen.dart';
import '../ui/finish_room_screen.dart';
import '../ui/layout_screen.dart';
import 'field_tasks.dart';
import 'ks2_work_scope.dart';

/// Where a field task should open (pure; used by UI + tests).
enum FieldTaskRouteKind {
  layout,
  finishFloor,
  finishWalls,
  checklist,
  ks2,
}

FieldTaskRouteKind classifyFieldTaskStep(String? stepId) {
  if (stepId == null || stepId.isEmpty) return FieldTaskRouteKind.checklist;
  if (stepId.startsWith('ks2_close_')) return FieldTaskRouteKind.ks2;
  return switch (stepId) {
    'fact_grid' || 'fact_ceiling_features' => FieldTaskRouteKind.layout,
    'fact_floor' => FieldTaskRouteKind.finishFloor,
    'fact_walls' => FieldTaskRouteKind.finishWalls,
    _ => FieldTaskRouteKind.checklist,
  };
}

/// Navigate to the screen that can resolve [task].
Future<void> openFieldTask(
  BuildContext context, {
  required FieldTask task,
}) async {
  final kind = classifyFieldTaskStep(task.stepId);
  switch (kind) {
    case FieldTaskRouteKind.layout:
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LayoutScreen(
            projectId: task.projectId,
            roomId: task.roomId,
          ),
        ),
      );
    case FieldTaskRouteKind.finishFloor:
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FinishRoomScreen(
            projectId: task.projectId,
            roomId: task.roomId,
            initialTabIndex: 2,
          ),
        ),
      );
    case FieldTaskRouteKind.finishWalls:
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FinishRoomScreen(
            projectId: task.projectId,
            roomId: task.roomId,
            initialTabIndex: 1,
          ),
        ),
      );
    case FieldTaskRouteKind.ks2:
      final scope = WorkScope.parse(
        task.stepId!.substring('ks2_close_'.length),
      );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContractWorkspaceScreen(
            projectId: task.projectId,
            initialTab: 1,
            initialScope: scope,
            focusRoomId: task.roomId,
          ),
        ),
      );
    case FieldTaskRouteKind.checklist:
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FieldChecklistScreen(
            projectId: task.projectId,
            roomId: task.roomId,
            highlightStepId: task.stepId,
          ),
        ),
      );
  }
}
