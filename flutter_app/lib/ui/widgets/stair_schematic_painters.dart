import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/finish_model.dart';
import '../../domain/special_space.dart';
import 'finish_painters.dart';

enum StairPreviewMode { elevation, plan, iso }

const _kAccent = Color(0xFFFFC857);
const _kFrame = Color(0xFF9AA8B8);
const _kStepFill = Color(0xFF4A6A88);
const _kLandingFill = Color(0xFF3D5A80);

String _fmtM(double cm) {
  final v = cm / 100;
  return v == v.roundToDouble()
      ? '${v.round()} м'
      : '${v.toStringAsFixed(1)} м';
}

String _fmtCm(double cm) {
  return cm == cm.roundToDouble()
      ? '${cm.round()} см'
      : '${cm.toStringAsFixed(0)} см';
}

void _dimText(
  Canvas canvas,
  Offset at,
  String text, {
  bool rotate = false,
  Color color = _kAccent,
  double fontSize = 11,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  canvas.save();
  canvas.translate(at.dx, at.dy);
  if (rotate) canvas.rotate(-math.pi / 2);
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();
}

/// Exterior dimension with ticks — stays outside [inner].
void _drawOutsideDim({
  required Canvas canvas,
  required Offset a,
  required Offset b,
  required String label,
  required Offset outward,
  bool rotateLabel = false,
}) {
  final len = (b - a).distance;
  if (len < 1) return;
  final u = (b - a) / len;
  final n = outward;
  final a1 = a + n;
  final b1 = b + n;
  final paint = Paint()
    ..color = _kAccent
    ..strokeWidth = 1.1;
  canvas.drawLine(a, a1, paint);
  canvas.drawLine(b, b1, paint);
  canvas.drawLine(a1, b1, paint);
  // ticks
  final tick = Offset(-u.dy, u.dx) * 4;
  canvas.drawLine(a1 - tick, a1 + tick, paint);
  canvas.drawLine(b1 - tick, b1 + tick, paint);
  _dimText(canvas, Offset((a1.dx + b1.dx) / 2, (a1.dy + b1.dy) / 2) + n * 0.35,
      label,
      rotate: rotateLabel);
}

/// Which shaft walls are counted in finish (matches [StairwellParams.finishSides]).
Set<int> stairFinishWallIndices(int finishSides) {
  final n = finishSides < 2 ? 2 : (finishSides > 4 ? 4 : finishSides);
  return switch (n) {
    2 => {1, 3}, // две длинные (Д)
    3 => {0, 1, 3}, // две Д + торец промежут. (Ш)
    _ => {0, 1, 2, 3},
  };
}

/// Top plan with landings, treads, openings and outer dims.
class StairPlanPainter extends CustomPainter {
  StairPlanPainter({
    required this.geometry,
    this.selectedOpeningIndex,
    this.finishSides = 4,
  });

  final StairSchematicGeometry geometry;
  final int? selectedOpeningIndex;
  final int finishSides;

  @override
  void paint(Canvas canvas, Size size) {
    final w = geometry.widthCm;
    final d = geometry.depthCm;
    if (w <= 0 || d <= 0) return;

    final hasOpeningDims = selectedOpeningIndex != null &&
        selectedOpeningIndex! >= 0 &&
        selectedOpeningIndex! < geometry.openings.length;
    final pad = hasOpeningDims ? 72.0 : 52.0;
    final s = math.min((size.width - pad * 2) / w, (size.height - pad * 2) / d);
    final ox = (size.width - w * s) / 2;
    final oy = (size.height - d * s) / 2;
    Offset map(double x, double y) => Offset(ox + x * s, oy + y * s);

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1A2330));

    for (final z in geometry.zones) {
      final path = Path();
      for (var i = 0; i < z.pointsCm.length; i++) {
        final p = map(z.pointsCm[i][0], z.pointsCm[i][1]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = switch (z.kind) {
            'landing' => _kLandingFill,
            'flight' => _kStepFill,
            'void' => const Color(0xFF0E1520),
            _ => const Color(0xFF2A3848),
          },
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = z.kind == 'landing' ? 1.8 : 1.0
          ..color = z.kind == 'landing' || z.kind == 'flight'
              ? _kAccent
              : _kFrame,
      );
    }

    final treadPaint = Paint()
      ..color = _kAccent.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (final t in geometry.treads) {
      canvas.drawLine(map(t.x0, t.y0), map(t.x1, t.y0), treadPaint);
    }

    // Cell walls: accent = under finish, muted = not finished
    final finished = stairFinishWallIndices(finishSides);
    void wallEdge(int wi, Offset a, Offset b) {
      final on = finished.contains(wi);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? 2.4 : 1.2
          ..color = on ? _kAccent : _kFrame.withValues(alpha: 0.55),
      );
    }

    wallEdge(0, map(0, 0), map(w, 0));
    wallEdge(1, map(w, 0), map(w, d));
    wallEdge(2, map(w, d), map(0, d));
    wallEdge(3, map(0, d), map(0, 0));

    _drawOpeningsPlan(canvas, map, s);
    _drawSelectedOpeningDimsPlan(canvas, map);

    _drawOutsideDim(
      canvas: canvas,
      a: map(0, 0),
      b: map(w, 0),
      label: 'Ш ${_fmtM(w)}',
      outward: const Offset(0, -18),
    );
    _drawOutsideDim(
      canvas: canvas,
      a: map(w, 0),
      b: map(w, d),
      label: 'Д ${_fmtM(d)}',
      outward: const Offset(18, 0),
      rotateLabel: true,
    );
    // Mid + bottom landing depths
    final mid = geometry.midLandingDepthCm;
    final bot = geometry.bottomLandingDepthCm;
    _drawOutsideDim(
      canvas: canvas,
      a: map(0, 0),
      b: map(0, mid),
      label: 'пл ${_fmtCm(mid)}',
      outward: const Offset(-22, 0),
      rotateLabel: true,
    );
    _drawOutsideDim(
      canvas: canvas,
      a: map(0, d - bot),
      b: map(0, d),
      label: 'пл ${_fmtCm(bot)}',
      outward: const Offset(-22, 0),
      rotateLabel: true,
    );
  }

  void _drawOpeningsPlan(
    Canvas canvas,
    Offset Function(double, double) map,
    double s,
  ) {
    final w = geometry.widthCm;
    final d = geometry.depthCm;
    final stroke = Paint()
      ..color = const Color(0xFF7EC8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    final fill = Paint()..color = const Color(0x667EC8FF);
    final inset = 10 / s; // cm → outward notch depth
    for (final o in geometry.openings) {
      final along = o.offsetAlongWallCm;
      final ww = o.widthCm;
      final wi = o.wallIndex < 0 ? 0 : (o.wallIndex > 3 ? 3 : o.wallIndex);
      late Offset a, b, aIn, bIn;
      switch (wi) {
        case 0: // y=0 → notch toward +y
          a = map(along, 0);
          b = map(along + ww, 0);
          aIn = map(along, inset);
          bIn = map(along + ww, inset);
        case 1: // x=w → notch toward −x
          a = map(w, along);
          b = map(w, along + ww);
          aIn = map(w - inset, along);
          bIn = map(w - inset, along + ww);
        case 2: // y=d → notch toward −y
          a = map(along, d);
          b = map(along + ww, d);
          aIn = map(along, d - inset);
          bIn = map(along + ww, d - inset);
        default: // x=0 → notch toward +x
          a = map(0, along);
          b = map(0, along + ww);
          aIn = map(inset, along);
          bIn = map(inset, along + ww);
      }
      final hole = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(aIn.dx, aIn.dy)
        ..lineTo(bIn.dx, bIn.dy)
        ..lineTo(b.dx, b.dy)
        ..close();
      canvas.drawPath(hole, fill);
      canvas.drawPath(hole, stroke);
    }
  }

  void _drawSelectedOpeningDimsPlan(
    Canvas canvas,
    Offset Function(double, double) map,
  ) {
    final i = selectedOpeningIndex;
    if (i == null || i < 0 || i >= geometry.openings.length) return;
    final o = geometry.openings[i];
    final wi = o.wallIndex < 0 ? 0 : (o.wallIndex > 3 ? 3 : o.wallIndex);
    final wallLen = stairWallLengthCm(geometry, wi);
    final start = o.offsetAlongWallCm < 0
        ? 0.0
        : (o.offsetAlongWallCm > wallLen ? wallLen : o.offsetAlongWallCm);
    final endRaw = start + o.widthCm;
    final end = endRaw > wallLen ? wallLen : endRaw;
    final left = start;
    final mid = end - start;
    final right = wallLen - end;
    final w = geometry.widthCm;
    final d = geometry.depthCm;

    // Same style as Ш/Д: outside the cell, yellow ticks + label.
    // Further out than overall Ш/Д so chains don't overlap.
    late Offset outward;
    late bool rotate;
    late Offset Function(double t) alongWall; // t = cm along wall from 0
    switch (wi) {
      case 0: // y=0, along +X — outside up
        outward = const Offset(0, -36);
        rotate = false;
        alongWall = (t) => map(t, 0);
      case 1: // x=w, along +Y — outside right
        outward = const Offset(36, 0);
        rotate = true;
        alongWall = (t) => map(w, t);
      case 2: // y=d, along +X — outside down
        outward = const Offset(0, 36);
        rotate = false;
        alongWall = (t) => map(t, d);
      default: // x=0, along +Y — outside left
        outward = const Offset(-36, 0);
        rotate = true;
        alongWall = (t) => map(0, t);
    }

    void seg(double t0, double t1, String label) {
      if (t1 - t0 < 1.5) return;
      _drawOutsideDim(
        canvas: canvas,
        a: alongWall(t0),
        b: alongWall(t1),
        label: label,
        outward: outward,
        rotateLabel: rotate,
      );
    }

    // Edge → opening → edge (как цепочка размеров стены)
    seg(0, left, _fmtCm(left));
    seg(left, end, _fmtCm(mid));
    seg(end, wallLen, _fmtCm(right));
  }

  @override
  bool shouldRepaint(covariant StairPlanPainter old) =>
      old.geometry != geometry ||
      old.selectedOpeningIndex != selectedOpeningIndex ||
      old.finishSides != finishSides;
}

