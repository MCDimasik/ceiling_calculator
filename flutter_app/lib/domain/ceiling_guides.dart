import 'dart:math' as math;

import 'materials_calculator.dart';

enum GuideKind {
  g3600('3600', 'Направляющая 3600', 360, 6),
  g1200('1200', 'Направляющая 1200', 120, 2),
  g600('600', 'Направляющая 600', 60, 1),
  g2400('2400', 'Направляющая 2400', 240, 4);

  const GuideKind(this.id, this.materialName, this.lengthCm, this.tilesAlong);

  final String id;
  final String materialName;
  final int lengthCm;
  /// How many 600×600 tiles fit along one profile length.
  final int tilesAlong;

  static GuideKind? tryParse(String? raw) {
    if (raw == null) return null;
    for (final k in GuideKind.values) {
      if (k.id == raw) return k;
    }
    return null;
  }
}

enum GuideAxis { horizontal, vertical }

class CeilingGuideMark {
  CeilingGuideMark({
    required this.axis,
    required this.lineIndex,
    required this.kind,
    this.anchorAlongIndex = 0,
  });

  /// Grid line index — world coord = offset + lineIndex × cell size.
  final GuideAxis axis;
  final int lineIndex;
  final GuideKind kind;

  /// Grid line index on the perpendicular axis — where the first profile anchors.
  final int anchorAlongIndex;

  String get storageKey =>
      '${axis == GuideAxis.horizontal ? 'h' : 'v'}:$lineIndex';

  double worldCoord({
    required double offsetX,
    required double offsetY,
    required double cellSize,
  }) {
    return axis == GuideAxis.horizontal
        ? offsetY + lineIndex * cellSize
        : offsetX + lineIndex * cellSize;
  }

  double anchorWorldCoord({
    required double offsetX,
    required double offsetY,
    required double cellSize,
  }) {
    return axis == GuideAxis.horizontal
        ? offsetX + anchorAlongIndex * cellSize
        : offsetY + anchorAlongIndex * cellSize;
  }

  Map<String, dynamic> toJson() => {
        'axis': axis == GuideAxis.horizontal ? 'h' : 'v',
        'line': lineIndex,
        'kind': kind.id,
        if (anchorAlongIndex != 0) 'anchor': anchorAlongIndex,
      };

  static CeilingGuideMark? fromJson(
    Map<String, dynamic> json, {
    double offsetX = 0,
    double offsetY = 0,
    double cellSize = 60,
  }) {
    final axisRaw = json['axis'] as String?;
    final kind = GuideKind.tryParse(json['kind'] as String?);
    if (kind == null || axisRaw == null) return null;
    final axis = axisRaw == 'v' ? GuideAxis.vertical : GuideAxis.horizontal;

    int? lineIndex;
    final lineRaw = json['line'];
    if (lineRaw is num) {
      lineIndex = lineRaw.round();
    } else {
      final pos = (json['pos'] as num?)?.toDouble();
      if (pos != null) {
        lineIndex = axis == GuideAxis.horizontal
            ? ((pos - offsetY) / cellSize).round()
            : ((pos - offsetX) / cellSize).round();
      }
    }
    if (lineIndex == null) return null;

    var anchor = 0;
    final anchorRaw = json['anchor'];
    if (anchorRaw is num) {
      anchor = anchorRaw.round();
    }

    return CeilingGuideMark(
      axis: axis,
      lineIndex: lineIndex,
      kind: kind,
      anchorAlongIndex: anchor,
    );
  }
}

List<CeilingGuideMark> parseCeilingGuides(
  List<Map<String, dynamic>> raw, {
  double offsetX = 0,
  double offsetY = 0,
  double cellSize = 60,
}) {
  final out = <CeilingGuideMark>[];
  for (final m in raw) {
    final g = CeilingGuideMark.fromJson(
      m,
      offsetX: offsetX,
      offsetY: offsetY,
      cellSize: cellSize,
    );
    if (g != null) out.add(g);
  }
  return out;
}

/// Legacy marks without `anchor` get a centroid-based anchor on the perpendicular axis.
List<CeilingGuideMark> parseCeilingGuidesWithLegacyAnchor(
  List<Map<String, dynamic>> raw,
  List<List<double>> walls, {
  double offsetX = 0,
  double offsetY = 0,
  double cellSize = 60,
}) {
  final (cx, cy) = roomCentroidCm(walls);
  final out = <CeilingGuideMark>[];
  for (final m in raw) {
    var g = CeilingGuideMark.fromJson(
      m,
      offsetX: offsetX,
      offsetY: offsetY,
      cellSize: cellSize,
    );
    if (g == null) continue;
    if (m['anchor'] == null && g.anchorAlongIndex == 0) {
      final anchor = g.axis == GuideAxis.horizontal
          ? snapGuideLineIndex(
              axis: GuideAxis.vertical,
              worldCoord: cx,
              offset: offsetX,
              cellSize: cellSize,
              walls: walls,
            )
          : snapGuideLineIndex(
              axis: GuideAxis.horizontal,
              worldCoord: cy,
              offset: offsetY,
              cellSize: cellSize,
              walls: walls,
            );
      g = CeilingGuideMark(
        axis: g.axis,
        lineIndex: g.lineIndex,
        kind: g.kind,
        anchorAlongIndex: anchor,
      );
    }
    out.add(g);
  }
  return out;
}

