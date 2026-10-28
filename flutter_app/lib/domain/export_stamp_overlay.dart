import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'documentation_model.dart';

/// Draws a compact GOST-style stamp block into [area].
void drawExportStampBlock(
  Canvas canvas,
  Rect area, {
  required DocumentationStamp stamp,
  required String roomName,
  bool lightTheme = true,
}) {
  final fill = lightTheme ? const Color(0xFFFAFAFA) : const Color(0xFF1F2121);
  final border = lightTheme ? const Color(0xFF455A64) : const Color(0xFFB0BEC5);
  final textColor = lightTheme ? const Color(0xFF263238) : const Color(0xFFECEFF1);
  final lines = stamp.stampLines(roomName: roomName);

  canvas.drawRect(area, Paint()..color = fill);
  canvas.drawRect(
    area,
    Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );

  _drawScaleBar(canvas, area, textColor);

  const pad = 8.0;
  const colGap = 16.0;
  var y = area.top + pad;
  final titleTp = TextPainter(
    text: TextSpan(
      text: stamp.sheetTitle,
      style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: area.width - pad * 2);
  titleTp.paint(canvas, Offset(area.left + pad, y));
  y += titleTp.height + 6;

  final half = (area.width - pad * 2 - colGap) / 2;
  var leftY = y;
  var rightY = y;
  for (var i = 0; i < lines.length; i++) {
    final (label, value) = lines[i];
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: '$label: ', style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 9)),
          TextSpan(text: value, style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.w600)),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: half);
    if (i.isEven) {
      tp.paint(canvas, Offset(area.left + pad, leftY));
      leftY += tp.height + 3;
    } else {
      tp.paint(canvas, Offset(area.left + pad + half + colGap, rightY));
      rightY += tp.height + 3;
    }
  }
}

/// Compact scale reference in stamp band (GOST-style hint).
void _drawScaleBar(Canvas canvas, Rect area, Color textColor) {
  const barCm = 100.0;
  final barPx = (area.width * 0.18).clamp(48.0, 120.0);
  final left = area.right - barPx - 12;
  final y = area.top + 10;
  final paint = Paint()
    ..color = textColor
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(left, y), Offset(left + barPx, y), paint);
  canvas.drawLine(Offset(left, y - 4), Offset(left, y + 4), paint);
  canvas.drawLine(Offset(left + barPx, y - 4), Offset(left + barPx, y + 4), paint);
  final tp = TextPainter(
    text: TextSpan(
      text: '${barCm.round()} см',
      style: TextStyle(color: textColor, fontSize: 8),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(left + (barPx - tp.width) / 2, y + 5));
}

/// Appends stamp band below the image bytes (for PNG export packs).
Future<Uint8List> applyExportStamp({
  required Uint8List pngBytes,
  required DocumentationStamp stamp,
  required String roomName,
  double stampBandHeight = 132,
}) async {
  if (pngBytes.isEmpty) return pngBytes;

  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;

  final w = image.width.toDouble();
  final h = image.height.toDouble() + stampBandHeight;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
  canvas.drawImage(image, Offset.zero, Paint());
  drawExportStampBlock(
    canvas,
    Rect.fromLTWH(0, image.height.toDouble(), w, stampBandHeight),
    stamp: stamp,
    roomName: roomName,
    lightTheme: true,
  );

  final picture = recorder.endRecording();
  final out = await picture.toImage(w.toInt(), h.toInt());
  final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