/// Side section: both flights yellow; frame gray; thick landings; outer dims.
class StairElevationPainter extends CustomPainter {
  StairElevationPainter({
    required this.geometry,
    this.selectedOpeningIndex,
  });

  final StairSchematicGeometry geometry;
  final int? selectedOpeningIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final d = geometry.depthCm;
    final h = geometry.heightCm;
    if (d <= 0 || h <= 0) return;

    const padL = 52.0;
    const padR = 36.0;
    const padT = 36.0;
    const padB = 44.0;
    final drawW = size.width - padL - padR;
    final drawH = size.height - padT - padB;
    final s = math.min(drawW / d, drawH / h);
    final ox = padL + (drawW - d * s) / 2;
    final oy = padT + drawH;
    Offset map(double y, double z) => Offset(ox + y * s, oy - z * s);

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1A2330));

    // Cell frame — neutral
    final cell = Rect.fromPoints(map(0, 0), map(d, h));
    canvas.drawRect(cell, Paint()..color = const Color(0xFF222C3A));
    canvas.drawRect(
      cell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _kFrame,
    );

    // Landing slabs — fill thickness, accent only on top (no internal mid-line)
    final landEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _kAccent;
    for (final L in geometry.landings) {
      final body = Rect.fromPoints(map(L.y0, L.zTop), map(L.y1, L.zUnder));
      canvas.drawRect(body, Paint()..color = _kLandingFill);
      canvas.drawLine(map(L.y0, L.zTop), map(L.y1, L.zTop), landEdge);
      canvas.drawLine(map(L.y0, L.zTop), map(L.y0, L.zUnder), landEdge);
      canvas.drawLine(map(L.y1, L.zTop), map(L.y1, L.zUnder), landEdge);
    }

    // Step volumes: solid fill only; one yellow nosing silhouette (no double edges)
    final treadFill = Paint()..color = _kStepFill;
    for (final t in geometry.treads) {
      final y0 = math.min(t.y0, t.y1);
      final y1 = math.max(t.y0, t.y1);
      final block = Rect.fromPoints(map(y0, t.zTop), map(y1, t.zBottom));
      canvas.drawRect(block, treadFill);
    }

    void drawNosings(List<List<double>> pts) {
      if (pts.length < 2) return;
      final edge = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = map(pts[i][0], pts[i][1]);
        if (i == 0) {
          edge.moveTo(o.dx, o.dy);
        } else {
          edge.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.miter
          ..color = _kAccent,
      );
    }

    drawNosings(geometry.elevationLower);
    drawNosings(geometry.elevationUpper);

    // Openings: long walls (1/3) as face rects in Д×В; end walls (0/2) as edge marks
    final opStroke = Paint()
      ..color = const Color(0xFF7EC8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final opFill = Paint()..color = const Color(0x557EC8FF);
    for (final o in geometry.openings) {
      final wi = o.wallIndex < 0 ? 0 : (o.wallIndex > 3 ? 3 : o.wallIndex);
      final z0 = o.sillCm;
      final z1 = o.sillCm + o.heightCm;
      if (wi == 1 || wi == 3) {
        final y0 = o.offsetAlongWallCm;
        final y1 = o.offsetAlongWallCm + o.widthCm;
        final r = Rect.fromPoints(map(y0, z0), map(y1, z1));
        canvas.drawRect(r, opFill);
        canvas.drawRect(r, opStroke);
        // door swing hint
        canvas.drawLine(map(y0, z0), map((y0 + y1) / 2, z1), opStroke);
      } else {
        final y = wi == 0 ? 0.0 : d;
        canvas.drawRect(
          Rect.fromPoints(map(y - 4 / s, z0), map(y + 4 / s, z1)),
          opFill,
        );
        canvas.drawRect(
          Rect.fromPoints(map(y - 4 / s, z0), map(y + 4 / s, z1)),
          opStroke,
        );
      }
    }

    // Outer dims — outside the cell
    _drawOutsideDim(
      canvas: canvas,
      a: map(0, 0),
      b: map(0, h),
      label: 'В ${_fmtM(h)}',
      outward: const Offset(-20, 0),
      rotateLabel: true,
    );
    _drawOutsideDim(
      canvas: canvas,
      a: map(0, 0),
      b: map(d, 0),
      label: 'Д ${_fmtM(d)}',
      outward: const Offset(0, 20),
    );
    final mid = geometry.midLandingDepthCm;
    final bot = geometry.bottomLandingDepthCm;
    _drawOutsideDim(
      canvas: canvas,
      a: map(0, h),
      b: map(mid, h),
      label: 'пл ${_fmtCm(mid)}',
      outward: const Offset(0, -16),
    );
    _drawOutsideDim(
      canvas: canvas,
      a: map(d - bot, h),
      b: map(d, h),
      label: 'пл ${_fmtCm(bot)}',
      outward: const Offset(0, -16),
    );
  }

  @override
  bool shouldRepaint(covariant StairElevationPainter old) =>
      old.geometry != geometry ||
      old.selectedOpeningIndex != selectedOpeningIndex;
}

