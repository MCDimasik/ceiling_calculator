import 'package:flutter/material.dart';

import '../domain/finish_model.dart';
import 'room_hub_screen.dart';

/// Open unified room hub (preferred entry for cross-module navigation).
///
/// Use [replaceCurrent] from module screens after flushing: pops back to an
/// existing Hub in the stack (dropping stale Finish/Layout parents) or pushes
/// a new Hub if none is present.
Future<void> openRoomHub(
  BuildContext context, {
  required int projectId,
  required int roomId,
  AppModule initialModule = AppModule.ceilingLayout,
  bool autoOpenModule = false,
  bool replaceCurrent = false,
}) {
  final nav = Navigator.of(context);
  final route = MaterialPageRoute<void>(
    settings: const RouteSettings(name: RoomHubScreen.routeName),
    builder: (_) => RoomHubScreen(
      projectId: projectId,
      roomId: roomId,
      initialModule: initialModule,
      autoOpenModule: autoOpenModule,
    ),
  );
  if (!replaceCurrent) {
    return nav.push(route);
  }

  var hubFound = false;
  nav.popUntil((r) {
    if (r.settings.name == RoomHubScreen.routeName) {
      hubFound = true;
      return true;
    }
    return r.isFirst;
  });
  if (hubFound) {
    // Already on Hub — refresh by replacing it so room data reloads.
    return nav.pushReplacement(route);
  }
  return nav.push(route);
}

/// Cross-module jump: flush caller first, then Hub → auto-open [module]
/// without stacking Finish/Layout/Docs on top of each other.
Future<void> openRoomModule(
  BuildContext context, {
  required int projectId,
  required int roomId,
  required AppModule module,
}) {
  return openRoomHub(
    context,
    projectId: projectId,
    roomId: roomId,
    initialModule: module,
    autoOpenModule: true,
    replaceCurrent: true,
  );
}
