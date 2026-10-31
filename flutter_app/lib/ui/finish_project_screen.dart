import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../domain/finish_extra_works.dart';
import '../domain/finish_layer_pricing.dart';
import '../domain/finish_model.dart';
import '../domain/finish_vedomost.dart';
import '../domain/local_user_role.dart';
import '../domain/materials_calculator.dart';
import '../domain/models.dart';
import '../domain/money_format.dart';
import '../domain/project_floors.dart';
import '../domain/room_finish_areas.dart';
import '../domain/special_space.dart';
import 'finish_bulk_editors.dart';
import 'finish_materials_screen.dart';
import 'master_plan_screen.dart';
import 'room_navigation.dart';
import 'widgets/screen_scaffold.dart';

/// Project-level finish hub: overview of all rooms + extra works constructor.
class FinishProjectScreen extends StatefulWidget {
  const FinishProjectScreen({super.key, required this.projectId});

  final int projectId;

  @override
  State<FinishProjectScreen> createState() => _FinishProjectScreenState();
}

class _FinishProjectScreenState extends State<FinishProjectScreen>
    with SingleTickerProviderStateMixin {
  Project? _project;
  FinishExtraWorksState _extra = FinishExtraWorksState();
  bool _loading = true;
  String? _error;
  late final TabController _tabs;
  bool _showExtraFab = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _tabs.addListener(_onTabsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _onTabsChanged() {
    // Only react when the settled index changes — TabController notifies every
    // animation tick, and rebuilding Scaffold/FAB each frame detaches Material
    // ink (`referenceBox.attached`).
    if (_tabs.indexIsChanging) return;
    final show = _tabs.index == 4;
    if (show != _showExtraFab && mounted) {
      setState(() => _showExtraFab = show);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabsChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final projects = AppScope.of(context).projects;
      final project = await projects.getProject(widget.projectId);
      if (!mounted) return;
      if (project != null) {
        // Heal leaked «общая цена» accents from older bulk-copy / diverged prices.
        await sanitizeProjectPriceGroups(
          project.rooms,
          persist: projects.updateRoom,
        );
      }
      if (!mounted) return;
      setState(() {
        _project = project;
        _extra = FinishExtraWorksState.fromJson(project?.finishExtraWorksJson);
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

  Future<void> _persistExtra() async {
    final project = _project;
    if (project?.id == null) return;
    final json = _extra.toJson();
    project!.finishExtraWorksJson = json;
    await AppScope.of(context).projects.updateFinishExtraWorks(
          project.id!,
          finishExtraWorksJson: json,
        );
  }

  List<Room> get _layoutRooms =>
      (_project?.rooms ?? []).where(roomHasFinishGeometry).toList();

  Future<void> _openRoom(Room room, {int tab = 0}) async {
    if (room.id == null) return;
    await openFinishRoom(
      context,
      projectId: widget.projectId,
      roomId: room.id!,
      initialTabIndex: tab,
    );
    if (!mounted) return;
    // Wait for route/ink teardown; immediate setState after pop races Material.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (mounted) await _load(showSpinner: false);
  }

  Future<void> _applyLayerPricesToAll() async {
    final rooms = _layoutRooms;
    if (rooms.isEmpty) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Цены слоёв по объекту'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'autofill'),
            child: const Text('Подтянуть пустые из каталога работ'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'autofill_all'),
            child: const Text('Обновить все из каталога'),
          ),
          if (rooms.length >= 2)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'copy'),
              child: const Text('Скопировать цены из первого помещения'),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final n = await applyFinishLayerPricesAcrossRooms(
      context,
      rooms: rooms,
      source: choice == 'copy' ? rooms.first : null,
      autofillOnlyEmpty: choice != 'autofill_all',
    );
    if (!mounted) return;
    await _load(showSpinner: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n > 0
              ? 'Обновлены цены в $n помещ.'
              : 'Нечего обновлять — цены уже стоят или нет совпадений',
        ),
      ),
    );
  }

  Future<void> _setProjectFinishIncludes({
    bool? floor,
    bool? walls,
    bool? ceiling,
  }) async {
    final project = _project;
    if (project == null) return;
    final repo = AppScope.of(context).projects;
    for (final room in project.rooms) {
      if (floor != null) room.finishIncludeFloor = floor;
      if (walls != null) room.finishIncludeWalls = walls;
      if (ceiling != null) room.finishIncludeCeiling = ceiling;
      if (room.id != null) {
        await repo.updateRoom(room);
      }
    }
    if (mounted) await _load(showSpinner: false);
  }

  Future<void> _openMaterials() async {
    final scope = FinishVedomostScopeX.fromProjectTab(_tabs.index);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinishMaterialsScreen(
          projectId: widget.projectId,
          scope: scope,
        ),
      ),
    );
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (mounted) await _load(showSpinner: false);
  }

  Future<void> _addExtraWork() async {
    final template = await showModalBottomSheet<FinishWorkTemplate>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final templates = _extra.allTemplates;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Шаблон или пустая работа',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('С нуля'),
                onTap: () => Navigator.pop(
                  ctx,
                  FinishWorkTemplate(
                    id: 'blank',
                    title: 'Новая работа',
                    unit: FinishWorkUnit.m2,
                    defaultWastePercent: 0,
                    measureKind: FinishMeasureKind.area,
                  ),
                ),
              ),
              const Divider(height: 1),
              for (final t in templates)
                ListTile(
                  title: Text(t.title),
                  subtitle: Text('${t.category} · ${t.unit.labelRu}'),
                  onTap: () => Navigator.pop(ctx, t),
                ),
            ],
          ),
        );
      },
    );
    if (template == null || !mounted) return;

    final draft = template.id == 'blank'
        ? FinishExtraWork(
            id: newFinishWorkId(),
            title: '',
            qtyMode: FinishWorkQtyMode.manual,
            sortIndex: _extra.projectWorks().length,
          )
        : template.toWork(sortIndex: _extra.projectWorks().length);

    final edited = await showDialog<FinishExtraWork>(
      context: context,
      builder: (ctx) => _FinishExtraWorkEditor(initial: draft),
    );
    if (edited == null || !mounted) return;
    setState(() {
      _extra = FinishExtraWorksState(
        works: [..._extra.works, edited],
        templates: _extra.templates,
      );
    });
    await _persistExtra();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final project = _project;
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Сводка объекта')),
        body: Center(child: Text(_error ?? 'Нет данных')),
      );
    }

    return ScreenScaffold(
      backgroundBlur: 0.5,
      dimOpacity: 0.58,
      appBar: AppBar(
        title: Text('${project.name} · сводка'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          tabs: const [
            Tab(text: 'Обзор'),
            Tab(text: 'Стены'),
            Tab(text: 'Пол'),
            Tab(text: 'Потолок'),
            Tab(text: 'Другие работы'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'План объекта',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MasterPlanScreen(projectId: widget.projectId),
                ),
              );
              if (mounted) await _load(showSpinner: false);
            },
            icon: const Icon(Icons.apartment_outlined),
          ),
          if (AppScope.of(context).user.effectiveRole.canFinishVedomost)
            TextButton(
              onPressed: _openMaterials,
              child: const Text('Ведомость'),
            ),
        ],
      ),
      floatingActionButton: _showExtraFab
          ? FloatingActionButton.extended(
              onPressed: _addExtraWork,
              icon: const Icon(Icons.add),
              label: const Text('Работа'),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(
            onApplyLayerPrices: _applyLayerPricesToAll,
            project: project,
            rooms: _layoutRooms,
            allRooms: project.rooms,
            onOpenRoom: (r) => _openRoom(r),
            onOpenMaterials: _openMaterials,
            onSetIncludes: _setProjectFinishIncludes,
          ),
          _SectionRoomsTab(
            project: project,
            rooms: _layoutRooms,
            section: 'Стены',
            emptyHint: 'Нет комнат с чертежом — стены считаются по контуру',
            onOpenRoom: (r) => _openRoom(r, tab: 1),
            onReload: () => _load(showSpinner: false),
          ),
          _SectionRoomsTab(
            project: project,
            rooms: _layoutRooms,
            section: 'Пол',
            emptyHint: 'Нет комнат с чертежом',
            onOpenRoom: (r) => _openRoom(r, tab: 2),
            onReload: () => _load(showSpinner: false),
          ),
          _SectionRoomsTab(
            project: project,
            rooms: _layoutRooms,
            section: 'Потолок',
            emptyHint: 'Нет комнат с чертежом',
            onOpenRoom: (r) => _openRoom(r, tab: 3),
            onReload: () => _load(showSpinner: false),
          ),
          _OtherWorksTab(
            state: _extra,
            onChanged: (next) async {
              setState(() => _extra = next);
              await _persistExtra();
            },
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.project,
    required this.rooms,
    required this.allRooms,
    required this.onOpenRoom,
    required this.onOpenMaterials,
    required this.onSetIncludes,
    required this.onApplyLayerPrices,
  });

  final Project project;
  final List<Room> rooms;
  final List<Room> allRooms;
  final ValueChanged<Room> onOpenRoom;
  final VoidCallback onOpenMaterials;
  final Future<void> Function({bool? floor, bool? walls, bool? ceiling})
      onSetIncludes;
  final VoidCallback onApplyLayerPrices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var floor = 0.0;
    var walls = 0.0;
    var ceiling = 0.0;
    var perimeter = 0.0;
    var openings = 0.0;
    final heights = <double>{};
    for (final room in rooms) {
      final areas = resolveRoomFinishAreas(room);
      floor += areas.floorM2;
      walls += areas.wallsM2;
      ceiling += areas.ceilingM2;
      if (!areas.fromSpecial && room.hasLayout) {
        perimeter += FinishCalculator.perimeterM(room.walls);
        openings += room.openings
            .map(RoomOpening.fromJson)
            .fold<double>(0, (a, o) => a + o.effectiveAreaM2(room.walls));
      }
      if (!areas.fromSpecial) heights.add(room.ceilingHeightCm);
    }
    final extra = FinishExtraWorksState.fromJson(project.finishExtraWorksJson);
    final extraCount = extra.projectWorks().length;
    final heightLabel = heights.length == 1
        ? '${(heights.first / 100).toStringAsFixed(heights.first % 100 == 0 ? 0 : 2)} м'
        : 'разная';
    final money = finishScopePriceTotals(rooms);
    final moneyTotal = money.floor + money.walls + money.ceiling;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('По объекту', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('Помещений со схемой', '${rooms.length}'),
                _kv('Пол', '${floor.toStringAsFixed(2)} м²'),
                _kv('Потолок', '${ceiling.toStringAsFixed(2)} м²'),
                _kv('Периметр стен', '${perimeter.toStringAsFixed(2)} м'),
                _kv('Высота стен', heightLabel),
                _kv('Стены', '${walls.toStringAsFixed(2)} м²'),
                if (openings > 0.005)
                  _kv('Проёмы (вычтены)', '${openings.toStringAsFixed(2)} м²'),
                _kv('Другие работы', '$extraCount поз.'),
                if (moneyTotal > 0 &&
                    AppScope.of(context).user.effectiveRole.canPricing) ...[
                  const Divider(height: 20),
                  Text(
                    'Работы по расценкам слоёв',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  if (money.floor > 0) _kv('Пол', formatRub(money.floor)),
                  if (money.walls > 0) _kv('Стены', formatRub(money.walls)),
                  if (money.ceiling > 0) _kv('Потолок', formatRub(money.ceiling)),
                  _kv('Итого работы', formatRub(moneyTotal)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (allRooms.isNotEmpty) ...[
          _ProjectScopeIncludesCard(
            allRooms: allRooms,
            onSetIncludes: onSetIncludes,
          ),
          const SizedBox(height: 12),
        ],
        if (AppScope.of(context).user.effectiveRole.canFinishVedomost) ...[
          FilledButton.tonalIcon(
            onPressed: onOpenMaterials,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Ведомость отделки объекта'),
          ),
          const SizedBox(height: 8),
        ],
        if (AppScope.of(context).user.effectiveRole.canPricing) ...[
          OutlinedButton.icon(
            onPressed: rooms.isEmpty ? null : onApplyLayerPrices,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Цены слоёв для всех помещений'),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        Text('Помещения', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (rooms.isEmpty)
          Text(
            'Добавьте комнаты и контуры — сводка посчитает площади автоматически.',
            style: theme.textTheme.bodySmall,
          )
        else
          _RoomTilesGrid(
            rooms: rooms,
            floors: project.floors,
            onOpenRoom: onOpenRoom,
          ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(k)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Compact expandable project-level floor/walls/ceiling include toggles.
class _ProjectScopeIncludesCard extends StatefulWidget {
  const _ProjectScopeIncludesCard({
    required this.allRooms,
    required this.onSetIncludes,
  });

  final List<Room> allRooms;
  final Future<void> Function({bool? floor, bool? walls, bool? ceiling})
      onSetIncludes;

  @override
  State<_ProjectScopeIncludesCard> createState() =>
      _ProjectScopeIncludesCardState();
}

class _ProjectScopeIncludesCardState extends State<_ProjectScopeIncludesCard> {
  bool _expanded = false;

  String _hint(bool Function(Room) included) {
    final rooms = widget.allRooms;
    final on = rooms.where(included).length;
    final off = rooms.length - on;
    if (off == 0) return 'все вкл.';
    if (on == 0) return 'все выкл.';
    return 'выкл. в $off';
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.allRooms;
    // ON unless every room has the section off (mixed stays ON).
    final floorOn = rooms.any((r) => r.finishIncludeFloor);
    final wallsOn = rooms.any((r) => r.finishIncludeWalls);
    final ceilingOn = rooms.any((r) => r.finishIncludeCeiling);
    final summary =
        'Пол ${_hint((r) => r.finishIncludeFloor)} · '
        'стены ${_hint((r) => r.finishIncludeWalls)} · '
        'потолок ${_hint((r) => r.finishIncludeCeiling)}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.tune, size: 22),
            title: const Text('Состав расчёта'),
            subtitle: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              title: const Text('Пол'),
              subtitle: Text(_hint((r) => r.finishIncludeFloor)),
              value: floorOn,
              onChanged: (v) => widget.onSetIncludes(floor: v),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Стены'),
              subtitle: Text(_hint((r) => r.finishIncludeWalls)),
              value: wallsOn,
              onChanged: (v) => widget.onSetIncludes(walls: v),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Потолок'),
              subtitle: Text(_hint((r) => r.finishIncludeCeiling)),
              value: ceilingOn,
              onChanged: (v) => widget.onSetIncludes(ceiling: v),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionRoomsTab extends StatelessWidget {
  const _SectionRoomsTab({
    required this.project,
    required this.rooms,
    required this.section,
    required this.emptyHint,
    required this.onOpenRoom,
    required this.onReload,
  });

  final Project project;
  final List<Room> rooms;
  final String section;
  final String emptyHint;
  final ValueChanged<Room> onOpenRoom;
  final Future<void> Function() onReload;

  Future<void> _bulkEdit(BuildContext context) async {
    if (rooms.isEmpty) return;
    final bool applied;
    if (section == 'Пол') {
      applied = await showBulkFloorEditor(context, rooms: rooms);
    } else if (section == 'Стены') {
      applied = await showBulkWallsEditor(context, rooms: rooms);
    } else if (section == 'Потолок') {
      applied = await showBulkCeilingEditor(
        context,
        project: project,
        rooms: rooms,
      );
    } else {
      applied = false;
    }
    if (!context.mounted) return;
    if (applied) await onReload();
  }

  String? _coverageHint() {
    final ({int ready, int total}) cov;
    final String label;
    if (section == 'Стены') {
      cov = wallLayersCoverage(rooms);
      label = 'Слои стен';
    } else if (section == 'Пол') {
      cov = floorPrepCoverage(rooms);
      label = 'Подготовка пола';
    } else if (section == 'Потолок') {
      cov = ceilingPrepCoverage(rooms);
      label = 'Подготовка потолка';
    } else {
      return null;
    }
    if (cov.total == 0) return null;
    if (cov.ready == cov.total) {
      return '$label: во всех ${cov.total} помещ.';
    }
    if (cov.ready == 0) return '$label: не заданы (0 из ${cov.total})';
    return '$label: ${cov.ready} из ${cov.total} помещ.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onSurface;
    // Always recompute from current [project] — parent reloads after bulk/room edits.
    final agg = aggregateFinishVedomostLines(project)
        .where((l) => l.section == section)
        .toList();
    final coverage = _coverageHint();
    final coverageComplete = coverage != null && coverage.contains('во всех');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('Итого по объекту · $section', style: theme.textTheme.titleMedium),
        if (coverage != null) ...[
          const SizedBox(height: 6),
          Text(
            coverage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: coverageComplete
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (agg.isEmpty)
          Text(emptyHint, style: theme.textTheme.bodySmall)
        else
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < agg.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: on.withValues(alpha: 0.08)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            agg[i].name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: on,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${agg[i].quantity} ${agg[i].unit}'.trim(),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: on,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: rooms.isEmpty ? null : () => _bulkEdit(context),
          icon: const Icon(Icons.tune),
          label: Text('Задать «$section» для всех помещений'),
        ),
        const SizedBox(height: 20),
        Text('Помещения', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (rooms.isEmpty)
          Text('Нет помещений с чертежом', style: theme.textTheme.bodySmall)
        else
          _RoomTilesGrid(
            rooms: rooms,
            floors: project.floors,
            onOpenRoom: onOpenRoom,
            subtitleFor: (room) {
              final bits = buildFinishVedomostLines(room, project: project)
                  .where((l) => l.section == section)
                  .map((l) => '${l.name}: ${l.quantity} ${l.unit}'.trim())
                  .take(2)
                  .toList();
              if (bits.isNotEmpty) return bits.join('\n');
              // ЛК / объём: не показывать «0.0 м²» с пустого контура.
              if (room.isSpecialSpace) {
                return room.specialSpace?.kindLabelRu ?? 'Особое';
              }
              return '${MaterialsCalculator.roomAreaM2(room.walls).toStringAsFixed(1)} м²';
            },
          ),
      ],
    );
  }
}

/// Compact 3-up room tiles with frosted fill (overview + section tabs).
class _RoomTilesGrid extends StatelessWidget {
  const _RoomTilesGrid({
    required this.rooms,
    required this.onOpenRoom,
    this.floors = const [],
    this.subtitleFor,
  });

  final List<Room> rooms;
  final List<ProjectFloor> floors;
  final ValueChanged<Room> onOpenRoom;
  final String Function(Room room)? subtitleFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onSurface;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rooms.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (context, index) {
        final room = rooms[index];
        final areaOrExtra = subtitleFor?.call(room) ??
            (room.isSpecialSpace
                ? (room.specialSpace?.kindLabelRu ?? 'Особое')
                : '${MaterialsCalculator.roomAreaM2(room.walls).toStringAsFixed(1)} м²');
        final subtitle = areaOrExtra;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onOpenRoom(room),
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.surface.withValues(alpha: 0.42),
                border: Border.all(color: on.withValues(alpha: 0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomNameWithFloor(room: room, floors: floors),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on,
                        height: 1.15,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: on.withValues(alpha: 0.85),
                          height: 1.2,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OtherWorksTab extends StatelessWidget {
  const _OtherWorksTab({
    required this.state,
    required this.onChanged,
  });

  final FinishExtraWorksState state;
  final ValueChanged<FinishExtraWorksState> onChanged;

  Future<void> _edit(BuildContext context, FinishExtraWork work) async {
    final edited = await showDialog<FinishExtraWork>(
      context: context,
      builder: (ctx) => _FinishExtraWorkEditor(initial: work),
    );
    if (edited == null) return;
    final works =
        state.works.map((w) => w.id == work.id ? edited : w).toList();
    onChanged(FinishExtraWorksState(works: works, templates: state.templates));
  }

  void _delete(FinishExtraWork work) {
    final works = state.works.where((w) => w.id != work.id).toList();
    onChanged(FinishExtraWorksState(works: works, templates: state.templates));
  }

  void _duplicate(FinishExtraWork work) {
    final copy = work.copyWith(
      id: newFinishWorkId(),
      title: '${work.title} (копия)',
      sortIndex: state.projectWorks().length,
    );
    onChanged(
      FinishExtraWorksState(
        works: [...state.works, copy],
        templates: state.templates,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final works = state.projectWorks();
    var totalCost = 0.0;
    var hasCost = false;
    for (final w in works) {
      final t = w.lineTotal;
      if (t != null) {
        hasCost = true;
        totalCost += t;
      }
    }

    // No nested Scaffold — parent ScreenScaffold owns AppBar + FAB.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        Text(
          'Работы вне комнат: улица, перила, фасад и любые позиции '
          'с ручным количеством или измерением.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (works.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Text(
              'Пока пусто — добавьте работу из шаблона или с нуля.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          for (final w in works)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(w.title.isEmpty ? 'Без названия' : w.title),
                subtitle: Text(
                  [
                    w.category,
                    '${formatFinishWorkQty(w.quantityWithWaste, w.unit)} ${w.unit.labelRu}',
                    if (w.wastePercent > 0)
                      'запас ${w.wastePercent.toStringAsFixed(0)}%',
                    if (w.lineTotal != null)
                      formatRub(w.lineTotal!),
                  ].join(' · '),
                ),
                isThreeLine: true,
                onTap: () => _edit(context, w),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'dup') _duplicate(w);
                    if (v == 'del') _delete(w);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'dup', child: Text('Дублировать')),
                    PopupMenuItem(value: 'del', child: Text('Удалить')),
                  ],
                ),
              ),
            ),
        if (hasCost) ...[
          const SizedBox(height: 8),
          Text(
            'Сумма по ценам строк: ${formatRub(totalCost)}',
            style: theme.textTheme.titleSmall,
          ),
        ],
      ],
    );
  }
}

/// Owns TextEditingControllers so they are disposed with the dialog State,
/// not immediately after showDialog returns (which caused red-screen crashes).
class _FinishExtraWorkEditor extends StatefulWidget {
  const _FinishExtraWorkEditor({required this.initial});

  final FinishExtraWork initial;

  @override
  State<_FinishExtraWorkEditor> createState() => _FinishExtraWorkEditorState();
}

class _FinishExtraWorkEditorState extends State<_FinishExtraWorkEditor> {
  late FinishExtraWork _draft;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _materialCtrl;
  late final TextEditingController _manualCtrl;
  late final TextEditingController _wasteCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _lenCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _countCtrl;
  late final TextEditingController _normCtrl;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _titleCtrl = TextEditingController(text: _draft.title);
    _notesCtrl = TextEditingController(text: _draft.notes);
    _materialCtrl =
        TextEditingController(text: _draft.materialLabel ?? '');
    _manualCtrl = TextEditingController(
      text: _draft.manualQty == 0 ? '' : _draft.manualQty.toString(),
    );
    _wasteCtrl = TextEditingController(
      text: _draft.wastePercent == 0 ? '' : _draft.wastePercent.toString(),
    );
    _priceCtrl = TextEditingController(
      text: _draft.unitPrice?.toString() ?? '',
    );
    _lenCtrl = TextEditingController(
      text: _draft.measure.lengthM == 0
          ? ''
          : _draft.measure.lengthM.toString(),
    );
    _widthCtrl = TextEditingController(
      text: _draft.measure.widthM == 0
          ? ''
          : _draft.measure.widthM.toString(),
    );
    _heightCtrl = TextEditingController(
      text: _draft.measure.heightM == 0
          ? ''
          : _draft.measure.heightM.toString(),
    );
    _countCtrl = TextEditingController(
      text: _draft.measure.count == 0 ? '' : _draft.measure.count.toString(),
    );
    _normCtrl = TextEditingController(
      text: _draft.measure.normPerPiece == 1
          ? '1'
          : _draft.measure.normPerPiece.toString(),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _materialCtrl.dispose();
    _manualCtrl.dispose();
    _wasteCtrl.dispose();
    _priceCtrl.dispose();
    _lenCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _countCtrl.dispose();
    _normCtrl.dispose();
    super.dispose();
  }

  double _parse(String raw, [double fallback = 0]) =>
      double.tryParse(raw.replaceAll(',', '.')) ?? fallback;

  void _syncFields() {
    _draft = _draft.copyWith(
      title: _titleCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      materialLabel: _materialCtrl.text.trim().isEmpty
          ? null
          : _materialCtrl.text.trim(),
      manualQty: _parse(_manualCtrl.text),
      wastePercent: _parse(_wasteCtrl.text),
      unitPrice: double.tryParse(_priceCtrl.text.replaceAll(',', '.')),
      measure: _draft.measure.copyWith(
        lengthM: _parse(_lenCtrl.text),
        widthM: _parse(_widthCtrl.text),
        heightM: _parse(_heightCtrl.text),
        count: _parse(_countCtrl.text),
        normPerPiece: _parse(_normCtrl.text, 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Работа'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: finishWorkCategoryPresets.contains(_draft.category)
                    ? _draft.category
                    : 'прочее',
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in finishWorkCategoryPresets)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _draft = _draft.copyWith(category: v));
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<FinishWorkUnit>(
                // ignore: deprecated_member_use
                value: _draft.unit,
                decoration: const InputDecoration(
                  labelText: 'Единица',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final u in FinishWorkUnit.values)
                    DropdownMenuItem(value: u, child: Text(u.labelRu)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _draft = _draft.copyWith(unit: v));
                },
              ),
              const SizedBox(height: 10),
              SegmentedButton<FinishWorkQtyMode>(
                segments: const [
                  ButtonSegment(
                    value: FinishWorkQtyMode.manual,
                    label: Text('Вручную'),
                  ),
                  ButtonSegment(
                    value: FinishWorkQtyMode.measure,
                    label: Text('Измерение'),
                  ),
                ],
                selected: {_draft.qtyMode},
                onSelectionChanged: (s) {
                  setState(() => _draft = _draft.copyWith(qtyMode: s.first));
                },
              ),
              const SizedBox(height: 10),
              if (_draft.qtyMode == FinishWorkQtyMode.manual)
                TextField(
                  controller: _manualCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Количество ()',
                    border: const OutlineInputBorder(),
                  ),
                )
              else ...[
                DropdownButtonFormField<FinishMeasureKind>(
                  // ignore: deprecated_member_use
                  value: _draft.measure.kind == FinishMeasureKind.lengthHeight
                      ? FinishMeasureKind.area
                      : _draft.measure.kind,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Схема измерения',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: FinishMeasureKind.area,
                      child: Text('Площадь'),
                    ),
                    DropdownMenuItem(
                      value: FinishMeasureKind.length,
                      child: Text('Длина'),
                    ),
                    DropdownMenuItem(
                      value: FinishMeasureKind.countNorm,
                      child: Text('Кол. × норма'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    // Legacy lengthHeight → area (same L×secondDim product).
                    final kind = v == FinishMeasureKind.lengthHeight
                        ? FinishMeasureKind.area
                        : v;
                    setState(
                      () => _draft = _draft.copyWith(
                        measure: _draft.measure.copyWith(kind: kind),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                if (_draft.measure.kind == FinishMeasureKind.area ||
                    _draft.measure.kind == FinishMeasureKind.length ||
                    _draft.measure.kind == FinishMeasureKind.lengthHeight)
                  TextField(
                    controller: _lenCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Длина, м',
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (_draft.measure.kind == FinishMeasureKind.area ||
                    _draft.measure.kind == FinishMeasureKind.lengthHeight) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _widthCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Ширина, м',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_draft.measure.kind == FinishMeasureKind.countNorm) ...[
                  TextField(
                    controller: _countCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Количество',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _normCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Норма на 1 шт',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _wasteCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Запас, %',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Цена за ед. (необяз.)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _materialCtrl,
                decoration: const InputDecoration(
                  labelText: 'Материал / артикул (необяз.)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Заметка',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            _syncFields();
            var result = _draft;
            if (result.title.trim().isEmpty) {
              result = result.copyWith(title: 'Без названия');
            }
            Navigator.pop(context, result);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
