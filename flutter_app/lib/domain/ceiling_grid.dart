import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Type of a cell relative to the room polygon.
enum CellKind { outside, full, cut }

/// One configurable tile cell of the ceiling grid.
@immutable
class GridCell {
  const GridCell({
    required this.col,
    required this.row,
    required this.xCm,
    required this.yCm,
    required this.kind,
    this.cutXCm = 0,
    this.cutYCm = 0,
    this.hasLight = false,
  });

  final int col;
  final int row;
  final double xCm;
  final double yCm;
  final CellKind kind;
  final double cutXCm;
  final double cutYCm;
  final bool hasLight;

  String get id => '$col:$row';

  bool get acceptsLight {
    if (kind == CellKind.outside) return false;
    if (kind == CellKind.cut && (cutXCm < 1.0 || cutYCm < 1.0)) return false;
    return true;
  }

  GridCell copyWith({
    CellKind? kind,
    double? cutXCm,
    double? cutYCm,
    bool? hasLight,
  }) {
    return GridCell(
      col: col,
      row: row,
      xCm: xCm,
      yCm: yCm,
      kind: kind ?? this.kind,
      cutXCm: cutXCm ?? this.cutXCm,
      cutYCm: cutYCm ?? this.cutYCm,
      hasLight: hasLight ?? this.hasLight,
    );
  }
}

class _GridRebuildSnapshot {
  const _GridRebuildSnapshot({
    required this.cells,
    required this.vLines,
    required this.hLines,
    required this.full,
    required this.cut,
  });

  final List<GridCell> cells;
  final List<(double, double, double, double)> vLines;
  final List<(double, double, double, double)> hLines;
  final int full;
  final int cut;
}

class _LruCache<K, V> {
  _LruCache(this.maxSize);

  final int maxSize;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  V? operator [](K key) {
    final value = _map.remove(key);
    if (value == null) return null;
    _map[key] = value;
    return value;
  }

  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }

  void clear() => _map.clear();

  int get length => _map.length;
}

/// Unified ceiling/floor grid — tile analysis ported from Kivy `CeilingLayout`.
/// Supports rectangular cells via [cellWidthCm] / [cellHeightCm].
class CeilingGrid {
  CeilingGrid({
    double cellSizeCm = 60,
    double? cellWidthCm,
    double? cellHeightCm,
    this.offsetXCm = 0,
    this.offsetYCm = 0,
    this.geomEpsCm = 0.05,
  })  : cellWidthCm = cellWidthCm ?? cellSizeCm,
        cellHeightCm = cellHeightCm ?? cellSizeCm;

  static const int cacheMaxSize = 32;
  static final _LruCache<String, _GridRebuildSnapshot> _rebuildCache =
      _LruCache(cacheMaxSize);

  @visibleForTesting
  static void clearRebuildCache() => _rebuildCache.clear();

  @visibleForTesting
  static int get rebuildCacheLength => _rebuildCache.length;

  double cellWidthCm;
  double cellHeightCm;
  double offsetXCm;
  double offsetYCm;
  double geomEpsCm;

  /// Convenience for square grids (ceiling Armstrong etc.).
  double get cellSizeCm => cellWidthCm;
  set cellSizeCm(double v) {
    cellWidthCm = v;
    cellHeightCm = v;
  }

  List<GridCell> _cells = const [];
  List<(double, double, double, double)> _vLines = const [];
  List<(double, double, double, double)> _hLines = const [];
  int _full = 0;
  int _cut = 0;
  bool _dirty = true;

  List<GridCell> get cells => _cells;
  List<(double x1, double y1, double x2, double y2)> get verticalLines => _vLines;
  List<(double x1, double y1, double x2, double y2)> get horizontalLines => _hLines;
  int get fullTiles => _full;
  int get cutTiles => _cut;
  int get lightCount => _cells.where((c) => c.hasLight).length;

  (int full, int cut) get effectiveTileCounts {
    var full = _full;
    var cut = _cut;
    var rem = lightCount;
    final fromFull = math.min(rem, full);
    full -= fromFull;
    rem -= fromFull;
    cut = math.max(0, cut - rem);
    return (full, cut);
  }

