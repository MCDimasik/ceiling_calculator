import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'pdf_vector_walls.dart';
import 'plan_seg_model.dart';

/// Detect room outline on a floor-plan.
///
/// Pipeline split:
/// - **Vector PDF**: face-walk / thick wall mask from content streams.
/// - **Photo / raster**: ONNX DeepLab room seg → fallback Sobel flood.
class PlanAutoOutline {
  PlanAutoOutline._();

  /// Returns polygon in full-resolution image coordinates, or null.
  static Future<List<ui.Offset>?> outlineAtTap({
    required Uint8List imageBytes,
    required ui.Offset tapImage,
    int maxWidth = 640,
    PdfVectorWalls? vectorWalls,
  }) async {
    // Prefer exact face walk on vector walls (no raster collapse to a line).
    if (vectorWalls != null && vectorWalls.isUseful) {
      final face = vectorWalls.roomOutlineAt(tapImage);
      if (face != null && face.length >= 3) return face;
    }

    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final sw = src.width;
    final sh = src.height;
    if (sw < 8 || sh < 8) {
      src.dispose();
      return null;
    }

    // Photo path: try trained room/wall model before classical edges.
    if (vectorWalls == null || !vectorWalls.isUseful) {
      try {
        final ml = await PlanSegModel.outlineRoomAtTap(
          imageBytes: imageBytes,
          tapImage: tapImage,
          imageWidth: sw,
          imageHeight: sh,
        );
        if (ml != null && ml.length >= 3) {
          src.dispose();
          return ml;
        }
      } catch (e, st) {
        debugPrint('PlanSegModel outline failed: $e\n$st');
        PlanSegModel.lastError ??= 'Сбой модели: $e';
      }
    }

    final scale = sw > maxWidth ? maxWidth / sw : 1.0;
    final dw = math.max(8, (sw * scale).round());
    final dh = math.max(8, (sh * scale).round());

    late final List<bool> baseWall;
    if (vectorWalls != null && vectorWalls.isUseful) {
      src.dispose();
      baseWall = _wallMaskFromVectors(vectorWalls.segments, dw, dh, scale);
    } else {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        src,
        ui.Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
        ui.Rect.fromLTWH(0, 0, dw.toDouble(), dh.toDouble()),
        ui.Paint(),
      );
      final picture = recorder.endRecording();
      final small = await picture.toImage(dw, dh);
      src.dispose();

      final bd = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
      small.dispose();
      if (bd == null) return null;
      baseWall = _buildWallMask(bd.buffer.asUint8List(), dw, dh);
    }

    final tx = (tapImage.dx * scale).round().clamp(0, dw - 1);
    final ty = (tapImage.dy * scale).round().clamp(0, dh - 1);

