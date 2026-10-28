import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

/// Embedded JPEG streams found in a PDF (largest first) — fast path for scans.
///
/// Parses JPEG marker structure so we don't swallow PDF bytes after a false EOI
/// (common cause of "Corrupt JPEG / Unsupported marker 0x3e").
List<Uint8List> extractEmbeddedJpegsFromPdf(List<int> bytes) {
  final data = Uint8List.fromList(bytes);
  final found = <Uint8List>[];
  var i = 0;
  while (i < data.length - 4) {
    if (data[i] != 0xFF || data[i + 1] != 0xD8) {
      i++;
      continue;
    }
    final end = _jpegEoiIndex(data, i);
    if (end == null) {
      i++;
      continue;
    }
    final slice = data.sublist(i, end + 2);
    if (_jpegHasSof(slice)) {
      found.add(slice);
    }
    i = end + 2;
  }
  found.sort((a, b) => b.length.compareTo(a.length));
  return found;
}

/// Embedded PNG streams (IHDR…IEND) — some CAD exports embed PNG, not JPEG.
List<Uint8List> extractEmbeddedPngsFromPdf(List<int> bytes) {
  final data = Uint8List.fromList(bytes);
  final found = <Uint8List>[];
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  var i = 0;
  while (i < data.length - 24) {
    var match = true;
    for (var k = 0; k < sig.length; k++) {
      if (data[i + k] != sig[k]) {
        match = false;
        break;
      }
    }
    if (!match) {
      i++;
      continue;
    }
    var pos = i + 8;
    var ok = false;
    while (pos + 12 <= data.length) {
      final len = (data[pos] << 24) |
          (data[pos + 1] << 16) |
          (data[pos + 2] << 8) |
          data[pos + 3];
      if (len < 0 || pos + 12 + len > data.length) break;
      final t0 = data[pos + 4];
      final t1 = data[pos + 5];
      final t2 = data[pos + 6];
      final t3 = data[pos + 7];
      final isIend = t0 == 0x49 && t1 == 0x45 && t2 == 0x4E && t3 == 0x44;
      pos += 12 + len;
      if (isIend) {
        found.add(data.sublist(i, pos));
        i = pos;
        ok = true;
        break;
      }
    }
    if (!ok) i++;
  }
  found.sort((a, b) => b.length.compareTo(a.length));
  return found;
}

/// Walk JPEG markers from SOI at [start]; return index of EOI 0xFFD9, or null.
int? _jpegEoiIndex(Uint8List data, int start) {
  if (start + 3 >= data.length) return null;
  var i = start + 2;
  while (i < data.length - 1) {
    if (data[i] != 0xFF) {
      i++;
      continue;
    }
    while (i < data.length && data[i] == 0xFF) {
      i++;
    }
    if (i >= data.length) return null;
    final marker = data[i];
    i++;
    if (marker == 0xD9) return i - 2; // EOI
    if (marker == 0xD8) return null; // nested SOI — abort
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    if (marker == 0xDA) {
      if (i + 1 >= data.length) return null;
      final segLen = (data[i] << 8) | data[i + 1];
      if (segLen < 2) return null;
      i += segLen;
      while (i < data.length - 1) {
        if (data[i] != 0xFF) {
          i++;
          continue;
        }
        final n = data[i + 1];
        if (n == 0x00) {
          i += 2;
          continue;
        }
        if (n == 0xD9) return i;
        break;
      }
      continue;
    }
    if (i + 1 >= data.length) return null;
    final segLen = (data[i] << 8) | data[i + 1];
    if (segLen < 2 || i + segLen > data.length) return null;
    i += segLen;
  }
  return null;
}

bool _jpegHasSof(Uint8List jpeg) {
  if (jpeg.length < 128) return false;
  if (jpeg[0] != 0xFF || jpeg[1] != 0xD8) return false;
  if (jpeg[jpeg.length - 2] != 0xFF || jpeg[jpeg.length - 1] != 0xD9) {
    return false;
  }
  var i = 2;
  while (i < jpeg.length - 3) {
    if (jpeg[i] != 0xFF) {
      i++;
      continue;
    }
    while (i < jpeg.length && jpeg[i] == 0xFF) {
      i++;
    }
    if (i >= jpeg.length) break;
    final marker = jpeg[i++];
    if (marker == 0xD9) break;
    if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8) {
      return true;
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0xDA) {
      break;
    }
    if (i + 1 >= jpeg.length) break;
    final segLen = (jpeg[i] << 8) | jpeg[i + 1];
    if (segLen < 2) break;
    i += segLen;
  }
  return false;
}

Future<bool> _codecCanDecode(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    frame.image.dispose();
    return true;
  } catch (_) {
    return false;
  }
}

