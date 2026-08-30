import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/materials_calculator.dart';
import '../domain/models.dart';
import '../domain/room_draft.dart';
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
}

class RoomEditorScreen extends StatefulWidget {
  const RoomEditorScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<RoomEditorScreen> createState() => _RoomEditorScreenState();
}

class _RoomEditorScreenState extends State<RoomEditorScreen> {
  Room? _room;
  late RoomDraft _draft;
  bool _loading = true;
  final _transform = TransformationController();
  Size? _lastViewport;
  bool _viewCentered = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      _loading = false;
      _viewCentered = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCursor());
  }

  void _centerOnCursor() {
    final viewport = _lastViewport;
    if (viewport == null || !mounted) return;
    final canvasSize = Size(viewport.width * 2.2, viewport.height * 2.2);
    final m = RoomEditorMetrics.compute(
      walls: _draft.walls,
      cursor: _draft.cursor,
      canvasSize: canvasSize,
    );
    final pos = m.worldToCanvas(_draft.cursor[0], _draft.cursor[1]);
    final tx = viewport.width / 2 - pos.dx;
    final ty = viewport.height / 2 - pos.dy;
    _transform.value = Matrix4.identity()..translateByDouble(tx, ty, 0, 1);
    _viewCentered = true;
  }

  Future<void> _persist() async {
    final room = _room;
    if (room == null) return;
    room.walls = _draft.walls.map((w) => List<double>.from(w)).toList();
    room.lastPosition = List<double>.from(_draft.cursor);
    await AppScope.of(context).projects.updateRoom(room);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCursor());
  }

  Future<void> _goLayout() async {
    await _persist();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LayoutScreen(
          projectId: widget.projectId,
          roomId: widget.roomId,
        ),
      ),
    );
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
    final info =
        'Точка (${_draft.cursor[0].toStringAsFixed(1)}, ${_draft.cursor[1].toStringAsFixed(1)})  ·  '
        'Стен: ${_draft.walls.length}  ·  '
        'P: ${perimeter.toStringAsFixed(2)} м  ·  '
        'Площадь: ${area.toStringAsFixed(2)} м²'
        '${_draft.isClosed ? '  ·  замкнута' : ''}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_room!.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _persist();
            if (mounted) Navigator.pop(context);
          },
        ),
        actions: [
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
          IconButton(
            tooltip: 'Отдалить',
            onPressed: () {
              final s = _transform.value.getMaxScaleOnAxis();
              _transform.value = Matrix4.identity()..scaleByDouble(s / 1.25, s / 1.25, 1, 1);
            },
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            tooltip: 'Приблизить',
            onPressed: () {
              final s = _transform.value.getMaxScaleOnAxis();
              _transform.value = Matrix4.identity()..scaleByDouble(s * 1.25, s * 1.25, 1, 1);
            },
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Сброс',
            onPressed: () {
              setState(() => _draft.reset());
              WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCursor());
            },
            icon: const Icon(Icons.delete_outline),
          ),
          TextButton(
            onPressed: _draft.walls.length >= 3 ? _goLayout : null,
            child: const Text('Раскладка'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(info, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: ColoredBox(
              color: CanvasPalette.bg,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                  _lastViewport = viewport;
                  if (!_viewCentered) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_viewCentered) _centerOnCursor();
                    });
                  }
                  final canvasSize = Size(viewport.width * 2.2, viewport.height * 2.2);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      InteractiveViewer(
                        transformationController: _transform,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(300),
                        minScale: 0.2,
                        maxScale: 6,
                        panEnabled: true,
                        scaleEnabled: true,
                        child: SizedBox(
                          width: canvasSize.width,
                          height: canvasSize.height,
                          child: CustomPaint(
                            size: canvasSize,
                            painter: _WallsPainter(
                              walls: _draft.walls,
                              cursor: _draft.cursor,
                              isClosed: _draft.isClosed,
                            ),
                          ),
                        ),
                      ),
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
                                if (_draft.walls.length >= 3 && !_draft.isClosed)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: OutlinedButton.icon(
                                      onPressed: () => setState(() => _draft.closeRoom()),
                                      icon: const Icon(Icons.link),
                                      label: const Text('Замкнуть комнату'),
                                    ),
                                  ),
                                AnalogJoystick(onDirection: _askLength),
                                const SizedBox(height: 4),
                                Text(
                                  'Отклоните стик и отпустите — затем введите длину',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.white70,
                                        shadows: const [
                                          Shadow(blurRadius: 4, color: Colors.black87),
                                        ],
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _WallsPainter extends CustomPainter {
  _WallsPainter({
    required this.walls,
    required this.cursor,
    required this.isClosed,
  });

  final List<List<double>> walls;
  final List<double> cursor;
  final bool isClosed;

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

    for (final w in walls) {
      canvas.drawLine(map(w[0], w[1]), map(w[2], w[3]), wallPaint);
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
      old.walls != walls || old.cursor != cursor || old.isClosed != isClosed;
}
