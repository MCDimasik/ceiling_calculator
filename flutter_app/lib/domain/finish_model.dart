import 'dart:math' as math;

import 'package:flutter/material.dart';

/// App entry modules that share the same projects/rooms.
enum AppModule {
  ceilingLayout,
  materials,
  finish,
}

extension AppModuleX on AppModule {
  String get homeLabel => switch (this) {
        AppModule.ceilingLayout => 'Расчет раскладки потолка',
        AppModule.materials => 'Расчет материалов',
        AppModule.finish => 'Расчет отделки',
      };

  String get projectsTitle => switch (this) {
        AppModule.ceilingLayout => 'Проекты · раскладка',
        AppModule.materials => 'Проекты · материалы',
        AppModule.finish => 'Проекты · отделка',
      };
}

/// Window / door opening subtracted from wall area.
///
/// One row = one **type** (size + optional placement). [quantity] multiplies
/// the area; several rows = several different types (e.g. two door sizes).
class RoomOpening {
  RoomOpening({
    required this.kind,
    required this.widthCm,
    required this.heightCm,
    this.quantity = 1,
    this.label,
    this.wallIndex,
    this.offsetAlongWallCm = 0,
    this.sillHeightCm = 0,
  });

  /// `window` | `door` | custom.
  String kind;
  double widthCm;
  double heightCm;

  /// How many identical openings of this type.
  int quantity;

  /// Optional name, e.g. «Входная», «Межкомнатная».
  String? label;

  /// Wall index in room.walls for 3D placement; null = area-only (not placed).
  int? wallIndex;

  /// Distance along the wall from its start (cm) to the opening's left edge.
  double offsetAlongWallCm;

  /// Height from floor to bottom of opening (cm).
  double sillHeightCm;

  double get unitAreaM2 => (widthCm * heightCm) / 10000.0;
  double get areaM2 => unitAreaM2 * math.max(1, quantity);

  String get displayName {
    final base = kind == 'door' ? 'Дверь' : (kind == 'window' ? 'Окно' : kind);
    if (label != null && label!.trim().isNotEmpty) return '${label!.trim()} ($base)';
    return base;
  }

  Map<String, Object?> toJson() => {
        'kind': kind,
        'width_cm': widthCm,
        'height_cm': heightCm,
        'quantity': quantity,
        'label': label,
        'wall_index': wallIndex,
        'offset_along_wall_cm': offsetAlongWallCm,
        'sill_height_cm': sillHeightCm,
      };

  static RoomOpening fromJson(Map<String, dynamic> j) => RoomOpening(
        kind: j['kind'] as String? ?? 'window',
        widthCm: (j['width_cm'] as num?)?.toDouble() ?? 0,
        heightCm: (j['height_cm'] as num?)?.toDouble() ?? 0,
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        label: j['label'] as String?,
        wallIndex: j['wall_index'] as int?,
        offsetAlongWallCm: (j['offset_along_wall_cm'] as num?)?.toDouble() ?? 0,
        sillHeightCm: (j['sill_height_cm'] as num?)?.toDouble() ?? 0,
      );
}

/// Saved InteractiveViewer camera for layout (and later finish/3D).
class ViewTransform {
  const ViewTransform({this.scale = 1, this.tx = 0, this.ty = 0});

  final double scale;
  final double tx;
  final double ty;

  Matrix4 toMatrix() => Matrix4.identity()
    ..translateByDouble(tx, ty, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);

  static ViewTransform fromMatrix(Matrix4 m) {
    final s = m.getMaxScaleOnAxis();
    return ViewTransform(scale: s, tx: m.storage[12], ty: m.storage[13]);
  }

  Map<String, Object?> toJson() => {'scale': scale, 'tx': tx, 'ty': ty};

