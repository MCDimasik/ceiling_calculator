import 'dart:math' as math;

enum CeilingType { armstrong, grilyatoGl, grilyatoClassic }

/// Pure port of Python `materials_calculator.py` (no Flutter UI deps).
class MaterialsCalculator {
  MaterialsCalculator._();

  static int ceilDiv(num value, num divisor) {
    if (divisor == 0) return 0;
    return (value / divisor).ceil();
  }

  static double roomPerimeterCm(List<List<double>> walls) {
    if (walls.isEmpty) return 0;
    var p = 0.0;
    for (final w in walls) {
      p += math.sqrt((w[2] - w[0]) * (w[2] - w[0]) + (w[3] - w[1]) * (w[3] - w[1]));
    }
    return p;
  }

  static (double, double) roomDimsCm(List<List<double>> walls) {
    if (walls.isEmpty) return (0, 0);
    final xs = <double>[];
    final ys = <double>[];
    for (final w in walls) {
      xs.addAll([w[0], w[2]]);
      ys.addAll([w[1], w[3]]);
    }
    return (xs.reduce(math.max) - xs.reduce(math.min), ys.reduce(math.max) - ys.reduce(math.min));
  }

  static List<(double, double)> orderedPointsFromWalls(List<List<double>> walls) {
    if (walls.isEmpty) return [];
    final points = <(double, double)>[(walls[0][0], walls[0][1])];
    for (final w in walls) {
      final a = (w[0], w[1]);
      final b = (w[2], w[3]);
      if (points.isEmpty || points.last != a) points.add(a);
      points.add(b);
    }
    if (points.length > 1 && points.first == points.last) {
      points.removeLast();
    }
    return points;
  }

  static double roomAreaM2(List<List<double>> walls) {
    final points = orderedPointsFromWalls(walls);
    if (points.length < 3) return 0;
    var s = 0.0;
    final n = points.length;
    for (var i = 0; i < n; i++) {
      final a = points[i];
      final b = points[(i + 1) % n];
      s += a.$1 * b.$2 - b.$1 * a.$2;
    }
    return s.abs() * 0.5 / 10000.0;
  }

  static List<double> _segmentLengths(List<(double, double)> points) {
    final lengths = <double>[];
    final n = points.length;
    for (var i = 0; i < n; i++) {
      final a = points[i];
      final b = points[(i + 1) % n];
      lengths.add(math.sqrt((b.$1 - a.$1) * (b.$1 - a.$1) + (b.$2 - a.$2) * (b.$2 - a.$2)));
    }
    return lengths;
  }

  static bool _isRectangle(List<(double, double)> points, {double eps = 1e-3}) {
    if (points.length != 4) return false;
    final lengths = _segmentLengths(points);
    if (lengths.reduce(math.min) <= eps) return false;
    return (lengths[0] - lengths[2]).abs() <= eps && (lengths[1] - lengths[3]).abs() <= eps;
  }

  static int grilyatoCassetteCount(List<List<double>> walls, int fallback) {
    final fromArea = cassetteCountFromArea(walls);
    return math.max(fromArea, fallback);
  }

  /// Purchase qty from room area: ceil(S / 0.36) for 600×600 — matches supplier calcs
  /// (10×10 m → 278).
  static int cassetteCountFromArea(
    List<List<double>> walls, {
    double cellCm = 60,
  }) {
    final cellM2 = (cellCm * cellCm) / 10000.0;
    if (cellM2 <= 0) return 0;
    final area = roomAreaM2(walls);
    if (area <= 0) return 0;
    return (area / cellM2).ceil();
  }

  /// Smart purchase count: area baseline + packing of cut pieces from layout.
  ///
  /// - Ignores crumb cuts thinner than [minUsefulCutCm] (e.g. 1 cm to the wall).
  /// - Packs remaining cut area into whole cassettes: one board can cover several cuts.
  /// - Never below [cassetteCountFromArea] (supplier floor).
  static int estimatePurchaseCassettes({
    required List<List<double>> walls,
    Iterable<({bool isFull, double cutXCm, double cutYCm})>? layoutTiles,
    double cellCm = 60,
    double minUsefulCutCm = 3.0,
  }) {
    final fromArea = cassetteCountFromArea(walls, cellCm: cellCm);
    if (layoutTiles == null) return fromArea;

    var full = 0;
    var cutAreaCm2 = 0.0;
    final cellArea = cellCm * cellCm;
    for (final t in layoutTiles) {
      if (t.isFull) {
        full++;
        continue;
      }
      if (t.cutXCm < minUsefulCutCm || t.cutYCm < minUsefulCutCm) continue;
      cutAreaCm2 += t.cutXCm * t.cutYCm;
    }
    final packedCuts = cellArea <= 0 ? 0 : (cutAreaCm2 / cellArea).ceil();
    final fromLayout = full + packedCuts;
    return math.max(fromArea, fromLayout);
  }

  /// Mama/Papa pieces per 600×600 cassette (always 600 mm profiles).
  static int grilyatoProfilesPerCassette(String cellSize) => _profileFactor(cellSize);

  static int _profileFactor(String cellSize) {
    if (cellSize == '75x75') return 7;
    if (cellSize == '50x50') return 11;
    return 5; // 100x100
  }