List<(double, double)> roomHorizontalSegments(
  List<(double, double)> polygon,
  double y,
) {
  const eps = 1e-6;
  final xs = <double>[];
  final n = polygon.length;
  for (var i = 0; i < n; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % n];
    if ((a.$2 - y).abs() <= eps && (b.$2 - y).abs() <= eps) {
      xs.add(a.$1);
      xs.add(b.$1);
      continue;
    }
    final ay = a.$2;
    final by = b.$2;
    if ((ay <= y && by > y) || (by <= y && ay > y)) {
      final dy = by - ay;
      if (dy.abs() > eps) {
        final t = (y - ay) / dy;
        xs.add(a.$1 + t * (b.$1 - a.$1));
      }
    }
  }
  xs.sort();
  final segs = <(double, double)>[];
  for (var i = 0; i + 1 < xs.length; i += 2) {
    if (xs[i + 1] > xs[i] + eps) segs.add((xs[i], xs[i + 1]));
  }
  return segs;
}

List<(double, double)> roomVerticalSegments(
  List<(double, double)> polygon,
  double x,
) {
  const eps = 1e-6;
  final ys = <double>[];
  final n = polygon.length;
  for (var i = 0; i < n; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % n];
    if ((a.$1 - x).abs() <= eps && (b.$1 - x).abs() <= eps) {
      ys.add(a.$2);
      ys.add(b.$2);
      continue;
    }
    final ax = a.$1;
    final bx = b.$1;
    if ((ax <= x && bx > x) || (bx <= x && ax > x)) {
      final dx = bx - ax;
      if (dx.abs() > eps) {
        final t = (x - ax) / dx;
        ys.add(a.$2 + t * (b.$2 - a.$2));
      }
    }
  }
  ys.sort();
  final segs = <(double, double)>[];
  for (var i = 0; i + 1 < ys.length; i += 2) {
    if (ys[i + 1] > ys[i] + eps) segs.add((ys[i], ys[i + 1]));
  }
  return segs;
}