class StairIsometricPainter extends CustomPainter {
  StairIsometricPainter({
    required this.geometry,
    required this.shell,
    this.yaw = 0.62,
    this.pitch = 0.38,
    this.zoom = 1.0,
    this.selectedOpeningIndex,
  });

  final StairSchematicGeometry geometry;
  final RoomShell3D shell;
  final double yaw;
  final double pitch;
  final double zoom;
  final int? selectedOpeningIndex;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1A2330));
    final (minX, maxX, minY, maxY) = shell.bounds2d;
    final h = shell.heightCm;

    Offset iso(double x, double y, double z) {
      final p = IsometricShellPainter.projectIso(
        x: x,
        y: y,
        z: z,
        size: size,
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        heightCm: h,
        yaw: yaw,
        pitch: pitch,
      );
      final c = Offset(size.width / 2, size.height / 2);
      return c + (p - c) * zoom;
    }

    final floor = Path()
      ..moveTo(iso(0, 0, 0).dx, iso(0, 0, 0).dy)
      ..lineTo(iso(geometry.widthCm, 0, 0).dx, iso(geometry.widthCm, 0, 0).dy)
      ..lineTo(
        iso(geometry.widthCm, geometry.depthCm, 0).dx,
        iso(geometry.widthCm, geometry.depthCm, 0).dy,
      )
      ..lineTo(iso(0, geometry.depthCm, 0).dx, iso(0, geometry.depthCm, 0).dy)
      ..close();
    canvas.drawPath(floor, Paint()..color = const Color(0xFF2A3848));
    canvas.drawPath(
      floor,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _kFrame
        ..strokeWidth = 1.3,
    );

    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..color = _kFrame.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    void edge(double ax, double ay, double bx, double by) {
      canvas.drawLine(iso(ax, ay, 0), iso(bx, by, 0), wire);
      canvas.drawLine(iso(bx, by, 0), iso(bx, by, h), wire);
      canvas.drawLine(iso(bx, by, h), iso(ax, ay, h), wire);
      canvas.drawLine(iso(ax, ay, h), iso(ax, ay, 0), wire);
    }

    edge(0, 0, geometry.widthCm, 0);
    edge(geometry.widthCm, 0, geometry.widthCm, geometry.depthCm);
    edge(geometry.widthCm, geometry.depthCm, 0, geometry.depthCm);
    edge(0, geometry.depthCm, 0, 0);

    for (final L in geometry.landings) {
      _box(
        canvas,
        iso,
        L.x0,
        L.x1,
        L.y0,
        L.y1,
        L.zUnder,
        L.zTop,
        fill: _kLandingFill,
        stroke: _kAccent,
      );
    }

    final sorted = List<StairTread3D>.from(geometry.treads)
      ..sort((a, b) => a.zTop.compareTo(b.zTop));
    for (final t in sorted) {
      // Volumetric tread slab
      _box(
        canvas,
        iso,
        t.x0,
        t.x1,
        math.min(t.y0, t.y1),
        math.max(t.y0, t.y1),
        t.zUnder,
        t.zTop,
        fill: _kStepFill,
        stroke: _kAccent,
      );
      // Riser face at the lower edge of the tread (ascent nose)
      final yNose = t.y0 <= t.y1 ? t.y0 : t.y1;
      final riser = Path()
        ..moveTo(iso(t.x0, yNose, t.zBottom).dx, iso(t.x0, yNose, t.zBottom).dy)
        ..lineTo(iso(t.x1, yNose, t.zBottom).dx, iso(t.x1, yNose, t.zBottom).dy)
        ..lineTo(iso(t.x1, yNose, t.zTop).dx, iso(t.x1, yNose, t.zTop).dy)
        ..lineTo(iso(t.x0, yNose, t.zTop).dx, iso(t.x0, yNose, t.zTop).dy)
        ..close();
      canvas.drawPath(riser, Paint()..color = const Color(0xFF3A5570));
      canvas.drawPath(
        riser,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _kAccent
          ..strokeWidth = 0.9,
      );
    }

    _drawOpeningsIso(canvas, iso);
    _drawSelectedOpeningDimsIso(canvas, iso);

    _dimText(canvas, iso(geometry.widthCm / 2, -24, 0), 'Ш ${_fmtM(geometry.widthCm)}');
    _dimText(
      canvas,
      iso(geometry.widthCm + 24, geometry.depthCm / 2, 0),
      'Д ${_fmtM(geometry.depthCm)}',
    );
    _dimText(
      canvas,
      iso(-28, 0, geometry.heightCm / 2),
      'В ${_fmtM(geometry.heightCm)}',
      rotate: true,
    );
  }

  void _drawOpeningsIso(
    Canvas canvas,
    Offset Function(double, double, double) iso,
  ) {
    final w = geometry.widthCm;
    final d = geometry.depthCm;

    Path quad(List<(double, double, double)> pts) {
      final p = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = iso(pts[i].$1, pts[i].$2, pts[i].$3);
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      p.close();
      return p;
    }

    for (var i = 0; i < geometry.openings.length; i++) {
      final o = geometry.openings[i];
      final selected = i == selectedOpeningIndex;
      final stroke = Paint()
        ..color = selected ? _kAccent : const Color(0xFF7EC8FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.4 : 1.6;
      final fill = Paint()
        ..color = selected ? const Color(0x99FFC857) : const Color(0x667EC8FF);
      final wi = o.wallIndex < 0 ? 0 : (o.wallIndex > 3 ? 3 : o.wallIndex);
      final a = o.offsetAlongWallCm;
      final b = o.offsetAlongWallCm + o.widthCm;
      final z0 = o.sillCm;
      final z1 = o.sillCm + o.heightCm;
      final Path hole;
      switch (wi) {
        case 0:
          hole = quad([(a, 0, z0), (b, 0, z0), (b, 0, z1), (a, 0, z1)]);
        case 1:
          hole = quad([(w, a, z0), (w, b, z0), (w, b, z1), (w, a, z1)]);
        case 2:
          hole = quad([(a, d, z0), (b, d, z0), (b, d, z1), (a, d, z1)]);
        default:
          hole = quad([(0, a, z0), (0, b, z0), (0, b, z1), (0, a, z1)]);
      }
      canvas.drawPath(hole, fill);
      canvas.drawPath(hole, stroke);
    }
  }

  /// Edge → door → edge dims on the wall in 3D (same idea as plan Ш/Д ticks).
  void _drawSelectedOpeningDimsIso(
    Canvas canvas,
    Offset Function(double, double, double) iso,
  ) {
    final i = selectedOpeningIndex;
    if (i == null || i < 0 || i >= geometry.openings.length) return;
    final o = geometry.openings[i];
    final wi = o.wallIndex < 0 ? 0 : (o.wallIndex > 3 ? 3 : o.wallIndex);
    final wallLen = stairWallLengthCm(geometry, wi);
    final start = o.offsetAlongWallCm < 0
        ? 0.0
        : (o.offsetAlongWallCm > wallLen ? wallLen : o.offsetAlongWallCm);
    final endRaw = start + o.widthCm;
    final end = endRaw > wallLen ? wallLen : endRaw;
    final w = geometry.widthCm;
    final d = geometry.depthCm;
    // Dim line just above the door head so it sits on the model face.
    final z = o.sillCm + o.heightCm + 8;

    Offset along(double t) {
      switch (wi) {
        case 0:
          return iso(t, 0, z);
        case 1:
          return iso(w, t, z);
        case 2:
          return iso(t, d, z);
        default:
          return iso(0, t, z);
      }
    }

    final roomCenter = iso(w / 2, d / 2, z);

    void seg(double t0, double t1, String label) {
      if (t1 - t0 < 1.5) return;
      final a = along(t0);
      final b = along(t1);
      final dir = b - a;
      final len = dir.distance;
      if (len < 2) return;
      final u = dir / len;
      var n = Offset(-u.dy, u.dx);
      final nLen = n.distance;
      if (nLen < 1e-6) return;
      n = n / nLen;
      // Push label away from shaft center (outside the wall).
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      if ((mid + n * 24 - roomCenter).distance <
          (mid - n * 24 - roomCenter).distance) {
        n = -n;
      }
      _drawOutsideDim(
        canvas: canvas,
        a: a,
        b: b,
        label: label,
        outward: n * 28,
      );
    }

    seg(0, start, _fmtCm(start));
    seg(start, end, _fmtCm(end - start));
    seg(end, wallLen, _fmtCm(wallLen - end));
  }

  void _box(
    Canvas canvas,
    Offset Function(double, double, double) iso,
    double x0,
    double x1,
    double y0,
    double y1,
    double z0,
    double z1, {
    required Color fill,
    required Color stroke,
  }) {
    Path face(List<(double, double, double)> pts) {
      final p = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = iso(pts[i].$1, pts[i].$2, pts[i].$3);
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      p.close();
      return p;
    }

    final side = face([
      (x1, y0, z0),
      (x1, y1, z0),
      (x1, y1, z1),
      (x1, y0, z1),
    ]);
    canvas.drawPath(side, Paint()..color = const Color(0xFF2E4558));
    canvas.drawPath(
      side,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = stroke
        ..strokeWidth = 0.9,
    );

    final front = face([
      (x0, y0, z0),
      (x1, y0, z0),
      (x1, y0, z1),
      (x0, y0, z1),
    ]);
    canvas.drawPath(front, Paint()..color = const Color(0xFF3A5570));
    canvas.drawPath(
      front,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = stroke
        ..strokeWidth = 0.9,
    );

    final top = face([
      (x0, y0, z1),
      (x1, y0, z1),
      (x1, y1, z1),
      (x0, y1, z1),
    ]);
    canvas.drawPath(top, Paint()..color = fill);
    canvas.drawPath(
      top,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = stroke
        ..strokeWidth = 1.1,
    );
  }

  @override
  bool shouldRepaint(covariant StairIsometricPainter old) =>
      old.geometry != geometry ||
      old.shell != shell ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.selectedOpeningIndex != selectedOpeningIndex;
}

