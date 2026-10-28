import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

/// Straight wall segment in **image pixel** coordinates (same space as raster).
class PdfWallSegment {
  const PdfWallSegment(this.a, this.b);
  final Offset a;
  final Offset b;

  double get length => (b - a).distance;
}

/// Result of vector extraction from one PDF page.
class PdfVectorWalls {
  PdfVectorWalls({
    required this.segments,
    required this.pageSizePt,
    required this.imageSize,
    required this.source,
  }) : junctions = _clusterJunctions(segments, imageSize);

  factory PdfVectorWalls.fromSendable(Map<String, Object> raw) {
    final coords = (raw['coords'] as List).cast<double>();
    final segs = <PdfWallSegment>[];
    for (var i = 0; i + 3 < coords.length; i += 4) {
      segs.add(
        PdfWallSegment(
          Offset(coords[i], coords[i + 1]),
          Offset(coords[i + 2], coords[i + 3]),
        ),
      );
    }
    return PdfVectorWalls(
      segments: segs,
      pageSizePt: Size(
        (raw['pageW'] as num).toDouble(),
        (raw['pageH'] as num).toDouble(),
      ),
      imageSize: Size(
        (raw['imageW'] as num).toDouble(),
        (raw['imageH'] as num).toDouble(),
      ),
      source: raw['source'] as String? ?? 'content-stream',
    );
  }

  final List<PdfWallSegment> segments;
  final Size pageSizePt;
  final Size imageSize;
  final String source; // e.g. 'content-stream'

  /// Endpoints where ≥2 wall segments meet (image coords).
  final List<Offset> junctions;

  bool get isUseful => segments.length >= 8;

  /// Snap [p] to nearest wall junction within [tolImg] image pixels.
  Offset? snapToJunction(Offset p, {required double tolImg}) {
    Offset? best;
    var bestD = tolImg * tolImg;
    for (final j in junctions) {
      final d = (j - p).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = j;
      }
    }
    return best;
  }

  /// Room outline at [tap]: thick vector wall mask → flood → snap to junctions.
  ///
  /// CAD plans usually draw walls as *double* lines, so a pure face-walk on the
  /// line graph often finds the wall cavity, not the room. Raster fill is more
  /// robust; snapping restores sharp corners.
  List<Offset>? roomOutlineAt(Offset tap) {
    return _outlineByThickFlood(this, tap) ??
        _traceRoomFace(segments, tap, imageSize);
  }
}