/// One drawable segment of a marked guide line.
class GuideDrawSegment {
  const GuideDrawSegment({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.isPrimary,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final bool isPrimary;
}

class GuideEdgeSnap {
  const GuideEdgeSnap({
    required this.axis,
    required this.lineIndex,
    required this.coord,
  });

  final GuideAxis axis;
  final int lineIndex;
  final double coord;

  String get storageKey =>
      '${axis == GuideAxis.horizontal ? 'h' : 'v'}:$lineIndex';
}

/// Snap to the nearest horizontal or vertical grid line / room edge.
GuideEdgeSnap snapGuideEdgeAt({
  required double worldX,
  required double worldY,
  required double offsetX,
  required double offsetY,
  required double cellSize,
  required List<List<double>> walls,
  GuideAxis? preferAxis,
}) {
  final hIndex = snapGuideLineIndex(
    axis: GuideAxis.horizontal,
    worldCoord: worldY,
    offset: offsetY,
    cellSize: cellSize,
    walls: walls,
  );
  final vIndex = snapGuideLineIndex(
    axis: GuideAxis.vertical,
    worldCoord: worldX,
    offset: offsetX,
    cellSize: cellSize,
    walls: walls,
  );
  final hCoord = offsetY + hIndex * cellSize;
  final vCoord = offsetX + vIndex * cellSize;
  final hDist = (worldY - hCoord).abs();
  final vDist = (worldX - vCoord).abs();
  final tol = cellSize * 0.42;

  if (preferAxis == GuideAxis.horizontal && hDist <= tol * 1.15) {
    return GuideEdgeSnap(axis: GuideAxis.horizontal, lineIndex: hIndex, coord: hCoord);
  }
  if (preferAxis == GuideAxis.vertical && vDist <= tol * 1.15) {
    return GuideEdgeSnap(axis: GuideAxis.vertical, lineIndex: vIndex, coord: vCoord);
  }
  if (hDist <= vDist) {
    return GuideEdgeSnap(axis: GuideAxis.horizontal, lineIndex: hIndex, coord: hCoord);
  }
  return GuideEdgeSnap(axis: GuideAxis.vertical, lineIndex: vIndex, coord: vCoord);
}

/// Polygon centroid in room cm — stable center for irregular rooms.
(double, double) roomCentroidCm(List<List<double>> walls) {
  final pts = MaterialsCalculator.orderedPointsFromWalls(walls);
  if (pts.length < 3) {
    if (pts.isEmpty) return (0, 0);
    return (pts.first.$1, pts.first.$2);
  }
  var area2 = 0.0;
  var cx = 0.0;
  var cy = 0.0;
  final n = pts.length;
  for (var i = 0; i < n; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % n];
    final cross = a.$1 * b.$2 - b.$1 * a.$2;
    area2 += cross;
    cx += (a.$1 + b.$1) * cross;
    cy += (a.$2 + b.$2) * cross;
  }
  if (area2.abs() < 1e-9) {
    var sx = 0.0, sy = 0.0;
    for (final p in pts) {
      sx += p.$1;
      sy += p.$2;
    }
    return (sx / n, sy / n);
  }
  return (cx / (3 * area2), cy / (3 * area2));
}

(double, double)? _pickWallRun(
  GuideAxis axis,
  List<(double, double)> polygon,
  double coordCm,
  double alongCm,
) {
  final runs = axis == GuideAxis.horizontal
      ? roomHorizontalSegments(polygon, coordCm)
      : roomVerticalSegments(polygon, coordCm);
  if (runs.isEmpty) return null;

  for (final seg in runs) {
    if (alongCm >= seg.$1 - 1e-6 && alongCm <= seg.$2 + 1e-6) return seg;
  }

  (double, double)? best;
  var bestDist = double.infinity;
  for (final seg in runs) {
    final d = alongCm < seg.$1
        ? seg.$1 - alongCm
        : alongCm > seg.$2
            ? alongCm - seg.$2
            : 0.0;
    if (d < bestDist) {
      bestDist = d;
      best = seg;
    }
  }
  return best;
}

/// One profile-length piece for floating drag preview (follows finger in 2D).
GuideDrawSegment? guideFloatingSegmentAt({
  required GuideAxis axis,
  required double coordCm,
  required double alongCm,
  required GuideKind kind,
  required List<List<double>> walls,
}) {
  final polygon = MaterialsCalculator.orderedPointsFromWalls(walls);
  if (polygon.length < 3) return null;

  final guideLen = kind.lengthCm.toDouble();
  final run = _pickWallRun(axis, polygon, coordCm, alongCm);
  if (run == null) return null;

  if (axis == GuideAxis.horizontal) {
    final seg = run;
    var start = alongCm.clamp(seg.$1, seg.$2);
    if (start + guideLen > seg.$2) start = math.max(seg.$1, seg.$2 - guideLen);
    final end = math.min(start + guideLen, seg.$2);
    if (end <= start) return null;
    return GuideDrawSegment(
      x1: start,
      y1: coordCm,
      x2: end,
      y2: coordCm,
      isPrimary: true,
    );
  }

  final seg = run;
  var start = alongCm.clamp(seg.$1, seg.$2);
  if (start + guideLen > seg.$2) start = math.max(seg.$1, seg.$2 - guideLen);
  final end = math.min(start + guideLen, seg.$2);
  if (end <= start) return null;
  return GuideDrawSegment(
    x1: coordCm,
    y1: start,
    x2: coordCm,
    y2: end,
    isPrimary: true,
  );
}

/// First profile-length segment on a guide line (for floating preview).
GuideDrawSegment? guideLeadSegmentAt({
  required GuideAxis axis,
  required double coordCm,
  required GuideKind kind,
  required List<List<double>> walls,
}) {
  final polygon = MaterialsCalculator.orderedPointsFromWalls(walls);
  if (polygon.length < 3) return null;
  final guideLen = kind.lengthCm.toDouble();
  if (axis == GuideAxis.horizontal) {
    for (final seg in roomHorizontalSegments(polygon, coordCm)) {
      final len = seg.$2 - seg.$1;
      if (len <= 0) continue;
      final end = math.min(seg.$1 + guideLen, seg.$2);
      return GuideDrawSegment(
        x1: seg.$1,
        y1: coordCm,
        x2: end,
        y2: coordCm,
        isPrimary: true,
      );
    }
  } else {
    for (final seg in roomVerticalSegments(polygon, coordCm)) {
      final len = seg.$2 - seg.$1;
      if (len <= 0) continue;
      final end = math.min(seg.$1 + guideLen, seg.$2);
      return GuideDrawSegment(
        x1: coordCm,
        y1: seg.$1,
        x2: coordCm,
        y2: end,
        isPrimary: true,
      );
    }
  }
  return null;
}

/// Full wall-to-wall segments for a placed guide line.
List<GuideDrawSegment> guideFullSegments(
  CeilingGuideMark mark,
  List<List<double>> walls, {
  required double offsetX,
  required double offsetY,
  required double cellSize,
  double? coordCm,
}) {
  final polygon = MaterialsCalculator.orderedPointsFromWalls(walls);
  if (polygon.length < 3) return const [];

  final coord = coordCm ??
      mark.worldCoord(
        offsetX: offsetX,
        offsetY: offsetY,
        cellSize: cellSize,
      );
  final out = <GuideDrawSegment>[];
  if (mark.axis == GuideAxis.horizontal) {
    for (final seg in roomHorizontalSegments(polygon, coord)) {
      if (seg.$2 > seg.$1) {
        out.add(GuideDrawSegment(
          x1: seg.$1,
          y1: coord,
          x2: seg.$2,
          y2: coord,
          isPrimary: false,
        ));
      }
    }
  } else {
    for (final seg in roomVerticalSegments(polygon, coord)) {
      if (seg.$2 > seg.$1) {
        out.add(GuideDrawSegment(
          x1: coord,
          y1: seg.$1,
          x2: coord,
          y2: seg.$2,
          isPrimary: false,
        ));
      }
    }
  }
  return out;
}

List<GuideDrawSegment> guideDrawSegments(
  CeilingGuideMark mark,
  List<List<double>> walls, {
  required double offsetX,
  required double offsetY,
  required double cellSize,
  bool highlightLead = true,
}) {
  final polygon = MaterialsCalculator.orderedPointsFromWalls(walls);
  if (polygon.length < 3) return const [];

  final guideLen = mark.kind.lengthCm.toDouble();
  final coord = mark.worldCoord(
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
  );
  final out = <GuideDrawSegment>[];

  void addRun(double a1, double b1, double a2, double b2) {
    final len = math.sqrt((a2 - a1) * (a2 - a1) + (b2 - b1) * (b2 - b1));
    if (len <= 0) return;
    if (highlightLead && len > guideLen + 1e-6) {
      final t = guideLen / len;
      final mx = a1 + (a2 - a1) * t;
      final my = b1 + (b2 - b1) * t;
      out.add(GuideDrawSegment(x1: a1, y1: b1, x2: mx, y2: my, isPrimary: true));
      out.add(GuideDrawSegment(x1: mx, y1: my, x2: a2, y2: b2, isPrimary: false));
    } else {
      out.add(GuideDrawSegment(x1: a1, y1: b1, x2: a2, y2: b2, isPrimary: true));
    }
  }

  if (mark.axis == GuideAxis.horizontal) {
    for (final seg in roomHorizontalSegments(polygon, coord)) {
      addRun(seg.$1, coord, seg.$2, coord);
    }
  } else {
    for (final seg in roomVerticalSegments(polygon, coord)) {
      addRun(coord, seg.$1, coord, seg.$2);
    }
  }
  return out;
}

(double, double) _roomSpan(GuideAxis axis, List<List<double>> walls) {
  if (walls.isEmpty) return (0, 0);
  var minV = walls.first[axis == GuideAxis.horizontal ? 1 : 0];
  var maxV = minV;
  for (final w in walls) {
    for (final v in [
      axis == GuideAxis.horizontal ? w[1] : w[0],
      axis == GuideAxis.horizontal ? w[3] : w[2],
    ]) {
      minV = math.min(minV, v);
      maxV = math.max(maxV, v);
    }
  }
  return (minV, maxV);
}

/// World position of anchor grid line on the perpendicular axis.
double guideAnchorWorldCoord({
  required CeilingGuideMark mark,
  required double gridOffsetX,
  required double gridOffsetY,
  required double visualOffsetX,
  required double visualOffsetY,
  required double cellSize,
}) {
  final perpAxis =
      mark.axis == GuideAxis.horizontal ? GuideAxis.vertical : GuideAxis.horizontal;
  return guideLineWorldCoord(
    axis: perpAxis,
    lineIndex: mark.anchorAlongIndex,
    gridOffset: perpAxis == GuideAxis.vertical ? gridOffsetX : gridOffsetY,
    visualOffset: perpAxis == GuideAxis.vertical ? visualOffsetX : visualOffsetY,
    cellSize: cellSize,
  );
}

/// World position of a guide grid line — matches tile grid shift during drag.
double guideLineWorldCoord({
  required GuideAxis axis,
  required int lineIndex,
  required double gridOffset,
  required double visualOffset,
  required double cellSize,
}) {
  return gridOffset + lineIndex * cellSize + (visualOffset - gridOffset);
}

int snapGuideLineIndex({
  required GuideAxis axis,
  required double worldCoord,
  required double offset,
  required double cellSize,
  List<List<double>>? walls,
}) {
  if (cellSize <= 0) return 0;
  // Nearest grid line — including lines that coincide with a wall when the
  // tile grid starts at the wall (full tile from the edge).
  return ((worldCoord - offset) / cellSize).round();
}

/// Snap both grid indices for a guide placement (line + anchor intersection).
({int lineIndex, int anchorIndex, GuideAxis axis}) snapGuidePlacement({
  required double worldX,
  required double worldY,
  required double offsetX,
  required double offsetY,
  required double cellSize,
  required List<List<double>> walls,
  GuideAxis? preferAxis,
}) {
  final edge = snapGuideEdgeAt(
    worldX: worldX,
    worldY: worldY,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
    walls: walls,
    preferAxis: preferAxis,
  );
  final perpAxis =
      edge.axis == GuideAxis.horizontal ? GuideAxis.vertical : GuideAxis.horizontal;
  final anchorIndex = snapGuideLineIndex(
    axis: perpAxis,
    worldCoord: perpAxis == GuideAxis.vertical ? worldX : worldY,
    offset: perpAxis == GuideAxis.vertical ? offsetX : offsetY,
    cellSize: cellSize,
    walls: walls,
  );
  return (lineIndex: edge.lineIndex, anchorIndex: anchorIndex, axis: edge.axis);
}

/// Profile pieces for purchase/draw: stock lengths along each run, **phased to
/// the grid** so joints stay on the 60 cm module across separate bays of an
/// irregular room (not restarted from each wall stub).
///
/// [anchorAlongCm] (or grid offset along the run) sets the phase origin.
/// Example: span 425 cm of 3600 with anchor 0 → cuts at 360, remnant 65.
List<GuideDrawSegment> guideProfilePieceSegments(
  CeilingGuideMark mark,
  List<List<double>> walls, {
  required double offsetX,
  required double offsetY,
  required double cellSize,
  double? coordCm,
  double? anchorAlongCm,
}) {
  final polygon = MaterialsCalculator.orderedPointsFromWalls(walls);
  if (polygon.length < 3) return const [];

  final guideLen = mark.kind.lengthCm.toDouble();
  if (guideLen <= 0) return const [];

  final coord = coordCm ??
      mark.worldCoord(
        offsetX: offsetX,
        offsetY: offsetY,
        cellSize: cellSize,
      );

  // Guides coinciding with room walls are perimeter angle, not carriers.
  final spanAxis = mark.axis;
  final (minB, maxB) = _roomSpan(spanAxis, walls);
  if ((coord - minB).abs() <= 1.0 || (coord - maxB).abs() <= 1.0) {
    return const [];
  }

  final runs = mark.axis == GuideAxis.horizontal
      ? roomHorizontalSegments(polygon, coord)
      : roomVerticalSegments(polygon, coord);
  if (runs.isEmpty) return const [];

  // Phase joints to the global grid along the run (same in every bay).
  final phaseOrigin = anchorAlongCm ??
      (mark.axis == GuideAxis.horizontal ? offsetX : offsetY);

  const eps = 1e-6;
  final out = <GuideDrawSegment>[];

  for (final run in runs) {
    final runStart = run.$1;
    final runEnd = run.$2;
    if (runEnd <= runStart + eps) continue;

    // Split points: run ends + every stock boundary on the global phase.
    final cuts = <double>[runStart, runEnd];
    final firstCut =
        phaseOrigin + ((runStart - phaseOrigin) / guideLen).ceil() * guideLen;
    for (var t = firstCut; t < runEnd - eps; t += guideLen) {
      if (t > runStart + eps && t < runEnd - eps) cuts.add(t);
    }
    cuts.sort();

    for (var i = 0; i < cuts.length - 1; i++) {
      final pos = cuts[i];
      final end = cuts[i + 1];
      if (end <= pos + eps) continue;

      if (mark.axis == GuideAxis.horizontal) {
        out.add(GuideDrawSegment(
          x1: pos,
          y1: coord,
          x2: end,
          y2: coord,
          isPrimary: true,
        ));
      } else {
        out.add(GuideDrawSegment(
          x1: coord,
          y1: pos,
          x2: coord,
          y2: end,
          isPrimary: true,
        ));
      }
    }
  }

  out.sort((a, b) {
    final aa = mark.axis == GuideAxis.horizontal ? a.x1 : a.y1;
    final bb = mark.axis == GuideAxis.horizontal ? b.x1 : b.y1;
    return aa.compareTo(bb);
  });
  return out;
}

int piecesOnMarkedLine(
  CeilingGuideMark mark,
  List<List<double>> walls, {
  required double offsetX,
  required double offsetY,
  required double cellSize,
}) {
  return packGuidePurchaseCount(
    guideProfilePieceSegments(
      mark,
      walls,
      offsetX: offsetX,
      offsetY: offsetY,
      cellSize: cellSize,
    ),
    mark.kind.lengthCm.toDouble(),
  );
}

/// Trim from each factory end that removes a lock/connector (cm).
///
/// Profiles join lock-to-lock. Cutting both ends leaves a middle remnant without
/// locks — that remnant is scrap. Wall-to-wall spans on the perimeter angle do
/// not need locks; max useful length after trimming both ends is
/// [GuideKind.lengthCm] − 2×[guideLockTrimCm] (e.g. 340 cm for 3600).
const double guideLockTrimCm = 10;

/// Extra length reserved on each side of a lock-to-lock scrap join (cm).
///
/// Two one-lock remnants of lengths L1, L2 can cover a span [need] only if
/// `L1 + L2 − 2×guideJoinMarginCm >= need`.
const double guideJoinMarginCm = 20;

/// Purchase qty for one stock length, with one-lock remnant reuse + joins.
///
/// Factory bars have locks on both ends. Cutting once yields two one-lock
/// pieces. Any further cut on a remnant removes its last lock — the leftover
/// is scrap and is **not** banked. So one purchased bar yields at most
/// **two** usable short pieces (both ends), never a chain of middle cuts.
///
/// - Full (~stock) pieces → +1 each, no remnant.
/// - Short pieces: prefer a single remnant ≥ need (consume whole remnant),
///   else a pair with usable `L1+L2−2×[guideJoinMarginCm]`, else buy a new
///   bar and bank `stock−need` as the other one-lock end when useful.
/// - Crumbs shorter than [minUsefulCm] ignored.
int packGuidePurchaseCount(
  List<GuideDrawSegment> segments,
  double stockLenCm, {
  double minUsefulCm = 5.0,
}) {
  if (stockLenCm <= 0 || segments.isEmpty) return 0;

  const eps = 0.5;
  final needs = <double>[];
  for (final seg in segments) {
    final len = math.sqrt(
      (seg.x2 - seg.x1) * (seg.x2 - seg.x1) + (seg.y2 - seg.y1) * (seg.y2 - seg.y1),
    );
    if (len < minUsefulCm) continue;
    needs.add(len);
  }
  if (needs.isEmpty) return 0;

  // Longest first so large spans claim new stock / big remnants before small ones.
  needs.sort((a, b) => b.compareTo(a));

  var purchase = 0;
  final remnants = <double>[]; // one-lock leftovers (at most one factory end)

  bool tryConsumeSingleRemnant(double need) {
    var bestIdx = -1;
    var bestLen = double.infinity;
    for (var i = 0; i < remnants.length; i++) {
      final r = remnants[i];
      if (r + eps >= need && r < bestLen) {
        bestLen = r;
        bestIdx = i;
      }
    }
    if (bestIdx < 0) return false;
    // Taking the lock end for [need] leaves a double-cut middle — scrap.
    remnants.removeAt(bestIdx);
    return true;
  }

  bool tryConsumeJoinedRemnants(double need) {
    // Prefer the tightest pair that still covers [need] after join margins.
    var bestI = -1;
    var bestJ = -1;
    var bestSum = double.infinity;
    for (var i = 0; i < remnants.length; i++) {
      for (var j = i + 1; j < remnants.length; j++) {
        final usable =
            remnants[i] + remnants[j] - 2 * guideJoinMarginCm;
        if (usable + eps >= need) {
          final sum = remnants[i] + remnants[j];
          if (sum < bestSum) {
            bestSum = sum;
            bestI = i;
            bestJ = j;
          }
        }
      }
    }
    if (bestI < 0) return false;
    // Remove higher index first.
    remnants.removeAt(bestJ);
    remnants.removeAt(bestI);
    return true;
  }

  for (final need in needs) {
    if (need >= stockLenCm - eps) {
      purchase++;
      continue;
    }
    if (tryConsumeSingleRemnant(need)) continue;
    if (tryConsumeJoinedRemnants(need)) continue;

    purchase++;
    final remnant = stockLenCm - need;
    if (remnant >= minUsefulCm) remnants.add(remnant);
  }

  return purchase;
}

/// Count guide profiles from marks drawn on the layout grid.
/// Segments of the same stock kind are packed together (remnants shared across lines).
Map<String, int>? countGuidesFromMarks(
  List<CeilingGuideMark> guides,
  List<List<double>> walls, {
  required double offsetX,
  required double offsetY,
  required double cellSize,
}) {
  if (guides.isEmpty) return null;

  final segsByKind = <String, List<GuideDrawSegment>>{};
  final stockByKind = <String, double>{};

  for (final g in guides) {
    final name = g.kind.materialName;
    stockByKind[name] = g.kind.lengthCm.toDouble();
    final segs = guideProfilePieceSegments(
      g,
      walls,
      offsetX: offsetX,
      offsetY: offsetY,
      cellSize: cellSize,
    );
    segsByKind.putIfAbsent(name, () => <GuideDrawSegment>[]).addAll(segs);
  }

  if (segsByKind.isEmpty) return null;
  final counts = <String, int>{};
  for (final e in segsByKind.entries) {
    final stock = stockByKind[e.key] ?? 1;
    final n = packGuidePurchaseCount(e.value, stock);
    if (n > 0) counts[e.key] = n;
  }
  return counts.isEmpty ? null : counts;
}

/// Frame template matching materials ceiling label.
CeilingFrameTemplate ceilingFrameTemplateForLabel(String? ceilingLabel) {
  return switch (ceilingLabel) {
    'Грильято' => CeilingFrameTemplate.grilyatoClassic,
    'GL' => CeilingFrameTemplate.grilyatoGl,
    _ => CeilingFrameTemplate.armstrong,
  };
}

/// Full carrier frame when the operator left no guide marks.
List<CeilingGuideMark> autoGuideMarksForRoom({
  required List<List<double>> walls,
  required double offsetX,
  required double offsetY,
  required double cellSize,
  required String? ceilingLabel,
  String? cellSizeLabel,
}) {
  if (walls.length < 3 || cellSize <= 0) return const [];
  final template = ceilingFrameTemplateForLabel(ceilingLabel);
  final seed = seedFrameAtRoomCenter(
    template: template,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
    walls: walls,
  );
  return proposeCeilingFrame(
    template: template,
    seed: seed,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
    walls: walls,
    cellSizeLabel: cellSizeLabel ?? '100x100',
  );
}

Set<String> guideKeysForCeilingType(CeilingType type) {
  switch (type) {
    case CeilingType.armstrong:
    case CeilingType.grilyatoGl:
      return {'Направляющая 3600', 'Направляющая 1200', 'Направляющая 600'};
    case CeilingType.grilyatoClassic:
      return {'Направляющая 2400', 'Направляющая 1200', 'Направляющая 600'};
  }
}

List<CeilingGuideMark> filterGuideMarksForCeilingType(
  List<CeilingGuideMark> marks,
  CeilingType type,
) {
  return marks.where((m) {
    switch (type) {
      case CeilingType.armstrong:
      case CeilingType.grilyatoGl:
        return m.kind != GuideKind.g2400;
      case CeilingType.grilyatoClassic:
        return m.kind != GuideKind.g3600;
    }
  }).toList();
}

Map<String, int>? filterGuideCountsForCeilingType(
  Map<String, int>? counts,
  CeilingType type,
) {
  if (counts == null || counts.isEmpty) return null;
  final allowed = guideKeysForCeilingType(type);
  final out = <String, int>{};
  for (final e in counts.entries) {
    if (allowed.contains(e.key)) out[e.key] = e.value;
  }
  return out.isEmpty ? null : out;
}

void stripExtraneousForCeilingType(Map<String, int> out, CeilingType type) {
  final forbiddenPrefixes = switch (type) {
    CeilingType.armstrong => [
      'Направляющая 2400',
      'Соединитель',
      'Профиль Папа',
      'Профиль Мама',
      'Заглушки',
    ],
    CeilingType.grilyatoClassic => ['Направляющая 3600', 'Заглушки'],
    CeilingType.grilyatoGl => ['Направляющая 2400', 'Соединитель'],
  };
  out.removeWhere((k, _) {
    for (final f in forbiddenPrefixes) {
      if (k == f || k.startsWith('$f (')) return true;
    }
    return false;
  });
  if (type == CeilingType.armstrong) {
    out.removeWhere(
      (k, _) => k.startsWith('Плиты/кассеты (') && !k.contains('Армстронг'),
    );
  } else {
    out.removeWhere(
      (k, _) => k.startsWith('Плиты/кассеты (') && k.contains('Армстронг'),
    );
  }
}

Map<String, int> applyGuideOverrides(
  Map<String, int> result,
  Map<String, int>? guideCounts, {
  CeilingType type = CeilingType.armstrong,
}) {
  final out = Map<String, int>.from(result);
  stripExtraneousForCeilingType(out, type);

  final filtered = filterGuideCountsForCeilingType(guideCounts, type);
  if (filtered == null) return out;

  final formulaSusp = out['Подвес'] ?? 0;

  // Replace the whole carrier set from marks — clear formula lengths that
  // were not placed (e.g. only 1200/600 on a small room must drop 3600).
  for (final k in guideKeysForCeilingType(type)) {
    out.remove(k);
  }
  out.remove('Подвес');
  out.remove('Соединитель');

  for (final e in filtered.entries) {
    out[e.key] = e.value;
  }

  final g3600 = filtered['Направляющая 3600'] ?? 0;
  final g2400 = filtered['Направляющая 2400'] ?? 0;
  final g1200 = filtered['Направляющая 1200'] ?? 0;
  if (g3600 > 0) {
    out['Подвес'] = g3600 * 4;
  } else if (g2400 > 0) {
    out['Подвес'] = g2400 * (type == CeilingType.grilyatoClassic ? 3 : 4);
    if (type == CeilingType.grilyatoClassic) {
      out['Соединитель'] = g2400;
    }
  } else if (g1200 > 0) {
    // No 3600/2400: 1200 act as mains. Spec is «mains × 4» for 3600
    // (~0.9 m pitch). One 3600 ≈ three 1200 → ~1.33 hangers per 1200;
    // use ×2 ( запас, closer to area formula than ×4).
    out['Подвес'] = g1200 * 2;
  } else if (formulaSusp > 0) {
    out['Подвес'] = formulaSusp;
  }

  stripExtraneousForCeilingType(out, type);
  return out;
}

bool _guideLineOnRoomBoundary({
  required GuideAxis axis,
  required int lineIndex,
  required double offsetX,
  required double offsetY,
  required double cellSize,
  required List<List<double>> walls,
  double tolCm = 1.0,
}) {
  final (minB, maxB) = _roomSpan(axis, walls);
  final offset = axis == GuideAxis.horizontal ? offsetY : offsetX;
  final coord = offset + lineIndex * cellSize;
  return (coord - minB).abs() <= tolCm || (coord - maxB).abs() <= tolCm;
}

bool _guideLineIntersectsRoom({
  required GuideAxis axis,
  required int lineIndex,
  required double offsetX,
  required double offsetY,
  required double cellSize,
  required List<List<double>> walls,
}) {
  if (_guideLineOnRoomBoundary(
    axis: axis,
    lineIndex: lineIndex,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
    walls: walls,
  )) {
    // Perimeter is wall angle / edge — not a T-bar carrier line.
    return false;
  }
  final polygon = MaterialsCalculator.orderedPointsFromWalls(walls);
  if (polygon.length < 3) return false;
  final coord = axis == GuideAxis.horizontal
      ? offsetY + lineIndex * cellSize
      : offsetX + lineIndex * cellSize;
  final runs = axis == GuideAxis.horizontal
      ? roomHorizontalSegments(polygon, coord)
      : roomVerticalSegments(polygon, coord);
  return runs.any((r) => r.$2 - r.$1 > 1.0);
}

List<int> _gridLineIndicesInRoom({
  required GuideAxis axis,
  required double offsetX,
  required double offsetY,
  required double cellSize,
  required List<List<double>> walls,
}) {
  if (cellSize <= 0 || walls.isEmpty) return const [];
  final (minB, maxB) = _roomSpan(axis, walls);
  final offset = axis == GuideAxis.horizontal ? offsetY : offsetX;
  final i0 = ((minB - offset) / cellSize).floor() - 1;
  final i1 = ((maxB - offset) / cellSize).ceil() + 1;
  final out = <int>[];
  for (var i = i0; i <= i1; i++) {
    if (_guideLineIntersectsRoom(
      axis: axis,
      lineIndex: i,
      offsetX: offsetX,
      offsetY: offsetY,
      cellSize: cellSize,
      walls: walls,
    )) {
      out.add(i);
    }
  }
  return out;
}

/// Ceiling frame templates (T-bar / Grilyato carrier).
enum CeilingFrameTemplate {
  armstrong,
  grilyatoClassic,
  grilyatoGl;

