import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_model.dart';
import '../domain/materials_calculator.dart';
import '../domain/models.dart';
import '../domain/project_floors.dart';
import '../domain/room_finish_areas.dart';
import '../domain/special_space.dart';
import 'adaptive_layout.dart';
import 'desktop_cascade.dart';
import 'documentation_flow_screens.dart';
import 'widgets/cascade_pane_toolbar.dart';
import 'widgets/desktop_room_actions.dart';
import 'widgets/room_floor_fab.dart';
import 'finish_project_screen.dart';
import 'finish_room_screen.dart';
import 'in_app_share_flow.dart';
import 'layout_screen.dart';
import 'master_plan_screen.dart';
import 'project_dashboard_screen.dart';
import 'room_editor_screen.dart';
import 'room_hub_screen.dart';
import 'room_navigation.dart';
import 'special_space_screen.dart';
import 'widgets/add_floor_sheet.dart';
import 'widgets/add_space_sheet.dart';
import 'widgets/batch_create_rooms_dialog.dart';
import 'widgets/floor_pager_chip.dart';
import 'widgets/long_press_action_tile.dart';
import 'widgets/numeric_input.dart';
import 'widgets/screen_scaffold.dart';
import 'widgets/transparent_reorder_proxy.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({
    super.key,
    required this.projectId,
    this.module = AppModule.ceilingLayout,
    /// Right pane of desktop master–detail (no back-to-projects).
    this.embeddedInSplit = false,
    /// Desktop cascade: open layout / сводка in center pane.
    this.cascadeMode = false,
  });

  final int projectId;
  final AppModule module;
  final bool embeddedInSplit;
  final bool cascadeMode;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  Project? _project;
  bool _loading = true;
  String? _error;
  bool _started = false;
  ProjectFloor? _selectedFloor;
  final Set<int> _selectedRoomIds = {};

  bool get _selectionMode => _selectedRoomIds.isNotEmpty;

  void _toggleRoomSelected(int? id) {
    if (id == null) return;
    setState(() {
      if (!_selectedRoomIds.remove(id)) {
        _selectedRoomIds.add(id);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedRoomIds.clear());

  List<Room> _selectedRooms() {
    final all = _project?.rooms ?? const <Room>[];
    return [
      for (final r in all)
        if (r.id != null && _selectedRoomIds.contains(r.id)) r,
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final cached = AppScope.of(context).projects.peekCachedProject(widget.projectId);
    if (cached != null) {
      _project = cached;
      _loading = false;
    }
    _reload();
  }

  Future<void> _reload() async {
    final hadData = _project != null;
    if (!hadData) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final project = await AppScope.of(context).projects.getProject(widget.projectId);
      if (!mounted) return;
      setState(() {
        _project = project;
        _loading = false;
        if (project == null) {
          _error = 'Проект не найден';
        } else {
          _selectedFloor = _resolveSelectedFloor(project);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  ProjectFloor? _resolveSelectedFloor(Project project) {
    final pages = floorsForPager(project.floors);
    if (!projectHasExplicitFloors(project.floors) || pages.isEmpty) {
      return null;
    }
    if (_selectedFloor != null) {
      for (final f in pages) {
        if (f.id == _selectedFloor!.id) return f;
      }
    }
    return pages.first;
  }

  Future<void> _createRoom() async {
    final name = await _askName(title: 'Новая комната', hint: 'Название комнаты');
    if (name == null || name.isEmpty) return;
    final floorId = _selectedFloor?.id;
    final room = await AppScope.of(context).projects.createRoom(
      widget.projectId,
      name,
      floorId: floorId,
    );
    if (!context.mounted || room.id == null) return;
    final cascade = widget.cascadeMode
        ? DesktopCascadeHost.maybeOf(context)
        : null;
    if (cascade != null) {
      final editor = RoomEditorScreen(
        projectId: widget.projectId,
        roomId: room.id!,
        module: widget.module == AppModule.finish
            ? AppModule.finish
            : AppModule.ceilingLayout,
      );
      cascade.openDetail(
        editor,
        title: room.name,
        detailId: 'room:${room.id}',
      );
      await _reload();
      return;
    }
    if (widget.module == AppModule.finish) {
      await openFinishRoomCanvas(
        context,
        projectId: widget.projectId,
        roomId: room.id!,
        hasLayout: false,
      );
      if (!context.mounted) return;
    }
    await _reload();
  }

  /// Finish-only: volume-only room or stairwell (no floor plan).
  bool get _projectHasStairwell =>
      (_project?.rooms ?? []).any(
        (r) => r.specialSpace?.kind == SpecialSpaceKind.stairwell,
      );

  Future<void> _createSpecialSpace() async {
    if (widget.module != AppModule.finish) return;
    final choice = await showAddSpaceSheet(context);
    if (choice == null || !mounted) return;

    if (choice == AddSpaceChoice.stairwell && _projectHasStairwell) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'На объекте уже есть лестничная клетка — вторая не нужна',
          ),
        ),
      );
      return;
    }

    final title = switch (choice) {
      AddSpaceChoice.volume => 'Объём без чертежа',
      AddSpaceChoice.stairwell => 'Лестничная клетка',
    };
    final hint = switch (choice) {
      AddSpaceChoice.volume => 'Напр. Коридор · шпаклёвка',
      AddSpaceChoice.stairwell => 'Напр. ЛК 1–5 эт.',
    };
    final name = await _askName(title: title, hint: hint);
    if (name == null || name.isEmpty) return;
    final floorId = _selectedFloor?.id;
    final room = await AppScope.of(context).projects.createRoom(
      widget.projectId,
      name,
      floorId: floorId,
      mirrorToTypicalGroup: false,
    );
    if (!context.mounted || room.id == null) return;

    room.specialSpace = SpecialSpace(
      kind: choice == AddSpaceChoice.stairwell
          ? SpecialSpaceKind.stairwell
          : SpecialSpaceKind.volume,
      stair: choice == AddSpaceChoice.stairwell ? StairwellParams() : null,
    );
    if (choice == AddSpaceChoice.stairwell) {
      room.finishIncludeFloor = false;
      room.finishIncludeCeiling = false;
      room.finishIncludeWalls = true;
    }
    await AppScope.of(context).projects.updateRoom(room);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpecialSpaceScreen(
          projectId: widget.projectId,
          roomId: room.id!,
        ),
      ),
    );
    if (!context.mounted) return;
    await _reload();
  }

  Future<void> _deleteFloor(ProjectFloor floor) async {
    if (floor.id == null) return;
    final project = _project;
    if (project == null) return;

    final floorsToDelete = <ProjectFloor>[];
    if (floor.isTypicalGroup && floor.typicalGroupId != null) {
      floorsToDelete.addAll(
        project.floors.where((f) => f.typicalGroupId == floor.typicalGroupId),
      );
    } else {
      floorsToDelete.add(floor);
    }
    final deleteIds = <int>{
      for (final f in floorsToDelete)
        if (f.id != null) f.id!,
    };

    final atRisk = spanningStairwellsAtRiskOnFloorDelete(
      rooms: project.rooms,
      floors: project.floors,
      deletingFloorIds: deleteIds,
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final title = floor.isTypicalGroup
            ? 'Удалить типовой блок?'
            : 'Удалить этаж?';
        final base =
            '«${floor.pagerLabel}» будет удалён вместе с помещениями этого этажа.';
        String content = base;
        if (atRisk.isNotEmpty) {
          final names = atRisk.map((r) => '«${r.name}»').join(', ');
          content =
              '$base\n\nЛестничные клетки $names охватывают и другие этажи. '
              'Их перенесём на оставшийся этаж, чтобы не потерять.';
        }
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(atRisk.isEmpty ? 'Удалить' : 'Перенести ЛК и удалить'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    if (!mounted) return;
    final repo = AppScope.of(context).projects;

    for (final room in atRisk) {
      final target = preferReassignFloorForStairwell(
        room: room,
        floors: project.floors,
        deletingFloorIds: deleteIds,
      );
      if (target?.id == null) continue;
      room.floorId = target!.id;
      await repo.updateRoom(room);
    }

    for (final f in floorsToDelete) {
      if (f.id != null) await repo.deleteFloor(f.id!);
    }
    if (!mounted) return;
    setState(() => _selectedFloor = null);
    await _reload();
  }

  Future<void> _makeFloorTypical(ProjectFloor floor) async {
    if (floor.id == null || floor.isTypicalGroup) return;
    final countCtrl = TextEditingController(text: '5');
    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сделать этаж типовым'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '«${floor.pagerLabel}» станет шаблоном. Укажите, сколько этажей '
              'в блоке (включая этот).',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: countCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Число этажей',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(countCtrl.text.trim()) ?? 0;
              Navigator.pop(ctx, n);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    countCtrl.dispose();
    if (count == null || count < 2) return;
    final created = await AppScope.of(context).projects.makeFloorTypical(
          projectId: widget.projectId,
          floorId: floor.id!,
          totalCount: count,
        );
    if (!mounted) return;
    await _reload();
    if (created.isNotEmpty) {
      setState(() => _selectedFloor = created.first);
    }
  }

  Future<void> _addFloor({required bool typical}) async {
    final project = _project;
    if (project == null) return;
    final pages = floorsForPager(project.floors);
    final maxNum = pages.isEmpty
        ? 1
        : pages.map((f) => f.typicalSpanEnd ?? f.floorNumber).fold<int>(1, (a, b) => a > b ? a : b);
    final result = await showAddFloorSheet(
      context: context,
      rooms: project.rooms,
      floors: project.floors,
      typical: typical,
      suggestedStart: maxNum + 1,
    );
    if (result == null) return;
    final created = await AppScope.of(context).projects.addFloors(
      projectId: widget.projectId,
      startNumber: result.startNumber ?? maxNum + 1,
      count: result.count,
      typical: result.typical,
      sourceRoomIds: result.sourceRoomIds,
    );
    if (!mounted) return;
    await _reload();
    if (created.isNotEmpty) {
      setState(() => _selectedFloor = created.first);
    }
  }

  Future<void> _batchCreateRooms() async {
    final existing = _project?.rooms.length ?? 0;
    final specs = await showDialog<List<({String name, double lengthCm, double widthCm})>>(
      context: context,
      builder: (_) => BatchCreateRoomsDialog(existingRoomCount: existing),
    );
    if (specs == null || specs.isEmpty) return;
    final created = await AppScope.of(context).projects.createRectRooms(
      widget.projectId,
      specs,
      floorId: _selectedFloor?.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Создано помещений: ${created.length}')),
    );
    await _reload();
  }

  Future<void> _renameRoom(Room room) async {
    final name = await _askName(
      title: 'Переименовать',
      hint: 'Название комнаты',
      initial: room.name,
    );
    if (name == null || name.isEmpty || room.id == null) return;
    await AppScope.of(context).projects.renameRoom(room.id!, name);
    await _reload();
  }

  Future<void> _deleteRoom(Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить комнату?'),
        content: Text('«${room.name}» будет удалена.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true || room.id == null) return;
    await AppScope.of(context).projects.deleteRoom(widget.projectId, room.id!);
    await _reload();
  }

  Future<String?> _askName({
    required String title,
    required String hint,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: NumericInput.textKeyboard,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareRoom(Room room) async {
    final project =
        await AppScope.of(context).projects.getProject(widget.projectId);
    if (project == null || !mounted) return;
    await shareProjectOrRooms(this.context, project: project, rooms: [room]);
  }

  Future<void> _shareSelectedRooms() async {
    final rooms = _selectedRooms();
    if (rooms.isEmpty) return;
    final project =
        await AppScope.of(context).projects.getProject(widget.projectId);
    if (project == null || !mounted) return;
    await shareProjectOrRooms(this.context, project: project, rooms: rooms);
  }

  Future<void> _duplicateSelectedRooms() async {
    final rooms = _selectedRooms();
    if (rooms.isEmpty) return;
    final repo = AppScope.of(context).projects;
    var n = 0;
    for (final room in rooms) {
      if (room.specialSpace?.kind == SpecialSpaceKind.stairwell) continue;
      final name = '${room.name} (копия)';
      await repo.duplicateRoom(widget.projectId, room, name);
      n++;
    }
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(n == 0 ? 'Нечего копировать' : 'Скопировано: $n')),
    );
    await _reload();
  }

  Future<void> _deleteSelectedRooms() async {
    final rooms = _selectedRooms();
    if (rooms.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить помещения (${rooms.length})?'),
        content: Text(
          rooms.map((r) => r.name).join(', '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = AppScope.of(context).projects;
    for (final room in rooms) {
      if (room.id == null) continue;
      await repo.deleteRoom(widget.projectId, room.id!);
    }
    if (!mounted) return;
    _clearSelection();
    await _reload();
  }

  Future<void> _duplicateRoom(Room room) async {
    if (room.specialSpace?.kind == SpecialSpaceKind.stairwell) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Лестничную клетку нельзя дублировать — на объекте только одна',
          ),
        ),
      );
      return;
    }
    final name = await _askName(
      title: 'Копировать комнату',
      hint: 'Название новой комнаты',
    );
    if (name == null || name.isEmpty) return;
    await AppScope.of(context).projects.duplicateRoom(widget.projectId, room, name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Создана «$name»')),
      );
    }
    await _reload();
  }

  Future<void> _openRoom(Room room) async {
    if (room.id == null) return;
    final cascade = widget.cascadeMode
        ? DesktopCascadeHost.maybeOf(context)
        : null;

    if (widget.module == AppModule.documentation) {
      await openDocumentationRoom(
        context,
        projectId: widget.projectId,
        roomId: room.id!,
      );
      await _reload();
      return;
    }
    if (widget.module == AppModule.ceilingLayout) {
      if (room.isSpecialSpace) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Это помещение без чертежа — откройте в отделке'),
          ),
        );
        return;
      }
      final page = room.hasLayout
          ? LayoutScreen(
              projectId: widget.projectId,
              roomId: room.id!,
            )
          : RoomEditorScreen(
              projectId: widget.projectId,
              roomId: room.id!,
            );
      if (cascade != null) {
        cascade.openDetail(
          page,
          title: room.name,
          detailId: 'room:${room.id}',
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page),
      );
      await _reload();
      return;
    }
    // Finish: special space → volume/stair editor; else room tabs.
    if (widget.module == AppModule.finish) {
      if (cascade != null) {
        if (room.isSpecialSpace) {
          cascade.openDetail(
            SpecialSpaceScreen(
              projectId: widget.projectId,
              roomId: room.id!,
            ),
            title: room.name,
            detailId: 'room:${room.id}',
          );
        } else {
          cascade.openDetail(
            FinishRoomScreen(
              projectId: widget.projectId,
              roomId: room.id!,
            ),
            title: room.name,
            detailId: 'room:${room.id}',
          );
        }
        return;
      }
      if (room.isSpecialSpace) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SpecialSpaceScreen(
              projectId: widget.projectId,
              roomId: room.id!,
            ),
          ),
        );
      } else {
        await openFinishRoom(
          context,
          projectId: widget.projectId,
          roomId: room.id!,
        );
      }
      await _reload();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: RoomHubScreen.routeName),
        builder: (_) => RoomHubScreen(
          projectId: widget.projectId,
          roomId: room.id!,
          initialModule: widget.module,
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _project?.rooms ?? [];
    // AppBar: floor area only (comparable). Walls of ЛК stay out of this sum.
    final area = rooms.where(roomHasFinishGeometry).fold<double>(0, (a, r) {
      final resolved = resolveRoomFinishAreas(r);
      if (resolved.fromSpecial) return a + resolved.floorM2;
      return a + MaterialsCalculator.roomAreaM2(r.walls);
    });
    final wallsExtra = rooms.where(roomHasFinishGeometry).fold<double>(0, (a, r) {
      final resolved = resolveRoomFinishAreas(r);
      if (!resolved.fromSpecial) return a;
      return a + resolved.wallsM2;
    });
    final perimeter = rooms
        .where((r) => r.hasLayout)
        .fold<double>(
            0, (a, r) => a + MaterialsCalculator.roomPerimeterCm(r.walls) / 100);
    final metrics = _project == null
        ? null
        : wallsExtra > 0.05
            ? 'пол ${area.toStringAsFixed(1)} м² · ЛК ${wallsExtra.toStringAsFixed(1)} · '
                'P ${perimeter.toStringAsFixed(1)} м'
            : '${area.toStringAsFixed(1)} м² · P ${perimeter.toStringAsFixed(1)} м';
    final phoneTitle = _project == null
        ? 'Комнаты'
        : wallsExtra > 0.05
            ? '${_project!.name} · пол ${area.toStringAsFixed(2)} м²'
                ' · стены ЛК ${wallsExtra.toStringAsFixed(1)} · '
                'P ${perimeter.toStringAsFixed(2)} м'
            : '${_project!.name} · ${area.toStringAsFixed(2)} м² · '
                'P ${perimeter.toStringAsFixed(2)} м';

    final roomActions = <Widget>[
      if (!_selectionMode) ...[
        if (widget.module == AppModule.documentation)
          IconButton(
            tooltip: 'Настройки документации',
            visualDensity: VisualDensity.compact,
            onPressed: _project == null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DocumentationProjectSettingsScreen(
                          projectId: widget.projectId,
                        ),
                      ),
                    );
                    await _reload();
                  },
            icon: const Icon(Icons.settings_outlined),
          ),
        IconButton(
          tooltip: 'План объекта',
          visualDensity: VisualDensity.compact,
          onPressed: _project == null
              ? null
              : () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MasterPlanScreen(projectId: widget.projectId),
                    ),
                  );
                  await _reload();
                },
          icon: const Icon(Icons.apartment_outlined),
        ),
        IconButton(
          tooltip: 'Обновить',
          visualDensity: VisualDensity.compact,
          onPressed: _loading ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ];

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _clearSelection();
      },
      child: ScreenScaffold(
        constrainDesktopWidth: !widget.embeddedInSplit,
        embedInParentBackground: widget.cascadeMode,
        dimOpacity: widget.module == AppModule.finish ? 0.58 : 0.45,
        appBar: widget.cascadeMode
            ? CascadePaneToolbar(
                title: _selectionMode
                    ? 'Выбрано: ${_selectedRoomIds.length}'
                    : (_project?.name ?? 'Помещения'),
                subtitle: _selectionMode ? null : metrics,
                leading: IconButton(
                  tooltip: _selectionMode ? 'Снять выбор' : 'К объектам',
                  visualDensity: VisualDensity.compact,
                  onPressed: _selectionMode
                      ? _clearSelection
                      : () => DesktopCascadeHost.maybeOf(context)
                          ?.clearProject(),
                  icon: Icon(
                    _selectionMode ? Icons.close : Icons.arrow_back,
                    size: 20,
                  ),
                ),
                actions: roomActions,
              )
            : AppBar(
                automaticallyImplyLeading: !widget.embeddedInSplit,
                leading: _selectionMode
                    ? IconButton(
                        tooltip: 'Снять выбор',
                        onPressed: _clearSelection,
                        icon: const Icon(Icons.close),
                      )
                    : (widget.embeddedInSplit
                        ? const Icon(Icons.meeting_room_outlined)
                        : null),
                title: Text(
                  _selectionMode
                      ? 'Выбрано: ${_selectedRoomIds.length}'
                      : phoneTitle,
                ),
                actions: roomActions,
              ),
        floatingActionButton: _selectionMode ||
                _project == null ||
                widget.cascadeMode
            ? null
            : RoomFloorFab(
                onCreateRoom: _createRoom,
                onBatchRooms: _batchCreateRooms,
                onCreateFloor: () => _addFloor(typical: false),
                onTypicalFloors: () => _addFloor(typical: true),
                onCreateSpecialSpace: widget.module == AppModule.finish
                    ? _createSpecialSpace
                    : null,
              ),
        bottomNavigationBar: _selectionMode
            ? SafeArea(
                child: Material(
                  elevation: 8,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _shareSelectedRooms,
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Поделиться'),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _duplicateSelectedRooms,
                            icon: const Icon(Icons.content_copy),
                            label: const Text('Копия'),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _deleteSelectedRooms,
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Удалить'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        body: widget.cascadeMode &&
                !_selectionMode &&
                _project != null
            ? Stack(
                children: [
                  Positioned.fill(child: _buildBody()),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 10,
                    child: DesktopRoomActionsBar(
                      onCreateRoom: _createRoom,
                      onBatchRooms: _batchCreateRooms,
                      onCreateFloor: () => _addFloor(typical: false),
                      onTypicalFloors: () => _addFloor(typical: true),
                      onCreateSpecialSpace: widget.module == AppModule.finish
                          ? _createSpecialSpace
                          : null,
                    ),
                  ),
                ],
              )
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Ошибка: $_error'));
    }
    final project = _project!;
    final allRooms = project.rooms;
    final floors = project.floors;
    final showFloors = projectHasExplicitFloors(floors);
    final rooms = roomsForPagerFloor(
      rooms: allRooms,
      floors: floors,
      selected: _selectedFloor,
      includeSpanningStairwells: true,
    );
    final showFinishSummary = widget.module == AppModule.finish;
    final showDocSummary = widget.module == AppModule.documentation;
    final showProjectSummary = showFinishSummary || showDocSummary;
    if (allRooms.isEmpty && !showProjectSummary && !showFloors) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.meeting_room_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('В проекте пока нет комнат'),
            const SizedBox(height: 8),
            Text(
              'Добавьте комнату и откройте редактор стен.\n'
              'Свайпните «+ Комната» в сторону — «+ Этаж».',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showFloors) ...[
          const SizedBox(height: 8),
          FloorPagerChip(
            floors: floors,
            selected: _selectedFloor,
            onSelected: (f) => setState(() => _selectedFloor = f),
            onDeleteFloor: (f) => _deleteFloor(f),
            onMakeTypical: (f) => _makeFloorTypical(f),
          ),
          const SizedBox(height: 4),
        ],
        Expanded(
          child: showFloors
              ? FloorPageView(
                  floors: floors,
                  rooms: allRooms,
                  selected: _selectedFloor,
                  onSelected: (f) => setState(() => _selectedFloor = f),
                  childBuilder: (context, floor, floorRooms) =>
                      _buildRoomList(
                    floorRooms,
                    showProjectSummary: showProjectSummary,
                    showDocSummary: showDocSummary,
                    allRoomsForSummary: allRooms,
                  ),
                )
              : _buildRoomList(
                  rooms,
                  showProjectSummary: showProjectSummary,
                  showDocSummary: showDocSummary,
                  allRoomsForSummary: allRooms,
                ),
        ),
      ],
    );
  }

  Widget _buildRoomList(
    List<Room> rooms, {
    required bool showProjectSummary,
    required bool showDocSummary,
    required List<Room> allRoomsForSummary,
  }) {
    final header = showProjectSummary ? 1 : 0;
    final itemCount = rooms.length + header;

    return RefreshIndicator(
      onRefresh: _reload,
      child: ReorderableListView.builder(
        padding: EdgeInsets.fromLTRB(
          widget.cascadeMode ? 12 : 16,
          12,
          widget.cascadeMode ? 12 : 16,
          88,
        ),
        buildDefaultDragHandles: false,
        proxyDecorator: transparentReorderProxyDecorator,
        itemCount: itemCount == 0 ? 1 : itemCount,
        onReorder: (oldIndex, newIndex) async {
          if (header > 0 && (oldIndex == 0 || newIndex == 0)) return;
          var oi = oldIndex - header;
          var ni = newIndex - header;
          if (ni > oi) ni -= 1;
          if (oi < 0 || oi >= rooms.length || ni < 0 || ni > rooms.length) {
            return;
          }
          final floorId = _selectedFloor?.id;
          final moved = rooms[oi];
          // Spanning ЛК shown as guest on another floor — order is global; skip.
          if (floorId != null &&
              moved.specialSpace?.kind == SpecialSpaceKind.stairwell &&
              moved.floorId != floorId) {
            return;
          }
          final list = List<Room>.from(rooms);
          final item = list.removeAt(oi);
          list.insert(ni.clamp(0, list.length), item);
          final others = (_project?.rooms ?? [])
              .where((r) => !list.any((x) => x.id == r.id))
              .toList();
          final merged = [...list, ...others];
          setState(() => _project = _project!.copyWith(rooms: merged));
          final ids =
              merged.where((r) => r.id != null).map((r) => r.id!).toList();
          await AppScope.of(context)
              .projects
              .reorderRooms(widget.projectId, ids);
        },
        itemBuilder: (context, i) {
          if (showProjectSummary && i == 0) {
            final layoutN =
                allRoomsForSummary.where(roomHasFinishGeometry).length;
            if (showDocSummary) {
              return Card(
                key: const ValueKey('summary-doc'),
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  minTileHeight: DesktopMetrics.listTileMinHeight(context),
                  leading: CircleAvatar(
                    radius: DesktopMetrics.leadingRadius(context),
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.dashboard_outlined),
                  ),
                  title: Text(
                    'Сводка объекта',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    layoutN == 0
                        ? 'Готовность к актам · КП · КС · документы'
                        : 'Помещений с чертежом: $layoutN · готовность и генератор документов',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final page = ProjectDashboardScreen(
                      projectId: widget.projectId,
                      focusFloorId: _selectedFloor?.id,
                    );
                    final host = widget.cascadeMode
                        ? DesktopCascadeHost.maybeOf(context)
                        : null;
                    if (host != null) {
                      host.openDetail(
                        page,
                        title: 'Сводка объекта',
                        detailId: 'dash:${widget.projectId}',
                      );
                      return;
                    }
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => page),
                    );
                    await _reload();
                  },
                ),
              );
            }
            return Card(
              key: const ValueKey('summary-finish'),
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                minTileHeight: DesktopMetrics.listTileMinHeight(context),
                leading: CircleAvatar(
                  radius: DesktopMetrics.leadingRadius(context),
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor:
                      Theme.of(context).colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.apartment_outlined),
                ),
                title: Text(
                  'Сводка объекта',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  layoutN == 0
                      ? 'Обзор, стены, пол, потолок и другие работы'
                      : 'С объёмами: $layoutN · обзор и конструктор работ',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final page = FinishProjectScreen(
                    projectId: widget.projectId,
                  );
                  final host = widget.cascadeMode
                      ? DesktopCascadeHost.maybeOf(context)
                      : null;
                  if (host != null) {
                    host.openDetail(
                      page,
                      title: 'Сводка объекта',
                      detailId: 'finish:${widget.projectId}',
                    );
                    return;
                  }
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => page),
                  );
                  await _reload();
                },
              ),
            );
          }
          final roomIndex = showProjectSummary ? i - 1 : i;
          if (roomIndex < 0 || roomIndex >= rooms.length) {
            return const SizedBox.shrink(key: ValueKey('empty'));
          }
          final room = rooms[roomIndex];
          final floorTag = roomFloorLabel(
            room: room,
            floors: _project?.floors ?? const [],
          );
          final subtitle = () {
            // Spanning ЛК already shows «эт. 1–5» — skip anchor «1 этаж».
            final spanStair = () {
              final s = room.specialSpace;
              if (s == null || s.kind != SpecialSpaceKind.stairwell) {
                return false;
              }
              final st = s.stair;
              if (st == null) return false;
              return st.floorsFrom != st.floorsTo;
            }();
            final floorPrefix =
                (floorTag == null || spanStair) ? '' : '$floorTag · ';
            if (widget.module == AppModule.documentation) {
              if (room.isSpecialSpace) {
                final s = room.specialSpace!;
                final parts = <String>[s.kindLabelRu];
                final st = s.stair;
                if (s.kind == SpecialSpaceKind.stairwell && st != null) {
                  final lo = st.floorsFrom <= st.floorsTo
                      ? st.floorsFrom
                      : st.floorsTo;
                  final hi = st.floorsFrom <= st.floorsTo
                      ? st.floorsTo
                      : st.floorsFrom;
                  parts.add(lo == hi ? 'эт. $lo' : 'эт. $lo–$hi');
                }
                return '$floorPrefix${parts.join(' · ')}';
              }
              if (!room.hasLayout) return '${floorPrefix}Нет чертежа';
              return '${floorPrefix}Схемы · ведомость · акты';
            }
            if (room.isSpecialSpace) {
              final a = resolveRoomFinishAreas(room);
              final s = room.specialSpace!;
              final parts = <String>[s.kindLabelRu];
              final st = s.stair;
              if (s.kind == SpecialSpaceKind.stairwell && st != null) {
                final lo = st.floorsFrom <= st.floorsTo
                    ? st.floorsFrom
                    : st.floorsTo;
                final hi = st.floorsFrom <= st.floorsTo
                    ? st.floorsTo
                    : st.floorsFrom;
                parts.add(lo == hi ? 'эт. $lo' : 'эт. $lo–$hi');
              }
              if (a.wallsM2 > 0) {
                parts.add('стены ${a.wallsM2.toStringAsFixed(1)} м²');
              }
              if (a.floorM2 > 0) {
                parts.add('пол ${a.floorM2.toStringAsFixed(1)} м²');
              }
              return '$floorPrefix${parts.join(' · ')}';
            }
            if (room.hasLayout) {
              final a = MaterialsCalculator.roomAreaM2(room.walls);
              final p =
                  MaterialsCalculator.roomPerimeterCm(room.walls) / 100;
              return '$floorPrefixСтен: ${room.walls.length} · ${a.toStringAsFixed(2)} м² · P ${p.toStringAsFixed(2)} м';
            }
            return '$floorPrefix' 'Чертёж ещё не создан';
          }();
          return Padding(
            key: ValueKey(room.id ?? 'room-$roomIndex'),
            padding: const EdgeInsets.only(bottom: 8),
            child: LongPressActionTile(
              title: room.specialSpace?.kind == SpecialSpaceKind.stairwell
                  ? '${room.name} · ЛК'
                  : roomNameWithFloor(
                      room: room,
                      floors: _project?.floors ?? const [],
                    ),
              subtitle: subtitle,
              leading: room.specialSpace?.kind == SpecialSpaceKind.stairwell
                  ? Icon(
                      Icons.stairs_outlined,
                      color: Theme.of(context).colorScheme.secondary,
                    )
                  : null,
              selected: (room.id != null &&
                      _selectedRoomIds.contains(room.id)) ||
                  (widget.cascadeMode &&
                      room.id != null &&
                      DesktopCascadeHost.maybeOf(context)?.detailId ==
                          'room:${room.id}'),
              selectionMode: _selectionMode,
              onToggleSelect: room.id == null
                  ? null
                  : () => _toggleRoomSelected(room.id),
              onOpen: () => _openRoom(room),
              onRename: () => _renameRoom(room),
              onDuplicate: () => _duplicateRoom(room),
              onShare: () => _shareRoom(room),
              onDelete: () => _deleteRoom(room),
              // Guest spanning ЛК: no drag — avoids reshuffling global order by accident.
              reorderIndex: _selectionMode
                  ? null
                  : ((_selectedFloor?.id != null &&
                          room.specialSpace?.kind ==
                              SpecialSpaceKind.stairwell &&
                          room.floorId != _selectedFloor!.id)
                      ? null
                      : i),
            ),
          );
        },
      ),
    );
  }
}
