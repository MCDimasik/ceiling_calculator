import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_model.dart';
import '../domain/materials_calculator.dart';
import '../domain/models.dart';
import '../domain/project_transfer.dart';
import 'finish_room_screen.dart';
import 'layout_screen.dart';
import 'master_plan_screen.dart';
import 'room_editor_screen.dart';
import 'widgets/long_press_action_tile.dart';
import 'widgets/numeric_input.dart';
import 'widgets/screen_scaffold.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({
    super.key,
    required this.projectId,
    this.module = AppModule.ceilingLayout,
  });

  final int projectId;
  final AppModule module;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  Project? _project;
  bool _loading = true;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final project = await AppScope.of(context).projects.getProject(widget.projectId);
      if (!mounted) return;
      setState(() {
        _project = project;
        _loading = false;
        if (project == null) _error = 'Проект не найден';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createRoom() async {
    final name = await _askName(title: 'Новая комната', hint: 'Название комнаты');
    if (name == null || name.isEmpty) return;
    await AppScope.of(context).projects.createRoom(widget.projectId, name);
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
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    if (project == null || !mounted) return;
    await shareProject(project, rooms: [room]);
  }

  Future<void> _openRoom(Room room) async {
    if (room.id == null) return;
    if (widget.module == AppModule.finish) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FinishRoomScreen(
            projectId: widget.projectId,
            roomId: room.id!,
          ),
        ),
      );
      await _reload();
      return;
    }
    // Kivy parity: rooms with walls ≥ 3 open layout directly (skip editor).
    if (room.hasLayout) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LayoutScreen(
            projectId: widget.projectId,
            roomId: room.id!,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RoomEditorScreen(
            projectId: widget.projectId,
            roomId: room.id!,
          ),
        ),
      );
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _project?.rooms ?? [];
    final area = rooms.fold<double>(0, (a, r) => a + MaterialsCalculator.roomAreaM2(r.walls));
    final perimeter =
        rooms.fold<double>(0, (a, r) => a + MaterialsCalculator.roomPerimeterCm(r.walls) / 100);
    final title = _project == null
        ? 'Комнаты'
        : '${_project!.name} · ${area.toStringAsFixed(2)} м² · P ${perimeter.toStringAsFixed(2)} м';
    return ScreenScaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'План объекта',
            onPressed: _project == null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MasterPlanScreen(projectId: widget.projectId),
                      ),
                    );
                    await _reload();
                  },
            icon: const Icon(Icons.apartment_outlined),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _project == null ? null : _createRoom,
        icon: const Icon(Icons.add),
        label: const Text('Комната'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Ошибка: $_error'));
    }
    final rooms = _project?.rooms ?? [];
    if (rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.meeting_room_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('В проекте пока нет комнат'),
            const SizedBox(height: 8),
            Text(
              'Добавьте комнату и откройте редактор стен',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final room = rooms[i];
          final subtitle = room.hasLayout
              ? () {
                  final a = MaterialsCalculator.roomAreaM2(room.walls);
                  final p = MaterialsCalculator.roomPerimeterCm(room.walls) / 100;
                  return 'Стен: ${room.walls.length} · ${a.toStringAsFixed(2)} м² · P ${p.toStringAsFixed(2)} м';
                }()
              : 'Чертёж ещё не создан';
          return LongPressActionTile(
            leading: Icon(
              room.hasLayout ? Icons.crop_square : Icons.crop_square_outlined,
            ),
            title: room.name,
            subtitle: subtitle,
            onOpen: () => _openRoom(room),
            onRename: () => _renameRoom(room),
            onShare: () => _shareRoom(room),
            onDelete: () => _deleteRoom(room),
          );
        },
      ),
    );
  }
}
