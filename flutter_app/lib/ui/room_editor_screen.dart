import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../domain/dimension_lines.dart';
import '../domain/finish_model.dart' show AppModule, RoomOpening;
import '../domain/layout_contour_sync.dart';
import '../domain/materials_calculator.dart';
import '../domain/models.dart';
import '../domain/opening_remap.dart';
import '../domain/plan_orthogonal.dart';
import '../domain/room_draft.dart';
import '../domain/wall_geometry.dart';
import 'adaptive_layout.dart';
import 'desktop_cascade.dart';
import 'finish_overview_editor_screen.dart';
import 'finish_room_screen.dart';
import 'geometry_capture_hub_screen.dart';
import 'layout_screen.dart';
import 'widgets/canvas_palette.dart';
import 'widgets/controls.dart';
import 'widgets/numeric_input.dart';

/// World ↔ canvas mapping for room editor (shared by painter and camera centering).
class RoomEditorMetrics {
  const RoomEditorMetrics({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.canvasSize,
  });

  final double minX, maxX, minY, maxY, scale, padX, padY;
  final Size canvasSize;

  double get worldW => math.max(1.0, maxX - minX);
  double get worldH => math.max(1.0, maxY - minY);

  static RoomEditorMetrics compute({
    required List<List<double>> walls,
    required List<double> cursor,
    required Size canvasSize,
  }) {
    var minX = cursor[0];
    var maxX = cursor[0];
    var minY = cursor[1];
    var maxY = cursor[1];
    if (walls.isNotEmpty) {
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
    minX -= 40;
    maxX += 40;
    minY -= 40;
    maxY += 40;
    final worldW = math.max(1.0, maxX - minX);
    final worldH = math.max(1.0, maxY - minY);
    final s = math.min(canvasSize.width / worldW, canvasSize.height / worldH) * 0.9;
    final padX = (canvasSize.width - worldW * s) / 2;
    final padY = (canvasSize.height - worldH * s) / 2;
    return RoomEditorMetrics(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      scale: s,
      padX: padX,
      padY: padY,
      canvasSize: canvasSize,
    );
  }

  Offset worldToCanvas(double x, double y) {
    final px = (x - minX) * scale + padX;
    final py = canvasSize.height - ((y - minY) * scale + padY);
    return Offset(px, py);
  }

  Offset canvasToWorld(Offset p) {
    final x = (p.dx - padX) / scale + minX;
    final y = (canvasSize.height - p.dy - padY) / scale + minY;
    return Offset(x, y);
  }

  /// Canvas-space bounds of walls + cursor (for viewport fitting).
  Rect contentBounds({
    required List<List<double>> walls,
    required List<double> cursor,
  }) {
    var minCx = double.infinity;
    var maxCx = -double.infinity;
    var minCy = double.infinity;
    var maxCy = -double.infinity;

    void include(double wx, double wy) {
      final p = worldToCanvas(wx, wy);
      minCx = math.min(minCx, p.dx);
      maxCx = math.max(maxCx, p.dx);
      minCy = math.min(minCy, p.dy);
      maxCy = math.max(maxCy, p.dy);
    }

    for (final w in walls) {
      include(w[0], w[1]);
      include(w[2], w[3]);
    }
    include(cursor[0], cursor[1]);

    if (minCx == double.infinity) {
      final c = worldToCanvas(cursor[0], cursor[1]);
      return Rect.fromCenter(center: c, width: 160, height: 160);
    }

    const pad = 24.0;
    return Rect.fromLTRB(
      minCx - pad,
      minCy - pad,
      maxCx + pad,
      maxCy + pad,
    );
  }
}

class RoomEditorScreen extends StatefulWidget {
  const RoomEditorScreen({
    super.key,
    required this.projectId,
    required this.roomId,
    this.module = AppModule.ceilingLayout,
  });

  final int projectId;
  final int roomId;
  /// Ceiling → [LayoutScreen]; finish → [FinishOverviewEditorScreen].
  final AppModule module;

  @override
  State<RoomEditorScreen> createState() => _RoomEditorScreenState();
}

class _RoomEditorScreenState extends State<RoomEditorScreen> {
  Room? _room;
  late RoomDraft _draft;
  bool _loading = true;
  final _transform = TransformationController();
  Size? _lastViewport;
  bool _viewInitialized = false;
  List<RoomOpening> _openings = [];
  bool _openingsDirty = false;
  int? _dragVertex;
  int? _selectedVertex;
  int? _placingIndex;
  int? _selectedOpening;
  int? _dragOpening;
  bool _orthoDefault = true;
  /// Finger→world gain while dragging a corner (<1 = less sensitive).
  static const _vertexDragGain = 0.42;
  Offset? _dragOriginWorld;
  Offset? _dragFingerOriginWorld;

  static const _minScale = 0.01;
  static const _maxScale = 6.0;
  static const _viewportMargin = 0.05;
  /// On entry, never zoom in closer than this (medium view; cursor stays centered).
  static const _initialScaleCap = 0.5;
  static const _canvasFactor = 8.0;
  static const _vertexHitPx = 28.0;

  Size _canvasSize(Size viewport) =>
      Size(viewport.width * _canvasFactor, viewport.height * _canvasFactor);

  static const _dirLabels = {
    'up': 'вверх',
    'down': 'вниз',
    'left': 'влево',
    'right': 'вправо',
    'up_left': 'вверх-влево',
    'up_right': 'вверх-вправо',
    'down_left': 'вниз-влево',
    'down_right': 'вниз-вправо',
  };

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  double _lastLabelScale = 1;

