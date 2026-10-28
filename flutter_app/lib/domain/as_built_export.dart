import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../ui/widgets/canvas_palette.dart';
import 'ceiling_grid.dart';
import 'ceiling_guides.dart';
import 'dimension_lines.dart';
import 'document_qr.dart';
import 'documentation_model.dart';
import 'export_stamp_overlay.dart';
import 'floor_as_built_export.dart';
import 'hidden_works_pdf.dart';
import 'layout_layers.dart';
import 'pdf_stamp_block.dart';
import 'models.dart';
import 'pdf_fonts.dart';
import 'project_materials.dart';
import 'wall_as_built_export.dart';

/// Layout metrics for export (same math as layout screen).
class AsBuiltMetrics {
  AsBuiltMetrics({
    required this.scale,
    required this.minX,
    required this.maxY,
    required this.ox,
    required this.oy,
  });

  final double scale;
  final double minX;
  final double maxY;
  final double ox;
  final double oy;

  static AsBuiltMetrics compute(Size size, List<List<double>> walls) {
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
    final scale = math.min(size.width / worldW, size.height / worldH) * 0.82;
    final roomWidthPx = worldW * scale;
    final roomHeightPx = worldH * scale;
    final ox = (size.width - roomWidthPx) / 2;
    final oy = (size.height - roomHeightPx) / 2;
    return AsBuiltMetrics(scale: scale, minX: minX, maxY: maxY, ox: ox, oy: oy);
  }

  Offset map(double x, double y) {
    final px = ox + (x - minX) * scale;
    final py = oy + (maxY - y) * scale;
    return Offset(px, py);
  }
}

/// Layer toggles for as-built PNG/PDF export.
class AsBuiltExportOptions {
  const AsBuiltExportOptions({
    this.showWalls = true,
    this.showTiles = true,
    this.showGrid = true,
    this.showGuides = true,
    this.showLights = true,
    this.showTileDims = true,
    this.showWallDims = true,
    this.showGridStep = true,
    this.showLightCallouts = true,
    this.showFloor = false,
    this.showNotes = false,
  });

  final bool showWalls;
  final bool showTiles;
  final bool showGrid;
  final bool showGuides;
  final bool showLights;
  final bool showTileDims;
  final bool showWallDims;
  final bool showGridStep;
  final bool showLightCallouts;
  final bool showFloor;
  final bool showNotes;

  factory AsBuiltExportOptions.fromLayoutLayers(LayoutLayerVisibility layers) {
    return AsBuiltExportOptions(
      showWalls: layers.walls,
      showGrid: layers.grid,
      showGuides: layers.guides,
      showLights: layers.lights,
      showFloor: layers.floor,
      showNotes: layers.notes,
      showWallDims: layers.wallDims,
      showTileDims: layers.tileDims,
    );
  }

  AsBuiltExportOptions copyWith({
    bool? showWalls,
    bool? showTiles,
    bool? showGrid,
    bool? showGuides,
    bool? showLights,
    bool? showTileDims,
    bool? showWallDims,
    bool? showGridStep,
    bool? showLightCallouts,
    bool? showFloor,
    bool? showNotes,
  }) {
    return AsBuiltExportOptions(
      showWalls: showWalls ?? this.showWalls,
      showTiles: showTiles ?? this.showTiles,
      showGrid: showGrid ?? this.showGrid,
      showGuides: showGuides ?? this.showGuides,
      showLights: showLights ?? this.showLights,
      showTileDims: showTileDims ?? this.showTileDims,
      showWallDims: showWallDims ?? this.showWallDims,
      showGridStep: showGridStep ?? this.showGridStep,
      showLightCallouts: showLightCallouts ?? this.showLightCallouts,
      showFloor: showFloor ?? this.showFloor,
      showNotes: showNotes ?? this.showNotes,
    );
  }
}

class AsBuiltLayoutPainter extends CustomPainter {
  AsBuiltLayoutPainter({
    required this.walls,
    required this.grid,
    required this.metrics,
    required this.lightIds,
    required this.guides,
    required this.visualOffsetX,
    required this.visualOffsetY,
    this.options = const AsBuiltExportOptions(),
    this.notesOverlay,
  });