Future<String?> _writeTempImage(Uint8List bytes, String ext) async {
  final dir = await getTemporaryDirectory();
  final out = File(
    p.join(dir.path, 'plan_${DateTime.now().millisecondsSinceEpoch}.$ext'),
  );
  await out.writeAsBytes(bytes);
  return out.path;
}

/// Soft cap only for pathological sheets (A0 @ 200dpi ≈ 6–7k). Vectors still
/// come from the PDF content stream — this only limits the **preview raster**.
const int kPdfPlanMaxEdgePx = 6000;

/// Decode [pngBytes], paint on white, optionally downscale so max edge ≤ [maxEdge].
Future<Uint8List?> _normalizePlanPng(
  Uint8List pngBytes, {
  int maxEdge = kPdfPlanMaxEdgePx,
}) async {
  try {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final sw = src.width;
    final sh = src.height;
    final long = math.max(sw, sh);
    final scale = long > maxEdge ? maxEdge / long : 1.0;
    final dw = math.max(1, (sw * scale).round());
    final dh = math.max(1, (sh * scale).round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, dw.toDouble(), dh.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
      ui.Rect.fromLTWH(0, 0, dw.toDouble(), dh.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    src.dispose();
    final picture = recorder.endRecording();
    final out = await picture.toImage(dw, dh);
    final bd = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    if (bd == null) return null;
    return bd.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Count PDF pages via PDFium raster pass (stops after probing).
/// Falls back to embedded image count when raster is unavailable.
Future<int> countPdfPages(String pdfPath) async {
  try {
    final bytes = await File(pdfPath).readAsBytes();
    var n = 0;
    // Low DPI + stop early — only need a count, not full pages.
    await for (final _ in Printing.raster(bytes, dpi: 18)) {
      n++;
      if (n >= 40) break;
    }
    if (n > 0) return n;
  } catch (_) {}
  final bytes = await File(pdfPath).readAsBytes();
  final embedded = extractEmbeddedJpegsFromPdf(bytes).length +
      extractEmbeddedPngsFromPdf(bytes).length;
  return embedded;
}

/// @deprecated Use [countPdfPages].
int countPdfEmbeddedPages(String pdfPath) {
  final bytes = File(pdfPath).readAsBytesSync();
  return extractEmbeddedJpegsFromPdf(bytes).length +
      extractEmbeddedPngsFromPdf(bytes).length;
}

/// Rasterize a PDF plan page for corner tapping / auto-outline.
///
/// Strategy:
/// 1. Prefer real page render via PDFium ([Printing.raster]) — works for
///    vector plans (CAD / «чертёж линиями»), not only scanned JPEGs.
/// 2. Fallback: largest embedded JPEG/PNG stream (legacy scans).
///
/// Only the requested page is rasterized; output is capped to [kPdfPlanMaxEdgePx].
Future<String?> rasterizePdfPlanPage(String pdfPath, {int pageIndex = 0}) async {
  final bytes = await File(pdfPath).readAsBytes();

  // 1) True page raster — only the selected page (vector extract still uses
  // the original PDF bytes; this raster is preview / photo-fallback only).
  for (final dpi in const [200.0, 150.0, 120.0]) {
    try {
      await for (final page in Printing.raster(
        bytes,
        pages: [pageIndex],
        dpi: dpi,
      )) {
        final png = await page.toPng();
        final normalized = await _normalizePlanPng(png);
        if (normalized != null && await _codecCanDecode(normalized)) {
          return await _writeTempImage(normalized, 'png');
        }
        break;
      }
    } catch (_) {
      // Try lower DPI / fall through.
    }
  }

  // 2) Embedded raster streams (fast path for photo-scans).
  final images = <(Uint8List, String)>[
    for (final j in extractEmbeddedJpegsFromPdf(bytes)) (j, 'jpg'),
    for (final png in extractEmbeddedPngsFromPdf(bytes)) (png, 'png'),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));

  if (images.isEmpty) return null;
  final idx = pageIndex.clamp(0, images.length - 1);
  for (var k = idx; k < images.length; k++) {
    final (data, ext) = images[k];
    if (ext == 'png') {
      final normalized = await _normalizePlanPng(data);
      if (normalized != null && await _codecCanDecode(normalized)) {
        return await _writeTempImage(normalized, 'png');
      }
    }
    if (await _codecCanDecode(data)) {
      return await _writeTempImage(data, ext);
    }
  }
  return null;
}

Future<String?> rasterizePdfPlanFirstPage(String pdfPath) =>
    rasterizePdfPlanPage(pdfPath, pageIndex: 0);

/// Human-readable reason when [rasterizePdfPlanPage] returns null.
String pdfPlanUnsupportedMessage() =>
    'Не удалось открыть страницу PDF.\n'
    'Попробуйте другую страницу или экспортируйте лист как JPG/PNG.';

bool isPdfPath(String path) => p.extension(path).toLowerCase() == '.pdf';
