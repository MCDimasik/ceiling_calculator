import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/project_repository.dart';
import '../domain/ceiling_grid.dart';
import '../domain/dimension_lines.dart';
import '../domain/finish_model.dart';
import '../domain/floor_covering.dart';
import '../domain/floor_layout.dart';
import '../domain/models.dart';
import '../domain/project_materials.dart';
import '../domain/wall_geometry.dart';
import 'room_editor_screen.dart';
import 'room_navigation.dart';
import 'widgets/canvas_palette.dart';
import 'widgets/controls.dart';
import 'widgets/finish_painters.dart';
import 'widgets/numeric_input.dart';
import 'widgets/screen_scaffold.dart';

enum _OvMoveTarget { none, opening, floor, ceiling }

/// Room overview editor: layered 2D/3D with layout-style bottom bar.
class FinishOverviewEditorScreen extends StatefulWidget {
  const FinishOverviewEditorScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<FinishOverviewEditorScreen> createState() =>
      _FinishOverviewEditorScreenState();
}

class _FinishOverviewEditorScreenState extends State<FinishOverviewEditorScreen> {
  Room? _room;
  ProjectRepository? _projects;
  bool _loading = true;
  bool _view3d = false;
  bool _showWalls = true;
  bool _showFloor = true;
  bool _showCeiling = true;
  bool _showOpenings = true;
  double _yaw = 0.4;
  double _pitch = 0.55;
  Size? _view3dSize;

  final _transform = TransformationController();
  FloorPlanMetrics? _metrics;

