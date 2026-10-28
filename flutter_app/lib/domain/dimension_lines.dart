import 'dart:math' as math;

import 'package:flutter/material.dart';

/// CAD-style dimension line with extension ticks and arrow heads.
abstract final class DimensionLines {
  static void drawSegmentDimension(
    Canvas canvas, {
    required Offset a,
    required Offset b,
    required String label,
    required Color color,
    double offsetPx = 28,
    bool placeAbove = true,
    double fontSize = 10,
  }) {
    final delta = b - a;
    final len = delta.distance;
    if (len < 8) return;

    final dir = delta / len;
    final normal = Offset(-dir.dy, dir.dx) * (placeAbove ? -1 : 1);
    final dimA = a + normal * offsetPx;
    final dimB = b + normal * offsetPx;

    final ext = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    canvas.drawLine(a + normal * 4, dimA, ext);
    canvas.drawLine(b + normal * 4, dimB, ext);

    final line = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    canvas.drawLine(dimA, dimB, line);

    _drawArrow(canvas, dimA, dir, color);
    _drawArrow(canvas, dimB, -dir, color);

    final mid = (dimA + dimB) / 2;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2 + (placeAbove ? -2 : 2)));
  }

  static void drawHorizontalDimension(
    Canvas canvas, {
    required double x0,
    required double x1,
    required double y,
    required double mapY,
    required Offset Function(double x, double y) map,
    required String label,
    required Color color,
    double offsetPx = 28,
    bool below = true,
  }) {
    final a = map(x0, mapY);
    final b = map(x1, mapY);
    drawSegmentDimension(
      canvas,
      a: a,
      b: b,
      label: label,
      color: color,
      offsetPx: offsetPx,
      placeAbove: !below,
    );
  }

  static void drawVerticalDimension(
    Canvas canvas, {
    required double x,
    required double y0,
    required double y1,
    required Offset Function(double x, double y) map,
    required String label,
    required Color color,
    double offsetPx = 28,
    bool left = true,
  }) {
    final a = map(x, y0);
    final b = map(x, y1);
    final delta = b - a;
    final len = delta.distance;
    if (len < 8) return;
    final dir = delta / len;
    final normal = Offset(-dir.dy, dir.dx) * (left ? -1 : 1);
    final dimA = a + normal * offsetPx;
    final dimB = b + normal * offsetPx;

    final ext = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    canvas.drawLine(a + normal * 4, dimA, ext);
    canvas.drawLine(b + normal * 4, dimB, ext);

    final line = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    canvas.drawLine(dimA, dimB, line);

    _drawArrow(canvas, dimA, dir, color);
    _drawArrow(canvas, dimB, -dir, color);

    final mid = (dimA + dimB) / 2;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, mid - Offset(tp.width + 4, tp.height / 2));
  }

  static void _drawArrow(Canvas canvas, Offset tip, Offset dir, Color color) {
    final paint = Paint()..color = color;
    final n = Offset(-dir.dy, dir.dx);
    const size = 5.0;
    final p1 = tip - dir * size + n * (size * 0.45);
    final p2 = tip - dir * size - n * (size * 0.45);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      paint,
    );
  }

  static String formatCm(double cm) {
    if ((cm - cm.round()).abs() < 0.05) return '${cm.round()}';
    return cm.toStringAsFixed(0);
  }

  static double segmentLengthCm(List<double> wall) =>
      math.sqrt(math.pow(wall[2] - wall[0], 2) + math.pow(wall[3] - wall[1], 2));
}