  final List<List<double>> walls;
  final CeilingGrid grid;
  final AsBuiltMetrics metrics;
  final Set<String> lightIds;
  final Map<String, CeilingGuideMark> guides;
  final double visualOffsetX;
  final double visualOffsetY;
  final AsBuiltExportOptions options;
  final String? notesOverlay;

  bool get showTileDims => options.showTileDims;
  bool get showWallDims => options.showWallDims;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = CanvasPalette.bg);

    if (options.showFloor && walls.length >= 3) {
      final path = Path();
      final start = metrics.map(walls.first[0], walls.first[1]);
      path.moveTo(start.dx, start.dy);
      for (final w in walls) {
        final p = metrics.map(w[2], w[3]);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0x338D6E63));
      final label = TextPainter(
        text: const TextSpan(
          text: 'Пол',
          style: TextStyle(color: Color(0xFF6D4C41), fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(12, size.height - label.height - 12));
    }

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
    final borderPath = Path();

    for (final c in grid.cells) {
      final dx = visualOffsetX - grid.offsetXCm;
      final dy = visualOffsetY - grid.offsetYCm;
      final x = c.xCm + dx;
      final y = c.yCm + dy;
      final a = metrics.map(x, y);
      final b = metrics.map(x + cell, y + cell);
      final r = Rect.fromPoints(a, b);
      final lit = options.showLights && lightIds.contains(c.id);
      if (options.showTiles) {
        canvas.drawRect(
          r,
          lit ? lightPaint : (c.kind == CellKind.full ? fullPaint : cutPaint),
        );
        if (options.showGrid) borderPath.addRect(r);
      } else if (lit) {
        canvas.drawRect(r, lightPaint);
      }

      if (showTileDims && c.kind == CellKind.cut) {
        const threshold = 59.95;
        if (c.cutXCm < threshold || c.cutYCm < threshold) {
          final label = '${c.cutXCm.round()}×${c.cutYCm.round()}';
          final tp = TextPainter(
            text: TextSpan(
              text: label,
              style: const TextStyle(
                color: CanvasPalette.text,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
        }
      }
    }
    if (options.showGrid && borderPath.computeMetrics().length > 0) {
      canvas.drawPath(borderPath, linePaint);
    }

    if (options.showGrid && options.showGridStep && grid.cells.isNotEmpty) {
      final sample = grid.cells.firstWhere(
        (c) => c.kind != CellKind.outside,
        orElse: () => grid.cells.first,
      );
      final dx = visualOffsetX - grid.offsetXCm;
      final dy = visualOffsetY - grid.offsetYCm;
      final sx = sample.xCm + dx;
      final sy = sample.yCm + dy;
      final label = '${cell.round()}×${cell.round()}';
      final a = metrics.map(sx, sy);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: CanvasPalette.grid,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, a + const Offset(2, 2));
    }

    if (options.showGuides) _paintGuides(canvas, cell);

    if (options.showLights && options.showLightCallouts) {
      var n = 1;
      for (final c in grid.cells) {
        if (!lightIds.contains(c.id)) continue;
        final dx = visualOffsetX - grid.offsetXCm;
        final dy = visualOffsetY - grid.offsetYCm;
        final cx = c.xCm + dx + cell / 2;
        final cy = c.yCm + dy + cell / 2;
        final p = metrics.map(cx, cy);
        final label = '$n · ${c.id}';
        n++;
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Color(0xFFE65100),
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final bg = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: p,
            width: tp.width + 6,
            height: tp.height + 4,
          ),
          const Radius.circular(3),
        );
        canvas.drawRRect(bg, Paint()..color = const Color(0xEEFFF3E0));
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
    }

    if (options.showWalls) {
      for (final w in walls) {
        final a = metrics.map(w[0], w[1]);
        final b = metrics.map(w[2], w[3]);
        canvas.drawLine(a, b, wallPaint);
        if (showWallDims) {
          final len = math.sqrt(math.pow(w[2] - w[0], 2) + math.pow(w[3] - w[1], 2));
          DimensionLines.drawSegmentDimension(
            canvas,
            a: a,
            b: b,
            label: len.toStringAsFixed(0),
            color: CanvasPalette.wall,
            offsetPx: 22,
          );
        }
      }
    }

    if (options.showNotes) {
      final note = (notesOverlay ?? '').trim();
      if (note.isNotEmpty) {
        final short = note.length > 120 ? '${note.substring(0, 117)}…' : note;
        final tp = TextPainter(
          text: TextSpan(
            text: short,
            style: const TextStyle(color: Color(0xFF37474F), fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width * 0.35);
        const pad = 6.0;
        final bg = RRect.fromRectAndRadius(
          Rect.fromLTWH(8, 8, tp.width + pad * 2, tp.height + pad * 2),
          const Radius.circular(4),
        );
        canvas.drawRRect(bg, Paint()..color = const Color(0xCCFFFDE7));
        tp.paint(canvas, const Offset(8 + pad, 8 + pad));
      }
    }
  }

  void _paintGuides(Canvas canvas, double cell) {
    final cellSize = grid.cellSizeCm;
    for (final mark in guides.values) {
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
        walls,
        offsetX: visualOffsetX,
        offsetY: visualOffsetY,
        cellSize: cellSize,
        coordCm: coord,
        anchorAlongCm: anchorCm,
      );
      final color = _guideColor(mark.kind);
      final stroke = mark.kind == GuideKind.g3600 ? 4.0 : 2.8;
      for (final seg in segments) {
        final a = metrics.map(seg.x1, seg.y1);
        final b = metrics.map(seg.x2, seg.y2);
        final paint = Paint()
          ..color = color.withValues(alpha: 0.92)
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(a, b, paint);
      }
    }
  }

  static Color _guideColor(GuideKind kind) {
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

  @override
  bool shouldRepaint(covariant AsBuiltLayoutPainter old) => true;
}

AsBuiltSceneData buildAsBuiltScene(Room room) {
  final grid = CeilingGrid(
    offsetXCm: room.gridOffsetX.toDouble(),
    offsetYCm: room.gridOffsetY.toDouble(),
  );
  final lights = <String>{};
  for (final f in room.lightFixtures) {
    if (f.length >= 2) lights.add('${f[0]}:${f[1]}');
  }
  grid.rebuild(
    roomPoints: pointsFromWalls(room.walls),
    walls: room.walls,
    lightIds: lights,
  );
  final guides = {
    for (final g in parseCeilingGuidesWithLegacyAnchor(
      room.ceilingGuides,
      room.walls,
      offsetX: room.gridOffsetX.toDouble(),
      offsetY: room.gridOffsetY.toDouble(),
      cellSize: grid.cellSizeCm,
    ))
      g.storageKey: g,
  };
  return AsBuiltSceneData(
    grid: grid,
    lightIds: lights,
    guides: guides,
    visualOffsetX: room.gridOffsetX.toDouble(),
    visualOffsetY: room.gridOffsetY.toDouble(),
  );
}

class AsBuiltSceneData {
  AsBuiltSceneData({
    required this.grid,
    required this.lightIds,
    required this.guides,
    required this.visualOffsetX,
    required this.visualOffsetY,
  });

  final CeilingGrid grid;
  final Set<String> lightIds;
  final Map<String, CeilingGuideMark> guides;
  final double visualOffsetX;
  final double visualOffsetY;
}

Future<Uint8List> renderAsBuiltPng(
  Room room, {
  Size size = const Size(1200, 900),
  AsBuiltExportOptions options = const AsBuiltExportOptions(),
}) async {
  final scene = buildAsBuiltScene(room);
  final metrics = AsBuiltMetrics.compute(size, room.walls);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  AsBuiltLayoutPainter(
    walls: room.walls,
    grid: scene.grid,
    metrics: metrics,
    lightIds: scene.lightIds,
    guides: scene.guides,
    visualOffsetX: scene.visualOffsetX,
    visualOffsetY: scene.visualOffsetY,
    options: options,
    notesOverlay: RoomDocumentationChecklist.fromJson(room.documentationChecklistJson).notes,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Ceiling + floor + walls schemes stacked vertically for PNG export.
Future<Uint8List> renderCombinedAsBuiltPng(
  Room room, {
  AsBuiltExportOptions options = const AsBuiltExportOptions(),
  Size size = const Size(1200, 900),
}) async {
  final ceilingBytes = await renderAsBuiltPng(room, options: options, size: size);
  final floorBytes =
      await renderFloorPlanPng(room, size: size, showWallDims: options.showWallDims);
  final wallBytes = await renderWallFinishPng(room, pageSize: size);

  final panels = <(String, Uint8List)>[
    if (ceilingBytes.isNotEmpty) ('Потолок', ceilingBytes),
    if (options.showFloor && floorBytes.isNotEmpty) ('Пол', floorBytes),
    if (options.showWalls && wallBytes.isNotEmpty) ('Стены', wallBytes),
  ];
  if (panels.isEmpty) return Uint8List(0);
  if (panels.length == 1) return panels.first.$2;

  final frames = <(String, ui.Image)>[];
  for (final (label, bytes) in panels) {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    frames.add((label, frame.image));
  }

  const gap = 48.0;
  const labelH = 28.0;
  var w = 0.0;
  var h = 0.0;
  for (final (_, img) in frames) {
    w = math.max(w, img.width.toDouble());
    h += labelH + img.height;
  }
  h += gap * (frames.length - 1);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);

  var y = 0.0;
  for (var i = 0; i < frames.length; i++) {
    final (label, img) = frames[i];
    if (i > 0) y += gap;
    final title = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);
    title.paint(canvas, Offset((w - title.width) / 2, y + 4));
    canvas.drawImage(
      img,
      Offset((w - img.width) / 2, y + labelH),
      Paint(),
    );
    y += labelH + img.height;
  }

  final picture = recorder.endRecording();
  final out = await picture.toImage(w.toInt(), h.toInt());
  final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

Future<Uint8List> buildAsBuiltPdf({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  AsBuiltExportOptions options = const AsBuiltExportOptions(),
}) async {
  final png = await renderAsBuiltPng(room, options: options);
  final pdf = await PdfFonts.newDocument();
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  final qrPayload = buildDocumentQrPayload(
    docType: 'as_built_ceiling',
    projectName: project.name,
    roomName: room.name,
    issuedAt: stampFilled.issueDate,
    documentNumber: stampFilled.documentNumber,
    projectId: project.id,
    roomId: room.id,
  );

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pdfGostTitleBlock(stamp: stampFilled, roomName: room.name),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.Center(
                child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 8),
            documentQrFooter(payload: qrPayload),
          ],
        );
      },
    ),
  );
  return pdf.save();
}

