import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/ceiling_grid.dart';
import '../../domain/ceiling_guides.dart';
import '../../domain/design_ceiling_features_baseline.dart';
import '../../domain/layout_layers.dart';
import 'canvas_palette.dart';

Color guideKindColor(GuideKind kind) {
  switch (kind) {
    case GuideKind.g3600:
      return const Color(0xFF1565C0);
    case GuideKind.g1200:
      return const Color(0xFF2E7D32);
    case GuideKind.g600:
      return const Color(0xFFE65100);
    case GuideKind.g2400:
      return const Color(0xFF6A1B9A);
  }
}

class LayoutMetrics {
  LayoutMetrics({
    required this.scale,
    required this.minX,
    required this.minY,
    required this.maxY,
    required this.ox,
    required this.oy,
    required this.roomWidthPx,
    required this.roomHeightPx,
    required this.centroidWorldX,
    required this.centroidWorldY,
    required this.size,
  });

  final double scale;
  final double minX;
  final double minY;
  final double maxY;
  final double ox;
  final double oy;
  final double roomWidthPx;
  final double roomHeightPx;
  final double centroidWorldX;
  final double centroidWorldY;
  final Size size;

  Offset get roomCentroidScreen => Offset(
        ox + (centroidWorldX - minX) * scale,
        oy + (maxY - centroidWorldY) * scale,
      );

  Offset get roomCenterScreen =>
      Offset(ox + roomWidthPx / 2, oy + roomHeightPx / 2);

  double fitScaleForViewport(Size viewport) {
    if (roomWidthPx <= 0 || roomHeightPx <= 0) return 1;
    return math.min(viewport.width / roomWidthPx, viewport.height / roomHeightPx) *
        0.9;
  }

  static LayoutMetrics compute(Size size, List<List<double>> walls) {
    double minX = 0, maxX = 100, minY = 0, maxY = 100;
    if (walls.isNotEmpty) {
      minX = walls.first[0];
      maxX = walls.first[0];
      minY = walls.first[1];
      maxY = walls.first[1];
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
    }
    minX -= 60;
    maxX += 60;
    minY -= 60;
    maxY += 60;
    final worldW = math.max(1.0, maxX - minX);
    final worldH = math.max(1.0, maxY - minY);
    final scale = math.min(size.width / worldW, size.height / worldH) * 0.88;
    final roomWidthPx = worldW * scale;
    final roomHeightPx = worldH * scale;
    final ox = (size.width - roomWidthPx) / 2;
    final oy = (size.height - roomHeightPx) / 2;
    final (cx, cy) = roomCentroidCm(walls);
    return LayoutMetrics(
      scale: scale,
      minX: minX,
      minY: minY,
      maxY: maxY,
      ox: ox,
      oy: oy,
      roomWidthPx: roomWidthPx,
      roomHeightPx: roomHeightPx,
      centroidWorldX: cx,
      centroidWorldY: cy,
      size: size,
    );
  }

  Offset screenToWorld(Offset p) {
    final x = minX + (p.dx - ox) / scale;
    final y = maxY - (p.dy - oy) / scale;
    return Offset(x, y);
  }
}

bool _guideGhostListsEqual(List<CeilingGuideMark> a, List<CeilingGuideMark> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (guideBaselineKey(a[i]) != guideBaselineKey(b[i])) return false;
  }
  return true;
}

class LayoutPainter extends CustomPainter {
  LayoutPainter({
    required this.walls,
    required this.grid,
    required this.metrics,
    required this.showTileDims,
    required this.showWallDims,
    required this.visualOffsetX,
    required this.visualOffsetY,
    required this.visibleWorld,
    required this.lightIds,
    required this.guides,
    required this.wallsForGuides,
    required this.showGuides,
    this.floatingGuide,
    this.dragSmoothX,
    this.dragSmoothY,
    this.showDesignOverlay = false,
    this.designGridOffsetX = 0,
    this.designGridOffsetY = 0,
    this.designLightIds = const {},
    this.designGuideGhosts = const [],
    this.layers = const LayoutLayerVisibility(),
    this.notesOverlay,
    this.floorOffsetX = 0,
    this.floorOffsetY = 0,
    this.floorTileWCm = 60,
    this.floorTileHCm = 60,
  });