/// Hit result for long-press / drag on a wall.
class StairWallHit {
  const StairWallHit({
    required this.wallIndex,
    required this.offsetAlongWallCm,
  });
  final int wallIndex;

  /// Start of opening along the wall (cm), or finger position when placing.
  final double offsetAlongWallCm;
}

double stairWallLengthCm(StairSchematicGeometry g, int wallIndex) {
  final wi = wallIndex < 0 ? 0 : (wallIndex > 3 ? 3 : wallIndex);
  return (wi == 0 || wi == 2) ? g.widthCm : g.depthCm;
}

/// Geometric center of the wall as opening **start** for [openingWidthCm].
double centeredOpeningStartCm(
  StairSchematicGeometry g,
  int wallIndex,
  double openingWidthCm,
) {
  final len = stairWallLengthCm(g, wallIndex);
  final maxStart = math.max(0.0, len - openingWidthCm);
  final mid = (len - openingWidthCm) / 2;
  if (mid < 0) return 0;
  if (mid > maxStart) return maxStart;
  return mid;
}

double clampOpeningStartCm({
  required double start,
  required double wallLen,
  required double openingWidth,
}) {
  final maxStart = math.max(0.0, wallLen - openingWidth);
  if (start < 0) return 0;
  if (start > maxStart) return maxStart;
  return start;
}

