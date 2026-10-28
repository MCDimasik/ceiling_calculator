import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/widgets/finish_painters.dart';
import 'dimension_lines.dart';
import 'floor_covering.dart';
import 'floor_layout.dart';
import 'models.dart';

Future<Uint8List> renderFloorPlanPng(
  Room room, {
  Size size = const Size(1200, 900),
  bool showWallDims = true,
}) async {
  if (!room.hasLayout) {
    return Uint8List(0);
  }
  final covering = FloorCoveringKindX.parse(room.floorCoveringKind);
  final pattern = FloorLayingPatternX.parse(room.floorLayingPattern);
  final layout = FloorLayoutBuilder.build(
    walls: room.walls,
    covering: covering,
    pattern: pattern,
    boardW: room.finishTileWidthCm,
    boardL: room.finishTileHeightCm,
    offsetX: room.floorGridOffsetX.toDouble(),
    offsetY: room.floorGridOffsetY.toDouble(),
    rotationDeg: room.floorLayoutRotationDeg,
  );
  final metrics = FloorPlanMetrics.fromWalls(room.walls, size);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  FloorPlanPainter(
    walls: room.walls,
    metrics: metrics,
    layout: layout,
    showCutDims: true,
  ).paint(canvas, size);

  if (showWallDims) {
    const dimColor = Color(0xFF1565C0);
    for (final w in room.walls) {
      final len = DimensionLines.segmentLengthCm(w);
      if (len < 20) continue;
      final a = metrics.map(w[0], w[1]);
      final b = metrics.map(w[2], w[3]);
      DimensionLines.drawSegmentDimension(
        canvas,
        a: a,
        b: b,
        label: '${DimensionLines.formatCm(len)} см',
        color: dimColor,
        offsetPx: 22,
        placeAbove: true,
      );
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

String floorPlanCaption(Room room) {
  final k = FloorCoveringKindX.parse(room.floorCoveringKind);
  if (k == FloorCoveringKind.screed) {
    final d = room.floorScreedDepthCm <= 0
        ? defaultScreedDepthCm
        : room.floorScreedDepthCm;
    return 'Пол: ${k.labelRu} · толщина ${d.round()} см';
  }
  final p = FloorLayingPatternX.parse(room.floorLayingPattern);
  return 'Пол: ${k.labelRu} · ${p.labelRu} · ${room.finishTileWidthCm.round()}×${room.finishTileHeightCm.round()} см';
}
