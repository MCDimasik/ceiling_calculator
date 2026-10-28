/// Open finish editor for a room (no Hub).
Future<void> openFinishRoom(
  BuildContext context, {
  required int projectId,
  required int roomId,
  bool replaceCurrent = false,
}) {
  final nav = Navigator.of(context);
  final route = MaterialPageRoute<void>(
    builder: (_) => FinishRoomScreen(
      projectId: projectId,
      roomId: roomId,
    ),
  );
  if (replaceCurrent) {
    return nav.pushReplacement(route);
  }
  return nav.push(route);
}