  void setOffset(double xCm, double yCm) {
    offsetXCm = xCm;
    offsetYCm = yCm;
    _dirty = true;
  }

  void setCellSize(double sizeCm) {
    cellWidthCm = sizeCm;
    cellHeightCm = sizeCm;
    _dirty = true;
  }

  void setCellSizeWH(double widthCm, double heightCm) {
    cellWidthCm = widthCm;
    cellHeightCm = heightCm;
    _dirty = true;
  }

  void markDirty() => _dirty = true;

  static String _cacheKey({
    required List<(double x, double y)> roomPoints,
    required List<List<double>> walls,
    required double cellWidthCm,
    required double cellHeightCm,
    required double offsetXCm,
    required double offsetYCm,
    required Set<String> lights,
  }) {
    final buf = StringBuffer()
      ..write(cellWidthCm.toStringAsFixed(3))
      ..write('x')
      ..write(cellHeightCm.toStringAsFixed(3))
      ..write('|')
      ..write(offsetXCm.toStringAsFixed(3))
      ..write('|')
      ..write(offsetYCm.toStringAsFixed(3))
      ..write('|');
    for (final p in roomPoints) {
      buf
        ..write(p.$1.toStringAsFixed(3))
        ..write(',')
        ..write(p.$2.toStringAsFixed(3))
        ..write(';');
    }
    buf.write('|');
    for (final w in walls) {
      for (final v in w) {
        buf.write(v.toStringAsFixed(3));
        buf.write(',');
      }
      buf.write(';');
    }
    buf.write('|');
    final sortedLights = lights.toList()..sort();
    for (final id in sortedLights) {
      buf.write(id);
      buf.write(';');
    }
    return buf.toString();
  }

  void rebuild({
    required List<(double x, double y)> roomPoints,
    required List<List<double>> walls,
    Set<String>? lightIds,
  }) {
    final lights = lightIds ?? {};
    if (roomPoints.length < 3 || walls.isEmpty) {
      _cells = const [];
      _vLines = const [];
      _hLines = const [];
      _full = 0;
      _cut = 0;
      _dirty = false;
      return;
    }

    final key = _cacheKey(
      roomPoints: roomPoints,
      walls: walls,
      cellWidthCm: cellWidthCm,
      cellHeightCm: cellHeightCm,
      offsetXCm: offsetXCm,
      offsetYCm: offsetYCm,
      lights: lights,
    );
    final cached = _rebuildCache[key];
    if (cached != null) {
      _applySnapshot(cached);
      _dirty = false;
      return;
    }

    final snapshot = _computeRebuild(
      roomPoints: roomPoints,
      walls: walls,
      lights: lights,
    );
    _rebuildCache[key] = snapshot;
    _applySnapshot(snapshot);
    _dirty = false;
  }

  void _applySnapshot(_GridRebuildSnapshot s) {
    _cells = s.cells;
    _vLines = s.vLines;
    _hLines = s.hLines;
    _full = s.full;
    _cut = s.cut;
  }

