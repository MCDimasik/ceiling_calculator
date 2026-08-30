import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_model.dart';
import '../domain/models.dart';
import '../domain/project_transfer.dart';
import 'rooms_screen.dart';
import 'widgets/long_press_action_tile.dart';
import 'widgets/numeric_input.dart';
import 'widgets/screen_scaffold.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({
    super.key,
    this.module = AppModule.ceilingLayout,
  });

  final AppModule module;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Project> _projects = [];
  final Map<int, double> _areaByProjectId = {};
  bool _loading = true;
  bool _refreshing = false;
  bool _started = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final repo = AppScope.of(context).projects;
    final cached = repo.cachedProjects;
    final areas = repo.cachedAreas;
    if (cached != null) {
      _projects = cached;
      _loading = false;
      if (areas != null) {
        _areaByProjectId
          ..clear()
          ..addAll(areas);
      }
    }
    _reload(showSpinner: _projects.isEmpty);
  }

  Future<void> _reload({bool showSpinner = false}) async {
    if (showSpinner && _projects.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }
    try {
      final repo = AppScope.of(context).projects;
      final list = await repo.listProjects();
      if (!mounted) return;
      setState(() {
        _projects = list;
        _loading = false;
      });
      final areas = await repo.projectFloorAreasM2();
      if (!mounted) return;
      setState(() {
        _areaByProjectId
          ..clear()
          ..addAll(areas);
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _importProject() async {
    try {
      final project = await importProjectFile(AppScope.of(context).projects);
      if (!mounted) return;
      if (project == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импортирован «${project.name}»')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта: $e')),
      );
    }
  }

  Future<void> _shareProject(Project project) async {
    final full = await AppScope.of(context).projects.getProject(project.id!);
    if (full == null || !mounted) return;
    await shareProject(full);
  }

  Future<void> _createProject() async {
    final name = await _askName(title: 'Новый проект', hint: 'Название проекта');
    if (name == null || name.isEmpty) return;
    await AppScope.of(context).projects.createProject(name);
    await _reload();
  }

  Future<void> _renameProject(Project project) async {
    final name = await _askName(
      title: 'Переименовать',
      hint: 'Название проекта',
      initial: project.name,
    );
    if (name == null || name.isEmpty || project.id == null) return;
    await AppScope.of(context).projects.renameProject(project.id!, name);
    await _reload();
  }

  Future<void> _deleteProject(Project project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить проект?'),
        content: Text('«${project.name}» и все комнаты будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true || project.id == null) return;
    await AppScope.of(context).projects.deleteProject(project.id!);
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

  Future<void> _openProject(Project project) async {
    if (project.id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomsScreen(
          projectId: project.id!,
          module: widget.module,
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      appBar: AppBar(
        title: Text(widget.module.projectsTitle),
        actions: [
          IconButton(
            tooltip: 'Импорт .ccproj',
            onPressed: _importProject,
            icon: const Icon(Icons.file_open),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: (_loading || _refreshing) ? null : () => _reload(showSpinner: false),
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        icon: const Icon(Icons.add),
        label: const Text('Проект'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Ошибка: $_error'),
        ),
      );
    }
    if (_projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('Пока нет проектов'),
            const SizedBox(height: 8),
            Text(
              'Создайте первый проект кнопкой ниже',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _reload(showSpinner: false),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        itemCount: _projects.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final p = _projects[i];
          final area = p.id != null ? _areaByProjectId[p.id!] : null;
          final date = _formatDate(p.createdAt);
          final subtitle = (area != null && area > 0)
              ? '${area.toStringAsFixed(1)} м² · $date'
              : date;
          return LongPressActionTile(
            leading: CircleAvatar(
              child: Text(
                p.name.isNotEmpty ? p.name.substring(0, 1).toUpperCase() : '?',
              ),
            ),
            title: p.name,
            subtitle: subtitle,
            onOpen: () => _openProject(p),
            onRename: () => _renameProject(p),
            onShare: () => _shareProject(p),
            onDelete: () => _deleteProject(p),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yy = local.year.toString();
    return '$dd.$mm.$yy';
  }
}