  String get materialsLabel => switch (this) {
        armstrong => 'Армстронг',
        grilyatoClassic => 'Грильято',
        grilyatoGl => 'GL',
      };

  GuideKind get mainGuideKind => switch (this) {
        grilyatoClassic => GuideKind.g2400,
        _ => GuideKind.g3600,
      };

  bool get needsCellSize => this != armstrong;

  /// Main-runner pitch in 600 mm grid cells (always 1200 mm = 2 cells).
  /// Classic Grilyato uses the same carrier as Armstrong, with 2400 mains.
  int mainSpacingCells(String cellSize) => 2;

  String schemeHint(String cellSize) {
    switch (this) {
      case armstrong:
        return 'Несущие 3600 каждые 1200 мм, поперечные 1200 каждые 600 мм, '
            'промежуточные 600 — модуль 600×600.';
      case grilyatoGl:
        return 'Каркас как у Армстронга (3600 / 1200 / 600). '
            'Решётка: папа/мама 600 мм (×5/×7/×11 от кассет по ячейке $cellSize), '
            'L-профиль/заглушки = кассеты × 4.';
      case grilyatoClassic:
        return 'Каркас как у Армстронга, но несущие 2400 (шаг 1200 мм) + 1200 + 600. '
            'Решётка: папа/мама 600 мм (×5/×7/×11 от кассет по ячейке $cellSize), '
            'без L-профиля. Подвесы = 2400 × 3.';
    }
  }
}

/// Build full carrier frame from a seed main runner.
List<CeilingGuideMark> proposeCeilingFrame({
  required CeilingFrameTemplate template,
  required CeilingGuideMark seed,
  required double offsetX,
  required double offsetY,
  required double cellSize,
  required List<List<double>> walls,
  String cellSizeLabel = '100x100',
}) {
  final mainSpacing = template.mainSpacingCells(cellSizeLabel);
  if (cellSize <= 0 || mainSpacing < 1) return [seed];

  final mainKind = template.mainGuideKind;
  final mainAxis = seed.axis;
  final crossAxis =
      mainAxis == GuideAxis.horizontal ? GuideAxis.vertical : GuideAxis.horizontal;

  final mainLines = _gridLineIndicesInRoom(
    axis: mainAxis,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
    walls: walls,
  );
  final crossLines = _gridLineIndicesInRoom(
    axis: crossAxis,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
    walls: walls,
  );

  final byKey = <String, CeilingGuideMark>{};
  final anchor = seed.anchorAlongIndex;

  for (final i in mainLines) {
    final delta = i - seed.lineIndex;
    final isMain = delta % mainSpacing == 0;
    final mark = CeilingGuideMark(
      axis: mainAxis,
      lineIndex: i,
      kind: (mainSpacing == 1 || isMain) ? mainKind : GuideKind.g600,
      anchorAlongIndex: anchor,
    );
    byKey[mark.storageKey] = mark;
  }

  for (final j in crossLines) {
    final crossKind = mainSpacing == 1 ? GuideKind.g600 : GuideKind.g1200;
    final mark = CeilingGuideMark(
      axis: crossAxis,
      lineIndex: j,
      kind: crossKind,
      anchorAlongIndex: seed.lineIndex,
    );
    byKey[mark.storageKey] = mark;
  }

  // Seed line always carries the template main profile.
  byKey[seed.storageKey] = CeilingGuideMark(
    axis: seed.axis,
    lineIndex: seed.lineIndex,
    kind: mainKind,
    anchorAlongIndex: seed.anchorAlongIndex,
  );

  return byKey.values.toList();
}

/// Armstrong / T-bar frame from one main runner (3600).
List<CeilingGuideMark> proposeArmstrongFrame({
  required CeilingGuideMark seed,
  required double offsetX,
  required double offsetY,
  required double cellSize,
  required List<List<double>> walls,
  int mainSpacingCells = 2,
}) {
  return proposeCeilingFrame(
    template: CeilingFrameTemplate.armstrong,
    seed: seed,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
    walls: walls,
    cellSizeLabel: mainSpacingCells == 1 ? '50x50' : '100x100',
  );
}

CeilingGuideMark? findFrameSeed(
  Iterable<CeilingGuideMark> marks, {
  required CeilingFrameTemplate template,
}) {
  final prefer = template.mainGuideKind;
  for (final m in marks) {
    if (m.kind == prefer) return m;
  }
  for (final m in marks) {
    if (m.kind == GuideKind.g3600 || m.kind == GuideKind.g2400) return m;
  }
  return marks.isEmpty ? null : marks.first;
}

CeilingGuideMark? findArmstrongSeed(Iterable<CeilingGuideMark> marks) {
  return findFrameSeed(marks, template: CeilingFrameTemplate.armstrong);
}

/// Seed main runner near room centroid when nothing is placed yet.
CeilingGuideMark seedFrameAtRoomCenter({
  required CeilingFrameTemplate template,
  required double offsetX,
  required double offsetY,
  required double cellSize,
  required List<List<double>> walls,
}) {
  final (cx, cy) = roomCentroidCm(walls);
  final placement = snapGuidePlacement(
    worldX: cx,
    worldY: cy,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
    walls: walls,
    preferAxis: GuideAxis.horizontal,
  );
  return CeilingGuideMark(
    axis: placement.axis,
    lineIndex: placement.lineIndex,
    kind: template.mainGuideKind,
    anchorAlongIndex: placement.anchorIndex,
  );
}

int? lineIndexFromWorld({
  required String axis,
  required double world,
  required double offset,
  required double cellSize,
}) {
  if (cellSize <= 0) return null;
  return ((world - offset) / cellSize).round();
}

String? guideStorageKeyFromWorld({
  required String axis,
  required double world,
  required double offsetX,
  required double offsetY,
  required double cellSize,
}) {
  final offset = axis == 'h' ? offsetY : offsetX;
  final idx = lineIndexFromWorld(axis: axis, world: world, offset: offset, cellSize: cellSize);
  if (idx == null) return null;
  return '$axis:$idx';
}
