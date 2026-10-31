import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_design_baseline.dart';
import '../domain/models.dart';
import '../domain/project_floors.dart';

/// Batch re-baseline: snapshot current state as new «project» for selected rooms.
class RebaselineWizardScreen extends StatefulWidget {
  const RebaselineWizardScreen({super.key, required this.projectId});

  final int projectId;

  @override
  State<RebaselineWizardScreen> createState() => _RebaselineWizardScreenState();
}

class _RebaselineWizardScreenState extends State<RebaselineWizardScreen> {
  Project? _project;
  bool _loading = true;
  bool _running = false;
  final _selected = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _project = project;
      _loading = false;
      _selected
        ..clear()
        ..addAll(
          project?.rooms
                  .where((r) => r.hasLayout && r.id != null)
                  .map((r) => r.id!)
                  .toList() ??
              [],
        );
    });
  }

  Future<void> _run() async {
    final project = _project;
    if (project == null || _selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Обновить проект?'),
        content: Text(
          'Текущее состояние ${_selected.length} комнат станет новым «проектом» '
          'для сравнения «проект vs факт». Предыдущие снимки сохраняются в истории.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Обновить')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _running = true);
    final rooms = project.rooms.where((r) => r.id != null && _selected.contains(r.id)).toList();
    final names = rebaselineRoomsWithLayout(rooms);
    for (final room in rooms) {
      await AppScope.of(context).projects.updateRoom(room);
    }
    if (!mounted) return;
    setState(() => _running = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Проект обновлён: ${names.length} комнат')),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final project = _project;
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Re-baseline')),
        body: const Center(child: Text('Проект не найден')),
      );
    }
    final withLayout = project.rooms.where((r) => r.hasLayout).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Обновить проект (re-baseline)'),
        actions: [
          TextButton(
            onPressed: _running
                ? null
                : () => setState(() {
                      if (_selected.length == withLayout.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(
                          withLayout.where((r) => r.id != null).map((r) => r.id!),
                        );
                      }
                    }),
            child: Text(_selected.length == withLayout.length ? 'Снять все' : 'Все'),
          ),
        ],
      ),
      body: withLayout.isEmpty
          ? const Center(child: Text('Нет комнат с контуром'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Зафиксируйте текущую раскладку, пол и контур как новый проект '
                      'для всех выбранных комнат. Используйте после приёмки этапа '
                      'или перед сдачей объекта.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final room in withLayout)
                  CheckboxListTile(
                    value: room.id != null && _selected.contains(room.id),
                    onChanged: room.id == null
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                _selected.add(room.id!);
                              } else {
                                _selected.remove(room.id);
                              }
                            }),
                    title: Text(
                      roomNameWithFloor(
                        room: room,
                        floors: _project?.floors ?? const [],
                      ),
                    ),
                    subtitle: Text(
                      hasFinishDesignBaseline(room)
                          ? formatFinishBaselineStatus(room)
                          : 'Baseline ещё не создан',
                    ),
                    secondary: Icon(
                      room.layoutConfirmed ? Icons.check_circle_outline : Icons.edit_outlined,
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _running || _selected.isEmpty ? null : _run,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text('Обновить проект (${_selected.length})'),
          ),
        ),
      ),
    );
  }
}
