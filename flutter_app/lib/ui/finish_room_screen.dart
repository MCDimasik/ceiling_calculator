import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/ceiling_grid.dart';
import '../domain/finish_model.dart';
import '../domain/floor_covering.dart';
import '../domain/floor_layout.dart';
import '../domain/models.dart';
import '../domain/project_materials.dart';
import 'layout_screen.dart';
import 'materials_result_screen.dart';
import 'widgets/controls.dart';
import 'widgets/finish_painters.dart';
import 'widgets/floor_rotate_control.dart';
import 'widgets/numeric_input.dart';
import 'widgets/opening_plan_placer.dart';
import 'widgets/screen_scaffold.dart';

/// Finish module: height, openings, floor tiles, areas + isometric shell.
class FinishRoomScreen extends StatefulWidget {
  const FinishRoomScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<FinishRoomScreen> createState() => _FinishRoomScreenState();
}

class _FinishRoomScreenState extends State<FinishRoomScreen> {
  Room? _room;
  Project? _project;
  bool _loading = true;
  final _heightCtrl = TextEditingController();
  final _tileWCtrl = TextEditingController();
  final _tileHCtrl = TextEditingController();
  final _floorGrid = CeilingGrid();
  final _wallGrid = CeilingGrid();

  double _floorOffX = 0;
  double _floorOffY = 0;
  int _wallElevationIndex = 0;
  double _shellYaw = 0.4;
  double _shellPitch = 0.55;

  /// Opening type currently being placed on the 2D plan (`null` = view only).
  int? _placingIndex;