  void _onTransformChanged() {
    if (!mounted) return;
    final s = _transform.value.getMaxScaleOnAxis();
    if ((s - _lastLabelScale).abs() / math.max(_lastLabelScale, 0.01) < 0.04) {
      return;
    }
    _lastLabelScale = s;
    setState(() {});
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
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
      _room = room;
      _draft = RoomDraft(
        walls: room?.walls,
        cursor: room?.lastPosition ??
            (room != null && room.walls.isNotEmpty
                ? [room.walls.last[2], room.walls.last[3]]
                : [0, 0]),
      );
      _draft.seedUndoBaseline();
      _openings = room?.openings.map(RoomOpening.fromJson).toList() ?? [];
      _openingsDirty = false;
      _dragVertex = null;
      _selectedVertex = null;
      _placingIndex = null;
      _selectedOpening = null;
      _dragOpening = null;
      _loading = false;
      _viewInitialized = false;
    });
  }

  void _fitInitialView() {
    final viewport = _lastViewport;
    if (viewport == null || !mounted) return;
    final m = _currentMetrics();
    final bounds = m.contentBounds(walls: _draft.walls, cursor: _draft.cursor);
    final cursor = m.worldToCanvas(_draft.cursor[0], _draft.cursor[1]);
    var scale = math.min(_scaleToFit(bounds), _initialScaleCap);
    scale = _scaleKeepingFocalVisible(
      bounds: bounds,
      focalCanvas: cursor,
      preferredScale: scale,
    );
    _applyTransform(scale: scale, focalCanvas: cursor);
    _viewInitialized = true;
  }

  void _centerOnCursor() {
    final viewport = _lastViewport;
    if (viewport == null || !mounted) return;
    final scale = _transform.value.getMaxScaleOnAxis();
    final m = _currentMetrics();
    final focal = m.worldToCanvas(_draft.cursor[0], _draft.cursor[1]);
    _applyTransform(scale: scale, focalCanvas: focal);
  }

  RoomEditorMetrics _currentMetrics() {
    final viewport = _lastViewport!;
    return RoomEditorMetrics.compute(
      walls: _draft.walls,
      cursor: _draft.cursor,
      canvasSize: _canvasSize(viewport),
    );
  }

  double _scaleToFit(Rect canvasBounds) {
    final viewport = _lastViewport!;
    final availW = viewport.width * (1 - 2 * _viewportMargin);
    final availH = viewport.height * (1 - 2 * _viewportMargin);
    final contentW = math.max(canvasBounds.width, 1.0);
    final contentH = math.max(canvasBounds.height, 1.0);
    final scale = math.min(availW / contentW, availH / contentH);
    return scale.clamp(_minScale, _maxScale);
  }

  double _scaleKeepingFocalVisible({
    required Rect bounds,
    required Offset focalCanvas,
    required double preferredScale,
  }) {
    var scale = preferredScale.clamp(_minScale, _maxScale);
    while (scale > _minScale && !_focalFramingShowsBounds(bounds, focalCanvas, scale)) {
      scale *= 0.92;
    }
    return scale.clamp(_minScale, _maxScale);
  }

  bool _focalFramingShowsBounds(Rect bounds, Offset focalCanvas, double scale) {
    final viewport = _lastViewport!;
    final inset = Rect.fromLTWH(
      viewport.width * _viewportMargin,
      viewport.height * _viewportMargin,
      viewport.width * (1 - 2 * _viewportMargin),
      viewport.height * (1 - 2 * _viewportMargin),
    );
    final points = [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ];
    for (final p in points) {
      final sx = viewport.width / 2 + (p.dx - focalCanvas.dx) * scale;
      final sy = viewport.height / 2 + (p.dy - focalCanvas.dy) * scale;
      if (!inset.contains(Offset(sx, sy))) return false;
    }
    return true;
  }

  void _ensureContentVisible() {
    final viewport = _lastViewport;
    if (viewport == null || !mounted) return;
    final m = _currentMetrics();
    final bounds = m.contentBounds(walls: _draft.walls, cursor: _draft.cursor);
    final needed = _scaleToFit(bounds);
    final current = _transform.value.getMaxScaleOnAxis();
    if (needed >= current - 0.0001 && _focalFramingShowsBounds(
          bounds,
          _screenFocalFromTransform(),
          current,
        )) {
      return;
    }
    final scale = math.min(current, needed);
    _applyTransform(scale: scale, focalCanvas: bounds.center);
  }

  Offset _screenFocalFromTransform() {
    final viewport = _lastViewport!;
    final scale = _transform.value.getMaxScaleOnAxis();
    if (scale <= 0) return Offset(viewport.width / 2, viewport.height / 2);
    final tx = _transform.value.storage[12];
    final ty = _transform.value.storage[13];
    return Offset(
      (viewport.width / 2 - tx) / scale,
      (viewport.height / 2 - ty) / scale,
    );
  }

  void _applyTransform({
    required double scale,
    required Offset focalCanvas,
  }) {
    final viewport = _lastViewport;
    if (viewport == null || !mounted) return;
    final tx = viewport.width / 2 - focalCanvas.dx * scale;
    final ty = viewport.height / 2 - focalCanvas.dy * scale;
    _transform.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    _lastLabelScale = scale;
    // Force dim labels to recompute for the new zoom.
    setState(() {});
  }

  Future<void> _persist() async {
    final room = _room;
    if (room == null) return;
    final oldWalls = room.walls.map((w) => List<double>.from(w)).toList();
    final placedBefore = room.openings
        .map(RoomOpening.fromJson)
        .where((o) => o.wallIndex != null)
        .length;
    room.walls = _draft.walls.map((w) => List<double>.from(w)).toList();
    room.lastPosition = List<double>.from(_draft.cursor);
    room.openings = _openings.map((e) => e.toJson()).toList();
    if (oldWalls.isNotEmpty) {
      remapRoomOpeningsAfterWallChange(room, oldWalls: oldWalls);
      _openings = room.openings.map(RoomOpening.fromJson).toList();
    }
    final placedAfter = room.openings
        .map(RoomOpening.fromJson)
        .where((o) => o.wallIndex != null)
        .length;
    final sync = syncLayoutFeaturesToContour(room);
    await AppScope.of(context).projects.updateRoom(room);
    _openingsDirty = false;
    if (!mounted) return;
    final parts = <String>[];
    if (sync.summaryRu.isNotEmpty) parts.add(sync.summaryRu);
    final unplaced = placedBefore - placedAfter;
    if (unplaced > 0) parts.add('проёмы без стены: $unplaced');
    if (parts.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Контур сохранён · ${parts.join(' · ')}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  bool get _isDirty {
    final room = _room;
    if (room == null) return false;
    if (_openingsDirty) return true;
    if (_draft.walls.length != room.walls.length) return true;
    for (var i = 0; i < _draft.walls.length; i++) {
      final a = _draft.walls[i];
      final b = room.walls[i];
      if (a.length != b.length) return true;
      for (var j = 0; j < a.length; j++) {
        if ((a[j] - b[j]).abs() > 0.05) return true;
      }
    }
    return false;
  }

  int? _hitVertex(Offset canvasPt, RoomEditorMetrics m) {
    final pts = _draft.orderedPoints();
    final scale = _transform.value.getMaxScaleOnAxis().clamp(0.01, 20.0);
    final hitR = _vertexHitPx / scale;
    var bestI = -1;
    var bestD = hitR;
    for (var i = 0; i < pts.length; i++) {
      final c = m.worldToCanvas(pts[i].$1, pts[i].$2);
      final d = (c - canvasPt).distance;
      if (d < bestD) {
        bestD = d;
        bestI = i;
      }
    }
    return bestI >= 0 ? bestI : null;
  }

  int? _hitOpening(Offset world) {
    var bestI = -1;
    var bestD = 40.0;
    final walls = _draft.walls;
    for (var i = 0; i < _openings.length; i++) {
      final o = _openings[i];
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

  void _onCanvasTap(Offset canvasPt) {
    final m = _currentMetrics();
    final world = m.canvasToWorld(canvasPt);
    if (_placingIndex != null) {
      _placeOpeningAt(world, clearPlacing: true);
      return;
    }
    final oi = _hitOpening(world);
    if (oi != null) {
      setState(() {
        _selectedOpening = _selectedOpening == oi ? null : oi;
        _selectedVertex = null;
      });
      return;
    }
    final hit = _hitVertex(canvasPt, m);
    setState(() {
      _selectedVertex = hit == _selectedVertex ? null : hit;
      _selectedOpening = null;
    });
  }

  void _placeOpeningAt(Offset world, {required bool clearPlacing}) {
    final i = _dragOpening ?? _placingIndex ?? _selectedOpening;
    if (i == null || i < 0 || i >= _openings.length) return;
    final hit = nearestWallHit(_draft.walls, world.dx, world.dy, maxDistCm: 50);
    if (hit == null) return;
    final o = _openings[i];
    var start = hit.offsetAlongCm - o.widthCm / 2;
    start = start.clamp(0.0, math.max(0.0, hit.wallLengthCm - o.widthCm));
    setState(() {
      o.wallIndex = hit.wallIndex;
      o.offsetAlongWallCm = start;
      if (clearPlacing) _placingIndex = null;
      _selectedOpening = i;
      _openingsDirty = true;
    });
  }

  List<Offset> _pointsAsOffsets() => [
        for (final p in _draft.orderedPoints()) Offset(p.$1, p.$2),
      ];

  void _applyOrthoDrag(int index, Offset world) {
    var p = world;
    final pts = _pointsAsOffsets();
    if (_orthoDefault && pts.length >= 3) {
      final trial = List<Offset>.from(pts)..[index] = p;
      Offset? best;
      // Soft pull while dragging; hard snap on release.
      const magnet = 42.0;
      var bestD = magnet * magnet;
      for (final c in orthoCornerCandidates(trial, index)) {
        final d = (c - p).distanceSquared;
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      if (best != null) {
        final dist = math.sqrt(bestD);
        final t = (1.0 - dist / magnet).clamp(0.0, 1.0);
        final ease = Curves.easeOutCubic.transform(t);
        p = Offset.lerp(p, best, 0.18 + 0.55 * ease)!;
      }
    }
    _draft.moveVertex(index, p.dx, p.dy, recordUndo: false);
  }

  void _finishVertexDrag() {
    final i = _dragVertex;
    if (i == null) {
      setState(() {
        _dragVertex = null;
        _dragOriginWorld = null;
        _dragFingerOriginWorld = null;
      });
      return;
    }
    if (_orthoDefault && _draft.orderedPoints().length >= 3) {
      final closed = _draft.isClosed;
      final snapped = snapVertexNeighborhoodToRightAngles(
        _pointsAsOffsets(),
        i,
        magnetDeg: 20,
      );
      _draft.replacePoints(
        [for (final p in snapped) (p.dx, p.dy)],
        closed: closed,
        recordUndo: false,
      );
    }
    setState(() {
      _dragVertex = null;
      _dragOriginWorld = null;
      _dragFingerOriginWorld = null;
    });
  }

  Future<void> _onAddOpeningFab() async {
    if (_placingIndex != null) {
      setState(() {
        final i = _placingIndex!;
        if (i >= 0 &&
            i < _openings.length &&
            _openings[i].wallIndex == null) {
          _openings.removeAt(i);
          _openingsDirty = true;
        }
        _placingIndex = null;
      });
      return;
    }
    if (_draft.walls.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала нарисуйте контур')),
      );
      return;
    }
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
    setState(() {
      _openings.add(
        RoomOpening(
          kind: kind,
          widthCm: widthCm,
          heightCm: heightCm,
          sillHeightCm: sill,
        ),
      );
      _placingIndex = _openings.length - 1;
      _openingsDirty = true;
      _selectedVertex = null;
      _selectedOpening = null;
      _dragOpening = null;
    });
  }

  /// Leave editor: save / discard / cancel when dirty.
  Future<bool> _leaveEditor({required Future<void> Function() afterSaveOrDiscard}) async {
    if (!_isDirty) {
      await afterSaveOrDiscard();
      return true;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сохранить контур?'),
        content: Text(
          _draft.walls.isEmpty
              ? 'Черновик пуст — сохранение сотрёт существующий контур и срежет свет/направляющие.'
              : !_draft.isClosed && _draft.walls.length >= 3
                  ? 'Контур не замкнут. Сохранить как есть или отменить изменения?'
                  : 'Есть несохранённые изменения контура.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Остаться')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Не сохранять')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Сохранить')),
        ],
      ),
    );
    if (choice == null || choice == 'cancel' || !mounted) return false;
    if (choice == 'save') {
      if (_draft.walls.isEmpty && (_room?.walls.isNotEmpty ?? false)) {
        final wipe = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Стереть контур?'),
            content: const Text(
              'Пустой контур перезапишет комнату. Свет, направляющие и проёмы на плане будут сброшены.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Стереть')),
            ],
          ),
        );
        if (wipe != true || !mounted) return false;
      }
      await _persist();
    }
    if (!mounted) return false;
    await afterSaveOrDiscard();
    return true;
  }

  bool get _isFinish => widget.module == AppModule.finish;

  String get _nextEditorLabel => _isFinish ? 'К отделке' : 'Раскладка';

  /// After save/discard: finish + closed contour → room tabs; else pop / closeDetail.
  Future<void> _exitAfterEditor() async {
    if (!mounted) return;
    final closed = _draft.isClosed && _draft.walls.length >= 3;
    final cascade = DesktopCascadeHost.maybeOf(context);
    if (_isFinish && closed) {
      final page = FinishRoomScreen(
        projectId: widget.projectId,
        roomId: widget.roomId,
      );
      if (cascade != null) {
        cascade.openDetail(
          page,
          title: _room?.name ?? 'Отделка',
          detailId: 'room:${widget.roomId}',
        );
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => page),
      );
      return;
    }
    if (cascade != null) {
      cascade.closeDetail();
      return;
    }
    Navigator.of(context).pop();
  }

  /// Hover preview for click-to-draw (canvas coords).
  String? _hoverDrawDir;
  Offset? _hoverArrowFrom;
  Offset? _hoverArrowTo;

  bool _useEditorDesktopChrome(BuildContext context) {
    return DesktopCascadeHost.maybeOf(context) != null ||
        AdaptiveBreakpoints.useDesktopChrome(context);
  }

  String? _dirFromDelta(Offset delta, {double minDist = 12}) {
    if (delta.distance < minDist) return null;
    final absDx = delta.dx.abs();
    final absDy = delta.dy.abs();
    if (absDx >= absDy) {
      return delta.dx >= 0 ? 'right' : 'left';
    }
    return delta.dy < 0 ? 'up' : 'down';
  }

  void _updateHoverDrawPreview(Offset localPos) {
    if (_placingIndex != null || _dragVertex != null || _dragOpening != null) {
      if (_hoverDrawDir != null) {
        setState(() {
          _hoverDrawDir = null;
          _hoverArrowFrom = null;
          _hoverArrowTo = null;
        });
      }
      return;
    }
    final m = _currentMetrics();
    final cursorCanvas =
        m.worldToCanvas(_draft.cursor[0], _draft.cursor[1]);
    final delta = localPos - cursorCanvas;
    final dir = _dirFromDelta(delta);
    if (dir == null) {
      if (_hoverDrawDir != null) {
        setState(() {
          _hoverDrawDir = null;
          _hoverArrowFrom = null;
          _hoverArrowTo = null;
        });
      }
      return;
    }
    final len = 56.0;
    final tip = switch (dir) {
      'right' => cursorCanvas + Offset(len, 0),
      'left' => cursorCanvas + Offset(-len, 0),
      'up' => cursorCanvas + Offset(0, -len),
      _ => cursorCanvas + Offset(0, len),
    };
    setState(() {
      _hoverDrawDir = dir;
      _hoverArrowFrom = cursorCanvas;
      _hoverArrowTo = tip;
    });
  }

  void _onCanvasTapDownDraw(TapDownDetails details) {
    if (_placingIndex != null || _dragVertex != null || _dragOpening != null) {
      return;
    }
    final m = _currentMetrics();
    if (_hitVertex(details.localPosition, m) != null) return;
    final cursorCanvas =
        m.worldToCanvas(_draft.cursor[0], _draft.cursor[1]);
    final dir = _dirFromDelta(details.localPosition - cursorCanvas);
    if (dir == null) return;
    // ignore: discarded_futures
    _askLength(dir);
  }

  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_placingIndex != null) return KeyEventResult.ignored;
    // Physical keys: WASD / arrows work regardless of input language.
    final key = event.physicalKey;
    String? dir;
    if (key == PhysicalKeyboardKey.arrowUp ||
        key == PhysicalKeyboardKey.keyW) {
      dir = 'up';
    } else if (key == PhysicalKeyboardKey.arrowDown ||
        key == PhysicalKeyboardKey.keyS) {
      dir = 'down';
    } else if (key == PhysicalKeyboardKey.arrowLeft ||
        key == PhysicalKeyboardKey.keyA) {
      dir = 'left';
    } else if (key == PhysicalKeyboardKey.arrowRight ||
        key == PhysicalKeyboardKey.keyD) {
      dir = 'right';
    } else if (key == PhysicalKeyboardKey.keyC &&
        _draft.walls.length >= 3 &&
        !_draft.isClosed) {
      setState(() => _draft.closeRoom());
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    // ignore: discarded_futures
    _askLength(dir);
    return KeyEventResult.handled;
  }

  Future<void> _goNextEditor() async {
    if (!_draft.isClosed) {
      if (_draft.walls.length >= 3) {
        final close = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Замкнуть контур?'),
            content: Text(
              _isFinish
                  ? 'Для редактора отделки нужен замкнутый контур. Замкнуть сейчас и открыть слои?'
                  : 'Для раскладки нужен замкнутый контур. Замкнуть сейчас и открыть раскладку?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Замкнуть')),
            ],
          ),
        );
        if (close != true || !mounted) return;
        setState(() => _draft.closeRoom());
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нужны минимум 3 стены и замкнутый контур')),
        );
        return;
      }
    }
    await _persist();
    if (!mounted) return;
    if (_isFinish) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FinishOverviewEditorScreen(
            projectId: widget.projectId,
            roomId: widget.roomId,
          ),
        ),
      );
    } else {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LayoutScreen(
            projectId: widget.projectId,
            roomId: widget.roomId,
          ),
        ),
      );
    }
  }

  Future<void> _askLength(String direction) async {
    final controller = TextEditingController();
    final length = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Длина (${_dirLabels[direction] ?? direction})',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: NumericInput.decimalKeyboard,
                inputFormatters: NumericInput.decimalFormatters,
                decoration: const InputDecoration(
                  hintText: 'см',
                  suffixText: 'см',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) {
                  final n = double.tryParse(v.replaceAll(',', '.'));
                  if (n != null && n > 0) Navigator.pop(ctx, n);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final n = double.tryParse(controller.text.replaceAll(',', '.'));
                        if (n != null && n > 0) Navigator.pop(ctx, n);
                      },
                      child: const Text('Подтвердить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (length == null) return;
    setState(() => _draft.addWall(direction, length));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureContentVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Редактор')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }

    final area = MaterialsCalculator.roomAreaM2(_draft.walls);
    final perimeter = MaterialsCalculator.roomPerimeterCm(_draft.walls) / 100;
    // ARCHIVED: wallDiff vs проект — `_archived/finish_project_vs_fact_ui.dart.txt`
    final info =
        'Точка (${_draft.cursor[0].toStringAsFixed(1)}, ${_draft.cursor[1].toStringAsFixed(1)})  ·  '
        'Стен: ${_draft.walls.length}  ·  '
        'P: ${perimeter.toStringAsFixed(2)} м  ·  '
        'Площадь: ${area.toStringAsFixed(2)} м²'
        '${_draft.isClosed ? '  ·  замкнута' : ''}';
    final desktopChrome = _useEditorDesktopChrome(context);

    return Focus(
      autofocus: desktopChrome,
      onKeyEvent: _onEditorKey,
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leaveEditor(afterSaveOrDiscard: _exitAfterEditor);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_room!.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _leaveEditor(afterSaveOrDiscard: _exitAfterEditor),
        ),
        actions: [
          // ARCHIVED: Project vs fact overlay toggle — see `_archived/README.md`
          IconButton(
            tooltip: 'Захват помещения',
            onPressed: () async {
              final ok = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => GeometryCaptureHubScreen(
                    projectId: widget.projectId,
                    roomId: widget.roomId,
                    module: widget.module,
                  ),
                ),
              );
              if (ok == true) await _load();
            },
            icon: const Icon(Icons.photo_size_select_large_outlined),
          ),
          IconButton(
            tooltip: 'Отменить',
            onPressed: _draft.canUndo ? () => setState(() => _draft.undo()) : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Повторить',
            onPressed: _draft.canRedo ? () => setState(() => _draft.redo()) : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: 'К точке',
            onPressed: _centerOnCursor,
            icon: const Icon(Icons.center_focus_strong),
          ),
          TextButton(
            onPressed: _draft.isClosed
                ? _goNextEditor
                : (_draft.walls.length >= 3 ? _goNextEditor : null),
            child: Text(_nextEditorLabel),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              desktopChrome
                  ? '$info\nКлик / стрелки / WASD — стена · C — замкнуть · джойстик справа'
                  : info,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: CanvasPalette.bg,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                  _lastViewport = viewport;
                  if (!_viewInitialized) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_viewInitialized) _fitInitialView();
                    });
                  }
                  final canvasSize = _canvasSize(viewport);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      InteractiveViewer(
                        transformationController: _transform,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(500000),
                        minScale: _minScale,
                        maxScale: _maxScale,
                        panEnabled:
                            _dragVertex == null && _dragOpening == null,
                        scaleEnabled:
                            _dragVertex == null && _dragOpening == null,
                        child: SizedBox(
                          width: canvasSize.width,
                          height: canvasSize.height,
                          child: MouseRegion(
                            onHover: desktopChrome
                                ? (e) =>
                                    _updateHoverDrawPreview(e.localPosition)
                                : null,
                            onExit: desktopChrome
                                ? (_) {
                                    if (_hoverDrawDir == null) return;
                                    setState(() {
                                      _hoverDrawDir = null;
                                      _hoverArrowFrom = null;
                                      _hoverArrowTo = null;
                                    });
                                  }
                                : null,
                            child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: desktopChrome
                                ? _onCanvasTapDownDraw
                                : null,
                            onTapUp: (d) => _onCanvasTap(d.localPosition),
                            onLongPressStart: (d) {
                              final m = _currentMetrics();
                              final world = m.canvasToWorld(d.localPosition);
                              final oi = _hitOpening(world);
                              if (oi != null) {
                                setState(() {
                                  _dragOpening = oi;
                                  _selectedOpening = oi;
                                  _placingIndex = null;
                                  _dragVertex = null;
                                  _selectedVertex = null;
                                });
                                return;
                              }
                              final hit = _hitVertex(d.localPosition, m);
                              if (hit == null) return;
                              final pts = _pointsAsOffsets();
                              setState(() {
                                _draft.saveUndo();
                                _dragVertex = hit;
                                _selectedVertex = hit;
                                _placingIndex = null;
                                _selectedOpening = null;
                                _dragOpening = null;
                                _dragOriginWorld = hit < pts.length
                                    ? pts[hit]
                                    : world;
                                _dragFingerOriginWorld = world;
                              });
                            },
                            onLongPressMoveUpdate: (d) {
                              final m = _currentMetrics();
                              final w = m.canvasToWorld(d.localPosition);
                              final oi = _dragOpening;
                              if (oi != null) {
                                _placeOpeningAt(w, clearPlacing: false);
                                return;
                              }
                              final i = _dragVertex;
                              if (i == null) return;
                              final origin = _dragOriginWorld;
                              final finger0 = _dragFingerOriginWorld;
                              final target = (origin != null && finger0 != null)
                                  ? origin + (w - finger0) * _vertexDragGain
                                  : w;
                              setState(() => _applyOrthoDrag(i, target));
                            },
                            onLongPressEnd: (_) {
                              if (_dragOpening != null) {
                                setState(() => _dragOpening = null);
                                return;
                              }
                              _finishVertexDrag();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _ensureContentVisible();
                              });
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CustomPaint(
                                  size: canvasSize,
                                  painter: _WallsPainter(
                                    walls: _draft.walls,
                                    cursor: _draft.cursor,
                                    isClosed: _draft.isClosed,
                                    openings: _openings,
                                    selectedVertex: _selectedVertex,
                                    dragVertex: _dragVertex,
                                    placingIndex: _placingIndex,
                                    selectedOpeningIndex:
                                        _dragOpening ?? _selectedOpening,
                                    showAngles: _dragVertex != null,
                                    transform: _transform,
                                  ),
                                ),
                                if (desktopChrome &&
                                    _hoverArrowFrom != null &&
                                    _hoverArrowTo != null &&
                                    _hoverDrawDir != null)
                                  CustomPaint(
                                    size: canvasSize,
                                    painter: _DrawDirArrowPainter(
                                      from: _hoverArrowFrom!,
                                      to: _hoverArrowTo!,
                                      label: _dirLabels[_hoverDrawDir!] ??
                                          _hoverDrawDir!,
                                    ),
                                  ),
                              ],
                            ),
                          ), // GestureDetector
                          ), // MouseRegion
                        ), // SizedBox
                      ), // InteractiveViewer
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Material(
                              color: _orthoDefault
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.85)
                                  : Colors.black.withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: () => setState(
                                  () => _orthoDefault = !_orthoDefault,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    '90°',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Material(
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
                          ],
                        ),
                      ),
                      if (_placingIndex != null)
                        Positioned(
                          top: 52,
                          right: 8,
                          left: 8,
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
                      if (!desktopChrome)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_draft.walls.length >= 3 &&
                                      !_draft.isClosed)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            setState(() => _draft.closeRoom()),
                                        icon: const Icon(Icons.link),
                                        label: const Text('Замкнуть комнату'),
                                      ),
                                    ),
                                  AnalogJoystick(onDirection: _askLength),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (desktopChrome) ...[
                        if (_draft.walls.length >= 3 && !_draft.isClosed)
                          Positioned(
                            left: 12,
                            bottom: 12,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => _draft.closeRoom()),
                              icon: const Icon(Icons.link),
                              label: const Text('Замкнуть комнату'),
                            ),
                          ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Material(
                            elevation: 3,
                            borderRadius: BorderRadius.circular(16),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLowest
                                .withValues(alpha: 0.94),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: AnalogJoystick(
                                size: 128,
                                onDirection: _askLength,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
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

class _DrawDirArrowPainter extends CustomPainter {
  _DrawDirArrowPainter({
    required this.from,
    required this.to,
    required this.label,
  });

  final Offset from;
  final Offset to;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A56DB)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, paint);
    final dir = to - from;
    if (dir.distance < 1) return;
    final n = dir / dir.distance;
    final orth = Offset(-n.dy, n.dx);
    final tip = to;
    final a = tip - n * 14 + orth * 8;
    final b = tip - n * 14 - orth * 8;
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..close();
    canvas.drawPath(
      head,
      Paint()
        ..color = const Color(0xFF1A56DB)
        ..style = PaintingStyle.fill,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF1A56DB),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          backgroundColor: Color(0xE6FFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, tip + const Offset(8, -18));
  }

  @override
  bool shouldRepaint(covariant _DrawDirArrowPainter old) =>
      old.from != from || old.to != to || old.label != label;
}