List<Offset>? _outlineByThickFlood(PdfVectorWalls walls, Offset tap) {
  final img = walls.imageSize;
  final maxW = 900.0;
  final scale = img.width > maxW ? maxW / img.width : 1.0;
  final w = math.max(8, (img.width * scale).round());
  final h = math.max(8, (img.height * scale).round());
  final minLen = math.max(6.0, math.min(img.width, img.height) * 0.005);

  final mask = List<bool>.filled(w * h, false);
  void plot(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    mask[y * w + x] = true;
  }

  void thick(Offset a, Offset b, int rad) {
    final x0 = (a.dx * scale).round();
    final y0 = (a.dy * scale).round();
    final x1 = (b.dx * scale).round();
    final y1 = (b.dy * scale).round();
    final steps = math.max((a - b).distance * scale, 1).ceil();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = (x0 + (x1 - x0) * t).round();
      final y = (y0 + (y1 - y0) * t).round();
      for (var dy = -rad; dy <= rad; dy++) {
        for (var dx = -rad; dx <= rad; dx++) {
          if (dx * dx + dy * dy <= rad * rad + 1) plot(x + dx, y + dy);
        }
      }
    }
  }

  for (final s in walls.segments) {
    if (s.length < minLen) continue;
    thick(s.a, s.b, 2);
  }

  final tx = (tap.dx * scale).round().clamp(0, w - 1);
  final ty = (tap.dy * scale).round().clamp(0, h - 1);

  List<Offset>? tryFlood(List<bool> baseMask, int seal) {
    final wall = List<bool>.from(baseMask);
    _dilateBool(wall, w, h, seal);
    _erodeBool(wall, w, h, math.max(1, seal - 1));

    var sx = tx;
    var sy = ty;
    if (wall[sy * w + sx]) {
      final alt = _nearestFalse(wall, w, h, tx, ty, 40);
      if (alt == null) return null;
      sx = alt.$1;
      sy = alt.$2;
    }

    final filled = List<bool>.filled(w * h, false);
    final stack = <int>[sy * w + sx];
    filled[sy * w + sx] = true;
    var count = 0;
    var border = 0;
    final maxFill = (w * h * 0.42).round();
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      count++;
      if (count > maxFill) return null;
      final x = i % w;
      final y = i ~/ w;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) border++;
      for (final (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final j = ny * w + nx;
        if (filled[j] || wall[j]) continue;
        filled[j] = true;
        stack.add(j);
      }
    }
    // Leak into page margin → try stronger door seal.
    if (border > math.max(20, (w + h) ~/ 25)) return null;
    if (count < 60) return null;

    final boundary = _mooreBoundary(filled, w, h);
    if (boundary.length < 4) return null;

    var eps = math.max(2.0, math.min(w, h) / 50.0);
    var simplified = _dp(boundary, eps);
    while (simplified.length > 24 && eps < 18) {
      eps += 1.2;
      simplified = _dp(boundary, eps);
    }
    if (simplified.length < 3) return null;

    final toFull = 1 / scale;
    final poly = <Offset>[
      for (final p in simplified) Offset(p.dx * toFull, p.dy * toFull),
    ];
    // Snap only when a junction is near *and* preserves local axes with
    // neighbours — loose snap looked like "random points".
    final snapTol = math.max(3.0, math.min(img.width, img.height) * 0.0035);
    final axisTol = math.max(2.0, math.min(img.width, img.height) * 0.002);
    for (var i = 0; i < poly.length; i++) {
      final prev = poly[(i - 1 + poly.length) % poly.length];
      final next = poly[(i + 1) % poly.length];
      final p = poly[i];
      Offset? best;
      var bestD = snapTol * snapTol;
      for (final j in walls.junctions) {
        final d = (j - p).distanceSquared;
        if (d >= bestD) continue;
        final axisOk = ((j.dx - prev.dx).abs() <= axisTol ||
                (j.dy - prev.dy).abs() <= axisTol) &&
            ((j.dx - next.dx).abs() <= axisTol ||
                (j.dy - next.dy).abs() <= axisTol);
        // If the contour itself isn't ortho yet, still allow a close snap.
        final softOk = (j - p).distance <= snapTol * 0.55;
        if (!axisOk && !softOk) continue;
        bestD = d;
        best = j;
      }
      if (best != null) poly[i] = best;
    }
    return poly;
  }

  for (final seal in const [2, 4, 6, 9]) {
    final poly = tryFlood(mask, seal);
    if (poly != null) return poly;
  }
  return null;
}

void _dilateBool(List<bool> m, int w, int h, int passes) {
  for (var p = 0; p < passes; p++) {
    final next = List<bool>.from(m);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        if (m[y * w + x]) continue;
        if (m[y * w + x - 1] ||
            m[y * w + x + 1] ||
            m[(y - 1) * w + x] ||
            m[(y + 1) * w + x]) {
          next[y * w + x] = true;
        }
      }
    }
    for (var i = 0; i < m.length; i++) {
      m[i] = next[i];
    }
  }
}

void _erodeBool(List<bool> m, int w, int h, int passes) {
  for (var p = 0; p < passes; p++) {
    final next = List<bool>.from(m);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        if (!m[y * w + x]) continue;
        if (!m[y * w + x - 1] ||
            !m[y * w + x + 1] ||
            !m[(y - 1) * w + x] ||
            !m[(y + 1) * w + x]) {
          next[y * w + x] = false;
        }
      }
    }
    for (var i = 0; i < m.length; i++) {
      m[i] = next[i];
    }
  }
}

(int, int)? _nearestFalse(List<bool> m, int w, int h, int cx, int cy, int r) {
  for (var d = 1; d <= r; d++) {
    for (var dy = -d; dy <= d; dy++) {
      for (var dx = -d; dx <= d; dx++) {
        if (dx.abs() != d && dy.abs() != d) continue;
        final x = cx + dx;
        final y = cy + dy;
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        if (!m[y * w + x]) return (x, y);
      }
    }
  }
  return null;
}

