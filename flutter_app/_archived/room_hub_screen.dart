import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/documentation_model.dart';
import '../domain/finish_design_baseline.dart';
import '../domain/finish_model.dart';
import '../domain/models.dart';
import '../domain/room_documentation_status.dart';
import 'documentation_flow_screens.dart';
import 'field_checklist_screen.dart';
import 'finish_room_screen.dart';
import 'geometry_capture_hub_screen.dart';
import 'ks2_closure_screen.dart';
import 'layout_screen.dart';
import 'materials_result_screen.dart';
import 'room_editor_screen.dart';
import 'widgets/room_workflow_chip.dart';

/// Unified entry for one room: layout, finish, materials, documentation.
class RoomHubScreen extends StatelessWidget {
  const RoomHubScreen({
    super.key,
    required this.projectId,
    required this.roomId,
    this.initialModule = AppModule.ceilingLayout,
    this.autoOpenModule = false,
  });

  static const routeName = 'room_hub';

  final int projectId;
  final int roomId;
  final AppModule initialModule;
  final bool autoOpenModule;

  @override
  Widget build(BuildContext context) {
    return _RoomHubBody(
      projectId: projectId,
      roomId: roomId,
      initialModule: initialModule,
      autoOpenModule: autoOpenModule,
    );
  }
}

class _RoomHubBody extends StatefulWidget {
  const _RoomHubBody({
    required this.projectId,
    required this.roomId,
    required this.initialModule,
    required this.autoOpenModule,
  });

  final int projectId;
  final int roomId;
  final AppModule initialModule;
  final bool autoOpenModule;

  @override
  State<_RoomHubBody> createState() => _RoomHubBodyState();
}