class _WallsPainter extends CustomPainter {
  _WallsPainter({
    required this.walls,
    required this.cursor,
    required this.isClosed,
    required this.transform,
    this.openings = const [],
    this.selectedVertex,
    this.dragVertex,
    this.placingIndex,
    this.selectedOpeningIndex,
    this.showAngles = false,
  }) : super(repaint: transform);

  final List<List<double>> walls;
  final List<double> cursor;
  final bool isClosed;
  final TransformationController transform;
  final List<RoomOpening> openings;
  final int? selectedVertex;
  final int? dragVertex;
  final int? placingIndex;
  final int? selectedOpeningIndex;
  final bool showAngles;

  /// Uniform on-screen size for wall + opening dims (IV-compensated).
  double _labelFontSize() {
    final s = transform.value.getMaxScaleOnAxis().clamp(0.02, 8.0);
    return (32.0 / s).clamp(88.0, 560.0);
  }

  double _labelOffset() {
    final s = transform.value.getMaxScaleOnAxis().clamp(0.02, 8.0);
    return (36.0 / s).clamp(96.0, 640.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = CanvasPalette.bg);

    final wallPaint = Paint()
      ..color = CanvasPalette.wall
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final cursorPaint = Paint()..color = CanvasPalette.cursor;

    final m = RoomEditorMetrics.compute(walls: walls, cursor: cursor, canvasSize: size);
    Offset map(double x, double y) => m.worldToCanvas(x, y);

    // ARCHIVED: designWalls ghost overlay — `_archived/finish_project_vs_fact_ui.dart.txt`

    final dimFs = _labelFontSize();
    final dimOff = _labelOffset();
    for (final w in walls) {
      final a = map(w[0], w[1]);
      final b = map(w[2], w[3]);
      canvas.drawLine(a, b, wallPaint);
      final lenCm = math.sqrt(
        math.pow(w[2] - w[0], 2) + math.pow(w[3] - w[1], 2),
      );
      if (lenCm < 5) continue;
      DimensionLines.drawSegmentDimension(
        canvas,
        a: a,
        b: b,
        label: '${lenCm.round()}',
        color: CanvasPalette.text.withValues(alpha: 0.95),
        offsetPx: dimOff,
        placeAbove: true,
        fontSize: dimFs,
      );
    }

    if (walls.length >= 3 && !isClosed) {
      final last = walls.last;
      final first = walls.first;
      final closing = Paint()
        ..color = CanvasPalette.closingLine.withValues(alpha: 0.85)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      _drawDashedLine(
        canvas,
        map(last[2], last[3]),
        map(first[0], first[1]),
        closing,
      );
    }

    if (isClosed && walls.length >= 3) {
      final fillPath = Path();
      final start = map(walls.first[0], walls.first[1]);
      fillPath.moveTo(start.dx, start.dy);
      for (final w in walls) {
        final p = map(w[2], w[3]);
        fillPath.lineTo(p.dx, p.dy);
      }
      fillPath.close();
      canvas.drawPath(
        fillPath,
        Paint()..color = CanvasPalette.roomFill.withValues(alpha: 0.55),
      );
    }

    // Openings on walls
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
      final selected = i == placingIndex || i == selectedOpeningIndex;
      final paint = Paint()
        ..color = selected
            ? const Color(0xFFFFC857)
            : (o.kind == 'door'
                ? const Color(0xFFE07A5F)
                : const Color(0xFF81B29A))
        ..strokeWidth = selected ? 10 : 8
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;
      final n = math.max(1, o.quantity);
      for (var q = 0; q < n; q++) {
        final t0 = o.offsetAlongWallCm + q * (o.widthCm + gap);
        if (t0 >= len) break;
        final t1 = math.min(len, t0 + o.widthCm);
        canvas.drawLine(
          map(ax + ux * t0, ay + uy * t0),
          map(ax + ux * t1, ay + uy * t1),
          paint,
        );
      }
      if (selected) {
        _paintOpeningWallDims(canvas, map, o, ax, ay, ux, uy, len);
      }
    }