  static Map<String, int> calcArmstrong(List<List<double>> walls, int cassetteCount) {
    final perimeterCm = roomPerimeterCm(walls);
    final areaM2 = roomAreaM2(walls);
    final corner3m = ceilDiv(perimeterCm, 300);
    final guide3600 = ((areaM2 * 0.84) / 3.6).ceil();
    final guide1200 = ((areaM2 * 1.68) / 1.2).ceil();
    final guide600 = ((areaM2 * 0.85) / 0.6).ceil();
    return {
      'Плиты/кассеты': cassetteCount,
      'Направляющая 3600': guide3600,
      'Направляющая 1200': guide1200,
      'Направляющая 600': guide600,
      'Подвес': guide3600 * 4,
      'Уголок': corner3m,
    };
  }

  static Map<String, int> calcGrilyatoGl(
    List<List<double>> walls,
    int cassetteCount,
    String cellSize,
  ) {
    final perimeterCm = roomPerimeterCm(walls);
    final areaM2 = roomAreaM2(walls);
    // Trust caller purchase count (layout pack / area). Fallback to area only.
    if (cassetteCount <= 0) {
      cassetteCount = cassetteCountFromArea(walls);
    }
    final k = grilyatoProfilesPerCassette(cellSize);
    final corner3m = ceilDiv(perimeterCm, 300);
    // Carrier frame = same as Armstrong (3600 / 1200 / 600).
    final guide3600 = ((areaM2 * 0.84) / 3.6).ceil();
    final guide1200 = ((areaM2 * 1.68) / 1.2).ceil();
    final guide600 = ((areaM2 * 0.85) / 0.6).ceil();
    // Grille: 600 mm papa/mama; L-profile (Заглушки) = 4 per cassette.
    final profile = cassetteCount * k;
    final lProfile = cassetteCount * 4;
    return {
      'Профиль Папа': profile,
      'Профиль Мама': profile,
      'Направляющая 3600': guide3600,
      'Направляющая 1200': guide1200,
      'Направляющая 600': guide600,
      'Подвес': guide3600 * 4,
      'Уголок': corner3m,
      'Заглушки': lProfile,
    };
  }

  static Map<String, int> calcGrilyatoClassic(
    List<List<double>> walls,
    int cassetteCount,
    String cellSize,
  ) {
    final perimeterCm = roomPerimeterCm(walls);
    final areaM2 = roomAreaM2(walls);
    if (cassetteCount <= 0) {
      cassetteCount = cassetteCountFromArea(walls);
    }
    final corner3m = ceilDiv(perimeterCm, 300);
    // Same carrier geometry as Armstrong, but mains are 2400.
    final guide2400 = ((areaM2 * 0.84) / 2.4).ceil();
    final guide1200 = ((areaM2 * 1.68) / 1.2).ceil();
    final guide600 = ((areaM2 * 0.85) / 0.6).ceil();
    final k = grilyatoProfilesPerCassette(cellSize);
    final profile = cassetteCount * k;
    return {
      'Профиль Папа': profile,
      'Профиль Мама': profile,
      'Направляющая 2400': guide2400,
      'Направляющая 1200': guide1200,
      'Направляющая 600': guide600,
      'Подвес': guide2400 * 3,
      'Уголок': corner3m,
      'Соединитель': guide2400,
    };
  }

  static Map<String, int> applyLightDeductions(
    Map<String, int> result,
    CeilingType type,
    String cellSize,
    int lightCount,
  ) {
    if (lightCount <= 0) return Map<String, int>.from(result);
    final out = Map<String, int>.from(result);
    if (type == CeilingType.armstrong) {
      final key = 'Плиты/кассеты';
      if (out.containsKey(key)) {
        out[key] = math.max(0, out[key]! - lightCount);
      }
    } else {
      final k = grilyatoProfilesPerCassette(cellSize);
      final deduct = lightCount * k;
      for (final key in ['Профиль Папа', 'Профиль Мама']) {
        if (out.containsKey(key)) {
          out[key] = math.max(0, out[key]! - deduct);
        }
      }
      // L-profile / заглушки: 4 per remaining cassette-equivalent.
      if (type == CeilingType.grilyatoGl && out.containsKey('Заглушки')) {
        final profile = out['Профиль Мама'] ?? 0;
        out['Заглушки'] = k == 0 ? 0 : ((profile / k) * 4.0).ceil();
      }
    }
    return out;
  }

  static Map<String, int> calculate({
    required CeilingType type,
    required List<List<double>> walls,
    required int cassetteCount,
    String cellSize = '100x100',
    int lightCount = 0,
  }) {
    late Map<String, int> result;
    switch (type) {
      case CeilingType.armstrong:
        result = calcArmstrong(walls, cassetteCount);
      case CeilingType.grilyatoGl:
        result = calcGrilyatoGl(walls, cassetteCount, cellSize);
      case CeilingType.grilyatoClassic:
        result = calcGrilyatoClassic(walls, cassetteCount, cellSize);
    }
    result = applyLightDeductions(result, type, cellSize, lightCount);
    if (lightCount > 0) {
      return {'Светильники': lightCount, ...result};
    }
    return result;
  }
}
