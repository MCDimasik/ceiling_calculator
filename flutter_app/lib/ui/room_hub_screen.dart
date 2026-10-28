import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/documentation_model.dart';
import '../domain/finish_model.dart';
import '../domain/models.dart';
import '../domain/room_documentation_status.dart';
import 'documentation_flow_screens.dart';
import 'finish_materials_screen.dart';
import 'finish_room_screen.dart';
import 'geometry_capture_hub_screen.dart';
import 'layout_screen.dart';
import 'materials_result_screen.dart';
import 'materials_flow_screens.dart';
import 'room_editor_screen.dart';
import 'widgets/room_workflow_chip.dart';
import 'widgets/screen_scaffold.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cached = AppScope.of(context).projects.peekCachedProject(widget.projectId);
      if (cached != null && mounted) {
        Room? room;
        for (final r in cached.rooms) {
          if (r.id == widget.roomId) room = r;
        }
        setState(() {
          _project = cached;
          _room = room;
          _loading = false;
        });
      }
      _load();
    });
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
        builder: (_) => FinishMaterialsScreen(
          projectId: widget.projectId,
          roomId: widget.roomId,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openCeilingMaterials() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MaterialsResultScreen(
          projectId: widget.projectId,
          roomId: widget.roomId,
          calcMode: MaterialsCalcMode.ceiling,
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
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    final project = _project;
    final room = _room;
    if (project == null || room == null) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Комната')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }

    final summary = roomDocumentationSummary(room, project);
    final highlight = widget.autoOpenModule ? widget.initialModule : null;
    final checklist = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
    final doc = ProjectDocumentation.fromJson(project.documentationJson);
    final workflow = roomWorkflowStatus(
      room,
      summary,
      checklist: checklist,
      project: project,
      documentation: doc,
    );
    final module = widget.initialModule;

    return ScreenScaffold(
      appBar: AppBar(title: Text('Комната · ${room.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (module == AppModule.ceilingLayout) ...[
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
          if (module == AppModule.finish)
            _HubTile(
              icon: Icons.home_work_outlined,
              title: 'Отделка',
              subtitle: 'Пол · стены · потолок · проёмы',
              highlighted: highlight == AppModule.finish,
              onTap: _openFinish,
            ),
          if (module == AppModule.materials) ...[
            _HubTile(
              icon: Icons.inventory_2_outlined,
              title: 'Материалы отделки',
              subtitle: 'Пол · стены · площади · доп. работы',
              highlighted: highlight == AppModule.materials,
              onTap: _openMaterials,
            ),
            _HubTile(
              icon: Icons.grid_view_rounded,
              title: 'Материалы потолка',
              subtitle: 'Направляющие, плиты, подвесы',
              onTap: _openCeilingMaterials,
            ),
          ],
          if (module == AppModule.documentation)
            Card(
              clipBehavior: Clip.antiAlias,
              color: highlight == AppModule.documentation
                  ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                  : null,
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Row(
                  children: [
                    Expanded(child: Text('Документы · ${room.name}')),
                    RoomWorkflowChip(status: workflow),
                  ],
                ),
                subtitle: const Text('КС-2 · ведомость · схемы · скрытые'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openDocumentation,
              ),
            ),
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