class _RoomHubBodyState extends State<_RoomHubBody> {
  Project? _project;
  Room? _room;
  bool _loading = true;
  bool _initialNavDone = false;

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
      _loading = false;
    });
    if (!_initialNavDone && room != null && widget.autoOpenModule) {
      _initialNavDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialModule(room!));
    }
  }

  Future<void> _openLayout(Room room) async {
    if (!room.hasLayout) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RoomEditorScreen(
            projectId: widget.projectId,
            roomId: widget.roomId,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LayoutScreen(
            projectId: widget.projectId,
            roomId: widget.roomId,
          ),
        ),
      );
    }
    await _load();
  }

  Future<void> _openFinish() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinishRoomScreen(
          projectId: widget.projectId,
          roomId: widget.roomId,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openMaterials() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MaterialsResultScreen(
          projectId: widget.projectId,
          roomId: widget.roomId,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openCapture() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GeometryCaptureHubScreen(
          projectId: widget.projectId,
          roomId: widget.roomId,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openDocumentation() async {
    await openDocumentationRoom(
      context,
      projectId: widget.projectId,
      roomId: widget.roomId,
    );
    await _load();
  }

  Future<void> _openInitialModule(Room room) async {
    switch (widget.initialModule) {
      case AppModule.ceilingLayout:
        await _openLayout(room);
      case AppModule.finish:
        await _openFinish();
      case AppModule.materials:
        await _openMaterials();
      case AppModule.documentation:
        await _openDocumentation();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final project = _project;
    final room = _room;
    if (project == null || room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Комната')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }

    final summary = roomDocumentationSummary(room, project);
    final highlight = widget.autoOpenModule ? widget.initialModule : null;
    final checklist = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
    final workflow = roomWorkflowStatus(room, summary, checklist: checklist);
    final role = AppScope.of(context).fieldRole.role;
    final module = widget.initialModule;

    return Scaffold(
      appBar: AppBar(title: Text('Комната · ${room.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (module == AppModule.documentation) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.task_alt),
                title: Row(
                  children: [
                    Expanded(child: Text(summary.shortLabel)),
                    RoomWorkflowChip(status: workflow),
                  ],
                ),
                subtitle: Text(
                  summary.missingItems.isEmpty
                      ? 'Комплекс отделки · документация в порядке'
                      : 'Не закрыто: ${summary.missingItems.first}',
                ),
              ),
            ),
            if (hasFinishDesignBaseline(room)) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.compare_arrows, size: 20),
                  title: const Text('Проект vs факт'),
                  subtitle: Text(formatFinishBaselineStatus(room)),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
          if (module == AppModule.ceilingLayout && role.canEditLayout) ...[
            _HubTile(
              icon: Icons.grid_on,
              title: 'Раскладка потолка',
              subtitle: room.hasLayout
                  ? (room.layoutConfirmed ? 'Подтверждена' : 'Черновик')
                  : 'Нарисовать контур',
              highlighted: highlight == AppModule.ceilingLayout,
              onTap: () => _openLayout(room),
            ),
            _HubTile(
              icon: Icons.camera_alt_outlined,
              title: 'Захват помещения',
              subtitle: room.hasLayout
                  ? 'Фото-план · RoomPlan · AR углы'
                  : 'Создать контур с устройства',
              onTap: _openCapture,
            ),
          ],
          if (module == AppModule.finish && role.canEditLayout)
            _HubTile(
              icon: Icons.home_work_outlined,
              title: 'Отделка',
              subtitle: 'Пол · стены · потолок · проёмы',
              highlighted: highlight == AppModule.finish,
              onTap: _openFinish,
            ),
          if (module == AppModule.materials && role.canSeePricing)
            _HubTile(
              icon: Icons.inventory_2_outlined,
              title: 'Материалы',
              subtitle: 'Потолок + отделка (BOM)',
              highlighted: highlight == AppModule.materials,
              onTap: _openMaterials,
            ),
          if (module == AppModule.documentation) ...[
            if (role.canEditLayout) ...[
              _HubTile(
                icon: Icons.grid_on,
                title: 'Раскладка потолка',
                subtitle: room.hasLayout
                    ? (room.layoutConfirmed ? 'Подтверждена' : 'Черновик')
                    : 'Нарисовать контур',
                highlighted: highlight == AppModule.ceilingLayout,
                onTap: () => _openLayout(room),
              ),
              _HubTile(
                icon: Icons.home_work_outlined,
                title: 'Отделка',
                subtitle: 'Пол · стены · потолок · проёмы',
                highlighted: highlight == AppModule.finish,
                onTap: _openFinish,
              ),
            ],
            if (role.canSeePricing)
              _HubTile(
                icon: Icons.inventory_2_outlined,
                title: 'Материалы',
                subtitle: 'Потолок + отделка (BOM)',
                highlighted: highlight == AppModule.materials,
                onTap: _openMaterials,
              ),
            if (role.canEditLayout)
              _HubTile(
                icon: Icons.camera_alt_outlined,
                title: 'Захват помещения',
                subtitle: room.hasLayout
                    ? 'Фото-план · RoomPlan · AR углы'
                    : 'Создать контур с устройства',
                onTap: _openCapture,
              ),
            _HubTile(
              icon: Icons.description_outlined,
              title: role.workerOnlyChecklist ? 'Скрытые работы' : 'Документация',
              subtitle: summary.readyForHandover
                  ? 'Готово к акту'
                  : '${summary.shortLabel} · скрытые ${summary.hiddenWorksDone}/${summary.hiddenWorksTotal}',
              highlighted: highlight == AppModule.documentation,
              onTap: role.workerOnlyChecklist
                  ? () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FieldChecklistScreen(
                            projectId: widget.projectId,
                            roomId: widget.roomId,
                          ),
                        ),
                      );
                      await _load();
                    }
                  : _openDocumentation,
            ),
            if (role.canSeePricing)
              _HubTile(
                icon: Icons.table_chart_outlined,
                title: 'Ведомость материалов',
                subtitle: 'По комнате · Excel / PDF / текст',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DocumentationVedomostScreen(
                        projectId: widget.projectId,
                        roomId: widget.roomId,
                      ),
                    ),
                  );
                  await _load();
                },
              ),
            if (role.canCloseActs)
              _HubTile(
                icon: Icons.receipt_long_outlined,
                title: 'Закрытие КС-2',
                subtitle: 'Промежуточный акт по полу / стенам / потолку',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Ks2ClosureScreen(
                        projectId: widget.projectId,
                        focusRoomId: widget.roomId,
                      ),
                    ),
                  );
                  await _load();
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: highlighted ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
