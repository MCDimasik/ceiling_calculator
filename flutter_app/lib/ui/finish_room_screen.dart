import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/project_repository.dart';
import '../domain/ceiling_grid.dart';
import '../domain/finish_model.dart';
import '../domain/finish_material_links.dart';
import '../domain/cost_calculator.dart';
import '../domain/documentation_model.dart';
import '../domain/finish_layer_pricing.dart';
import '../domain/finish_vedomost.dart';
import '../domain/finish_quantities.dart';
import '../domain/floor_covering.dart';
import '../domain/floor_layout.dart';
import '../domain/models.dart';
import '../domain/money_format.dart';
import '../domain/special_space.dart';
import '../domain/primary_supplier.dart';
import '../domain/project_materials.dart';
import '../domain/project_price_resolver.dart';
import '../domain/floor_layout_undo.dart';
import '../domain/opening_templates.dart';
import '../domain/room_finish_areas.dart';
import '../domain/surface_prep_layers.dart';
import '../domain/work_rates_catalog.dart';
import '../domain/wall_elevation_geometry.dart';
import 'finish_materials_screen.dart';
import 'room_navigation.dart';
import 'widgets/canvas_palette.dart';
import 'widgets/controls.dart';
import 'widgets/finish_painters.dart';
import 'widgets/layer_price_fields.dart';
import 'widgets/numeric_input.dart';
import 'widgets/opening_plan_placer.dart';
import 'widgets/screen_scaffold.dart';
import 'widgets/stair_schematic_painters.dart';

/// Finish module: height, openings, floor tiles, areas + isometric shell.
class FinishRoomScreen extends StatefulWidget {
  const FinishRoomScreen({
    super.key,
    required this.projectId,
    required this.roomId,
    this.initialTabIndex = 0,
    this.lockedTabIndex,
    this.editorTitle,
    this.specialLayersOnly = false,
  });

  final int projectId;
  final int roomId;

  /// 0 Обзор · 1 Стены · 2 Пол · 3 Потолок
  final int initialTabIndex;

  /// When set, shows only this tab as a full-screen section editor (no TabBar).
  final int? lockedTabIndex;

  /// AppBar title when [lockedTabIndex] is set.
  final String? editorTitle;

  /// Edit wall layers for ЛК / объём without redirecting to [SpecialSpaceScreen].
  final bool specialLayersOnly;

  bool get isSectionEditor => lockedTabIndex != null;

  @override
  State<FinishRoomScreen> createState() => _FinishRoomScreenState();
}

class _FinishRoomScreenState extends State<FinishRoomScreen> with WidgetsBindingObserver {
  Room? _room;
  Project? _project;
  Map<String, SupplierPrice>? _prices;
  ProjectRepository? _projects;
  bool _loading = true;
  final _heightCtrl = TextEditingController();
  final _tileWCtrl = TextEditingController();
  final _tileHCtrl = TextEditingController();
  final _screedDepthCtrl = TextEditingController();
  final _floorCoveringPriceCtrl = TextEditingController();
  final _ceilingSystemPriceCtrl = TextEditingController();
  Timer? _heightSaveTimer;
  final _wallGrid = CeilingGrid();

  final _wallTileUndo = FloorLayoutUndoStack();
  int _wallElevationIndex = 0;
  double _shellYaw = 0.4;
  double _shellPitch = 0.55;

  /// Opening type currently being placed on the 2D plan (`null` = view only).
  int? _placingIndex;
  bool _layersSectionExpanded = true;
  bool _openingsSectionExpanded = true;
  bool _floorPrepExpanded = true;
  bool _ceilingPrepExpanded = true;

