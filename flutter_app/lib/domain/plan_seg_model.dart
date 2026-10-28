import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// DeepLabV3-MobileNet wall/room segmentation (CubiCasa fine-tune).
///
/// Classes: 0=background, 1=wall, 2=room.
///
/// Trained on **schematic floor-plan drawings** (CubiCasa5K), not photos of
/// real rooms. Best on clean top-down plan images / scans of drawings.
class PlanSegModel {
  PlanSegModel._();

  static const assetKey = 'assets/ml/room_walls.onnx';
  static const _size = 512;
  static const _mean = [0.485, 0.456, 0.406];
  static const _std = [0.229, 0.224, 0.225];

  static OrtSession? _session;
  static Future<OrtSession?>? _loading;
  static bool _unavailable = false;

  /// Last failure reason for UI (Russian, short).
  static String? lastError;

  static Future<OrtSession?> _ensureSession() async {
    if (_unavailable) return null;
    if (_session != null) return _session;
    if (_loading != null) return _loading;
    _loading = _openSession();
    try {
      _session = await _loading;
    } finally {
      _loading = null;
    }
    if (_session == null) {
      _unavailable = true;
      lastError ??= 'Не удалось загрузить ONNX-модель сегментации.';
    }
    return _session;
  }

  static Future<OrtSession?> _openSession() async {
    final ort = OnnxRuntime();
    try {
      final s = await ort.createSessionFromAsset(assetKey);
      debugPrint('PlanSegModel: loaded asset $assetKey');
      return s;
    } catch (e) {
      debugPrint('PlanSegModel: asset load failed: $e');
    }
    for (final path in [
      r'D:\celling_dateset\runs\deeplab_rooms\room_walls.onnx',
      p.join(
        (await getApplicationSupportDirectory()).path,
        'room_walls.onnx',
      ),
    ]) {
      if (!File(path).existsSync()) continue;
      try {
        final s = await ort.createSession(path);
        debugPrint('PlanSegModel: loaded file $path');
        return s;
      } catch (e) {
        debugPrint('PlanSegModel: file load failed ($path): $e');
      }
    }
    lastError = 'Модель room_walls.onnx не найдена в assets.';
    return null;
  }

  static Future<bool> isAvailable() async =>
      (await _ensureSession()) != null;

