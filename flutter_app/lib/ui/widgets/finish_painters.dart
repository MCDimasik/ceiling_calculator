import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/finish_model.dart';
import '../../domain/floor_layout.dart';
import 'canvas_palette.dart';

class FloorPlanMetrics {
  FloorPlanMetrics._({
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

  factory FloorPlanMetrics.fromWalls(List<List<double>> walls, Size size) {
    var minX = walls.first[0];
    var maxX = walls.first[0];
    var minY = walls.first[1];
    var maxY = walls.first[1];
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
    final worldW = (maxX - minX).clamp(1.0, 1e9);
    final worldH = (maxY - minY).clamp(1.0, 1e9);
    final scale = math.min(size.width / worldW, size.height / worldH) * 0.88;
    final ox = (size.width - worldW * scale) / 2;
    final oy = (size.height - worldH * scale) / 2;
    return FloorPlanMetrics._(
      scale: scale,
      minX: minX,
      minY: minY,
      maxY: maxY,
      ox: ox,
      oy: oy,
      size: size,
    );
  }

  factory FloorPlanMetrics.fromRect(double widthCm, double heightCm, Size size) {
    final worldW = widthCm.clamp(1.0, 1e9);
    final worldH = heightCm.clamp(1.0, 1e9);
    final scale = math.min(size.width / worldW, size.height / worldH) * 0.88;
    final ox = (size.width - worldW * scale) / 2;
    final oy = (size.height - worldH * scale) / 2;
    return FloorPlanMetrics._(
      scale: scale,
      minX: 0,
      minY: 0,
      maxY: worldH,
      ox: ox,
      oy: oy,
      size: size,
    );
  }

  Offset map(double x, double y) {
    final px = ox + (x - minX) * scale;
    final py = oy + (maxY - y) * scale;
    return Offset(px, py);
  }
}

/// Paints precomputed [FloorLayoutSnapshot] boards (cached, discrete objects).
class FloorPlanPainter extends CustomPainter {
  FloorPlanPainter({
    required this.walls,
    required this.metrics,
    required this.layout,
    this.showCutDims = true,
  });

  final List<List<double>> walls;
  final FloorPlanMetrics metrics;
  final FloorLayoutSnapshot layout;
  final bool showCutDims;

  Path _roomPath() {
    final path = Path();
    if (walls.isEmpty) return path;
    final first = metrics.map(walls.first[0], walls.first[1]);
    path.moveTo(first.dx, first.dy);
    for (final w in walls) {
      final b = metrics.map(w[2], w[3]);
      path.lineTo(b.dx, b.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = CanvasPalette.bg);
    final clip = _roomPath();
    canvas.save();
    canvas.clipPath(clip);

    final fullPaint = Paint()..color = CanvasPalette.fullTile;
    final cutPaint = Paint()..color = CanvasPalette.cutTile;
    final linePaint = Paint()
      ..color = CanvasPalette.grid
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (final b in layout.boards) {
      final center = metrics.map(b.cxCm, b.cyCm);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-b.rotationRad);
      final hw = b.widthCm * metrics.scale / 2;
      final hh = b.heightCm * metrics.scale / 2;
      final r = Rect.fromLTRB(-hw, -hh, hw, hh);
      canvas.drawRect(r, b.cut ? cutPaint : fullPaint);
      canvas.drawRect(r, linePaint);

      if (showCutDims && b.cut) {
        final cw = b.cutWidthCm ?? b.widthCm;
        final ch = b.cutHeightCm ?? b.heightCm;
        // Skip near-full leftovers to reduce clutter.
        if (cw < b.widthCm * 0.98 || ch < b.heightCm * 0.98) {
          final fontSize = (8.5 * (metrics.scale / 2).clamp(0.55, 1.5)).clamp(7.0, 13.0);
          final tp = TextPainter(
            text: TextSpan(
              text: b.cutLabel,
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
          )..layout(maxWidth: math.max(8, r.width - 2));
          if (tp.width <= r.width + 4 && tp.height <= r.height + 2) {
            final origin = Offset(-tp.width / 2, -tp.height / 2);
            final chip = RRect.fromRectAndRadius(
              Rect.fromLTWH(origin.dx - 2, origin.dy - 1, tp.width + 4, tp.height + 2),
              const Radius.circular(2),
            );
            canvas.drawRRect(chip, Paint()..color = const Color(0xAA000000));
            tp.paint(canvas, origin);
          }
        }
      }
      canvas.restore();
    }
    canvas.restore();

    final wallPaint = Paint()
      ..color = CanvasPalette.wall
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final w in walls) {
      canvas.drawLine(metrics.map(w[0], w[1]), metrics.map(w[2], w[3]), wallPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter old) =>
      old.walls != walls ||
      old.layout != layout ||
      old.showCutDims != showCutDims ||
      old.metrics.scale != metrics.scale ||
      old.metrics.ox != metrics.ox;
}

class IsometricShellPainter extends CustomPainter {
  IsometricShellPainter({
    required this.shell,
    required this.walls,
    this.yaw = 0.55,
    this.pitch = 0.35,
  });

  final RoomShell3D shell;
  final List<List<double>> walls;
  final double yaw;
  final double pitch;

  Offset _iso(double x, double y, double z, Size size, double minX, double maxX, double minY, double maxY) {
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final cz = shell.heightCm / 2;
    final span = math.max(maxX - minX, math.max(maxY - minY, shell.heightCm)).clamp(1.0, 1e9);
    final s = math.min(size.width, size.height) * 0.52 / span;

    // Orbit camera: yaw around Z, pitch around X — uniform orthographic scale (no squash).
    final dx = x - cx;
    final dy = y - cy;
    final dz = z - cz;

    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final x1 = dx * cosY - dy * sinY;
    final y1 = dx * sinY + dy * cosY;
    final z1 = dz;

    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);
    final y2 = y1 * cosP - z1 * sinP;
    final z2 = y1 * sinP + z1 * cosP;

    return Offset(size.width / 2 + x1 * s, size.height / 2 - z2 * s - y2 * s * 0.15);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (minX, maxX, minY, maxY) = shell.bounds2d;
    final h = shell.heightCm;
    final floor = shell.floorPolygonCm;
    final n = floor.length;
    if (n < 3) return;

    Offset map(double x, double y, double z) => _iso(x, y, z, size, minX, maxX, minY, maxY);

    final wallPaint = Paint()
      ..color = const Color(0xFF4A6A88)
      ..style = PaintingStyle.fill;
    final edge = Paint()
      ..color = const Color(0xFFE8F0F8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final topPaint = Paint()
      ..color = const Color(0xFF6B8BA8)
      ..style = PaintingStyle.fill;
    final holePaint = Paint()
      ..color = const Color(0xFF0E1520)
      ..style = PaintingStyle.fill;
    final holeEdge = Paint()
      ..color = const Color(0xFFFFC857)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final floorPaint = Paint()
      ..color = const Color(0xFF2A3848)
      ..style = PaintingStyle.fill;

    final floorPath = Path();
    for (var i = 0; i < n; i++) {
      final p = map(floor[i].dx, floor[i].dy, 0);
      if (i == 0) {
        floorPath.moveTo(p.dx, p.dy);
      } else {
        floorPath.lineTo(p.dx, p.dy);
      }
    }
    floorPath.close();
    canvas.drawPath(floorPath, floorPaint);
    canvas.drawPath(floorPath, edge);

    for (var i = 0; i < n; i++) {
      final a = floor[i];
      final b = floor[(i + 1) % n];
      final path = Path()
        ..moveTo(map(a.dx, a.dy, 0).dx, map(a.dx, a.dy, 0).dy)
        ..lineTo(map(b.dx, b.dy, 0).dx, map(b.dx, b.dy, 0).dy)
        ..lineTo(map(b.dx, b.dy, h).dx, map(b.dx, b.dy, h).dy)
        ..lineTo(map(a.dx, a.dy, h).dx, map(a.dx, a.dy, h).dy)
        ..close();
      canvas.drawPath(path, wallPaint);
      canvas.drawPath(path, edge);

      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final labelAt = map(mid.dx, mid.dy, h * 0.55);
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, labelAt - Offset(tp.width / 2, tp.height / 2));
    }

    const gapCm = 30.0;
    for (final o in shell.openings) {
      final wi = o.wallIndex;
      if (wi == null || wi < 0 || wi >= walls.length) continue;
      final w = walls[wi];
      final ax = w[0], ay = w[1], bx = w[2], by = w[3];
      final wallLen = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
      if (wallLen < 1) continue;
      final ux = (bx - ax) / wallLen;
      final uy = (by - ay) / wallLen;
      final count = math.max(1, o.quantity);
      for (var q = 0; q < count; q++) {
        final start = o.offsetAlongWallCm + q * (o.widthCm + gapCm);
        if (start >= wallLen) break;
        final t0 = start.clamp(0.0, wallLen).toDouble();
        final t1 = (start + o.widthCm).clamp(0.0, wallLen).toDouble();
        if (t1 - t0 < 1) continue;
        final z0 = o.sillHeightCm.clamp(0.0, h).toDouble();
        final z1 = (o.sillHeightCm + o.heightCm).clamp(0.0, h).toDouble();
        final p0 = Offset(ax + ux * t0, ay + uy * t0);
        final p1 = Offset(ax + ux * t1, ay + uy * t1);
        final hole = Path()
          ..moveTo(map(p0.dx, p0.dy, z0).dx, map(p0.dx, p0.dy, z0).dy)
          ..lineTo(map(p1.dx, p1.dy, z0).dx, map(p1.dx, p1.dy, z0).dy)
          ..lineTo(map(p1.dx, p1.dy, z1).dx, map(p1.dx, p1.dy, z1).dy)
          ..lineTo(map(p0.dx, p0.dy, z1).dx, map(p0.dx, p0.dy, z1).dy)
          ..close();
        canvas.drawPath(hole, holePaint);
        canvas.drawPath(hole, holeEdge);
      }
    }

    final top = Path();
    for (var i = 0; i < n; i++) {
      final p = map(floor[i].dx, floor[i].dy, h);
      if (i == 0) {
        top.moveTo(p.dx, p.dy);
      } else {
        top.lineTo(p.dx, p.dy);
      }
    }
    top.close();
    canvas.drawPath(top, topPaint);
    canvas.drawPath(top, edge);
  }

  @override
  bool shouldRepaint(covariant IsometricShellPainter old) =>
      old.shell.heightCm != shell.heightCm ||
      old.shell.openings != shell.openings ||
      old.walls != walls ||
      old.yaw != yaw ||
      old.pitch != pitch;
}