  final List<List<double>> walls;
  final CeilingGrid grid;
  final LayoutMetrics metrics;
  final bool showTileDims;
  final bool showWallDims;
  final double visualOffsetX;
  final double visualOffsetY;
  final Rect visibleWorld;
  final Set<String> lightIds;
  final Map<String, CeilingGuideMark> guides;
  final List<List<double>> wallsForGuides;
  final bool showGuides;
  final CeilingGuideMark? floatingGuide;
  final double? dragSmoothX;
  final double? dragSmoothY;
  final bool showDesignOverlay;
  final int designGridOffsetX;
  final int designGridOffsetY;
  final Set<String> designLightIds;
  final List<CeilingGuideMark> designGuideGhosts;
  final LayoutLayerVisibility layers;
  final String? notesOverlay;
  final double floorOffsetX;
  final double floorOffsetY;
  final double floorTileWCm;
  final double floorTileHCm;

  void _drawGuideCaps(Canvas canvas, Offset a, Offset b, Color color, double stroke) {
    final capR = math.max(stroke * 2.1, 5.5);
    final capPaint = Paint()..color = color;
    final rim = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(a, capR, capPaint);
    canvas.drawCircle(b, capR, capPaint);
    canvas.drawCircle(a, capR, rim);
    canvas.drawCircle(b, capR, rim);
  }

