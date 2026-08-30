import 'dart:collection';
import 'dart:math' as math;

import 'floor_covering.dart';

/// One discrete floor board/tile for painting & counting (like a grid cell).
class FloorBoard {
  const FloorBoard({
    required this.cxCm,
    required this.cyCm,
    required this.widthCm,
    required this.heightCm,
    this.rotationRad = 0,
    this.cut = false,
    this.cutWidthCm,
    this.cutHeightCm,
  });

  /// Center in room cm coordinates.
  final double cxCm;
  final double cyCm;
  final double widthCm;
  final double heightCm;
  final double rotationRad;
  final bool cut;

  /// Approximate remaining size inside the room (cm), for cut boards.
  final double? cutWidthCm;
  final double? cutHeightCm;

  String get cutLabel {
    final w = (cutWidthCm ?? widthCm).round();
    final h = (cutHeightCm ?? heightCm).round();
    return '$w×$h';
  }
}

class FloorLayoutSnapshot {
  const FloorLayoutSnapshot({
    required this.boards,
    required this.fullCount,
    required this.cutCount,
  });

  final List<FloorBoard> boards;
  final int fullCount;
  final int cutCount;
}

class _Lru<K, V> {
  _Lru(this.maxSize);
  final int maxSize;
  final LinkedHashMap<K, V> _map = LinkedHashMap();

  V? operator [](K key) {
    final v = _map.remove(key);
    if (v == null) return null;
    _map[key] = v;
    return v;
  }

  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }
}

/// Builds discrete boards for tile/laminate patterns (cached).
class FloorLayoutBuilder {
  FloorLayoutBuilder._();

  static final _cache = _Lru<String, FloorLayoutSnapshot>(24);

  static FloorLayoutSnapshot build({
    required List<List<double>> walls,
    required FloorCoveringKind covering,
    required FloorLayingPattern pattern,
    required double boardW,
    required double boardL,
    required double offsetX,
    required double offsetY,
    int rotationDeg = 0,
  }) {
    final key = _key(
      walls,
      covering,
      pattern,
      boardW,
      boardL,
      offsetX,
      offsetY,
      rotationDeg,
    );
    final hit = _cache[key];
    if (hit != null) return hit;

    final (minX0, maxX0, minY0, maxY0) = _bounds(walls);
    final cx = (minX0 + maxX0) / 2;
    final cy = (minY0 + maxY0) / 2;
    final rot = ((rotationDeg % 360) + 360) % 360;

    var poly = _polygon(walls);
    var minX = minX0;
    var maxX = maxX0;
    var minY = minY0;
    var maxY = maxY0;
    if (rot != 0) {
      final radInv = -rot * math.pi / 180;
      poly = _rotatePoly(poly, cx, cy, radInv);
      (minX, maxX, minY, maxY) = _boundsPoly(poly);
    }

    var w = boardW <= 0 ? 20.0 : boardW;
    var l = boardL <= 0 ? 120.0 : boardL;

    List<FloorBoard> boards;
    if (pattern == FloorLayingPattern.straight) {
      boards = _straight(minX, maxX, minY, maxY, w, l, offsetX, offsetY, poly);
    } else if (pattern == FloorLayingPattern.brick || pattern == FloorLayingPattern.third) {
      boards = _staggered(
        minX,
        maxX,
        minY,
        maxY,
        w,
        l,
        offsetX,
        offsetY,
        pattern.rowStaggerFraction,
        poly,
      );
    } else if (pattern == FloorLayingPattern.diagonal) {
      boards = _diagonal(minX, maxX, minY, maxY, w, l, offsetX, offsetY, poly);
    } else {
      boards = _straight(minX, maxX, minY, maxY, w, l, offsetX, offsetY, poly);
    }

    if (rot != 0) {
      final rad = rot * math.pi / 180;
      final cos = math.cos(rad);
      final sin = math.sin(rad);
      boards = [
        for (final b in boards)
          FloorBoard(
            cxCm: cx + (b.cxCm - cx) * cos - (b.cyCm - cy) * sin,
            cyCm: cy + (b.cxCm - cx) * sin + (b.cyCm - cy) * cos,
            widthCm: b.widthCm,
            heightCm: b.heightCm,
            rotationRad: b.rotationRad + rad,
            cut: b.cut,
            cutWidthCm: b.cutWidthCm,
            cutHeightCm: b.cutHeightCm,
          ),
      ];
    }

    var full = 0;
    var cut = 0;
    for (final b in boards) {
      if (b.cut) {
        cut++;
      } else {
        full++;
      }
    }
    final snap = FloorLayoutSnapshot(boards: boards, fullCount: full, cutCount: cut);
    _cache[key] = snap;
    return snap;
  }