  _GridRebuildSnapshot _computeRebuild({
    required List<(double x, double y)> roomPoints,
    required List<List<double>> walls,
    required Set<String> lights,
  }) {
    final bounds = _roomBounds(walls);
    final (roomMinX, roomMaxX, roomMinY, roomMaxY) = bounds;

    final cellW = cellWidthCm;
    final cellH = cellHeightCm;
    final searchMinX = roomMinX - cellW;
    final searchMaxX = roomMaxX + cellW;
    final searchMinY = roomMinY - cellH;
    final searchMaxY = roomMaxY + cellH;

    final startX =
        ((searchMinX - offsetXCm) / cellW).floor() * cellW + offsetXCm;
    final startY =
        ((searchMinY - offsetYCm) / cellH).floor() * cellH + offsetYCm;

    final originCol = ((startX - offsetXCm) / cellW).round();
    final originRow = ((startY - offsetYCm) / cellH).round();

    final next = <GridCell>[];
    var full = 0;
    var cut = 0;

    var col = originCol;
    for (var x = startX; x < searchMaxX; x += cellW, col++) {
      var row = originRow;
      for (var y = startY; y < searchMaxY; y += cellH, row++) {
        final x2 = x + cellW;
        final y2 = y + cellH;
        final analysis = _analyzeTile(
          walls: walls,
          roomPoints: roomPoints,
          bounds: bounds,
          x1: x,
          y1: y,
          x2: x2,
          y2: y2,
        );
        if (analysis.kind == CellKind.outside) continue;
        final id = '$col:$row';
        if (analysis.kind == CellKind.full) full++;
        if (analysis.kind == CellKind.cut) cut++;
        next.add(GridCell(
          col: col,
          row: row,
          xCm: x,
          yCm: y,
          kind: analysis.kind,
          cutXCm: analysis.cutX,
          cutYCm: analysis.cutY,
          hasLight: lights.contains(id),
        ));
      }
    }

    double? gMinX, gMaxX, gMinY, gMaxY;
    for (final c in next) {
      gMinX = gMinX == null ? c.xCm : math.min(gMinX, c.xCm);
      gMaxX = gMaxX == null ? c.xCm + cellW : math.max(gMaxX, c.xCm + cellW);
      gMinY = gMinY == null ? c.yCm : math.min(gMinY, c.yCm);
      gMaxY = gMaxY == null ? c.yCm + cellH : math.max(gMaxY, c.yCm + cellH);
    }
    final v = <(double, double, double, double)>[];
    final h = <(double, double, double, double)>[];
    if (gMinX != null) {
      for (var x = gMinX; x <= gMaxX! + geomEpsCm; x += cellW) {
        v.add((x, gMinY!, x, gMaxY!));
      }
      for (var y = gMinY!; y <= gMaxY! + geomEpsCm; y += cellH) {
        h.add((gMinX, y, gMaxX, y));
      }
    }

    return _GridRebuildSnapshot(
      cells: List.unmodifiable(next),
      vLines: List.unmodifiable(v),
      hLines: List.unmodifiable(h),
      full: full,
      cut: cut,
    );
  }

  bool get isDirty => _dirty;

  GridCell? cellAt(int col, int row) {
    for (final c in _cells) {
      if (c.col == col && c.row == row) return c;
    }
    return null;
  }

  Set<String> toggleLight(int col, int row) {
    final out = <String>{};
    final updated = <GridCell>[];
    for (final c in _cells) {
      if (c.col == col && c.row == row) {
        if (!c.acceptsLight && !c.hasLight) {
          updated.add(c);
          continue;
        }
        final next = c.copyWith(hasLight: !c.hasLight);
        updated.add(next);
        if (next.hasLight) out.add(next.id);
      } else {
        updated.add(c);
        if (c.hasLight) out.add(c.id);
      }
    }
    _cells = updated;
    return out;
  }

  /// Removes lights on cells that left the room contour (Kivy parity).
  bool pruneLights() {
    var changed = false;
    final updated = <GridCell>[];
    for (final c in _cells) {
      if (c.hasLight && !c.acceptsLight) {
        updated.add(c.copyWith(hasLight: false));
        changed = true;
      } else {
        updated.add(c);
      }
    }
    if (changed) _cells = updated;
    return changed;
  }

