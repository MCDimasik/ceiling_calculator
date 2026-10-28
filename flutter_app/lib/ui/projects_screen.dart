import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_model.dart';
import '../domain/models.dart';
import '../domain/project_transfer.dart';
import 'materials_flow_screens.dart';
import 'materials_result_screen.dart';
import 'project_dashboard_screen.dart';
import 'rooms_screen.dart';
import 'widgets/app_extended_fab.dart';
import 'widgets/archive_pull_reveal.dart';
import 'widgets/long_press_action_tile.dart';
import 'widgets/numeric_input.dart';
import 'widgets/screen_scaffold.dart';
import 'widgets/transparent_reorder_proxy.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({
    super.key,
    this.module = AppModule.ceilingLayout,
    this.archived = false,
    this.materialsCalcMode,
    this.openDashboardOnSelect = false,
  });

  final AppModule module;
  final bool archived;
  /// When set, opening a project skips rooms and goes to materials for that scope.
  final MaterialsCalcMode? materialsCalcMode;

  /// Home «Сводка объектов» — open [ProjectDashboardScreen] instead of rooms.
  final bool openDashboardOnSelect;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Project> _projects = [];
  final Map<int, double> _areaByProjectId = {};
  final Map<int, (int ready, int total)> _docReadyByProjectId = {};
  bool _loading = true;
  bool _refreshing = false;
  bool _started = false;
  String? _error;
  int _archivedCount = 0;
  /// Blocks pull-to-reveal archive while the reorder handle / list drag is active.
  bool _reorderHandlePressed = false;
  bool _reorderDragActive = false;

  bool get _archivePullLocked =>
      _reorderHandlePressed || _reorderDragActive;

  void _setReorderHandlePressed(bool pressed) {
    if (_reorderHandlePressed == pressed) return;
    setState(() => _reorderHandlePressed = pressed);
  }

  void _setReorderDragActive(bool active) {
    if (_reorderDragActive == active) {
      if (!active && _reorderHandlePressed) {
        setState(() => _reorderHandlePressed = false);
      }
      return;
    }
    setState(() {
      _reorderDragActive = active;
      if (!active) _reorderHandlePressed = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final repo = AppScope.of(context).projects;
    final cached = repo.cachedProjects;
    final areas = repo.cachedAreas;
    final docReady = repo.cachedDocReady;
    if (cached != null && !widget.archived) {
      _projects = cached;
      _loading = false;
      if (areas != null) {
        _areaByProjectId
          ..clear()
          ..addAll(areas);
      }
      if (docReady != null && widget.module == AppModule.documentation) {
        _docReadyByProjectId
          ..clear()
          ..addAll(docReady);
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
      final list = await repo.listProjects(archived: widget.archived);
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
      if (!widget.archived) {
        final count = await repo.archivedProjectCount();
        if (!mounted) return;
        setState(() => _archivedCount = count);
      }
      if (widget.module == AppModule.documentation) {
        final docCounts = await repo.projectDocumentationReadyCounts();
        if (!mounted) return;
        setState(() {
          _docReadyByProjectId
            ..clear()
            ..addAll(docCounts);
        });
      }
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

  Future<void> _archiveProject(Project project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('В архив?'),
        content: Text('«${project.name}» будет скрыт из списка. Его можно вернуть из архива.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('В архив')),
        ],
      ),
    );
    if (ok != true || project.id == null) return;
    await AppScope.of(context).projects.archiveProject(project.id!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${project.name}» в архиве')),
      );
    }
    await _reload();
  }

  Future<void> _restoreProject(Project project) async {
    if (project.id == null) return;
    await AppScope.of(context).projects.unarchiveProject(project.id!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${project.name}» восстановлен')),
      );
    }
    await _reload();
  }

  Future<void> _deleteProject(Project project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить проект?'),
        content: Text('«${project.name}» и все комнаты будут удалены безвозвратно.'),
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
    if (widget.materialsCalcMode == MaterialsCalcMode.ceiling ||
        widget.materialsCalcMode == MaterialsCalcMode.finish) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MaterialsResultScreen(
            projectId: project.id!,
            calcMode: widget.materialsCalcMode!,
          ),
        ),
      );
      await _reload();
      return;
    }
    // Warm full project so RoomsScreen / dashboard paint without spinner.
    await AppScope.of(context).projects.getProject(project.id!);
    if (!mounted) return;
    if (widget.openDashboardOnSelect) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProjectDashboardScreen(projectId: project.id!),
        ),
      );
      await _reload();
      return;
    }
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

  String _appBarTitle() {
    if (widget.archived) return 'Архив';
    if (widget.openDashboardOnSelect) return 'Сводка объектов';
    if (widget.materialsCalcMode == MaterialsCalcMode.ceiling) {
      return 'Проекты · материалы потолка';
    }
    if (widget.materialsCalcMode == MaterialsCalcMode.finish) {
      return 'Проекты · материалы отделки';
    }
    return widget.module.projectsTitle;
  }

  Future<void> _openArchive() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectsScreen(
          module: widget.module,
          archived: true,
          materialsCalcMode: widget.materialsCalcMode,
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      appBar: AppBar(
        title: Text(_appBarTitle()),
        actions: [
          if (!widget.archived)
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
      floatingActionButton: widget.archived
          ? null
          : AppExtendedFab(
              heroTag: 'projects_fab',
              onPressed: _createProject,
              icon: Icons.add,
              label: 'Проект',
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
      final emptyBody = RefreshIndicator(
        onRefresh: () => _reload(showSpinner: false),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.45,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.archived ? Icons.archive_outlined : Icons.folder_open,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(widget.archived ? 'Архив пуст' : 'Пока нет проектов'),
                    if (!widget.archived) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Создайте первый проект кнопкой ниже',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      if (widget.archived) return emptyBody;
      return ArchivePullReveal(
        locked: _archivePullLocked,
        archiveTile: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ArchiveRevealBar(
            count: _archivedCount,
            onTap: _openArchive,
          ),
        ),
        child: emptyBody,
      );
    }

    final listBody = RefreshIndicator(
      onRefresh: () => _reload(showSpinner: false),
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        buildDefaultDragHandles: false,
        proxyDecorator: transparentReorderProxyDecorator,
        itemCount: _projects.length,
        onReorderStart: widget.archived
            ? null
            : (_) => _setReorderDragActive(true),
        onReorderEnd: widget.archived
            ? null
            : (_) => _setReorderDragActive(false),
        onReorder: widget.archived
            ? (_, __) {}
            : (oldIndex, newIndex) async {
                if (newIndex > oldIndex) newIndex -= 1;
                setState(() {
                  final item = _projects.removeAt(oldIndex);
                  _projects.insert(newIndex, item);
                });
                final ids = _projects
                    .where((p) => p.id != null)
                    .map((p) => p.id!)
                    .toList();
                await AppScope.of(context).projects.reorderProjects(ids);
              },
        itemBuilder: (context, i) {
          final p = _projects[i];
          final area = p.id != null ? _areaByProjectId[p.id!] : null;
          final date = _formatDate(p.createdAt);
          final docReady = p.id != null ? _docReadyByProjectId[p.id!] : null;
          final subtitle = () {
            if (widget.module == AppModule.documentation && docReady != null) {
              final (ready, total) = docReady;
              final areaPart = area != null && area > 0 ? '${area.toStringAsFixed(1)} м² · ' : '';
              return '$areaPartготово $ready/$total · $date';
            }
            if (area != null && area > 0) {
              return '${area.toStringAsFixed(1)} м² · $date';
            }
            return date;
          }();
          return Padding(
            key: ValueKey(p.id ?? 'project-$i'),
            padding: const EdgeInsets.only(bottom: 8),
            child: LongPressActionTile(
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
              onArchive: widget.archived ? null : () => _archiveProject(p),
              onRestore: widget.archived ? () => _restoreProject(p) : null,
              onDelete: () => _deleteProject(p),
              reorderIndex: widget.archived ? null : i,
              onReorderHandleActive: widget.archived
                  ? null
                  : _setReorderHandlePressed,
            ),
          );
        },
      ),
    );

    if (widget.archived) return listBody;

    return ArchivePullReveal(
      locked: _archivePullLocked,
      archiveTile: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _ArchiveRevealBar(
          count: _archivedCount,
          onTap: _openArchive,
        ),
      ),
      child: listBody,
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

class _ArchiveRevealBar extends StatelessWidget {
  const _ArchiveRevealBar({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  static String _archiveSubtitle(int count) {
    if (count <= 0) return 'Скрытые объекты';
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return '$count проектов';
    if (mod10 == 1) return '$count проект';
    if (mod10 >= 2 && mod10 <= 4) return '$count проекта';
    return '$count проектов';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 72,
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: const Icon(Icons.archive_outlined),
        ),
        title: const Text('Архив'),
        subtitle: Text(_archiveSubtitle(count)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
