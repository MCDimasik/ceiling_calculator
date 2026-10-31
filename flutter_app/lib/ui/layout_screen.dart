import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/project_repository.dart';
import '../domain/ceiling_grid.dart';
import '../domain/ceiling_guides.dart';
import '../domain/finish_model.dart';
import '../domain/finish_vedomost.dart';
import '../domain/materials_calculator.dart';
import '../domain/models.dart';
import '../domain/design_ceiling_features_baseline.dart';
import '../domain/design_walls_baseline.dart';
import '../domain/finish_design_baseline.dart';
import '../domain/layout_design_baseline.dart';
import '../domain/wall_polygon_diff.dart';
import '../domain/layout_layers.dart';
import '../domain/layout_undo.dart';
import '../domain/documentation_model.dart';
import '../domain/project_materials.dart';
import 'adaptive_layout.dart';
import 'desktop_cascade.dart';
import 'materials_flow_screens.dart';
import 'materials_result_screen.dart';
import 'room_navigation.dart';
import 'widgets/canvas_palette.dart';
import 'widgets/controls.dart';
import 'widgets/layout_canvas_painter.dart';

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

class _LayoutScreenState extends State<LayoutScreen> with WidgetsBindingObserver {
  Room? _room;
  Project? _project;
  ProjectRepository? _projects;
  final _grid = CeilingGrid();
  final _transform = TransformationController();
  LayoutMode _mode = LayoutMode.grid;
  bool _loading = true;

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

  /// Long-press on clear: expand kind pills to the right.
  bool _showGuideKindClear = false;

  LayoutMetrics? _lastMetrics;

  Timer? _rebuildThrottle;
  bool _rebuildPending = false;
  Timer? _liveGridThrottle;
  Timer? _viewCullThrottle;
  Timer? _autosaveTimer;
  bool _viewApplied = false;
  /// When true, next `_applyOrCenterView` ignores saved camera and fits room.
  bool _forceFitNext = false;
  bool _canvasReady = false;
  double _anchorOffsetX = 0;
  double _anchorOffsetY = 0;
  bool _gridPanUndoPushed = false;
  LayoutLayerVisibility _layers = const LayoutLayerVisibility();
  final _undoStack = LayoutUndoStack();

  void _pushUndoSnapshot() {
    _undoStack.push(
      LayoutEditSnapshot.capture(
        gridOffsetX: _grid.offsetXCm.round(),
        gridOffsetY: _grid.offsetYCm.round(),
        visualOffsetX: _visualOffsetX,
        visualOffsetY: _visualOffsetY,
        lightIds: _lightIds,
        guides: _guides,
      ),
    );
  }

  void _applySnapshot(LayoutEditSnapshot snap, Room room) {
    _grid.offsetXCm = snap.gridOffsetX.toDouble();
    _grid.offsetYCm = snap.gridOffsetY.toDouble();
    _visualOffsetX = snap.visualOffsetX;
    _visualOffsetY = snap.visualOffsetY;
    _lightIds
      ..clear()
      ..addAll(snap.lightIds);
    _guides
      ..clear()
      ..addAll(
        {
          for (final e in snap.guidesJson.entries)
            if (CeilingGuideMark.fromJson(
                  Map<String, dynamic>.from(e.value as Map),
                  offsetX: snap.visualOffsetX,
                  offsetY: snap.visualOffsetY,
                  cellSize: _grid.cellSizeCm,
                )
                case final g?)
              e.key: g,
        },
      );
    _rebuildGrid(room);
  }

  void _undoLayout(Room room) {
    final snap = _undoStack.undo();
    if (snap == null) return;
    setState(() => _applySnapshot(snap, room));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Отменено'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _redoLayout(Room room) {
    final snap = _undoStack.redo();
    if (snap == null) return;
    setState(() => _applySnapshot(snap, room));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Повторено'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _setLayerValue(LayoutLayerVisibility Function(LayoutLayerVisibility) update) {
    setState(() {
      final next = update(_layers);
      final visible =
          next.walls || next.grid || next.guides || next.lights || next.floor || next.notes;
      if (!visible) return;
      _layers = next;
    });
    _captureViewToRoom();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _transform.addListener(_onTransformChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant LayoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.projectId != widget.projectId) {
      setState(() {
        _loading = true;
        _viewApplied = false;
        _lightIds.clear();
        _guides.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // ignore: discarded_futures
      _flushAutosave();
    }
  }

  @override
  void dispose() {
    // Best-effort sync write before tearing down (cannot await dispose).
    _flushAutosaveSync();
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    _rebuildThrottle?.cancel();
    _liveGridThrottle?.cancel();
    _viewCullThrottle?.cancel();
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    super.dispose();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _persist(markLayoutConfirmed: false);
    });
  }

