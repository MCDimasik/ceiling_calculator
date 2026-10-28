import 'dart:math' as math;
import 'dart:ui';

/// Scale image polygon to real-world cm using one known wall length.
List<List<double>> wallsFromPhotoPlan({
  required List<Offset> imagePoints,
  required int wallIndex,
  required double wallLengthCm,
}) {
  if (imagePoints.length < 3) {
    throw ArgumentError('Нужно минимум 3 угла');
  }
  if (wallIndex < 0 || wallIndex >= imagePoints.length) {
    throw ArgumentError('Неверный индекс стены');
  }
  final a = imagePoints[wallIndex];
  final b = imagePoints[(wallIndex + 1) % imagePoints.length];
  final pxLen = _dist(a, b);
  if (pxLen < 2) throw ArgumentError('Стена на фото слишком короткая');
  final scale = wallLengthCm / pxLen;

  // Image Y grows down; room editor Y grows up — flip Y relative to first point.
  final origin = imagePoints[0];
  final cmPoints = <List<double>>[];
  for (final p in imagePoints) {
    cmPoints.add([
      (p.dx - origin.dx) * scale,
      -(p.dy - origin.dy) * scale,
    ]);
  }

  final walls = <List<double>>[];
  for (var i = 0; i < cmPoints.length; i++) {
    final p1 = cmPoints[i];
    final p2 = cmPoints[(i + 1) % cmPoints.length];
    walls.add([p1[0], p1[1], p2[0], p2[1]]);
  }
  return walls;
}

double _dist(Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  return math.sqrt(dx * dx + dy * dy);
}

double pixelWallLength(List<Offset> points, int wallIndex) {
  if (points.length < 2) return 0;
  final a = points[wallIndex % points.length];
  final b = points[(wallIndex + 1) % points.length];
  return _dist(a, b);
}