  void _drawGuideRun(
    Canvas canvas, {
    required GuideDrawSegment seg,
    required Color color,
    required double stroke,
    required bool withCaps,
    Offset shadowOffset = Offset.zero,
  }) {
    final a = _map(seg.x1, seg.y1) + shadowOffset;
    final b = _map(seg.x2, seg.y2) + shadowOffset;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, paint);
    if (withCaps) _drawGuideCaps(canvas, a, b, color, stroke);
  }

  static Color _guideColor(GuideKind kind) => guideKindColor(kind);

  Offset _map(double x, double y) {
    final px = metrics.ox + (x - metrics.minX) * metrics.scale;
    final py = metrics.oy + (metrics.maxY - y) * metrics.scale;
    return Offset(px, py);
  }

  /// How far painted tiles stick out past [wallIndex] along outward normal (cm).
  ///
  /// Only corners in a thin strip along this wall segment count — otherwise
  /// zigzag rooms pull labels out to the AABB of distant cut tiles.
  double _maxOutwardOverhangCm({
    required int wallIndex,
    required double onx,
    required double ony,
    required double cellCm,
  }) {
    final w = walls[wallIndex];
    final wx0 = w[0];
    final wy0 = w[1];
    final wdx = w[2] - w[0];
    final wdy = w[3] - w[1];
    final wlen = math.sqrt(wdx * wdx + wdy * wdy);
    if (wlen < 1) return 0;
    final tdx = wdx / wlen;
    final tdy = wdy / wlen;
    // Corners must lie on this segment and just outside the wall.
    final alongPad = cellCm * 0.35;
    final outBand = cellCm * 1.15;

    var maxOut = 0.0;
    for (final c in grid.cells) {
      if (c.kind == CellKind.outside) continue;
      // Only cut tiles (and near-full cuts) create visible overhang past the wall.
      if (c.kind != CellKind.cut) continue;
      final (ox, oy) = _cellOrigin(c);
      final corners = <(double, double)>[
        (ox, oy),
        (ox + cellCm, oy),
        (ox, oy + cellCm),
        (ox + cellCm, oy + cellCm),
      ];
      for (final (px, py) in corners) {
        final sx = px - wx0;
        final sy = py - wy0;
        final along = sx * tdx + sy * tdy;
        if (along < -alongPad || along > wlen + alongPad) continue;
        final out = sx * onx + sy * ony;
        if (out <= 0.5 || out > outBand) continue;
        if (out > maxOut) maxOut = out;
      }
    }
    return maxOut;
  }

  /// Distance along a ray until it hits another wall segment (cm).
  double _rayClearanceToWallsCm(
    List<List<double>> walls, {
    required int excludeIndex,
    required double ox,
    required double oy,
    required double dx,
    required double dy,
  }) {
    var best = double.infinity;
    for (var i = 0; i < walls.length; i++) {
      if (i == excludeIndex) continue;
      final w = walls[i];
      final hit = _raySegmentHitT(ox, oy, dx, dy, w[0], w[1], w[2], w[3]);
      if (hit != null && hit > 1.0) {
        best = math.min(best, hit);
      }
    }
    return best.isFinite ? best : 1e9;
  }

  /// Returns distance along ray (ox,oy)+t*(dx,dy) to segment, or null if no hit.
  static double? _raySegmentHitT(
    double ox,
    double oy,
    double dx,
    double dy,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    final sx = x2 - x1;
    final sy = y2 - y1;
    final denom = dx * sy - dy * sx;
    if (denom.abs() < 1e-9) return null;
    final qx = x1 - ox;
    final qy = y1 - oy;
    final t = (qx * sy - qy * sx) / denom;
    final u = (qx * dy - qy * dx) / denom;
    if (t <= 1e-6 || u < -1e-6 || u > 1 + 1e-6) return null;
    return t;
  }

  /// World origin of cell — shifts live with [visualOffset] before grid rebuild.
  (double, double) _cellOrigin(GridCell c) {
    final dx = visualOffsetX - grid.offsetXCm;
    final dy = visualOffsetY - grid.offsetYCm;
    return (c.xCm + dx, c.yCm + dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = CanvasPalette.bg);

    final wallPaint = Paint()
      ..color = CanvasPalette.wall
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final fullPaint = Paint()..color = CanvasPalette.fullTile;
    final cutPaint = Paint()..color = CanvasPalette.cutTile;
    final linePaint = Paint()
      ..color = CanvasPalette.grid
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final lightPaint = Paint()..color = const Color.fromRGBO(255, 245, 184, 0.85);
    final cell = grid.cellSizeCm;
    final view = visibleWorld;
    final borderPath = Path();

    if (layers.floor) {
      _paintFloorOverlay(canvas);
    }

    if (layers.grid || layers.lights) {
      for (final c in grid.cells) {
        final (x, y) = _cellOrigin(c);
        if (x + cell < view.left ||
            x > view.right ||
            y + cell < view.top ||
            y > view.bottom) {
          continue;
        }
        final a = _map(x, y);
        final b = _map(x + cell, y + cell);
        final r = Rect.fromPoints(a, b);
        final lit = layers.lights && lightIds.contains(c.id);
        if (layers.grid) {
          canvas.drawRect(
            r,
            lit ? lightPaint : (c.kind == CellKind.full ? fullPaint : cutPaint),
          );
          borderPath.addRect(r);
        } else if (lit) {
          canvas.drawRect(r, lightPaint);
        }

        if (layers.grid && showTileDims && c.kind == CellKind.cut) {
          if (c.cutXCm < cell || c.cutYCm < cell) {
            final label = '${c.cutXCm.round()}×${c.cutYCm.round()}';
            final fontSize =
                (math.min(r.width, r.height) * 0.324).clamp(10.0, 23.0);
            final tp = TextPainter(
              text: TextSpan(
                text: label,
                style: TextStyle(
                  color: CanvasPalette.text,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  shadows: const [
                    Shadow(blurRadius: 2, color: Colors.black87),
                  ],
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
          }
        }
      }
    }
    if (layers.grid && borderPath.computeMetrics().length > 0) {
      canvas.drawPath(borderPath, linePaint);
    }

    if (showDesignOverlay) {
      final ghostDx = designGridOffsetX - grid.offsetXCm;
      final ghostDy = designGridOffsetY - grid.offsetYCm;
      if (ghostDx != 0 || ghostDy != 0) {
        final ghostFill = Paint()..color = const Color(0x44FF9800);
        final ghostStroke = Paint()
          ..color = const Color(0xCCFF9800)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        for (final c in grid.cells) {
          if (c.kind == CellKind.outside) continue;
          final (x, y) = _cellOrigin(c);
          final gx = x + ghostDx;
          final gy = y + ghostDy;
          if (gx + cell < view.left ||
              gx > view.right ||
              gy + cell < view.top ||
              gy > view.bottom) {
            continue;
          }
          final a = _map(gx, gy);
          final b = _map(gx + cell, gy + cell);
          final r = Rect.fromPoints(a, b);
          canvas.drawRect(r, ghostFill);
          canvas.drawRect(r, ghostStroke);
        }
      }
    }

    if (showDesignOverlay && designLightIds.isNotEmpty) {
      final ghostLight = Paint()..color = const Color(0x88FF9800);
      final ghostRing = Paint()
        ..color = const Color(0xFFFF9800)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final c in grid.cells) {
        if (!designLightIds.contains(c.id) || lightIds.contains(c.id)) continue;
        final (x, y) = _cellOrigin(c);
        final center = _map(x + cell / 2, y + cell / 2);
        canvas.drawCircle(center, cell * 0.22, ghostLight);
        canvas.drawCircle(center, cell * 0.22, ghostRing);
      }
    }

    if (showDesignOverlay && designGuideGhosts.isNotEmpty) {
      _paintDesignGuideGhosts(canvas, view, cell);
    }

    if (layers.guides && showGuides) {
      _paintGuides(canvas, view, cell);
    }

    if (layers.walls) {
      final cellCm = grid.cellSizeCm;
      // Same sizing as cut-tile dimension labels.
      final tilePx = cellCm * metrics.scale;
      final fontSize = (tilePx * 0.324).clamp(10.0, 23.0);
      const nearGapCm = 10.0;
      const floatPadCm = 12.0;

      for (var wi = 0; wi < walls.length; wi++) {
        final w = walls[wi];
        final a = _map(w[0], w[1]);
        final b = _map(w[2], w[3]);
        canvas.drawLine(a, b, wallPaint);
        if (!showWallDims) continue;

        final len =
            math.sqrt(math.pow(w[2] - w[0], 2) + math.pow(w[3] - w[1], 2));
        if (len < 1) continue;

        final midWx = (w[0] + w[2]) / 2;
        final midWy = (w[1] + w[3]) / 2;
        final wdx = w[2] - w[0];
        final wdy = w[3] - w[1];
        final wlen = math.sqrt(wdx * wdx + wdy * wdy);
        if (wlen < 1) continue;

        // Outward normal in world space (away from room centroid).
        var onx = -wdy / wlen;
        var ony = wdx / wlen;
        final toCx = metrics.centroidWorldX - midWx;
        final toCy = metrics.centroidWorldY - midWy;
        if (onx * toCx + ony * toCy > 0) {
          onx = -onx;
          ony = -ony;
        }

        // Float past cut tiles on THIS wall only; never past one cell (zigzag AABB).
        final overhangCm = _maxOutwardOverhangCm(
          wallIndex: wi,
          onx: onx,
          ony: ony,
          cellCm: cellCm,
        );
        var offsetCm = nearGapCm;
        if (overhangCm > 1) {
          offsetCm = math.min(overhangCm + floatPadCm, cellCm * 0.85);
        }

        final outwardClearance = _rayClearanceToWallsCm(
          walls,
          excludeIndex: wi,
          ox: midWx,
          oy: midWy,
          dx: onx,
          dy: ony,
        );

        // Concave / zigzag: another wall blocks → keep label tight to this wall
        // (inside or a small outward gap), never jump to the outer bounding box.
        final placeInside = outwardClearance < offsetCm + 6;
        if (placeInside) {
          onx = -onx;
          ony = -ony;
          final inwardClearance = _rayClearanceToWallsCm(
            walls,
            excludeIndex: wi,
            ox: midWx,
            oy: midWy,
            dx: onx,
            dy: ony,
          );
          offsetCm = math
              .min(nearGapCm, inwardClearance * 0.35)
              .clamp(nearGapCm * 0.5, cellCm * 0.45);
        } else if (outwardClearance.isFinite) {
          offsetCm = math.min(offsetCm, outwardClearance * 0.45)
              .clamp(nearGapCm * 0.5, cellCm * 0.85);
        }

        final edgeAnchor = _map(midWx + onx * offsetCm, midWy + ony * offsetCm);
        final wallMidScreen = _map(midWx, midWy);
        var snx = edgeAnchor.dx - wallMidScreen.dx;
        var sny = edgeAnchor.dy - wallMidScreen.dy;
        final snLen = math.sqrt(snx * snx + sny * sny);
        if (snLen > 1e-6) {
          snx /= snLen;
          sny /= snLen;
        }

        final tp = TextPainter(
          text: TextSpan(
            text: len.toStringAsFixed(0),
            style: TextStyle(
              color: CanvasPalette.wall,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              shadows: const [
                Shadow(blurRadius: 3, color: Colors.black87),
                Shadow(blurRadius: 1, color: Colors.black54),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Offset is to the near edge of the label (toward the wall), not its center.
        final halfAlongOut =
            0.5 * (tp.width * snx.abs() + tp.height * sny.abs());
        final center = Offset(
          edgeAnchor.dx + snx * halfAlongOut,
          edgeAnchor.dy + sny * halfAlongOut,
        );
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      }
    }

    if (layers.notes && notesOverlay != null && notesOverlay!.trim().isNotEmpty) {
      final note = notesOverlay!.trim();
      final short = note.length > 120 ? '${note.substring(0, 117)}…' : note;
      final tp = TextPainter(
        text: TextSpan(
          text: short,
          style: const TextStyle(color: Color(0xFF37474F), fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.35);
      final pad = 6.0;
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(8, 8, tp.width + pad * 2, tp.height + pad * 2),
        const Radius.circular(4),
      );
      canvas.drawRRect(bg, Paint()..color = const Color(0xCCFFFDE7));
      tp.paint(canvas, Offset(8 + pad, 8 + pad));
    }
  }

  void _paintFloorOverlay(Canvas canvas) {
    if (walls.length < 3) return;
    final path = Path();
    final start = _map(walls.first[0], walls.first[1]);
    path.moveTo(start.dx, start.dy);
    for (final w in walls) {
      final p = _map(w[2], w[3]);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(path, Paint()..color = const Color(0x338D6E63));
    var minX = walls[0][0];
    var maxX = walls[0][0];
    var minY = walls[0][1];
    var maxY = walls[0][1];
    for (final w in walls) {
      minX = math.min(minX, math.min(w[0], w[2]));
      maxX = math.max(maxX, math.max(w[0], w[2]));
      minY = math.min(minY, math.min(w[1], w[3]));
      maxY = math.max(maxY, math.max(w[1], w[3]));
    }
    final tileW = floorTileWCm <= 0 ? 60.0 : floorTileWCm;
    final tileH = floorTileHCm <= 0 ? 60.0 : floorTileHCm;
    final line = Paint()
      ..color = const Color(0x668D6E63)
      ..strokeWidth = 0.8;
    for (var x = minX + floorOffsetX; x <= maxX + 0.5; x += tileW) {
      canvas.drawLine(_map(x, minY), _map(x, maxY), line);
    }
    for (var y = minY + floorOffsetY; y <= maxY + 0.5; y += tileH) {
      canvas.drawLine(_map(minX, y), _map(maxX, y), line);
    }
    canvas.restore();
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Пол',
        style: TextStyle(color: Color(0xFF5D4037), fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, _map(minX, maxY) + const Offset(6, 6));
  }

  void _paintDesignGuideGhosts(Canvas canvas, Rect view, double cell) {
    final cellSize = grid.cellSizeCm;
    const ghostColor = Color(0xCCFF9800);
    for (final mark in designGuideGhosts) {
      final gridOffH = designGridOffsetY.toDouble();
      final gridOffV = designGridOffsetX.toDouble();
      final coord = guideLineWorldCoord(
        axis: mark.axis,
        lineIndex: mark.lineIndex,
        gridOffset: mark.axis == GuideAxis.horizontal ? gridOffH : gridOffV,
        visualOffset: mark.axis == GuideAxis.horizontal ? visualOffsetY : visualOffsetX,
        cellSize: cellSize,
      );
      final perpAxis =
          mark.axis == GuideAxis.horizontal ? GuideAxis.vertical : GuideAxis.horizontal;
      final anchorCm = guideLineWorldCoord(
        axis: perpAxis,
        lineIndex: mark.anchorAlongIndex,
        gridOffset: perpAxis == GuideAxis.vertical ? gridOffV : gridOffH,
        visualOffset: perpAxis == GuideAxis.vertical ? visualOffsetX : visualOffsetY,
        cellSize: cellSize,
      );
      final segments = guideProfilePieceSegments(
        mark,
        wallsForGuides,
        offsetX: visualOffsetX,
        offsetY: visualOffsetY,
        cellSize: cellSize,
        coordCm: coord,
        anchorAlongCm: anchorCm,
      );
      final stroke = mark.kind == GuideKind.g3600 ? 4.0 : 2.8;
      for (final seg in segments) {
        final midX = (seg.x1 + seg.x2) * 0.5;
        final midY = (seg.y1 + seg.y2) * 0.5;
        if (midX < view.left - cell || midX > view.right + cell) continue;
        if (midY < view.top - cell || midY > view.bottom + cell) continue;
        _drawGuideRun(
          canvas,
          seg: seg,
          color: ghostColor,
          stroke: stroke,
          withCaps: true,
        );
      }
    }
  }

  void _paintGuides(Canvas canvas, Rect view, double cell) {
    final cellSize = grid.cellSizeCm;
    for (final e in guides.entries) {
      final mark = e.value;
      final coord = guideLineWorldCoord(
        axis: mark.axis,
        lineIndex: mark.lineIndex,
        gridOffset: mark.axis == GuideAxis.horizontal ? grid.offsetYCm : grid.offsetXCm,
        visualOffset: mark.axis == GuideAxis.horizontal ? visualOffsetY : visualOffsetX,
        cellSize: cellSize,
      );
      final perpAxis =
          mark.axis == GuideAxis.horizontal ? GuideAxis.vertical : GuideAxis.horizontal;
      final anchorCm = guideLineWorldCoord(
        axis: perpAxis,
        lineIndex: mark.anchorAlongIndex,
        gridOffset: perpAxis == GuideAxis.vertical ? grid.offsetXCm : grid.offsetYCm,
        visualOffset: perpAxis == GuideAxis.vertical ? visualOffsetX : visualOffsetY,
        cellSize: cellSize,
      );
      final segments = guideProfilePieceSegments(
        mark,
        wallsForGuides,
        offsetX: visualOffsetX,
        offsetY: visualOffsetY,
        cellSize: cellSize,
        coordCm: coord,
        anchorAlongCm: anchorCm,
      );
      final color = _guideColor(mark.kind);
      final stroke = mark.kind == GuideKind.g3600 ? 4.0 : 2.8;
      for (final seg in segments) {
        final midX = (seg.x1 + seg.x2) * 0.5;
        final midY = (seg.y1 + seg.y2) * 0.5;
        if (midX < view.left - cell || midX > view.right + cell) continue;
        if (midY < view.top - cell || midY > view.bottom + cell) continue;
        _drawGuideRun(
          canvas,
          seg: seg,
          color: color.withValues(alpha: 0.92),
          stroke: stroke,
          withCaps: true,
        );
      }
    }

    if (floatingGuide != null && dragSmoothX != null && dragSmoothY != null) {
      final mark = floatingGuide!;
      // Follow finger freely; snap preview picks H/V by proximity (↑↓←→).
      final placement = snapGuidePlacement(
        worldX: dragSmoothX!,
        worldY: dragSmoothY!,
        offsetX: visualOffsetX,
        offsetY: visualOffsetY,
        cellSize: cellSize,
        walls: wallsForGuides,
      );
      final axis = placement.axis;
      final coord = axis == GuideAxis.horizontal ? dragSmoothY! : dragSmoothX!;
      final along = axis == GuideAxis.horizontal ? dragSmoothX! : dragSmoothY!;
      final preview = CeilingGuideMark(
        axis: axis,
        lineIndex: placement.lineIndex,
        kind: mark.kind,
        anchorAlongIndex: placement.anchorIndex,
      );
      final segments = guideProfilePieceSegments(
        preview,
        wallsForGuides,
        offsetX: visualOffsetX,
        offsetY: visualOffsetY,
        cellSize: cellSize,
        coordCm: coord,
        anchorAlongCm: along,
      );
      final color = _guideColor(mark.kind);
      const floatStroke = 5.5;
      for (final seg in segments) {
        final midX = (seg.x1 + seg.x2) * 0.5;
        final midY = (seg.y1 + seg.y2) * 0.5;
        if (midX < view.left - cell || midX > view.right + cell) continue;
        if (midY < view.top - cell || midY > view.bottom + cell) continue;
        _drawGuideRun(
          canvas,
          seg: seg,
          color: Colors.black.withValues(alpha: 0.22),
          stroke: floatStroke + 1.5,
          withCaps: false,
          shadowOffset: const Offset(1.5, 2.5),
        );
        _drawGuideRun(
          canvas,
          seg: seg,
          color: color.withValues(alpha: 0.95),
          stroke: floatStroke,
          withCaps: true,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant LayoutPainter old) {
    return old.walls != walls ||
        old.grid.cells != grid.cells ||
        old.grid.offsetXCm != grid.offsetXCm ||
        old.grid.offsetYCm != grid.offsetYCm ||
        old.grid.cellSizeCm != grid.cellSizeCm ||
        old.metrics.scale != metrics.scale ||
        old.metrics.minX != metrics.minX ||
        old.metrics.minY != metrics.minY ||
        old.metrics.size != metrics.size ||
        old.showTileDims != showTileDims ||
        old.showWallDims != showWallDims ||
        old.visualOffsetX != visualOffsetX ||
        old.visualOffsetY != visualOffsetY ||
        old.visibleWorld != visibleWorld ||
        old.lightIds.length != lightIds.length ||
        !old.lightIds.containsAll(lightIds) ||
        old.guides.length != guides.length ||
        !mapEquals(old.guides, guides) ||
        old.wallsForGuides != wallsForGuides ||
        old.showGuides != showGuides ||
        old.floatingGuide != floatingGuide ||
        old.dragSmoothX != dragSmoothX ||
        old.dragSmoothY != dragSmoothY ||
        old.showDesignOverlay != showDesignOverlay ||
        old.designGridOffsetX != designGridOffsetX ||
        old.designGridOffsetY != designGridOffsetY ||
        old.designLightIds.length != designLightIds.length ||
        !old.designLightIds.containsAll(designLightIds) ||
        old.designGuideGhosts.length != designGuideGhosts.length ||
        !_guideGhostListsEqual(old.designGuideGhosts, designGuideGhosts) ||
        old.layers.walls != layers.walls ||
        old.layers.grid != layers.grid ||
        old.layers.guides != layers.guides ||
        old.layers.lights != layers.lights ||
        old.layers.floor != layers.floor ||
        old.layers.notes != layers.notes ||
        old.notesOverlay != notesOverlay ||
        old.floorOffsetX != floorOffsetX ||
        old.floorOffsetY != floorOffsetY ||
        old.floorTileWCm != floorTileWCm ||
        old.floorTileHCm != floorTileHCm;
  }
}