  _OvMoveTarget _moveTarget = _OvMoveTarget.none;
  int? _selectedOpeningIndex;
  int? _placingIndex;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _onTransform() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
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
    if (!mounted) return;
    setState(() {
      _room = room;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    final room = _room;
    final projects = _projects;
    if (room == null || projects == null) return;
    await projects.updateRoom(room);
  }

  List<RoomOpening> get _openings {
    final room = _room;
    if (room == null) return const [];
    return room.openings.map(RoomOpening.fromJson).toList();
  }

  void _clearSelection() {
    setState(() {
      _moveTarget = _OvMoveTarget.none;
      _selectedOpeningIndex = null;
      _placingIndex = null;
    });
  }

  Future<void> _onAddOpeningFab() async {
    if (_view3d) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавление проёма — в режиме 2D')),
      );
      return;
    }
    if (_placingIndex != null) {
      final room = _room;
      if (room == null) return;
      final list = _openings.toList();
      final i = _placingIndex!;
      if (i >= 0 && i < list.length && list[i].wallIndex == null) {
        list.removeAt(i);
        setState(() {
          room.openings = list.map((e) => e.toJson()).toList();
          _placingIndex = null;
        });
        await _persist();
      } else {
        setState(() => _placingIndex = null);
      }
      return;
    }
    final room = _room;
    if (room == null || room.walls.isEmpty) return;
    var kind = 'door';
    final wCtrl = TextEditingController(text: '90');
    final hCtrl = TextEditingController(text: '210');
    final sillCtrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Добавить проём'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'door', label: Text('Дверь')),
                        ButtonSegment(value: 'window', label: Text('Окно')),
                      ],
                      selected: {kind},
                      onSelectionChanged: (s) {
                        setLocal(() {
                          kind = s.first;
                          if (kind == 'door') {
                            wCtrl.text = '90';
                            hCtrl.text = '210';
                            sillCtrl.text = '0';
                          } else {
                            wCtrl.text = '120';
                            hCtrl.text = '140';
                            sillCtrl.text = '90';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: wCtrl,
                      keyboardType: NumericInput.decimalKeyboard,
                      inputFormatters: NumericInput.decimalFormatters,
                      decoration: const InputDecoration(
                        labelText: 'Ширина',
                        suffixText: 'см',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: hCtrl,
                      keyboardType: NumericInput.decimalKeyboard,
                      inputFormatters: NumericInput.decimalFormatters,
                      decoration: const InputDecoration(
                        labelText: 'Высота',
                        suffixText: 'см',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: sillCtrl,
                      keyboardType: NumericInput.decimalKeyboard,
                      inputFormatters: NumericInput.decimalFormatters,
                      decoration: const InputDecoration(
                        labelText: 'Подоконник / порог',
                        suffixText: 'см',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
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
                  child: const Text('Разместить'),
                ),
              ],
            );
          },
        );
      },
    );
    final widthCm = double.tryParse(wCtrl.text.replaceAll(',', '.')) ?? 0;
    final heightCm = double.tryParse(hCtrl.text.replaceAll(',', '.')) ?? 0;
    final sill = double.tryParse(sillCtrl.text.replaceAll(',', '.')) ?? 0;
    wCtrl.dispose();
    hCtrl.dispose();
    sillCtrl.dispose();
    if (ok != true || !mounted || widthCm <= 0 || heightCm <= 0) return;
    final list = _openings.toList();
    list.add(
      RoomOpening(
        kind: kind,
        widthCm: widthCm,
        heightCm: heightCm,
        sillHeightCm: sill,
      ),
    );
    setState(() {
      room.openings = list.map((e) => e.toJson()).toList();
      _placingIndex = list.length - 1;
      _moveTarget = _OvMoveTarget.none;
      _selectedOpeningIndex = null;
      _showOpenings = true;
    });
    await _persist();
  }

  void _placeOpeningAt(Offset world) {
    final room = _room;
    final i = _placingIndex;
    if (room == null || i == null) return;
    final list = _openings.toList();
    if (i < 0 || i >= list.length) return;
    final hit = nearestWallHit(room.walls, world.dx, world.dy, maxDistCm: 50);
    if (hit == null) return;
    final o = list[i];
    var start = hit.offsetAlongCm - o.widthCm / 2;
    start = start.clamp(0.0, math.max(0.0, hit.wallLengthCm - o.widthCm));
    o.wallIndex = hit.wallIndex;
    o.offsetAlongWallCm = start;
    setState(() {
      room.openings = list.map((e) => e.toJson()).toList();
      _placingIndex = null;
      _moveTarget = _OvMoveTarget.opening;
      _selectedOpeningIndex = i;
    });
    _persist();
  }

  /// Joystick → wall offset. In 3D: left/right relative to the viewer
  /// (after rotating the opening toward the camera). In 2D: world axes.
  double _openingAlongDelta({
    required Room room,
    required RoomOpening o,
    required double ux,
    required double uy,
    required double len,
    required double dx,
    required double dy,
  }) {
    if (!_view3d) {
      // Top-down: project joystick onto wall tangent in world cm.
      return dx * ux + dy * uy;
    }
    final size = _view3dSize ?? const Size(400, 400);
    final shell = RoomShell3D.fromWalls(
      room.walls,
      heightCm: room.ceilingHeightCm,
      openings: _openings,
    );
    if (shell == null) return dx * ux + dy * uy;
    final (minX, maxX, minY, maxY) = shell.bounds2d;
    final wi = o.wallIndex!;
    final w = room.walls[wi];
    final ax = w[0], ay = w[1];
    final mid = (o.offsetAlongWallCm + o.widthCm / 2).clamp(0.0, len);
    final z = (o.sillHeightCm + o.heightCm / 2).clamp(0.0, shell.heightCm);
    Offset proj(double t) {
      final x = ax + ux * t;
      final y = ay + uy * t;
      return IsometricShellPainter.projectIso(
        x: x,
        y: y,
        z: z,
        size: size,
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        heightCm: shell.heightCm,
        yaw: _yaw,
        pitch: _pitch,
      );
    }

    // Screen tangent of +wall direction (increasing offsetAlongWall).
    final a = proj(mid);
    final b = proj(math.min(len, mid + 20));
    final screen = b - a;
    final sn = screen.distance;
    if (sn < 1e-3) return dx * ux + dy * uy;
    final sx = screen.dx / sn;
    final sy = screen.dy / sn;
    // Joystick: right=+x, up=+dy → screen up is −y.
    final joySx = dx;
    final joySy = -dy;
    return joySx * sx + joySy * sy;
  }

  Future<void> _nudge(double dx, double dy, {bool finalize = false}) async {
    final room = _room;
    if (room == null) return;
    setState(() {
      switch (_moveTarget) {
        case _OvMoveTarget.opening:
          final i = _selectedOpeningIndex;
          if (i == null) break;
          final list = _openings.toList();
          if (i < 0 || i >= list.length) break;
          final o = list[i];
          final wi = o.wallIndex;
          if (wi == null || wi < 0 || wi >= room.walls.length) break;
          final w = room.walls[wi];
          final wdx = w[2] - w[0];
          final wdy = w[3] - w[1];
          final len = math.sqrt(wdx * wdx + wdy * wdy);
          if (len < 1) break;
          final ux = wdx / len;
          final uy = wdy / len;
          final along = _openingAlongDelta(
            room: room,
            o: o,
            ux: ux,
            uy: uy,
            len: len,
            dx: dx,
            dy: dy,
          );
          o.offsetAlongWallCm = (o.offsetAlongWallCm + along)
              .clamp(0.0, math.max(0.0, len - o.widthCm))
              .toDouble();
          room.openings = list.map((e) => e.toJson()).toList();
        case _OvMoveTarget.floor:
          room.floorGridOffsetX += dx.round();
          room.floorGridOffsetY += dy.round();
        case _OvMoveTarget.ceiling:
          room.gridOffsetX += dx.round();
          room.gridOffsetY += dy.round();
        case _OvMoveTarget.none:
          break;
      }
    });
    if (finalize) await _persist();
  }

  /// [local] is in InteractiveViewer child space (already untransformed).
  Offset _sceneToWorld(Offset local) {
    final m = _metrics;
    if (m == null) return local;
    return m.screenToWorld(local);
  }

  int? _hitOpening(Offset world) {
    final room = _room;
    if (room == null) return null;
    var bestI = -1;
    var bestD = 40.0;
    final openings = _openings;
    final walls = room.walls;
    for (var i = 0; i < openings.length; i++) {
      final o = openings[i];
      final wi = o.wallIndex;
      if (wi == null || wi < 0 || wi >= walls.length) continue;
      final w = walls[wi];
      final ax = w[0], ay = w[1], bx = w[2], by = w[3];
      final len = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
      if (len < 1) continue;
      final ux = (bx - ax) / len;
      final uy = (by - ay) / len;
      final mid = o.offsetAlongWallCm + o.widthCm / 2;
      final mx = ax + ux * mid;
      final my = ay + uy * mid;
      final d = math.sqrt(math.pow(world.dx - mx, 2) + math.pow(world.dy - my, 2));
      if (d < bestD) {
        bestD = d;
        bestI = i;
      }
    }
    return bestI >= 0 ? bestI : null;
  }

  void _onLongPressAt(Offset local, {Size? viewSize, RoomShell3D? shell}) {
    if (_view3d) {
      if (!_showOpenings || shell == null || viewSize == null) return;
      final room = _room;
      if (room == null) return;
      final oi = IsometricShellPainter.hitOpeningIndex(
        local: local,
        size: viewSize,
        shell: shell,
        walls: room.walls,
        yaw: _yaw,
        pitch: _pitch,
      );
      if (oi == null) return;
      setState(() {
        _moveTarget = _OvMoveTarget.opening;
        _selectedOpeningIndex = oi;
      });
      return;
    }
    final world = _sceneToWorld(local);
    final oi = _hitOpening(world);
    if (oi != null && _showOpenings) {
      setState(() {
        _moveTarget = _OvMoveTarget.opening;
        _selectedOpeningIndex = oi;
      });
      return;
    }
    // Prefer ceiling when visible (drawn on top), else floor.
    // In 2D floor is hidden while ceiling is on — don't select floor then.
    if (_showCeiling) {
      setState(() {
        _moveTarget = _OvMoveTarget.ceiling;
        _selectedOpeningIndex = null;
      });
      return;
    }
    if (_showFloor) {
      setState(() {
        _moveTarget = _OvMoveTarget.floor;
        _selectedOpeningIndex = null;
      });
    }
  }

  Future<void> _onTapAt(Offset local) async {
    if (_view3d) {
      if (_moveTarget != _OvMoveTarget.none) _clearSelection();
      return;
    }
    if (_placingIndex != null) {
      _placeOpeningAt(_sceneToWorld(local));
      return;
    }
    if (_moveTarget != _OvMoveTarget.none) {
      _clearSelection();
      return;
    }
  }

  String get _selectionHint {
    switch (_moveTarget) {
      case _OvMoveTarget.opening:
        return 'Проём · джойстик двигает вдоль стены · тап — снять выбор';
      case _OvMoveTarget.floor:
        return 'Пол · джойстик смещает раскладку · тап — снять выбор';
      case _OvMoveTarget.ceiling:
        return 'Потолок · джойстик смещает сетку · тап — снять выбор';
      case _OvMoveTarget.none:
        return _view3d
            ? 'Тяните для поворота · долгое нажатие на проём — выбрать'
            : 'Долгое нажатие — выбрать · джойстик — сдвинуть';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = _room;
    if (room == null || !room.hasLayout) {
      return Scaffold(
        appBar: AppBar(title: const Text('Редактор · Обзор')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Нет контура помещения',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => RoomEditorScreen(
                          projectId: widget.projectId,
                          roomId: widget.roomId,
                          module: AppModule.finish,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Нарисовать контур'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final openings = _openings;
    final shell = RoomShell3D.fromWalls(
      room.walls,
      heightCm: room.ceilingHeightCm,
      openings: openings,
    );
    final covering = FloorCoveringKindX.parse(room.floorCoveringKind);
    final pattern = FloorLayingPatternX.parse(room.floorLayingPattern);
    final floorLayout = covering.hasBoardLayout
        ? FloorLayoutBuilder.build(
            walls: room.walls,
            covering: covering,
            pattern: pattern,
            boardW: room.finishTileWidthCm,
            boardL: room.finishTileHeightCm,
            offsetX: room.floorGridOffsetX.toDouble(),
            offsetY: room.floorGridOffsetY.toDouble(),
            rotationDeg: room.floorLayoutRotationDeg,
          )
        : FloorLayoutBuilder.build(
            walls: room.walls,
            covering: FloorCoveringKind.screed,
            pattern: FloorLayingPattern.straight,
            boardW: 60,
            boardL: 60,
            offsetX: 0,
            offsetY: 0,
          );

    final ceilingGrid = CeilingGrid(cellSizeCm: 60);
    ceilingGrid.setOffset(room.gridOffsetX.toDouble(), room.gridOffsetY.toDouble());
    final lights = <String>{};
    for (final f in room.lightFixtures) {
      if (f.length >= 2) lights.add('${f[0]}:${f[1]}');
    }
    ceilingGrid.rebuild(
      roomPoints: pointsFromWalls(room.walls),
      walls: room.walls,
      lightIds: lights,
    );

    return ScreenScaffold(
      backgroundBlur: 0.45,
      dimOpacity: 0.55,
      appBar: AppBar(
        title: Text('${room.name} · отделка'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Стены'),
                  selected: _showWalls,
                  onSelected: (v) => setState(() => _showWalls = v),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Проёмы'),
                  selected: _showOpenings,
                  onSelected: (v) => setState(() => _showOpenings = v),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Пол'),
                  selected: _showFloor,
                  onSelected: (v) => setState(() => _showFloor = v),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Потолок'),
                  selected: _showCeiling,
                  onSelected: (v) => setState(() => _showCeiling = v),
                ),
              ],
            ),
          ),
          if (_moveTarget != _OvMoveTarget.none)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Text(
                _selectionHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: CanvasPalette.bg,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: _view3d
                      ? (shell == null
                          ? const Center(
                              child: Text(
                                'Нет оболочки',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, c3d) {
                                final viewSize =
                                    Size(c3d.maxWidth, c3d.maxHeight);
                                _view3dSize = viewSize;
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (_) => _onTapAt(Offset.zero),
                                  onLongPressStart: (d) => _onLongPressAt(
                                    d.localPosition,
                                    viewSize: viewSize,
                                    shell: shell,
                                  ),
                                  onPanUpdate: _moveTarget ==
                                          _OvMoveTarget.opening
                                      ? null
                                      : (d) {
                                          setState(() {
                                            _yaw = (_yaw + d.delta.dx * 0.01) %
                                                (math.pi * 2);
                                            _pitch =
                                                (_pitch + d.delta.dy * 0.01)
                                                    .clamp(0.15, 1.2);
                                          });
                                        },
                                  child: CustomPaint(
                                    painter: IsometricShellPainter(
                                      shell: shell,
                                      walls: room.walls,
                                      yaw: _yaw,
                                      pitch: _pitch,
                                      showWalls: _showWalls,
                                      showFloor: _showFloor,
                                      showCeiling: _showCeiling,
                                      showOpenings: _showOpenings,
                                      selectedOpeningIndex:
                                          _selectedOpeningIndex,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                );
                              },
                            ))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final size = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            final metrics =
                                FloorPlanMetrics.fromWalls(room.walls, size);
                            _metrics = metrics;
                            return InteractiveViewer(
                              transformationController: _transform,
                              constrained: false,
                              minScale: 0.35,
                              maxScale: 8,
                              boundaryMargin: const EdgeInsets.all(280),
                              child: SizedBox(
                                width: size.width,
                                height: size.height,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (d) => _onTapAt(d.localPosition),
                                  onLongPressStart: (d) =>
                                      _onLongPressAt(d.localPosition),
                                  child: CustomPaint(
                                    size: size,
                                    painter: _OverviewPlanPainter(
                                      walls: room.walls,
                                      metrics: metrics,
                                      floorLayout: floorLayout,
                                      ceilingGrid: ceilingGrid,
                                      openings: openings,
                                      showWalls: _showWalls,
                                      showFloor: _showFloor,
                                      showCeiling: _showCeiling,
                                      showOpenings: _showOpenings,
                                      selectedOpeningIndex:
                                          _placingIndex ??
                                              _selectedOpeningIndex,
                                      highlightFloor:
                                          _moveTarget == _OvMoveTarget.floor,
                                      highlightCeiling:
                                          _moveTarget == _OvMoveTarget.ceiling,
                                      showFloorCutDims: _showFloor &&
                                          !_showCeiling &&
                                          (_moveTarget ==
                                                  _OvMoveTarget.floor ||
                                              _moveTarget ==
                                                  _OvMoveTarget.none),
                                      showCeilingCutDims: _showCeiling &&
                                          (_moveTarget ==
                                                  _OvMoveTarget.ceiling ||
                                              _moveTarget !=
                                                  _OvMoveTarget.floor),
                                      paintFloorIn2d:
                                          _showFloor && !_showCeiling,
                                      viewScale: _transform.value
                                          .getMaxScaleOnAxis(),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: _placingIndex != null
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.85)
                              : Colors.black.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: _onAddOpeningFab,
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _placingIndex != null
                                        ? Icons.close
                                        : Icons.door_front_door_outlined,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _placingIndex != null
                                        ? 'Отмена'
                                        : 'Проём',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_placingIndex != null)
                        Positioned(
                          top: 52,
                          left: 8,
                          right: 8,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Text(
                                'Коснитесь стены, чтобы разместить проём',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const joyIdeal = 96.0;
                    const sideIdeal = 72.0;
                    const gapIdeal = 12.0;
                    const minTotal =
                        sideIdeal + gapIdeal + joyIdeal + gapIdeal + sideIdeal;
                    final scale =
                        (constraints.maxWidth / minTotal).clamp(0.55, 1.0);
                    final joy = joyIdeal * scale;
                    final side = sideIdeal * scale;
                    final gap = gapIdeal * scale;

                    Future<void> openRoomTab(int tab) async {
                      await openFinishRoom(
                        context,
                        projectId: widget.projectId,
                        roomId: widget.roomId,
                        initialTabIndex: tab,
                      );
                      await _load();
                    }

                    Widget leftColumn() => SizedBox(
                          width: side,
                          height: joy,
                          child: Column(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: _OvModeChip(
                                    label: 'Потол.',
                                    selected: false,
                                    onTap: () => openRoomTab(3),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: _OvModeChip(
                                    label: 'Пол',
                                    selected: false,
                                    onTap: () => openRoomTab(2),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: _OvModeChip(
                                    label: 'Стены',
                                    selected: false,
                                    onTap: () => openRoomTab(1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );

                    Widget rightColumn() => SizedBox(
                          width: side,
                          height: joy,
                          child: Column(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: _OvModeChip(
                                    label: _view3d ? '3D' : '2D',
                                    selected: true,
                                    onTap: () => setState(() {
                                      _view3d = !_view3d;
                                      _clearSelection();
                                    }),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: _OvModeChip(
                                    label: 'Контур',
                                    selected: false,
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => RoomEditorScreen(
                                            projectId: widget.projectId,
                                            roomId: widget.roomId,
                                            module: AppModule.finish,
                                          ),
                                        ),
                                      );
                                      await _load();
                                    },
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: _OvModeChip(
                                    label: 'Парам.',
                                    selected: false,
                                    onTap: () => openRoomTab(0),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );

                    return SizedBox(
                      height: joy,
                      width: constraints.maxWidth,
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: leftColumn(),
                            ),
                          ),
                          SizedBox(width: gap),
                          ArrowJoystick(
                            size: joy,
                            onTick: _nudge,
                            onRelease: () => _nudge(0, 0, finalize: true),
                          ),
                          SizedBox(width: gap),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: rightColumn(),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OvModeChip extends StatelessWidget {
  const _OvModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = danger
        ? scheme.error.withValues(alpha: 0.28)
        : selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected || danger ? FontWeight.w700 : FontWeight.w500,
              color: danger ? scheme.error : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewPlanPainter extends CustomPainter {
  _OverviewPlanPainter({
    required this.walls,
    required this.metrics,
    required this.floorLayout,
    required this.ceilingGrid,
    required this.openings,
    required this.showWalls,
    required this.showFloor,
    required this.showCeiling,
    required this.showOpenings,
    this.selectedOpeningIndex,
    this.highlightFloor = false,
    this.highlightCeiling = false,
    this.showFloorCutDims = false,
    this.showCeilingCutDims = false,
    this.paintFloorIn2d = true,
    this.viewScale = 1,
  });

  final List<List<double>> walls;
  final FloorPlanMetrics metrics;
  final FloorLayoutSnapshot floorLayout;
  final CeilingGrid ceilingGrid;
  final List<RoomOpening> openings;
  final bool showWalls;
  final bool showFloor;
  final bool showCeiling;
  final bool showOpenings;
  final int? selectedOpeningIndex;
  final bool highlightFloor;
  final bool highlightCeiling;
  final bool showFloorCutDims;
  final bool showCeilingCutDims;
  /// In 2D, floor is hidden while ceiling is on (avoids overlapping grids).
  final bool paintFloorIn2d;
  /// InteractiveViewer scale — keep dim labels ~readable on large rooms.
  final double viewScale;

  double get _dimFont => (28.0 / viewScale.clamp(0.05, 4.0)).clamp(28.0, 560.0);
  double get _dimOff => (42.0 / viewScale.clamp(0.05, 4.0)).clamp(42.0, 840.0);

  void _paintChipLabel(Canvas canvas, Offset center, String text, {double fontSize = 10}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: CanvasPalette.text,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          shadows: const [
            Shadow(blurRadius: 2, color: Colors.black87),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = Offset(center.dx - tp.width / 2, center.dy - tp.height / 2);
    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.dx - 2, origin.dy - 1, tp.width + 4, tp.height + 2),
      const Radius.circular(2),
    );
    canvas.drawRRect(chip, Paint()..color = const Color(0xAA000000));
    tp.paint(canvas, origin);
  }

  void _paintCeilingCuts(Canvas canvas) {
    final cell = ceilingGrid.cellSizeCm;
    for (final c in ceilingGrid.cells) {
      if (c.kind != CellKind.cut) continue;
      if (c.cutXCm >= cell && c.cutYCm >= cell) continue;
      if (c.cutXCm < 1 && c.cutYCm < 1) continue;
      final cx = c.xCm + c.cutXCm / 2;
      final cy = c.yCm + c.cutYCm / 2;
      final a = metrics.map(c.xCm, c.yCm);
      final b = metrics.map(c.xCm + cell, c.yCm + cell);
      final tilePx = (b - a).distance / math.sqrt2;
      final fontSize = (tilePx * 0.28).clamp(8.0, 16.0);
      _paintChipLabel(
        canvas,
        metrics.map(cx, cy),
        '${c.cutXCm.round()}×${c.cutYCm.round()}',
        fontSize: fontSize,
      );
    }
  }

  void _paintOpeningWallDims(Canvas canvas, RoomOpening o) {
    final wi = o.wallIndex;
    if (wi == null || wi < 0 || wi >= walls.length) return;
    final w = walls[wi];
    final ax = w[0], ay = w[1], bx = w[2], by = w[3];
    final len = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
    if (len < 1) return;
    final ux = (bx - ax) / len;
    final uy = (by - ay) / len;

    final t0 = o.offsetAlongWallCm.clamp(0.0, len).toDouble();
    final t1 = (o.offsetAlongWallCm + o.widthCm).clamp(0.0, len).toDouble();

    Offset at(double t) => metrics.map(ax + ux * t, ay + uy * t);
    const dimColor = Color(0xFFFFC857);
    const gapColor = Color(0xFF8FB4D4);

    final fs = _dimFont;
    final off = _dimOff;
    // Left gap: wall start → opening start
    if (t0 > 2) {
      DimensionLines.drawSegmentDimension(
        canvas,
        a: at(0),
        b: at(t0),
        label: '${t0.round()}',
        color: gapColor,
        offsetPx: off,
        placeAbove: true,
        fontSize: fs,
      );
    }
    // Opening width
    if (t1 - t0 > 2) {
      DimensionLines.drawSegmentDimension(
        canvas,
        a: at(t0),
        b: at(t1),
        label: '${(t1 - t0).round()}',
        color: dimColor,
        offsetPx: off,
        placeAbove: true,
        fontSize: fs,
      );
    }
    // Right gap: opening end → wall end
    if (len - t1 > 2) {
      DimensionLines.drawSegmentDimension(
        canvas,
        a: at(t1),
        b: at(len),
        label: '${(len - t1).round()}',
        color: gapColor,
        offsetPx: off,
        placeAbove: true,
        fontSize: fs,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = CanvasPalette.bg);

    // Floor under ceiling — in 2D only when ceiling is off.
    if (showFloor && paintFloorIn2d) {
      FloorPlanPainter(
        walls: walls,
        metrics: metrics,
        layout: floorLayout,
        showCutDims: showFloorCutDims,
        paintBackground: false,
        paintWalls: false,
      ).paint(canvas, size);
      if (highlightFloor) {
        final path = Path();
        if (walls.isNotEmpty) {
          final first = metrics.map(walls.first[0], walls.first[1]);
          path.moveTo(first.dx, first.dy);
          for (final w in walls) {
            path.lineTo(metrics.map(w[2], w[3]).dx, metrics.map(w[2], w[3]).dy);
          }
          path.close();
          canvas.drawPath(
            path,
            Paint()
              ..color = const Color(0x44FFC857)
              ..style = PaintingStyle.fill,
          );
        }
      }
    }

    // Ceiling on top of floor.
    if (showCeiling) {
      final gridPaint = Paint()
        ..color = highlightCeiling
            ? const Color(0xAAFFC857)
            : const Color(0x88FFC857)
        ..strokeWidth = highlightCeiling ? 1.6 : 1.1
        ..style = PaintingStyle.stroke;
      for (final c in ceilingGrid.cells) {
        if (c.kind == CellKind.outside) continue;
        final a = metrics.map(c.xCm, c.yCm);
        final b = metrics.map(c.xCm + ceilingGrid.cellSizeCm, c.yCm);
        final d = metrics.map(
          c.xCm + ceilingGrid.cellSizeCm,
          c.yCm + ceilingGrid.cellSizeCm,
        );
        final e = metrics.map(c.xCm, c.yCm + ceilingGrid.cellSizeCm);
        canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..lineTo(d.dx, d.dy)
            ..lineTo(e.dx, e.dy)
            ..close(),
          gridPaint,
        );
      }
      if (showCeilingCutDims) {
        _paintCeilingCuts(canvas);
      }
    }

    if (showWalls) {
      final wallPaint = Paint()
        ..color = CanvasPalette.wall
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      for (final w in walls) {
        canvas.drawLine(
          metrics.map(w[0], w[1]),
          metrics.map(w[2], w[3]),
          wallPaint,
        );
      }
    }

    if (showOpenings) {
      const gap = 30.0;
      for (var i = 0; i < openings.length; i++) {
        final o = openings[i];
        final wi = o.wallIndex;
        if (wi == null || wi < 0 || wi >= walls.length) continue;
        final w = walls[wi];
        final ax = w[0], ay = w[1], bx = w[2], by = w[3];
        final len = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
        if (len < 1) continue;
        final ux = (bx - ax) / len;
        final uy = (by - ay) / len;
        final selected = i == selectedOpeningIndex;
        final fill = Paint()
          ..color = selected
              ? const Color(0xFFFFC857)
              : (o.kind == 'door'
                  ? const Color(0xFFE07A5F)
                  : const Color(0xFF81B29A))
          ..strokeWidth = selected ? 11 : 8
          ..strokeCap = StrokeCap.butt
          ..style = PaintingStyle.stroke;
        final n = math.max(1, o.quantity);
        for (var q = 0; q < n; q++) {
          final t0 = o.offsetAlongWallCm + q * (o.widthCm + gap);
          if (t0 >= len) break;
          final t1 = math.min(len, t0 + o.widthCm);
          canvas.drawLine(
            metrics.map(ax + ux * t0, ay + uy * t0),
            metrics.map(ax + ux * t1, ay + uy * t1),
            fill,
          );
        }
        if (selected) {
          _paintOpeningWallDims(canvas, o);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OverviewPlanPainter old) =>
      old.showWalls != showWalls ||
      old.showFloor != showFloor ||
      old.showCeiling != showCeiling ||
      old.showOpenings != showOpenings ||
      old.selectedOpeningIndex != selectedOpeningIndex ||
      old.highlightFloor != highlightFloor ||
      old.highlightCeiling != highlightCeiling ||
      old.showFloorCutDims != showFloorCutDims ||
      old.showCeilingCutDims != showCeilingCutDims ||
      old.paintFloorIn2d != paintFloorIn2d ||
      old.viewScale != viewScale ||
      old.walls != walls ||
      old.floorLayout != floorLayout ||
      old.openings != openings ||
      old.ceilingGrid != ceilingGrid;
}
