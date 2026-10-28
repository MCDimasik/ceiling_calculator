import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_model.dart';
import '../domain/finish_vedomost.dart';
import '../domain/models.dart';
import '../domain/special_space.dart';
import 'finish_floor_editor_screen.dart';
import 'finish_materials_screen.dart';
import 'finish_overview_editor_screen.dart';
import 'finish_room_screen.dart';
import 'finish_walls_editor_screen.dart';
import 'layout_screen.dart';
import 'master_plan_screen.dart';
import 'room_editor_screen.dart';
import 'room_hub_screen.dart';
import 'special_space_screen.dart';

/// Dedicated finish editors (separate from ceiling [LayoutScreen]).
enum FinishEditorKind {
  overview,
  walls,
  floor,
  ceiling,
}

extension FinishEditorKindX on FinishEditorKind {
  String get labelRu => switch (this) {
        FinishEditorKind.overview => 'Обзор',
        FinishEditorKind.walls => 'Стены',
        FinishEditorKind.floor => 'Пол',
        FinishEditorKind.ceiling => 'Потолок',
      };

  static FinishEditorKind fromRoomTab(int index) => switch (index) {
        1 => FinishEditorKind.walls,
        2 => FinishEditorKind.floor,
        3 => FinishEditorKind.ceiling,
        _ => FinishEditorKind.overview,
      };

  static FinishEditorKind? fromVedomostScope(FinishVedomostScope scope) =>
      switch (scope) {
        FinishVedomostScope.all => FinishEditorKind.overview,
        FinishVedomostScope.walls => FinishEditorKind.walls,
        FinishVedomostScope.floor => FinishEditorKind.floor,
        FinishVedomostScope.ceiling => FinishEditorKind.ceiling,
        FinishVedomostScope.extraWorks => null,
      };
}

/// Open unified room hub (preferred entry for cross-module navigation).
///
/// Use [replaceCurrent] from module screens after flushing: pops back to an
/// existing Hub in the stack (dropping stale Finish/Layout parents) or pushes
/// a new Hub if none is present.
///
/// **Finish module:** prefer [openFinishRoom] / [openRoomModule] — Hub is skipped.
Future<void> openRoomHub(
  BuildContext context, {
  required int projectId,
  required int roomId,
  AppModule initialModule = AppModule.ceilingLayout,
  bool autoOpenModule = false,
  bool replaceCurrent = false,
}) {
  // ARCHIVED: finish used to land on Hub first — see `_archived/README.md`.
  if (initialModule == AppModule.finish) {
    return openFinishRoom(
      context,
      projectId: projectId,
      roomId: roomId,
      replaceCurrent: replaceCurrent,
    );
  }
  if (initialModule == AppModule.materials) {
    final nav = Navigator.of(context);
    final route = MaterialPageRoute<void>(
      builder: (_) => FinishMaterialsScreen(
        projectId: projectId,
        roomId: roomId,
      ),
    );
    if (replaceCurrent) return nav.pushReplacement(route);
    return nav.push(route);
  }

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
    return nav.pushReplacement(route);
  }
  return nav.push(route);
}

/// Finish room tabs (overview / walls / floor / ceiling) — primary finish entry.
/// Volume-only / stairwell rooms open [SpecialSpaceScreen] instead.
Future<void> openFinishRoom(
  BuildContext context, {
  required int projectId,
  required int roomId,
  bool replaceCurrent = false,
  int initialTabIndex = 0,
}) async {
  final project = await AppScope.of(context).projects.getProject(projectId);
  Room? room;
  if (project != null) {
    for (final r in project.rooms) {
      if (r.id == roomId) room = r;
    }
  }
  if (!context.mounted) return;
  final nav = Navigator.of(context);
  final Route<void> route = room != null && room.isSpecialSpace
      ? MaterialPageRoute<void>(
          builder: (_) => SpecialSpaceScreen(
            projectId: projectId,
            roomId: roomId,
          ),
        )
      : MaterialPageRoute<void>(
          builder: (_) => FinishRoomScreen(
            projectId: projectId,
            roomId: roomId,
            initialTabIndex: initialTabIndex,
          ),
        );
  if (replaceCurrent) {
    await nav.pushReplacement(route);
  } else {
    await nav.push(route);
  }
}

