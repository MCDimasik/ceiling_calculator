import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/ceiling_grid.dart';
import '../domain/ceiling_guides.dart';
import '../domain/finish_model.dart';
import '../domain/materials_calculator.dart';
import '../domain/models.dart';
import '../domain/project_materials.dart';
import 'materials_result_screen.dart';
import 'finish_room_screen.dart';
import 'widgets/canvas_palette.dart';
import 'widgets/controls.dart';

enum LayoutMode { pan, grid, lights, guides }

class LayoutScreen extends StatefulWidget {
  const LayoutScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<LayoutScreen> createState() => _LayoutScreenState();
}

class _LayoutScreenState extends State<LayoutScreen> {
  Room? _room;
  final _grid = CeilingGrid();
  final _transform = TransformationController();
  LayoutMode _mode = LayoutMode.grid;
  bool _loading = true;
  bool _showTileDims = true;
  bool _showWallDims = true;

  /// Live offset for cheap visual grid while dragging/nudging.
  double _visualOffsetX = 0;
  double _visualOffsetY = 0;

  /// Authoritative light cell ids (`col:row`) — survive offset rebuilds.
  final Set<String> _lightIds = {};

  /// Grid lines marked as guide profiles (`h:120` / `v:300` → mark).
  final Map<String, CeilingGuideMark> _guides = {};

  GuideKind _guideKind = GuideKind.g3600;
  /// Last chosen main runner (3600/2400) — kept when switching to 1200/600.
  GuideKind _mainGuideKind = GuideKind.g3600;

  /// Guide picked up for move — only the lead segment is shown until dropped.
  CeilingGuideMark? _floatingGuide;
  double? _dragSmoothX;
  double? _dragSmoothY;

  _LayoutMetrics? _lastMetrics;

