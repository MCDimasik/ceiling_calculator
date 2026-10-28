import 'dart:io';

import 'package:flutter/material.dart';

import 'widgets/screen_scaffold.dart';

import '../app_scope.dart';
import '../domain/documentation_model.dart';
import '../domain/finish_model.dart';
import '../domain/field_role.dart';
import '../domain/documentation_photos.dart';
import '../domain/models.dart';
import '../domain/project_dashboard.dart';
import '../domain/room_documentation_status.dart';
import 'project_dashboard_screen.dart';
import 'room_navigation.dart';
import 'contract_workspace_screen.dart';

/// Worker / foreman fast path: hidden works photos only.
class FieldChecklistScreen extends StatefulWidget {
  const FieldChecklistScreen({
    super.key,
    required this.projectId,
    required this.roomId,
    this.highlightStepId,
  });

  final int projectId;
  final int roomId;
  final String? highlightStepId;

  @override
  State<FieldChecklistScreen> createState() => _FieldChecklistScreenState();
}

class _FieldChecklistScreenState extends State<FieldChecklistScreen> {
  Project? _project;
  Room? _room;
  RoomDocumentationChecklist _checklist = RoomDocumentationChecklist();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    Room? room;
    if (project != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    if (!mounted) return;
    setState(() {
      _project = project;
      _room = room;
      _checklist = RoomDocumentationChecklist.fromJson(room?.documentationChecklistJson);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final room = _room;
    if (room?.id == null) return;
    final json = roomChecklistJsonForSave(_checklist, room!.documentationChecklistJson);
    await AppScope.of(context).projects.updateRoomChecklist(
          room.id!,
          checklistJson: json,
        );
    room.documentationChecklistJson = json;
  }

  Future<void> _addPhoto(String stepId) async {
    final room = _room;
    if (room?.id == null) return;
    final path = await pickAndStoreDocumentationPhoto(
      projectId: widget.projectId,
      roomId: room!.id!,
      stepId: stepId,
    );
    if (path == null || !mounted) return;
    setState(() {
      final list = List<String>.from(_checklist.stepPhotos[stepId] ?? [])..add(path);
      _checklist.stepPhotos[stepId] = list;
    });
    await _save();
    await maybePromptScopedKs2(
      context,
      projectId: widget.projectId,
      roomId: room.id!,
      stepId: stepId,
    );
  }

  Future<void> _removePhoto(String stepId, String path) async {
    await removeDocumentationPhoto(path);
    if (!mounted) return;
    setState(() {
      final list = List<String>.from(_checklist.stepPhotos[stepId] ?? [])..remove(path);
      if (list.isEmpty) {
        _checklist.stepPhotos.remove(stepId);
      } else {
        _checklist.stepPhotos[stepId] = list;
      }
    });
    await _save();
  }

  void _viewPhoto(String path, String title) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(title, style: Theme.of(ctx).textTheme.titleSmall),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Закрыть'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleManualTask(ManualFieldTask task, bool? done) async {
    setState(() => task.done = done ?? false);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    final project = _project;
    final room = _room;
    if (project == null || room == null) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Смена')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }

    final summary = roomDocumentationSummary(room, project, checklist: _checklist);
    final hwSteps = summary.steps
        .where((s) => s.step.phase == DocumentationPhase.hiddenWorks)
        .toList();

    return ScreenScaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Смена · ${room.name}'),
            if (_checklist.assignee.isNotEmpty)
              Text(_checklist.assignee, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LinearProgressIndicator(
            value: summary.hiddenWorksTotal == 0
                ? 0
                : summary.hiddenWorksDone / summary.hiddenWorksTotal,
          ),
          const SizedBox(height: 8),
          Text(
            'Скрытые: ${summary.hiddenWorksDone}/${summary.hiddenWorksTotal}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (_checklist.assignee.isNotEmpty ||
              _checklist.dueDate != null ||
              _checklist.manualTasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_checklist.assignee.isNotEmpty)
                      Text('Назначено: ${_checklist.assignee}'),
                    if (_checklist.dueDate != null)
                      Text(
                        'Срок: ${_checklist.dueDate!.day.toString().padLeft(2, '0')}.'
                        '${_checklist.dueDate!.month.toString().padLeft(2, '0')}.'
                        '${_checklist.dueDate!.year}',
                      ),
                    if (_checklist.manualTasks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Задачи', style: Theme.of(context).textTheme.titleSmall),
                      for (final t in _checklist.manualTasks)
                        CheckboxListTile(
                          value: t.done,
                          onChanged: (v) => _toggleManualTask(t, v),
                          title: Text(t.message),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          for (final st in hwSteps)
            if (!st.applies)
              ListTile(
                leading: Icon(Icons.remove_circle_outline, color: Theme.of(context).disabledColor),
                title: Text(st.step.title, style: TextStyle(color: Theme.of(context).disabledColor)),
                subtitle: Text('Не требуется · ${st.hint}'),
              )
            else
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: widget.highlightStepId == st.step.id
                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            st.done ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: st.done ? Theme.of(context).colorScheme.primary : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(st.step.title, style: Theme.of(context).textTheme.titleSmall),
                          ),
                        ],
                      ),
                      if (st.hint.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(st.hint, style: Theme.of(context).textTheme.bodySmall),
                        ),
                      if (_checklist.photosFor(st.step.id).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _checklist.photosFor(st.step.id).length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final path = _checklist.photosFor(st.step.id)[i];
                              final file = File(path);
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  InkWell(
                                    onTap: () => _viewPhoto(path, st.step.title),
                                    borderRadius: BorderRadius.circular(6),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: file.existsSync()
                                          ? Image.file(file, width: 64, height: 64, fit: BoxFit.cover)
                                          : Container(
                                              width: 64,
                                              height: 64,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              child: const Icon(Icons.broken_image_outlined),
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    top: -6,
                                    right: -6,
                                    child: Material(
                                      color: Theme.of(context).colorScheme.errorContainer,
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () => _removePhoto(st.step.id, path),
                                        child: const Padding(
                                          padding: EdgeInsets.all(2),
                                          child: Icon(Icons.close, size: 16),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _addPhoto(st.step.id),
                        icon: const Icon(Icons.add_a_photo),
                        label: Text(
                          _checklist.photosFor(st.step.id).isEmpty
                              ? 'Сфотографировать'
                              : 'Ещё фото (${_checklist.photosFor(st.step.id).length})',
                        ),
                      ),
                      if (_checklist.hiddenWorksConfirmed[st.step.id] != true &&
                          _checklist.photosFor(st.step.id).isEmpty)
                        TextButton(
                          onPressed: () async {
                            setState(() => _checklist.hiddenWorksConfirmed[st.step.id] = true);
                            await _save();
                            final room = _room;
                            if (room?.id != null && mounted) {
                              await maybePromptScopedKs2(
                                context,
                                projectId: widget.projectId,
                                roomId: room!.id!,
                                stepId: st.step.id,
                              );
                            }
                          },
                          child: const Text('Без фото — подтверждаю'),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Project picker for field shift (worker / foreman home shortcut).
class FieldShiftProjectsScreen extends StatelessWidget {
  const FieldShiftProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FieldShiftProjectsBody();
  }
}

class _FieldShiftProjectsBody extends StatefulWidget {
  const _FieldShiftProjectsBody();

  @override
  State<_FieldShiftProjectsBody> createState() => _FieldShiftProjectsBodyState();
}

class _FieldShiftProjectsBodyState extends State<_FieldShiftProjectsBody> {
  List<Project> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      appBar: AppBar(title: const Text('Смена на объекте')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _projects.length,
              itemBuilder: (context, i) {
                final p = _projects[i];
                return Card(
                  child: ListTile(
                    title: Text(p.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      if (p.id == null) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FieldShiftRoomsScreen(projectId: p.id!),
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

class FieldShiftRoomsScreen extends StatefulWidget {
  const FieldShiftRoomsScreen({super.key, required this.projectId});

  final int projectId;

  @override
  State<FieldShiftRoomsScreen> createState() => _FieldShiftRoomsScreenState();
}

class _FieldShiftRoomsScreenState extends State<FieldShiftRoomsScreen> {
  Project? _project;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _project = project;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    final project = _project;
    if (project == null) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Комнаты')),
        body: const Center(child: Text('Проект не найден')),
      );
    }
    final roleCtrl = AppScope.of(context).fieldRole;
    final items = roomsForFieldShift(
      project,
      assigneeFilter: roleCtrl.role == FieldRole.worker ? roleCtrl.workerName : null,
      onlyUnassigned: roleCtrl.role == FieldRole.worker && roleCtrl.workerName.isNotEmpty,
    );
    return ScreenScaffold(
      appBar: AppBar(
        title: Text('Смена · ${project.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_outlined),
            tooltip: 'Сводка',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProjectDashboardScreen(projectId: widget.projectId),
              ),
            ),
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('Открытых задач нет — всё закрыто'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final cl = RoomDocumentationChecklist.fromJson(item.room.documentationChecklistJson);
                return Card(
                  child: ListTile(
                    title: Text(item.room.name),
                    subtitle: Text(
                      cl.assignee.isEmpty
                          ? item.summary.shortLabel
                          : '${cl.assignee} · ${item.summary.shortLabel}',
                    ),
                    trailing: const Icon(Icons.camera_alt_outlined),
                    onTap: () async {
                      if (item.room.id == null) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FieldChecklistScreen(
                            projectId: widget.projectId,
                            roomId: item.room.id!,
                          ),
                        ),
                      );
                      await _load();
                    },
                  ),
                );
              },
            ),
    );
  }
}
