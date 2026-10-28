import 'dart:math' as math;

/// Nearest wall segment hit for 2D plan (cm).
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

List<List<double>> wallsFromPoints2d(List<(double, double)> points) {
  if (points.length < 3) return const [];
  final walls = <List<double>>[];
  for (var i = 0; i < points.length; i++) {
    final p1 = points[i];
    final p2 = points[(i + 1) % points.length];
    walls.add([p1.$1, p1.$2, p2.$1, p2.$2]);
  }
  return walls;
}

List<List<double>> normalizeWallsToOrigin(List<List<double>> walls) {
  if (walls.isEmpty) return walls;
  var minX = double.infinity;
  var minY = double.infinity;
  for (final w in walls) {
    minX = math.min(minX, math.min(w[0], w[2]));
    minY = math.min(minY, math.min(w[1], w[3]));
  }
  return walls
      .map(
        (w) => [
          w[0] - minX,
          w[1] - minY,
          w[2] - minX,
          w[3] - minY,
        ],
      )
      .toList();
}
