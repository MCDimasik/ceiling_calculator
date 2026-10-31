import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/canvas_metrics.dart';
import '../../domain/finish_model.dart';
import '../../domain/floor_layout.dart';
import '../../domain/wall_elevation_geometry.dart';
import '../../domain/wall_elevation_painter.dart';
import 'canvas_palette.dart';

export '../../domain/canvas_metrics.dart';
export '../../domain/wall_elevation_painter.dart';

/// Paints precomputed [FloorLayoutSnapshot] boards (cached, discrete objects).
class FloorPlanPainter extends CustomPainter {
  FloorPlanPainter({
    required this.walls,
    required this.metrics,
    required this.layout,
    this.showCutDims = true,
    this.paintBackground = true,
    this.paintWalls = true,
  });

  final List<List<double>> walls;
  final FloorPlanMetrics metrics;
  final FloorLayoutSnapshot layout;
  final bool showCutDims;
  final bool paintBackground;
  final bool paintWalls;

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
    if (paintBackground) {
      canvas.drawRect(Offset.zero & size, Paint()..color = CanvasPalette.bg);
    }
    final clip = _roomPath();
    canvas.save();
    canvas.clipPath(clip);

    // Solid floor fill (screed / empty layout, and under tile boards).
    canvas.drawPath(
      clip,
      Paint()..color = const Color(0xFF3A4A5C),
    );

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
      canvas.restore();
    }
    canvas.restore();

    // Cut labels at the visible-piece centroid (not full-board centre — that
    // often lies outside the room and gets clipped, hiding one wall's cuts).
    if (showCutDims) {
      for (final b in layout.boards) {
        if (!b.cut) continue;
        final cw = b.cutWidthCm ?? b.widthCm;
        final ch = b.cutHeightCm ?? b.heightCm;
        if (cw >= b.widthCm * 0.98 && ch >= b.heightCm * 0.98) continue;
        // Match ceiling cut labels in overview (~tilePx * 0.28).
        final tilePx = math.min(b.widthCm, b.heightCm) * metrics.scale;
        final fontSize = (tilePx * 0.28).clamp(8.0, 16.0);
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
        )..layout();
        final pos = metrics.map(b.labelX, b.labelY);
        final origin = Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2);
        final chip = RRect.fromRectAndRadius(
          Rect.fromLTWH(origin.dx - 2, origin.dy - 1, tp.width + 4, tp.height + 2),
          const Radius.circular(2),
        );
        canvas.drawRRect(chip, Paint()..color = const Color(0xAA000000));
        tp.paint(canvas, origin);
      }
    }

    final wallPaint = Paint()
      ..color = CanvasPalette.wall
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (paintWalls) {
      for (final w in walls) {
        canvas.drawLine(metrics.map(w[0], w[1]), metrics.map(w[2], w[3]), wallPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter old) {
    if (old.walls != walls ||
        old.showCutDims != showCutDims ||
        old.paintBackground != paintBackground ||
        old.paintWalls != paintWalls ||
        old.metrics.scale != metrics.scale ||
        old.layout.fullCount != layout.fullCount ||
        old.layout.cutCount != layout.cutCount ||
        old.layout.boards.length != layout.boards.length) {
      return true;
    }
    final a = old.layout.boards;
    final b = layout.boards;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.cxCm != y.cxCm ||
          x.cyCm != y.cyCm ||
          x.cutWidthCm != y.cutWidthCm ||
          x.cutHeightCm != y.cutHeightCm ||
          x.cut != y.cut ||
          x.cutLabel != y.cutLabel) {
        return true;
      }
    }
    return false;
  }
}

/// Semi-transparent project floor layout overlay (project vs fact).
class FloorLayoutGhostPainter extends CustomPainter {
  FloorLayoutGhostPainter({
    required this.metrics,
    required this.layout,
  });

  final FloorPlanMetrics metrics;
  final FloorLayoutSnapshot layout;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0x44FF9800);
    final stroke = Paint()
      ..color = const Color(0xCCFF9800)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final b in layout.boards) {
      final center = metrics.map(b.cxCm, b.cyCm);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-b.rotationRad);
      final hw = b.widthCm * metrics.scale / 2;
      final hh = b.heightCm * metrics.scale / 2;
      final r = Rect.fromLTRB(-hw, -hh, hw, hh);
      canvas.drawRect(r, fill);
      canvas.drawRect(r, stroke);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant FloorLayoutGhostPainter old) =>
      old.metrics.scale != metrics.scale || old.layout != layout;
}

class IsometricShellPainter extends CustomPainter {
  IsometricShellPainter({
    required this.shell,
    required this.walls,
    this.yaw = 0.55,
    this.pitch = 0.35,
    this.showWalls = true,
    this.showFloor = true,
    this.showCeiling = true,
    this.showOpenings = true,
    this.selectedOpeningIndex,
  });

  final RoomShell3D shell;
  final List<List<double>> walls;
  final double yaw;
  final double pitch;
  final bool showWalls;
  final bool showFloor;
  final bool showCeiling;
  final bool showOpenings;
  final int? selectedOpeningIndex;

  static Offset projectIso({
    required double x,
    required double y,
    required double z,
    required Size size,
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    required double heightCm,
    required double yaw,
    required double pitch,
  }) {
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final cz = heightCm / 2;
    final rawSpan = math.max(maxX - minX, math.max(maxY - minY, heightCm));
    final span = rawSpan < 1.0 ? 1.0 : (rawSpan > 1e9 ? 1e9 : rawSpan);
    final s = math.min(size.width, size.height) * 0.52 / span;

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

    return Offset(
      size.width / 2 + x1 * s,
      size.height / 2 - z2 * s - y2 * s * 0.15,
    );
  }

