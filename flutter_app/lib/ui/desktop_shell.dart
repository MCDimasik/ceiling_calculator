import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_model.dart';
import '../domain/local_user_role.dart';
import '../domain/project_transfer.dart';
import 'adaptive_layout.dart';
import 'desktop_cascade.dart';
import 'director_archive_screen.dart';
import 'home_screen.dart';
import 'materials_flow_screens.dart';
import 'materials_result_screen.dart';
import 'pricing_hub_screen.dart';
import 'projects_screen.dart';
import 'room_editor_screen.dart';
import 'rooms_screen.dart';
import 'settings_screen.dart';
import 'sync_inbox_screen.dart';
import 'widgets/app_background.dart';
import 'widgets/numeric_input.dart';

/// Full HD desktop: cascading panes (modules → projects/rooms → detail).
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  DesktopCascadeModule? _module;
  int? _projectId;
  Widget? _detail;
  String? _detailTitle;
  Object? _detailId;

  static const _modulesW = 248.0;
  static const _listW = 380.0;

  var _roomsEpoch = 0;
  var _dropHover = false;

  List<DesktopCascadeModule> _allowed(AppUserRole role) {
    return [
      if (role.canCeilingLayout) DesktopCascadeModule.ceiling,
      if (role.canCeilingMaterials) DesktopCascadeModule.materialsCeiling,
      if (role.canFinish) DesktopCascadeModule.finish,
      if (role.canDocumentation) DesktopCascadeModule.documentation,
      if (role.canPricing) DesktopCascadeModule.pricing,
      if (role.canArchive) DesktopCascadeModule.archive,
      DesktopCascadeModule.inbox,
      if (role.canSettings) DesktopCascadeModule.settings,
    ];
  }

  void _openModule(DesktopCascadeModule m) {
    if (_module == m) return;
    setState(() {
      _module = m;
      _projectId = null;
      _detail = null;
      _detailTitle = null;
      _detailId = null;
    });
  }

  void _openProject(int id) {
    setState(() {
      _projectId = id;
      _detail = null;
      _detailTitle = null;
      _detailId = null;
    });
  }

  void _openDetail(Widget detail, {String? title, Object? detailId}) {
    setState(() {
      _detail = detail;
      _detailTitle = title;
      _detailId = detailId;
    });
  }

  void _closeDetail() {
    setState(() {
      _detail = null;
      _detailTitle = null;
      _detailId = null;
    });
  }

  void _clearProject() {
    setState(() {
      _projectId = null;
      _detail = null;
      _detailTitle = null;
      _detailId = null;
    });
  }

  void _goHome() {
    setState(() {
      _module = null;
      _projectId = null;
      _detail = null;
      _detailTitle = null;
      _detailId = null;
    });
  }

  Widget _moduleBody(DesktopCascadeModule m) {
    return switch (m) {
      DesktopCascadeModule.pricing =>
        const PricingHubScreen(cascadeMode: true),
      DesktopCascadeModule.archive =>
        const DirectorArchiveScreen(cascadeMode: true),
      DesktopCascadeModule.inbox => const SyncInboxScreen(),
      DesktopCascadeModule.settings => const SettingsScreen(),
      DesktopCascadeModule.documentation => ProjectsScreen(
          key: const ValueKey('proj-docs'),
          module: AppModule.documentation,
          cascadeMode: true,
        ),
      DesktopCascadeModule.ceiling => ProjectsScreen(
          key: const ValueKey('proj-ceiling'),
          module: AppModule.ceilingLayout,
          cascadeMode: true,
        ),
      DesktopCascadeModule.finish => ProjectsScreen(
          key: const ValueKey('proj-finish'),
          module: AppModule.finish,
          cascadeMode: true,
        ),
      DesktopCascadeModule.materialsCeiling => ProjectsScreen(
          key: const ValueKey('proj-mat'),
          materialsCalcMode: MaterialsCalcMode.ceiling,
          cascadeMode: true,
        ),
    };
  }

  Widget _roomsPane(DesktopCascadeModule m) {
    final appMod = m.appModule ?? AppModule.ceilingLayout;
    return RoomsScreen(
      key: ValueKey('rooms-$_projectId-$appMod-$_roomsEpoch'),
      projectId: _projectId!,
      module: appMod,
      embeddedInSplit: true,
      cascadeMode: true,
    );
  }

  Future<void> _importProject() async {
    try {
      final p = await importProjectFile(AppScope.of(context).projects);
      if (!mounted || p == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импортирован «${p.name}»')),
      );
      setState(() => _roomsEpoch++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта: $e')),
      );
    }
  }

  Future<void> _importDroppedPaths(List<String> paths) async {
    String? file;
    for (final p in paths) {
      final l = p.toLowerCase();
      if (l.endsWith('.ccproj') || l.endsWith('.json')) {
        file = p;
        break;
      }
    }
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Перетащите файл .ccproj')),
      );
      return;
    }
    try {
      final p = await importProjectFromPath(
        AppScope.of(context).projects,
        file,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импортирован «${p.name}»')),
      );
      setState(() => _roomsEpoch++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта: $e')),
      );
    }
  }

  Future<void> _createRoomFromEmptyDetail() async {
    final projectId = _projectId;
    final m = _module;
    if (projectId == null || m == null) return;
    if (!m.usesProjectRoomsCascade) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая комната'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: NumericInput.textKeyboard,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Название комнаты'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final room = await AppScope.of(context).projects.createRoom(
      projectId,
      name,
    );
    if (!mounted || room.id == null) return;

    final appMod = m.appModule ?? AppModule.ceilingLayout;
    _openDetail(
      RoomEditorScreen(
        projectId: projectId,
        roomId: room.id!,
        module: appMod,
      ),
      title: room.name,
      detailId: 'room:${room.id}',
    );
    setState(() => _roomsEpoch++);
  }

  /// Soft mid-pane only (projects ↔ rooms). Detail never uses this.
  Widget _midPaneSwitch({required Widget child}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) {
        return FadeTransition(opacity: anim, child: child);
      },
      child: child,
    );
  }

  Widget _cascadeBody(
    List<DesktopCascadeModule> modules,
    ColorScheme scheme,
  ) {
    final m = _module!;
    final projectCascade =
        m.usesProjectRoomsCascade || m.usesProjectThenDetail;
    final hubCascade = m.usesHubThenDetail;
    final showMid = projectCascade || hubCascade;

    Widget midChild;
    Object midKey;
    if (hubCascade) {
      midChild = _moduleBody(m);
      midKey = 'hub-$m';
    } else if (!projectCascade) {
      midChild = const SizedBox.shrink();
      midKey = 'mid-none';
    } else if (_projectId == null || m.usesProjectThenDetail) {
      midChild = _moduleBody(m);
      midKey = 'list-$m';
    } else {
      midChild = _roomsPane(m);
      midKey = 'rooms-$_projectId-$m-$_roomsEpoch';
    }

    final Widget detailChild;
    if (!showMid) {
      detailChild = KeyedSubtree(
        key: ValueKey('solo-$m'),
        child: _moduleBody(m),
      );
    } else if (_detail != null) {
      detailChild = KeyedSubtree(
        key: ValueKey('detail-$_detailId'),
        child: _DetailWorkspace(
          title: _detailTitle ?? 'Просмотр',
          moduleLabel: m.labelRu,
          onClose: _closeDetail,
          child: _detail!,
        ),
      );
    } else if (hubCascade) {
      detailChild = KeyedSubtree(
        key: ValueKey('hint-hub-$m'),
        child: DesktopEmptyState(
          icon: m.icon,
          title: m == DesktopCascadeModule.pricing
              ? 'Выберите раздел слева'
              : 'Выберите категорию слева',
          subtitle: m == DesktopCascadeModule.pricing
              ? 'Работа, материалы или комплекты откроются здесь'
              : 'Файлы категории откроются в этой области',
        ),
      );
    } else if (_projectId == null) {
      detailChild = KeyedSubtree(
        key: ValueKey('hint-project-$m'),
        child: DesktopEmptyState(
          icon: Icons.folder_open_outlined,
          title: 'Выберите объект слева',
          subtitle: m.usesProjectThenDetail
              ? 'В центре откроется расчёт материалов'
              : 'Справа появятся помещения выбранного объекта',
        ),
      );
    } else {
      detailChild = KeyedSubtree(
        key: ValueKey('hint-room-$_projectId'),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _createRoomFromEmptyDetail,
            child: DesktopEmptyState(
              icon: Icons.add_box_outlined,
              title: 'Новая комната',
              subtitle:
                  'Нажмите здесь или «+ Комната», чтобы задать имя и открыть чертёж',
              action: FilledButton.tonalIcon(
                onPressed: _createRoomFromEmptyDetail,
                icon: const Icon(Icons.add),
                label: const Text('Создать комнату'),
              ),
            ),
          ),
        ),
      );
    }

    final workArea = DropTarget(
      onDragEntered: (_) => setState(() => _dropHover = true),
      onDragExited: (_) => setState(() => _dropHover = false),
      onDragDone: (detail) async {
        setState(() => _dropHover = false);
        final paths = detail.files
            .map((f) => f.path)
            .where((p) => p.isNotEmpty)
            .toList();
        if (paths.isEmpty) return;
        await _importDroppedPaths(paths);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _modulesW,
                child: _ModulesSidebar(
                  modules: modules,
                  selected: _module,
                  onHome: _goHome,
                  onSelect: _openModule,
                  onImport: _importProject,
                ),
              ),
              _PaneDivider(scheme: scheme),
              if (showMid) ...[
                SizedBox(
                  width: _listW,
                  child: _DesktopPaneSurface(
                    child: ClipRect(
                      child: _midPaneSwitch(
                        child: KeyedSubtree(
                          key: ValueKey(midKey),
                          child: midChild,
                        ),
                      ),
                    ),
                  ),
                ),
                _PaneDivider(scheme: scheme),
              ],
              Expanded(
                child: _DesktopPaneSurface(
                  elevated: true,
                  child: detailChild,
                ),
              ),
            ],
          ),
          if (_dropHover)
            ColoredBox(
              color: scheme.primary.withValues(alpha: 0.18),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 20,
                    ),
                    child: Text(
                      'Отпустите .ccproj для импорта',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return workArea;
  }

  @override
  Widget build(BuildContext context) {
    final role = AppScope.of(context).user.effectiveRole;
    final modules = _allowed(role);
    final scheme = Theme.of(context).colorScheme;
    final home = _module == null;

    return DesktopCascadeHost(
      openModule: _openModule,
      openProject: (id) {
        final m = _module;
        if (m == DesktopCascadeModule.materialsCeiling) {
          _openDetail(
            MaterialsResultScreen(
              projectId: id,
              calcMode: MaterialsCalcMode.ceiling,
            ),
            title: 'Материалы потолка',
            detailId: 'mat:$id',
          );
          setState(() => _projectId = id);
          return;
        }
        _openProject(id);
      },
      openDetail: _openDetail,
      closeDetail: _closeDetail,
      clearProject: _clearProject,
      goHome: _goHome,
      module: _module,
      projectId: _projectId,
      hasDetail: _detail != null,
      detailId: _detailId,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackground(
          dim: true,
          allowVideo: home,
          child: SafeArea(
            // Only home ↔ cascade shell animates.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                return FadeTransition(opacity: anim, child: child);
              },
              child: home
                  ? const KeyedSubtree(
                      key: ValueKey('home'),
                      child: HomeScreen(embeddedInDesktopShell: true),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('cascade'),
                      child: _cascadeBody(modules, scheme),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneDivider extends StatelessWidget {
  const _PaneDivider({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(
      width: 1,
      thickness: 1,
      color: scheme.outlineVariant.withValues(alpha: 0.55),
    );
  }
}

/// Solid pane plate so columns read as desktop panels, not floating phone cards.
class _DesktopPaneSurface extends StatelessWidget {
  const _DesktopPaneSurface({
    required this.child,
    this.elevated = false,
  });

  final Widget child;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return ColoredBox(
      color: elevated
          ? (light
              ? scheme.surfaceContainerLowest.withValues(alpha: 0.72)
              : scheme.surface.withValues(alpha: 0.55))
          : (light
              ? scheme.surfaceContainerLow.withValues(alpha: 0.78)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.35)),
      child: child,
    );
  }
}

/// Narrow OS-style nav sidebar (not large mobile cards).
class _ModulesSidebar extends StatelessWidget {
  const _ModulesSidebar({
    required this.modules,
    required this.selected,
    required this.onHome,
    required this.onSelect,
    required this.onImport,
  });

  final List<DesktopCascadeModule> modules;
  final DesktopCascadeModule? selected;
  final VoidCallback onHome;
  final void Function(DesktopCascadeModule) onSelect;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final canImport = AppScope.of(context).user.effectiveRole.canCeilingImport;
    return ColoredBox(
      color: light
          ? const Color(0xE8E8EEF5)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Icon(Icons.apps_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Модули',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _SidebarItem(
              icon: Icons.home_outlined,
              label: 'Главная',
              selected: false,
              onTap: onHome,
            ),
          ),
          if (canImport)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _SidebarItem(
                icon: Icons.file_upload_outlined,
                label: 'Импорт .ccproj',
                selected: false,
                onTap: onImport,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              children: [
                for (final m in modules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _SidebarItem(
                      icon: m.icon,
                      label: m.labelRu,
                      selected: selected == m,
                      onTap: () => onSelect(m),
                    ),
                  ),
              ],
            ),
          ),
          if (canImport)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Text(
                'Или перетащите .ccproj\nв окно приложения',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                      height: 1.3,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? scheme.primary : scheme.onSurface,
                      ),
                ),
              ),
              if (selected)
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Workspace header for the right pane (document-style, not phone AppBar).
class _DetailWorkspace extends StatelessWidget {
  const _DetailWorkspace({
    required this.title,
    required this.moduleLabel,
    required this.onClose,
    required this.child,
  });

  final String title;
  final String moduleLabel;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.surfaceContainerLowest.withValues(alpha: 0.92),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Закрыть',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        moduleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Picks phone [HomeScreen] or [DesktopShell] from window size / defines.
class AppRootHome extends StatelessWidget {
  const AppRootHome({super.key});

  @override
  Widget build(BuildContext context) {
    if (AdaptiveBreakpoints.useDesktopChrome(context)) {
      return const DesktopShell();
    }
    return const HomeScreen();
  }
}