/// Stamped PDF for any as-built scheme kind (ceiling / floor / walls / combined).
Future<Uint8List> buildSchemePdf({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  required AsBuiltSchemeKind scheme,
  AsBuiltExportOptions options = const AsBuiltExportOptions(),
}) async {
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  switch (scheme) {
    case AsBuiltSchemeKind.combined:
      return buildCombinedAsBuiltPdf(
        project: project,
        room: room,
        stamp: stamp,
        options: options,
      );
    case AsBuiltSchemeKind.ceiling:
      return buildAsBuiltPdf(
        project: project,
        room: room,
        stamp: stamp,
        options: options,
      );
    case AsBuiltSchemeKind.floor:
    case AsBuiltSchemeKind.walls:
      break;
  }

  final Uint8List rawPng = switch (scheme) {
    AsBuiltSchemeKind.floor =>
        await renderFloorPlanPng(room, showWallDims: options.showWallDims),
    AsBuiltSchemeKind.walls => await renderWallFinishPng(room),
    _ => Uint8List(0),
  };
  final png = await applyExportStamp(
    pngBytes: rawPng,
    stamp: stampFilled,
    roomName: room.name,
  );
  final caption = switch (scheme) {
    AsBuiltSchemeKind.floor => floorPlanCaption(room),
    AsBuiltSchemeKind.walls => 'Развёртка стен · раскладка и проёмы',
    _ => '',
  };
  final docType = scheme == AsBuiltSchemeKind.floor ? 'as_built_floor' : 'as_built_walls';

  final pdf = await PdfFonts.newDocument();
  final qrPayload = buildDocumentQrPayload(
    docType: docType,
    projectName: project.name,
    roomName: room.name,
    issuedAt: stampFilled.issueDate,
    documentNumber: stampFilled.documentNumber,
    projectId: project.id,
    roomId: room.id,
  );
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pdfGostTitleBlock(stamp: stampFilled, roomName: room.name),
          if (caption.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(caption, style: PdfFonts.text(fontSize: 9)),
          ],
          pw.SizedBox(height: 8),
          pw.Expanded(
            child: pw.Center(child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain)),
          ),
          pw.SizedBox(height: 8),
          documentQrFooter(payload: qrPayload),
        ],
      ),
    ),
  );
  return pdf.save();
}