(double ox, double oy, double s) _planMapParams(Size size, StairSchematicGeometry g) {
  const pad = 48.0;
  final s = math.min(
    (size.width - pad * 2) / g.widthCm,
    (size.height - pad * 2) / g.depthCm,
  );
  final ox = (size.width - g.widthCm * s) / 2;
  final oy = (size.height - g.depthCm * s) / 2;
  return (ox, oy, s);
}

(double ox, double oy, double s) _elevMapParams(Size size, StairSchematicGeometry g) {
  const padL = 52.0;
  const padR = 36.0;
  const padT = 36.0;
  const padB = 44.0;
  final drawW = size.width - padL - padR;
  final drawH = size.height - padT - padB;
  final s = math.min(drawW / g.depthCm, drawH / g.heightCm);
  final ox = padL + (drawW - g.depthCm * s) / 2;
  final oy = padT + drawH;
  return (ox, oy, s);
}

/// Plan hit-test (local coords of the 900×700 paint child).
StairWallHit? hitStairPlanWall(
  Offset local,
  Size size,
  StairSchematicGeometry g, {
  double maxDistPx = 36,
}) {
  final w = g.widthCm;
  final d = g.depthCm;
  if (w <= 0 || d <= 0) return null;
  final (ox, oy, s) = _planMapParams(size, g);
  final x = (local.dx - ox) / s;
  final y = (local.dy - oy) / s;
  final candidates = <(int, double, double)>[
    (0, y.abs() * s, x),
    (1, (x - w).abs() * s, y),
    (2, (y - d).abs() * s, x),
    (3, x.abs() * s, y),
  ];
  candidates.sort((a, b) => a.$2.compareTo(b.$2));
  final best = candidates.first;
  if (best.$2 > maxDistPx) return null;
  final wallLen = stairWallLengthCm(g, best.$1);
  final along = best.$3 < 0
      ? 0.0
      : (best.$3 > wallLen ? wallLen : best.$3);
  return StairWallHit(wallIndex: best.$1, offsetAlongWallCm: along);
}

/// Elevation: face taps → long walls (1/3); near vertical edges → ends (0/2).
StairWallHit? hitStairElevationWall(
  Offset local,
  Size size,
  StairSchematicGeometry g, {
  double maxDistPx = 40,
}) {
  final d = g.depthCm;
  final h = g.heightCm;
  if (d <= 0 || h <= 0) return null;
  final (ox, oy, s) = _elevMapParams(size, g);
  final yCm = (local.dx - ox) / s;
  final zCm = (oy - local.dy) / s;
  if (zCm < -30 || zCm > h + 30) return null;
  if (yCm < -30 || yCm > d + 30) return null;

  final dist0 = yCm.abs() * s;
  final dist2 = (yCm - d).abs() * s;
  final edgePx = math.max(maxDistPx, 22.0);

  if (dist0 <= edgePx && dist0 <= dist2) {
    // End wall at y=0 — along = width center (Ш)
    return StairWallHit(
      wallIndex: 0,
      offsetAlongWallCm: g.widthCm / 2,
    );
  }
  if (dist2 <= edgePx) {
    return StairWallHit(
      wallIndex: 2,
      offsetAlongWallCm: g.widthCm / 2,
    );
  }
  // Interior of side view = long wall (along Д). Prefer wall 3 (лев.).
  final along = yCm < 0 ? 0.0 : (yCm > d ? d : yCm);
  return StairWallHit(wallIndex: 3, offsetAlongWallCm: along);
}

