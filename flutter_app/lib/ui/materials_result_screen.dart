import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/ceiling_grid.dart';
import '../domain/finish_vedomost.dart';
import '../domain/cost_calculator.dart';
import '../domain/finish_model.dart';
import '../domain/materials_calculator.dart';
import '../domain/materials_formulas.dart';
import '../domain/models.dart';
import '../domain/documentation_model.dart';
import '../domain/primary_supplier.dart';
import '../domain/project_export.dart';
import '../domain/project_floors.dart';
import '../domain/project_materials.dart';
import '../domain/vedomost_export.dart';
import 'documentation_flow_screens.dart';
import 'layout_screen.dart';
import 'materials_flow_screens.dart';
import 'room_navigation.dart';
import 'widgets/floor_pager_chip.dart';

enum _OverrideConflictAction { overwriteAll, exceptOverrides }

class MaterialsResultScreen extends StatefulWidget {
  const MaterialsResultScreen({
    super.key,
    required this.projectId,
    this.roomId,
    this.calcMode = MaterialsCalcMode.ceiling,
  });

  final int projectId;
  final int? roomId;
  final MaterialsCalcMode calcMode;

  @override
  State<MaterialsResultScreen> createState() => _MaterialsResultScreenState();
}

class _MaterialsResultScreenState extends State<MaterialsResultScreen> {
  Project? _project;
  Room? _room;
  Map<String, int> _ceilingResult = {};
  List<FinishVedomostLine> _finishLines = [];
  Map<String, SupplierPrice>? _prices;
  bool _loading = true;
  bool _showFormulas = false;