  Future<void> _flushAutosave() async {
    if (_autosaveTimer == null) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    await _persist(markLayoutConfirmed: false);
  }

  /// Sync snapshot + fire-and-forget DB write (dispose path).
  void _flushAutosaveSync() {
    if (_autosaveTimer == null) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
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
    final projects = _projects;
    if (projects != null) {
      // ignore: discarded_futures
      projects.updateRoom(room);
    }
  }

  void _onTransformChanged() {
    // Throttle cull/repaint while panning — full setState every frame is costly.
    if (_viewCullThrottle?.isActive ?? false) return;
    _viewCullThrottle = Timer(const Duration(milliseconds: 50), () {
      if (mounted) setState(() {});
    });
  }

  bool _viewShowsRoom(Size viewport, LayoutMetrics metrics) {
    final roomRect = Rect.fromLTWH(
      metrics.ox,
      metrics.oy,
      metrics.roomWidthPx,
      metrics.roomHeightPx,
    );
    for (final corner in [
      roomRect.topLeft,
      roomRect.topRight,
      roomRect.bottomLeft,
      roomRect.bottomRight,
    ]) {
      final p = MatrixUtils.transformPoint(_transform.value, corner);
      if (p.dx < -viewport.width * 0.08 ||
          p.dx > viewport.width * 1.08 ||
          p.dy < -viewport.height * 0.08 ||
          p.dy > viewport.height * 1.08) {
        return false;
      }
    }
    return true;
  }