  Timer? _rebuildThrottle;
  bool _rebuildPending = false;
  Timer? _liveGridThrottle;
  Timer? _viewCullThrottle;
  bool _viewApplied = false;
  bool _canvasReady = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _rebuildThrottle?.cancel();
    _liveGridThrottle?.cancel();
    _viewCullThrottle?.cancel();
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    // Throttle cull/repaint while panning — full setState every frame is costly.
    if (_viewCullThrottle?.isActive ?? false) return;
    _viewCullThrottle = Timer(const Duration(milliseconds: 50), () {
      if (mounted) setState(() {});
    });
  }

  void _applyOrCenterView(Size viewport, Size canvasSize, _LayoutMetrics metrics) {
    if (_viewApplied || _room == null) return;
    _viewApplied = true;

    final focal = metrics.roomCentroidScreen;
    final fitScale = metrics.fitScaleForViewport(viewport);
    _transform.value = Matrix4.identity()
      ..translateByDouble(viewport.width / 2, viewport.height / 2, 0, 1)
      ..scaleByDouble(fitScale, fitScale, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
  }

  void _captureViewToRoom() {
    final room = _room;
    if (room == null) return;
    room.layoutViewJson = ViewTransform.fromMatrix(_transform.value).toJson();
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
      _viewApplied = false;
      _canvasReady = false;
      _room = room;
      _loading = false;
      if (room != null) {
        _visualOffsetX = room.gridOffsetX.toDouble();
        _visualOffsetY = room.gridOffsetY.toDouble();
        _lightIds
          ..clear()
          ..addAll(
            room.lightFixtures
                .where((f) => f.length >= 2)
                .map((f) => '${f[0]}:${f[1]}'),
          );
        _rebuildGrid(room);
        _guides
          ..clear()
          ..addEntries(
            parseCeilingGuidesWithLegacyAnchor(
              room.ceilingGuides,
              room.walls,
              offsetX: _visualOffsetX,
              offsetY: _visualOffsetY,
              cellSize: _grid.cellSizeCm,
            ).map((g) => MapEntry(g.storageKey, g)),
          );
        _mode = _shouldDefaultPan(room) ? LayoutMode.pan : LayoutMode.grid;
        _canvasReady = true;
      }
    });
  }

  /// Reopen in Pan when layout was confirmed, or legacy room already edited once.
  bool _shouldDefaultPan(Room room) {
    if (room.layoutConfirmed) return true;
    return room.hasLayout &&
        (room.lightFixtures.isNotEmpty ||
            room.layoutViewJson != null ||
            room.gridOffsetX != 0 ||
            room.gridOffsetY != 0);
  }

  bool _canConfirmLayout(Room room) =>
      room.hasLayout && _grid.cells.any((c) => c.kind != CellKind.outside);

  void _shiftGuideLineIndices(int hDelta, int vDelta) {
    if (hDelta == 0 && vDelta == 0) return;
    final next = <String, CeilingGuideMark>{};
    for (final e in _guides.entries) {
      final m = e.value;
      var line = m.lineIndex;
      var anchor = m.anchorAlongIndex;
      if (m.axis == GuideAxis.horizontal) {
        if (hDelta != 0) line += hDelta;
        if (vDelta != 0) anchor += vDelta;
      } else {
        if (vDelta != 0) line += vDelta;
        if (hDelta != 0) anchor += hDelta;
      }
      final key = '${m.axis == GuideAxis.vertical ? 'v' : 'h'}:$line';
      next[key] = CeilingGuideMark(
        axis: m.axis,
        lineIndex: line,
        kind: m.kind,
        anchorAlongIndex: anchor,
      );
    }
    _guides
      ..clear()
      ..addAll(next);
  }

  /// Sync grid to visual offset; optionally wrap. Preserves light/guide world positions.
  void _syncGridToVisual(Room room, {required bool wrap}) {
    final cw = _grid.cellWidthCm <= 0 ? 60.0 : _grid.cellWidthCm;
    final ch = _grid.cellHeightCm <= 0 ? 60.0 : _grid.cellHeightCm;
    final prevGridX = _grid.offsetXCm;
    final prevGridY = _grid.offsetYCm;
    final preWrapX = _visualOffsetX;
    final preWrapY = _visualOffsetY;

    final nextX = wrap ? _wrapOffset(preWrapX, cw) : preWrapX;
    final nextY = wrap ? _wrapOffset(preWrapY, ch) : preWrapY;

    final dragDx = preWrapX - prevGridX;
    final dragDy = preWrapY - prevGridY;
    final lightWorlds = <(double, double)>[];
    for (final c in _grid.cells) {
      if (_lightIds.contains(c.id)) {
        lightWorlds.add((
          c.xCm + dragDx + cw / 2,
          c.yCm + dragDy + ch / 2,
        ));
      }
    }

    if (wrap) {
      final hLineDelta = ((preWrapY - nextY) / ch).round();
      final vLineDelta = ((preWrapX - nextX) / cw).round();
      _shiftGuideLineIndices(hLineDelta, vLineDelta);
    }

    _visualOffsetX = nextX;
    _visualOffsetY = nextY;
    _grid.offsetXCm = nextX;
    _grid.offsetYCm = nextY;

    _grid.rebuild(
      roomPoints: pointsFromWalls(room.walls),
      walls: room.walls,
      lightIds: const {},
    );

    _lightIds.clear();
    for (final (wx, wy) in lightWorlds) {
      for (final c in _grid.cells) {
        if (c.acceptsLight &&
            wx >= c.xCm &&
            wx < c.xCm + cw &&
            wy >= c.yCm &&
            wy < c.yCm + ch) {
          _lightIds.add(c.id);
          break;
        }
      }
    }

    _grid.rebuild(
      roomPoints: pointsFromWalls(room.walls),
      walls: room.walls,
      lightIds: _lightIds,
    );
    _grid.pruneLights();
    final lit = _grid.cells.where((c) => c.hasLight).map((c) => c.id).toSet();
    _lightIds.removeWhere((id) => !lit.contains(id));
  }

  void _commitGridOffset(Room room) => _syncGridToVisual(room, wrap: true);

  void _scheduleLiveGridSync(Room room) {
    if (_liveGridThrottle?.isActive ?? false) return;
    _liveGridThrottle = Timer(const Duration(milliseconds: 36), () {
      if (!mounted || _room == null) return;
      if (_visualOffsetX == _grid.offsetXCm && _visualOffsetY == _grid.offsetYCm) {
        return;
      }
      setState(() => _syncGridToVisual(room, wrap: false));
    });
  }

  void _rebuildGrid(Room room) {
    _grid.offsetXCm = _visualOffsetX;
    _grid.offsetYCm = _visualOffsetY;
    _grid.rebuild(
      roomPoints: pointsFromWalls(room.walls),
      walls: room.walls,
      lightIds: _lightIds,
    );
    _grid.pruneLights();
    final litOnGrid = _grid.cells.where((c) => c.hasLight).map((c) => c.id).toSet();
    _lightIds.removeWhere((id) => !litOnGrid.contains(id));
  }

  /// Schedule a throttled cell rebuild; always keeps visual offset live.
  void _scheduleRebuild(Room room, {bool immediate = false}) {
    if (immediate) {
      _rebuildThrottle?.cancel();
      _rebuildThrottle = null;
      _rebuildPending = false;
      _rebuildGrid(room);
      return;
    }
    _rebuildPending = true;
    if (_rebuildThrottle?.isActive ?? false) return;
    _rebuildThrottle = Timer(const Duration(milliseconds: 80), () {
      if (!mounted || !_rebuildPending) return;
      _rebuildPending = false;
      setState(() => _rebuildGrid(room));
    });
  }

  Future<void> _persist({bool markLayoutConfirmed = true}) async {
    final room = _room;
    if (room == null) return;
    _commitGridOffset(room);
    room.gridOffsetX = _grid.offsetXCm.round();
    room.gridOffsetY = _grid.offsetYCm.round();
    room.lightFixtures = _lightIds.map((id) {
      final parts = id.split(':');
      return [int.parse(parts[0]), int.parse(parts[1])];
    }).toList();
    _captureViewToRoom();
    room.ceilingGuides = _guides.values.map((g) => g.toJson()).toList();
    if (markLayoutConfirmed && _canConfirmLayout(room)) {
      room.layoutConfirmed = true;
    }
    await AppScope.of(context).projects.updateRoom(room);
  }

  void _onTapUp(TapUpDetails d, _LayoutMetrics m) {
    if (_room == null) return;
    if (_mode == LayoutMode.lights) {
      _onLightTap(d, m);
    } else if (_mode == LayoutMode.guides) {
      _onGuideTap(d, m);
    }
  }

  void _onLightTap(TapUpDetails d, _LayoutMetrics m) {
    if (_room == null) return;
    final world = m.screenToWorld(d.localPosition);
    final cell = _grid.cellSizeCm;
    GridCell? hit;
    final ox = _visualOffsetX - _grid.offsetXCm;
    final oy = _visualOffsetY - _grid.offsetYCm;
    for (final c in _grid.cells) {
      final x = c.xCm + ox;
      final y = c.yCm + oy;
      if (world.dx >= x &&
          world.dx < x + cell &&
          world.dy >= y &&
          world.dy < y + cell) {
        hit = c;
        break;
      }
    }
    if (hit == null || !hit.acceptsLight) return;
    setState(() {
      final id = hit!.id;
      if (_lightIds.contains(id)) {
        _lightIds.remove(id);
      } else {
        _lightIds.add(id);
      }
      _grid.toggleLight(hit.col, hit.row);
    });
  }

  void _onGuideTap(TapUpDetails d, _LayoutMetrics m) {
    if (_floatingGuide != null || _room == null) return;
    final world = m.screenToWorld(d.localPosition);
    final cell = _grid.cellSizeCm;
    final tol = cell * 0.35;

    final existing = _hitExistingGuide(world, tol);
    if (existing != null) {
      setState(() {
        if (_guides[existing]?.kind == _guideKind) {
          _guides.remove(existing);
        } else {
          final prev = _guides[existing]!;
          _guides[existing] = CeilingGuideMark(
            axis: prev.axis,
            lineIndex: prev.lineIndex,
            kind: _guideKind,
            anchorAlongIndex: prev.anchorAlongIndex,
          );
        }
      });
      return;
    }

    final placement = snapGuidePlacement(
      worldX: world.dx,
      worldY: world.dy,
      offsetX: _visualOffsetX,
      offsetY: _visualOffsetY,
      cellSize: cell,
      walls: _room!.walls,
    );
    final key =
        '${placement.axis == GuideAxis.vertical ? 'v' : 'h'}:${placement.lineIndex}';
    final placed = CeilingGuideMark(
      axis: placement.axis,
      lineIndex: placement.lineIndex,
      kind: _guideKind,
      anchorAlongIndex: placement.anchorIndex,
    );
    setState(() => _guides[key] = placed);
  }

  Future<void> _openFrameTemplateDialog() async {
    final room = _room;
    if (room == null) return;

    var template = CeilingFrameTemplate.armstrong;
    final has2400 = _mainGuideKind == GuideKind.g2400 ||
        _guideKind == GuideKind.g2400 ||
        _guides.values.any((g) => g.kind == GuideKind.g2400);
    final existingCeiling = room.materialsCeiling;
    if (has2400) {
      template = CeilingFrameTemplate.grilyatoClassic;
    } else if (existingCeiling == 'Грильято') {
      template = CeilingFrameTemplate.grilyatoClassic;
    } else if (existingCeiling == 'GL') {
      template = CeilingFrameTemplate.grilyatoGl;
    }
    var cell = room.materialsCell ?? '100x100';
    if (cell != '50x50' && cell != '75x75' && cell != '100x100') {
      cell = '100x100';
    }

    final result = await showDialog<({CeilingFrameTemplate template, String cell})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Шаблон каркаса'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Тип потолка', style: Theme.of(ctx).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SegmentedButton<CeilingFrameTemplate>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: CeilingFrameTemplate.armstrong,
                          label: Text('Армстронг'),
                        ),
                        ButtonSegment(
                          value: CeilingFrameTemplate.grilyatoClassic,
                          label: Text('Грильято'),
                        ),
                        ButtonSegment(
                          value: CeilingFrameTemplate.grilyatoGl,
                          label: Text('GL'),
                        ),
                      ],
                      selected: {template},
                      onSelectionChanged: (s) => setLocal(() => template = s.first),
                    ),
                    if (template.needsCellSize) ...[
                      const SizedBox(height: 16),
                      Text('Ячейка решётки', style: Theme.of(ctx).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: '50x50', label: Text('50×50')),
                          ButtonSegment(value: '75x75', label: Text('75×75')),
                          ButtonSegment(value: '100x100', label: Text('100×100')),
                        ],
                        selected: {cell},
                        onSelectionChanged: (s) => setLocal(() => cell = s.first),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      template.schemeHint(cell),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _guides.isEmpty
                          ? 'Несущий ряд будет построен от центра комнаты '
                              '(можно заранее поставить свой ряд тапом).'
                          : 'Каркас строится от уже выставленного несущего ряда.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, (template: template, cell: cell)),
                  child: const Text('Построить'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || !mounted) return;
    await _applyFrameTemplate(result.template, result.cell);
  }

  Future<void> _applyFrameTemplate(
    CeilingFrameTemplate template,
    String cellSizeLabel,
  ) async {
    final room = _room;
    if (room == null) return;

    final seed = findFrameSeed(_guides.values, template: template) ??
        seedFrameAtRoomCenter(
          template: template,
          offsetX: _visualOffsetX,
          offsetY: _visualOffsetY,
          cellSize: _grid.cellSizeCm,
          walls: room.walls,
        );

    final proposed = proposeCeilingFrame(
      template: template,
      seed: seed,
      offsetX: _visualOffsetX,
      offsetY: _visualOffsetY,
      cellSize: _grid.cellSizeCm,
      walls: room.walls,
      cellSizeLabel: cellSizeLabel,
    );

    setState(() {
      _guides
        ..clear()
        ..addEntries(proposed.map((g) => MapEntry(g.storageKey, g)));
      room.materialsCeiling = template.materialsLabel;
      if (template.needsCellSize) {
        room.materialsCell = cellSizeLabel;
      }
      room.materialsOverride = true;
    });

    final projects = AppScope.of(context).projects;
    final roomId = room.id;
    if (roomId != null) {
      await projects.updateRoomMaterials(
        roomId,
        override: true,
        ceiling: template.materialsLabel,
        susp: room.materialsSusp,
        cell: template.needsCellSize ? cellSizeLabel : room.materialsCell,
      );
    }
    await projects.updateProjectMaterials(
      widget.projectId,
      ceiling: template.materialsLabel,
      cell: template.needsCellSize ? cellSizeLabel : room.materialsCell,
    );
    await _persist(markLayoutConfirmed: false);
  }

  String? _hitExistingGuide(Offset world, double tol) {
    final room = _room;
    if (room == null) return null;
    String? bestKey;
    var bestDist = double.infinity;
    for (final e in _guides.entries) {
      final mark = e.value;
      final coord = guideLineWorldCoord(
        axis: mark.axis,
        lineIndex: mark.lineIndex,
        gridOffset: mark.axis == GuideAxis.horizontal ? _grid.offsetYCm : _grid.offsetXCm,
        visualOffset: mark.axis == GuideAxis.horizontal ? _visualOffsetY : _visualOffsetX,
        cellSize: _grid.cellSizeCm,
      );
      final dist = mark.axis == GuideAxis.horizontal
          ? (world.dy - coord).abs()
          : (world.dx - coord).abs();
      if (dist <= tol && dist < bestDist) {
        bestDist = dist;
        bestKey = e.key;
      }
    }
    return bestKey;
  }

  void _onGuideLongPressStart(LongPressStartDetails d, _LayoutMetrics m) {
    if (_mode != LayoutMode.guides || _room == null) return;
    final world = m.screenToWorld(d.localPosition);
    final key = _hitExistingGuide(world, _grid.cellSizeCm * 0.45);
    if (key == null) return;
    final mark = _guides.remove(key);
    if (mark == null) return;
    setState(() {
      _floatingGuide = mark;
      _dragSmoothX = world.dx;
      _dragSmoothY = world.dy;
    });
  }

  void _onGuideLongPressMove(LongPressMoveUpdateDetails d, _LayoutMetrics m) {
    if (_floatingGuide == null || _room == null) return;
    final world = m.screenToWorld(d.localPosition);
    setState(() {
      _dragSmoothX = world.dx;
      _dragSmoothY = world.dy;
    });
  }

  void _onGuideLongPressEnd(LongPressEndDetails d) {
    if (_floatingGuide == null) {
      setState(() {
        _dragSmoothX = null;
        _dragSmoothY = null;
      });
      return;
    }
    final room = _room!;
    final prev = _floatingGuide!;
    final cell = _grid.cellSizeCm;
    final placement = snapGuidePlacement(
      worldX: _dragSmoothX ?? 0,
      worldY: _dragSmoothY ?? 0,
      offsetX: _visualOffsetX,
      offsetY: _visualOffsetY,
      cellSize: cell,
      walls: room.walls,
      preferAxis: prev.axis,
    );
    final key =
        '${placement.axis == GuideAxis.vertical ? 'v' : 'h'}:${placement.lineIndex}';
    setState(() {
      _guides[key] = CeilingGuideMark(
        axis: placement.axis,
        lineIndex: placement.lineIndex,
        kind: prev.kind,
        anchorAlongIndex: placement.anchorIndex,
      );
      _floatingGuide = null;
      _dragSmoothX = null;
      _dragSmoothY = null;
    });
  }

  /// Live guide marks for drawing/counts (includes floating preview at snap).
  List<CeilingGuideMark> _guideMarksForCounts() {
    final marks = _guides.values.toList();
    final floating = _floatingGuide;
    final room = _room;
    if (floating == null || room == null) return marks;
    final placement = snapGuidePlacement(
      worldX: _dragSmoothX ?? 0,
      worldY: _dragSmoothY ?? 0,
      offsetX: _visualOffsetX,
      offsetY: _visualOffsetY,
      cellSize: _grid.cellSizeCm,
      walls: room.walls,
      preferAxis: floating.axis,
    );
    marks.add(CeilingGuideMark(
      axis: placement.axis,
      lineIndex: placement.lineIndex,
      kind: floating.kind,
      anchorAlongIndex: placement.anchorIndex,
    ));
    return marks;
  }

  Map<String, int>? _guideMaterialCounts() {
    if (_room == null) return null;
    final marks = _guideMarksForCounts();
    if (marks.isEmpty) return null;
    return countGuidesFromMarks(
      marks,
      _room!.walls,
      offsetX: _visualOffsetX,
      offsetY: _visualOffsetY,
      cellSize: _grid.cellSizeCm,
    );
  }

  String _guideStatsHint() {
    final counts = _guideMaterialCounts();
    if (counts == null) return '';
    final g3600 = counts['Направляющая 3600'] ?? 0;
    final g1200 = counts['Направляющая 1200'] ?? 0;
    final g600 = counts['Направляющая 600'] ?? 0;
    final g2400 = counts['Направляющая 2400'] ?? 0;
    final parts = <String>[];
    if (g3600 > 0) parts.add('$g3600×3600');
    if (g2400 > 0) parts.add('$g2400×2400');
    if (g1200 > 0) parts.add('$g1200×1200');
    if (g600 > 0) parts.add('$g600×600');
    if (parts.isEmpty) return '';
    return '  ·  Напр.: ${parts.join(' / ')}';
  }

  bool get _joystickEnabled =>
      _mode == LayoutMode.grid ||
      _mode == LayoutMode.pan ||
      _mode == LayoutMode.lights ||
      _mode == LayoutMode.guides;

  void _clearGuides() => setState(_guides.clear);

  void _nudge(double dx, double dy, {bool finalize = false}) {
    final room = _room;
    if (room == null || !_joystickEnabled) return;
    setState(() {
      _visualOffsetX += dx;
      _visualOffsetY += dy;
      if (finalize) {
        _liveGridThrottle?.cancel();
        _commitGridOffset(room);
      } else {
        _scheduleLiveGridSync(room);
      }
    });
  }

  static double _wrapOffset(double v, double period) {
    if (period <= 0) return 0;
    var x = v % period;
    if (x < 0) x += period;
    return x;
  }

  Rect _visibleWorld(Size paintSize, _LayoutMetrics metrics) {
    final m = Matrix4.copy(_transform.value);
    final det = m.invert();
    double minSx;
    double maxSx;
    double minSy;
    double maxSy;
    if (det == 0.0) {
      minSx = 0;
      maxSx = paintSize.width;
      minSy = 0;
      maxSy = paintSize.height;
    } else {
      final corners = <Offset>[
        Offset.zero,
        Offset(paintSize.width, 0),
        Offset(0, paintSize.height),
        Offset(paintSize.width, paintSize.height),
      ].map((p) => MatrixUtils.transformPoint(m, p));
      minSx = double.infinity;
      maxSx = -double.infinity;
      minSy = double.infinity;
      maxSy = -double.infinity;
      for (final p in corners) {
        minSx = math.min(minSx, p.dx);
        maxSx = math.max(maxSx, p.dx);
        minSy = math.min(minSy, p.dy);
        maxSy = math.max(maxSy, p.dy);
      }
    }
    final a = metrics.screenToWorld(Offset(minSx, minSy));
    final b = metrics.screenToWorld(Offset(maxSx, maxSy));
    return Rect.fromLTRB(
      math.min(a.dx, b.dx),
      math.min(a.dy, b.dy),
      math.max(a.dx, b.dx),
      math.max(a.dy, b.dy),
    ).inflate(_grid.cellSizeCm);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = _room;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Раскладка')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }

    final (ef, ec) = _grid.effectiveTileCounts;
    final area = MaterialsCalculator.roomAreaM2(room.walls);
    final perimeter = MaterialsCalculator.roomPerimeterCm(room.walls) / 100;
    final guideHint = _guideStatsHint();
    final stats =
        'Целых: $ef  ·  Резаных: $ec  ·  Свет: ${_grid.lightCount}  ·  '
        'P: ${perimeter.toStringAsFixed(2)} м  ·  '
        'Площадь: ${area.toStringAsFixed(2)} м²  ·  '
        'Смещение: ${_visualOffsetX.round()}×${_visualOffsetY.round()} см'
        '${_mode == LayoutMode.pan && (room.layoutConfirmed || _shouldDefaultPan(room)) ? '  ·  Панорама (сетка заблокирована)' : ''}'
        '$guideHint';

    return Scaffold(
      appBar: AppBar(
        title: Text(room.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _persist();
            if (!mounted) return;
            // Always return to rooms list (Kivy go_back → rooms).
            Navigator.of(context).pop();
          },
        ),
        actions: [
          IconButton(
            tooltip: _mode == LayoutMode.pan ? 'Центрировать' : 'Сброс смещения',
            onPressed: () {
              setState(() {
                if (_mode == LayoutMode.pan) {
                  _viewApplied = false; // re-center on next frame
                } else {
                  _visualOffsetX = 0;
                  _visualOffsetY = 0;
                  _scheduleRebuild(room, immediate: true);
                }
              });
            },
            icon: const Icon(Icons.restart_alt),
          ),
          TextButton(
            onPressed: () async {
              await _persist();
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FinishRoomScreen(
                    projectId: widget.projectId,
                    roomId: widget.roomId,
                  ),
                ),
              );
              await _load();
            },
            child: const Text('Отделка'),
          ),
          TextButton(
            onPressed: () async {
              await _persist();
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MaterialsResultScreen(
                    projectId: widget.projectId,
                    roomId: widget.roomId,
                  ),
                ),
              );
              await _load();
            },
            child: const Text('Материал'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
            child: Text(stats, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Stack(
              children: [
                ColoredBox(
              color: CanvasPalette.bg,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                  // Larger canvas so InteractiveViewer can pan (child == viewport ⇒ no pan).
                  final canvasSize = Size(viewport.width * 2.2, viewport.height * 2.2);
                  final metrics = _LayoutMetrics.compute(canvasSize, room.walls);
                  _lastMetrics = metrics;
                  final visibleWorld = _visibleWorld(viewport, metrics);
                  if (!_viewApplied) {
                    _applyOrCenterView(viewport, canvasSize, metrics);
                  }
                  if (!_canvasReady) {
                    return ColoredBox(color: CanvasPalette.bg);
                  }
                  return InteractiveViewer(
                    transformationController: _transform,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(300),
                    minScale: 0.25,
                    maxScale: 6,
                    panEnabled: _floatingGuide == null &&
                        (_mode == LayoutMode.pan ||
                            _mode == LayoutMode.lights ||
                            _mode == LayoutMode.guides),
                    scaleEnabled: true,
                    child: SizedBox(
                      width: canvasSize.width,
                      height: canvasSize.height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _onTapUp(d, metrics),
                        onLongPressStart: _mode == LayoutMode.guides
                            ? (d) => _onGuideLongPressStart(d, metrics)
                            : null,
                        onLongPressMoveUpdate: _mode == LayoutMode.guides
                            ? (d) => _onGuideLongPressMove(d, metrics)
                            : null,
                        onLongPressEnd: _mode == LayoutMode.guides
                            ? _onGuideLongPressEnd
                            : null,
                        onPanUpdate: _mode == LayoutMode.grid
                            ? (d) {
                                final dx = d.delta.dx / metrics.scale;
                                final dy = -d.delta.dy / metrics.scale;
                                setState(() {
                                  _visualOffsetX += dx;
                                  _visualOffsetY += dy;
                                  _scheduleLiveGridSync(room);
                                });
                              }
                            : null,
                        onPanEnd: _mode == LayoutMode.grid
                            ? (_) {
                                _liveGridThrottle?.cancel();
                                setState(() => _commitGridOffset(room));
                              }
                            : null,
                        onPanCancel: _mode == LayoutMode.grid
                            ? () {
                                _liveGridThrottle?.cancel();
                                setState(() => _commitGridOffset(room));
                              }
                            : null,
                        child: CustomPaint(
                          size: canvasSize,
                          painter: _LayoutPainter(
                            walls: room.walls,
                            grid: _grid,
                            metrics: metrics,
                            showTileDims: _showTileDims,
                            showWallDims: _showWallDims,
                            visualOffsetX: _visualOffsetX,
                            visualOffsetY: _visualOffsetY,
                            visibleWorld: visibleWorld,
                            lightIds: _lightIds,
                            guides: _guides,
                            wallsForGuides: room.walls,
                            showGuides: _mode == LayoutMode.guides,
                            floatingGuide: _floatingGuide,
                            dragSmoothX: _dragSmoothX,
                            dragSmoothY: _dragSmoothY,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
                if (_mode == LayoutMode.guides)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Row(
                      children: [
                        Material(
                          color: Colors.black.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(10),
                          child: IconButton(
                            tooltip: 'Шаблон каркаса',
                            onPressed: _openFrameTemplateDialog,
                            icon: const Icon(Icons.grid_on, color: Color(0xFFFFC857)),
                          ),
                        ),
                        if (_guides.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Material(
                            color: Colors.black.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(10),
                            child: IconButton(
                              tooltip: 'Очистить направляющие',
                              onPressed: _clearGuides,
                              icon: const Icon(Icons.cleaning_services, color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const joyIdeal = 96.0;
                  const sideIdeal = 72.0;
                  const gapIdeal = 12.0;
                  const minTotal = sideIdeal + gapIdeal + joyIdeal + gapIdeal + sideIdeal;
                  final scale = (constraints.maxWidth / minTotal).clamp(0.55, 1.0);
                  final joy = joyIdeal * scale;
                  final side = sideIdeal * scale;
                  final gap = gapIdeal * scale;

                  Widget leftColumn() => SizedBox(
                        width: side,
                        height: joy,
                        child: Column(
                          children: [
                            for (final spec in [
                              (LayoutMode.grid, 'Сетка'),
                              (LayoutMode.pan, 'Панорама'),
                              (LayoutMode.guides, 'Напр.'),
                            ])
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 1),
                                  child: _ModeChip(
                                    label: spec.$2,
                                    selected: _mode == spec.$1,
                                    onTap: () => setState(() => _mode = spec.$1),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );

                  Widget rightColumn() {
                    if (_mode == LayoutMode.guides) {
                      return SizedBox(
                        width: side,
                        height: joy,
                        child: Column(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1),
                                child: _MainGuideSwipeChip(
                                  kind: _mainGuideKind == GuideKind.g2400
                                      ? GuideKind.g2400
                                      : GuideKind.g3600,
                                  selected: _guideKind == GuideKind.g3600 ||
                                      _guideKind == GuideKind.g2400,
                                  accent3600: _guideKindColor(GuideKind.g3600),
                                  accent2400: _guideKindColor(GuideKind.g2400),
                                  onChanged: (kind) => setState(() {
                                    _mainGuideKind = kind;
                                    _guideKind = kind;
                                  }),
                                ),
                              ),
                            ),
                            for (final kind in [GuideKind.g1200, GuideKind.g600])
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 1),
                                  child: _ModeChip(
                                    label: kind.id,
                                    selected: _guideKind == kind,
                                    accent: _guideKindColor(kind),
                                    onTap: () => setState(() => _guideKind = kind),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                    return SizedBox(
                        width: side,
                        height: joy,
                        child: Column(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1),
                                child: _ModeChip(
                                  label: 'Свет',
                                  selected: _mode == LayoutMode.lights,
                                  onTap: () => setState(() => _mode = LayoutMode.lights),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1),
                                child: _ModeChip(
                                  label: 'Плиты',
                                  selected: _showTileDims,
                                  onTap: () => setState(() => _showTileDims = !_showTileDims),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1),
                                child: _ModeChip(
                                  label: 'Стены',
                                  selected: _showWallDims,
                                  onTap: () => setState(() => _showWallDims = !_showWallDims),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                  }

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
                        if (_joystickEnabled)
                          ArrowJoystick(
                            size: joy,
                            onTick: _nudge,
                            onRelease: () => _nudge(0, 0, finalize: true),
                          )
                        else
                          SizedBox(width: joy, height: joy),
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
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = accent;
    return Material(
      color: selected
          ? (accentColor?.withValues(alpha: 0.28) ?? scheme.primaryContainer)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              if (accentColor != null)
                Container(
                  width: 5,
                  color: accentColor,
                ),
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? (accentColor ?? scheme.onPrimaryContainer)
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Long-press + pull down (iOS keyboard style) to switch 3600 ↔ 2400.
class _MainGuideSwipeChip extends StatefulWidget {
  const _MainGuideSwipeChip({
    required this.kind,
    required this.selected,
    required this.onChanged,
    required this.accent3600,
    required this.accent2400,
  });

  /// Currently chosen main runner (3600 or 2400).
  final GuideKind kind;
  final bool selected;
  final ValueChanged<GuideKind> onChanged;
  final Color accent3600;
  final Color accent2400;

  @override
  State<_MainGuideSwipeChip> createState() => _MainGuideSwipeChipState();
}

class _MainGuideSwipeChipState extends State<_MainGuideSwipeChip> {
  bool _pulling = false;
  double _pullDy = 0;
  static const _switchPx = 14.0;
  static const _maxSlide = 10.0;

  GuideKind get _preview {
    if (!_pulling) return widget.kind;
    if (_pullDy > _switchPx) return GuideKind.g2400;
    if (_pullDy < -_switchPx) return GuideKind.g3600;
    return widget.kind;
  }

  void _endPull() {
    final next = _preview;
    setState(() {
      _pulling = false;
      _pullDy = 0;
    });
    if (next != widget.kind || !widget.selected) {
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _preview;
    final accent =
        preview == GuideKind.g2400 ? widget.accent2400 : widget.accent3600;
    final slide = _pullDy.clamp(-_maxSlide, _maxSlide);

    return Material(
      color: widget.selected
          ? accent.withValues(alpha: 0.28)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(widget.kind),
        onVerticalDragStart: (_) => setState(() {
          _pulling = true;
          _pullDy = 0;
        }),
        onVerticalDragUpdate: (d) => setState(() {
          _pullDy += d.delta.dy;
        }),
        onVerticalDragEnd: (_) => _endPull(),
        onVerticalDragCancel: () => setState(() {
          _pulling = false;
          _pullDy = 0;
        }),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    curve: Curves.easeOut,
                    width: 5,
                    color: accent,
                  ),
                  Expanded(
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(0, _pulling ? slide * 0.35 : 0),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 90),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) {
                            final offset = Tween<Offset>(
                              begin: Offset(0, preview == GuideKind.g2400 ? -0.35 : 0.35),
                              end: Offset.zero,
                            ).animate(anim);
                            return FadeTransition(
                              opacity: anim,
                              child: SlideTransition(position: offset, child: child),
                            );
                          },
                          child: Text(
                            preview.id,
                            key: ValueKey(preview.id),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: widget.selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: widget.selected ? accent : scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_pulling)
                Positioned(
                  left: 5,
                  right: 0,
                  bottom: 2,
                  child: Opacity(
                    opacity: (_pullDy.abs() / _switchPx).clamp(0.35, 1.0),
                    child: Text(
                      preview == GuideKind.g2400 ? '↑ 3600' : '↓ 2400',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _guideKindColor(GuideKind kind) {
  switch (kind) {
    case GuideKind.g3600:
      return const Color(0xFF1565C0);
    case GuideKind.g1200:
      return const Color(0xFF2E7D32);
    case GuideKind.g600:
      return const Color(0xFFE65100);
    case GuideKind.g2400:
      return const Color(0xFF6A1B9A);
  }
}

class _LayoutMetrics {
  _LayoutMetrics({
    required this.scale,
    required this.minX,
    required this.minY,
    required this.maxY,
    required this.ox,
    required this.oy,
    required this.roomWidthPx,
    required this.roomHeightPx,
    required this.centroidWorldX,
    required this.centroidWorldY,
    required this.size,
  });

  final double scale;
  final double minX;
  final double minY;
  final double maxY;
  final double ox;
  final double oy;
  final double roomWidthPx;
  final double roomHeightPx;
  final double centroidWorldX;
  final double centroidWorldY;
  final Size size;

  Offset get roomCentroidScreen => Offset(
        ox + (centroidWorldX - minX) * scale,
        oy + (maxY - centroidWorldY) * scale,
      );

  Offset get roomCenterScreen =>
      Offset(ox + roomWidthPx / 2, oy + roomHeightPx / 2);

  double fitScaleForViewport(Size viewport) {
    if (roomWidthPx <= 0 || roomHeightPx <= 0) return 1;
    return math.min(viewport.width / roomWidthPx, viewport.height / roomHeightPx) *
        0.9;
  }

  static _LayoutMetrics compute(Size size, List<List<double>> walls) {
    double minX = 0, maxX = 100, minY = 0, maxY = 100;
    if (walls.isNotEmpty) {
      minX = walls.first[0];
      maxX = walls.first[0];
      minY = walls.first[1];
      maxY = walls.first[1];
      for (final w in walls) {
        for (final x in [w[0], w[2]]) {
          minX = math.min(minX, x);
          maxX = math.max(maxX, x);
        }
        for (final y in [w[1], w[3]]) {
          minY = math.min(minY, y);
          maxY = math.max(maxY, y);
        }
      }
    }
    minX -= 60;
    maxX += 60;
    minY -= 60;
    maxY += 60;
    final worldW = math.max(1.0, maxX - minX);
    final worldH = math.max(1.0, maxY - minY);
    final scale = math.min(size.width / worldW, size.height / worldH) * 0.88;
    final roomWidthPx = worldW * scale;
    final roomHeightPx = worldH * scale;
    final ox = (size.width - roomWidthPx) / 2;
    final oy = (size.height - roomHeightPx) / 2;
    final (cx, cy) = roomCentroidCm(walls);
    return _LayoutMetrics(
      scale: scale,
      minX: minX,
      minY: minY,
      maxY: maxY,
      ox: ox,
      oy: oy,
      roomWidthPx: roomWidthPx,
      roomHeightPx: roomHeightPx,
      centroidWorldX: cx,
      centroidWorldY: cy,
      size: size,
    );
  }

  Offset screenToWorld(Offset p) {
    final x = minX + (p.dx - ox) / scale;
    final y = maxY - (p.dy - oy) / scale;
    return Offset(x, y);
  }
}

class _LayoutPainter extends CustomPainter {
  _LayoutPainter({
    required this.walls,
    required this.grid,
    required this.metrics,
    required this.showTileDims,
    required this.showWallDims,
    required this.visualOffsetX,
    required this.visualOffsetY,
    required this.visibleWorld,
    required this.lightIds,
    required this.guides,
    required this.wallsForGuides,
    required this.showGuides,
    this.floatingGuide,
    this.dragSmoothX,
    this.dragSmoothY,
  });

  final List<List<double>> walls;
  final CeilingGrid grid;
  final _LayoutMetrics metrics;
  final bool showTileDims;
  final bool showWallDims;
  final double visualOffsetX;
  final double visualOffsetY;
  final Rect visibleWorld;
  final Set<String> lightIds;
  final Map<String, CeilingGuideMark> guides;
  final List<List<double>> wallsForGuides;
  final bool showGuides;
  final CeilingGuideMark? floatingGuide;
  final double? dragSmoothX;
  final double? dragSmoothY;

  void _drawGuideCaps(Canvas canvas, Offset a, Offset b, Color color, double stroke) {
    final capR = math.max(stroke * 2.1, 5.5);
    final capPaint = Paint()..color = color;
    final rim = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(a, capR, capPaint);
    canvas.drawCircle(b, capR, capPaint);
    canvas.drawCircle(a, capR, rim);
    canvas.drawCircle(b, capR, rim);
  }

  void _drawGuideRun(
    Canvas canvas, {
    required GuideDrawSegment seg,
    required Color color,
    required double stroke,
    required bool withCaps,
    Offset shadowOffset = Offset.zero,
  }) {
    final a = _map(seg.x1, seg.y1) + shadowOffset;
    final b = _map(seg.x2, seg.y2) + shadowOffset;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, paint);
    if (withCaps) _drawGuideCaps(canvas, a, b, color, stroke);
  }

  static Color _guideColor(GuideKind kind) => _guideKindColor(kind);

  Offset _map(double x, double y) {
    final px = metrics.ox + (x - metrics.minX) * metrics.scale;
    final py = metrics.oy + (metrics.maxY - y) * metrics.scale;
    return Offset(px, py);
  }

  /// World origin of cell — shifts live with [visualOffset] before grid rebuild.
  (double, double) _cellOrigin(GridCell c) {
    final dx = visualOffsetX - grid.offsetXCm;
    final dy = visualOffsetY - grid.offsetYCm;
    return (c.xCm + dx, c.yCm + dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = CanvasPalette.bg);

    final wallPaint = Paint()
      ..color = CanvasPalette.wall
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final fullPaint = Paint()..color = CanvasPalette.fullTile;
    final cutPaint = Paint()..color = CanvasPalette.cutTile;
    final linePaint = Paint()
      ..color = CanvasPalette.grid
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final lightPaint = Paint()..color = const Color.fromRGBO(255, 245, 184, 0.85);
    final cell = grid.cellSizeCm;
    final view = visibleWorld;
    final borderPath = Path();

    // Draw only non-outside tiles (Kivy parity) — no viewport-wide grid.
    for (final c in grid.cells) {
      final (x, y) = _cellOrigin(c);
      if (x + cell < view.left ||
          x > view.right ||
          y + cell < view.top ||
          y > view.bottom) {
        continue;
      }
      final a = _map(x, y);
      final b = _map(x + cell, y + cell);
      final r = Rect.fromPoints(a, b);
      final lit = lightIds.contains(c.id);
      canvas.drawRect(
        r,
        lit ? lightPaint : (c.kind == CellKind.full ? fullPaint : cutPaint),
      );
      borderPath.addRect(r);

      if (showTileDims && c.kind == CellKind.cut) {
        const threshold = 59.95;
        if (c.cutXCm < threshold || c.cutYCm < threshold) {
          final label = '${c.cutXCm.round()}×${c.cutYCm.round()}';
          final fontSize = (9 * (metrics.scale / 2).clamp(0.55, 1.6)).clamp(8.0, 16.0);
          final tp = TextPainter(
            text: TextSpan(
              text: label,
              style: TextStyle(
                color: CanvasPalette.text,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(blurRadius: 3, color: Colors.black87),
                  Shadow(blurRadius: 1, color: Colors.black),
                ],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final origin = r.center - Offset(tp.width / 2, tp.height / 2);
          final chip = RRect.fromRectAndRadius(
            Rect.fromLTWH(origin.dx - 3, origin.dy - 2, tp.width + 6, tp.height + 4),
            const Radius.circular(3),
          );
          canvas.drawRRect(chip, Paint()..color = const Color(0xAA000000));
          tp.paint(canvas, origin);
        }
      }
    }
    canvas.drawPath(borderPath, linePaint);

    if (showGuides) {
      _paintGuides(canvas, view, cell);
    }

    for (final w in walls) {
      final a = _map(w[0], w[1]);
      final b = _map(w[2], w[3]);
      canvas.drawLine(a, b, wallPaint);
      if (showWallDims) {
        final len = math.sqrt(math.pow(w[2] - w[0], 2) + math.pow(w[3] - w[1], 2));
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        final tp = TextPainter(
          text: TextSpan(
            text: len.toStringAsFixed(0),
            style: TextStyle(
              color: CanvasPalette.wall,
              fontSize: 10 * (metrics.scale / 2).clamp(0.7, 1.4),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, mid - Offset(tp.width / 2, tp.height + 2));
      }
    }
  }

  void _paintGuides(Canvas canvas, Rect view, double cell) {
    final cellSize = grid.cellSizeCm;
    for (final e in guides.entries) {
      final mark = e.value;
      final coord = guideLineWorldCoord(
        axis: mark.axis,
        lineIndex: mark.lineIndex,
        gridOffset: mark.axis == GuideAxis.horizontal ? grid.offsetYCm : grid.offsetXCm,
        visualOffset: mark.axis == GuideAxis.horizontal ? visualOffsetY : visualOffsetX,
        cellSize: cellSize,
      );
      final perpAxis =
          mark.axis == GuideAxis.horizontal ? GuideAxis.vertical : GuideAxis.horizontal;
      final anchorCm = guideLineWorldCoord(
        axis: perpAxis,
        lineIndex: mark.anchorAlongIndex,
        gridOffset: perpAxis == GuideAxis.vertical ? grid.offsetXCm : grid.offsetYCm,
        visualOffset: perpAxis == GuideAxis.vertical ? visualOffsetX : visualOffsetY,
        cellSize: cellSize,
      );
      final segments = guideProfilePieceSegments(
        mark,
        wallsForGuides,
        offsetX: visualOffsetX,
        offsetY: visualOffsetY,
        cellSize: cellSize,
        coordCm: coord,
        anchorAlongCm: anchorCm,
      );
      final color = _guideColor(mark.kind);
      final stroke = mark.kind == GuideKind.g3600 ? 4.0 : 2.8;
      for (final seg in segments) {
        final midX = (seg.x1 + seg.x2) * 0.5;
        final midY = (seg.y1 + seg.y2) * 0.5;
        if (midX < view.left - cell || midX > view.right + cell) continue;
        if (midY < view.top - cell || midY > view.bottom + cell) continue;
        _drawGuideRun(
          canvas,
          seg: seg,
          color: color.withValues(alpha: 0.92),
          stroke: stroke,
          withCaps: true,
        );
      }
    }

    if (floatingGuide != null && dragSmoothX != null && dragSmoothY != null) {
      final mark = floatingGuide!;
      final axis = mark.axis;
      final coord = axis == GuideAxis.horizontal ? dragSmoothY! : dragSmoothX!;
      final along = axis == GuideAxis.horizontal ? dragSmoothX! : dragSmoothY!;
      final preview = CeilingGuideMark(
        axis: axis,
        lineIndex: 0,
        kind: mark.kind,
        anchorAlongIndex: 0,
      );
      final segments = guideProfilePieceSegments(
        preview,
        wallsForGuides,
        offsetX: visualOffsetX,
        offsetY: visualOffsetY,
        cellSize: cellSize,
        coordCm: coord,
        anchorAlongCm: along,
      );
      final color = _guideColor(mark.kind);
      const floatStroke = 5.5;
      for (final seg in segments) {
        final midX = (seg.x1 + seg.x2) * 0.5;
        final midY = (seg.y1 + seg.y2) * 0.5;
        if (midX < view.left - cell || midX > view.right + cell) continue;
        if (midY < view.top - cell || midY > view.bottom + cell) continue;
        _drawGuideRun(
          canvas,
          seg: seg,
          color: Colors.black.withValues(alpha: 0.22),
          stroke: floatStroke + 1.5,
          withCaps: false,
          shadowOffset: const Offset(1.5, 2.5),
        );
        _drawGuideRun(
          canvas,
          seg: seg,
          color: color.withValues(alpha: 0.95),
          stroke: floatStroke,
          withCaps: true,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutPainter old) {
    return old.walls != walls ||
        old.grid.cells != grid.cells ||
        old.grid.offsetXCm != grid.offsetXCm ||
        old.grid.offsetYCm != grid.offsetYCm ||
        old.grid.cellSizeCm != grid.cellSizeCm ||
        old.metrics.scale != metrics.scale ||
        old.metrics.minX != metrics.minX ||
        old.metrics.minY != metrics.minY ||
        old.metrics.size != metrics.size ||
        old.showTileDims != showTileDims ||
        old.showWallDims != showWallDims ||
        old.visualOffsetX != visualOffsetX ||
        old.visualOffsetY != visualOffsetY ||
        old.visibleWorld != visibleWorld ||
        old.lightIds.length != lightIds.length ||
        !old.lightIds.containsAll(lightIds) ||
        old.guides.length != guides.length ||
        !mapEquals(old.guides, guides) ||
        old.wallsForGuides != wallsForGuides ||
        old.showGuides != showGuides ||
        old.floatingGuide != floatingGuide ||
        old.dragSmoothX != dragSmoothX ||
        old.dragSmoothY != dragSmoothY;
  }
}