  /// Decode [imageBytes] and stretch to exactly [_size]×[_size] RGBA.
  static Future<Uint8List?> _rgba512(Uint8List imageBytes) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, _size.toDouble(), _size.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    src.dispose();
    final picture = recorder.endRecording();
    final out = await picture.toImage(_size, _size);
    final bd = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    out.dispose();
    return bd?.buffer.asUint8List();
  }

  /// Run segmentation; returns HxW class indices at model resolution (_size).
  static Future<Uint8List?> predictClasses(Uint8List imageBytes) async {
    lastError = null;
    final session = await _ensureSession();
    if (session == null) return null;

    final rgba = await _rgba512(imageBytes);
    if (rgba == null || rgba.length < _size * _size * 4) {
      lastError = 'Не удалось подготовить изображение для модели.';
      return null;
    }

    final n = _size * _size;
    final input = Float32List(3 * n);
    for (var i = 0; i < n; i++) {
      final o = i * 4;
      final r = rgba[o] / 255.0;
      final g = rgba[o + 1] / 255.0;
      final b = rgba[o + 2] / 255.0;
      input[i] = (r - _mean[0]) / _std[0];
      input[n + i] = (g - _mean[1]) / _std[1];
      input[2 * n + i] = (b - _mean[2]) / _std[2];
    }

    final inputName = session.inputNames.first;
    final outputName = session.outputNames.first;
    late final OrtValue tensor;
    try {
      tensor = await OrtValue.fromList(input, [1, 3, _size, _size]);
    } catch (e) {
      lastError = 'Ошибка тензора входа: $e';
      debugPrint('PlanSegModel: OrtValue.fromList $e');
      return null;
    }

    try {
      final outputs = await session.run({inputName: tensor});
      try {
        final out = outputs[outputName];
        if (out == null) {
          lastError = 'Модель не вернула logits.';
          return null;
        }
        final flat = await out.asFlattenedList();
        if (flat.length < 3 * n) {
          lastError =
              'Неожиданный размер выхода модели (${flat.length} < ${3 * n}).';
          return null;
        }
        final classes = Uint8List(n);
        var c0 = 0, c1 = 0, c2 = 0;
        for (var i = 0; i < n; i++) {
          var bestC = 0;
          var bestV = -double.infinity;
          for (var c = 0; c < 3; c++) {
            final v = (flat[c * n + i] as num).toDouble();
            if (v > bestV) {
              bestV = v;
              bestC = c;
            }
          }
          classes[i] = bestC;
          if (bestC == 0) {
            c0++;
          } else if (bestC == 1) {
            c1++;
          } else {
            c2++;
          }
        }
        debugPrint('PlanSegModel: classes bg=$c0 wall=$c1 room=$c2');
        if (c2 < 80 && c1 < 80) {
          lastError =
              'Модель почти не видит стены/комнаты на этом фото '
              '(обучена на схемах планов, не на фото интерьера).';
        }
        return classes;
      } finally {
        for (final v in outputs.values) {
          await v.dispose();
        }
      }
    } catch (e) {
      lastError = 'Сбой инференса: $e';
      debugPrint('PlanSegModel: run $e');
      return null;
    } finally {
      await tensor.dispose();
    }
  }

  /// Outline at [tapImage] (full-res image coords).
  ///
  /// CubiCasa often predicts one big "room" blob through door gaps. We seal
  /// predicted walls (dilate) then flood from the tap — same idea as classical
  /// plan outline, but barriers come from the network.
  static Future<List<ui.Offset>?> outlineRoomAtTap({
    required Uint8List imageBytes,
    required ui.Offset tapImage,
    required int imageWidth,
    required int imageHeight,
  }) async {
    final classes = await predictClasses(imageBytes);
    if (classes == null) return null;

    final sx = _size / imageWidth;
    final sy = _size / imageHeight;
    final tx = (tapImage.dx * sx).round().clamp(0, _size - 1);
    final ty = (tapImage.dy * sy).round().clamp(0, _size - 1);

    final baseWall = List<bool>.generate(
      _size * _size,
      (i) => classes[i] == 1,
      growable: false,
    );

    // Stronger seals first close doors between rooms on dense экспликации.
    for (final seal in const [2, 3, 4, 6, 8, 1]) {
      final wall = List<bool>.from(baseWall);
      _dilate(wall, _size, _size, seal);

      var x0 = tx;
      var y0 = ty;
      if (wall[y0 * _size + x0]) {
        final near = _nearestFalse(wall, tx, ty, 48);
        if (near == null) continue;
        x0 = near.$1;
        y0 = near.$2;
      }

      // Prefer staying on predicted room pixels when possible.
      final polyRoom = _floodTrace(
        seedX: x0,
        seedY: y0,
        canEnter: (j) => !wall[j] && classes[j] == 2,
        maxFrac: 0.35,
        rejectBorderLeak: true,
      );
      if (polyRoom != null) {
        return _toFull(polyRoom, imageWidth, imageHeight);
      }

      final polyOpen = _floodTrace(
        seedX: x0,
        seedY: y0,
        canEnter: (j) => !wall[j],
        maxFrac: 0.30,
        rejectBorderLeak: true,
      );
      if (polyOpen != null) {
        return _toFull(polyOpen, imageWidth, imageHeight);
      }
    }

    // Last resort: raw room CC without size panic (whole flat as one outline).
    final loose = _outlineLooseRoom(classes, tx, ty);
    if (loose != null) {
      return _toFull(loose, imageWidth, imageHeight);
    }

    lastError ??=
        'Модель видит план, но не отделила комнату в точке тапа '
        '(щели в дверях). Тапните в центр нужной комнаты.';
    return null;
  }

  static List<ui.Offset>? _toFull(
    List<ui.Offset> poly,
    int imageWidth,
    int imageHeight,
  ) {
    final toX = imageWidth / _size;
    final toY = imageHeight / _size;
    return [for (final p in poly) ui.Offset(p.dx * toX, p.dy * toY)];
  }

  static List<ui.Offset>? _outlineLooseRoom(
    Uint8List classes,
    int tx,
    int ty,
  ) {
    var x0 = tx;
    var y0 = ty;
    if (classes[y0 * _size + x0] != 2) {
      final near = _nearestClass(classes, _size, _size, tx, ty, 2, 64);
      if (near == null) return null;
      x0 = near.$1;
      y0 = near.$2;
    }
    return _floodTrace(
      seedX: x0,
      seedY: y0,
      canEnter: (j) => classes[j] == 2,
      maxFrac: 0.85,
      rejectBorderLeak: false,
    );
  }

  static void _dilate(List<bool> m, int w, int h, int passes) {
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

  static List<ui.Offset>? _floodTrace({
    required int seedX,
    required int seedY,
    required bool Function(int j) canEnter,
    required double maxFrac,
    bool rejectBorderLeak = false,
  }) {
    final filled = List<bool>.filled(_size * _size, false);
    final stack = <int>[seedY * _size + seedX];
    if (!canEnter(stack.first)) return null;
    filled[stack.first] = true;
    var count = 0;
    var border = 0;
    final maxFill = (_size * _size * maxFrac).round();
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      count++;
      if (count > maxFill) return null;
      final x = i % _size;
      final y = i ~/ _size;
      if (x == 0 || y == 0 || x == _size - 1 || y == _size - 1) border++;
      for (final (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
        if (nx < 0 || ny < 0 || nx >= _size || ny >= _size) continue;
        final j = ny * _size + nx;
        if (filled[j] || !canEnter(j)) continue;
        filled[j] = true;
        stack.add(j);
      }
    }
    if (rejectBorderLeak && border > math.max(20, _size ~/ 8)) return null;
    if (count < 40) return null;

    final boundary = _mooreBoundary(filled, _size, _size);
    if (boundary.length < 4) return null;
    final simplified = _simplify(boundary, _size, _size);
    if (simplified.length < 3) return null;
    return simplified;
  }

  static (int, int)? _nearestFalse(List<bool> wall, int cx, int cy, int r) {
    for (var d = 1; d <= r; d++) {
      for (var dy = -d; dy <= d; dy++) {
        for (var dx = -d; dx <= d; dx++) {
          if (dx.abs() != d && dy.abs() != d) continue;
          final x = cx + dx;
          final y = cy + dy;
          if (x < 0 || y < 0 || x >= _size || y >= _size) continue;
          if (!wall[y * _size + x]) return (x, y);
        }
      }
    }
    return null;
  }

  static (int, int)? _nearestClass(
    Uint8List classes,
    int w,
    int h,
    int cx,
    int cy,
    int cls,
    int r,
  ) {
    for (var d = 1; d <= r; d++) {
      for (var dy = -d; dy <= d; dy++) {
        for (var dx = -d; dx <= d; dx++) {
          if (dx.abs() != d && dy.abs() != d) continue;
          final x = cx + dx;
          final y = cy + dy;
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          if (classes[y * w + x] == cls) return (x, y);
        }
      }
    }
    return null;
  }

  static List<ui.Offset> _mooreBoundary(List<bool> inside, int w, int h) {
    bool inb(int x, int y) =>
        x >= 0 && y >= 0 && x < w && y < h && inside[y * w + x];
    var sx = -1, sy = -1;
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
    var x = sx, y = sy, backDir = 0;
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

  static List<ui.Offset> _simplify(List<ui.Offset> ordered, int w, int h) {
    var eps = math.max(2.0, math.min(w, h) / 50.0);
    var simplified = _dp(ordered, eps);
    while (simplified.length > 24 && eps < 20) {
      eps += 1.2;
      simplified = _dp(ordered, eps);
    }
    return simplified;
  }

  static List<ui.Offset> _dp(List<ui.Offset> pts, double eps) {
    if (pts.length < 3) return pts;
    var maxD = 0.0;
    var idx = 0;
    final a = pts.first;
    final b = pts.last;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = _perp(pts[i], a, b);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > eps) {
      final left = _dp(pts.sublist(0, idx + 1), eps);
      final right = _dp(pts.sublist(idx), eps);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [a, b];
  }

  static double _perp(ui.Offset p, ui.Offset a, ui.Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-9) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
    final proj = ui.Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }
}
