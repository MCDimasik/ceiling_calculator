import 'package:flutter/material.dart';

import '../domain/ceiling_grid.dart';

class DemoGridScreen extends StatefulWidget {
  const DemoGridScreen({super.key});

  @override
  State<DemoGridScreen> createState() => _DemoGridScreenState();
}

class _DemoGridScreenState extends State<DemoGridScreen> {
  late final CeilingGrid _grid;
  // Simple 300×240 cm rectangle room (cm).
  final _room = <(double, double)>[
    (0, 0),
    (300, 0),
    (300, 240),
    (0, 240),
  ];

  @override
  void initState() {
    super.initState();
    _grid = CeilingGrid(cellSizeCm: 60);
    _rebuild();
  }

  final _walls = [
    [0.0, 0.0, 300.0, 0.0],
    [300.0, 0.0, 300.0, 240.0],
    [300.0, 240.0, 0.0, 240.0],
    [0.0, 240.0, 0.0, 0.0],
  ];

  void _rebuild() {
    _grid.rebuild(roomPoints: _room, walls: _walls);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final (full, cut) = _grid.effectiveTileCounts;
    return Scaffold(
      appBar: AppBar(title: const Text('Сетка (CeilingGrid)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Целых: $full | Резаных: $cut | Свет: ${_grid.lightCount}\n'
              'Offset: ${_grid.offsetXCm.toStringAsFixed(0)}, ${_grid.offsetYCm.toStringAsFixed(0)}',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapUp: (d) {
                    final cell = _hitTest(d.localPosition, constraints.biggest);
                    if (cell == null) return;
                    setState(() => _grid.toggleLight(cell.col, cell.row));
                  },
                  child: CustomPaint(
                    size: constraints.biggest,
                    painter: _GridPainter(grid: _grid, room: _room),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () {
                      _grid.setOffset(_grid.offsetXCm + 10, _grid.offsetYCm);
                      _rebuild();
                    },
                    child: const Text('Offset X +10'),
                  ),
                  FilledButton(
                    onPressed: () {
                      _grid.setOffset(_grid.offsetXCm, _grid.offsetYCm + 10);
                      _rebuild();
                    },
                    child: const Text('Offset Y +10'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      _grid.setOffset(0, 0);
                      _rebuild();
                    },
                    child: const Text('Сброс offset'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  GridCell? _hitTest(Offset local, Size size) {
    const pad = 24.0;
    final bounds = _roomBounds();
    final scale = _scale(size, bounds, pad);
    final ox = (size.width - (bounds.$3 - bounds.$1) * scale) / 2;
    final oy = (size.height - (bounds.$4 - bounds.$2) * scale) / 2;
    final xCm = (local.dx - ox) / scale + bounds.$1;
    final yCm = (local.dy - oy) / scale + bounds.$2;
    for (final c in _grid.cells) {
      if (xCm >= c.xCm &&
          xCm < c.xCm + _grid.cellSizeCm &&
          yCm >= c.yCm &&
          yCm < c.yCm + _grid.cellSizeCm) {
        return c;
      }
    }
    return null;
  }

  (double minX, double minY, double maxX, double maxY) _roomBounds() {
    var minX = _room.first.$1, maxX = _room.first.$1;
    var minY = _room.first.$2, maxY = _room.first.$2;
    for (final p in _room) {
      if (p.$1 < minX) minX = p.$1;
      if (p.$1 > maxX) maxX = p.$1;
      if (p.$2 < minY) minY = p.$2;
      if (p.$2 > maxY) maxY = p.$2;
    }
    return (minX, minY, maxX, maxY);
  }

  double _scale(Size size, (double, double, double, double) b, double pad) {
    final w = b.$3 - b.$1;
    final h = b.$4 - b.$2;
    return ((size.width - pad * 2) / w).clamp(0.0, double.infinity).clamp(
          0,
          (size.height - pad * 2) / h,
        );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.grid, required this.room});

  final CeilingGrid grid;
  final List<(double, double)> room;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 24.0;
    var minX = room.first.$1, maxX = room.first.$1;
    var minY = room.first.$2, maxY = room.first.$2;
    for (final p in room) {
      minX = minX < p.$1 ? minX : p.$1;
      maxX = maxX > p.$1 ? maxX : p.$1;
      minY = minY < p.$2 ? minY : p.$2;
      maxY = maxY > p.$2 ? maxY : p.$2;
    }
    final w = maxX - minX;
    final h = maxY - minY;
    final scale = ((size.width - pad * 2) / w).clamp(0.0, (size.height - pad * 2) / h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;

    Offset map(double x, double y) => Offset(ox + (x - minX) * scale, oy + (y - minY) * scale);

    final roomPaint = Paint()
      ..color = const Color(0x332F6DF6)
      ..style = PaintingStyle.fill;
    final roomPath = Path()..moveTo(map(room.first.$1, room.first.$2).dx, map(room.first.$1, room.first.$2).dy);
    for (final p in room.skip(1)) {
      final o = map(p.$1, p.$2);
      roomPath.lineTo(o.dx, o.dy);
    }
    roomPath.close();
    canvas.drawPath(roomPath, roomPaint);

    final fullPaint = Paint()..color = const Color(0x33888888);
    final cutPaint = Paint()..color = const Color(0x55AAAAAA);
    final lightPaint = Paint()..color = const Color(0x88FFC107);
    for (final c in grid.cells) {
      final rect = Rect.fromPoints(
        map(c.xCm, c.yCm),
        map(c.xCm + grid.cellSizeCm, c.yCm + grid.cellSizeCm),
      );
      canvas.drawRect(rect, c.hasLight ? lightPaint : (c.kind == CellKind.full ? fullPaint : cutPaint));
    }

    final linePaint = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1;
    for (final l in grid.verticalLines) {
      canvas.drawLine(map(l.$1, l.$2), map(l.$3, l.$4), linePaint);
    }
    for (final l in grid.horizontalLines) {
      canvas.drawLine(map(l.$1, l.$2), map(l.$3, l.$4), linePaint);
    }

    final wallPaint = Paint()
      ..color = const Color(0xFFE8EEF8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(roomPath, wallPaint);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => true;
}