List<Offset> _mooreBoundary(List<bool> inside, int w, int h) {
  bool inb(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && inside[y * w + x];
  var sx = -1, sy = -1;
  for (var y = 0; y < h && sx < 0; y++) {
    for (var x = 0; x < w; x++) {
      if (inb(x, y) && !inb(x, y - 1)) {
        sx = x;
        sy = y;
        break;
      }
    }
  }
  if (sx < 0) return const [];
  const vx = [0, 1, 0, -1];
  const vy = [-1, 0, 1, 0];
  var x = sx, y = sy, back = 0;
  final path = <Offset>[Offset(x.toDouble(), y.toDouble())];
  for (var guard = 0; guard < w * h * 8; guard++) {
    var moved = false;
    for (var t = 0; t < 4; t++) {
      final d = (back + 1 + t) % 4;
      final nx = x + vx[d];
      final ny = y + vy[d];
      if (!inb(nx, ny)) continue;
      x = nx;
      y = ny;
      back = (d + 2) % 4;
      path.add(Offset(x.toDouble(), y.toDouble()));
      moved = true;
      break;
    }
    if (!moved) break;
    if (x == sx && y == sy && path.length > 3) break;
  }
  return path;
}

List<Offset> _dp(List<Offset> pts, double eps) {
  if (pts.length < 3) return pts;
  var maxD = 0.0;
  var idx = 0;
  final a = pts.first;
  final b = pts.last;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _perp(pts[i], a, b);
    if (d > maxD) {
      maxD = d;
      idx = i;
    }
  }
  if (maxD > eps) {
    final left = _dp(pts.sublist(0, idx + 1), eps);
    final right = _dp(pts.sublist(idx), eps);
    return [...left.sublist(0, left.length - 1), ...right];
  }
  return [a, b];
}

double _perp(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1e-9) return (p - a).distance;
  final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
  final proj = Offset(a.dx + t * dx, a.dy + t * dy);
  return (p - proj).distance;
}

List<Offset> _clusterJunctions(List<PdfWallSegment> segments, Size image) {
  if (segments.isEmpty) return const [];
  final eps = math.max(3.0, math.min(image.width, image.height) * 0.0015);
  // Only longer strokes — skip glyph / hatch noise.
  final minLen = math.max(8.0, math.min(image.width, image.height) * 0.006);
  final pts = <Offset>[];
  for (final s in segments) {
    if (s.length < minLen) continue;
    pts.add(s.a);
    pts.add(s.b);
  }
  if (pts.isEmpty) return const [];

  final clusters = <Offset>[];
  final counts = <int>[];
  for (final p in pts) {
    var found = -1;
    for (var i = 0; i < clusters.length; i++) {
      if ((clusters[i] - p).distanceSquared <= eps * eps) {
        found = i;
        break;
      }
    }
    if (found < 0) {
      clusters.add(p);
      counts.add(1);
    } else {
      final n = counts[found];
      clusters[found] = Offset(
        (clusters[found].dx * n + p.dx) / (n + 1),
        (clusters[found].dy * n + p.dy) / (n + 1),
      );
      counts[found] = n + 1;
    }
  }
  // Junction = shared by ≥2 endpoints (degree hint via visit count).
  final out = <Offset>[];
  for (var i = 0; i < clusters.length; i++) {
    if (counts[i] >= 2) out.add(clusters[i]);
  }
  return out;
}

