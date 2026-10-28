import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  Offset screenToWorld(Offset p) {
    final x = minX + (p.dx - ox) / scale;
    final y = maxY - (p.dy - oy) / scale;
    return Offset(x, y);
  }
}
