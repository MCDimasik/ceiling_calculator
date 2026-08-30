import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/finish_model.dart';

/// Cheap 2D hit: nearest wall segment + offset along it (cm).
class WallHit {
  const WallHit({
    required this.wallIndex,
    required this.offsetAlongCm,
    required this.distanceCm,
    required this.wallLengthCm,
  });

  final int wallIndex;
  final double offsetAlongCm;
  final double distanceCm;
  final double wallLengthCm;
}

WallHit? nearestWallHit(
  List<List<double>> walls,
  double x,
  double y, {
  double maxDistCm = 45,
}) {
  WallHit? best;
  for (var i = 0; i < walls.length; i++) {
    final w = walls[i];
    final ax = w[0], ay = w[1], bx = w[2], by = w[3];
    final abx = bx - ax, aby = by - ay;
    final len2 = abx * abx + aby * aby;
    if (len2 < 1e-6) continue;
    final len = math.sqrt(len2);
    var t = ((x - ax) * abx + (y - ay) * aby) / len2;
    t = t.clamp(0.0, 1.0);
    final px = ax + abx * t;
    final py = ay + aby * t;
    final d = math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
    if (d > maxDistCm) continue;
    if (best == null || d < best.distanceCm) {
      best = WallHit(
        wallIndex: i,
        offsetAlongCm: t * len,
        distanceCm: d,
        wallLengthCm: len,
      );
    }
  }
  return best;
}

/// Top-down plan: tap/drag a wall to place the selected opening. O(walls) per gesture.
class OpeningPlanPlacer extends StatelessWidget {
  const OpeningPlanPlacer({
    super.key,
    required this.walls,
    required this.openings,
    this.placingIndex,
    this.onPlace,
    this.onSelectOpening,
  });

  final List<List<double>> walls;
  final List<RoomOpening> openings;

  /// Which opening type is being placed; null = view-only.
  final int? placingIndex;

  /// Called when user places/moves the active opening on a wall.
  /// [offsetAlongCm] is the **start** of the opening (left edge along wall).
  final void Function(int wallIndex, double offsetAlongCm)? onPlace;

  final ValueChanged<int>? onSelectOpening;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final metrics = _PlanMetrics.compute(size, walls);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handle(d.localPosition, metrics, tap: true),
          onPanUpdate: placingIndex == null
              ? null
              : (d) => _handle(d.localPosition, metrics, tap: false),
          child: CustomPaint(
            size: size,
            painter: _PlanPainter(
              walls: walls,
              openings: openings,
              metrics: metrics,
              placingIndex: placingIndex,
            ),
          ),
        );
      },
    );
  }

  void _handle(Offset local, _PlanMetrics m, {required bool tap}) {
    final world = m.screenToWorld(local);
    // Prefer selecting an existing mark when not dragging.
    if (tap && placingIndex == null && onSelectOpening != null) {
      final idx = _hitOpeningMark(world, m);
      if (idx != null) {
        onSelectOpening!(idx);
        return;
      }
    }
    if (placingIndex == null || onPlace == null) return;
    final hit = nearestWallHit(walls, world.dx, world.dy);
    if (hit == null) return;
    final o = openings[placingIndex!];
    // Center opening on tap when possible.
    var start = hit.offsetAlongCm - o.widthCm / 2;
    start = start.clamp(0.0, math.max(0.0, hit.wallLengthCm - o.widthCm));
    onPlace!(hit.wallIndex, start);
  }

  int? _hitOpeningMark(Offset world, _PlanMetrics m) {
    const gap = 30.0;
    var bestI = -1;
    var bestD = 25.0; // cm
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
      final n = math.max(1, o.quantity);
      for (var q = 0; q < n; q++) {
        final t0 = o.offsetAlongWallCm + q * (o.widthCm + gap);
        if (t0 >= len) break;
        final mid = t0 + o.widthCm / 2;
        final mx = ax + ux * mid;
        final my = ay + uy * mid;
        final d = math.sqrt(math.pow(world.dx - mx, 2) + math.pow(world.dy - my, 2));
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }
    }
    return bestI >= 0 ? bestI : null;
  }
}

