import 'dart:math' as math;
import 'dart:ui';

/// Footprint stats for a closed polygon in cm.
class PolygonFootprint {
  const PolygonFootprint({
    required this.areaM2,
    required this.perimeterM,
    required this.vertexCount,
  });

  final double areaM2;
  final double perimeterM;
  final int vertexCount;
}

/// Shoelace area from wall segments [[x1,y1,x2,y2],...] in cm.
PolygonFootprint footprintFromWalls(List<List<double>> walls) {
  if (walls.length < 3) {
    return const PolygonFootprint(areaM2: 0, perimeterM: 0, vertexCount: 0);
  }
  final verts = <Offset>[];
  for (final w in walls) {
    if (verts.isEmpty) {
      verts.add(Offset(w[0], w[1]));
    }
    verts.add(Offset(w[2], w[3]));
  }
  var area = 0.0;
  for (var i = 0; i < verts.length; i++) {
    final a = verts[i];
    final b = verts[(i + 1) % verts.length];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  area = area.abs() / 2;
  var perim = 0.0;
  for (final w in walls) {
    final dx = w[2] - w[0];
    final dy = w[3] - w[1];
    perim += math.sqrt(dx * dx + dy * dy);
  }
  return PolygonFootprint(
    areaM2: area / 10000,
    perimeterM: perim / 100,
    vertexCount: walls.length,
  );
}

/// Simple self-intersection check for polygon edges (excluding adjacent).
bool polygonHasSelfIntersection(List<Offset> points) {
  if (points.length < 4) return false;
  final n = points.length;
  for (var i = 0; i < n; i++) {
    final a1 = points[i];
    final a2 = points[(i + 1) % n];
    for (var j = i + 2; j < n; j++) {
      if (i == 0 && j == n - 1) continue;
      final b1 = points[j];
      final b2 = points[(j + 1) % n];
      if (_segmentsIntersect(a1, a2, b1, b2)) return true;
    }
  }
  return false;
}

bool _segmentsIntersect(Offset p1, Offset p2, Offset p3, Offset p4) {
  double cross(Offset a, Offset b, Offset c) =>
      (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  final d1 = cross(p3, p4, p1);
  final d2 = cross(p3, p4, p2);
  final d3 = cross(p1, p2, p3);
  final d4 = cross(p1, p2, p4);
  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    return true;
  }
  return false;
}

String? validatePhotoPlanPoints(List<Offset> imagePoints) {
  if (imagePoints.length < 3) return 'Нужно минимум 3 угла';
  if (polygonHasSelfIntersection(imagePoints)) {
    return 'Контур пересекается — проверьте порядок углов (по часовой)';
  }
  return null;
}
