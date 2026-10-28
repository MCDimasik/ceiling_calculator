import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/project_repository.dart';
import '../domain/floor_covering.dart';
import '../domain/floor_layout.dart';
import '../domain/floor_layout_undo.dart';
import '../domain/models.dart';
import 'room_navigation.dart';
import 'widgets/canvas_palette.dart';
import 'widgets/controls.dart';
import 'widgets/finish_painters.dart';
import 'widgets/screen_scaffold.dart';

/// Full-screen floor layout editor (pan/zoom, offset joystick, cut dims).
class FinishFloorEditorScreen extends StatefulWidget {
  const FinishFloorEditorScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<FinishFloorEditorScreen> createState() =>
      _FinishFloorEditorScreenState();
}

class _FinishFloorEditorScreenState extends State<FinishFloorEditorScreen> {
  Room? _room;
  ProjectRepository? _projects;
  bool _loading = true;
  bool _showCutDims = true;
  final _transform = TransformationController();
  final _undo = FloorLayoutUndoStack();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
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
    if (room != null) {
      _undo.seed(
        FloorLayoutUndoSnapshot(
          offsetX: room.floorGridOffsetX,
          offsetY: room.floorGridOffsetY,
          rotationDeg: room.floorLayoutRotationDeg,
        ),
      );
    }
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

  void _pushUndo() {
    final room = _room;
    if (room == null) return;
    _undo.push(
      FloorLayoutUndoSnapshot(
        offsetX: room.floorGridOffsetX,
        offsetY: room.floorGridOffsetY,
        rotationDeg: room.floorLayoutRotationDeg,
      ),
    );
  }

  Future<void> _nudge(double dx, double dy, {bool finalize = false}) async {
    final room = _room;
    if (room == null) return;
    setState(() {
      room.floorGridOffsetX += dx.round();
      room.floorGridOffsetY += dy.round();
    });
    if (finalize) {
      _pushUndo();
      await _persist();
    }
  }

  Future<void> _resetOffset() async {
    final room = _room;
    if (room == null) return;
    setState(() {
      room.floorGridOffsetX = 0;
      room.floorGridOffsetY = 0;
    });
    _pushUndo();
    await _persist();
  }

  void _rotateBy(int deltaDeg, {bool finalize = false}) {
    final room = _room;
    if (room == null) return;
    setState(() {
      room.floorLayoutRotationDeg =
          ((room.floorLayoutRotationDeg + deltaDeg) % 360 + 360) % 360;
    });
    if (finalize) {
      _pushUndo();
      // ignore: discarded_futures
      _persist();
    }
  }

  Future<void> _resetRotation() async {
    final room = _room;
    if (room == null) return;
    setState(() => room.floorLayoutRotationDeg = 0);
    _pushUndo();
    await _persist();
  }

  Future<void> _openFloorParams() async {
    await openFinishRoom(
      context,
      projectId: widget.projectId,
      roomId: widget.roomId,
      initialTabIndex: 2,
    );
    await _load();
  }

  Future<void> _undoStep() async {
    final snap = _undo.undo();
    final room = _room;
    if (snap == null || room == null) return;
    setState(() {
      room.floorGridOffsetX = snap.offsetX;
      room.floorGridOffsetY = snap.offsetY;
      room.floorLayoutRotationDeg = snap.rotationDeg;
    });
    await _persist();
  }

  Future<void> _redoStep() async {
    final snap = _undo.redo();
    final room = _room;
    if (snap == null || room == null) return;
    setState(() {
      room.floorGridOffsetX = snap.offsetX;
      room.floorGridOffsetY = snap.offsetY;
      room.floorLayoutRotationDeg = snap.rotationDeg;
    });
    await _persist();
  }

