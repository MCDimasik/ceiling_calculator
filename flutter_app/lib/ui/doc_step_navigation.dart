import 'package:flutter/material.dart';

import '../domain/documentation_model.dart';
import '../domain/finish_model.dart';
import '../domain/room_documentation_status.dart';
import 'documentation_flow_screens.dart';
import 'documentation_hidden_layers_screen.dart';
import 'finish_materials_screen.dart';
import 'layout_screen.dart';
import 'finish_room_screen.dart';
import 'geometry_capture_hub_screen.dart';
import 'room_hub_screen.dart';

/// Navigate to fix a missing documentation step.
Future<void> openMissingDocumentationStep(
  BuildContext context, {
  required int projectId,
  required int roomId,
  required String stepId,
}) async {
  switch (stepId) {
    case 'drawing':
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GeometryCaptureHubScreen(projectId: projectId, roomId: roomId),
        ),
      );
    case 'walls_plan':
    case 'floor_plan':
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FinishRoomScreen(projectId: projectId, roomId: roomId),
        ),
      );
    case 'ceiling_frame':
    case 'ceiling_layout':
    case 'ceiling_lights':
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LayoutScreen(projectId: projectId, roomId: roomId),
        ),
      );
    case 'materials':
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FinishMaterialsScreen(
            projectId: projectId,
            roomId: roomId,
          ),
        ),
      );
    default:
      if (stepId.startsWith('hw_')) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DocumentationHiddenLayersScreen(
              projectId: projectId,
              roomId: roomId,
            ),
          ),
        );
      } else if (stepId == 'accepted') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DocumentationChecklistScreen(
              projectId: projectId,
              roomId: roomId,
            ),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            settings: const RouteSettings(name: RoomHubScreen.routeName),
            builder: (_) => RoomHubScreen(
              projectId: projectId,
              roomId: roomId,
              initialModule: AppModule.documentation,
              autoOpenModule: true,
            ),
          ),
        );
      }
  }
}

/// Map incomplete steps to actionable items with step ids.
List<({String stepId, String title})> missingDocumentationActions(
  RoomDocumentationSummary summary,
) {
  final out = <({String stepId, String title})>[];
  for (final s in summary.steps) {
    if (!s.applies || s.done) continue;
    if (s.step.id == DocumentationStep.accepted.id) continue;
    out.add((stepId: s.step.id, title: s.step.title));
  }
  return out;
}
