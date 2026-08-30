import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/materials_calculator.dart';
import '../domain/models.dart';
import '../domain/project_transfer.dart';
import 'materials_result_screen.dart';
import 'project_cost_screen.dart';
import 'room_editor_screen.dart';
import 'widgets/long_press_action_tile.dart';
import 'widgets/screen_scaffold.dart';

class MaterialsProjectsScreen extends StatefulWidget {
  const MaterialsProjectsScreen({super.key});

  @override
  State<MaterialsProjectsScreen> createState() => _MaterialsProjectsScreenState();
}

class _MaterialsProjectsScreenState extends State<MaterialsProjectsScreen> {
  List<Project> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final list = await AppScope.of(context).projects.listProjects();
    if (!mounted) return;
    setState(() {
      _projects = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      appBar: AppBar(
        title: const Text('Материалы — проекты'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? const Center(child: Text('Нет проектов'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _projects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = _projects[i];
                    return LongPressActionTile(
                      title: p.name,
                      onOpen: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MaterialsRoomsScreen(projectId: p.id!),
                          ),
                        );
                        _reload();
                      },
                      onShare: () async {
                        final full = await AppScope.of(context).projects.getProject(p.id!);
                        if (full != null) await shareProject(full);
                      },
                      onDelete: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Удалить проект?'),
                            content: Text('«${p.name}»'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
                            ],
                          ),
                        );
                        if (ok == true && p.id != null) {
                          await AppScope.of(context).projects.deleteProject(p.id!);
                          await _reload();
                        }
                      },
                    );
                  },
                ),
    );
  }
}

class MaterialsRoomsScreen extends StatefulWidget {
  const MaterialsRoomsScreen({super.key, required this.projectId});

  final int projectId;

  @override
  State<MaterialsRoomsScreen> createState() => _MaterialsRoomsScreenState();
}

class _MaterialsRoomsScreenState extends State<MaterialsRoomsScreen> {
  Project? _project;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final p = await AppScope.of(context).projects.getProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _project = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final admin = AppScope.of(context).admin.unlocked;
    return ScreenScaffold(
      appBar: AppBar(
        title: Text(_project?.name ?? 'Комнаты'),
        actions: [
          if (admin)
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProjectCostScreen(projectId: widget.projectId),
                  ),
                );
              },
              child: const Text('Стоимость'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MaterialsResultScreen(projectId: widget.projectId),
                ),
              );
            },
            child: const Text('Полный Расчет'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final room in _project?.rooms ?? <Room>[])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LongPressActionTile(
                      title: room.name,
                      subtitle: room.hasLayout
                          ? 'S=${MaterialsCalculator.roomAreaM2(room.walls).toStringAsFixed(2)} м² · стен ${room.walls.length}'
                          : 'Нет чертежа',
                      onOpen: () {
                        if (room.hasLayout) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MaterialsResultScreen(
                                projectId: widget.projectId,
                                roomId: room.id,
                              ),
                            ),
                          );
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RoomEditorScreen(
                                projectId: widget.projectId,
                                roomId: room.id!,
                              ),
                            ),
                          );
                        }
                      },
                      onShare: () async {
                        if (_project != null) {
                          await shareProject(_project!, rooms: [room]);
                        }
                      },
                      onDelete: () async {
                        if (room.id == null) return;
                        await AppScope.of(context).projects.deleteRoom(widget.projectId, room.id!);
                        await _reload();
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