  /// Hit-test openings in screen space (long-press / tap in 3D overview).
  static int? hitOpeningIndex({
    required Offset local,
    required Size size,
    required RoomShell3D shell,
    required List<List<double>> walls,
    required double yaw,
    required double pitch,
    double maxDistPx = 36,
  }) {
    final (minX, maxX, minY, maxY) = shell.bounds2d;
    final h = shell.heightCm;
    var bestI = -1;
    var bestD = maxDistPx;
    for (var i = 0; i < shell.openings.length; i++) {
      final o = shell.openings[i];
      final wi = o.wallIndex;
      if (wi == null || wi < 0 || wi >= walls.length) continue;
      final w = walls[wi];
      final ax = w[0], ay = w[1], bx = w[2], by = w[3];
      final wallLen = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
      if (wallLen < 1) continue;
      final ux = (bx - ax) / wallLen;
      final uy = (by - ay) / wallLen;
      final mid = o.offsetAlongWallCm + o.widthCm / 2;
      final mx = ax + ux * mid;
      final my = ay + uy * mid;
      final mz = (o.sillHeightCm + o.heightCm / 2).clamp(0.0, h);
      final p = projectIso(
        x: mx,
        y: my,
        z: mz,
        size: size,
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        heightCm: h,
        yaw: yaw,
        pitch: pitch,
      );
      final d = (p - local).distance;
      if (d < bestD) {
        bestD = d;
        bestI = i;
      }
    }
    return bestI >= 0 ? bestI : null;
  }

  Offset _iso(double x, double y, double z, Size size, double minX, double maxX, double minY, double maxY) {
    return projectIso(
      x: x,
      y: y,
      z: z,
      size: size,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      heightCm: shell.heightCm,
      yaw: yaw,
      pitch: pitch,
    );
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
    // Ceiling = cooler translucent slab on top; floor = warmer ground plane.
    final topPaint = Paint()
      ..color = const Color(0x996B9EC4)
      ..style = PaintingStyle.fill;
    final holePaint = Paint()
      ..color = const Color(0xFF0E1520)
      ..style = PaintingStyle.fill;
    final holeEdge = Paint()
      ..color = const Color(0xFFFFC857)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final floorPaint = Paint()
      ..color = const Color(0xFF5C4A3A)
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
    if (showFloor) {
      canvas.drawPath(floorPath, floorPaint);
      canvas.drawPath(floorPath, edge);
    }

    if (showWalls) {
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
    }

    if (showOpenings) {
      const gapCm = 30.0;
      for (var oi = 0; oi < shell.openings.length; oi++) {
        final o = shell.openings[oi];
        final wi = o.wallIndex;
        if (wi == null || wi < 0 || wi >= walls.length) continue;
        final w = walls[wi];
        final ax = w[0], ay = w[1], bx = w[2], by = w[3];
        final wallLen = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
        if (wallLen < 1) continue;
        final ux = (bx - ax) / wallLen;
        final uy = (by - ay) / wallLen;
        final selected = oi == selectedOpeningIndex;
        final edgePaint = selected
            ? (Paint()
              ..color = const Color(0xFFFFC857)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4)
            : holeEdge;
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
          canvas.drawPath(hole, edgePaint);
          if (selected && q == 0) {
            final leftGap = t0;
            final rightGap = wallLen - t1;
            final width = t1 - t0;
            void chip(Offset at, String text, Color color) {
              final tp = TextPainter(
                text: TextSpan(
                  text: text,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    shadows: const [Shadow(blurRadius: 2, color: Colors.black87)],
                  ),
                ),
                textDirection: TextDirection.ltr,
              )..layout();
              final origin =
                  Offset(at.dx - tp.width / 2, at.dy - tp.height / 2);
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromLTWH(
                    origin.dx - 4,
                    origin.dy - 2,
                    tp.width + 8,
                    tp.height + 4,
                  ),
                  const Radius.circular(4),
                ),
                Paint()..color = const Color(0xCC000000),
              );
              tp.paint(canvas, origin);
            }

            if (leftGap > 2) {
              chip(
                map(ax + ux * (leftGap / 2), ay + uy * (leftGap / 2), z1 + 8),
                '${leftGap.round()}',
                const Color(0xFF8FB4D4),
              );
            }
            chip(
              map(ax + ux * ((t0 + t1) / 2), ay + uy * ((t0 + t1) / 2), z1 + 8),
              '${width.round()}',
              const Color(0xFFFFC857),
            );
            if (rightGap > 2) {
              chip(
                map(
                  ax + ux * (t1 + rightGap / 2),
                  ay + uy * (t1 + rightGap / 2),
                  z1 + 8,
                ),
                '${rightGap.round()}',
                const Color(0xFF8FB4D4),
              );
            }
          }
        }
      }
    }

    if (showCeiling) {
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
  }

  @override
  bool shouldRepaint(covariant IsometricShellPainter old) =>
      old.shell.heightCm != shell.heightCm ||
      old.shell.openings != shell.openings ||
      old.walls != walls ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.showWalls != showWalls ||
      old.showFloor != showFloor ||
      old.showCeiling != showCeiling ||
      old.showOpenings != showOpenings ||
      old.selectedOpeningIndex != selectedOpeningIndex;
}