  static const _ceilingOptions = ['Армстронг', 'Грильято', 'GL'];
  static const _suspOptions = ['Подвес 0,5', 'Подвес 1', 'Подвес 1,5'];
  static const _cellOptions = ['50x50', '75x75', '100x100'];

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    _tileWCtrl.dispose();
    _tileHCtrl.dispose();
    super.dispose();
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
      if (room != null) {
        _heightCtrl.text = room.ceilingHeightCm.round().toString();
        _tileWCtrl.text = room.finishTileWidthCm.round().toString();
        _tileHCtrl.text = room.finishTileHeightCm.round().toString();
        _floorOffX = room.floorGridOffsetX.toDouble();
        _floorOffY = room.floorGridOffsetY.toDouble();
        _rebuildFloorGrid();
        _rebuildWallGrid();
      }
    });
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
    if (room == null || !room.hasLayout) return null;
    final h = double.tryParse(_heightCtrl.text.replaceAll(',', '.')) ?? room.ceilingHeightCm;
    final tw = double.tryParse(_tileWCtrl.text.replaceAll(',', '.')) ?? room.finishTileWidthCm;
    final th = double.tryParse(_tileHCtrl.text.replaceAll(',', '.')) ?? room.finishTileHeightCm;
    return FinishCalculator.compute(
      walls: room.walls,
      heightCm: h,
      openings: _openings,
      tileWidthCm: tw,
      tileHeightCm: th,
      wallLayers: _wallLayers,
    );
  }

  void _rebuildFloorGrid() {
    final room = _room;
    if (room == null || !room.hasLayout) return;
    final tw = double.tryParse(_tileWCtrl.text.replaceAll(',', '.')) ?? room.finishTileWidthCm;
    final th = double.tryParse(_tileHCtrl.text.replaceAll(',', '.')) ?? room.finishTileHeightCm;
    _floorGrid.setCellSizeWH(tw, th);
    _floorGrid.setOffset(_floorOffX, _floorOffY);
    _floorGrid.rebuild(
      roomPoints: pointsFromWalls(room.walls),
      walls: room.walls,
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
    final room = _room;
    if (room == null) return;
    room.ceilingHeightCm =
        double.tryParse(_heightCtrl.text.replaceAll(',', '.')) ?? room.ceilingHeightCm;
    room.finishTileWidthCm =
        double.tryParse(_tileWCtrl.text.replaceAll(',', '.')) ?? room.finishTileWidthCm;
    room.finishTileHeightCm =
        double.tryParse(_tileHCtrl.text.replaceAll(',', '.')) ?? room.finishTileHeightCm;
    room.floorGridOffsetX = _floorOffX.round();
    room.floorGridOffsetY = _floorOffY.round();
    await AppScope.of(context).projects.updateRoom(room);
  }

  void _syncOpenings(List<RoomOpening> list) {
    final room = _room;
    if (room == null) return;
    setState(() => room.openings = list.map((o) => o.toJson()).toList());
  }

  void _syncLayers(List<FinishLayer> list) {
    final room = _room;
    if (room == null) return;
    setState(() {
      room.wallFinishLayers = list.map((o) => o.toJson()).toList();
      _rebuildWallGrid();
    });
  }

  void _onFloorTileChanged() {
    setState(_rebuildFloorGrid);
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

  void _nudgeFloor(double dx, double dy, {bool finalize = false}) {
    final room = _room;
    final tw = double.tryParse(_tileWCtrl.text.replaceAll(',', '.')) ??
        room?.finishTileWidthCm ??
        60;
    final th = double.tryParse(_tileHCtrl.text.replaceAll(',', '.')) ??
        room?.finishTileHeightCm ??
        60;
    setState(() {
      _floorOffX = _wrapOffset(_floorOffX + dx, tw);
      _floorOffY = _wrapOffset(_floorOffY + dy, th);
      _rebuildFloorGrid();
    });
    if (finalize) _persist();
  }

  static double _wrapOffset(double v, double period) {
    if (period <= 0) return 0;
    var x = v % period;
    if (x < 0) x += period;
    return x;
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
    if (finalize) _persist();
  }

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
    final qtyCtrl = TextEditingController(text: (existing?.quantity ?? 1).toString());
    final sillCtrl = TextEditingController(
      text: (existing?.sillHeightCm ?? (kind == 'window' ? 90 : 0)).round().toString(),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(existing == null ? 'Тип проёма' : 'Изменить проём'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                          if (existing == null) {
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
                      decoration: const InputDecoration(
                        labelText: 'Название (необязательно)',
                        hintText: 'Входная / Межкомнатная…',
                        isDense: true,
                      ),
                    ),
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
                    const SizedBox(height: 8),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: NumericInput.integerKeyboard,
                      inputFormatters: NumericInput.integerFormatters,
                      decoration: const InputDecoration(
                        labelText: 'Количество одинаковых',
                        helperText: 'Размещение — на плане ниже',
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
    if (ok != true || !mounted) return;

    final next = RoomOpening(
      kind: kind,
      label: labelCtrl.text.trim().isEmpty ? null : labelCtrl.text.trim(),
      widthCm: double.tryParse(wCtrl.text) ?? 0,
      heightCm: double.tryParse(hCtrl.text) ?? 0,
      quantity: math.max(1, int.tryParse(qtyCtrl.text) ?? 1),
      wallIndex: existing?.wallIndex,
      offsetAlongWallCm: existing?.offsetAlongWallCm ?? 0,
      sillHeightCm: double.tryParse(sillCtrl.text) ?? 0,
    );
    final list = _openings.toList();
    if (index != null) {
      list[index] = next;
      _syncOpenings(list);
      await _persist();
    } else {
      // Auto-place on the topmost wall, centered.
      final placed = _defaultOpeningPlacement(next);
      list.add(placed);
      _syncOpenings(list);
      await _persist();
      setState(() => _placingIndex = list.length - 1);
    }
  }

  /// Center of the wall with the highest average Y (top of the plan).
  RoomOpening _defaultOpeningPlacement(RoomOpening opening) {
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
    final start = ((len - opening.widthCm) / 2)
        .clamp(0.0, math.max(0.0, len - opening.widthCm))
        .toDouble();
    return RoomOpening(
      kind: opening.kind,
      label: opening.label,
      widthCm: opening.widthCm,
      heightCm: opening.heightCm,
      quantity: opening.quantity,
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
    _syncOpenings(list);
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

  Future<void> _setQuantity(int index, int qty) async {
    final list = _openings.toList();
    if (index < 0 || index >= list.length) return;
    list[index].quantity = math.max(1, qty);
    _syncOpenings(list);
    await _persist();
  }

  Future<void> _removeOpening(int index) async {
    final list = _openings.toList()..removeAt(index);
    _syncOpenings(list);
    await _persist();
  }

  Future<void> _addOrEditLayer({FinishLayer? existing, int? index}) async {
    var kind = existing?.kind ?? FinishLayerKind.plaster;
    var coats = existing?.paintCoats.clamp(1, 3) ?? 2;
    final twCtrl = TextEditingController(
      text: (existing?.tileWidthCm ?? 60).round().toString(),
    );
    final thCtrl = TextEditingController(
      text: (existing?.tileHeightCm ?? 60).round().toString(),
    );

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
                                labelText: 'Высота',
                                suffixText: 'см',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
    if (ok != true || !mounted) return;

    final next = FinishLayer(
      kind: kind,
      paintCoats: coats,
      tileWidthCm: double.tryParse(twCtrl.text) ?? 60,
      tileHeightCm: double.tryParse(thCtrl.text) ?? 60,
      tileOffsetX: existing?.tileOffsetX ?? 0,
      tileOffsetY: existing?.tileOffsetY ?? 0,
      enabled: existing?.enabled ?? true,
    );
    final list = _wallLayers.toList();
    if (index != null) {
      list[index] = next;
    } else {
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
                  tooltip: 'Удалить тип',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    if (_placingIndex == i) setState(() => _placingIndex = null);
                    await _removeOpening(i);
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Text('Кол-во'),
                IconButton(
                  onPressed: () => _setQuantity(i, o.quantity - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('${o.quantity}', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  onPressed: () => _setQuantity(i, o.quantity + 1),
                  icon: const Icon(Icons.add_circle_outline),
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
                  : 'Стена ${o.wallIndex! + 1} · отступ ${o.offsetAlongWallCm.round()} см'
                      '${o.quantity > 1 ? ' · ×${o.quantity}' : ''}',
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

  Widget _buildOverviewTab(Room room, FinishAreas areas, RoomShell3D? shell) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('Площади', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _AreaRow(
          label: 'Периметр',
          value: areas.perimeterM,
          customValue: '${areas.perimeterM.toStringAsFixed(2)} м',
        ),
        _AreaRow(label: 'Пол', value: areas.floorM2),
        _AreaRow(label: 'Потолок', value: areas.ceilingM2),
        _AreaRow(label: 'Стены (до проёмов)', value: areas.wallsGrossM2),
        _AreaRow(label: 'Проёмы', value: -areas.openingsM2),
        _AreaRow(label: 'Стены (нетто)', value: areas.wallsNetM2, emphasize: true),
        _AreaRow(label: 'Всего отделка', value: areas.totalFinishM2, emphasize: true),
        const SizedBox(height: 8),
        Text(
          '${FloorCoveringKindX.parse(_room?.floorCoveringKind).labelRu} '
          '${_tileWCtrl.text}×${_tileHCtrl.text}: ${areas.floorTiles} шт.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (areas.wallLayers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Слои стен', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final q in areas.wallLayers)
            _AreaRow(
              label: q.layer.displayLabel,
              value: q.areaM2,
              customValue: q.layer.kind == FinishLayerKind.tile
                  ? '${q.areaM2.toStringAsFixed(2)} м² · ~${q.tilesEstimate} шт.'
                  : null,
            ),
          _AreaRow(
            label: 'Слои суммарно',
            value: areas.wallLayersTotalM2,
            emphasize: true,
          ),
        ],
        const SizedBox(height: 20),
        Text('3D-оболочка', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Те же координаты, что на плане: стена + отступ + высота от пола.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          'Потяните пальцем, чтобы вращать. Для телефона это лёгкая отрисовка (оболочка без тяжёлого 3D-движка).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
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
          },
          onEditingComplete: _persist,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text('Слои отделки стен', style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: () => _addOrEditLayer(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Слой'),
            ),
          ],
        ),
        Text(
          'Порядок снизу вверх: демонтаж → штукатурка → … → финиш. '
          'Краска: 1–3 слоя. Плитка: раскладка на выбранной стене ниже.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_wallLayers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Пока нет слоёв — добавьте базовые виды отделки'),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
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
              return Card(
                key: ValueKey('layer-$i-${layer.kind.id}-${layer.displayLabel}'),
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle),
                  ),
                  title: Text(layer.displayLabel),
                  subtitle: Text(
                    layer.kind == FinishLayerKind.paint
                        ? 'Покрытие ×${layer.coats} от площади стен нетто'
                        : layer.kind == FinishLayerKind.tile
                            ? 'Раскладка на развёртке стены'
                            : 'Площадь = стены нетто · тяните за ≡',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _addOrEditLayer(existing: layer, index: i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _removeLayer(i),
                      ),
                    ],
                  ),
                ),
              );
            },
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
                  return CustomPaint(
                    painter: FloorPlanPainter(
                      walls: [
                        [0, 0, wallLen, 0],
                        [wallLen, 0, wallLen, wallH],
                        [wallLen, wallH, 0, wallH],
                        [0, wallH, 0, 0],
                      ],
                      metrics: metrics,
                      layout: FloorLayoutBuilder.build(
                        walls: [
                          [0, 0, wallLen, 0],
                          [wallLen, 0, wallLen, wallH],
                          [wallLen, wallH, 0, wallH],
                          [0, wallH, 0, 0],
                        ],
                        covering: FloorCoveringKind.tile,
                        pattern: FloorLayingPattern.straight,
                        boardW: tile.tileWidthCm,
                        boardL: tile.tileHeightCm,
                        offsetX: tile.tileOffsetX.toDouble(),
                        offsetY: tile.tileOffsetY.toDouble(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: ArrowJoystick(
              size: 100,
              onTick: _nudgeWallTile,
              onRelease: () => _nudgeWallTile(0, 0, finalize: true),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text('Типы дверей и окон', style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: () => _addOrEditOpening(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Тип'),
            ),
          ],
        ),
        Text(
          'Создайте тип → разместите на плане тапом по стене. '
          'Несколько штук одного типа встают вдоль стены автоматически.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_openings.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Пока нет проёмов'),
          ),
        for (var i = 0; i < _openings.length; i++) _buildOpeningCard(i),
        const SizedBox(height: 16),
        Text('План размещения', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          _placingIndex == null
              ? 'Нажмите «Разместить» у типа или коснитесь метки на плане.'
              : 'Режим размещения: ${_openings[_placingIndex!].displayName}. Коснитесь стены.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
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
    );
  }

  Widget _buildFloorTab(Room room) {
    final covering = FloorCoveringKindX.parse(room.floorCoveringKind);
    final pattern = FloorLayingPatternX.parse(room.floorLayingPattern);
    final presets = covering == FloorCoveringKind.laminate
        ? laminateBoardPresets
        : floorTilePresets;
    final sizeLabel = covering == FloorCoveringKind.laminate
        ? 'Доска (ширина × длина)'
        : 'Плитка (Ш × В)';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('Покрытие', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<FloorCoveringKind>(
          showSelectedIcon: false,
          segments: [
            for (final k in FloorCoveringKind.values)
              ButtonSegment(value: k, label: Text(k.labelRu)),
          ],
          selected: {covering},
          onSelectionChanged: (s) {
            setState(() {
              room.floorCoveringKind = s.first.id;
              if (s.first == FloorCoveringKind.laminate) {
                room.floorLayingPattern = FloorLayingPattern.brick.id;
                _applyFloorPreset(laminateBoardPresets.first);
              } else {
                room.floorLayingPattern = FloorLayingPattern.straight.id;
                _applyFloorPreset(floorTilePresets.first);
              }
              _rebuildFloorGrid();
            });
            _persist();
          },
        ),
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
                      _rebuildFloorGrid();
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
                    _rebuildFloorGrid();
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
                  labelText: covering == FloorCoveringKind.laminate ? 'Ширина доски' : 'Ширина',
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
                  labelText: covering == FloorCoveringKind.laminate ? 'Длина доски' : 'Высота',
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
              offsetX: _floorOffX,
              offsetY: _floorOffY,
              rotationDeg: room.floorLayoutRotationDeg,
            );
            return 'Целых: ${layout.fullCount}  ·  Резаных: ${layout.cutCount}  ·  '
                'Смещение: ${_floorOffX.round()}×${_floorOffY.round()} см  ·  '
                'Поворот: ${room.floorLayoutRotationDeg}°';
          }(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            AspectRatio(
              aspectRatio: 1.15,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, constraints.maxHeight);
                    final metrics = FloorPlanMetrics.fromWalls(room.walls, size);
                    final bw = double.tryParse(_tileWCtrl.text.replaceAll(',', '.')) ??
                        room.finishTileWidthCm;
                    final bl = double.tryParse(_tileHCtrl.text.replaceAll(',', '.')) ??
                        room.finishTileHeightCm;
                    final layout = FloorLayoutBuilder.build(
                      walls: room.walls,
                      covering: covering,
                      pattern: pattern,
                      boardW: bw,
                      boardL: bl,
                      offsetX: _floorOffX,
                      offsetY: _floorOffY,
                      rotationDeg: room.floorLayoutRotationDeg,
                    );
                    return CustomPaint(
                      painter: FloorPlanPainter(
                        walls: room.walls,
                        metrics: metrics,
                        layout: layout,
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: FloorRotateControl(
                rotationDeg: room.floorLayoutRotationDeg,
                onRotationChanged: (deg) {
                  setState(() => room.floorLayoutRotationDeg = deg);
                },
                onPersist: _persist,
                onReset: () {
                  setState(() => room.floorLayoutRotationDeg = 0);
                  _persist();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: ArrowJoystick(
            size: 108,
            onTick: _nudgeFloor,
            onRelease: () => _nudgeFloor(0, 0, finalize: true),
          ),
        ),
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
        Text(
          'Раскладка и материалы потолка живут в одной комнате: '
          'правки здесь видны в «Расчёте материалов», и наоборот.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Text('Раскладка потолка', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _AreaRow(label: 'Смещение сетки', value: 0, customValue: '${room.gridOffsetX}×${room.gridOffsetY} см'),
        _AreaRow(label: 'Целых плит', value: ef.toDouble(), customValue: '$ef шт.'),
        _AreaRow(label: 'Резаных плит', value: ec.toDouble(), customValue: '$ec шт.'),
        _AreaRow(
          label: 'Светильников',
          value: room.lightFixtures.length.toDouble(),
          customValue: '${room.lightFixtures.length} шт.',
        ),
        _AreaRow(label: 'Площадь потолка', value: areas.ceilingM2),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LayoutScreen(
                  projectId: widget.projectId,
                  roomId: widget.roomId,
                ),
              ),
            );
            if (mounted) await _load();
          },
          icon: const Icon(Icons.grid_view),
          label: const Text('Открыть раскладку потолка'),
        ),
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => MaterialsResultScreen(
                  projectId: widget.projectId,
                  roomId: widget.roomId,
                ),
              ),
            );
            if (mounted) await _load();
          },
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Открыть расчёт материалов'),
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
    if (!room.hasLayout) {
      return Scaffold(
        appBar: AppBar(title: Text(room.name)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Сначала задайте контур комнаты в разделе «Расчет раскладки потолка».',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final areas = _areas!;
    final height = double.tryParse(_heightCtrl.text.replaceAll(',', '.')) ?? room.ceilingHeightCm;
    final shell = RoomShell3D.fromWalls(
      room.walls,
      heightCm: height,
      openings: _openings,
    );

    return DefaultTabController(
      length: 4,
      child: ScreenScaffold(
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
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Обзор'),
              Tab(text: 'Стены'),
              Tab(text: 'Пол'),
              Tab(text: 'Потолок'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildOverviewTab(room, areas, shell),
            _buildWallsTab(room),
            _buildFloorTab(room),
            _buildCeilingTab(room, areas),
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
    final style = emphasize
        ? Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;
    final text = customValue ?? '${value.toStringAsFixed(2)} м²';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(text, style: style),
        ],
      ),
    );
  }
}

