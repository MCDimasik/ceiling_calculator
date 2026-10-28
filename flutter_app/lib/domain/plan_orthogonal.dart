import 'dart:math' as math;
import 'dart:ui';

/// Interior angle at [i] in degrees (0–180 for polygon corners).
double vertexInteriorAngleDeg(List<Offset> pts, int i) {
  if (pts.length < 3) return 0;
  final n = pts.length;
  final prev = pts[(i - 1 + n) % n];
  final cur = pts[i];
  final next = pts[(i + 1) % n];
  final ax = prev.dx - cur.dx;
  final ay = prev.dy - cur.dy;
  final bx = next.dx - cur.dx;
  final by = next.dy - cur.dy;
  final la = math.sqrt(ax * ax + ay * ay);
  final lb = math.sqrt(bx * bx + by * by);
  if (la < 1e-6 || lb < 1e-6) return 0;
  var cos = (ax * bx + ay * by) / (la * lb);
  cos = cos.clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

/// Display helper: treat near-90 as exact 90 to avoid 89.8 UI noise.
String formatVertexAngleLabel(double deg, {double eps = 0.25}) {
  if ((deg - 90).abs() <= eps) return '90°';
  if ((deg - deg.round()).abs() < 0.05) return '${deg.round()}°';
  return '${deg.toStringAsFixed(1)}°';
}

/// Exact axis-aligned corner candidates for vertex [i] (neighbors fixed).
List<Offset> orthoCornerCandidates(List<Offset> pts, int vertexIndex) {
  final n = pts.length;
  final i = vertexIndex % n;
  final prev = pts[(i - 1 + n) % n];
  final next = pts[(i + 1) % n];
  return [
    Offset(prev.dx, next.dy),
    Offset(next.dx, prev.dy),
  ];
}

/// Soft/hard snap so angle at [vertexIndex] → 90° via axis-aligned corner.
Offset softSnapVertexToRightAngle(
  List<Offset> pts,
  int vertexIndex, {
  double magnetDeg = 14,
  bool hard = false,
}) {
  if (pts.length < 3) return pts[vertexIndex];
  final n = pts.length;
  final i = vertexIndex % n;
  final cur = pts[i];
  final ang = vertexInteriorAngleDeg(pts, i);
  if ((ang - 90).abs() > magnetDeg) return cur;

  final prev = pts[(i - 1 + n) % n];
  final next = pts[(i + 1) % n];
  Offset best = cur;
  var bestScore = double.infinity;
  for (final c in orthoCornerCandidates(pts, i)) {
    if ((c - prev).distanceSquared < 1e-4 || (c - next).distanceSquared < 1e-4) {
      continue;
    }
    final trial = List<Offset>.from(pts)..[i] = c;
    final a = vertexInteriorAngleDeg(trial, i);
    final score = (a - 90).abs() + (c - cur).distance * 0.01;
    if (score < bestScore) {
      bestScore = score;
      best = c;
    }
  }
  if (hard || (ang - 90).abs() <= magnetDeg * 0.55) {
    return best;
  }
  final t = (1 - (ang - 90).abs() / magnetDeg).clamp(0.0, 1.0);
  return Offset.lerp(cur, best, 0.55 + 0.45 * t)!;
}

/// After moving [i], hard-snap that vertex only (neighbors stay fixed).
///
/// Moving neighbors after the fact was creating ~89.8° drift on the far corner.
/// Then run a few cleanup passes that only hard-snap vertices already near 90°.
List<Offset> snapVertexNeighborhoodToRightAngles(
  List<Offset> pts,
  int vertexIndex, {
  double magnetDeg = 16,
}) {
  if (pts.length < 3) return List<Offset>.from(pts);
  final out = List<Offset>.from(pts);
  final n = out.length;
  final i = vertexIndex % n;

  // 1) Dragged vertex → exact ortho corner relative to fixed neighbors.
  out[i] = softSnapVertexToRightAngle(out, i, magnetDeg: magnetDeg, hard: true);

  // 2) Cleanup: hard-snap any other near-90 vertex without soft lerp.
  //    Do not snap vertices far from 90° (would reshape freehand corners).
  for (var pass = 0; pass < 5; pass++) {
    var changed = false;
    for (var v = 0; v < n; v++) {
      final ang = vertexInteriorAngleDeg(out, v);
      if ((ang - 90).abs() > magnetDeg) continue;
      if ((ang - 90).abs() < 1e-9) continue;
      final snapped =
          softSnapVertexToRightAngle(out, v, magnetDeg: magnetDeg, hard: true);
      if ((snapped - out[v]).distanceSquared > 1e-10) {
        out[v] = snapped;
        changed = true;
      }
    }
    if (!changed) break;
  }
  return out;
}

/// Snap all vertices toward 90° (one soft pass).
List<Offset> orthogonalizePolygon(
  List<Offset> pts, {
  double magnetDeg = 18,
}) {
  if (pts.length < 3) return List<Offset>.from(pts);
  final out = List<Offset>.from(pts);
  for (var i = 0; i < out.length; i++) {
    out[i] = softSnapVertexToRightAngle(out, i, magnetDeg: magnetDeg);
  }
  return out;
}

/// Force near-orthogonality: project each edge to dominant axis from previous.
List<Offset> forceAxisAlignedPolygon(List<Offset> pts) {
  if (pts.length < 3) return List<Offset>.from(pts);
  final out = List<Offset>.from(pts);
  for (var i = 1; i < out.length; i++) {
    final prev = out[i - 1];
    final cur = out[i];
    final dx = cur.dx - prev.dx;
    final dy = cur.dy - prev.dy;
    if (dx.abs() >= dy.abs()) {
      out[i] = Offset(cur.dx, prev.dy);
    } else {
      out[i] = Offset(prev.dx, cur.dy);
    }
  }
  final first = out.first;
  final last = out.last;
  final dx = first.dx - last.dx;
  final dy = first.dy - last.dy;
  if (dx.abs() >= dy.abs()) {
    out[out.length - 1] = Offset(first.dx, last.dy);
  } else {
    out[out.length - 1] = Offset(last.dx, first.dy);
  }
  return out;
}