List<Offset>? _traceRoomFace(
  List<PdfWallSegment> segments,
  Offset tap,
  Size page,
) {
  final minLen = math.max(10.0, math.min(page.width, page.height) * 0.008);
  final eps = math.max(4.0, math.min(page.width, page.height) * 0.002);
  final wallSegs = [
    for (final s in segments)
      if (s.length >= minLen) s,
  ];
  if (wallSegs.length < 3) return null;

  // Cluster endpoints → node ids.
  final nodes = <Offset>[];
  int nodeOf(Offset p) {
    for (var i = 0; i < nodes.length; i++) {
      if ((nodes[i] - p).distanceSquared <= eps * eps) return i;
    }
    nodes.add(p);
    return nodes.length - 1;
  }

  final edges = <(int, int)>{};
  for (final s in wallSegs) {
    final a = nodeOf(s.a);
    final b = nodeOf(s.b);
    if (a == b) continue;
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    edges.add((lo, hi));
  }
  if (edges.length < 3) return null;

  final adj = List.generate(nodes.length, (_) => <int>[]);
  for (final (a, b) in edges) {
    adj[a].add(b);
    adj[b].add(a);
  }

  // Closest edge to tap.
  var bestDist = double.infinity;
  var bestA = -1;
  var bestB = -1;
  for (final (a, b) in edges) {
    final d = _distPointToSeg(tap, nodes[a], nodes[b]);
    if (d < bestDist) {
      bestDist = d;
      bestA = a;
      bestB = b;
    }
  }
  if (bestA < 0) return null;

  // Orient so tap is to the left of A→B (interior for CCW rooms).
  Offset dir(int from, int to) => nodes[to] - nodes[from];
  double cross(Offset u, Offset v) => u.dx * v.dy - u.dy * v.dx;
  var a0 = bestA;
  var b0 = bestB;
  if (cross(dir(a0, b0), tap - nodes[a0]) < 0) {
    final t = a0;
    a0 = b0;
    b0 = t;
  }

  List<Offset>? walk(int startPrev, int startCur) {
    final pathIdx = <int>[startPrev, startCur];
    var prev = startPrev;
    var cur = startCur;
    for (var guard = 0; guard < nodes.length * 4; guard++) {
      final next = _leftMostNext(adj, nodes, cur, prev);
      if (next == null) return null;
      if (next == pathIdx.first && pathIdx.length >= 3) {
        return [for (final i in pathIdx) nodes[i]];
      }
      if (pathIdx.contains(next) && next != pathIdx.first) return null;
      pathIdx.add(next);
      prev = cur;
      cur = next;
    }
    return null;
  }

  var face = walk(a0, b0);
  // Try the other side if needed.
  if (face == null || !_polygonContains(face, tap) || _polyArea(face) < 100) {
    face = walk(b0, a0);
  }
  if (face == null || face.length < 3) return null;
  if (!_polygonContains(face, tap)) return null;
  final area = _polyArea(face);
  final pageArea = page.width * page.height;
  if (area < pageArea * 0.0002 || area > pageArea * 0.45) return null;
  return face;
}

int? _leftMostNext(
  List<List<int>> adj,
  List<Offset> nodes,
  int cur,
  int prev,
) {
  final neighbors = List<int>.from(adj[cur]);
  if (neighbors.isEmpty) return null;
  neighbors.sort((a, b) {
    final aa = math.atan2(
      nodes[a].dy - nodes[cur].dy,
      nodes[a].dx - nodes[cur].dx,
    );
    final bb = math.atan2(
      nodes[b].dy - nodes[cur].dy,
      nodes[b].dx - nodes[cur].dx,
    );
    return aa.compareTo(bb);
  });
  final idx = neighbors.indexOf(prev);
  if (idx < 0) return neighbors.first;
  // Arrive from prev: next CCW edge is the previous entry in atan2 order.
  return neighbors[(idx - 1 + neighbors.length) % neighbors.length];
}

double _distPointToSeg(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  if (len2 < 1e-9) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
  t = t.clamp(0.0, 1.0);
  final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (p - proj).distance;
}

double _polyArea(List<Offset> poly) {
  var a = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final p = poly[i];
    final q = poly[(i + 1) % poly.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a.abs() * 0.5;
}

bool _polygonContains(List<Offset> poly, Offset p) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final pi = poly[i];
    final pj = poly[j];
    final intersect = ((pi.dy > p.dy) != (pj.dy > p.dy)) &&
        (p.dx <
            (pj.dx - pi.dx) * (p.dy - pi.dy) / ((pj.dy - pi.dy) + 1e-12) +
                pi.dx);
    if (intersect) inside = !inside;
  }
  return inside;
}

/// Extract stroked/filled path edges from a PDF page content stream.
///
/// Architectural plans usually draw walls as `m`/`l`/`re` paths — not as a
/// JPEG. We decode Flate streams, interpret a subset of PDF graphics ops, and
/// map points from PDF user space → raster pixels using [imageSize].
class PdfVectorWallExtractor {
  PdfVectorWallExtractor._();

  /// [pageIndex] is 0-based. [imageSize] must match the raster of that page.
  static PdfVectorWalls? extract({
    required Uint8List pdfBytes,
    required int pageIndex,
    required Size imageSize,
  }) {
    final raw = extractSendable(
      pdfBytes: pdfBytes,
      pageIndex: pageIndex,
      imageWidth: imageSize.width,
      imageHeight: imageSize.height,
    );
    return raw == null ? null : PdfVectorWalls.fromSendable(raw);
  }