  ({CellKind kind, double cutX, double cutY}) _analyzeTile({
    required List<List<double>> walls,
    required List<(double, double)> roomPoints,
    required (double, double, double, double) bounds,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) {
    final (roomMinX, roomMaxX, roomMinY, roomMaxY) = bounds;
    final eps = geomEpsCm;
    final tileW = x2 - x1;
    final tileH = y2 - y1;

    if (x2 <= roomMinX || x1 >= roomMaxX || y2 <= roomMinY || y1 >= roomMaxY) {
      return (kind: CellKind.outside, cutX: 0.0, cutY: 0.0);
    }

    final corners = [(x1, y1), (x2, y1), (x2, y2), (x1, y2)];
    final cornersInside = corners
        .where((p) => _isPointInsideOrOnBoundary(walls, roomPoints, p.$1, p.$2))
        .length;

    if (cornersInside == 4) {
      return (kind: CellKind.full, cutX: tileW, cutY: tileH);
    }

    if (cornersInside == 0) {
      final testPoints = [
        ((x1 + x2) / 2, (y1 + y2) / 2),
        (x1 + 20, y1 + 20),
        (x2 - 20, y2 - 20),
        (x1 + 20, y2 - 20),
        (x2 - 20, y1 + 20),
      ];
      final inside = testPoints
          .where((p) => _isPointInsideOrOnBoundary(walls, roomPoints, p.$1, p.$2))
          .length;
      if (inside == 0) {
        return (kind: CellKind.outside, cutX: 0.0, cutY: 0.0);
      }
    }

    final (usefulX, usefulY) = _calculateCutDimensions(
      walls: walls,
      roomPoints: roomPoints,
      bounds: bounds,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
    );

    if (usefulX <= eps || usefulY <= eps) {
      return (kind: CellKind.outside, cutX: 0.0, cutY: 0.0);
    }

    if (usefulX >= (tileW - eps) && usefulY >= (tileH - eps)) {
      return (kind: CellKind.full, cutX: tileW, cutY: tileH);
    }

    return (kind: CellKind.cut, cutX: usefulX, cutY: usefulY);
  }

  (double, double, double, double) _roomBounds(List<List<double>> walls) {
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
    return (minX, maxX, minY, maxY);
  }

  bool _isRectangularRoom(
    List<List<double>> walls,
    (double, double, double, double) bounds,
  ) {
    if (walls.length != 4) return false;
    final corners = <(double, double)>{};
    for (final w in walls) {
      corners.add((w[0], w[1]));
      corners.add((w[2], w[3]));
    }
    if (corners.length != 4) return false;
    final (roomMinX, roomMaxX, roomMinY, roomMaxY) = bounds;
    final cornerX = corners.map((p) => p.$1).toSet().toList()..sort();
    final cornerY = corners.map((p) => p.$2).toSet().toList()..sort();
    return cornerX.length == 2 &&
        cornerY.length == 2 &&
        cornerX.contains(roomMinX) &&
        cornerX.contains(roomMaxX) &&
        cornerY.contains(roomMinY) &&
        cornerY.contains(roomMaxY);
  }

  (double, double) _calculateCutDimensions({
    required List<List<double>> walls,
    required List<(double, double)> roomPoints,
    required (double, double, double, double) bounds,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) {
    final eps = geomEpsCm;
    final tileW = x2 - x1;
    final tileH = y2 - y1;
    final (roomMinX, roomMaxX, roomMinY, roomMaxY) = bounds;

    if (_isRectangularRoom(walls, bounds)) {
      final ix1 = math.max(x1, roomMinX);
      final iy1 = math.max(y1, roomMinY);
      final ix2 = math.min(x2, roomMaxX);
      final iy2 = math.min(y2, roomMaxY);
      if (ix1 >= ix2 || iy1 >= iy2) return (0.0, 0.0);
      final usefulX = ix2 - ix1;
      final usefulY = iy2 - iy1;
      return (
        math.max(0.0, math.min(tileW, usefulX)),
        math.max(0.0, math.min(tileH, usefulY)),
      );
    }

    final clipped = _clipPolygonWithRect(roomPoints, x1, y1, x2, y2);
    if (clipped.length < 3) return (0.0, 0.0);

    final area = _polygonArea(clipped);
    if (area <= eps * eps) return (0.0, 0.0);

    var minXi = clipped.first.$1;
    var maxXi = clipped.first.$1;
    var minYi = clipped.first.$2;
    var maxYi = clipped.first.$2;
    for (final p in clipped) {
      minXi = math.min(minXi, p.$1);
      maxXi = math.max(maxXi, p.$1);
      minYi = math.min(minYi, p.$2);
      maxYi = math.max(maxYi, p.$2);
    }
    final usefulX = math.max(0.0, math.min(tileW, maxXi - minXi));
    final usefulY = math.max(0.0, math.min(tileH, maxYi - minYi));
    if (usefulX <= eps || usefulY <= eps) return (0.0, 0.0);
    return (usefulX, usefulY);
  }

  static double _polygonArea(List<(double, double)> points) {
    if (points.length < 3) return 0.0;
    var area = 0.0;
    for (var i = 0; i < points.length; i++) {
      final (x1, y1) = points[i];
      final (x2, y2) = points[(i + 1) % points.length];
      area += x1 * y2 - x2 * y1;
    }
    return area.abs() / 2.0;
  }

  static List<(double, double)> _clipPolygonWithRect(
    List<(double, double)> polygon,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    if (polygon.isEmpty) return [];
    final left = math.min(x1, x2);
    final right = math.max(x1, x2);
    final bottom = math.min(y1, y2);
    final top = math.max(y1, y2);

    List<(double, double)> clipEdge(
      List<(double, double)> points,
      bool Function((double, double)) insideFn,
      (double, double) Function((double, double), (double, double)) intersectFn,
    ) {
      if (points.isEmpty) return [];
      final out = <(double, double)>[];
      var prev = points.last;
      var prevInside = insideFn(prev);
      for (final curr in points) {
        final currInside = insideFn(curr);
        if (currInside) {
          if (!prevInside) out.add(intersectFn(prev, curr));
          out.add(curr);
        } else if (prevInside) {
          out.add(intersectFn(prev, curr));
        }
        prev = curr;
        prevInside = currInside;
      }
      return out;
    }

    (double, double) interLeft((double, double) a, (double, double) b) {
      final (ax, ay) = a;
      final (bx, by) = b;
      if ((bx - ax).abs() < 1e-10) return (left, ay);
      final t = (left - ax) / (bx - ax);
      return (left, ay + t * (by - ay));
    }

    (double, double) interRight((double, double) a, (double, double) b) {
      final (ax, ay) = a;
      final (bx, by) = b;
      if ((bx - ax).abs() < 1e-10) return (right, ay);
      final t = (right - ax) / (bx - ax);
      return (right, ay + t * (by - ay));
    }

    (double, double) interBottom((double, double) a, (double, double) b) {
      final (ax, ay) = a;
      final (bx, by) = b;
      if ((by - ay).abs() < 1e-10) return (ax, bottom);
      final t = (bottom - ay) / (by - ay);
      return (ax + t * (bx - ax), bottom);
    }

    (double, double) interTop((double, double) a, (double, double) b) {
      final (ax, ay) = a;
      final (bx, by) = b;
      if ((by - ay).abs() < 1e-10) return (ax, top);
      final t = (top - ay) / (by - ay);
      return (ax + t * (bx - ax), top);
    }

    var pts = polygon;
    pts = clipEdge(pts, (p) => p.$1 >= left, interLeft);
    pts = clipEdge(pts, (p) => p.$1 <= right, interRight);
    pts = clipEdge(pts, (p) => p.$2 >= bottom, interBottom);
    pts = clipEdge(pts, (p) => p.$2 <= top, interTop);
    return pts;
  }

  static double _pointToLineDistance(
    double px,
    double py,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    if (dx == 0 && dy == 0) {
      return math.sqrt((px - x1) * (px - x1) + (py - y1) * (py - y1));
    }
    final t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy);
    final tc = t.clamp(0.0, 1.0);
    final projX = x1 + tc * dx;
    final projY = y1 + tc * dy;
    return math.sqrt((px - projX) * (px - projX) + (py - projY) * (py - projY));
  }

  static bool _isPointInsideOrOnBoundary(
    List<List<double>> walls,
    List<(double, double)> poly,
    double px,
    double py,
  ) {
    const eps = 0.05;
    for (final w in walls) {
      if (_pointToLineDistance(px, py, w[0], w[1], w[2], w[3]) <= eps) {
        return true;
      }
    }
    return _pointInPolygon(poly, px, py);
  }

  static bool _pointInPolygon(List<(double, double)> poly, double x, double y) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].$1, yi = poly[i].$2;
      final xj = poly[j].$1, yj = poly[j].$2;
      final intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