/// Primary finish entry: contour editor if no layout, else layered overview canvas.
Future<void> openFinishRoomCanvas(
  BuildContext context, {
  required int projectId,
  required int roomId,
  bool? hasLayout,
  bool replaceCurrent = false,
}) async {
  var layout = hasLayout;
  if (layout == null) {
    final project = await AppScope.of(context).projects.getProject(projectId);
    Room? room;
    if (project != null) {
      for (final r in project.rooms) {
        if (r.id == roomId) room = r;
      }
    }
    layout = room?.hasLayout ?? false;
  }
  if (!context.mounted) return;
  final nav = Navigator.of(context);
  final Route<void> route = layout
      ? MaterialPageRoute<void>(
          builder: (_) => FinishOverviewEditorScreen(
            projectId: projectId,
            roomId: roomId,
          ),
        )
      : MaterialPageRoute<void>(
          builder: (_) => RoomEditorScreen(
            projectId: projectId,
            roomId: roomId,
            module: AppModule.finish,
          ),
        );
  if (replaceCurrent) {
    await nav.pushReplacement(route);
  } else {
    await nav.push(route);
  }
}

/// Open a finish section editor (walls / floor / ceiling layout / room overview).
///
/// When [roomId] is null and [kind] is [FinishEditorKind.overview], opens
/// [MasterPlanScreen] (project-level). For other kinds without [roomId],
/// pass [fallbackRoomId] (first room with layout) or the call is a no-op.
Future<void> openFinishEditor(
  BuildContext context, {
  required int projectId,
  int? roomId,
  required FinishEditorKind kind,
  int? fallbackRoomId,
  bool replaceCurrent = false,
}) {
  final resolvedRoomId = roomId ?? fallbackRoomId;
  final nav = Navigator.of(context);

  late final Route<void> route;
  switch (kind) {
    case FinishEditorKind.ceiling:
      if (resolvedRoomId == null) {
        return Future.value();
      }
      route = MaterialPageRoute<void>(
        builder: (_) => LayoutScreen(
          projectId: projectId,
          roomId: resolvedRoomId,
        ),
      );
    case FinishEditorKind.walls:
      if (resolvedRoomId == null) {
        return Future.value();
      }
      route = MaterialPageRoute<void>(
        builder: (_) => FinishWallsEditorScreen(
          projectId: projectId,
          roomId: resolvedRoomId,
        ),
      );
    case FinishEditorKind.floor:
      if (resolvedRoomId == null) {
        return Future.value();
      }
      route = MaterialPageRoute<void>(
        builder: (_) => FinishFloorEditorScreen(
          projectId: projectId,
          roomId: resolvedRoomId,
        ),
      );
    case FinishEditorKind.overview:
      if (roomId == null && fallbackRoomId == null) {
        route = MaterialPageRoute<void>(
          builder: (_) => MasterPlanScreen(projectId: projectId),
        );
      } else if (resolvedRoomId != null) {
        route = MaterialPageRoute<void>(
          builder: (_) => FinishOverviewEditorScreen(
            projectId: projectId,
            roomId: resolvedRoomId,
          ),
        );
      } else {
        return Future.value();
      }
  }

  if (replaceCurrent) return nav.pushReplacement(route);
  return nav.push(route);
}

/// Cross-module jump: flush caller first, then Hub → auto-open [module]
/// without stacking Finish/Layout/Docs on top of each other.
/// Finish opens [FinishRoomScreen] (tabs overview).
Future<void> openRoomModule(
  BuildContext context, {
  required int projectId,
  required int roomId,
  required AppModule module,
}) {
  if (module == AppModule.finish) {
    return openFinishRoom(
      context,
      projectId: projectId,
      roomId: roomId,
      replaceCurrent: true,
    );
  }
  if (module == AppModule.materials) {
    return Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => FinishMaterialsScreen(
          projectId: projectId,
          roomId: roomId,
        ),
      ),
    );
  }
  return openRoomHub(
    context,
    projectId: projectId,
    roomId: roomId,
    initialModule: module,
    autoOpenModule: true,
    replaceCurrent: true,
  );
}