class _PlanMetrics {
  _PlanMetrics({
    required this.scale,
    required this.minX,
    required this.minY,
    required this.maxY,
    required this.ox,
    required this.oy,
    required this.size,
  });

  final double scale;
  final double minX;
  final double minY;
  final double maxY;
  final double ox;
  final double oy;
  final Size size;

  static _PlanMetrics compute(Size size, List<List<double>> walls) {
    double minX = 0, maxX = 100, minY = 0, maxY = 100;
    if (walls.isNotEmpty) {
      minX = maxX = walls.first[0];
      minY = maxY = walls.first[1];
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
    final ww = math.max(1.0, maxX - minX);
    final wh = math.max(1.0, maxY - minY);
    final scale = math.min(size.width / ww, size.height / wh) * 0.9;
    final ox = (size.width - ww * scale) / 2;
    final oy = (size.height - wh * scale) / 2;
    return _PlanMetrics(
      scale: scale,
      minX: minX,
      minY: minY,
      maxY: maxY,
      ox: ox,
      oy: oy,
      size: size,
    );
  }

  Offset worldToScreen(double x, double y) {
    final px = ox + (x - minX) * scale;
    final py = oy + (maxY - y) * scale;
    return Offset(px, py);
  }

  Offset screenToWorld(Offset p) {
    final x = (p.dx - ox) / scale + minX;
    final y = maxY - (p.dy - oy) / scale;
    return Offset(x, y);
  }
}

class _PlanPainter extends CustomPainter {
  _PlanPainter({
    required this.walls,
    required this.openings,
    required this.metrics,
    required this.placingIndex,
  });

  final List<List<double>> walls;
  final List<RoomOpening> openings;
  final _PlanMetrics metrics;
  final int? placingIndex;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      Paint()..color = const Color(0xFF1A2330),
    );

    final wallPaint = Paint()
      ..color = const Color(0xFF8FB4D4)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final activeWall = Paint()
      ..color = const Color(0xFFFFC857)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final highlightWall = placingIndex != null &&
            placingIndex! >= 0 &&
            placingIndex! < openings.length
        ? openings[placingIndex!].wallIndex
        : null;

    for (var i = 0; i < walls.length; i++) {
      final w = walls[i];
      final a = metrics.worldToScreen(w[0], w[1]);
      final b = metrics.worldToScreen(w[2], w[3]);
      canvas.drawLine(a, b, i == highlightWall ? activeWall : wallPaint);

      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: i == highlightWall ? const Color(0xFFFFC857) : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, mid - Offset(tp.width / 2, tp.height + 4));
    }

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
      final selected = i == placingIndex;
      final fill = Paint()
        ..color = o.kind == 'door'
            ? (selected ? const Color(0xFFE07A5F) : const Color(0xFFC96A52))
            : (selected ? const Color(0xFF81B29A) : const Color(0xFF6A9B84))
        ..strokeWidth = selected ? 8 : 6
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;

      final n = math.max(1, o.quantity);
      for (var q = 0; q < n; q++) {
        final t0 = o.offsetAlongWallCm + q * (o.widthCm + gap);
        if (t0 >= len) break;
        final t1 = math.min(len, t0 + o.widthCm);
        final a = metrics.worldToScreen(ax + ux * t0, ay + uy * t0);
        final b = metrics.worldToScreen(ax + ux * t1, ay + uy * t1);
        canvas.drawLine(a, b, fill);
      }
    }

    if (placingIndex != null) {
      final tip = TextPainter(
        text: const TextSpan(
          text: 'Коснитесь стены · тяните вдоль неё',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 16);
      tip.paint(canvas, Offset(8, size.height - tip.height - 8));
    }
  }

  @override
  bool shouldRepaint(covariant _PlanPainter old) =>
      old.walls != walls ||
      old.openings != openings ||
      old.placingIndex != placingIndex ||
      old.metrics.scale != metrics.scale;
}
