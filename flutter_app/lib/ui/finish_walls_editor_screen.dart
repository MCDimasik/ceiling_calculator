import 'package:flutter/material.dart';

import 'finish_room_screen.dart';

/// Full-screen walls finish editor (openings, layers, wall tile layout).
class FinishWallsEditorScreen extends StatelessWidget {
  const FinishWallsEditorScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  Widget build(BuildContext context) {
    return FinishRoomScreen(
      projectId: projectId,
      roomId: roomId,
      initialTabIndex: 1,
      lockedTabIndex: 1,
      editorTitle: 'Редактор · Стены',
    );
  }
}
