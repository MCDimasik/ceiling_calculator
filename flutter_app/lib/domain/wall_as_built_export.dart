import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'canvas_metrics.dart';
import 'finish_model.dart';
import 'finish_quantities.dart';
import 'floor_covering.dart';
import 'floor_layout.dart';
import 'models.dart';
import 'wall_elevation_geometry.dart';
import 'wall_elevation_painter.dart';

FinishLayer? _firstEnabledWallTileLayer(Room room) {
  for (final raw in room.wallFinishLayers) {
    final l = FinishLayer.fromJson(raw);
    if (l.enabled && l.kind == FinishLayerKind.tile) return l;
  }
  return null;
}

FloorLayoutSnapshot _wallTileLayout({
  required double wallLen,
  required double wallH,
  required FinishLayer tile,
}) {
  final rect = wallElevationPolygon(wallLen, wallH);
  return FloorLayoutBuilder.build(
    walls: rect,
    covering: FloorCoveringKind.tile,
    pattern: FloorLayingPattern.straight,
    boardW: tile.tileWidthCm,
    boardL: tile.tileHeightCm,
    offsetX: tile.tileOffsetX.toDouble(),
    offsetY: tile.tileOffsetY.toDouble(),
  );
}

/// CAD wall elevations with tile layout and opening cutouts.
Future<Uint8List> renderWallElevationCadPng(
  Room room, {
  Size pageSize = const Size(1600, 1200),
}) async {
  if (!room.hasLayout) return Uint8List(0);

  final h = room.ceilingHeightCm;
  final tile = _firstEnabledWallTileLayer(room);
  final openings = room.openings.map(RoomOpening.fromJson).toList();
  final wallCount = room.walls.length;

  const margin = 24.0;
  const headerH = 56.0;
  const cols = 2;
  final rows = (wallCount / cols).ceil();
  final panelW = (pageSize.width - margin * 2) / cols;
  final panelH = (pageSize.height - margin * 2 - headerH) / rows;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
    Paint()..color = Colors.white,
  );

  final title = TextPainter(
    text: const TextSpan(
      text: 'Развёртка стен · исполнительная схема',
      style: TextStyle(color: Colors.black87, fontSize: 22, fontWeight: FontWeight.bold),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: pageSize.width - margin * 2);
  title.paint(canvas, Offset(margin, margin));

  final sub = TextPainter(
    text: TextSpan(
      text: '${room.name} · высота ${h.round()} см',
      style: const TextStyle(color: Colors.black54, fontSize: 14),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: pageSize.width - margin * 2);
  sub.paint(canvas, Offset(margin, margin + title.height + 4));

  for (var wi = 0; wi < wallCount; wi++) {
    final col = wi % cols;
    final row = wi ~/ cols;
    final ox = margin + col * panelW;
    final oy = margin + headerH + row * panelH;

    final w = room.walls[wi];
    final len = wallSegmentLengthCm(w);
    final rect = wallElevationPolygon(len, h);
    final wallOpenings = openingRectsOnWall(
      wallIndex: wi,
      wallLengthCm: len,
      roomHeightCm: h,
      openings: openings,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(ox + 4, oy + 4, panelW - 8, panelH - 8),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFFF5F5F5),
    );

    final inner = Rect.fromLTWH(ox + 12, oy + 12, panelW - 24, panelH - 24);
    final metrics = FloorPlanMetrics.fromRect(len, h, Size(inner.width, inner.height));
    final layout = tile != null
        ? _wallTileLayout(wallLen: len, wallH: h, tile: tile)
        : const FloorLayoutSnapshot(boards: [], fullCount: 0, cutCount: 0);

    canvas.save();
    canvas.translate(inner.left, inner.top);
    canvas.clipRect(Rect.fromLTWH(0, 0, inner.width, inner.height));
    final painter = WallElevationPainter(
      walls: rect,
      metrics: metrics,
      layout: layout,
      openings: wallOpenings,
      lightBackground: true,
      wallLabel: 'Стена ${wi + 1} · ${len.round()}×${h.round()} см',
      showCutDims: tile != null,
      showElevationDims: true,
    );
    painter.paint(canvas, Size(inner.width, inner.height));
    canvas.restore();

    if (tile == null) {
      final note = TextPainter(
        text: const TextSpan(
          text: 'Слой плитки не задан — контур и проёмы',
          style: TextStyle(color: Colors.black45, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: inner.width);
      note.paint(canvas, Offset(inner.left, inner.bottom - note.height - 4));
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(pageSize.width.toInt(), pageSize.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Summary + CAD elevations for documentation pack.
Future<Uint8List> renderWallFinishPng(Room room, {Size pageSize = const Size(1200, 900)}) async {
  if (!room.hasLayout) return Uint8List(0);

  final layers = room.wallFinishLayers.map(FinishLayer.fromJson).where((l) => l.enabled).toList();
  final openings = room.openings.map(RoomOpening.fromJson).toList();
  final counts = finishLayoutCountsForRoom(room);
  final areas = FinishCalculator.compute(
    walls: room.walls,
    heightCm: room.ceilingHeightCm,
    openings: openings,
    tileWidthCm: room.finishTileWidthCm,
    tileHeightCm: room.finishTileHeightCm,
    floorLayoutBoardCount: counts.floorBoards,
    wallLayoutTileCount: counts.wallTiles,
    ceilingLayoutTileCount: counts.ceilingTiles,
    wallLayers: layers,
  );
  final wallTiles = counts.wallTiles;
  final skirting = skirtingLengthM(room);

  const summaryH = 340.0;
  final cadH = pageSize.height - summaryH;
  final cadPage = Size(pageSize.width, math.max(cadH, 600));
  final cadBytes = await renderWallElevationCadPng(
    room,
    pageSize: cadPage,
  );
  if (cadBytes.isEmpty) return Uint8List(0);

  final codec = await ui.instantiateImageCodec(cadBytes);
  final frame = await codec.getNextFrame();
  final cadImage = frame.image;

  final totalH = summaryH + cadImage.height.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, pageSize.width, totalH),
    Paint()..color = Colors.white,
  );

  var y = 32.0;
  void drawLine(String text, {double fontSize = 16, FontWeight weight = FontWeight.normal}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Colors.black87, fontSize: fontSize, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: pageSize.width - 64);
    tp.paint(canvas, Offset(32, y));
    y += tp.height + 8;
  }

  drawLine('Исполнительная сводка · стены', fontSize: 22, weight: FontWeight.bold);
  drawLine('Помещение: ${room.name}');
  drawLine('Высота: ${room.ceilingHeightCm.round()} см');
  drawLine('Стены: ${areas.wallsNetM2.toStringAsFixed(2)} м²');
  drawLine('Проёмы: ${areas.openingsM2.toStringAsFixed(2)} м²');
  if (skirting > 0) drawLine('Плинтус: ${skirting.toStringAsFixed(1)} п.м.');
  if (wallTiles > 0) drawLine('Плитка (раскладка всех стен): $wallTiles шт + запас');
  y += 4;
  drawLine('Слои отделки:', weight: FontWeight.bold);
  for (final q in areas.wallLayers) {
    final extra = q.layer.kind == FinishLayerKind.tile ? ' · ${q.tilesEstimate} шт (раскладка)' : '';
    drawLine('• ${q.layer.displayLabel}: ${q.areaM2.toStringAsFixed(2)} м²$extra');
  }
  if (layers.isEmpty) drawLine('• Слои не заданы');

  canvas.drawImage(
    cadImage,
    Offset(0, summaryH),
    Paint(),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(pageSize.width.toInt(), totalH.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  cadImage.dispose();
  return bytes!.buffer.asUint8List();
}