  FloorLayoutSnapshot _layoutFor(Room room) {
    final covering = FloorCoveringKindX.parse(room.floorCoveringKind);
    final pattern = FloorLayingPatternX.parse(room.floorLayingPattern);
    if (!covering.hasBoardLayout) {
      return FloorLayoutBuilder.build(
        walls: room.walls,
        covering: FloorCoveringKind.screed,
        pattern: FloorLayingPattern.straight,
        boardW: 60,
        boardL: 60,
        offsetX: 0,
        offsetY: 0,
      );
    }
    return FloorLayoutBuilder.build(
      walls: room.walls,
      covering: covering,
      pattern: pattern,
      boardW: room.finishTileWidthCm,
      boardL: room.finishTileHeightCm,
      offsetX: room.floorGridOffsetX.toDouble(),
      offsetY: room.floorGridOffsetY.toDouble(),
      rotationDeg: room.floorLayoutRotationDeg,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = _room;
    if (room == null || !room.hasLayout) {
      return Scaffold(
        appBar: AppBar(title: const Text('Раскладка пола')),
        body: const Center(child: Text('Нет контура помещения')),
      );
    }

    final covering = FloorCoveringKindX.parse(room.floorCoveringKind);
    final layout = _layoutFor(room);
    final canEditGrid = covering.hasBoardLayout;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _persist();
        if (mounted) Navigator.pop(context);
      },
      child: ScreenScaffold(
        backgroundBlur: 0.45,
        dimOpacity: 0.55,
        appBar: AppBar(
          title: Text('${room.name} · пол'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _persist();
              if (!mounted) return;
              Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Отменить',
              onPressed: _undo.canUndo ? _undoStep : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Повторить',
              onPressed: _undo.canRedo ? _redoStep : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: 'Сброс смещения',
              onPressed: canEditGrid ? _resetOffset : null,
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                children: [
                  Text(
                    canEditGrid
                        ? '${covering.labelShortRu} · '
                            '${room.finishTileWidthCm.round()}×${room.finishTileHeightCm.round()} см · '
                            'целых ${layout.fullCount}, резаных ${layout.cutCount} · '
                            'смещение ${room.floorGridOffsetX}×${room.floorGridOffsetY} см'
                        : '${covering.labelShortRu} · без раскладки плит',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  if (canEditGrid) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Поворот ${room.floorLayoutRotationDeg}°',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: CanvasPalette.bg,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        final metrics =
                            FloorPlanMetrics.fromWalls(room.walls, size);
                        return InteractiveViewer(
                          transformationController: _transform,
                          constrained: false,
                          minScale: 0.35,
                          maxScale: 8,
                          boundaryMargin: const EdgeInsets.all(280),
                          child: SizedBox(
                            width: size.width,
                            height: size.height,
                            child: CustomPaint(
                              key: ValueKey(
                                'floor-${room.floorGridOffsetX}-'
                                '${room.floorGridOffsetY}-'
                                '${room.floorLayoutRotationDeg}-'
                                '${layout.fullCount}-${layout.cutCount}-'
                                '$_showCutDims',
                              ),
                              size: size,
                              painter: FloorPlanPainter(
                                walls: room.walls,
                                metrics: metrics,
                                layout: layout,
                                showCutDims: canEditGrid && _showCutDims,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Material(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                  child: canEditGrid
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            const joyIdeal = 96.0;
                            const sideIdeal = 72.0;
                            const gapIdeal = 12.0;
                            const minTotal = sideIdeal +
                                gapIdeal +
                                joyIdeal +
                                gapIdeal +
                                sideIdeal;
                            final scale = (constraints.maxWidth / minTotal)
                                .clamp(0.55, 1.0);
                            final joy = joyIdeal * scale;
                            final side = sideIdeal * scale;
                            final gap = gapIdeal * scale;

                            Widget chip({
                              required String label,
                              required VoidCallback onTap,
                              bool selected = false,
                              bool holdRepeat = false,
                              VoidCallback? onRelease,
                            }) {
                              return Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: _FloorModeChip(
                                    label: label,
                                    selected: selected,
                                    onTap: onTap,
                                    holdRepeat: holdRepeat,
                                    onRelease: onRelease,
                                  ),
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
                                      child: SizedBox(
                                        width: side,
                                        height: joy,
                                        child: Column(
                                          children: [
                                            chip(
                                              label: 'Сброс',
                                              onTap: _resetOffset,
                                            ),
                                            chip(
                                              label: 'Размеры',
                                              selected: _showCutDims,
                                              onTap: () => setState(
                                                () => _showCutDims =
                                                    !_showCutDims,
                                              ),
                                            ),
                                            chip(
                                              label: 'Парам.',
                                              onTap: _openFloorParams,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: gap),
                                  ArrowJoystick(
                                    size: joy,
                                    onTick: _nudge,
                                    onRelease: () =>
                                        _nudge(0, 0, finalize: true),
                                  ),
                                  SizedBox(width: gap),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: SizedBox(
                                        width: side,
                                        height: joy,
                                        child: Column(
                                          children: [
                                            chip(
                                              label: '−1°',
                                              holdRepeat: true,
                                              onTap: () => _rotateBy(-1),
                                              onRelease: () =>
                                                  _rotateBy(0, finalize: true),
                                            ),
                                            chip(
                                              label: '+1°',
                                              holdRepeat: true,
                                              onTap: () => _rotateBy(1),
                                              onRelease: () =>
                                                  _rotateBy(0, finalize: true),
                                            ),
                                            chip(
                                              label: '0°',
                                              selected:
                                                  room.floorLayoutRotationDeg ==
                                                      0,
                                              onTap: _resetRotation,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Для плитки/ламината задайте покрытие во вкладке Пол',
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              FilledButton.tonal(
                                onPressed: _openFloorParams,
                                child: const Text('Параметры пола'),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloorModeChip extends StatefulWidget {
  const _FloorModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.holdRepeat = false,
    this.onRelease,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool holdRepeat;
  final VoidCallback? onRelease;

  @override
  State<_FloorModeChip> createState() => _FloorModeChipState();
}

class _FloorModeChipState extends State<_FloorModeChip> {
  Timer? _timer;
  bool _pressed = false;
  int _holdTicks = 0;

  Duration _intervalForHoldTick(int n) {
    if (n < 6) return const Duration(milliseconds: 100);
    if (n < 18) return const Duration(milliseconds: 55);
    return const Duration(milliseconds: 32);
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(_intervalForHoldTick(_holdTicks), () {
      if (!_pressed) return;
      _holdTicks++;
      widget.onTap();
      _scheduleNext();
    });
  }

  void _startHold() {
    setState(() => _pressed = true);
    _holdTicks = 0;
    widget.onTap();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 280), () {
      if (!_pressed) return;
      _holdTicks = 1;
      widget.onTap();
      _scheduleNext();
    });
  }

  void _stopHold() {
    _timer?.cancel();
    _timer = null;
    _holdTicks = 0;
    if (_pressed) setState(() => _pressed = false);
    widget.onRelease?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = widget.selected || _pressed
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final child = Center(
      child: Text(
        widget.label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight:
              widget.selected || _pressed ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: widget.holdRepeat
          ? Listener(
              onPointerDown: (_) => _startHold(),
              onPointerUp: (_) => _stopHold(),
              onPointerCancel: (_) => _stopHold(),
              child: child,
            )
          : InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              child: child,
            ),
    );
  }
}