  static ViewTransform? tryParse(Map<String, dynamic>? j) {
    if (j == null) return null;
    return ViewTransform(
      scale: (j['scale'] as num?)?.toDouble() ?? 1,
      tx: (j['tx'] as num?)?.toDouble() ?? 0,
      ty: (j['ty'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Base finish layer kinds for walls (ordered stack).
enum FinishLayerKind {
  demolition,
  plaster,
  putty,
  primer,
  paint,
  tile,
}

extension FinishLayerKindX on FinishLayerKind {
  String get id => switch (this) {
        FinishLayerKind.demolition => 'demolition',
        FinishLayerKind.plaster => 'plaster',
        FinishLayerKind.putty => 'putty',
        FinishLayerKind.primer => 'primer',
        FinishLayerKind.paint => 'paint',
        FinishLayerKind.tile => 'tile',
      };

  String get labelRu => switch (this) {
        FinishLayerKind.demolition => 'Демонтаж',
        FinishLayerKind.plaster => 'Штукатурка',
        FinishLayerKind.putty => 'Шпаклевка',
        FinishLayerKind.primer => 'Грунтовка',
        FinishLayerKind.paint => 'Краска',
        FinishLayerKind.tile => 'Плитка',
      };

  static FinishLayerKind? tryParse(String? raw) {
    if (raw == null) return null;
    for (final k in FinishLayerKind.values) {
      if (k.id == raw) return k;
    }
    return null;
  }
}

/// One finish pass on walls (and optionally floor later).
class FinishLayer {
  FinishLayer({
    required this.kind,
    this.paintCoats = 1,
    this.tileWidthCm = 60,
    this.tileHeightCm = 60,
    this.tileOffsetX = 0,
    this.tileOffsetY = 0,
    this.enabled = true,
  });

  FinishLayerKind kind;

  /// Paint only: 1…3 coats. Multiplies covered area.
  int paintCoats;

  double tileWidthCm;
  double tileHeightCm;
  int tileOffsetX;
  int tileOffsetY;
  bool enabled;

  int get coats => kind == FinishLayerKind.paint
      ? paintCoats.clamp(1, 3)
      : 1;

  String get displayLabel {
    if (kind == FinishLayerKind.paint) {
      return '${kind.labelRu} ($coats сл.)';
    }
    if (kind == FinishLayerKind.tile) {
      return '${kind.labelRu} ${tileWidthCm.round()}×${tileHeightCm.round()}';
    }
    return kind.labelRu;
  }

  Map<String, Object?> toJson() => {
        'kind': kind.id,
        'paint_coats': paintCoats,
        'tile_width_cm': tileWidthCm,
        'tile_height_cm': tileHeightCm,
        'tile_offset_x': tileOffsetX,
        'tile_offset_y': tileOffsetY,
        'enabled': enabled,
      };

  static FinishLayer fromJson(Map<String, dynamic> j) {
    final kind = FinishLayerKindX.tryParse(j['kind'] as String?) ??
        FinishLayerKind.plaster;
    return FinishLayer(
      kind: kind,
      paintCoats: (j['paint_coats'] as num?)?.toInt() ?? 1,
      tileWidthCm: (j['tile_width_cm'] as num?)?.toDouble() ?? 60,
      tileHeightCm: (j['tile_height_cm'] as num?)?.toDouble() ?? 60,
      tileOffsetX: (j['tile_offset_x'] as num?)?.toInt() ?? 0,
      tileOffsetY: (j['tile_offset_y'] as num?)?.toInt() ?? 0,
      enabled: j['enabled'] as bool? ?? true,
    );
  }
}

/// Quantities for one wall finish layer against net wall area.
class FinishLayerQty {
  const FinishLayerQty({
    required this.layer,
    required this.areaM2,
    this.tilesEstimate = 0,
  });

  final FinishLayer layer;
  final double areaM2;
  final int tilesEstimate;
}

/// Floor / walls / ceiling areas for finish module.
class FinishAreas {
  const FinishAreas({
    required this.floorM2,
    required this.ceilingM2,
    required this.wallsGrossM2,
    required this.openingsM2,
    required this.wallsNetM2,
    required this.perimeterM,
    this.floorTiles = 0,
    this.ceilingTiles = 0,
    this.wallTiles = 0,
    this.wallLayers = const [],
  });

  final double floorM2;
  final double ceilingM2;
  final double wallsGrossM2;
  final double openingsM2;
  final double wallsNetM2;
  final double perimeterM;
  final int floorTiles;
  final int ceilingTiles;
  final int wallTiles;
  final List<FinishLayerQty> wallLayers;

  double get totalFinishM2 => floorM2 + ceilingM2 + wallsNetM2;
  int get totalTiles => floorTiles + ceilingTiles + wallTiles;

  /// Sum of layer coverages (paint × coats, etc.).
  double get wallLayersTotalM2 =>
      wallLayers.fold<double>(0, (a, q) => a + q.areaM2);
}

class FinishCalculator {
  /// Closed polygon area from wall segments (same as ceiling room area).
  static double floorAreaM2(List<List<double>> walls) {
    if (walls.isEmpty) return 0;
    final pts = <(double, double)>[];
    for (final w in walls) {
      pts.add((w[0], w[1]));
    }
    pts.add((walls.last[2], walls.last[3]));
    final uniq = <(double, double)>[];
    for (final p in pts) {
      if (uniq.isEmpty || uniq.last != p) uniq.add(p);
    }
    if (uniq.length >= 2 && uniq.first == uniq.last) uniq.removeLast();
    if (uniq.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0; i < uniq.length; i++) {
      final a = uniq[i];
      final b = uniq[(i + 1) % uniq.length];
      sum += a.$1 * b.$2 - b.$1 * a.$2;
    }
    return sum.abs() / 2.0 / 10000.0;
  }

  static double perimeterM(List<List<double>> walls) {
    var p = 0.0;
    for (final w in walls) {
      final dx = w[2] - w[0];
      final dy = w[3] - w[1];
      p += math.sqrt(dx * dx + dy * dy);
    }
    return p / 100.0;
  }

  static int tilesForArea(double areaM2, double tileWCm, double tileHCm) {
    final t = (tileWCm * tileHCm) / 10000.0;
    if (t <= 0 || areaM2 <= 0) return 0;
    return (areaM2 / t).ceil();
  }

  static List<FinishLayerQty> layerQuantities({
    required double wallsNetM2,
    required List<FinishLayer> layers,
  }) {
    final out = <FinishLayerQty>[];
    for (final layer in layers) {
      if (!layer.enabled) continue;
      final area = wallsNetM2 * layer.coats;
      final tiles = layer.kind == FinishLayerKind.tile
          ? tilesForArea(wallsNetM2, layer.tileWidthCm, layer.tileHeightCm)
          : 0;
      out.add(FinishLayerQty(layer: layer, areaM2: area, tilesEstimate: tiles));
    }
    return out;
  }

  static FinishAreas compute({
    required List<List<double>> walls,
    required double heightCm,
    required List<RoomOpening> openings,
    double tileWidthCm = 60,
    double tileHeightCm = 60,
    List<FinishLayer> wallLayers = const [],
  }) {
    final floor = floorAreaM2(walls);
    final peri = perimeterM(walls);
    final gross = peri * (heightCm / 100.0);
    final open = openings.fold<double>(0, (a, o) => a + o.areaM2);
    final net = math.max(0.0, gross - open);
    final layerQtys = layerQuantities(wallsNetM2: net, layers: wallLayers);
    FinishLayer? tileLayer;
    for (final l in wallLayers) {
      if (l.enabled && l.kind == FinishLayerKind.tile) {
        tileLayer = l;
        break;
      }
    }
    final wallTileW = tileLayer?.tileWidthCm ?? tileWidthCm;
    final wallTileH = tileLayer?.tileHeightCm ?? tileHeightCm;
    return FinishAreas(
      floorM2: floor,
      ceilingM2: floor,
      wallsGrossM2: gross,
      openingsM2: open,
      wallsNetM2: net,
      perimeterM: peri,
      floorTiles: tilesForArea(floor, tileWidthCm, tileHeightCm),
      ceilingTiles: tilesForArea(floor, 60, 60),
      wallTiles: tilesForArea(net, wallTileW, wallTileH),
      wallLayers: layerQtys,
    );
  }
}

/// Lightweight 3D shell from 2D walls + height — renderer-agnostic foundation.
///
/// Chosen model: **extruded floor polygon** (prism). Fits our wall list,
/// openings as wall cutouts later, works with CustomPainter isometric now and
/// any mesh engine (filament / three_dart) later without rewriting domain data.
class RoomShell3D {
  RoomShell3D({
    required this.floorPolygonCm,
    required this.heightCm,
    this.openings = const [],
  });

  final List<Offset> floorPolygonCm;
  final double heightCm;
  final List<RoomOpening> openings;

  static RoomShell3D? fromWalls(
    List<List<double>> walls, {
    required double heightCm,
    List<RoomOpening> openings = const [],
  }) {
    if (walls.length < 3) return null;
    final pts = <Offset>[];
    for (final w in walls) {
      pts.add(Offset(w[0], w[1]));
    }
    final last = Offset(walls.last[2], walls.last[3]);
    if (pts.isEmpty || (pts.last - last).distance > 0.5) pts.add(last);
    if (pts.length >= 2 && (pts.first - pts.last).distance < 0.5) {
      pts.removeLast();
    }
    if (pts.length < 3) return null;
    return RoomShell3D(
      floorPolygonCm: pts,
      heightCm: heightCm,
      openings: openings,
    );
  }

  /// Axis-aligned bounds in cm (x, y horizontal; z up).
  (double minX, double maxX, double minY, double maxY) get bounds2d {
    var minX = floorPolygonCm.first.dx;
    var maxX = minX;
    var minY = floorPolygonCm.first.dy;
    var maxY = minY;
    for (final p in floorPolygonCm) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return (minX, maxX, minY, maxY);
  }
}
