import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'canvas_metrics.dart';
import 'dimension_lines.dart';
import 'floor_layout.dart';
import 'wall_elevation_geometry.dart';

/// Wall elevation: tile layout with opening cutouts (2D unfold).
class WallElevationPainter extends CustomPainter {
  WallElevationPainter({
    required this.walls,
    required this.metrics,
    required this.layout,
    this.openings = const [],
    this.showCutDims = true,
    this.lightBackground = false,
    this.wallLabel,
    this.showElevationDims = false,
    this.bgColor = const Color.fromRGBO(31, 33, 33, 1),
    this.wallStrokeColor = const Color.fromRGBO(240, 245, 250, 1),
    this.fullTileColor = const Color.fromRGBO(230, 230, 230, 0.3),
    this.cutTileColor = const Color.fromRGBO(179, 179, 179, 0.3),
    this.gridLineColor = const Color.fromRGBO(201, 214, 222, 0.7),
    this.textColor = const Color.fromRGBO(240, 245, 250, 1),
  });

  final List<List<double>> walls;
  final FloorPlanMetrics metrics;
  final FloorLayoutSnapshot layout;
  final List<WallOpeningRect> openings;
  final bool showCutDims;
  final bool lightBackground;
  final String? wallLabel;
  final bool showElevationDims;
  final Color bgColor;
  final Color wallStrokeColor;
  final Color fullTileColor;
  final Color cutTileColor;
  final Color gridLineColor;
  final Color textColor;

  Color get _bg => lightBackground ? Colors.white : bgColor;
  Color get _wallStroke => lightBackground ? const Color(0xFF37474F) : wallStrokeColor;
  Color get _fullTile => lightBackground ? const Color(0xFFECEFF1) : fullTileColor;
  Color get _cutTile => lightBackground ? const Color(0xFFB0BEC5) : cutTileColor;
  Color get _gridLine => lightBackground ? const Color(0xFF90A4AE) : gridLineColor;
  Color get _text => lightBackground ? const Color(0xFF263238) : textColor;

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
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    if (wallLabel != null && wallLabel!.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: wallLabel,
          style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 16);
      tp.paint(canvas, const Offset(8, 6));
    }

    final clip = _roomPath();
    canvas.save();
    canvas.clipPath(clip);

    final fullPaint = Paint()..color = _fullTile;
    final cutPaint = Paint()..color = _cutTile;
    final linePaint = Paint()
      ..color = _gridLine
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
        if (cw < b.widthCm * 0.98 || ch < b.heightCm * 0.98) {
          final fontSize = (8.5 * (metrics.scale / 2).clamp(0.55, 1.5)).clamp(7.0, 13.0);
          final tp = TextPainter(
            text: TextSpan(
              text: b.cutLabel,
              style: TextStyle(
                color: _text,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                shadows: lightBackground
                    ? null
                    : const [
                        Shadow(blurRadius: 3, color: Colors.black87),
                        Shadow(blurRadius: 1, color: Colors.black),
                      ],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: math.max(8, r.width - 2));
          if (tp.width <= r.width + 4 && tp.height <= r.height + 2) {
            final origin = Offset(-tp.width / 2, -tp.height / 2);
            if (!lightBackground) {
              final chip = RRect.fromRectAndRadius(
                Rect.fromLTWH(origin.dx - 2, origin.dy - 1, tp.width + 4, tp.height + 2),
                const Radius.circular(2),
              );
              canvas.drawRRect(chip, Paint()..color = const Color(0xAA000000));
            }
            tp.paint(canvas, origin);
          }
        }
      }
      canvas.restore();
    }
    canvas.restore();

    final openingFill = Paint()..color = lightBackground ? Colors.white : bgColor;
    final openingEdge = Paint()
      ..color = lightBackground ? const Color(0xFFE65100) : const Color(0xFFFF9800)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final o in openings) {
      final p0 = metrics.map(o.leftCm, o.bottomCm);
      final p1 = metrics.map(o.leftCm + o.widthCm, o.bottomCm + o.heightCm);
      final rect = Rect.fromPoints(p0, p1);
      canvas.drawRect(rect, openingFill);
      canvas.drawRect(rect, openingEdge);

      final dash = Paint()
        ..color = openingEdge.color.withValues(alpha: 0.65)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      _drawDashedRect(canvas, rect, dash);

      final kindLabel = o.kind == 'door'
          ? 'дверь'
          : o.kind == 'window'
              ? 'окно'
              : 'проём';
      final label = o.label?.isNotEmpty == true ? '${o.label} · $kindLabel' : kindLabel;
      final dim = '${o.widthCm.round()}×${o.heightCm.round()}';
      final tp = TextPainter(
        text: TextSpan(
          text: '$label\n$dim',
          style: TextStyle(
            color: openingEdge.color,
            fontSize: (9 * metrics.scale / 2).clamp(8.0, 11.0),
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: rect.width - 4);
      if (tp.height <= rect.height - 4) {
        tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
      }
    }

    final wallPaint = Paint()
      ..color = _wallStroke
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final w in walls) {
      canvas.drawLine(metrics.map(w[0], w[1]), metrics.map(w[2], w[3]), wallPaint);
    }

    if (showElevationDims && walls.length >= 4) {
      final len = walls[1][0];
      final h = walls[2][1];
      final dimColor = lightBackground ? const Color(0xFF1565C0) : const Color(0xFF64B5F6);
      DimensionLines.drawHorizontalDimension(
        canvas,
        x0: 0,
        x1: len,
        y: 0,
        mapY: 0,
        map: metrics.map,
        label: '${DimensionLines.formatCm(len)} см',
        color: dimColor,
        below: true,
        offsetPx: 32,
      );
      DimensionLines.drawVerticalDimension(
        canvas,
        x: 0,
        y0: 0,
        y1: h,
        map: metrics.map,
        label: '${DimensionLines.formatCm(h)} см',
        color: dimColor,
        left: true,
        offsetPx: 36,
      );
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    for (final edge in [
      (Offset(rect.left, rect.top), Offset(rect.right, rect.top)),
      (Offset(rect.right, rect.top), Offset(rect.right, rect.bottom)),
      (Offset(rect.right, rect.bottom), Offset(rect.left, rect.bottom)),
      (Offset(rect.left, rect.bottom), Offset(rect.left, rect.top)),
    ]) {
      _drawDashedLine(canvas, edge.$1, edge.$2, paint, dash, gap);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
    final delta = b - a;
    final len = delta.distance;
    if (len < 1) return;
    final dir = delta / len;
    var t = 0.0;
    while (t < len) {
      final t1 = (t + dash).clamp(0.0, len);
      canvas.drawLine(a + dir * t, a + dir * t1, paint);
      t += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant WallElevationPainter old) =>
      old.walls != walls ||
      old.layout != layout ||
      old.openings != openings ||
      old.showCutDims != showCutDims ||
      old.lightBackground != lightBackground ||
      old.wallLabel != wallLabel ||
      old.showElevationDims != showElevationDims ||
      old.metrics.scale != metrics.scale;
}