  static String _key(
    List<List<double>> walls,
    FloorCoveringKind covering,
    FloorLayingPattern pattern,
    double boardW,
    double boardL,
    double ox,
    double oy,
    int rot,
  ) {
    final buf = StringBuffer()
      ..write(covering.id)
      ..write('|')
      ..write(pattern.id)
      ..write('|')
      ..write(boardW.toStringAsFixed(2))
      ..write('x')
      ..write(boardL.toStringAsFixed(2))
      ..write('|')
      ..write(ox.round())
      ..write(',')
      ..write(oy.round())
      ..write('|')
      ..write(rot);
    for (final w in walls) {
      buf
        ..write(';')
        ..write(w[0].round())
        ..write(',')
        ..write(w[1].round())
        ..write('-')
        ..write(w[2].round())
        ..write(',')
        ..write(w[3].round());
    }
    return buf.toString();
  }

  static (double, double, double, double) _bounds(List<List<double>> walls) {
    var minX = walls.first[0], maxX = walls.first[0];
    var minY = walls.first[1], maxY = walls.first[1];
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
    return (minX, maxX, minY, maxY);
  }

  static (double, double, double, double) _boundsPoly(List<(double, double)> poly) {
    var minX = poly.first.$1, maxX = poly.first.$1;
    var minY = poly.first.$2, maxY = poly.first.$2;
    for (final p in poly) {
      minX = math.min(minX, p.$1);
      maxX = math.max(maxX, p.$1);
      minY = math.min(minY, p.$2);
      maxY = math.max(maxY, p.$2);
    }
    return (minX, maxX, minY, maxY);
  }

  static List<(double, double)> _rotatePoly(
    List<(double, double)> pts,
    double cx,
    double cy,
    double rad,
  ) {
    final cos = math.cos(rad);
    final sin = math.sin(rad);
    return [
      for (final p in pts)
        (
          cx + (p.$1 - cx) * cos - (p.$2 - cy) * sin,
          cy + (p.$1 - cx) * sin + (p.$2 - cy) * cos,
        ),
    ];
  }

  static List<(double, double)> _polygon(List<List<double>> walls) {
    final pts = <(double, double)>[];
    for (final w in walls) {
      pts.add((w[0], w[1]));
    }
    final last = (walls.last[2], walls.last[3]);
    if (pts.isEmpty || pts.last != last) pts.add(last);
    if (pts.length >= 2 && pts.first == pts.last) pts.removeLast();
    return pts;
  }