/// 3D: nearest projected wall segment at mid-height (respects yaw/pitch/zoom).
StairWallHit? hitStairIsoWall(
  Offset local,
  Size size,
  StairSchematicGeometry g, {
  required double yaw,
  required double pitch,
  required double zoom,
  double maxDistPx = 48,
}) {
  final w = g.widthCm;
  final d = g.depthCm;
  final h = g.heightCm;
  if (w <= 0 || d <= 0 || h <= 0) return null;

  final shell = RoomShell3D(
    floorPolygonCm: [
      Offset.zero,
      Offset(w, 0),
      Offset(w, d),
      Offset(0, d),
    ],
    heightCm: h,
  );
  final (minX, maxX, minY, maxY) = shell.bounds2d;
  Offset iso(double x, double y, double z) {
    final p = IsometricShellPainter.projectIso(
      x: x,
      y: y,
      z: z,
      size: size,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      heightCm: h,
      yaw: yaw,
      pitch: pitch,
    );
    final c = Offset(size.width / 2, size.height / 2);
    return c + (p - c) * zoom;
  }

  final zMid = h * 0.45;
  // Segments oriented so t=0 matches opening offsetAlong=0 (same as plan drawing).
  final segs = <(int, Offset, Offset, double)>[
    (0, iso(0, 0, zMid), iso(w, 0, zMid), w), // along +X
    (1, iso(w, 0, zMid), iso(w, d, zMid), d), // along +Y
    (2, iso(0, d, zMid), iso(w, d, zMid), w), // along +X (was inverted)
    (3, iso(0, 0, zMid), iso(0, d, zMid), d), // along +Y (was inverted)
  ];

  var bestI = -1;
  var bestDist = maxDistPx;
  var bestAlong = 0.0;
  for (final (wi, a, b, lenCm) in segs) {
    final ab = b - a;
    final abLen2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLen2 < 1) continue;
    final t = ((local.dx - a.dx) * ab.dx + (local.dy - a.dy) * ab.dy) / abLen2;
    final tc = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
    final proj = Offset(a.dx + ab.dx * tc, a.dy + ab.dy * tc);
    final dist = (local - proj).distance;
    if (dist < bestDist) {
      bestDist = dist;
      bestI = wi;
      bestAlong = tc * lenCm;
    }
  }
  if (bestI < 0) return null;
  return StairWallHit(wallIndex: bestI, offsetAlongWallCm: bestAlong);
}

int? hitStairOpeningIndex(
  Offset local,
  Size size,
  StairSchematicGeometry g,
  StairPreviewMode mode, {
  double yaw = 0.62,
  double pitch = 0.38,
  double zoom = 1.0,
  double maxDistPx = 40,
}) {
  var bestI = -1;
  var bestD = maxDistPx;
  for (var i = 0; i < g.openings.length; i++) {
    final o = g.openings[i];
    final midAlong = o.offsetAlongWallCm + o.widthCm / 2;
    final Offset screen;
    switch (mode) {
      case StairPreviewMode.plan:
        final (ox, oy, s) = _planMapParams(size, g);
        final w = g.widthCm;
        final d = g.depthCm;
        final wi = o.wallIndex < 0 ? 0 : (o.wallIndex > 3 ? 3 : o.wallIndex);
        late double x, y;
        switch (wi) {
          case 0:
            x = midAlong;
            y = 0;
          case 1:
            x = w;
            y = midAlong;
          case 2:
            x = midAlong;
            y = d;
          default:
            x = 0;
            y = midAlong;
        }
        screen = Offset(ox + x * s, oy + y * s);
      case StairPreviewMode.elevation:
        final (ox, oy, s) = _elevMapParams(size, g);
        final wi = o.wallIndex < 0 ? 0 : (o.wallIndex > 3 ? 3 : o.wallIndex);
        final z = o.sillCm + o.heightCm / 2;
        if (wi == 0 || wi == 2) {
          final y = wi == 0 ? 0.0 : g.depthCm;
          screen = Offset(ox + y * s, oy - z * s);
        } else {
          screen = Offset(ox + midAlong * s, oy - z * s);
        }
      case StairPreviewMode.iso:
        // Project door center onto screen with same iso as the painter.
        final shell = RoomShell3D(
          floorPolygonCm: [
            Offset.zero,
            Offset(g.widthCm, 0),
            Offset(g.widthCm, g.depthCm),
            Offset(0, g.depthCm),
          ],
          heightCm: g.heightCm,
        );
        final (minX, maxX, minY, maxY) = shell.bounds2d;
        final wi = o.wallIndex < 0 ? 0 : (o.wallIndex > 3 ? 3 : o.wallIndex);
        final z = o.sillCm + o.heightCm / 2;
        late double ox3, oy3;
        switch (wi) {
          case 0:
            ox3 = midAlong;
            oy3 = 0;
          case 1:
            ox3 = g.widthCm;
            oy3 = midAlong;
          case 2:
            ox3 = midAlong;
            oy3 = g.depthCm;
          default:
            ox3 = 0;
            oy3 = midAlong;
        }
        final p = IsometricShellPainter.projectIso(
          x: ox3,
          y: oy3,
          z: z,
          size: size,
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          heightCm: g.heightCm,
          yaw: yaw,
          pitch: pitch,
        );
        final c = Offset(size.width / 2, size.height / 2);
        screen = c + (p - c) * zoom;
    }
    final dist = (local - screen).distance;
    if (dist < bestD) {
      bestD = dist;
      bestI = i;
    }
  }
  return bestI >= 0 ? bestI : null;
}