    for (final seal in const [2, 4, 6, 9]) {
      final wall = List<bool>.from(baseWall);
      _morphologicalClose(wall, dw, dh, radius: seal);
      var sx = tx;
      var sy = ty;
      if (wall[sy * dw + sx]) {
        final alt = _nearestOpen(wall, dw, dh, tx, ty, 24);
        if (alt == null) continue;
        sx = alt.$1;
        sy = alt.$2;
      }
      final poly = await _floodAndTrace(wall, dw, dh, sx, sy, 1 / scale);
      if (poly != null) return poly;
    }
    return null;
  }

  /// Rasterize vector strokes into a boolean wall mask (downscaled space).
  static List<bool> _wallMaskFromVectors(
    List<PdfWallSegment> segments,
    int w,
    int h,
    double imageToSmall,
  ) {
    final wall = List<bool>.filled(w * h, false);
    void plot(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      wall[y * w + x] = true;
    }

    void thickLine(ui.Offset a, ui.Offset b) {
      final x0 = (a.dx * imageToSmall).round();
      final y0 = (a.dy * imageToSmall).round();
      final x1 = (b.dx * imageToSmall).round();
      final y1 = (b.dy * imageToSmall).round();
      final steps = math.max((a - b).distance * imageToSmall, 1).ceil();
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = (x0 + (x1 - x0) * t).round();
        final y = (y0 + (y1 - y0) * t).round();
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            plot(x + dx, y + dy);
          }
        }
      }
    }

    for (final s in segments) {
      thickLine(s.a, s.b);
    }
    return wall;
  }

  /// Merge two polygons (convex-ish union via combined hull of vertices).
  static List<ui.Offset> mergePolygons(List<ui.Offset> a, List<ui.Offset> b) {
    final all = [...a, ...b];
    return _convexHull(all);
  }

  static List<bool> _buildWallMask(Uint8List rgba, int w, int h) {
    final lum = Float32List(w * h);
    final sorted = <double>[];
    for (var i = 0; i < w * h; i++) {
      final o = i * 4;
      final y = 0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2];
      lum[i] = y;
      sorted.add(y);
    }
    sorted.sort();
    // Darker ink ≈ bottom ~28% of luminances (walls/doors/text).
    final inkThr = sorted[(sorted.length * 0.28).floor().clamp(0, sorted.length - 1)];
    // Soft gray walls: anything clearly below mid-tone.
    final mean = sorted[sorted.length ~/ 2];
    final softThr = mean * 0.90;

    final grad = Float32List(w * h);
    var gMax = 1.0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final gx = -lum[i - w - 1] -
            2 * lum[i - 1] -
            lum[i + w - 1] +
            lum[i - w + 1] +
            2 * lum[i + 1] +
            lum[i + w + 1];
        final gy = -lum[i - w - 1] -
            2 * lum[i - w] -
            lum[i - w + 1] +
            lum[i + w - 1] +
            2 * lum[i + w] +
            lum[i + w + 1];
        final g = math.sqrt(gx * gx + gy * gy);
        grad[i] = g;
        if (g > gMax) gMax = g;
      }
    }
    final edgeThr = gMax * 0.18;

    final wall = List<bool>.filled(w * h, false);
    for (var i = 0; i < lum.length; i++) {
      wall[i] = lum[i] <= inkThr || lum[i] < softThr || grad[i] >= edgeThr;
    }
    return wall;
  }

  static void _dilateInPlace(List<bool> m, int w, int h, {int passes = 1}) {
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

  static void _erodeInPlace(List<bool> m, int w, int h, {int passes = 1}) {
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

  /// Close thin gaps (doorways) while roughly keeping wall thickness.
  static void _morphologicalClose(
    List<bool> m,
    int w,
    int h, {
    required int radius,
  }) {
    _dilateInPlace(m, w, h, passes: radius);
    _erodeInPlace(m, w, h, passes: math.max(1, radius - 1));
  }

  static (int, int)? _nearestOpen(
    List<bool> wall,
    int w,
    int h,
    int cx,
    int cy,
    int r,
  ) {
    for (var d = 1; d <= r; d++) {
      for (var dy = -d; dy <= d; dy++) {
        for (var dx = -d; dx <= d; dx++) {
          if (dx.abs() != d && dy.abs() != d) continue;
          final x = cx + dx;
          final y = cy + dy;
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          if (!wall[y * w + x]) return (x, y);
        }
      }
    }
    return null;
  }

  static Future<List<ui.Offset>?> _floodAndTrace(
    List<bool> wall,
    int w,
    int h,
    int sx,
    int sy,
    double toFull,
  ) async {
    final filled = List<bool>.filled(w * h, false);
    final stack = <int>[sy * w + sx];
    filled[sy * w + sx] = true;
    var count = 0;
    var borderHits = 0;
    // Typical single room on a floor plan is well under ~35% of the sheet.
    final maxFill = (w * h * 0.35).round();
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      count++;
      if (count > maxFill) return null;
      final x = i % w;
      final y = i ~/ w;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) {
        borderHits++;
      }
      for (final (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final j = ny * w + nx;
        if (filled[j] || wall[j]) continue;
        filled[j] = true;
        stack.add(j);
      }
    }
    // After sealing doors, a real room should not flood the page margin.
    // Tiny border contact (cropped plan) is OK; wide leak is not.
    if (borderHits > math.max(8, (w + h) ~/ 40)) return null;
    if (count < 60) return null;

    final ordered = _traceBoundaryMoore(filled, w, h);
    if (ordered.length < 4) return null;
    final simplified = _simplifyOutline(ordered, w, h);
    if (simplified.length < 3) return null;

    return [
      for (final p in simplified) ui.Offset(p.dx * toFull, p.dy * toFull),
    ];
  }

  /// 4-connected walk around filled region (room interior).
  static List<ui.Offset> _traceBoundaryMoore(List<bool> inside, int w, int h) {
    bool inb(int x, int y) =>
        x >= 0 && y >= 0 && x < w && y < h && inside[y * w + x];

    var sx = -1;
    var sy = -1;
    for (var y = 0; y < h && sx < 0; y++) {
      for (var x = 0; x < w; x++) {
        if (!inb(x, y)) continue;
        if (!inb(x, y - 1)) {
          sx = x;
          sy = y;
          break;
        }
      }
    }
    if (sx < 0) return const [];

    const vx = [0, 1, 0, -1];
    const vy = [-1, 0, 1, 0];

    var x = sx;
    var y = sy;
    var backDir = 0;
    final path = <ui.Offset>[ui.Offset(x.toDouble(), y.toDouble())];
    var guard = 0;

    while (guard++ < w * h * 8) {
      var moved = false;
      for (var t = 0; t < 4; t++) {
        final d = (backDir + 1 + t) % 4;
        final nx = x + vx[d];
        final ny = y + vy[d];
        if (!inb(nx, ny)) continue;
        x = nx;
        y = ny;
        backDir = (d + 2) % 4;
        path.add(ui.Offset(x.toDouble(), y.toDouble()));
        moved = true;
        break;
      }
      if (!moved) break;
      if (x == sx && y == sy && path.length > 3) break;
    }
    return path;
  }

  static List<ui.Offset> _simplifyOutline(
    List<ui.Offset> ordered,
    int w,
    int h,
  ) {
    // Keep wall nibs / small jogs — do not over-simplify to a "line".
    var eps = math.max(2.5, math.min(w, h) / 55.0);
    var simplified = _douglasPeucker(ordered, eps);
    while (simplified.length > 28 && eps < 24) {
      eps += 1.5;
      simplified = _douglasPeucker(ordered, eps);
    }
    return simplified;
  }

  static List<ui.Offset> _douglasPeucker(List<ui.Offset> pts, double eps) {
    if (pts.length < 3) return pts;
    var maxD = 0.0;
    var idx = 0;
    final a = pts.first;
    final b = pts.last;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = _perpDist(pts[i], a, b);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > eps) {
      final left = _douglasPeucker(pts.sublist(0, idx + 1), eps);
      final right = _douglasPeucker(pts.sublist(idx), eps);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [a, b];
  }

  static double _perpDist(ui.Offset p, ui.Offset a, ui.Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-9) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
    final proj = ui.Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }

  static List<ui.Offset> _convexHull(List<ui.Offset> pts) {
    if (pts.length <= 3) return List<ui.Offset>.from(pts);
    final sorted = [...pts]..sort((a, b) {
        final c = a.dx.compareTo(b.dx);
        return c != 0 ? c : a.dy.compareTo(b.dy);
      });
    List<ui.Offset> build(bool lower) {
      final h = <ui.Offset>[];
      for (final p in lower ? sorted : sorted.reversed) {
        while (h.length >= 2) {
          final a = h[h.length - 2];
          final b = h[h.length - 1];
          final cross =
              (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
          if (cross <= 0) {
            h.removeLast();
          } else {
            break;
          }
        }
        h.add(p);
      }
      return h;
    }

    final lower = build(true);
    final upper = build(false);
    return [
      ...lower.sublist(0, lower.length - 1),
      ...upper.sublist(0, upper.length - 1),
    ];
  }
}