  static bool _pointInPoly(double x, double y, List<(double, double)> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].$1, yi = poly[i].$2;
      final xj = poly[j].$1, yj = poly[j].$2;
      final hit = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
      if (hit) inside = !inside;
    }
    return inside;
  }

  /// Corners of oriented board; classify full/cut/outside by center + corners.
  static FloorBoard? _maybeBoard(
    double cx,
    double cy,
    double bw,
    double bh,
    double rot,
    List<(double, double)> poly,
  ) {
    final cos = math.cos(rot);
    final sin = math.sin(rot);
    final hx = bw / 2, hy = bh / 2;
    final corners = <(double, double)>[
      (cx + (-hx) * cos - (-hy) * sin, cy + (-hx) * sin + (-hy) * cos),
      (cx + (hx) * cos - (-hy) * sin, cy + (hx) * sin + (-hy) * cos),
      (cx + (hx) * cos - (hy) * sin, cy + (hx) * sin + (hy) * cos),
      (cx + (-hx) * cos - (hy) * sin, cy + (-hx) * sin + (hy) * cos),
    ];
    var inside = 0;
    for (final c in corners) {
      if (_pointInPoly(c.$1, c.$2, poly)) inside++;
    }
    final centerIn = _pointInPoly(cx, cy, poly);
    if (inside == 0 && !centerIn) return null;
    final cut = inside < 4;
    double? cutW;
    double? cutH;
    if (cut) {
      final size = _estimateCutSize(cx, cy, bw, bh, cos, sin, poly);
      if (size != null) {
        cutW = size.$1;
        cutH = size.$2;
      }
    }
    return FloorBoard(
      cxCm: cx,
      cyCm: cy,
      widthCm: bw,
      heightCm: bh,
      rotationRad: rot,
      cut: cut,
      cutWidthCm: cutW,
      cutHeightCm: cutH,
    );
  }

  /// Sample board local grid; bbox of samples inside room ≈ remaining piece.
  static (double, double)? _estimateCutSize(
    double cx,
    double cy,
    double bw,
    double bh,
    double cos,
    double sin,
    List<(double, double)> poly,
  ) {
    const n = 14;
    final hx = bw / 2, hy = bh / 2;
    double? minU, maxU, minV, maxV;
    for (var i = 0; i <= n; i++) {
      final u = -hx + (bw * i / n);
      for (var j = 0; j <= n; j++) {
        final v = -hy + (bh * j / n);
        final wx = cx + u * cos - v * sin;
        final wy = cy + u * sin + v * cos;
        if (!_pointInPoly(wx, wy, poly)) continue;
        minU = minU == null ? u : math.min(minU, u);
        maxU = maxU == null ? u : math.max(maxU, u);
        minV = minV == null ? v : math.min(minV, v);
        maxV = maxV == null ? v : math.max(maxV, v);
      }
    }
    if (minU == null || maxU == null || minV == null || maxV == null) return null;
    final w = (maxU - minU).clamp(0.0, bw);
    final h = (maxV - minV).clamp(0.0, bh);
    if (w < 0.5 || h < 0.5) return null;
    return (w, h);
  }

  static List<FloorBoard> _straight(
    double minX,
    double maxX,
    double minY,
    double maxY,
    double w,
    double l,
    double ox,
    double oy,
    List<(double, double)> poly,
  ) {
    final out = <FloorBoard>[];
    // board: length along X = l, width along Y = w
    final x0 = minX + ox;
    final y0 = minY + oy;
    final startCol = ((minX - l - x0) / l).floor() - 1;
    final endCol = ((maxX + l - x0) / l).ceil() + 1;
    final startRow = ((minY - w - y0) / w).floor() - 1;
    final endRow = ((maxY + w - y0) / w).ceil() + 1;
    for (var row = startRow; row <= endRow; row++) {
      for (var col = startCol; col <= endCol; col++) {
        final cx = x0 + col * l + l / 2;
        final cy = y0 + row * w + w / 2;
        final b = _maybeBoard(cx, cy, l, w, 0, poly);
        if (b != null) out.add(b);
      }
    }
    return out;
  }

  static List<FloorBoard> _staggered(
    double minX,
    double maxX,
    double minY,
    double maxY,
    double w,
    double l,
    double ox,
    double oy,
    double staggerFrac,
    List<(double, double)> poly,
  ) {
    final out = <FloorBoard>[];
    final y0 = minY + oy;
    final startRow = ((minY - w - y0) / w).floor() - 1;
    final endRow = ((maxY + w - y0) / w).ceil() + 1;
    for (var row = startRow; row <= endRow; row++) {
      final stagger = (row % 2 == 0) ? 0.0 : l * staggerFrac;
      final x0 = minX + ox + stagger;
      final startCol = ((minX - l - x0) / l).floor() - 1;
      final endCol = ((maxX + l - x0) / l).ceil() + 1;
      for (var col = startCol; col <= endCol; col++) {
        final cx = x0 + col * l + l / 2;
        final cy = y0 + row * w + w / 2;
        final b = _maybeBoard(cx, cy, l, w, 0, poly);
        if (b != null) out.add(b);
      }
    }
    return out;
  }

  static List<FloorBoard> _diagonal(
    double minX,
    double maxX,
    double minY,
    double maxY,
    double w,
    double l,
    double ox,
    double oy,
    List<(double, double)> poly,
  ) {
    const ang = math.pi / 4;
    final c = math.cos(ang);
    final s = math.sin(ang);
    final cx0 = (minX + maxX) / 2 + ox;
    final cy0 = (minY + maxY) / 2 + oy;
    final out = <FloorBoard>[];
    for (var i = -50; i <= 50; i++) {
      for (var j = -50; j <= 50; j++) {
        final u = i * l;
        final v = j * w;
        final cx = cx0 + u * c - v * s;
        final cy = cy0 + u * s + v * c;
        if (cx < minX - l || cx > maxX + l || cy < minY - l || cy > maxY + l) {
          continue;
        }
        final b = _maybeBoard(cx, cy, l, w, ang, poly);
        if (b != null) out.add(b);
      }
    }
    return out;
  }
}