class StairSchematicPreview extends StatefulWidget {
  const StairSchematicPreview({
    super.key,
    required this.geometry,
    this.onWallLongPress,
    this.selectedOpeningIndex,
    this.onSelectOpening,
    this.onMoveOpening,
    this.finishSides = 4,
  });

  final StairSchematicGeometry? geometry;

  /// Long-press empty wall → add opening (wall from hit; offset ignored — center).
  final void Function(StairWallHit hit)? onWallLongPress;

  final int? selectedOpeningIndex;
  final ValueChanged<int>? onSelectOpening;

  /// Drag selected opening to a new wall position (start along wall).
  final void Function(int index, StairWallHit hit)? onMoveOpening;

  /// How many shaft walls go into finish m² (highlighted on plan).
  final int finishSides;

  @override
  State<StairSchematicPreview> createState() => _StairSchematicPreviewState();
}

class _StairSchematicPreviewState extends State<StairSchematicPreview> {
  StairPreviewMode _mode = StairPreviewMode.plan;
  double _yaw = 0.62;
  double _pitch = 0.38;
  double _isoZoom = 1.0;
  double _baseIsoZoom = 1.0;
  bool _draggingOpening = false;
  int? _dragWallSticky;
  double? _smoothedAlong;

  /// Opening edit gestures only on plan / 3D — not on side elevation.
  bool get _openingsInteractive => _mode != StairPreviewMode.elevation;

  StairWallHit? _hitWall(Offset local, Size size, StairSchematicGeometry g) {
    return switch (_mode) {
      StairPreviewMode.plan => hitStairPlanWall(local, size, g),
      StairPreviewMode.elevation => null,
      StairPreviewMode.iso => hitStairIsoWall(
          local,
          size,
          g,
          yaw: _yaw,
          pitch: _pitch,
          zoom: _isoZoom,
        ),
    };
  }

  void _handleLongPress(Offset local, Size size, StairSchematicGeometry g) {
    if (!_openingsInteractive) return;
    final openingI = hitStairOpeningIndex(
      local,
      size,
      g,
      _mode,
      yaw: _yaw,
      pitch: _pitch,
      zoom: _isoZoom,
    );
    if (openingI != null) {
      widget.onSelectOpening?.call(openingI);
      final o = g.openings[openingI];
      setState(() {
        _draggingOpening = true;
        _dragWallSticky = o.wallIndex;
        _smoothedAlong = o.offsetAlongWallCm + o.widthCm / 2;
      });
      return;
    }
    final hit = _hitWall(local, size, g);
    if (hit != null) widget.onWallLongPress?.call(hit);
  }

  void _handlePanUpdate(Offset local, Size size, StairSchematicGeometry g) {
    final sel = widget.selectedOpeningIndex;
    if (!_openingsInteractive ||
        !_draggingOpening ||
        sel == null ||
        widget.onMoveOpening == null) {
      return;
    }
    final o = g.openings[sel];
    final sticky = _dragWallSticky ?? o.wallIndex;

    // Prefer staying on the same wall; switch only if another is clearly nearer.
    var wall = sticky;
    var alongCenter = _projectAlongWall(local, size, g, sticky);
    final nearest = _hitWall(local, size, g);
    if (nearest != null && nearest.wallIndex != sticky) {
      final distSticky = _distToWallPx(local, size, g, sticky);
      final distOther = _distToWallPx(local, size, g, nearest.wallIndex);
      if (distOther + 22 < distSticky) {
        wall = nearest.wallIndex;
        alongCenter = nearest.offsetAlongWallCm;
      }
    }
    _dragWallSticky = wall;

    // EMA along the wall — softer motion.
    final prev = _smoothedAlong;
    final smoothed =
        prev == null ? alongCenter : (prev * 0.72 + alongCenter * 0.28);
    _smoothedAlong = smoothed;

    final wallLen = stairWallLengthCm(g, wall);
    final start = clampOpeningStartCm(
      start: smoothed - o.widthCm / 2,
      wallLen: wallLen,
      openingWidth: o.widthCm,
    );
    widget.onMoveOpening!(
      sel,
      StairWallHit(wallIndex: wall, offsetAlongWallCm: start),
    );
  }

  double _projectAlongWall(
    Offset local,
    Size size,
    StairSchematicGeometry g,
    int wallIndex,
  ) {
    if (_mode == StairPreviewMode.plan) {
      final (ox, oy, s) = _planMapParams(size, g);
      final x = (local.dx - ox) / s;
      final y = (local.dy - oy) / s;
      final along = (wallIndex == 0 || wallIndex == 2) ? x : y;
      final len = stairWallLengthCm(g, wallIndex);
      if (along < 0) return 0;
      if (along > len) return len;
      return along;
    }
    final hit = hitStairIsoWall(
      local,
      size,
      g,
      yaw: _yaw,
      pitch: _pitch,
      zoom: _isoZoom,
      maxDistPx: 120,
    );
    if (hit != null && hit.wallIndex == wallIndex) {
      return hit.offsetAlongWallCm;
    }
    return _smoothedAlong ?? stairWallLengthCm(g, wallIndex) / 2;
  }

  double _distToWallPx(
    Offset local,
    Size size,
    StairSchematicGeometry g,
    int wallIndex,
  ) {
    if (_mode == StairPreviewMode.plan) {
      final (ox, oy, s) = _planMapParams(size, g);
      final x = (local.dx - ox) / s;
      final y = (local.dy - oy) / s;
      final w = g.widthCm;
      final d = g.depthCm;
      return switch (wallIndex) {
        0 => y.abs() * s,
        1 => (x - w).abs() * s,
        2 => (y - d).abs() * s,
        _ => x.abs() * s,
      };
    }
    final hit = hitStairIsoWall(
      local,
      size,
      g,
      yaw: _yaw,
      pitch: _pitch,
      zoom: _isoZoom,
      maxDistPx: 200,
    );
    if (hit != null && hit.wallIndex == wallIndex) return 10;
    return 90;
  }