    // Vertex handles (edit like photo/PDF stencil)
    final worldPts = <Offset>[];
    if (walls.isNotEmpty) {
      worldPts.add(Offset(walls.first[0], walls.first[1]));
      for (final w in walls) {
        worldPts.add(Offset(w[2], w[3]));
      }
      if (isClosed && worldPts.length > 1) worldPts.removeLast();
    }
    final pts = [for (final p in worldPts) map(p.dx, p.dy)];
    for (var i = 0; i < pts.length; i++) {
      final selected = i == selectedVertex || i == dragVertex;
      canvas.drawCircle(
        pts[i],
        selected ? 9 : 6,
        Paint()
          ..color = selected
              ? const Color(0xFFFFC857)
              : CanvasPalette.cursor.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        pts[i],
        selected ? 9 : 6,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    if (showAngles && worldPts.length >= 3 && dragVertex != null) {
      final i = dragVertex!;
      final ang = vertexInteriorAngleDeg(worldPts, i);
      final near90 = (ang - 90).abs() <= 0.25;
      final label = formatVertexAngleLabel(ang);
      final at = pts[i];
      final fs = _labelFontSize();
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: near90
                ? const Color(0xFF1B5E20)
                : const Color(0xFF000000),
            fontSize: fs,
            fontWeight: FontWeight.w700,
            shadows: const [
              Shadow(blurRadius: 3, color: Colors.black54),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pad = fs * 0.28;
      final lift = fs * 1.15;
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          at.dx - tp.width / 2 - pad,
          at.dy - lift - pad,
          tp.width + pad * 2,
          tp.height + pad * 2,
        ),
        Radius.circular(pad * 0.6),
      );
      canvas.drawRRect(bg, Paint()..color = const Color(0xF2FFFFFF));
      tp.paint(canvas, at + Offset(-tp.width / 2, -lift));
    }

    final c = map(cursor[0], cursor[1]);
    canvas.drawCircle(c, 7, cursorPaint);
    canvas.drawCircle(
      c,
      7,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintOpeningWallDims(
    Canvas canvas,
    Offset Function(double x, double y) map,
    RoomOpening o,
    double ax,
    double ay,
    double ux,
    double uy,
    double len,
  ) {
    final t0 = o.offsetAlongWallCm.clamp(0.0, len).toDouble();
    final t1 = (o.offsetAlongWallCm + o.widthCm).clamp(0.0, len).toDouble();
    Offset at(double t) => map(ax + ux * t, ay + uy * t);
    // Same on-screen size as layout wall/cut dims (~22 px), IV-compensated.
    final fs = _labelFontSize();
    final off = _labelOffset();
    const dimColor = Color(0xFFFFC857);
    const gapColor = Color(0xFF8FB4D4);

    void paintChip(Offset center, String text, Color color) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fs,
            fontWeight: FontWeight.w700,
            shadows: const [
              Shadow(blurRadius: 3, color: Colors.black87),
              Shadow(blurRadius: 1, color: Colors.black54),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pad = fs * 0.22;
      final origin = Offset(center.dx - tp.width / 2, center.dy - tp.height / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            origin.dx - pad,
            origin.dy - pad * 0.5,
            tp.width + pad * 2,
            tp.height + pad,
          ),
          Radius.circular(pad * 0.7),
        ),
        Paint()..color = const Color(0xCC000000),
      );
      tp.paint(canvas, origin);
    }

    // Dimension lines (layout-like) + bold chip labels.
    if (t0 > 2) {
      DimensionLines.drawSegmentDimension(
        canvas,
        a: at(0),
        b: at(t0),
        label: '',
        color: gapColor,
        offsetPx: off,
        placeAbove: true,
        fontSize: 1,
      );
      final mid = (at(0) + at(t0)) / 2;
      final n = Offset(-(at(t0) - at(0)).dy, (at(t0) - at(0)).dx);
      final nn = n.distance < 1e-6 ? const Offset(0, -1) : n / n.distance;
      paintChip(mid + nn * (-off), '${t0.round()}', gapColor);
    }
    if (t1 - t0 > 2) {
      DimensionLines.drawSegmentDimension(
        canvas,
        a: at(t0),
        b: at(t1),
        label: '',
        color: dimColor,
        offsetPx: off,
        placeAbove: true,
        fontSize: 1,
      );
      final mid = (at(t0) + at(t1)) / 2;
      final n = Offset(-(at(t1) - at(t0)).dy, (at(t1) - at(t0)).dx);
      final nn = n.distance < 1e-6 ? const Offset(0, -1) : n / n.distance;
      paintChip(mid + nn * (-off), '${(t1 - t0).round()}', dimColor);
    }
    if (len - t1 > 2) {
      DimensionLines.drawSegmentDimension(
        canvas,
        a: at(t1),
        b: at(len),
        label: '',
        color: gapColor,
        offsetPx: off,
        placeAbove: true,
        fontSize: 1,
      );
      final mid = (at(t1) + at(len)) / 2;
      final n = Offset(-(at(len) - at(t1)).dy, (at(len) - at(t1)).dx);
      final nn = n.distance < 1e-6 ? const Offset(0, -1) : n / n.distance;
      paintChip(mid + nn * (-off), '${(len - t1).round()}', gapColor);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 8.0;
    const gap = 6.0;
    final delta = b - a;
    final len = delta.distance;
    if (len <= 0) return;
    final dir = delta / len;
    var dist = 0.0;
    while (dist < len) {
      final start = a + dir * dist;
      final end = a + dir * math.min(dist + dash, len);
      canvas.drawLine(start, end, paint);
      dist += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _WallsPainter old) =>
      old.walls != walls ||
      old.cursor != cursor ||
      old.isClosed != isClosed ||
      old.openings != openings ||
      old.selectedVertex != selectedVertex ||
      old.dragVertex != dragVertex ||
      old.placingIndex != placingIndex ||
      old.selectedOpeningIndex != selectedOpeningIndex ||
      old.showAngles != showAngles ||
      // Same controller instance — compare scale so dim labels stay readable.
      old.transform.value.getMaxScaleOnAxis() !=
          transform.value.getMaxScaleOnAxis();
}