  /// Isolate-safe extract: plain lists/numbers only (no [Offset]/[Size]).
  static Map<String, Object>? extractSendable({
    required Uint8List pdfBytes,
    required int pageIndex,
    required double imageWidth,
    required double imageHeight,
  }) {
    try {
      final doc = _PdfDoc.parse(pdfBytes);
      if (doc.pages.isEmpty) return null;
      final idx = pageIndex.clamp(0, doc.pages.length - 1);
      final page = doc.pages[idx];
      final content = page.concatContent(doc);
      if (content == null || content.isEmpty) return null;

      final segsPt = _interpretPaths(content);
      if (segsPt.isEmpty) return null;

      final pageW = page.mediaBox.width;
      final pageH = page.mediaBox.height;
      if (pageW < 1 || pageH < 1) return null;

      // PDF y grows up; image y grows down.
      final sx = imageWidth / pageW;
      final sy = imageHeight / pageH;
      final minLenImg =
          math.max(6.0, math.min(imageWidth, imageHeight) * 0.004);

      final coords = <double>[];
      final lengths = <double>[];
      for (final s in segsPt) {
        final ax = s.a.dx * sx;
        final ay = (pageH - s.a.dy) * sy;
        final bx = s.b.dx * sx;
        final by = (pageH - s.b.dy) * sy;
        final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
        if (len < minLenImg) continue;
        coords.addAll([ax, ay, bx, by]);
        lengths.add(len);
      }
      if (coords.isEmpty) return null;

      // Cap for memory on huge sheets — keep longest segments.
      if (lengths.length > 20000) {
        final order = List.generate(lengths.length, (i) => i)
          ..sort((a, b) => lengths[b].compareTo(lengths[a]));
        final capped = <double>[];
        for (var k = 0; k < 20000; k++) {
          final i = order[k] * 4;
          capped.addAll(coords.sublist(i, i + 4));
        }
        coords
          ..clear()
          ..addAll(capped);
      }

      return {
        'coords': coords,
        'pageW': pageW,
        'pageH': pageH,
        'imageW': imageWidth,
        'imageH': imageHeight,
        'source': 'content-stream',
      };
    } catch (_) {
      return null;
    }
  }
}

class _Seg {
  _Seg(this.a, this.b);
  final Offset a;
  final Offset b;
}

List<_Seg> _interpretPaths(String content) {
  final tokens = _tokenize(content);
  final segs = <_Seg>[];
  final ctmStack = <_Matrix>[];
  var ctm = _Matrix.identity();
  final path = <Offset>[];
  var subStart = Offset.zero;
  var cur = Offset.zero;
  var inText = false;

  void emitStroke() {
    if (path.length < 2) return;
    for (var i = 1; i < path.length; i++) {
      segs.add(_Seg(path[i - 1], path[i]));
    }
  }

  void clearPath() {
    path.clear();
  }

  double numAt(int i) => double.tryParse(tokens[i]) ?? 0;

  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == 'BT') {
      inText = true;
      continue;
    }
    if (t == 'ET') {
      inText = false;
      continue;
    }
    if (inText) continue;

    switch (t) {
      case 'q':
        ctmStack.add(ctm);
        break;
      case 'Q':
        if (ctmStack.isNotEmpty) ctm = ctmStack.removeLast();
        break;
      case 'cm':
        if (i >= 6) {
          final m = _Matrix(
            numAt(i - 6),
            numAt(i - 5),
            numAt(i - 4),
            numAt(i - 3),
            numAt(i - 2),
            numAt(i - 1),
          );
          ctm = ctm.multiplied(m);
        }
        break;
      case 'm':
        if (i >= 2) {
          cur = ctm.map(Offset(numAt(i - 2), numAt(i - 1)));
          subStart = cur;
          path
            ..clear()
            ..add(cur);
        }
        break;
      case 'l':
        if (i >= 2) {
          cur = ctm.map(Offset(numAt(i - 2), numAt(i - 1)));
          path.add(cur);
        }
        break;
      case 'h':
        path.add(subStart);
        cur = subStart;
        break;
      case 're':
        if (i >= 4) {
          final x = numAt(i - 4);
          final y = numAt(i - 3);
          final w = numAt(i - 2);
          final h = numAt(i - 1);
          final p0 = ctm.map(Offset(x, y));
          final p1 = ctm.map(Offset(x + w, y));
          final p2 = ctm.map(Offset(x + w, y + h));
          final p3 = ctm.map(Offset(x, y + h));
          path
            ..clear()
            ..addAll([p0, p1, p2, p3, p0]);
          cur = p0;
          subStart = p0;
        }
        break;
      case 'c':
        if (i >= 6) {
          // Approximate cubic with end-point only + one mid sample.
          final x1 = numAt(i - 6);
          final y1 = numAt(i - 5);
          final x2 = numAt(i - 4);
          final y2 = numAt(i - 3);
          final x3 = numAt(i - 2);
          final y3 = numAt(i - 1);
          final p1 = ctm.map(Offset(x1, y1));
          final p2 = ctm.map(Offset(x2, y2));
          final p3 = ctm.map(Offset(x3, y3));
          path.add(Offset((cur.dx + p1.dx + p2.dx + p3.dx) / 4,
              (cur.dy + p1.dy + p2.dy + p3.dy) / 4));
          path.add(p3);
          cur = p3;
        }
        break;
      case 'v':
      case 'y':
        if (i >= 4) {
          final p = ctm.map(Offset(numAt(i - 2), numAt(i - 1)));
          path.add(p);
          cur = p;
        }
        break;
      case 'S':
      case 's':
        if (t == 's') path.add(subStart);
        emitStroke();
        clearPath();
        break;
      case 'b':
      case 'b*':
      case 'B':
      case 'B*':
      case 'f':
      case 'f*':
      case 'F':
        // Filled paths (wall slabs as rectangles) — keep edges.
        if (t.startsWith('b')) path.add(subStart);
        emitStroke();
        clearPath();
        break;
      case 'n':
        clearPath();
        break;
    }
  }
  return segs;
}