  void _endDrag() {
    setState(() {
      _draggingOpening = false;
      _dragWallSticky = null;
      _smoothedAlong = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = widget.geometry;

    return Material(
      color: const Color(0xFF121820),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              children: [
                Flexible(
                  child: SegmentedButton<StairPreviewMode>(
                    segments: const [
                      ButtonSegment(
                        value: StairPreviewMode.elevation,
                        label: Text('Бок'),
                      ),
                      ButtonSegment(
                        value: StairPreviewMode.plan,
                        label: Text('План'),
                      ),
                      ButtonSegment(
                        value: StairPreviewMode.iso,
                        label: Text('3D'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                if (_mode == StairPreviewMode.iso) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Мельче',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      final z = _isoZoom / 1.2;
                      _isoZoom = z < 0.45 ? 0.45 : z;
                    }),
                    icon: const Icon(Icons.remove, size: 18),
                  ),
                  Text(
                    '${(_isoZoom * 100).round()}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Крупнее',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      final z = _isoZoom * 1.2;
                      _isoZoom = z > 4.0 ? 4.0 : z;
                    }),
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: g == null
                ? Center(
                    child: Text(
                      'Введите Ш и Д',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : _mode == StairPreviewMode.iso
                    ? _buildIso(g)
                    : _build2d(g),
          ),
        ],
      ),
    );
  }

  Widget _build2d(StairSchematicGeometry g) {
    const paintSize = Size(900, 700);
    final interactive = _openingsInteractive;
    return InteractiveViewer(
      key: ValueKey(_mode),
      minScale: 0.4,
      maxScale: 6,
      panEnabled: !_draggingOpening,
      scaleEnabled: !_draggingOpening,
      boundaryMargin: const EdgeInsets.all(200),
      child: SizedBox(
        width: paintSize.width,
        height: paintSize.height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: interactive
              ? (d) {
                  final i = hitStairOpeningIndex(
                    d.localPosition,
                    paintSize,
                    g,
                    _mode,
                  );
                  if (i != null) widget.onSelectOpening?.call(i);
                }
              : null,
          onLongPressStart: interactive
              ? (d) => _handleLongPress(d.localPosition, paintSize, g)
              : null,
          onLongPressMoveUpdate: interactive && _draggingOpening
              ? (d) => _handlePanUpdate(d.localPosition, paintSize, g)
              : null,
          onLongPressEnd: interactive ? (_) => _endDrag() : null,
          onPanUpdate: interactive && _draggingOpening
              ? (d) => _handlePanUpdate(d.localPosition, paintSize, g)
              : null,
          onPanEnd: interactive ? (_) => _endDrag() : null,
          child: CustomPaint(
            painter: _mode == StairPreviewMode.elevation
                ? StairElevationPainter(geometry: g)
                : StairPlanPainter(
                    geometry: g,
                    // Dims only while dragging an opening to move it.
                    selectedOpeningIndex:
                        _draggingOpening ? widget.selectedOpeningIndex : null,
                    finishSides: widget.finishSides,
                  ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Widget _buildIso(StairSchematicGeometry g) {
    final shell = RoomShell3D(
      floorPolygonCm: [
        Offset.zero,
        Offset(g.widthCm, 0),
        Offset(g.widthCm, g.depthCm),
        Offset(0, g.depthCm),
      ],
      heightCm: g.heightCm,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              setState(() {
                final factor = e.scrollDelta.dy > 0 ? 0.9 : 1.1;
                final z = _isoZoom * factor;
                _isoZoom = z < 0.45 ? 0.45 : (z > 4.0 ? 4.0 : z);
              });
            }
          },
          child: GestureDetector(
            onTapUp: _openingsInteractive
                ? (d) {
                    final i = hitStairOpeningIndex(
                      d.localPosition,
                      size,
                      g,
                      StairPreviewMode.iso,
                      yaw: _yaw,
                      pitch: _pitch,
                      zoom: _isoZoom,
                    );
                    if (i != null) widget.onSelectOpening?.call(i);
                  }
                : null,
            onScaleStart: (_) {
              _baseIsoZoom = _isoZoom;
              if (_draggingOpening) return;
            },
            onScaleUpdate: (d) {
              if (_draggingOpening) {
                _handlePanUpdate(d.localFocalPoint, size, g);
                return;
              }
              setState(() {
                if (d.pointerCount >= 2 || (d.scale - 1.0).abs() > 0.02) {
                  final z = _baseIsoZoom * d.scale;
                  _isoZoom = z < 0.45 ? 0.45 : (z > 4.0 ? 4.0 : z);
                } else {
                  _yaw += d.focalPointDelta.dx * 0.01;
                  final p = _pitch - d.focalPointDelta.dy * 0.008;
                  _pitch = p < 0.08 ? 0.08 : (p > 1.15 ? 1.15 : p);
                }
              });
            },
            onLongPressStart: _openingsInteractive
                ? (d) => _handleLongPress(d.localPosition, size, g)
                : null,
            onLongPressMoveUpdate: _openingsInteractive && _draggingOpening
                ? (d) => _handlePanUpdate(d.localPosition, size, g)
                : null,
            onLongPressEnd: _openingsInteractive ? (_) => _endDrag() : null,
            child: CustomPaint(
              painter: StairIsometricPainter(
                geometry: g,
                shell: shell,
                yaw: _yaw,
                pitch: _pitch,
                zoom: _isoZoom,
                // Dims / highlight only while dragging to move.
                selectedOpeningIndex:
                    _draggingOpening ? widget.selectedOpeningIndex : null,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}
