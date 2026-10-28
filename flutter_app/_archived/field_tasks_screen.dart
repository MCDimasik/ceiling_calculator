import 'package:flutter/material.dart';

import 'widgets/screen_scaffold.dart';

import '../app_scope.dart';
import '../domain/field_role.dart';
import '../domain/field_task_routing.dart';
import '../domain/field_tasks.dart';
import '../domain/models.dart';
import '../domain/documentation_model.dart';
import 'project_dashboard_screen.dart';

/// In-app task center (offline alerts for urgent rooms / missing photos).
class FieldTasksScreen extends StatefulWidget {
  const FieldTasksScreen({super.key, this.projectId});

  final int? projectId;

  @override
  State<FieldTasksScreen> createState() => _FieldTasksScreenState();
}

class _FieldTasksScreenState extends State<FieldTasksScreen> {
  List<({Project project, FieldTask task})> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).projects;
    final roleCtrl = AppScope.of(context).fieldRole;
    final projects = widget.projectId == null
        ? await repo.listProjects()
        : [
            if (await repo.getProject(widget.projectId!) case final p?) p,
          ];
    final items = <({Project project, FieldTask task})>[];
    for (final p in projects) {
      if (p.id == null) continue;
      for (final t in buildFieldTasks(p)) {
        if (roleCtrl.role == FieldRole.worker && roleCtrl.workerName.isNotEmpty) {
          final room = p.rooms.cast<Room?>().firstWhere(
                (r) => r?.id == t.roomId,
                orElse: () => null,
              );
          if (room == null) continue;
          final cl = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
          if (cl.assignee.isEmpty) continue;
          if (!cl.assignee.toLowerCase().contains(roleCtrl.workerName.toLowerCase())) {
            continue;
          }
        }
        items.add((project: p, task: t));
      }
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      appBar: AppBar(
        title: Text(widget.projectId == null ? 'Задачи на объектах' : 'Задачи'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Открытых задач нет'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final row = _items[i];
                    final t = row.task;
                    final color = t.isBlocked
                        ? Colors.red
                        : t.isUrgent
                            ? Colors.orange
                            : Theme.of(context).colorScheme.primary;
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.notification_important, color: color),
                        title: Text('${row.project.name} · ${t.roomName}'),
                        subtitle: Text(
                          t.metaLine.isEmpty ? t.message : '${t.message}\n${t.metaLine}',
                        ),
                        isThreeLine: t.metaLine.isNotEmpty,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await openFieldTask(context, task: t);
                          await _load();
                        },
                        onLongPress: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProjectDashboardScreen(projectId: t.projectId),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