List<String> _tokenize(String content) {
  final out = <String>[];
  final buf = StringBuffer();
  var i = 0;
  void flush() {
    if (buf.isEmpty) return;
    out.add(buf.toString());
    buf.clear();
  }

  while (i < content.length) {
    final c = content.codeUnitAt(i);
    if (c == 37) {
      // % comment
      flush();
      while (i < content.length &&
          content.codeUnitAt(i) != 10 &&
          content.codeUnitAt(i) != 13) {
        i++;
      }
      continue;
    }
    if (c <= 32) {
      flush();
      i++;
      continue;
    }
    if (c == 40) {
      // (string
      flush();
      i++;
      while (i < content.length) {
        final ch = content.codeUnitAt(i);
        if (ch == 92) {
          i += 2;
          continue;
        }
        if (ch == 41) {
          i++;
          break;
        }
        i++;
      }
      continue;
    }
    if (c == 60) {
      flush();
      if (i + 1 < content.length && content.codeUnitAt(i + 1) == 60) {
        out.add('<<');
        i += 2;
        continue;
      }
      // <hex>
      i++;
      while (i < content.length && content.codeUnitAt(i) != 62) {
        i++;
      }
      if (i < content.length) i++;
      continue;
    }
    if (c == 62) {
      flush();
      if (i + 1 < content.length && content.codeUnitAt(i + 1) == 62) {
        out.add('>>');
        i += 2;
        continue;
      }
      i++;
      continue;
    }
    if (c == 91 || c == 93 || c == 123 || c == 125) {
      flush();
      out.add(String.fromCharCode(c));
      i++;
      continue;
    }
    if (c == 47) {
      flush();
      buf.write('/');
      i++;
      while (i < content.length) {
        final ch = content.codeUnitAt(i);
        if (ch <= 32 ||
            ch == 40 ||
            ch == 41 ||
            ch == 60 ||
            ch == 62 ||
            ch == 91 ||
            ch == 93 ||
            ch == 123 ||
            ch == 125 ||
            ch == 47 ||
            ch == 37) {
          break;
        }
        buf.writeCharCode(ch);
        i++;
      }
      flush();
      continue;
    }
    buf.writeCharCode(c);
    i++;
  }
  flush();
  return out;
}

class _Matrix {
  const _Matrix(this.a, this.b, this.c, this.d, this.e, this.f);
  final double a, b, c, d, e, f;

  static _Matrix identity() => const _Matrix(1, 0, 0, 1, 0, 0);