  static const _ceilingOptions = ['Армстронг', 'Грильято', 'GL'];
  static const _suspOptions = ['Подвес 0,5', 'Подвес 1', 'Подвес 1,5'];
  static const _cellOptions = ['50x50', '75x75', '100x100'];

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _flushHeightPersist();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final pending = _heightSaveTimer != null;
    _heightSaveTimer?.cancel();
    _heightSaveTimer = null;
    if (pending) {
      final room = _room;
      final projects = _projects;
      if (room != null && projects != null) {
        _applyHeightFieldsToRoom(room);
        // ignore: discarded_futures
        projects.updateRoom(room);
      }
    }
    _heightCtrl.dispose();
    _tileWCtrl.dispose();
    _tileHCtrl.dispose();
    _screedDepthCtrl.dispose();
    _floorCoveringPriceCtrl.dispose();
    _ceilingSystemPriceCtrl.dispose();
    super.dispose();
  }

  void _applyHeightFieldsToRoom(Room room) {
    room.ceilingHeightCm =
        double.tryParse(_heightCtrl.text.replaceAll(',', '.')) ?? room.ceilingHeightCm;
    room.finishTileWidthCm =
        double.tryParse(_tileWCtrl.text.replaceAll(',', '.')) ?? room.finishTileWidthCm;
    room.finishTileHeightCm =
        double.tryParse(_tileHCtrl.text.replaceAll(',', '.')) ?? room.finishTileHeightCm;
    room.floorScreedDepthCm =
        double.tryParse(_screedDepthCtrl.text.replaceAll(',', '.')) ??
            room.floorScreedDepthCm;
    final floorPriceRaw = _floorCoveringPriceCtrl.text.trim();
    room.floorCoveringUnitPrice = floorPriceRaw.isEmpty
        ? null
        : double.tryParse(floorPriceRaw.replaceAll(',', '.'));
    final ceilPriceRaw = _ceilingSystemPriceCtrl.text.trim();
    room.ceilingSystemUnitPrice = ceilPriceRaw.isEmpty
        ? null
        : double.tryParse(ceilPriceRaw.replaceAll(',', '.'));
  }

  void _scheduleHeightPersist() {
    _heightSaveTimer?.cancel();
    _heightSaveTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _persist();
    });
  }

  void _flushHeightPersist() {
    if (_heightSaveTimer == null) return;
    _heightSaveTimer?.cancel();
    _heightSaveTimer = null;
    // ignore: discarded_futures
    _persist();
  }

  Future<void> _load() async {
    final projects = AppScope.of(context).projects;
    _projects = projects;
    final project = await projects.getProject(widget.projectId);
    Room? room;
    if (project != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
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
      _project = project;
      _room = room;
      _prices = prices;
      _loading = false;
      if (room != null) {
        _heightCtrl.text = room.ceilingHeightCm.round().toString();
        _tileWCtrl.text = room.finishTileWidthCm.round().toString();
        _tileHCtrl.text = room.finishTileHeightCm.round().toString();
        _screedDepthCtrl.text = (room.floorScreedDepthCm <= 0
                ? defaultScreedDepthCm
                : room.floorScreedDepthCm)
            .round()
            .toString();
        final fp = room.floorCoveringUnitPrice;
        _floorCoveringPriceCtrl.text =
            (fp != null && fp > 0) ? fp.toStringAsFixed(0) : '';
        final cp = room.ceilingSystemUnitPrice;
        _ceilingSystemPriceCtrl.text =
            (cp != null && cp > 0) ? cp.toStringAsFixed(0) : '';
        final tile = _firstTileLayer;
        if (tile != null) {
          _wallTileUndo.seed(FloorLayoutUndoSnapshot(
            offsetX: tile.tileOffsetX,
            offsetY: tile.tileOffsetY,
          ));
        }
        _rebuildWallGrid();
        // Drop orphan / cross-room shared-price marks left by older bulk copy.
        final wallIdsBefore = room.wallFinishLayers
            .map((e) => e['price_group_id'])
            .toList();
        final walls = room.wallFinishLayers.map(FinishLayer.fromJson).toList();
        sanitizeWallPriceGroups(walls, roomId: room.id);
        room.wallFinishLayers = walls.map((l) => l.toJson()).toList();
        final floorPrep =
            room.floorPrepLayers.map(SurfacePrepLayer.fromJson).toList();
        sanitizePrepPriceGroups(floorPrep, roomId: room.id);
        room.floorPrepLayers = floorPrep.map((l) => l.toJson()).toList();
        final ceilPrep =
            room.ceilingPrepLayers.map(SurfacePrepLayer.fromJson).toList();
        sanitizePrepPriceGroups(ceilPrep, roomId: room.id);
        room.ceilingPrepLayers = ceilPrep.map((l) => l.toJson()).toList();
        final groupsDirty = wallIdsBefore.toString() !=
            room.wallFinishLayers.map((e) => e['price_group_id']).toList().toString();
        final migrated = migrateScreedPricesToM3(room);
        if (migrated > 0) {
          final fp = room.floorCoveringUnitPrice;
          _floorCoveringPriceCtrl.text =
              (fp != null && fp > 0) ? fp.toStringAsFixed(0) : '';
        }
        // Legacy: quantity>1 drew linked marks — expand into independent openings once.
        final expanded = _expandLinkedOpeningsInPlace(room);
        if (expanded || groupsDirty || migrated > 0) {
          scheduleMicrotask(() {
            if (mounted) _persist();
          });
        }
      }
    });
    if (pricesFailed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Цены поставщика не загрузились — суммы без каталога')),
      );
    }
    await _autofillMissingLayerPrices();
  }

  Future<void> _autofillMissingLayerPrices({bool onlyEmpty = true}) async {
    final room = _room;
    if (room == null || !mounted) return;
    final catalog = await WorkRatesCatalogStore.ensureLoaded();
    if (!mounted) return;
    final walls = _wallLayers.toList();
    final nWall = autofillWallLayerPrices(walls, catalog, onlyEmpty: onlyEmpty);
    if (nWall > 0) _syncLayers(walls);
    var nPrep = 0;
    for (final floor in [true, false]) {
      final prep = _prepLayers(floor: floor);
      final n = autofillPrepLayerPrices(
        prep,
        catalog,
        floor: floor,
        onlyEmpty: onlyEmpty,
      );
      if (n > 0) {
        nPrep += n;
        _syncPrepLayers(prep, floor: floor);
      }
    }
    final nCover = autofillCoveringPrices([room], catalog, onlyEmpty: onlyEmpty);
    if (nCover > 0) {
      final fp = room.floorCoveringUnitPrice;
      _floorCoveringPriceCtrl.text =
          (fp != null && fp > 0) ? fp.toStringAsFixed(0) : _floorCoveringPriceCtrl.text;
      final cp = room.ceilingSystemUnitPrice;
      _ceilingSystemPriceCtrl.text =
          (cp != null && cp > 0) ? cp.toStringAsFixed(0) : _ceilingSystemPriceCtrl.text;
    }
    final total = nWall + nPrep + nCover;
    if (total > 0) {
      setState(() {});
      await _persist();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Подставлено цен: $total')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            onlyEmpty
                ? 'Пустых слоёв без цены не осталось (или нет совпадений в каталоге)'
                : 'В каталоге нет подходящих позиций',
          ),
        ),
      );
    }
  }

  /// Splits openings with quantity>1 into separate qty=1 rows so each can move alone.
  /// Returns true if [room.openings] was rewritten.
  bool _expandLinkedOpeningsInPlace(Room room) {
    const gap = 30.0;
    final raw = room.openings.map(RoomOpening.fromJson).toList();
    if (!raw.any((o) => o.quantity > 1)) return false;
    final out = <RoomOpening>[];
    for (final o in raw) {
      final n = math.max(1, o.quantity);
      if (n <= 1) {
        out.add(
          RoomOpening(
            kind: o.kind,
            label: o.label,
            widthCm: o.widthCm,
            heightCm: o.heightCm,
            quantity: 1,
            wallIndex: o.wallIndex,
            offsetAlongWallCm: o.offsetAlongWallCm,
            sillHeightCm: o.sillHeightCm,
          ),
        );
        continue;
      }
      for (var q = 0; q < n; q++) {
        out.add(
          RoomOpening(
            kind: o.kind,
            label: o.label,
            widthCm: o.widthCm,
            heightCm: o.heightCm,
            quantity: 1,
            wallIndex: o.wallIndex,
            offsetAlongWallCm: o.wallIndex != null
                ? o.offsetAlongWallCm + q * (o.widthCm + gap)
                : 0,
            sillHeightCm: o.sillHeightCm,
          ),
        );
      }
    }
    room.openings = out.map((o) => o.toJson()).toList();
    return true;
  }

  List<RoomOpening> get _openings {
    final room = _room;
    if (room == null) return const [];
    return room.openings.map(RoomOpening.fromJson).toList();
  }

  List<FinishLayer> get _wallLayers {
    final room = _room;
    if (room == null) return const [];
    return room.wallFinishLayers.map(FinishLayer.fromJson).toList();
  }

  FinishLayer? get _firstTileLayer {
    for (final l in _wallLayers) {
      if (l.enabled && l.kind == FinishLayerKind.tile) return l;
    }
    return null;
  }

  FinishAreas? get _areas {
    final room = _room;
    final project = _project;
    if (room == null) return null;
    if (room.isSpecialSpace) {
      return finishAreasForRoom(
        room,
        project: project,
        wallLayersOverride: _wallLayers,
      );
    }
    if (!room.hasLayout) return null;
    final h = double.tryParse(_heightCtrl.text.replaceAll(',', '.')) ?? room.ceilingHeightCm;
    final tw = double.tryParse(_tileWCtrl.text.replaceAll(',', '.')) ?? room.finishTileWidthCm;
    final th = double.tryParse(_tileHCtrl.text.replaceAll(',', '.')) ?? room.finishTileHeightCm;
    var ceilingCell = 60.0;
    if (project != null) {
      final (ceiling, _, cell) = roomEffectiveConfig(room, project);
      ceilingCell = ceilingCellCm(ceiling, cell);
    }
    final counts = finishLayoutCountsForRoom(room);
    return FinishCalculator.compute(
      walls: room.walls,
      heightCm: h,
      openings: _openings,
      tileWidthCm: tw,
      tileHeightCm: th,
      ceilingCellCm: ceilingCell,
      floorLayoutBoardCount: counts.floorBoards,
      wallLayoutTileCount: counts.wallTiles,
      ceilingLayoutTileCount: counts.ceilingTiles,
      wallLayers: _wallLayers,
    );
  }

  void _rebuildWallGrid() {
    final room = _room;
    final tile = _firstTileLayer;
    if (room == null || !room.hasLayout || tile == null) return;
    if (_wallElevationIndex < 0 || _wallElevationIndex >= room.walls.length) {
      _wallElevationIndex = 0;
    }
    final w = room.walls[_wallElevationIndex];
    final len = math.sqrt(math.pow(w[2] - w[0], 2) + math.pow(w[3] - w[1], 2));
    final h = double.tryParse(_heightCtrl.text.replaceAll(',', '.')) ?? room.ceilingHeightCm;
    final rect = <List<double>>[
      [0, 0, len, 0],
      [len, 0, len, h],
      [len, h, 0, h],
      [0, h, 0, 0],
    ];
    _wallGrid.setCellSizeWH(tile.tileWidthCm, tile.tileHeightCm);
    _wallGrid.setOffset(tile.tileOffsetX.toDouble(), tile.tileOffsetY.toDouble());
    _wallGrid.rebuild(roomPoints: pointsFromWalls(rect), walls: rect);
  }

  (double lengthCm, double heightCm) _wallElevationSize(Room room) {
    final w = room.walls[_wallElevationIndex.clamp(0, room.walls.length - 1)];
    final len = math.sqrt(math.pow(w[2] - w[0], 2) + math.pow(w[3] - w[1], 2));
    final h = double.tryParse(_heightCtrl.text.replaceAll(',', '.')) ?? room.ceilingHeightCm;
    return (len, h);
  }

  CeilingGrid _buildCeilingGrid(Room room) {
    final grid = CeilingGrid(cellSizeCm: 60);
    grid.setOffset(room.gridOffsetX.toDouble(), room.gridOffsetY.toDouble());
    final lights = <String>{};
    for (final f in room.lightFixtures) {
      if (f.length >= 2) lights.add('${f[0]}:${f[1]}');
    }
    grid.rebuild(
      roomPoints: pointsFromWalls(room.walls),
      walls: room.walls,
      lightIds: lights,
    );
    return grid;
  }

  Future<void> _persist() async {
    _heightSaveTimer?.cancel();
    _heightSaveTimer = null;
    final room = _room;
    if (room == null) return;
    _applyHeightFieldsToRoom(room);
    final projects = _projects ?? (mounted ? AppScope.of(context).projects : null);
    if (projects == null) return;
    await projects.updateRoom(room);
  }

  Future<void> _setFinishInclude({
    bool? floor,
    bool? walls,
    bool? ceiling,
    bool? extraWorks,
  }) async {
    final room = _room;
    if (room == null) return;
    setState(() {
      if (floor != null) room.finishIncludeFloor = floor;
      if (walls != null) room.finishIncludeWalls = walls;
      if (ceiling != null) room.finishIncludeCeiling = ceiling;
      if (extraWorks != null) room.finishIncludeExtraWorks = extraWorks;
    });
    await _persist();
  }

  Widget _finishIncludeSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
    String title = 'Учитывать в расчётах',
    String? subtitle,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(
        subtitle ??
            (value
                ? 'Попадает в ведомость, материалы и документы'
                : 'Исключено из ведомости и закрытия КС'),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Future<void> _openFinishVedomost({
    FinishVedomostScope? scope,
    BuildContext? tabContext,
  }) async {
    await _persist();
    if (!mounted) return;
    final tab = widget.lockedTabIndex ??
        DefaultTabController.maybeOf(tabContext ?? context)?.index ??
        0;
    final resolved = scope ?? FinishVedomostScopeX.fromRoomTab(tab);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinishMaterialsScreen(
          projectId: widget.projectId,
          roomId: widget.roomId,
          scope: resolved,
        ),
      ),
    );
  }

  Future<void> _openSectionEditor({
    FinishEditorKind? kind,
    BuildContext? tabContext,
  }) async {
    await _persist();
    if (!mounted) return;
    final tab = widget.lockedTabIndex ??
        DefaultTabController.maybeOf(tabContext ?? context)?.index ??
        0;
    final resolved = kind ?? FinishEditorKindX.fromRoomTab(tab);
    await openFinishEditor(
      context,
      projectId: widget.projectId,
      roomId: widget.roomId,
      kind: resolved,
    );
    if (mounted) await _load();
  }

  void _syncOpenings(List<RoomOpening> list) {
    final room = _room;
    if (room == null) return;
    setState(() => room.openings = list.map((o) => o.toJson()).toList());
  }

  void _syncLayers(List<FinishLayer> list) {
    final room = _room;
    if (room == null) return;
    sanitizeWallPriceGroups(list, roomId: room.id);
    setState(() {
      room.wallFinishLayers = list.map((o) => o.toJson()).toList();
      _rebuildWallGrid();
    });
  }

  void _onFloorTileChanged() {
    setState(() {});
    _persist();
  }

  bool _floorPresetSelected((double, double) preset) {
    final w = double.tryParse(_tileWCtrl.text.replaceAll(',', '.'));
    final h = double.tryParse(_tileHCtrl.text.replaceAll(',', '.'));
    if (w == null || h == null) return false;
    return (w - preset.$1).abs() < 0.05 && (h - preset.$2).abs() < 0.05;
  }

  static String _formatPresetDim(double v) {
    final r = v.roundToDouble();
    if ((v - r).abs() < 0.001) return r.round().toString();
    return v.toString();
  }

  void _applyFloorPreset((double, double) preset) {
    _tileWCtrl.text = _formatPresetDim(preset.$1);
    _tileHCtrl.text = _formatPresetDim(preset.$2);
  }

  void _nudgeWallTile(double dx, double dy, {bool finalize = false}) {
    final layers = _wallLayers.toList();
    final i = layers.indexWhere((l) => l.enabled && l.kind == FinishLayerKind.tile);
    if (i < 0) return;
    setState(() {
      layers[i].tileOffsetX = (layers[i].tileOffsetX + dx).round();
      layers[i].tileOffsetY = (layers[i].tileOffsetY + dy).round();
      _room!.wallFinishLayers = layers.map((o) => o.toJson()).toList();
      _rebuildWallGrid();
    });
    if (finalize) _commitWallTileOffset();
  }

  void _commitWallTileOffset() {
    final tile = _firstTileLayer;
    if (tile == null) return;
    _wallTileUndo.push(FloorLayoutUndoSnapshot(
      offsetX: tile.tileOffsetX,
      offsetY: tile.tileOffsetY,
    ));
    _persist();
  }

  void _applyWallTileSnapshot(FloorLayoutUndoSnapshot snap) {
    final layers = _wallLayers.toList();
    final i = layers.indexWhere((l) => l.enabled && l.kind == FinishLayerKind.tile);
    if (i < 0) return;
    setState(() {
      layers[i].tileOffsetX = snap.offsetX;
      layers[i].tileOffsetY = snap.offsetY;
      _room!.wallFinishLayers = layers.map((o) => o.toJson()).toList();
      _rebuildWallGrid();
    });
    _persist();
  }

  void _undoWallTileOffset() {
    final snap = _wallTileUndo.undo();
    if (snap == null) return;
    _applyWallTileSnapshot(snap);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Плитка стены: ${formatFloorLayoutUndoLabel(snap)}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _redoWallTileOffset() {
    final snap = _wallTileUndo.redo();
    if (snap == null) return;
    _applyWallTileSnapshot(snap);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Плитка стены: ${formatFloorLayoutUndoLabel(snap)}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ARCHIVED: _confirmRebaseline / _showBaselineHistory — see `_archived/finish_project_vs_fact_ui.dart.txt`

  Future<void> _addOrEditOpening({RoomOpening? existing, int? index}) async {
    final room = _room;
    if (room == null) return;

    var kind = existing?.kind ?? 'door';
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final wCtrl = TextEditingController(
      text: (existing?.widthCm ?? (kind == 'door' ? 90 : 120)).round().toString(),
    );
    final hCtrl = TextEditingController(
      text: (existing?.heightCm ?? (kind == 'door' ? 210 : 140)).round().toString(),
    );
    final qtyCtrl = TextEditingController(text: '1');
    final sillCtrl = TextEditingController(
      text: (existing?.sillHeightCm ?? (kind == 'window' ? 90 : 0)).round().toString(),
    );
    final offsetCtrl = TextEditingController(
      text: existing?.wallIndex != null
          ? existing!.offsetAlongWallCm.round().toString()
          : '',
    );
    final templates = await loadOpeningTemplates();
    if (!mounted) {
      labelCtrl.dispose();
      wCtrl.dispose();
      hCtrl.dispose();
      qtyCtrl.dispose();
      sillCtrl.dispose();
      offsetCtrl.dispose();
      return;
    }
    OpeningTemplate? pickedTemplate;
    var saveAsTemplate = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final named = labelCtrl.text.trim().isNotEmpty;
            return AlertDialog(
              title: Text(existing == null ? 'Тип проёма' : 'Изменить проём'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (templates.isNotEmpty) ...[
                      DropdownButtonFormField<OpeningTemplate?>(
                        key: ValueKey(pickedTemplate?.id ?? 'none'),
                        initialValue: pickedTemplate,
                        decoration: const InputDecoration(
                          labelText: 'Из шаблона',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<OpeningTemplate?>(
                            value: null,
                            child: Text('— без шаблона —'),
                          ),
                          for (final t in templates)
                            DropdownMenuItem<OpeningTemplate?>(
                              value: t,
                              child: Text('${t.name} · ${t.widthCm.round()}×${t.heightCm.round()}'),
                            ),
                        ],
                        onChanged: (t) {
                          setLocal(() {
                            pickedTemplate = t;
                            if (t == null) return;
                            kind = t.kind;
                            labelCtrl.text = t.name;
                            wCtrl.text = t.widthCm.round().toString();
                            hCtrl.text = t.heightCm.round().toString();
                            sillCtrl.text = t.sillHeightCm.round().toString();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'door', label: Text('Дверь')),
                        ButtonSegment(value: 'window', label: Text('Окно')),
                      ],
                      selected: {kind},
                      onSelectionChanged: (s) {
                        setLocal(() {
                          kind = s.first;
                          if (existing == null && pickedTemplate == null) {
                            if (kind == 'window') {
                              wCtrl.text = '120';
                              hCtrl.text = '140';
                              sillCtrl.text = '90';
                            } else {
                              wCtrl.text = '90';
                              hCtrl.text = '210';
                              sillCtrl.text = '0';
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: labelCtrl,
                      keyboardType: NumericInput.textKeyboard,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setLocal(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Название (необязательно)',
                        hintText: 'Входная / Межкомнатная…',
                        isDense: true,
                      ),
                    ),
                    if (named) ...[
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: saveAsTemplate,
                        onChanged: (v) => setLocal(() => saveAsTemplate = v ?? false),
                        title: const Text('Сохранить как шаблон'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: wCtrl,
                            keyboardType: NumericInput.integerKeyboard,
                            inputFormatters: NumericInput.integerFormatters,
                            decoration: const InputDecoration(labelText: 'Ширина, см', isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: hCtrl,
                            keyboardType: NumericInput.integerKeyboard,
                            inputFormatters: NumericInput.integerFormatters,
                            decoration: const InputDecoration(labelText: 'Высота, см', isDense: true),
                          ),
                        ),
                      ],
                    ),
                    if (existing == null) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: qtyCtrl,
                        keyboardType: NumericInput.integerKeyboard,
                        inputFormatters: NumericInput.integerFormatters,
                        decoration: const InputDecoration(
                          labelText: 'Количество',
                          helperText: 'Каждый проём — отдельно, можно двигать по одному',
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: offsetCtrl,
                      keyboardType: NumericInput.decimalKeyboard,
                      inputFormatters: NumericInput.decimalFormatters,
                      decoration: const InputDecoration(
                        labelText: 'Отступ от левого края стены, см',
                        hintText: 'Пусто = по центру',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: sillCtrl,
                      keyboardType: NumericInput.integerKeyboard,
                      inputFormatters: NumericInput.integerFormatters,
                      decoration: const InputDecoration(
                        labelText: 'Высота от пола (подоконник), см',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
              ],
            );
          },
        );
      },
    );

    final label = labelCtrl.text.trim();
    final widthCm = double.tryParse(wCtrl.text.replaceAll(',', '.')) ?? 0;
    final heightCm = double.tryParse(hCtrl.text.replaceAll(',', '.')) ?? 0;
    final sill = double.tryParse(sillCtrl.text.replaceAll(',', '.')) ?? 0;
    final qty = math.max(1, int.tryParse(qtyCtrl.text) ?? 1);
    final offsetRaw = offsetCtrl.text.trim().replaceAll(',', '.');
    final customOffset =
        offsetRaw.isEmpty ? null : double.tryParse(offsetRaw);
    final shouldSaveTemplate = saveAsTemplate && label.isNotEmpty;

    labelCtrl.dispose();
    wCtrl.dispose();
    hCtrl.dispose();
    qtyCtrl.dispose();
    sillCtrl.dispose();
    offsetCtrl.dispose();

    if (ok != true || !mounted) return;

    if (shouldSaveTemplate) {
      await upsertOpeningTemplate(
        OpeningTemplate(
          id: pickedTemplate?.id ?? newOpeningTemplateId(),
          name: label,
          kind: kind,
          widthCm: widthCm,
          heightCm: heightCm,
          sillHeightCm: sill,
        ),
      );
    }

    final list = _openings.toList();
    if (index != null && existing != null) {
      final next = RoomOpening(
        kind: kind,
        label: label.isEmpty ? null : label,
        widthCm: widthCm,
        heightCm: heightCm,
        quantity: 1,
        wallIndex: existing.wallIndex,
        offsetAlongWallCm: customOffset ?? existing.offsetAlongWallCm,
        sillHeightCm: sill,
      );
      if (customOffset != null && existing.wallIndex != null) {
        next.offsetAlongWallCm = customOffset;
      } else if (customOffset != null && existing.wallIndex == null) {
        final placed = _defaultOpeningPlacement(next, offsetFromLeftCm: customOffset);
        list[index] = placed;
        _syncOpenings(list);
        await _persist();
        setState(() => _placingIndex = index);
        return;
      }
      list[index] = next;
      _syncOpenings(list);
      await _persist();
    } else {
      final created = <RoomOpening>[];
      for (var q = 0; q < qty; q++) {
        final base = RoomOpening(
          kind: kind,
          label: label.isEmpty ? null : label,
          widthCm: widthCm,
          heightCm: heightCm,
          quantity: 1,
          sillHeightCm: sill,
        );
        created.add(
          _defaultOpeningPlacement(
            base,
            offsetFromLeftCm: customOffset,
            siblingIndex: q,
            siblingCount: qty,
          ),
        );
      }
      list.addAll(created);
      _syncOpenings(list);
      await _persist();
      setState(() => _placingIndex = list.length - created.length);
    }
  }

  /// Place on the topmost wall. Empty [offsetFromLeftCm] → center the group.
  RoomOpening _defaultOpeningPlacement(
    RoomOpening opening, {
    double? offsetFromLeftCm,
    int siblingIndex = 0,
    int siblingCount = 1,
  }) {
    final room = _room;
    if (room == null || room.walls.isEmpty) return opening;
    var bestI = 0;
    var bestY = -double.infinity;
    for (var i = 0; i < room.walls.length; i++) {
      final w = room.walls[i];
      final midY = (w[1] + w[3]) / 2;
      if (midY > bestY) {
        bestY = midY;
        bestI = i;
      }
    }
    final w = room.walls[bestI];
    final len = math.sqrt(math.pow(w[2] - w[0], 2) + math.pow(w[3] - w[1], 2));
    const gap = 30.0;
    final n = math.max(1, siblingCount);
    final totalW = n * opening.widthCm + (n - 1) * gap;
    final groupStart = offsetFromLeftCm ??
        ((len - totalW) / 2).clamp(0.0, math.max(0.0, len - opening.widthCm)).toDouble();
    final start = (groupStart + siblingIndex * (opening.widthCm + gap))
        .clamp(0.0, math.max(0.0, len - opening.widthCm))
        .toDouble();
    return RoomOpening(
      kind: opening.kind,
      label: opening.label,
      widthCm: opening.widthCm,
      heightCm: opening.heightCm,
      quantity: 1,
      wallIndex: bestI,
      offsetAlongWallCm: start,
      sillHeightCm: opening.sillHeightCm,
    );
  }

  Future<void> _placeOpening(int index, int wallIndex, double offsetAlongCm) async {
    final list = _openings.toList();
    if (index < 0 || index >= list.length) return;
    list[index].wallIndex = wallIndex;
    list[index].offsetAlongWallCm = offsetAlongCm;
    list[index].quantity = 1;
    _syncOpenings(list);
    await _persist();
  }

  Future<void> _finishPlacing() async {
    setState(() => _placingIndex = null);
    await _persist();
  }

  Future<void> _clearPlacement(int index) async {
    final list = _openings.toList();
    if (index < 0 || index >= list.length) return;
    list[index].wallIndex = null;
    list[index].offsetAlongWallCm = 0;
    _syncOpenings(list);
    if (_placingIndex == index) {
      setState(() => _placingIndex = null);
    }
    await _persist();
  }

  Future<void> _duplicateOpening(int index) async {
    final list = _openings.toList();
    if (index < 0 || index >= list.length) return;
    final src = list[index];
    const gap = 30.0;
    var offset = src.offsetAlongWallCm;
    if (src.wallIndex != null) {
      offset = src.offsetAlongWallCm + src.widthCm + gap;
      final walls = _room?.walls ?? const <List<double>>[];
      if (src.wallIndex! >= 0 && src.wallIndex! < walls.length) {
        final w = walls[src.wallIndex!];
        final len = math.sqrt(math.pow(w[2] - w[0], 2) + math.pow(w[3] - w[1], 2));
        offset = offset.clamp(0.0, math.max(0.0, len - src.widthCm)).toDouble();
      }
    }
    final copy = RoomOpening(
      kind: src.kind,
      label: src.label,
      widthCm: src.widthCm,
      heightCm: src.heightCm,
      quantity: 1,
      wallIndex: src.wallIndex,
      offsetAlongWallCm: src.wallIndex != null ? offset : 0,
      sillHeightCm: src.sillHeightCm,
    );
    list.insert(index + 1, copy);
    _syncOpenings(list);
    await _persist();
    setState(() => _placingIndex = index + 1);
  }

  Future<void> _removeOpening(int index) async {
    final list = _openings.toList()..removeAt(index);
    if (_placingIndex != null) {
      if (_placingIndex == index) {
        setState(() => _placingIndex = null);
      } else if (_placingIndex! > index) {
        setState(() => _placingIndex = _placingIndex! - 1);
      }
    }
    _syncOpenings(list);
    await _persist();
  }

  /// One shared price for several wall layers (visual «итерация»).
  Future<void> _bindSharedWallPrice({bool all = false}) async {
    if (_wallLayers.isEmpty) return;
    final selected = <int>{
      if (all) for (var i = 0; i < _wallLayers.length; i++) i,
    };
    if (!all) {
      final picked = await showDialog<Set<int>>(
        context: context,
        builder: (ctx) {
          final local = <int>{0, if (_wallLayers.length > 1) 1};
          return StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
              title: const Text('Слои с одной ценой'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Выберите слои одной итерации — у них будет общая цена '
                      'и общая пометка в списке.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: math.min(280, 52.0 * _wallLayers.length),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _wallLayers.length,
                        itemBuilder: (_, i) => CheckboxListTile(
                          dense: true,
                          value: local.contains(i),
                          title: Text(_wallLayers[i].displayLabel),
                          subtitle: _wallLayers[i].unitPrice != null &&
                                  _wallLayers[i].unitPrice! > 0
                              ? Text(formatRub(_wallLayers[i].unitPrice!))
                              : null,
                          onChanged: (v) => setLocal(() {
                            if (v == true) {
                              local.add(i);
                            } else {
                              local.remove(i);
                            }
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, local),
                  child: const Text('Далее'),
                ),
              ],
            ),
          );
        },
      );
      if (picked == null || picked.isEmpty || !mounted) return;
      selected
        ..clear()
        ..addAll(picked);
    }
    if (selected.isEmpty) return;
    final price = await showBulkLayerPriceDialog(
      context,
      title: selected.length == 1
          ? 'Цена слоя'
          : 'Общая цена · ${selected.length} слоя',
      section: 'walls',
    );
    if (price == null || !mounted) return;
    final list = _wallLayers.toList();
    if (selected.length == 1) {
      // Single pick: if already in a group — update the whole group price.
      final i = selected.first;
      final gid = list[i].priceGroupId;
      if (gid != null && gid.isNotEmpty) {
        syncWallLayerGroupPrice(list, groupId: gid, unitPrice: price);
      } else {
        list[i].unitPrice = price;
      }
    } else {
      final groupId = newPriceGroupId(roomId: _room?.id);
      bindWallLayersSharedPrice(
        list,
        selected,
        unitPrice: price,
        groupId: groupId,
      );
    }
    _syncLayers(list);
    await _persist();
  }

  Future<void> _bindSharedPrepPrice({required bool floor}) async {
    final layers = _prepLayers(floor: floor);
    if (layers.isEmpty) return;
    final section = floor ? 'floor' : 'ceiling';
    final selected = <int>{};
    final picked = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) {
        final local = <int>{for (var i = 0; i < layers.length; i++) i};
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(floor ? 'Слои пола · общая цена' : 'Слои потолка · общая цена'),
            content: SizedBox(
              width: 360,
              height: math.min(280, 52.0 * layers.length + 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Отметьте слои одной итерации — одна цена на всех.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: layers.length,
                      itemBuilder: (_, i) => CheckboxListTile(
                        dense: true,
                        value: local.contains(i),
                        title: Text(layers[i].displayName(floor: floor)),
                        onChanged: (v) => setLocal(() {
                          if (v == true) {
                            local.add(i);
                          } else {
                            local.remove(i);
                          }
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, local),
                child: const Text('Далее'),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    selected.addAll(picked);
    final price = await showBulkLayerPriceDialog(
      context,
      title: 'Общая цена · ${selected.length} слоя',
      section: section,
    );
    if (price == null || !mounted) return;
    if (selected.length == 1) {
      final i = selected.first;
      final gid = layers[i].priceGroupId;
      if (gid != null && gid.isNotEmpty) {
        syncPrepLayerGroupPrice(layers, groupId: gid, unitPrice: price);
      } else {
        layers[i].unitPrice = price;
      }
    } else {
      bindPrepLayersSharedPrice(
        layers,
        selected,
        unitPrice: price,
        groupId: newPriceGroupId(roomId: _room?.id),
      );
    }
    _syncPrepLayers(layers, floor: floor);
    setState(() {});
    await _persist();
  }

  Future<void> _addOrEditLayer({FinishLayer? existing, int? index}) async {
    var kind = existing?.kind ?? FinishLayerKind.plaster;
    var coats = existing?.paintCoats.clamp(1, 3) ?? 2;
    var addPrimer = existing == null;
    final twCtrl = TextEditingController(
      text: (existing?.tileWidthCm ?? 60).round().toString(),
    );
    final thCtrl = TextEditingController(
      text: (existing?.tileHeightCm ?? 60).round().toString(),
    );
    final priceCtrl = TextEditingController(
      text: (existing?.unitPrice != null && existing!.unitPrice! > 0)
          ? existing.unitPrice!.toStringAsFixed(0)
          : '',
    );
    var materials = [
      for (final m in existing?.materialLinks ?? const <FinishMaterialLink>[])
        m.copy(),
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(existing == null ? 'Слой отделки' : 'Изменить слой'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<FinishLayerKind>(
                      key: ValueKey(kind),
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: 'Тип', isDense: true),
                      items: [
                        for (final k in FinishLayerKind.values)
                          DropdownMenuItem(value: k, child: Text(k.labelRu)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => kind = v);
                      },
                    ),
                    if (existing == null && kind != FinishLayerKind.primer) ...[
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: addPrimer,
                        onChanged: (v) => setLocal(() => addPrimer = v),
                        title: const Text('Добавить грунтовку'),
                        subtitle: const Text('Сначала слой грунтовки, затем выбранный тип'),
                      ),
                    ],
                    if (kind == FinishLayerKind.paint) ...[
                      const SizedBox(height: 12),
                      Text('Слоёв краски: $coats'),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1')),
                          ButtonSegment(value: 2, label: Text('2')),
                          ButtonSegment(value: 3, label: Text('3')),
                        ],
                        selected: {coats},
                        onSelectionChanged: (s) => setLocal(() => coats = s.first),
                      ),
                    ],
                    if (kind == FinishLayerKind.tile) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final p in floorTilePresets)
                            ActionChip(
                              label: Text('${p.$1.round()}×${p.$2.round()}'),
                              onPressed: () => setLocal(() {
                                twCtrl.text = p.$1.round().toString();
                                thCtrl.text = p.$2.round().toString();
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: twCtrl,
                              keyboardType: NumericInput.integerKeyboard,
                              inputFormatters: NumericInput.integerFormatters,
                              decoration: const InputDecoration(
                                labelText: 'Ширина',
                                suffixText: 'см',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: thCtrl,
                              keyboardType: NumericInput.integerKeyboard,
                              inputFormatters: NumericInput.integerFormatters,
                              decoration: const InputDecoration(
                                labelText: 'Длина',
                                suffixText: 'см',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    LayerPriceFields(
                      priceCtrl: priceCtrl,
                      section: 'walls',
                      suggestName: kind.labelRu,
                      layerKindId: kind.id,
                      materials: materials,
                      onMaterialsChanged: (m) => setLocal(() => materials = m),
                      onChanged: () => setLocal(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
              ],
            );
          },
        );
      },
    );
    final tileW = double.tryParse(twCtrl.text) ?? 60;
    final tileH = double.tryParse(thCtrl.text) ?? 60;
    final priceRaw = priceCtrl.text.trim();
    final unitPrice = priceRaw.isEmpty
        ? null
        : double.tryParse(priceRaw.replaceAll(',', '.'));
    final shouldAddPrimer = addPrimer;
    twCtrl.dispose();
    thCtrl.dispose();
    priceCtrl.dispose();
    if (ok != true || !mounted) return;

    // Individual price edit dissolves the whole shared-price group.
    final prevGroup = existing?.priceGroupId;
    final prevPrice = existing?.unitPrice;
    final priceChanged = unitPrice != prevPrice &&
        !(unitPrice == null && (prevPrice == null || prevPrice <= 0));
    final next = FinishLayer(
      kind: kind,
      paintCoats: coats,
      tileWidthCm: tileW,
      tileHeightCm: tileH,
      tileOffsetX: existing?.tileOffsetX ?? 0,
      tileOffsetY: existing?.tileOffsetY ?? 0,
      enabled: existing?.enabled ?? true,
      unitPrice: unitPrice,
      rateMatchKey: existing?.rateMatchKey,
      rateName: existing?.rateName,
      priceGroupId: priceChanged ? null : prevGroup,
      materialLinks: materials,
    );
    if (next.unitPrice == null || next.unitPrice! <= 0) {
      final catalog = await WorkRatesCatalogStore.ensureLoaded();
      autofillWallLayerPrices([next], catalog, onlyEmpty: true);
    }
    final list = _wallLayers.toList();
    if (index != null) {
      list[index] = next;
      if (priceChanged) dissolveWallPriceGroup(list, prevGroup);
    } else {
      if (shouldAddPrimer && kind != FinishLayerKind.primer) {
        final primer = FinishLayer(
          kind: FinishLayerKind.primer,
          paintCoats: 1,
          tileWidthCm: 60,
          tileHeightCm: 60,
          enabled: true,
        );
        final catalog = await WorkRatesCatalogStore.ensureLoaded();
        autofillWallLayerPrices([primer], catalog, onlyEmpty: true);
        list.add(primer);
      }
      list.add(next);
    }
    _syncLayers(list);
    await _persist();
  }

  Future<void> _removeLayer(int index) async {
    final list = _wallLayers.toList()..removeAt(index);
    _syncLayers(list);
    await _persist();
  }

  List<SurfacePrepLayer> _prepLayers({required bool floor}) {
    final room = _room;
    if (room == null) return [];
    final raw = floor ? room.floorPrepLayers : room.ceilingPrepLayers;
    return raw.map(SurfacePrepLayer.fromJson).toList();
  }

  void _syncPrepLayers(List<SurfacePrepLayer> list, {required bool floor}) {
    final room = _room;
    if (room == null) return;
    sanitizePrepPriceGroups(list, roomId: room.id);
    final encoded = list.map((l) => l.toJson()).toList();
    if (floor) {
      room.floorPrepLayers = encoded;
    } else {
      room.ceilingPrepLayers = encoded;
    }
  }

  Future<void> _setPrepEnabled(bool enabled, {required bool floor}) async {
    final room = _room;
    if (room == null) return;
    if (!enabled) {
      if (_prepLayers(floor: floor).isNotEmpty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Отключить доп. слои?'),
            content: const Text('Список подготовительных слоёв будет очищен.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Очистить'),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
      _syncPrepLayers([], floor: floor);
    } else if (_prepLayers(floor: floor).isEmpty) {
      final seed = floor
          ? SurfacePrepLayer(kindId: FloorPrepKind.screed.id, thicknessCm: 5)
          : SurfacePrepLayer(
              kindId: CeilingPrepKind.insulation.id,
              thicknessCm: 5,
            );
      _syncPrepLayers([seed], floor: floor);
      setState(() {
        if (floor) {
          _floorPrepExpanded = true;
        } else {
          _ceilingPrepExpanded = true;
        }
      });
    }
    setState(() {});
    await _persist();
  }

  Future<void> _addOrEditPrepLayer({
    required bool floor,
    SurfacePrepLayer? existing,
    int? index,
  }) async {
    var kindId = existing?.kindId ??
        (floor ? FloorPrepKind.screed.id : CeilingPrepKind.insulation.id);
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final thickCtrl = TextEditingController(
      text: (existing?.thicknessCm ?? 5).toStringAsFixed(
        (existing?.thicknessCm ?? 5) == (existing?.thicknessCm ?? 5).roundToDouble()
            ? 0
            : 1,
      ),
    );
    final priceCtrl = TextEditingController(
      text: (existing?.unitPrice != null && existing!.unitPrice! > 0)
          ? existing.unitPrice!.toStringAsFixed(0)
          : '',
    );
    var materials = [
      for (final m in existing?.materialLinks ?? const <FinishMaterialLink>[])
        m.copy(),
    ];
    final section = floor ? 'floor' : 'ceiling';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final showThickness =
                SurfacePrepLayer(kindId: kindId).usesThickness;
            final suggestName = floor
                ? FloorPrepKind.parse(kindId).labelRu
                : CeilingPrepKind.parse(kindId).labelRu;
            return AlertDialog(
              title: Text(existing == null ? 'Слой подготовки' : 'Изменить слой'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (floor)
                      DropdownButtonFormField<String>(
                        key: ValueKey('floor-$kindId'),
                        initialValue: kindId,
                        decoration: const InputDecoration(
                          labelText: 'Тип',
                          isDense: true,
                        ),
                        items: [
                          for (final k in FloorPrepKind.values)
                            DropdownMenuItem(value: k.id, child: Text(k.labelRu)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => kindId = v);
                        },
                      )
                    else
                      DropdownButtonFormField<String>(
                        key: ValueKey('ceil-$kindId'),
                        initialValue: kindId,
                        decoration: const InputDecoration(
                          labelText: 'Тип',
                          isDense: true,
                        ),
                        items: [
                          for (final k in CeilingPrepKind.values)
                            DropdownMenuItem(value: k.id, child: Text(k.labelRu)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => kindId = v);
                        },
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: labelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Название (необязательно)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (showThickness) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: thickCtrl,
                        keyboardType: NumericInput.decimalKeyboard,
                        inputFormatters: NumericInput.decimalFormatters,
                        decoration: const InputDecoration(
                          labelText: 'Толщина',
                          suffixText: 'см',
                          isDense: true,
                          border: OutlineInputBorder(),
                          helperText: 'Для объёма: площадь × толщина',
                        ),
                      ),
                    ],
                    LayerPriceFields(
                      priceCtrl: priceCtrl,
                      section: section,
                      suggestName: labelCtrl.text.trim().isEmpty
                          ? suggestName
                          : labelCtrl.text.trim(),
                      layerKindId: kindId,
                      priceUnitLabel: showThickness ? '₽/м³' : '₽/м²',
                      catalogToStoredPrice: showThickness
                          ? (p) {
                              final d = double.tryParse(
                                    thickCtrl.text.replaceAll(',', '.'),
                                  ) ??
                                  0;
                              return screedCatalogM2ToM3(p, d);
                            }
                          : null,
                      materials: materials,
                      onMaterialsChanged: (m) => setLocal(() => materials = m),
                      onChanged: () => setLocal(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
    final label = labelCtrl.text.trim();
    final thickness =
        double.tryParse(thickCtrl.text.replaceAll(',', '.')) ?? 0;
    final priceRaw = priceCtrl.text.trim();
    final unitPrice = priceRaw.isEmpty
        ? null
        : double.tryParse(priceRaw.replaceAll(',', '.'));
    labelCtrl.dispose();
    thickCtrl.dispose();
    priceCtrl.dispose();
    if (ok != true || !mounted) return;

    final prevGroup = existing?.priceGroupId;
    final prevPrice = existing?.unitPrice;
    final priceChanged = unitPrice != prevPrice &&
        !(unitPrice == null && (prevPrice == null || prevPrice <= 0));
    final next = SurfacePrepLayer(
      kindId: kindId,
      label: label.isEmpty ? null : label,
      enabled: existing?.enabled ?? true,
      thicknessCm: thickness,
      unitPrice: unitPrice,
      rateMatchKey: existing?.rateMatchKey,
      rateName: existing?.rateName,
      priceGroupId: priceChanged ? null : prevGroup,
      materialLinks: materials,
    );
    if (next.unitPrice == null || next.unitPrice! <= 0) {
      final catalog = await WorkRatesCatalogStore.ensureLoaded();
      autofillPrepLayerPrices([next], catalog, floor: floor, onlyEmpty: true);
    }
    final list = _prepLayers(floor: floor);
    if (index != null) {
      list[index] = next;
      if (priceChanged) dissolvePrepPriceGroup(list, prevGroup);
    } else {
      list.add(next);
    }
    _syncPrepLayers(list, floor: floor);
    setState(() {});
    await _persist();
  }

  Future<void> _removePrepLayer(int index, {required bool floor}) async {
    final list = _prepLayers(floor: floor)..removeAt(index);
    _syncPrepLayers(list, floor: floor);
    setState(() {});
    await _persist();
  }

  String _mainFloorCoveringLabel(Room room) {
    final covering = FloorCoveringKindX.parse(room.floorCoveringKind);
    if (covering == FloorCoveringKind.laminate) {
      final pattern = FloorLayingPatternX.parse(room.floorLayingPattern);
      return '${covering.labelRu} · ${pattern.labelRu}';
    }
    return covering.labelRu;
  }

  String _mainCeilingCoveringLabel(Room room) {
    final project = _project;
    if (project == null) {
      return room.materialsCeiling ?? 'Армстронг';
    }
    final (ceiling, susp, _) = roomEffectiveConfig(room, project);
    return '$ceiling · $susp';
  }

  Widget _buildPrepLayersSection({required bool floor}) {
    final room = _room;
    if (room == null) return const SizedBox.shrink();
    final layers = _prepLayers(floor: floor);
    final enabled = layers.isNotEmpty;
    final expanded = floor ? _floorPrepExpanded : _ceilingPrepExpanded;
    final area = floor ? _areas?.floorM2 : _areas?.ceilingM2;
    final mainLabel =
        floor ? _mainFloorCoveringLabel(room) : _mainCeilingCoveringLabel(room);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Доп. слои подготовки'),
          subtitle: Text(
            floor
                ? 'Стяжка, гидроизоляция, подкладка — сверх основного покрытия'
                : 'Утеплитель, покраска, шпаклёвка — сверх системы потолка',
          ),
          value: enabled,
          onChanged: (v) => _setPrepEnabled(v, floor: floor),
        ),
        if (enabled) ...[
          _CollapsibleSection(
            title: 'Порядок слоёв',
            countLabel: '${layers.length + 1}',
            expanded: expanded,
            onToggle: () => setState(() {
              if (floor) {
                _floorPrepExpanded = !_floorPrepExpanded;
              } else {
                _ceilingPrepExpanded = !_ceilingPrepExpanded;
              }
            }),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (layers.length >= 2)
                  IconButton(
                    tooltip: 'Общая цена на несколько слоёв',
                    onPressed: () => _bindSharedPrepPrice(floor: floor),
                    icon: const Icon(Icons.payments_outlined, size: 20),
                  ),
                TextButton.icon(
                  onPressed: () => _addOrEditPrepLayer(floor: floor),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Слой'),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    floor
                        ? 'Сверху вниз: к плите → подготовка → основное покрытие (закреплено внизу).'
                        : 'Сверху вниз: к перекрытию → подготовка → система потолка (закреплена внизу).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: _reorderLayerProxyDecorator,
                  itemCount: layers.length,
                  onReorderItem: (oldIndex, newIndex) async {
                    final list = layers.toList();
                    final item = list.removeAt(oldIndex);
                    list.insert(newIndex, item);
                    _syncPrepLayers(list, floor: floor);
                    setState(() {});
                    await _persist();
                  },
                  itemBuilder: (context, i) {
                    final layer = layers[i];
                    final order = i + 1;
                    final isFirst = i == 0;
                    String? volHint;
                    if (layer.enabled &&
                        layer.usesThickness &&
                        layer.thicknessCm > 0 &&
                        area != null) {
                      final vol = screedVolumeM3(area, layer.thicknessCm);
                      volHint =
                          '${layer.thicknessCm.toStringAsFixed(layer.thicknessCm == layer.thicknessCm.roundToDouble() ? 0 : 1)} см · ${vol.toStringAsFixed(3)} м³';
                    }
                    String? matHint;
                    if (layer.enabled && area != null) {
                      final (qty, unit) =
                          layer.materialQty(area, floor: floor);
                      if (unit != 'м²') matHint = '$qty $unit';
                    }
                    return _LayerOrderCard(
                      key: ValueKey(
                        'prep-$floor-$i-${layer.kindId}-${layer.label}',
                      ),
                      reorderIndex: i,
                      orderLabel: '$order',
                      title: layer.displayName(floor: floor),
                      subtitle: [
                        if (isFirst)
                          floor ? '↓ к плите' : '↓ к перекрытию'
                        else
                          'Слой $order из ${layers.length}',
                        if (volHint != null) volHint,
                        if (matHint != null) matHint,
                        if (layerPriceSubtitle(layer.unitPrice).isNotEmpty)
                          '${layerPriceSubtitle(layer.unitPrice)}'
                          '${layer.usesThickness ? '/м³' : '/м²'}',
                        if (priceGroupIsActive(
                          layers.map((e) => e.priceGroupId),
                          layer.priceGroupId,
                          unitPrices: layers.map((e) => e.unitPrice),
                        ))
                          'общая цена',
                      ].join(' · '),
                      priceGroupAccent: priceGroupIsActive(
                        layers.map((e) => e.priceGroupId),
                        layer.priceGroupId,
                        unitPrices: layers.map((e) => e.unitPrice),
                      )
                          ? layer.priceGroupId
                          : null,
                      enabled: layer.enabled,
                      onEnabledChanged: (v) async {
                        final list = layers.toList();
                        list[i].enabled = v;
                        _syncPrepLayers(list, floor: floor);
                        setState(() {});
                        await _persist();
                      },
                      onEdit: () => _addOrEditPrepLayer(
                        floor: floor,
                        existing: layer,
                        index: i,
                      ),
                      onDelete: () => _removePrepLayer(i, floor: floor),
                    );
                  },
                ),
                _LayerOrderCard(
                  key: ValueKey('prep-main-$floor-$mainLabel'),
                  orderLabel: '${layers.length + 1}',
                  title: mainLabel,
                  subtitle: floor
                      ? 'Основное покрытие · задаётся выше'
                      : 'Система потолка · задаётся выше',
                  locked: true,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _saveCeilingMaterials({
    required bool override,
    required String ceiling,
    required String susp,
    required String cell,
  }) async {
    final room = _room;
    final project = _project;
    if (room == null || project == null || room.id == null || project.id == null) return;
    final repo = AppScope.of(context).projects;
    room.materialsOverride = override;
    room.materialsCeiling = ceiling;
    room.materialsSusp = susp;
    room.materialsCell = cell;
    if (!override) {
      project.materialsCeiling = ceiling;
      project.materialsSusp = susp;
      project.materialsCell = cell;
      await repo.updateProjectMaterials(
        project.id!,
        ceiling: ceiling,
        susp: susp,
        cell: cell,
      );
    }
    await repo.updateRoomMaterials(
      room.id!,
      override: override,
      ceiling: ceiling,
      susp: susp,
      cell: cell,
    );
    if (!mounted) return;
    setState(() {});
  }

  Widget _sectionTitle(String text) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.15,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _overviewPriceSummary(Room room, FinishAreas areas) {
    final wallRate = sumLayerUnitPrices(_wallLayers);
    final floorRate = floorScopeUnitPrice(room);
    final ceilRate = ceilingScopeUnitPrice(room);
    final wallSum =
        wallRate != null ? areas.wallsNetM2 * wallRate : null;
    final floorSum =
        floorRate != null ? areas.floorM2 * floorRate : null;
    final ceilSum =
        ceilRate != null ? areas.ceilingM2 * ceilRate : null;
    final total = (wallSum ?? 0) + (floorSum ?? 0) + (ceilSum ?? 0);
    return [
      const SizedBox(height: 16),
      _sectionTitle('Работы · расценки слоёв'),
      Align(
        alignment: Alignment.centerRight,
        child: PopupMenuButton<String>(
          tooltip: 'Цены',
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.payments_outlined, size: 18),
                SizedBox(width: 6),
                Text('Цены слоёв'),
              ],
            ),
          ),
          onSelected: (v) {
            if (v == 'auto') {
              _autofillMissingLayerPrices(onlyEmpty: true);
            } else if (v == 'auto_all') {
              _autofillMissingLayerPrices(onlyEmpty: false);
            } else if (v == 'walls') {
              _bindSharedWallPrice(all: false);
            } else if (v == 'floor') {
              _bindSharedPrepPrice(floor: true);
            } else if (v == 'ceil') {
              _bindSharedPrepPrice(floor: false);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'auto',
              child: Text('Подтянуть пустые из каталога'),
            ),
            PopupMenuItem(
              value: 'auto_all',
              child: Text('Обновить все из каталога'),
            ),
            PopupMenuItem(
              value: 'walls',
              child: Text('Общая цена · стены…'),
            ),
            PopupMenuItem(
              value: 'floor',
              child: Text('Общая цена · пол…'),
            ),
            PopupMenuItem(
              value: 'ceil',
              child: Text('Общая цена · потолок…'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Цены задаются на слоях (стены / пол / потолок). '
        'Пустые подтягиваются из каталога работ.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      if (floorSum != null)
        _AreaRow(
          label: 'Пол',
          value: floorSum,
          customValue:
              '${formatRub(floorRate!)}/м² · ${formatRub(floorSum)}',
        )
      else
        const _AreaRow(label: 'Пол', value: 0, customValue: 'нет цен на слоях'),
      if (wallSum != null)
        _AreaRow(
          label: 'Стены',
          value: wallSum,
          customValue: '${formatRub(wallRate!)}/м² · ${formatRub(wallSum)}',
        )
      else
        const _AreaRow(
          label: 'Стены',
          value: 0,
          customValue: 'нет цен на слоях',
        ),
      if (ceilSum != null)
        _AreaRow(
          label: 'Потолок',
          value: ceilSum,
          customValue: '${formatRub(ceilRate!)}/м² · ${formatRub(ceilSum)}',
        )
      else
        const _AreaRow(
          label: 'Потолок',
          value: 0,
          customValue: 'нет цен на слоях',
        ),
      if (total > 0)
        _AreaRow(
          label: 'Итого работы',
          value: total,
          customValue: formatRub(total),
          emphasize: true,
        ),
    ];
  }

  List<Widget> _overviewPrepPriceRows({required bool floor}) {
    final layers = _prepLayers(floor: floor);
    if (layers.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      _sectionTitle(floor ? 'Слои пола (подготовка)' : 'Слои потолка (подготовка)'),
      const SizedBox(height: 8),
      for (var i = 0; i < layers.length; i++)
        InkWell(
          onTap: () => _addOrEditPrepLayer(
            floor: floor,
            existing: layers[i],
            index: i,
          ),
          child: _AreaRow(
            label: layers[i].displayName(floor: floor),
            value: layers[i].unitPrice ?? 0,
            customValue: [
              if (layers[i].unitPrice != null && layers[i].unitPrice! > 0)
                formatRub(layers[i].unitPrice!),
              if (priceGroupIsActive(
                layers.map((e) => e.priceGroupId),
                layers[i].priceGroupId,
                unitPrices: layers.map((e) => e.unitPrice),
              ))
                'общая цена',
              if (!layers[i].enabled) 'выкл.',
              'правка',
            ].where((e) => e.isNotEmpty).join(' · '),
          ),
        ),
    ];
  }

  List<Widget> _overviewFloorCoveringRows(Room room, FinishAreas areas) {
    final kind = FloorCoveringKindX.parse(room.floorCoveringKind);
    if (kind == FloorCoveringKind.screed) {
      final depth = double.tryParse(_screedDepthCtrl.text.replaceAll(',', '.')) ??
          room.floorScreedDepthCm;
      final d = depth <= 0 ? defaultScreedDepthCm : depth;
      final vol = screedVolumeM3(areas.floorM2, d);
      final price = floorCoveringUnitPriceOf(room);
      return [
        _AreaRow(
          label: 'Стяжка · объём',
          value: vol,
          customValue: '${vol.toStringAsFixed(3)} м³',
          emphasize: true,
        ),
        _AreaRow(
          label: 'Толщина',
          value: d,
          customValue: '${d.toStringAsFixed(d == d.roundToDouble() ? 0 : 1)} см',
        ),
        if (price != null)
          _AreaRow(
            label: 'Цена работ',
            value: price,
            customValue: '${formatRub(price)}/м³ · ${formatRub(vol * price)}',
          ),
      ];
    }
    return [
      _AreaRow(
        label: kind.labelRu,
        value: areas.floorTiles.toDouble(),
        customValue:
            '${_tileWCtrl.text}×${_tileHCtrl.text} см · ${areas.floorTiles} шт.',
      ),
    ];
  }

  Widget _buildOpeningCard(int i) {
    final o = _openings[i];
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: _placingIndex == i
          ? Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.55)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  o.kind == 'door' ? Icons.door_front_door : Icons.window,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${o.displayName} · ${o.widthCm.round()}×${o.heightCm.round()} см',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Изменить размеры',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _addOrEditOpening(existing: o, index: i),
                ),
                IconButton(
                  tooltip: 'Удалить',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    await _removeOpening(i);
                  },
                ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _duplicateOpening(i),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Ещё такой же'),
                ),
                const Spacer(),
                Text(
                  '${o.areaM2.toStringAsFixed(2)} м²',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            Text(
              o.wallIndex == null
                  ? 'На плане не размещён (учитывается только в площади)'
                  : 'Стена ${o.wallIndex! + 1} · отступ ${o.offsetAlongWallCm.round()} см',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (_placingIndex == i)
                  FilledButton.tonal(
                    onPressed: _finishPlacing,
                    child: const Text('Готово'),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () => setState(() => _placingIndex = i),
                    child: Text(o.wallIndex == null ? 'Разместить' : 'Сдвинуть'),
                  ),
                const SizedBox(width: 8),
                if (o.wallIndex != null)
                  TextButton(
                    onPressed: () => _clearPlacement(i),
                    child: const Text('Убрать с плана'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _finishSkuLine(String matchKey, double areaM2) {
    final sku = resolveFinishSku(sectionKey: matchKey, prices: _prices);
    if (sku.isEmpty) return null;
    return '${areaM2.toStringAsFixed(2)} м² · SKU $sku';
  }

  Widget _buildOverviewTab(Room room, FinishAreas areas, RoomShell3D? shell) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _EditorEntryCard(
          icon: Icons.layers_outlined,
          title: 'Редактор обзора',
          subtitle: 'Слои стен, пол и потолок на одном плане',
          onOpen: () => _openSectionEditor(kind: FinishEditorKind.overview),
        ),
        const SizedBox(height: 16),
        // ARCHIVED: Project vs fact overview card — `_archived/finish_project_vs_fact_ui.dart.txt`
        _sectionTitle('Площади'),
        const SizedBox(height: 8),
        _AreaRow(
          label: 'Периметр',
          value: areas.perimeterM,
          customValue: '${areas.perimeterM.toStringAsFixed(2)} м',
        ),
        _AreaRow(
          label: 'Пол',
          value: areas.floorM2,
          customValue: _finishSkuLine('finish_floor', areas.floorM2),
        ),
        _AreaRow(label: 'Потолок', value: areas.ceilingM2),
        _AreaRow(
          label: 'Стены (до проёмов)',
          value: areas.wallsGrossM2,
          customValue: _finishSkuLine('finish_wall', areas.wallsGrossM2),
        ),
        _AreaRow(label: 'Проёмы', value: -areas.openingsM2),
        _AreaRow(label: 'Стены', value: areas.wallsNetM2, emphasize: true),
        _AreaRow(label: 'Всего отделка', value: areas.totalFinishM2, emphasize: true),
        ..._overviewPriceSummary(room, areas),
        const SizedBox(height: 16),
        _sectionTitle('Напольное покрытие'),
        const SizedBox(height: 8),
        ..._overviewFloorCoveringRows(room, areas),
        ..._overviewPrepPriceRows(floor: true),
        if (areas.wallLayers.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('Слои стен'),
          const SizedBox(height: 8),
          for (var i = 0; i < areas.wallLayers.length; i++)
            InkWell(
              onTap: () {
                final q = areas.wallLayers[i];
                final idx = _wallLayers.indexWhere(
                  (l) =>
                      identical(l, q.layer) ||
                      (l.kind == q.layer.kind &&
                          l.unitPrice == q.layer.unitPrice &&
                          l.priceGroupId == q.layer.priceGroupId),
                );
                _addOrEditLayer(
                  existing: q.layer,
                  index: idx >= 0 ? idx : i,
                );
              },
              child: _AreaRow(
                label: areas.wallLayers[i].layer.displayLabel,
                value: areas.wallLayers[i].areaM2,
                customValue: () {
                  final q = areas.wallLayers[i];
                  final bits = <String>[
                    if (q.layer.kind == FinishLayerKind.tile)
                      '${q.areaM2.toStringAsFixed(2)} м² · ${q.tilesEstimate} шт.',
                    if (q.layer.unitPrice != null && q.layer.unitPrice! > 0)
                      formatRub(q.layer.unitPrice!),
                    if (priceGroupIsActive(
                      areas.wallLayers.map((e) => e.layer.priceGroupId),
                      q.layer.priceGroupId,
                      unitPrices:
                          areas.wallLayers.map((e) => e.layer.unitPrice),
                    ))
                      'общая цена',
                    'правка',
                  ];
                  return bits.join(' · ');
                }(),
              ),
            ),
          _AreaRow(
            label: 'Слои суммарно',
            value: areas.wallLayersTotalM2,
            emphasize: true,
          ),
        ],
        ..._overviewPrepPriceRows(floor: false),
        const SizedBox(height: 20),
        _sectionTitle('3D-оболочка'),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 16 / 10,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF1A2330),
              borderRadius: BorderRadius.circular(12),
            ),
            child: shell == null
                ? const Center(child: Text('Нет контура', style: TextStyle(color: Colors.white54)))
                : GestureDetector(
                    onPanUpdate: (d) {
                      setState(() {
                        _shellYaw += d.delta.dx * 0.012;
                        _shellPitch += d.delta.dy * 0.012;
                      });
                    },
                    child: CustomPaint(
                      painter: IsometricShellPainter(
                        shell: shell,
                        walls: room.walls,
                        yaw: _shellYaw,
                        pitch: _shellPitch,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildWallsTab(Room room) {
    final tile = _firstTileLayer;
    final (wallLen, wallH) = room.walls.isEmpty
        ? (0.0, 0.0)
        : _wallElevationSize(room);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _finishIncludeSwitch(
          value: room.finishIncludeWalls,
          onChanged: (v) => _setFinishInclude(walls: v),
        ),
        const SizedBox(height: 8),
        // ARCHIVED: Project vs fact · контур — `_archived/finish_project_vs_fact_ui.dart.txt`
        Text('Высота до потолка', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _heightCtrl,
          keyboardType: NumericInput.decimalKeyboard,
          inputFormatters: NumericInput.decimalFormatters,
          decoration: const InputDecoration(
            suffixText: 'см',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) {
            setState(() {
              _rebuildWallGrid();
            });
            _scheduleHeightPersist();
          },
          onEditingComplete: _persist,
        ),
        const SizedBox(height: 20),
        _CollapsibleSection(
          title: 'Слои отделки',
          countLabel: '${_wallLayers.length}',
          expanded: _layersSectionExpanded,
          onToggle: () =>
              setState(() => _layersSectionExpanded = !_layersSectionExpanded),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_wallLayers.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'Цены слоёв',
                  icon: const Icon(Icons.payments_outlined, size: 20),
                  onSelected: (v) {
                    if (v == 'group') {
                      _bindSharedWallPrice(all: false);
                    } else if (v == 'all') {
                      _bindSharedWallPrice(all: true);
                    } else if (v == 'auto') {
                      _autofillMissingLayerPrices(onlyEmpty: true);
                    } else if (v == 'auto_all') {
                      _autofillMissingLayerPrices(onlyEmpty: false);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'group',
                      child: Text('Общая цена на несколько слоёв…'),
                    ),
                    PopupMenuItem(
                      value: 'all',
                      child: Text('Одна цена на все слои'),
                    ),
                    PopupMenuItem(
                      value: 'auto',
                      child: Text('Подтянуть пустые из каталога'),
                    ),
                    PopupMenuItem(
                      value: 'auto_all',
                      child: Text('Обновить все из каталога'),
                    ),
                  ],
                ),
              TextButton.icon(
                onPressed: () => _addOrEditLayer(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Слой'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_wallLayers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Нет слоёв'),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: _reorderLayerProxyDecorator,
                  itemCount: _wallLayers.length,
                  onReorderItem: (oldIndex, newIndex) async {
                    final list = _wallLayers.toList();
                    final item = list.removeAt(oldIndex);
                    list.insert(newIndex, item);
                    _syncLayers(list);
                    await _persist();
                  },
                  itemBuilder: (context, i) {
                    final layer = _wallLayers[i];
                    final order = i + 1;
                    final isFirst = i == 0;
                    final isLast = i == _wallLayers.length - 1;
                    final orderHint = isFirst && isLast
                        ? 'Единственный слой'
                        : isFirst
                            ? '↓ снизу (к стене)'
                            : isLast
                                ? '↑ сверху (финиш)'
                                : 'Слой $order из ${_wallLayers.length}';
                    final priceHint = layerPriceSubtitle(layer.unitPrice);
                    final groupActive = priceGroupIsActive(
                      _wallLayers.map((e) => e.priceGroupId),
                      layer.priceGroupId,
                      unitPrices: _wallLayers.map((e) => e.unitPrice),
                    );
                    final groupHint = groupActive ? 'общая цена' : null;
                    return _LayerOrderCard(
                      key: ValueKey(
                        'layer-$i-${layer.kind.id}-${layer.displayLabel}',
                      ),
                      reorderIndex: i,
                      orderLabel: '$order',
                      title: layer.displayLabel,
                      subtitle: [
                        orderHint,
                        if (priceHint.isNotEmpty) priceHint,
                        if (groupHint != null) groupHint,
                      ].join(' · '),
                      priceGroupAccent: groupActive ? layer.priceGroupId : null,
                      enabled: layer.enabled,
                      onEnabledChanged: (v) async {
                        final list = _wallLayers.toList();
                        list[i].enabled = v;
                        _syncLayers(list);
                        await _persist();
                      },
                      onEdit: () =>
                          _addOrEditLayer(existing: layer, index: i),
                      onDelete: () => _removeLayer(i),
                    );
                  },
                ),
            ],
          ),
        ),
        if (tile != null) ...[
          const SizedBox(height: 20),
          Text('Раскладка плитки на стене', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Стена ${_wallElevationIndex + 1}: ${wallLen.round()}×${wallH.round()} см · '
            'целых ${_wallGrid.fullTiles}, резаных ${_wallGrid.cutTiles}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < room.walls.length; i++)
                ChoiceChip(
                  label: Text('${i + 1}'),
                  selected: _wallElevationIndex == i,
                  onSelected: (_) {
                    setState(() {
                      _wallElevationIndex = i;
                      _rebuildWallGrid();
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 1.35,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  final metrics = FloorPlanMetrics.fromRect(wallLen, wallH, size);
                  final wallRect = wallElevationPolygon(wallLen, wallH);
                  final wallOpenings = openingRectsOnWall(
                    wallIndex: _wallElevationIndex,
                    wallLengthCm: wallLen,
                    roomHeightCm: wallH,
                    openings: _openings,
                  );
                  return CustomPaint(
                    painter: WallElevationPainter(
                      walls: wallRect,
                      metrics: metrics,
                      layout: FloorLayoutBuilder.build(
                        walls: wallRect,
                        covering: FloorCoveringKind.tile,
                        pattern: FloorLayingPattern.straight,
                        boardW: tile.tileWidthCm,
                        boardL: tile.tileHeightCm,
                        offsetX: tile.tileOffsetX.toDouble(),
                        offsetY: tile.tileOffsetY.toDouble(),
                      ),
                      openings: wallOpenings,
                      showElevationDims: true,
                      bgColor: CanvasPalette.bg,
                      wallStrokeColor: CanvasPalette.wall,
                      fullTileColor: CanvasPalette.fullTile,
                      cutTileColor: CanvasPalette.cutTile,
                      gridLineColor: CanvasPalette.grid,
                      textColor: CanvasPalette.text,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: 'Отменить',
                onPressed: _wallTileUndo.canUndo ? _undoWallTileOffset : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'Повторить',
                onPressed: _wallTileUndo.canRedo ? _redoWallTileOffset : null,
                icon: const Icon(Icons.redo),
              ),
              const Spacer(),
              Text(
                'Смещение плитки',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Center(
            child: ArrowJoystick(
              size: 100,
              onTick: _nudgeWallTile,
              onRelease: () => _nudgeWallTile(0, 0, finalize: true),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _CollapsibleSection(
          title: 'Проёмы',
          countLabel: '${_openings.length}',
          expanded: _openingsSectionExpanded,
          onToggle: () => setState(
            () => _openingsSectionExpanded = !_openingsSectionExpanded,
          ),
          trailing: TextButton.icon(
            onPressed: () => _addOrEditOpening(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Тип'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_openings.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Нет проёмов'),
                )
              else
                for (var i = 0; i < _openings.length; i++) _buildOpeningCard(i),
              const SizedBox(height: 12),
              Text(
                room.isSpecialSpace ? 'Схема клетки' : 'План размещения',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (room.isSpecialSpace) ...[
                Builder(
                  builder: (ctx) {
                    final geom = _stairSchematicFor(room);
                    if (geom == null) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'У объёма без чертежа нет плана проёмов — только м².',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 280,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: StairSchematicPreview(
                              geometry: geom,
                              finishSides:
                                  room.specialSpace?.stair?.finishSides ?? 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Бок / план / 3D — как в редакторе ЛК. '
                          'Проёмы и размеры правятся там же.',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
                    );
                  },
                ),
              ] else
                AspectRatio(
                  aspectRatio: 1.15,
                  child: OpeningPlanPlacer(
                    walls: room.walls,
                    openings: _openings,
                    placingIndex: _placingIndex,
                    onPlace: (wall, offset) {
                      if (_placingIndex == null) return;
                      _placeOpening(_placingIndex!, wall, offset);
                    },
                    onSelectOpening: (i) => setState(() => _placingIndex = i),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  StairSchematicGeometry? _stairSchematicFor(Room room) {
    final space = room.specialSpace;
    if (space == null || space.kind != SpecialSpaceKind.stairwell) {
      return null;
    }
    try {
      return (space.stair ?? StairwellParams()).buildSchematic();
    } catch (_) {
      return null;
    }
  }

  Widget _buildFloorTab(Room room) {
    final covering = FloorCoveringKindX.parse(room.floorCoveringKind);
    final pattern = FloorLayingPatternX.parse(room.floorLayingPattern);
    final presets = covering == FloorCoveringKind.laminate
        ? laminateBoardPresets
        : floorTilePresets;
    final sizeLabel = covering == FloorCoveringKind.laminate
        ? 'Доска (ширина × длина)'
        : 'Плитка (ширина × длина)';
    final areas = _areas;
    // ARCHIVED: floor ghost (проект vs факт) — `_archived/finish_project_vs_fact_ui.dart.txt`
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _EditorEntryCard(
          icon: Icons.grid_view_outlined,
          title: 'Раскладка пола',
          subtitle: 'Смещение, поворот и размеры резов на плане',
          onOpen: () => _openSectionEditor(kind: FinishEditorKind.floor),
        ),
        const SizedBox(height: 8),
        _finishIncludeSwitch(
          value: room.finishIncludeFloor,
          onChanged: (v) => _setFinishInclude(floor: v),
        ),
        const SizedBox(height: 16),
        Text('Покрытие', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<FloorCoveringKind>(
          showSelectedIcon: false,
          segments: [
            for (final k in FloorCoveringKind.values)
              ButtonSegment(value: k, label: Text(k.labelShortRu)),
          ],
          selected: {covering},
          onSelectionChanged: (s) {
            setState(() {
              room.floorCoveringKind = s.first.id;
              if (s.first == FloorCoveringKind.laminate) {
                room.floorLayingPattern = FloorLayingPattern.brick.id;
                _applyFloorPreset(laminateBoardPresets.first);
              } else if (s.first == FloorCoveringKind.screed) {
                if (_screedDepthCtrl.text.trim().isEmpty) {
                  _screedDepthCtrl.text = defaultScreedDepthCm.round().toString();
                }
              } else {
                room.floorLayingPattern = FloorLayingPattern.straight.id;
                _applyFloorPreset(floorTilePresets.first);
              }
            });
            _persist();
          },
        ),
        const SizedBox(height: 12),
        Text(
          covering == FloorCoveringKind.screed
              ? 'Цена работ стяжки'
              : 'Цена работ покрытия',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        LayerPriceFields(
          priceCtrl: _floorCoveringPriceCtrl,
          section: 'floor',
          suggestName: covering.labelRu,
          layerKindId: covering.id,
          priceUnitLabel:
              covering == FloorCoveringKind.screed ? '₽/м³' : '₽/м²',
          catalogToStoredPrice: covering == FloorCoveringKind.screed
              ? (p) {
                  final d = double.tryParse(
                        _screedDepthCtrl.text.replaceAll(',', '.'),
                      ) ??
                      room.floorScreedDepthCm;
                  return screedCatalogM2ToM3(p, d);
                }
              : null,
          materials: decodeMaterialLinks(room.floorCoveringMaterials),
          onMaterialsChanged: (m) {
            room.floorCoveringMaterials = encodeMaterialLinks(m);
            setState(() {});
            _scheduleHeightPersist();
          },
          onChanged: () {
            _applyHeightFieldsToRoom(room);
            setState(() {});
            _scheduleHeightPersist();
          },
        ),
        if (covering == FloorCoveringKind.screed) ...[
          const SizedBox(height: 16),
          Text('Параметры стяжки', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _screedDepthCtrl,
            keyboardType: NumericInput.decimalKeyboard,
            inputFormatters: NumericInput.decimalFormatters,
            decoration: const InputDecoration(
              labelText: 'Толщина стяжки',
              suffixText: 'см',
              border: OutlineInputBorder(),
              isDense: true,
              helperText: 'Расход: площадь пола × толщина → объём',
            ),
            onChanged: (_) {
              setState(() {});
              _scheduleHeightPersist();
            },
          ),
          const SizedBox(height: 12),
          if (areas != null) ...[
            _AreaRow(label: 'Площадь пола', value: areas.floorM2),
            _AreaRow(
              label: 'Объём стяжки',
              value: screedVolumeM3(
                areas.floorM2,
                double.tryParse(_screedDepthCtrl.text.replaceAll(',', '.')) ??
                    room.floorScreedDepthCm,
              ),
              customValue: () {
                final d = double.tryParse(
                      _screedDepthCtrl.text.replaceAll(',', '.'),
                    ) ??
                    room.floorScreedDepthCm;
                final depth = d <= 0 ? defaultScreedDepthCm : d;
                final vol = screedVolumeM3(areas.floorM2, depth);
                return '${vol.toStringAsFixed(3)} м³';
              }(),
              emphasize: true,
            ),
          ],
          const SizedBox(height: 16),
          Text('План пола', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 1.15,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  final metrics = FloorPlanMetrics.fromWalls(room.walls, size);
                  final layout = FloorLayoutBuilder.build(
                    walls: room.walls,
                    covering: FloorCoveringKind.screed,
                    pattern: FloorLayingPattern.straight,
                    boardW: 60,
                    boardL: 60,
                    offsetX: 0,
                    offsetY: 0,
                  );
                  return CustomPaint(
                    painter: FloorPlanPainter(
                      walls: room.walls,
                      metrics: metrics,
                      layout: layout,
                      showCutDims: false,
                    ),
                  );
                },
              ),
            ),
          ),
        ] else ...[
          if (covering == FloorCoveringKind.laminate) ...[
            const SizedBox(height: 16),
            Text('Вид укладки', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in FloorLayingPattern.values)
                  ChoiceChip(
                    label: Text(p.labelRu),
                    showCheckmark: true,
                    selected: pattern == p,
                    onSelected: (_) {
                      setState(() {
                        room.floorLayingPattern = p.id;
                      });
                      _persist();
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(sizeLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in presets)
                ChoiceChip(
                  label: Text('${p.$1.round()}×${p.$2.round()}'),
                  showCheckmark: true,
                  selected: _floorPresetSelected(p),
                  onSelected: (_) {
                    setState(() {
                      _applyFloorPreset(p);
                    });
                    _persist();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tileWCtrl,
                  keyboardType: NumericInput.decimalKeyboard,
                  inputFormatters: NumericInput.decimalFormatters,
                  decoration: InputDecoration(
                    labelText: covering == FloorCoveringKind.laminate
                        ? 'Ширина доски'
                        : 'Ширина',
                    suffixText: 'см',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _onFloorTileChanged(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('×'),
              ),
              Expanded(
                child: TextField(
                  controller: _tileHCtrl,
                  keyboardType: NumericInput.decimalKeyboard,
                  inputFormatters: NumericInput.decimalFormatters,
                  decoration: InputDecoration(
                    labelText: covering == FloorCoveringKind.laminate
                        ? 'Длина доски'
                        : 'Длина',
                    suffixText: 'см',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _onFloorTileChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ARCHIVED: Project vs fact · пол card — `_archived/finish_project_vs_fact_ui.dart.txt`
          Text(
            () {
              final layout = FloorLayoutBuilder.build(
                walls: room.walls,
                covering: covering,
                pattern: pattern,
                boardW: double.tryParse(_tileWCtrl.text.replaceAll(',', '.')) ??
                    room.finishTileWidthCm,
                boardL: double.tryParse(_tileHCtrl.text.replaceAll(',', '.')) ??
                    room.finishTileHeightCm,
                offsetX: room.floorGridOffsetX.toDouble(),
                offsetY: room.floorGridOffsetY.toDouble(),
                rotationDeg: room.floorLayoutRotationDeg,
              );
              return 'Целых: ${layout.fullCount}  ·  Резаных: ${layout.cutCount}  ·  '
                  'Смещение: ${room.floorGridOffsetX}×${room.floorGridOffsetY} см  ·  '
                  'Поворот: ${room.floorLayoutRotationDeg}°';
            }(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 20),
        _buildPrepLayersSection(floor: true),
      ],
    );
  }

  Widget _buildCeilingTab(Room room, FinishAreas areas) {
    final ceilingGrid = _buildCeilingGrid(room);
    final (ef, ec) = ceilingGrid.effectiveTileCounts;
    final project = _project;
    final effective = project == null
        ? (room.materialsCeiling ?? 'Армстронг', room.materialsSusp ?? 'Подвес 0,5', room.materialsCell ?? '50x50')
        : roomEffectiveConfig(room, project);
    var override = room.materialsOverride;
    var ceiling = effective.$1;
    var susp = effective.$2;
    var cell = effective.$3;
    if (!_ceilingOptions.contains(ceiling)) ceiling = _ceilingOptions.first;
    if (!_suspOptions.contains(susp)) susp = _suspOptions.first;
    if (!_cellOptions.contains(cell)) cell = _cellOptions.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _EditorEntryCard(
          icon: Icons.grid_on_outlined,
          title: 'Раскладка потолка',
          subtitle: 'Сетка, направляющие, свет и размеры плит',
          onOpen: () => _openSectionEditor(kind: FinishEditorKind.ceiling),
        ),
        const SizedBox(height: 8),
        _finishIncludeSwitch(
          value: room.finishIncludeCeiling,
          onChanged: (v) => _setFinishInclude(ceiling: v),
        ),
        const SizedBox(height: 16),
        Text('Раскладка потолка', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _AreaRow(label: 'Смещение сетки', value: 0, customValue: '${room.gridOffsetX}×${room.gridOffsetY} см'),
        _AreaRow(label: 'Целых плит', value: ef.toDouble(), customValue: '$ef шт.'),
        _AreaRow(label: 'Резаных плит', value: ec.toDouble(), customValue: '$ec шт.'),
        _AreaRow(
          label: 'Закупка плит',
          value: ceilingPurchaseCount(room).toDouble(),
          customValue: '${ceilingPurchaseCount(room)} шт. (с запасом)',
        ),
        _AreaRow(
          label: 'Светильников',
          value: room.lightFixtures.length.toDouble(),
          customValue: '${room.lightFixtures.length} шт.',
        ),
        _AreaRow(label: 'Площадь потолка', value: areas.ceilingM2),
        const SizedBox(height: 24),
        Text('Материалы потолка', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Свой набор для этой комнаты'),
          subtitle: Text(
            override
                ? 'Переопределяет материалы проекта'
                : 'Берутся из проекта; смена ниже обновит проект',
          ),
          value: override,
          onChanged: (v) async {
            override = v;
            await _saveCeilingMaterials(
              override: override,
              ceiling: ceiling,
              susp: susp,
              cell: cell,
            );
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('ceil-$ceiling'),
          initialValue: ceiling,
          decoration: const InputDecoration(labelText: 'Тип потолка', isDense: true, border: OutlineInputBorder()),
          items: [
            for (final o in _ceilingOptions) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) async {
            if (v == null) return;
            await _saveCeilingMaterials(
              override: room.materialsOverride,
              ceiling: v,
              susp: susp,
              cell: cell,
            );
            // Re-suggest catalog price for the new system type if empty.
            if (_ceilingSystemPriceCtrl.text.trim().isEmpty) {
              await _autofillMissingLayerPrices(onlyEmpty: true);
            }
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Цена монтажа системы',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        LayerPriceFields(
          priceCtrl: _ceilingSystemPriceCtrl,
          section: 'ceiling',
          suggestName: ceiling,
          layerKindId: 'system',
          materials: decodeMaterialLinks(room.ceilingSystemMaterials),
          onMaterialsChanged: (m) {
            room.ceilingSystemMaterials = encodeMaterialLinks(m);
            setState(() {});
            _scheduleHeightPersist();
          },
          onChanged: () {
            _applyHeightFieldsToRoom(room);
            setState(() {});
            _scheduleHeightPersist();
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey('susp-$susp'),
          initialValue: susp,
          decoration: const InputDecoration(labelText: 'Подвес', isDense: true, border: OutlineInputBorder()),
          items: [
            for (final o in _suspOptions) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) async {
            if (v == null) return;
            await _saveCeilingMaterials(
              override: room.materialsOverride,
              ceiling: ceiling,
              susp: v,
              cell: cell,
            );
          },
        ),
        if (ceiling != 'Армстронг') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('cell-$cell'),
            initialValue: cell,
            decoration: const InputDecoration(labelText: 'Ячейка', isDense: true, border: OutlineInputBorder()),
            items: [
              for (final o in _cellOptions) DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await _saveCeilingMaterials(
                override: room.materialsOverride,
                ceiling: ceiling,
                susp: susp,
                cell: v,
              );
            },
          ),
        ],
        if (project != null) ...[
          const SizedBox(height: 16),
          Text('Полная спецификация потолка', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                children: [
                  for (final e in sortedMaterialEntries(calculateRoomMaterials(room, project)))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.key,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    height: 1.25,
                                  ),
                            ),
                          ),
                          Text(
                            '${e.value} шт',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _buildPrepLayersSection(floor: false),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _openFinishVedomost(scope: FinishVedomostScope.ceiling),
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Ведомость отделки'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = _room;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Отделка')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }
    if (room.isSpecialSpace && !widget.specialLayersOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await openFinishRoom(
          context,
          projectId: widget.projectId,
          roomId: widget.roomId,
          replaceCurrent: true,
        );
      });
      return Scaffold(
        appBar: AppBar(title: Text(room.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (room.isSpecialSpace && widget.specialLayersOnly) {
      return ScreenScaffold(
        appBar: AppBar(
          title: Text(widget.editorTitle ?? 'Слои · ${room.name}'),
        ),
        body: _buildWallsTab(room),
      );
    }
    if (!room.hasLayout) {
      // Empty hub is obsolete — open manual editor; capture is in its AppBar.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await openFinishRoomCanvas(
          context,
          projectId: widget.projectId,
          roomId: widget.roomId,
          hasLayout: false,
          replaceCurrent: true,
        );
      });
      return Scaffold(
        appBar: AppBar(title: Text(room.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final areas = _areas!;
    final height = double.tryParse(_heightCtrl.text.replaceAll(',', '.')) ?? room.ceilingHeightCm;
    final shell = RoomShell3D.fromWalls(
      room.walls,
      heightCm: height,
      openings: _openings,
    );

    final locked = widget.lockedTabIndex?.clamp(0, 3);
    final isEditor = locked != null;

    Widget bodyForTab(int i) {
      switch (i) {
        case 1:
          return _buildWallsTab(room);
        case 2:
          return _buildFloorTab(room);
        case 3:
          return _buildCeilingTab(room, areas);
        default:
          return _buildOverviewTab(room, areas, shell);
      }
    }

    if (isEditor) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await _persist();
          if (mounted) Navigator.pop(context);
        },
        child: ScreenScaffold(
          backgroundBlur: 0.5,
          dimOpacity: 0.58,
          appBar: AppBar(
            title: Text(widget.editorTitle ?? 'Редактор'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                await _persist();
                if (!mounted) return;
                Navigator.pop(context);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => _openFinishVedomost(
                  scope: FinishVedomostScopeX.fromRoomTab(locked),
                ),
                child: const Text('Ведомость'),
              ),
            ],
          ),
          body: bodyForTab(locked),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await _persist();
          if (mounted) Navigator.pop(context);
        },
        child: ScreenScaffold(
        backgroundBlur: 0.5,
        dimOpacity: 0.58,
        appBar: AppBar(
          title: Text(room.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _persist();
              if (!mounted) return;
              Navigator.pop(context);
            },
          ),
          actions: [
            Builder(
              builder: (tabCtx) => TextButton(
                onPressed: () => _openFinishVedomost(tabContext: tabCtx),
                child: const Text('Ведомость'),
              ),
            ),
            TextButton(
              onPressed: () async {
                await _persist();
                if (!mounted) return;
                await openRoomModule(
                  context,
                  projectId: widget.projectId,
                  roomId: widget.roomId,
                  module: AppModule.documentation,
                );
              },
              child: const Text('Документация'),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            tabs: const [
              Tab(text: 'Обзор'),
              Tab(text: 'Стены'),
              Tab(text: 'Пол'),
              Tab(text: 'Потолок'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            bodyForTab(0),
            bodyForTab(1),
            bodyForTab(2),
            bodyForTab(3),
          ],
        ),
      ),
    ),
    );
  }

  // ARCHIVED: _hasFloorDelta / _hasCeilingDelta / _hasWallDelta / _finishTab alerts
  // — see `_archived/finish_project_vs_fact_ui.dart.txt`
}

class _EditorEntryCard extends StatelessWidget {
  const _EditorEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Открыть'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaRow extends StatelessWidget {
  const _AreaRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.customValue,
  });

  final String label;
  final double value;
  final bool emphasize;
  final String? customValue;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    final style = emphasize
        ? Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: on,
          )
        : Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: on,
            height: 1.3,
          );
    final text = customValue ?? '${value.toStringAsFixed(2)} м²';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            text,
            style: style?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Keeps drag proxy transparent (default Material elevation tints the row).
Widget _reorderLayerProxyDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return Material(
    type: MaterialType.transparency,
    color: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    child: child,
  );
}

/// Compact layer row: drag+number stacked, title centered, actions flush right.
class _LayerOrderCard extends StatelessWidget {
  const _LayerOrderCard({
    super.key,
    this.reorderIndex,
    required this.orderLabel,
    required this.title,
    required this.subtitle,
    this.enabled,
    this.onEnabledChanged,
    this.onEdit,
    this.onDelete,
    this.locked = false,
    this.priceGroupAccent,
  });

  final int? reorderIndex;
  final String orderLabel;
  final String title;
  final String subtitle;
  final bool? enabled;
  final ValueChanged<bool>? onEnabledChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool locked;

  /// Same non-null id → shared price group (left accent bar).
  final String? priceGroupAccent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final orderBadge = CircleAvatar(
      radius: 11,
      backgroundColor: locked
          ? scheme.secondaryContainer
          : scheme.primaryContainer,
      child: Text(
        orderLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: locked
              ? scheme.onSecondaryContainer
              : scheme.onPrimaryContainer,
        ),
      ),
    );

    Widget leading;
    if (locked || reorderIndex == null) {
      leading = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 18, color: scheme.outline),
          const SizedBox(height: 2),
          orderBadge,
        ],
      );
    } else {
      leading = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: reorderIndex!,
            child: Icon(Icons.drag_handle, size: 20, color: scheme.outline),
          ),
          const SizedBox(height: 2),
          orderBadge,
        ],
      );
    }

    final borderColor = scheme.outlineVariant.withValues(alpha: 0.35);
    final groupColor = priceGroupAccent != null && priceGroupAccent!.isNotEmpty
        ? scheme.tertiary
        : null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: groupColor ?? borderColor),
        color: groupColor?.withValues(alpha: 0.06),
      ),
      foregroundDecoration: groupColor == null
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(color: groupColor, width: 4),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 2, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 36, child: leading),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (!locked) ...[
              if (enabled != null && onEnabledChanged != null)
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: enabled!,
                    onChanged: onEnabledChanged,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              if (onEdit != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
              if (onDelete != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onDelete,
                ),
            ] else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  'финиш',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    required this.title,
    required this.countLabel,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String countLabel;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      countLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: child,
            ),
        ],
      ),
    );
  }
}