  String _ceiling = 'Армстронг';
  String _susp = 'Подвес 0,5';
  String _cell = '50x50';
  bool _override = false;
  bool _scopeAllRooms = true;
  int? _scopedRoomId;
  ProjectFloor? _selectedFloor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    Room? room;
    if (project != null && widget.roomId != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    if (!mounted) return;
    Map<String, SupplierPrice>? prices;
    var pricesFailed = false;
    try {
      final doc = ProjectDocumentation.fromJson(project?.documentationJson);
      prices = await loadPrimarySupplierPrices(
        repo: AppScope.of(context).suppliers,
        doc: doc,
      );
    } catch (_) {
      pricesFailed = true;
    }
    if (!mounted) return;
    setState(() {
      _prices = prices;
      _project = project;
      _room = room;
      if (project != null) {
        final pages = floorsForPager(project.floors);
        if (projectHasExplicitFloors(project.floors) && pages.isNotEmpty) {
          _selectedFloor ??= pages.first;
        } else {
          _selectedFloor = null;
        }
      }
      if (project != null && widget.roomId == null) {
        _scopeAllRooms = true;
        _scopedRoomId = null;
      }
      if (room != null && project != null) {
        final cfg = roomEffectiveConfig(room, project);
        _ceiling = cfg.$1;
        _susp = cfg.$2;
        _cell = cfg.$3;
        _override = room.materialsOverride;
      } else if (project != null) {
        _ceiling = project.materialsCeiling ?? 'Армстронг';
        _susp = project.materialsSusp ?? 'Подвес 0,5';
        _cell = project.materialsCell ?? '50x50';
      }
      _recalc();
      _loading = false;
    });
    if (pricesFailed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Цены поставщика не загрузились — суммы без каталога')),
      );
    }
  }

  bool get _isProjectLevel => widget.roomId == null;

  bool get _isAllRoomsScope => _isProjectLevel && _scopeAllRooms;

  Room? get _scopedRoom {
    if (!_isProjectLevel || _scopeAllRooms || _scopedRoomId == null) return null;
    for (final r in _project?.rooms ?? const <Room>[]) {
      if (r.id == _scopedRoomId) return r;
    }
    return null;
  }

  Room? get _activeRoom => _room ?? _scopedRoom;

  Iterable<Room> get _selectableRooms {
    final project = _project;
    if (project == null) return const [];
    final base = roomsForPagerFloor(
      rooms: project.rooms,
      floors: project.floors,
      selected: _selectedFloor,
      // Show ЛК on every overlapping floor page (same room id — not multiplied
      // when aggregating ids). Full shaft areas; not a per-floor slice.
      includeSpanningStairwells: true,
    );
    return base.where((r) => r.id != null);
  }

  List<int> get _allRoomIds => [
        for (final r in _selectableRooms) r.id!,
      ];

  bool get _anyRoomOverride =>
      _selectableRooms.any((r) => r.materialsOverride);

  void _loadProjectConfig() {
    final project = _project;
    if (project == null) return;
    _ceiling = project.materialsCeiling ?? 'Армстронг';
    _susp = project.materialsSusp ?? 'Подвес 0,5';
    _cell = project.materialsCell ?? '50x50';
    _override = false;
  }

  void _loadRoomConfig(Room room) {
    final project = _project;
    if (project == null) return;
    final cfg = roomEffectiveConfig(room, project);
    _ceiling = cfg.$1;
    _susp = cfg.$2;
    _cell = cfg.$3;
    _override = room.materialsOverride;
  }

  void _recalc() {
    final project = _project;
    if (project == null) {
      _ceilingResult = {};
      _finishLines = [];
      return;
    }
    final ui = MaterialsUiConfig(ceiling: _ceiling, susp: _susp, cell: _cell);
    final activeRoom = _activeRoom;
    final finishMode = widget.calcMode == MaterialsCalcMode.finish;

    if (activeRoom != null) {
      activeRoom
        ..materialsOverride = _override
        ..materialsCeiling = _ceiling
        ..materialsSusp = _susp
        ..materialsCell = _cell;
      _ceilingResult = calculateRoomMaterials(
        activeRoom,
        project,
        ui: _override ? null : ui,
      );
      _finishLines = finishMode
          ? buildFinishVedomostLines(activeRoom, project: project)
          : [];
      return;
    }

    project
      ..materialsCeiling = _ceiling
      ..materialsSusp = _susp
      ..materialsCell = _cell;
    final (totals, _, _) = aggregateCeilingTotals(
      project,
      roomIds: _allRoomIds,
      ui: ui,
    );
    _ceilingResult = totals;
    _finishLines = finishMode
        ? aggregateFinishVedomostLines(project, roomIds: _allRoomIds)
        : [];
  }

  Future<void> _saveConfig() async {
    final project = _project;
    if (project == null) return;
    final repo = AppScope.of(context).projects;
    final activeRoom = _activeRoom;
    if (activeRoom != null) {
      await repo.updateRoomMaterials(
        activeRoom.id!,
        override: _override,
        ceiling: _ceiling,
        susp: _susp,
        cell: _cell,
      );
      activeRoom
        ..materialsOverride = _override
        ..materialsCeiling = _ceiling
        ..materialsSusp = _susp
        ..materialsCell = _cell;
    } else {
      await repo.updateProjectMaterials(
        project.id!,
        ceiling: _ceiling,
        susp: _susp,
        cell: _cell,
      );
    }
  }

  Future<_OverrideConflictAction?> _askOverrideConflict(int count) {
    return showDialog<_OverrideConflictAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Индивидуальные настройки'),
        content: Text(
          'В $count ${_roomCountLabel(count)} заданы свои параметры потолка. '
          'Как применить новые настройки?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _OverrideConflictAction.exceptOverrides),
            child: const Text('Кроме индивидуальных'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _OverrideConflictAction.overwriteAll),
            child: const Text('Для всех'),
          ),
        ],
      ),
    );
  }

  String _roomCountLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'помещениях';
    if (mod10 == 1) return 'помещении';
    if (mod10 >= 2 && mod10 <= 4) return 'помещениях';
    return 'помещениях';
  }

  Future<void> _applyConfigChange(void Function() mutate) async {
    if (!_isAllRoomsScope) {
      setState(() {
        mutate();
        if (_activeRoom != null && !_override) {
          _override = true;
          _activeRoom!.materialsOverride = true;
        }
        _recalc();
      });
      await _saveConfig();
      return;
    }

    final overridden = _selectableRooms.where((r) => r.materialsOverride).toList();
    if (overridden.isNotEmpty) {
      final action = await _askOverrideConflict(overridden.length);
      if (!mounted || action == null) return;
      setState(() {
        mutate();
        _recalc();
      });
      if (action == _OverrideConflictAction.overwriteAll) {
        final repo = AppScope.of(context).projects;
        for (final room in overridden) {
          room.materialsOverride = false;
          if (room.id != null) {
            await repo.updateRoomMaterials(
              room.id!,
              override: false,
              ceiling: _ceiling,
              susp: _susp,
              cell: _cell,
            );
          }
        }
      }
      await _saveConfig();
      return;
    }

    setState(() {
      mutate();
      _recalc();
    });
    await _saveConfig();
  }

  Future<void> _copy() async {
    final buf = StringBuffer();
    for (final e
        in sortedMaterialEntries(_ceilingResult)) {
      buf.writeln('${e.key}: ${e.value}');
    }
    for (final f in _finishLines) {
      buf.writeln('${f.section} · ${f.name}: ${f.quantity} ${f.unit}'.trim());
    }
    final text = buf.toString();
    await Clipboard.setData(ClipboardData(text: text));
    await SharePlus.instance.share(ShareParams(text: text, subject: 'Материалы'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скопировано / поделиться')),
    );
  }

  Future<void> _shareVedomost({required String format}) async {
    final project = _project;
    final room = _room;
    if (project == null || room == null) {
      await _copy();
      return;
    }
    if (!room.hasLayout) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет закрытого чертежа — ведомость недоступна')),
      );
      return;
    }
    await _persistSilent();
    final doc = ProjectDocumentation.fromJson(project.documentationJson);
    final stamp = doc.stamp.withDefaults(projectName: project.name, roomName: room.name);
    final dir = await getTemporaryDirectory();
    final base = safeExportBasename('${project.name}_${room.name}_vedomost');
    late final File file;
    if (format == 'pdf') {
      final bytes = await buildVedomostPdf(
        project: project,
        room: room,
        stamp: stamp,
        prices: _prices,
      );
      file = File(p.join(dir.path, '$base.pdf'));
      await file.writeAsBytes(bytes);
    } else if (format == 'xlsx') {
      final bytes = buildVedomostXlsx(
        project: project,
        room: room,
        stamp: stamp,
        prices: _prices,
      );
      file = File(p.join(dir.path, '$base.xlsx'));
      await file.writeAsBytes(bytes);
    } else {
      final text = _prices != null && _prices!.isNotEmpty
          ? buildVedomostTextWithPricing(
              project: project,
              room: room,
              stamp: stamp,
              prices: _prices,
            )
          : buildVedomostText(project: project, room: room, stamp: stamp);
      file = File(p.join(dir.path, '$base.txt'));
      await file.writeAsString(text);
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'Ведомость · ${room.name}'),
    );
  }

  Future<void> _persistSilent() async {
    await _saveConfig();
  }

  /// Open ceiling layout for the active room, or pick a room when summing the project.
  Future<void> _openLayoutFromMaterials() async {
    await _persistSilent();
    if (!mounted) return;

    Future<void> pushLayout(int roomId) async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LayoutScreen(
            projectId: widget.projectId,
            roomId: roomId,
          ),
        ),
      );
      if (mounted) await _load();
    }

    final active = _activeRoom;
    if (active?.id != null) {
      if (!active!.hasLayout) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У помещения нет чертежа')),
        );
        return;
      }
      await pushLayout(active.id!);
      return;
    }

    final rooms =
        _selectableRooms.where((r) => r.hasLayout && r.id != null).toList();
    if (rooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет помещений с чертежом')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Room>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Выберите помещение для раскладки',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              for (final room in rooms)
                ListTile(
                  title: Text(room.name),
                  subtitle: Text(
                    'S=${MaterialsCalculator.roomAreaM2(room.walls).toStringAsFixed(1)} м²',
                  ),
                  onTap: () => Navigator.pop(ctx, room),
                ),
            ],
          ),
        );
      },
    );
    if (picked?.id == null || !mounted) return;
    await pushLayout(picked!.id!);
  }

  String? _skuHint(String name) {
    final prices = _prices;
    if (prices == null) return null;
    for (final e in prices.entries) {
      if (name.toLowerCase().contains(e.key.toLowerCase()) ||
          e.key.toLowerCase().contains(name.toLowerCase())) {
        final sku = e.value.supplierSku;
        if (sku.isNotEmpty) return sku;
      }
    }
    return null;
  }

  String _layoutCellsOnPlan() {
    final room = _activeRoom;
    if (room == null || !room.hasLayout) return '—';
    final grid = CeilingGrid(
      offsetXCm: room.gridOffsetX.toDouble(),
      offsetYCm: room.gridOffsetY.toDouble(),
    );
    final lights = <String>{};
    for (final f in room.lightFixtures) {
      if (f.length >= 2) lights.add('${f[0]}:${f[1]}');
    }
    grid.rebuild(
      roomPoints: pointsFromWalls(room.walls),
      walls: room.walls,
      lightIds: lights,
    );
    final (full, cut) = grid.effectiveTileCounts;
    return '$full + $cut';
  }

  String get _scopeLabel {
    if (_isAllRoomsScope) return 'Все помещения';
    final room = _scopedRoom;
    return room?.name ?? 'Помещение';
  }

  void _selectRoomScope({required bool allRooms, int? roomId}) {
    setState(() {
      _scopeAllRooms = allRooms;
      _scopedRoomId = roomId;
      if (allRooms) {
        _loadProjectConfig();
      } else if (roomId != null) {
        final room = _scopedRoom;
        if (room != null) _loadRoomConfig(room);
      }
      _recalc();
    });
  }

  Future<void> _openRoomScopePicker() async {
    final rooms = _selectableRooms.toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Выбор помещений',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.apartment,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: const Text('Все помещения'),
                  subtitle: _anyRoomOverride
                      ? const Text('Есть помещения с индивидуальными настройками')
                      : Text('Сумма по ${rooms.length} помещ.'),
                  trailing: _isAllRoomsScope
                      ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                      : null,
                  selected: _isAllRoomsScope,
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectRoomScope(allRooms: true);
                  },
                ),
                const Divider(height: 1),
                for (final room in rooms)
                  Builder(
                    builder: (_) {
                      final selected =
                          !_isAllRoomsScope && _scopedRoomId == room.id;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            room.name.isNotEmpty
                                ? room.name[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(room.name),
                        subtitle: Text(
                          room.materialsOverride
                              ? 'Индивидуальные настройки потолка'
                              : room.hasLayout
                                  ? 'S=${MaterialsCalculator.roomAreaM2(room.walls).toStringAsFixed(1)} м²'
                                  : 'Нет чертежа',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (room.materialsOverride)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.tune,
                                  size: 18,
                                  color: theme.colorScheme.tertiary,
                                ),
                              ),
                            if (selected)
                              Icon(
                                Icons.check_circle,
                                color: theme.colorScheme.primary,
                              ),
                          ],
                        ),
                        selected: selected,
                        onTap: () {
                          if (room.id == null) return;
                          Navigator.pop(ctx);
                          _selectRoomScope(allRooms: false, roomId: room.id);
                        },
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRoomScopeButton() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        onPressed: _openRoomScopePicker,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child: Row(
          children: [
            Badge(
              isLabelVisible: _isAllRoomsScope && _anyRoomOverride,
              smallSize: 8,
              child: const Icon(Icons.meeting_room_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Выбор помещений',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _scopeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _selectedProjectAreaM2() {
    final project = _project;
    if (project == null) return 0;
    var area = 0.0;
    for (final room in project.rooms) {
      if (!room.hasLayout) continue;
      if (!_isAllRoomsScope && room.id != _scopedRoomId) continue;
      area += MaterialsCalculator.roomAreaM2(room.walls);
    }
    return area;
  }

  double _selectedProjectPerimeterM() {
    final project = _project;
    if (project == null) return 0;
    var peri = 0.0;
    for (final room in project.rooms) {
      if (!room.hasLayout) continue;
      if (!_isAllRoomsScope && room.id != _scopedRoomId) continue;
      peri += MaterialsCalculator.roomPerimeterCm(room.walls) / 100;
    }
    return peri;
  }

  Widget _buildCeilingResults() {
    if (_ceilingResult.isEmpty) {
      return const Text('Нет данных — нарисуйте стены комнаты');
    }
    return Column(
      children: sortedMaterialEntries(_ceilingResult)
          .map(
        (e) {
          final sku = _skuHint(e.key);
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(e.key),
            subtitle: sku != null ? Text('SKU $sku') : null,
            trailing: Text(
              '${e.value}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          );
        },
      ).toList(),
    );
  }

  Widget _buildFinishResults() {
    if (_finishLines.isEmpty) {
      return const SizedBox.shrink();
    }
    final bySection = <String, List<FinishVedomostLine>>{};
    for (final line in _finishLines) {
      bySection.putIfAbsent(line.section, () => []).add(line);
    }
    final sections = bySection.keys.toList();
    const order = ['Пол', 'Потолок', 'Стены', 'Расходники', 'Другие работы'];
    sections.sort((a, b) {
      final ai = order.indexOf(a);
      final bi = order.indexOf(b);
      final ao = ai < 0 ? order.length : ai;
      final bo = bi < 0 ? order.length : bi;
      if (ao != bo) return ao.compareTo(bo);
      return a.compareTo(b);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(section, style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final f in bySection[section]!)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(f.name),
              trailing: Text(
                '${f.quantity} ${f.unit}'.trim(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final title = _activeRoom?.name ?? _project?.name ?? 'Материалы';
    final needsCell = _ceiling == 'Грильято' || _ceiling == 'GL';
    final isProjectLevel = _isProjectLevel;
    final finishMode = widget.calcMode == MaterialsCalcMode.finish;
    final showRoomScope = isProjectLevel;
    final showOverrideSwitch = _activeRoom != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _persistSilent();
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: isProjectLevel
            ? PreferredSize(
                preferredSize: Size.fromHeight(
                  projectHasExplicitFloors(_project?.floors ?? const [])
                      ? 72
                      : 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (projectHasExplicitFloors(_project?.floors ?? const []))
                      FloorPagerChip(
                        floors: _project!.floors,
                        selected: _selectedFloor,
                        onSelected: (f) => setState(() {
                          _selectedFloor = f;
                          _recalc();
                        }),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          finishMode
                              ? (_isAllRoomsScope
                                  ? 'Материалы отделки · по этажу/объекту'
                                  : 'Материалы отделки · помещение')
                              : (_isAllRoomsScope
                                  ? 'Материалы потолка · по этажу/объекту'
                                  : 'Материалы потолка · помещение'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : null,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _persistSilent();
            if (mounted) Navigator.of(context).pop();
          },
        ),
        actions: [
          if (_room != null)
            TextButton(
              onPressed: () async {
                await _persistSilent();
                if (!mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DocumentationVedomostScreen(
                      projectId: widget.projectId,
                      roomId: widget.roomId!,
                    ),
                  ),
                );
              },
              child: const Text('Ведомость'),
            ),
          if (_room != null)
            TextButton(
              onPressed: () async {
                await _persistSilent();
                if (!mounted) return;
                await openRoomModule(
                  context,
                  projectId: widget.projectId,
                  roomId: widget.roomId!,
                  module: AppModule.documentation,
                );
              },
              child: const Text('Документ'),
            ),
          if (widget.calcMode == MaterialsCalcMode.ceiling)
            TextButton(
              onPressed: _openLayoutFromMaterials,
              child: const Text('Раскладка'),
            ),
          PopupMenuButton<String>(
            tooltip: 'Поделиться',
            icon: const Icon(Icons.share),
            onSelected: (v) {
              if (v == 'bom') {
                _copy();
              } else {
                _shareVedomost(format: v);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'bom', child: Text('BOM · текст')),
              if (_room != null) ...[
                const PopupMenuItem(value: 'pdf', child: Text('Ведомость · PDF')),
                const PopupMenuItem(value: 'xlsx', child: Text('Ведомость · Excel')),
                const PopupMenuItem(value: 'txt', child: Text('Ведомость · текст')),
              ],
            ],
          ),
          IconButton(
            tooltip: 'Сохранить настройки',
            onPressed: () async {
              await _saveConfig();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Настройки сохранены')),
                );
              }
            },
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (showRoomScope) _buildRoomScopeButton(),
          if (showOverrideSwitch)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Индивидуальная конфигурация'),
              subtitle: const Text('Отличается от настроек объекта'),
              value: _override,
              onChanged: (v) => _applyConfigChange(() {
                _override = v;
              }),
            ),
          Text('Тип потолка', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'Армстронг', label: Text('Армстронг')),
              ButtonSegment(value: 'Грильято', label: Text('Грильято')),
              ButtonSegment(value: 'GL', label: Text('GL')),
            ],
            selected: {_ceiling},
            onSelectionChanged: (s) => _applyConfigChange(() {
              _ceiling = s.first;
              _susp = 'Подвес 0,5';
              _cell = '50x50';
            }),
          ),
          const SizedBox(height: 12),
          Text('Подвес', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'Подвес 0,5', label: Text('0,5')),
              ButtonSegment(value: 'Подвес 1', label: Text('1')),
              ButtonSegment(value: 'Подвес 1,5', label: Text('1,5')),
            ],
            selected: {_susp},
            onSelectionChanged: (s) => _applyConfigChange(() => _susp = s.first),
          ),
          if (needsCell) ...[
            const SizedBox(height: 12),
            Text('Ячейка', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: '50x50', label: Text('50×50')),
                ButtonSegment(value: '75x75', label: Text('75×75')),
                ButtonSegment(value: '100x100', label: Text('100×100')),
              ],
              selected: {_cell},
              onSelectionChanged: (s) => _applyConfigChange(() => _cell = s.first),
            ),
          ],
          const SizedBox(height: 12),
          if (_activeRoom != null && _activeRoom!.hasLayout)
            Text(
              'Плиты: на плане ${_layoutCellsOnPlan()} · закупка ${ceilingPurchaseCount(_activeRoom!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Text(
            finishMode ? 'Потолок' : 'Результат',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildCeilingResults(),
          if (finishMode) ...[
            const SizedBox(height: 16),
            Text('Отделка', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _buildFinishResults(),
          ],
          TextButton(
            onPressed: () => setState(() => _showFormulas = !_showFormulas),
            child: Text(_showFormulas ? 'Скрыть пояснение' : 'Как считается'),
          ),
          if (_showFormulas) ...[
            const SizedBox(height: 8),
            SelectableText(
              materialsFormulasText(
                ceilingLabel: _ceiling,
                areaM2: _activeRoom != null
                    ? (_activeRoom!.hasLayout
                        ? MaterialsCalculator.roomAreaM2(_activeRoom!.walls)
                        : 0)
                    : _selectedProjectAreaM2(),
                perimeterM: _activeRoom != null
                    ? (_activeRoom!.hasLayout
                        ? MaterialsCalculator.roomPerimeterCm(_activeRoom!.walls) / 100
                        : 0)
                    : _selectedProjectPerimeterM(),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      ),
    );
  }
}