  _Matrix multiplied(_Matrix m) {
    return _Matrix(
      a * m.a + b * m.c,
      a * m.b + b * m.d,
      c * m.a + d * m.c,
      c * m.b + d * m.d,
      e * m.a + f * m.c + m.e,
      e * m.b + f * m.d + m.f,
    );
  }

  Offset map(Offset p) => Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);
}

class _PdfRect {
  const _PdfRect(this.x0, this.y0, this.x1, this.y1);
  final double x0, y0, x1, y1;
  double get width => (x1 - x0).abs();
  double get height => (y1 - y0).abs();
}

class _PdfPage {
  _PdfPage({required this.mediaBox, required this.contentRefs});
  final _PdfRect mediaBox;
  final List<int> contentRefs;

  String? concatContent(_PdfDoc doc) {
    final buf = StringBuffer();
    for (final id in contentRefs) {
      final s = doc.decodedStream(id);
      if (s != null) buf.write(s);
    }
    final text = buf.toString();
    return text.isEmpty ? null : text;
  }
}

class _PdfDoc {
  _PdfDoc(this.objects, this.pages);
  final Map<int, _PdfObject> objects;
  final List<_PdfPage> pages;

  static _PdfDoc parse(Uint8List bytes) {
    // ASCII mirror for searching keywords; binary streams read from [bytes].
    final ascii = String.fromCharCodes(
      bytes.map((b) => b < 128 ? b : 32),
    );
    final objects = <int, _PdfObject>{};
    final objRe = RegExp(r'(\d+)\s+(\d+)\s+obj');
    final matches = objRe.allMatches(ascii).toList();
    for (var mi = 0; mi < matches.length; mi++) {
      final m = matches[mi];
      final id = int.parse(m.group(1)!);
      final start = m.end;
      final end = mi + 1 < matches.length ? matches[mi + 1].start : ascii.length;
      final slice = ascii.substring(start, end);
      final endObj = slice.indexOf('endobj');
      final bodyAscii = endObj >= 0 ? slice.substring(0, endObj) : slice;
      objects[id] = _PdfObject.parseFromFile(
        id: id,
        dictAndMaybeStreamAscii: bodyAscii,
        fileBytes: bytes,
        objBodyFileStart: start,
      );
    }

    final pageById = <int, _PdfPage>{};
    for (final obj in objects.values) {
      final dict = obj.dictText;
      if (!RegExp(r'/Type\s*/Page(?!s)').hasMatch(dict)) continue;
      pageById[obj.id] = _PdfPage(
        mediaBox: _parseMediaBox(dict, objects) ??
            const _PdfRect(0, 0, 595, 842),
        contentRefs: _parseContentsRefs(dict),
      );
    }

    final pages = <_PdfPage>[];
    final rootKids = _findPageIdsInTree(objects);
    if (rootKids.isNotEmpty) {
      for (final id in rootKids) {
        final p = pageById[id];
        if (p != null) pages.add(p);
      }
    }
    if (pages.isEmpty) {
      pages.addAll(pageById.values);
    }
    return _PdfDoc(objects, pages);
  }

  String? decodedStream(int id) {
    final obj = objects[id];
    if (obj == null) return null;
    return obj.decodedStream();
  }
}

List<int> _findPageIdsInTree(Map<int, _PdfObject> objects) {
  int? catalogPages;
  for (final obj in objects.values) {
    if (RegExp(r'/Type\s*/Catalog').hasMatch(obj.dictText)) {
      final m = RegExp(r'/Pages\s+(\d+)\s+\d+\s+R').firstMatch(obj.dictText);
      if (m != null) catalogPages = int.parse(m.group(1)!);
      break;
    }
  }
  if (catalogPages == null) return const [];
  final out = <int>[];
  void walk(int id, int depth) {
    if (depth > 32) return;
    final obj = objects[id];
    if (obj == null) return;
    final dict = obj.dictText;
    if (RegExp(r'/Type\s*/Page(?!s)').hasMatch(dict)) {
      out.add(id);
      return;
    }
    final kids = RegExp(r'/Kids\s*\[(.*?)\]', dotAll: true).firstMatch(dict);
    if (kids == null) return;
    for (final m in RegExp(r'(\d+)\s+\d+\s+R').allMatches(kids.group(1)!)) {
      walk(int.parse(m.group(1)!), depth + 1);
    }
  }

  walk(catalogPages, 0);
  return out;
}

