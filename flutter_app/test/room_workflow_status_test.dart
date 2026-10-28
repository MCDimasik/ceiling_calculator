import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/room_documentation_status.dart';

void main() {
  final walls = [
    [0.0, 0.0, 400.0, 0.0],
    [400.0, 0.0, 400.0, 300.0],
    [400.0, 300.0, 0.0, 300.0],
    [0.0, 300.0, 0.0, 0.0],
  ];

  test('roomWorkflowStatus handedOver when accepted', () {
    final room = Room(
      name: 'R',
      walls: walls,
      documentationChecklistJson: {'accepted': true},
    );
    final project = Project(name: 'P', rooms: [room]);
    final summary = roomDocumentationSummary(room, project);
    expect(
      roomWorkflowStatus(room, summary),
      RoomWorkflowStatus.handedOver,
    );
  });

  test('roomWorkflowStatus inProgress when layout exists', () {
    final room = Room(name: 'R', walls: walls, layoutConfirmed: true);
    final project = Project(name: 'P', rooms: [room]);
    final summary = roomDocumentationSummary(room, project);
    expect(
      roomWorkflowStatus(room, summary),
      RoomWorkflowStatus.inProgress,
    );
  });

  test('roomWorkflowStatus notStarted without layout', () {
    final room = Room(name: 'R');
    final project = Project(name: 'P', rooms: [room]);
    final summary = roomDocumentationSummary(room, project);
    expect(
      roomWorkflowStatus(room, summary),
      RoomWorkflowStatus.notStarted,
    );
  });
}