  void _applyOrCenterView(Size viewport, Size canvasSize, LayoutMetrics metrics) {
    if (_viewApplied || _room == null) return;
    _viewApplied = true;

    if (!_forceFitNext) {
      final saved = ViewTransform.tryParse(_room!.layoutViewJson);
      if (saved != null &&
          saved.scale.isFinite &&
          saved.scale > 0.05 &&
          saved.tx.isFinite &&
          saved.ty.isFinite) {
        _transform.value = saved.toMatrix();
        if (_viewShowsRoom(viewport, metrics)) {
          return;
        }
      }
    }
    _forceFitNext = false;

    final focal = metrics.roomCentroidScreen;
    final fitScale = metrics.fitScaleForViewport(viewport);
    _transform.value = Matrix4.identity()
      ..translateByDouble(viewport.width / 2, viewport.height / 2, 0, 1)
      ..scaleByDouble(fitScale, fitScale, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    _captureViewToRoom();
  }

  void _captureViewToRoom() {
    final room = _room;
    if (room == null) return;
    final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
    view.addAll(ViewTransform.fromMatrix(_transform.value).toJson());
    view['layers'] = _layers.toJson();
    room.layoutViewJson = view;
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
      _viewApplied = false;
      _canvasReady = false;
      _project = project;
      _room = room;
      _loading = false;
      if (room != null) {
        final layersRaw = room.layoutViewJson?['layers'];
        final layersMap =
            layersRaw is Map ? Map<String, dynamic>.from(layersRaw) : null;
        if (layersMap != null) {
          _layers = LayoutLayerVisibility.fromJson(layersMap);
        } else {
          _layers = const LayoutLayerVisibility();
        }
        // Floor overlay is for finish module — never show on ceiling layout canvas.
        _layers = _layers.copyWith(floor: false);
        final noteText =
            RoomDocumentationChecklist.fromJson(room.documentationChecklistJson).notes.trim();
        if (noteText.isNotEmpty && (layersMap == null || !layersMap.containsKey('notes'))) {
          _layers = _layers.copyWith(notes: true);
        }
        _visualOffsetX = room.gridOffsetX.toDouble();
        _visualOffsetY = room.gridOffsetY.toDouble();
        _snapVisualOffsetToCm();
        _anchorOffsetX = _visualOffsetX;
        _anchorOffsetY = _visualOffsetY;
        _grid.cellSizeCm = layoutTileCm;
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
        _syncMainGuideKindFromCeiling();
        _canvasReady = true;
        _undoStack.seed(
          LayoutEditSnapshot.capture(
            gridOffsetX: _grid.offsetXCm.round(),
            gridOffsetY: _grid.offsetYCm.round(),
            visualOffsetX: _visualOffsetX,
            visualOffsetY: _visualOffsetY,
            lightIds: _lightIds,
            guides: _guides,
          ),
        );
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

  /// Main runner chip: 3600 for Armstrong/GL, 2400 for classic Grilyato.
  /// Prefers kinds already on the drawing when present.
  void _syncMainGuideKindFromCeiling() {
    final room = _room;
    GuideKind main = GuideKind.g3600;
    if (room != null) {
      final (ceiling, _, _) =
          roomEffectiveConfig(room, _project ?? Project(name: ''));
      main = ceilingFrameTemplateForLabel(ceiling).mainGuideKind;
    }
    if (_guides.values.any((g) => g.kind == GuideKind.g2400)) {
      main = GuideKind.g2400;
    } else if (_guides.values.any((g) => g.kind == GuideKind.g3600)) {
      main = GuideKind.g3600;
    }
    _mainGuideKind = main;
    if (_guideKind == GuideKind.g3600 || _guideKind == GuideKind.g2400) {
      _guideKind = main;
    }
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

  void _clampVisualOffset() {
    final cw = _grid.cellWidthCm <= 0 ? layoutTileCm : _grid.cellWidthCm;
    final ch = _grid.cellHeightCm <= 0 ? layoutTileCm : _grid.cellHeightCm;
    _visualOffsetX = _visualOffsetX.clamp(_anchorOffsetX - cw, _anchorOffsetX + cw);
    _visualOffsetY = _visualOffsetY.clamp(_anchorOffsetY - ch, _anchorOffsetY + ch);
  }

  /// Grid offset moves in whole centimeters (joystick and finger drag).
  void _snapVisualOffsetToCm() {
    _visualOffsetX = _visualOffsetX.roundToDouble();
    _visualOffsetY = _visualOffsetY.roundToDouble();
    _clampVisualOffset();
  }

  /// Sync grid to visual offset; clamp to ±1 cell from anchor. Preserves light/guide world positions.
  void _syncGridToVisual(Room room, {required bool wrap}) {
    final cw = _grid.cellWidthCm <= 0 ? 60.0 : _grid.cellWidthCm;
    final ch = _grid.cellHeightCm <= 0 ? 60.0 : _grid.cellHeightCm;
    final prevGridX = _grid.offsetXCm;
    final prevGridY = _grid.offsetYCm;

    _clampVisualOffset();
    final nextX = _visualOffsetX.roundToDouble();
    final nextY = _visualOffsetY.roundToDouble();
    final dragDx = nextX - prevGridX;
    final dragDy = nextY - prevGridY;
    final lightWorlds = <(double, double)>[];
    for (final c in _grid.cells) {
      if (_lightIds.contains(c.id)) {
        lightWorlds.add((
          c.xCm + dragDx + cw / 2,
          c.yCm + dragDy + ch / 2,
        ));
      }
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

  void _commitGridOffset(Room room) => _syncGridToVisual(room, wrap: false);

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
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
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
      // Never silent-rebaseline: that wipes project-vs-fact deltas.
      // Explicit rebaseline lives in Finish («Обновить проектную базу»).
      ensureFinishDesignBaseline(room);
    }
    await AppScope.of(context).projects.updateRoom(room);
  }

  /// If the operator left without placing guides, build the standard carrier frame
  /// so materials never fall back to area formulas.
  void _ensureAutoGuidesIfEmpty(Room room) {
    if (_guides.isNotEmpty || room.walls.length < 3) return;
    final project = _project ?? Project(name: '');
    final (ceilingLabel, _, cellLabel) = roomEffectiveConfig(room, project);
    final marks = autoGuideMarksForRoom(
      walls: room.walls,
      offsetX: _visualOffsetX,
      offsetY: _visualOffsetY,
      cellSize: layoutTileCm,
      ceilingLabel: ceilingLabel,
      cellSizeLabel: cellLabel,
    );
    if (marks.isEmpty) return;
    _guides
      ..clear()
      ..addEntries(marks.map((g) => MapEntry(g.storageKey, g)));
  }

  Future<void> _leaveLayout() async {
    // Do not silently confirm layout or invent carrier guides on back.
    await _persist(markLayoutConfirmed: false);
    if (!mounted) return;
    final cascade = DesktopCascadeHost.maybeOf(context);
    if (cascade != null) {
      cascade.closeDetail();
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _persistWithAutoGuides({bool markLayoutConfirmed = true}) async {
    final room = _room;
    if (room != null) {
      _ensureAutoGuidesIfEmpty(room);
    }
    await _persist(markLayoutConfirmed: markLayoutConfirmed);
  }

  Future<void> _editNotes() async {
    final room = _room;
    if (room == null) return;
    final cl = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
    final ctrl = TextEditingController(text: cl.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Заметка на чертеже'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Подписи, замечания прораба…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    cl.notes = text;
    room.documentationChecklistJson = cl.toJson();
    await AppScope.of(context).projects.updateRoom(room);
    setState(() {
      if (text.isNotEmpty) _layers = _layers.copyWith(notes: true);
      _captureViewToRoom();
    });
  }

  void _onTapUp(TapUpDetails d, LayoutMetrics m) {
    if (_room == null) return;
    if (_mode == LayoutMode.lights) {
      _onLightTap(d, m);
    } else if (_mode == LayoutMode.guides) {
      _onGuideTap(d, m);
    }
  }

  void _onLightTap(TapUpDetails d, LayoutMetrics m) {
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
    _pushUndoSnapshot();
    setState(() {
      final id = hit!.id;
      if (_lightIds.contains(id)) {
        _lightIds.remove(id);
      } else {
        _lightIds.add(id);
      }
      _grid.toggleLight(hit.col, hit.row);
    });
    _scheduleAutosave();
  }

  void _onGuideTap(TapUpDetails d, LayoutMetrics m) {
    if (_floatingGuide != null || _room == null) return;
    final world = m.screenToWorld(d.localPosition);
    final cell = _grid.cellSizeCm;
    final tol = cell * 0.35;

    final existing = _hitExistingGuide(world, tol);
    if (existing != null) {
      _pushUndoSnapshot();
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
      _scheduleAutosave();
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
    _pushUndoSnapshot();
    setState(() => _guides[key] = placed);
    _scheduleAutosave();
  }

  Future<void> _openFrameTemplateDialog() async {
    final room = _room;
    if (room == null) return;

    if (_guides.length > 1) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Перезаписать направляющие?'),
          content: Text(
            'На чертеже уже ${_guides.length} линий каркаса. '
            'Шаблон заменит всю разметку направляющих.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Построить')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    // 3600 → Armstrong, 2400 → Grilyato (by active guide kind or placed guides).
    final uses2400 = _guideKind == GuideKind.g2400 ||
        _mainGuideKind == GuideKind.g2400 ||
        _guides.values.any((g) => g.kind == GuideKind.g2400);
    var template = uses2400
        ? CeilingFrameTemplate.grilyatoClassic
        : CeilingFrameTemplate.armstrong;
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
                          : _guides.length == 1
                              ? 'Каркас будет построен от вашей первой направляющей.'
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

    const cellSize = layoutTileCm;

    final seed = findFrameSeed(_guides.values, template: template) ??
        seedFrameAtRoomCenter(
          template: template,
          offsetX: _visualOffsetX,
          offsetY: _visualOffsetY,
          cellSize: cellSize,
          walls: room.walls,
        );

    final proposed = proposeCeilingFrame(
      template: template,
      seed: seed,
      offsetX: _visualOffsetX,
      offsetY: _visualOffsetY,
      cellSize: cellSize,
      walls: room.walls,
      cellSizeLabel: cellSizeLabel,
    );

    _pushUndoSnapshot();
    setState(() {
      _guides
        ..clear()
        ..addEntries(proposed.map((g) => MapEntry(g.storageKey, g)));
      _grid.cellSizeCm = layoutTileCm;
      room.materialsCeiling = template.materialsLabel;
      if (template.needsCellSize) {
        room.materialsCell = cellSizeLabel;
      }
      room.materialsOverride = true;
      _mainGuideKind = template.mainGuideKind;
      if (_guideKind == GuideKind.g3600 || _guideKind == GuideKind.g2400) {
        _guideKind = template.mainGuideKind;
      }
      _rebuildGrid(room);
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
    final cell = _grid.cellSizeCm;
    String? bestKey;
    var bestDist = double.infinity;
    for (final e in _guides.entries) {
      final mark = e.value;
      final coord = guideLineWorldCoord(
        axis: mark.axis,
        lineIndex: mark.lineIndex,
        gridOffset: mark.axis == GuideAxis.horizontal ? _grid.offsetYCm : _grid.offsetXCm,
        visualOffset: mark.axis == GuideAxis.horizontal ? _visualOffsetY : _visualOffsetX,
        cellSize: cell,
      );
      final dist = mark.axis == GuideAxis.horizontal
          ? (world.dy - coord).abs()
          : (world.dx - coord).abs();
      if (dist > tol || dist >= bestDist) continue;

      final perpAxis =
          mark.axis == GuideAxis.horizontal ? GuideAxis.vertical : GuideAxis.horizontal;
      final anchorCm = guideLineWorldCoord(
        axis: perpAxis,
        lineIndex: mark.anchorAlongIndex,
        gridOffset: perpAxis == GuideAxis.vertical ? _grid.offsetXCm : _grid.offsetYCm,
        visualOffset:
            perpAxis == GuideAxis.vertical ? _visualOffsetX : _visualOffsetY,
        cellSize: cell,
      );
      final segs = guideProfilePieceSegments(
        mark,
        room.walls,
        offsetX: _visualOffsetX,
        offsetY: _visualOffsetY,
        cellSize: cell,
        coordCm: coord,
        anchorAlongCm: anchorCm,
      );
      var onRun = segs.isEmpty;
      for (final s in segs) {
        if (mark.axis == GuideAxis.horizontal) {
          final along = world.dx;
          final lo = math.min(s.x1, s.x2) - tol;
          final hi = math.max(s.x1, s.x2) + tol;
          if (along >= lo && along <= hi) {
            onRun = true;
            break;
          }
        } else {
          final along = world.dy;
          final lo = math.min(s.y1, s.y2) - tol;
          final hi = math.max(s.y1, s.y2) + tol;
          if (along >= lo && along <= hi) {
            onRun = true;
            break;
          }
        }
      }
      if (!onRun) continue;
      bestDist = dist;
      bestKey = e.key;
    }
    return bestKey;
  }

  void _onGuideLongPressStart(LongPressStartDetails d, LayoutMetrics m) {
    if (_mode != LayoutMode.guides || _room == null) return;
    final world = m.screenToWorld(d.localPosition);
    final key = _hitExistingGuide(world, _grid.cellSizeCm * 0.55);
    if (key == null) return;
    final mark = _guides.remove(key);
    if (mark == null) return;
    _pushUndoSnapshot();
    setState(() {
      _floatingGuide = mark;
      _dragSmoothX = world.dx;
      _dragSmoothY = world.dy;
      _showGuideKindClear = false;
    });
  }

  void _onGuideLongPressMove(LongPressMoveUpdateDetails d, LayoutMetrics m) {
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
    // Free drop: nearest H or V grid line (↑↓←→), not locked to old axis.
    final placement = snapGuidePlacement(
      worldX: _dragSmoothX ?? 0,
      worldY: _dragSmoothY ?? 0,
      offsetX: _visualOffsetX,
      offsetY: _visualOffsetY,
      cellSize: cell,
      walls: room.walls,
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
    _scheduleAutosave();
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
      _mode == LayoutMode.pan ||
      _mode == LayoutMode.grid ||
      _mode == LayoutMode.lights ||
      _mode == LayoutMode.guides;

  void _clearGuides() {
    if (_guides.isEmpty) return;
    _pushUndoSnapshot();
    setState(() {
      _guides.clear();
      _showGuideKindClear = false;
    });
    _scheduleAutosave();
  }

  void _clearGuidesOfKind(GuideKind kind) {
    final keys = _guides.entries
        .where((e) => e.value.kind == kind)
        .map((e) => e.key)
        .toList();
    if (keys.isEmpty) {
      setState(() => _showGuideKindClear = false);
      return;
    }
    _pushUndoSnapshot();
    setState(() {
      for (final k in keys) {
        _guides.remove(k);
      }
      _showGuideKindClear = false;
    });
    _scheduleAutosave();
  }

  GuideKind get _mainClearKind =>
      _mainGuideKind == GuideKind.g2400 ? GuideKind.g2400 : GuideKind.g3600;

  void _nudge(double dx, double dy, {bool finalize = false}) {
    final room = _room;
    if (room == null || !_joystickEnabled) return;
    setState(() {
      _visualOffsetX += dx;
      _visualOffsetY += dy;
      _snapVisualOffsetToCm();
      if (finalize) {
        _liveGridThrottle?.cancel();
        _commitGridOffset(room);
        _scheduleAutosave();
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

  Rect _visibleWorld(Size paintSize, LayoutMetrics metrics) {
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

  Set<String> _designLightIds(Room room) {
    final fixtures = readDesignLightFixtures(room);
    if (fixtures == null) return const {};
    return fixtures
        .where((f) => f.length >= 2)
        .map((f) => '${f[0]}:${f[1]}')
        .toSet();
  }

  List<CeilingGuideMark> _designGuideGhosts(Room room) {
    if (!room.layoutConfirmed || !hasDesignCeilingFeaturesBaseline(room)) {
      return const [];
    }
    final base = readDesignBaseline(room);
    return designGuideMarksNotInFact(
      room,
      offsetX: base.offsetX.toDouble(),
      offsetY: base.offsetY.toDouble(),
      cellSize: _grid.cellSizeCm,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final room = _room;
    if (room == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Раскладка')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }

    final (ef, ec) = _grid.effectiveTileCounts;
    final purchase = ceilingPurchaseCount(room);
    final area = MaterialsCalculator.roomAreaM2(room.walls);
    final perimeter = MaterialsCalculator.roomPerimeterCm(room.walls) / 100;
    final guideHint = _guideStatsHint();
    final stats =
        'На плане: $ef целых + $ec резаных  ·  Закупка: $purchase  ·  Свет: ${_grid.lightCount}  ·  '
        'P: ${perimeter.toStringAsFixed(2)} м  ·  '
        'Площадь: ${area.toStringAsFixed(2)} м²  ·  '
        'Смещение: ${_visualOffsetX.round()}×${_visualOffsetY.round()} см'
        '$guideHint';
    final inCascade = DesktopCascadeHost.maybeOf(context) != null;
    final desktopChrome =
        inCascade || AdaptiveBreakpoints.useDesktopChrome(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leaveLayout();
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(room.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _leaveLayout,
        ),
        actions: [
          IconButton(
            tooltip: _mode == LayoutMode.pan ? 'Центрировать' : 'Сброс смещения',
            onPressed: () {
              setState(() {
                if (_mode == LayoutMode.pan) {
                  _forceFitNext = true;
                  _viewApplied = false;
                } else {
                  // Absolute world origin — reset anchor first so ±1-cell clamp
                  // cannot pull 0,0 back toward the last saved offset.
                  _anchorOffsetX = 0;
                  _anchorOffsetY = 0;
                  _visualOffsetX = 0;
                  _visualOffsetY = 0;
                  _grid.offsetXCm = 0;
                  _grid.offsetYCm = 0;
                  _rebuildGrid(room);
                  _scheduleAutosave();
                }
              });
            },
            icon: const Icon(Icons.restart_alt),
          ),
          TextButton(
            onPressed: () async {
              await _persistWithAutoGuides();
              if (!mounted) return;
              await openRoomModule(
                context,
                projectId: widget.projectId,
                roomId: widget.roomId,
                module: AppModule.finish,
              );
            },
            child: const Text('Отделка'),
          ),
          TextButton(
            onPressed: () async {
              await _persistWithAutoGuides();
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MaterialsResultScreen(
                    projectId: widget.projectId,
                    roomId: widget.roomId,
                    calcMode: MaterialsCalcMode.ceiling,
                  ),
                ),
              );
            },
            child: const Text('Материал'),
          ),
        ],
      ),
      body: Focus(
        autofocus: desktopChrome,
        onKeyEvent: desktopChrome ? _onLayoutKey : null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
              child: Text(
                desktopChrome
                    ? '$stats\n←↑↓→ / WASD — сдвиг · 1–4 режимы · Space — панорама'
                    : stats,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: desktopChrome
                  ? Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.none,
                      children: [
                        _layoutCanvasStack(room),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: _LayoutDesktopFilterRail(
                            mode: _mode,
                            onMode: (m) => setState(() => _mode = m),
                            showTileDims: _layers.tileDims,
                            showWallDims: _layers.wallDims,
                            onToggleTileDims: () => _setLayerValue(
                              (l) => l.copyWith(tileDims: !l.tileDims),
                            ),
                            onToggleWallDims: () => _setLayerValue(
                              (l) => l.copyWith(wallDims: !l.wallDims),
                            ),
                            guideKind: _guideKind,
                            onGuideKind: (kind) => setState(() {
                              _guideKind = kind;
                              if (kind == GuideKind.g3600 ||
                                  kind == GuideKind.g2400) {
                                _mainGuideKind = kind;
                              }
                            }),
                          ),
                        ),
                      ],
                    )
                  : _layoutCanvasStack(room),
            ),
            if (!desktopChrome) _layoutPhoneBottomBar(),
          ],
        ),
      ),
    ),
    );
  }

  KeyEventResult _onLayoutKey(FocusNode node, KeyEvent event) {
    // Physical keys so WASD works on any keyboard layout (RU/EN/…).
    final physical = event.physicalKey;

    if (event is KeyUpEvent) {
      if (_isNudgePhysical(physical) && _joystickEnabled) {
        _nudge(0, 0, finalize: true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (physical == PhysicalKeyboardKey.digit1 ||
        physical == PhysicalKeyboardKey.numpad1) {
      setState(() => _mode = LayoutMode.grid);
      return KeyEventResult.handled;
    }
    if (physical == PhysicalKeyboardKey.digit2 ||
        physical == PhysicalKeyboardKey.numpad2) {
      setState(() => _mode = LayoutMode.pan);
      return KeyEventResult.handled;
    }
    if (physical == PhysicalKeyboardKey.digit3 ||
        physical == PhysicalKeyboardKey.numpad3) {
      setState(() => _mode = LayoutMode.guides);
      return KeyEventResult.handled;
    }
    if (physical == PhysicalKeyboardKey.digit4 ||
        physical == PhysicalKeyboardKey.numpad4) {
      setState(() => _mode = LayoutMode.lights);
      return KeyEventResult.handled;
    }
    if (physical == PhysicalKeyboardKey.space) {
      setState(() => _mode = LayoutMode.pan);
      return KeyEventResult.handled;
    }
    if (!_joystickEnabled) return KeyEventResult.ignored;
    double dx = 0, dy = 0;
    if (physical == PhysicalKeyboardKey.arrowUp ||
        physical == PhysicalKeyboardKey.keyW) {
      dy = 1;
    } else if (physical == PhysicalKeyboardKey.arrowDown ||
        physical == PhysicalKeyboardKey.keyS) {
      dy = -1;
    } else if (physical == PhysicalKeyboardKey.arrowLeft ||
        physical == PhysicalKeyboardKey.keyA) {
      dx = -1;
    } else if (physical == PhysicalKeyboardKey.arrowRight ||
        physical == PhysicalKeyboardKey.keyD) {
      dx = 1;
    } else {
      return KeyEventResult.ignored;
    }
    _nudge(dx, dy);
    return KeyEventResult.handled;
  }

  bool _isNudgePhysical(PhysicalKeyboardKey key) {
    return key == PhysicalKeyboardKey.arrowUp ||
        key == PhysicalKeyboardKey.arrowDown ||
        key == PhysicalKeyboardKey.arrowLeft ||
        key == PhysicalKeyboardKey.arrowRight ||
        key == PhysicalKeyboardKey.keyW ||
        key == PhysicalKeyboardKey.keyA ||
        key == PhysicalKeyboardKey.keyS ||
        key == PhysicalKeyboardKey.keyD;
  }

  Widget _layoutCanvasStack(Room room) {
    return Stack(
              children: [
                ColoredBox(
              color: CanvasPalette.bg,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                  final canvasSize = Size(viewport.width * 2.2, viewport.height * 2.2);
                  final metrics = LayoutMetrics.compute(canvasSize, room.walls);
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
                        onPanStart: _mode == LayoutMode.grid
                            ? (_) {
                                if (!_gridPanUndoPushed) {
                                  _pushUndoSnapshot();
                                  _gridPanUndoPushed = true;
                                }
                              }
                            : null,
                        onPanUpdate: _mode == LayoutMode.grid
                            ? (d) {
                                final dx = d.delta.dx / metrics.scale;
                                final dy = -d.delta.dy / metrics.scale;
                                setState(() {
                                  _visualOffsetX += dx;
                                  _visualOffsetY += dy;
                                  _snapVisualOffsetToCm();
                                  _scheduleLiveGridSync(room);
                                });
                              }
                            : null,
                        onPanEnd: _mode == LayoutMode.grid
                            ? (_) {
                                _liveGridThrottle?.cancel();
                                _gridPanUndoPushed = false;
                                setState(() => _commitGridOffset(room));
                              }
                            : null,
                        onPanCancel: _mode == LayoutMode.grid
                            ? () {
                                _liveGridThrottle?.cancel();
                                _gridPanUndoPushed = false;
                                setState(() => _commitGridOffset(room));
                              }
                            : null,
                        child: CustomPaint(
                          size: canvasSize,
                          painter: LayoutPainter(
                            walls: room.walls,
                            grid: _grid,
                            metrics: metrics,
                            showTileDims: _layers.tileDims,
                            showWallDims: _layers.wallDims,
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
                            showDesignOverlay: false,
                            designGridOffsetX: readDesignBaseline(room).offsetX,
                            designGridOffsetY: readDesignBaseline(room).offsetY,
                            designLightIds: _designLightIds(room),
                            designGuideGhosts: _designGuideGhosts(room),
                            layers: _layers,
                            notesOverlay: RoomDocumentationChecklist.fromJson(room.documentationChecklistJson).notes,
                            floorOffsetX: room.floorGridOffsetX.toDouble(),
                            floorOffsetY: room.floorGridOffsetY.toDouble(),
                            floorTileWCm: room.finishTileWidthCm,
                            floorTileHCm: room.finishTileHeightCm,
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Material(
                                color: Colors.black.withValues(alpha: 0.42),
                                borderRadius: BorderRadius.circular(10),
                                child: IconButton(
                                  tooltip:
                                      'Очистить все · удерживайте — по типу',
                                  onPressed: () {
                                    if (_showGuideKindClear) {
                                      setState(
                                        () => _showGuideKindClear = false,
                                      );
                                    } else {
                                      _clearGuides();
                                    }
                                  },
                                  onLongPress: () => setState(
                                    () => _showGuideKindClear =
                                        !_showGuideKindClear,
                                  ),
                                  icon: const Icon(
                                    Icons.cleaning_services,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.centerLeft,
                                child: _showGuideKindClear
                                    ? Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (final k in <GuideKind>[
                                              _mainClearKind,
                                              GuideKind.g1200,
                                              GuideKind.g600,
                                            ]) ...[
                                              _GuideKindClearPill(
                                                kind: k,
                                                onTap: () =>
                                                    _clearGuidesOfKind(k),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
  }

  Widget _layoutPhoneBottomBar() {
    return SafeArea(
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
                                  accent3600: guideKindColor(GuideKind.g3600),
                                  accent2400: guideKindColor(GuideKind.g2400),
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
                                    accent: guideKindColor(kind),
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
                                  selected: _layers.tileDims,
                                  onTap: () => _setLayerValue((l) => l.copyWith(tileDims: !l.tileDims)),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1),
                                child: _ModeChip(
                                  label: 'Стены',
                                  selected: _layers.wallDims,
                                  onTap: () => _setLayerValue((l) => l.copyWith(wallDims: !l.wallDims)),
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
          );
  }
}

/// Vertical filter/mode rail overlaid on the layout canvas (desktop).
/// Hover grows the chip and gently nudges neighbors.
class _LayoutDesktopFilterRail extends StatefulWidget {
  const _LayoutDesktopFilterRail({
    required this.mode,
    required this.onMode,
    required this.showTileDims,
    required this.showWallDims,
    required this.onToggleTileDims,
    required this.onToggleWallDims,
    required this.guideKind,
    required this.onGuideKind,
  });

  final LayoutMode mode;
  final ValueChanged<LayoutMode> onMode;
  final bool showTileDims;
  final bool showWallDims;
  final VoidCallback onToggleTileDims;
  final VoidCallback onToggleWallDims;
  final GuideKind guideKind;
  final ValueChanged<GuideKind> onGuideKind;

  @override
  State<_LayoutDesktopFilterRail> createState() =>
      _LayoutDesktopFilterRailState();
}

class _LayoutDesktopFilterRailState extends State<_LayoutDesktopFilterRail> {
  int? _hoverIndex;

  List<({String label, IconData icon, bool selected, VoidCallback onTap, Color? accent})>
      _items() {
    final modes = <({String label, IconData icon, bool selected, VoidCallback onTap, Color? accent})>[
      (
        label: 'Сетка',
        icon: Icons.grid_on,
        selected: widget.mode == LayoutMode.grid,
        onTap: () => widget.onMode(LayoutMode.grid),
        accent: null,
      ),
      (
        label: 'Панорама',
        icon: Icons.pan_tool_alt,
        selected: widget.mode == LayoutMode.pan,
        onTap: () => widget.onMode(LayoutMode.pan),
        accent: null,
      ),
      (
        label: 'Направл.',
        icon: Icons.straighten,
        selected: widget.mode == LayoutMode.guides,
        onTap: () => widget.onMode(LayoutMode.guides),
        accent: null,
      ),
      (
        label: 'Свет',
        icon: Icons.lightbulb_outline,
        selected: widget.mode == LayoutMode.lights,
        onTap: () => widget.onMode(LayoutMode.lights),
        accent: null,
      ),
    ];
    if (widget.mode == LayoutMode.guides) {
      for (final kind in [
        GuideKind.g3600,
        GuideKind.g2400,
        GuideKind.g1200,
        GuideKind.g600,
      ]) {
        modes.add((
          label: kind.id,
          icon: Icons.horizontal_rule,
          selected: widget.guideKind == kind,
          onTap: () => widget.onGuideKind(kind),
          accent: guideKindColor(kind),
        ));
      }
    } else {
      modes.add((
        label: 'Плиты',
        icon: Icons.crop_square,
        selected: widget.showTileDims,
        onTap: widget.onToggleTileDims,
        accent: null,
      ));
      modes.add((
        label: 'Стены',
        icon: Icons.border_outer,
        selected: widget.showWallDims,
        onTap: widget.onToggleWallDims,
        accent: null,
      ));
    }
    return modes;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    final hover = _hoverIndex;

    // Equal-width column, no solid panel behind the chips.
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _HoverFilterChip(
              label: items[i].label,
              icon: items[i].icon,
              selected: items[i].selected,
              accent: items[i].accent,
              hovered: hover == i,
              neighborPush: hover == null
                  ? 0
                  : (i - hover).clamp(-2, 2).toDouble() * 3.5,
              onHover: (v) => setState(() => _hoverIndex = v ? i : null),
              onTap: items[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _HoverFilterChip extends StatelessWidget {
  const _HoverFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.hovered,
    required this.neighborPush,
    required this.onHover,
    required this.onTap,
    this.accent,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool hovered;
  final double neighborPush;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = hovered ? 1.06 : 1.0;
    final bg = selected
        ? (accent?.withValues(alpha: 0.28) ?? scheme.primaryContainer)
        : scheme.surface.withValues(alpha: 0.82);
    final side = BorderSide(
      color: selected
          ? (accent ?? scheme.primary).withValues(alpha: 0.45)
          : scheme.outlineVariant.withValues(alpha: 0.55),
    );

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        offset: Offset(0, neighborPush / 48),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          scale: scale,
          child: Material(
            color: bg,
            elevation: hovered ? 2 : 0,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: side,
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: accent ??
                          (selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected
                              ? (accent ?? scheme.onPrimaryContainer)
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

/// Compact pill to clear one guide kind (long-press on clear → expand right).
class _GuideKindClearPill extends StatelessWidget {
  const _GuideKindClearPill({required this.kind, required this.onTap});

  final GuideKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = guideKindColor(kind);
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                kind.id,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