class _PdfObject {
  _PdfObject({
    required this.id,
    required this.dictText,
    this.streamBytes,
  });

  final int id;
  final String dictText;
  final Uint8List? streamBytes;

  static _PdfObject parseFromFile({
    required int id,
    required String dictAndMaybeStreamAscii,
    required Uint8List fileBytes,
    required int objBodyFileStart,
  }) {
    final streamIdx = dictAndMaybeStreamAscii.indexOf('stream');
    if (streamIdx < 0) {
      return _PdfObject(id: id, dictText: dictAndMaybeStreamAscii);
    }
    final dict = dictAndMaybeStreamAscii.substring(0, streamIdx);
    var dataStart = objBodyFileStart + streamIdx + 6;
    if (dataStart < fileBytes.length && fileBytes[dataStart] == 13) dataStart++;
    if (dataStart < fileBytes.length && fileBytes[dataStart] == 10) dataStart++;
    final lenMatch = RegExp(r'/Length\s+(\d+)').firstMatch(dict);
    if (lenMatch != null) {
      final len = int.parse(lenMatch.group(1)!);
      final end = math.min(fileBytes.length, dataStart + len);
      if (end > dataStart) {
        return _PdfObject(
          id: id,
          dictText: dict,
          streamBytes: fileBytes.sublist(dataStart, end),
        );
      }
    }
    // Fallback: until endstream keyword in ascii map.
    final endRel = dictAndMaybeStreamAscii.indexOf('endstream', streamIdx + 6);
    if (endRel < 0) return _PdfObject(id: id, dictText: dict);
    var contentEnd = objBodyFileStart + endRel;
    if (contentEnd > 0 && fileBytes[contentEnd - 1] == 10) contentEnd--;
    if (contentEnd > 0 && fileBytes[contentEnd - 1] == 13) contentEnd--;
    if (contentEnd <= dataStart) return _PdfObject(id: id, dictText: dict);
    return _PdfObject(
      id: id,
      dictText: dict,
      streamBytes: fileBytes.sublist(dataStart, contentEnd),
    );
  }

  String? decodedStream() {
    final raw = streamBytes;
    if (raw == null || raw.isEmpty) return null;
    final flate = dictText.contains('/FlateDecode') ||
        dictText.contains('/Fl');
    if (!flate) {
      return String.fromCharCodes(raw);
    }
    try {
      final decoded = ZLibCodec(raw: true).decode(raw);
      return String.fromCharCodes(decoded);
    } catch (_) {
      try {
        final decoded = ZLibCodec().decode(raw);
        return String.fromCharCodes(decoded);
      } catch (_) {
        return null;
      }
    }
  }
}

_PdfRect? _parseMediaBox(String dict, Map<int, _PdfObject> objects) {
  final direct = RegExp(
    r'/MediaBox\s*\[\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*\]',
  ).firstMatch(dict);
  if (direct != null) {
    return _PdfRect(
      double.parse(direct.group(1)!),
      double.parse(direct.group(2)!),
      double.parse(direct.group(3)!),
      double.parse(direct.group(4)!),
    );
  }
  final ref = RegExp(r'/MediaBox\s+(\d+)\s+\d+\s+R').firstMatch(dict);
  if (ref != null) {
    final obj = objects[int.parse(ref.group(1)!)];
    if (obj != null) {
      final m = RegExp(
        r'\[\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*\]',
      ).firstMatch(obj.dictText);
      if (m != null) {
        return _PdfRect(
          double.parse(m.group(1)!),
          double.parse(m.group(2)!),
          double.parse(m.group(3)!),
          double.parse(m.group(4)!),
        );
      }
    }
  }
  return null;
}

List<int> _parseContentsRefs(String dict) {
  final arr = RegExp(r'/Contents\s*\[(.*?)\]', dotAll: true).firstMatch(dict);
  if (arr != null) {
    return RegExp(r'(\d+)\s+\d+\s+R')
        .allMatches(arr.group(1)!)
        .map((m) => int.parse(m.group(1)!))
        .toList();
  }
  final single = RegExp(r'/Contents\s+(\d+)\s+\d+\s+R').firstMatch(dict);
  if (single != null) return [int.parse(single.group(1)!)];
  return const [];
}
