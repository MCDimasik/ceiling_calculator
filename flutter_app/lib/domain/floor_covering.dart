/// Floor covering material in the finish module.
enum FloorCoveringKind {
  tile,
  laminate,
  screed,
}

extension FloorCoveringKindX on FloorCoveringKind {
  String get id => switch (this) {
        FloorCoveringKind.tile => 'tile',
        FloorCoveringKind.laminate => 'laminate',
        FloorCoveringKind.screed => 'screed',
      };

  String get labelRu => switch (this) {
        FloorCoveringKind.tile => 'Плитка напольная',
        FloorCoveringKind.laminate => 'Ламинат',
        FloorCoveringKind.screed => 'Стяжка',
      };

  /// Short label for segmented buttons.
  String get labelShortRu => switch (this) {
        FloorCoveringKind.tile => 'Плитка',
        FloorCoveringKind.laminate => 'Ламинат',
        FloorCoveringKind.screed => 'Стяжка',
      };

  bool get hasBoardLayout =>
      this == FloorCoveringKind.tile || this == FloorCoveringKind.laminate;

  static FloorCoveringKind parse(String? raw) {
    for (final k in FloorCoveringKind.values) {
      if (k.id == raw) return k;
    }
    return FloorCoveringKind.tile;
  }
}

/// Laminate / board laying patterns.
enum FloorLayingPattern {
  /// Прямая (палубная), без смещения рядов.
  straight,

  /// Со смещением на 1/2 доски (кирпичная).
  brick,

  /// Со смещением на 1/3.
  third,

  /// Диагональ 45°.
  diagonal,
}

extension FloorLayingPatternX on FloorLayingPattern {
  String get id => switch (this) {
        FloorLayingPattern.straight => 'straight',
        FloorLayingPattern.brick => 'brick',
        FloorLayingPattern.third => 'third',
        FloorLayingPattern.diagonal => 'diagonal',
      };

  String get labelRu => switch (this) {
        FloorLayingPattern.straight => 'Рядами без смещения',
        FloorLayingPattern.brick => 'Со смещением на ½',
        FloorLayingPattern.third => 'Со смещением на ⅓',
        FloorLayingPattern.diagonal => 'По диагонали',
      };

  /// Row stagger as fraction of board length (axis-aligned patterns).
  double get rowStaggerFraction => switch (this) {
        FloorLayingPattern.straight => 0,
        FloorLayingPattern.brick => 0.5,
        FloorLayingPattern.third => 1 / 3,
        FloorLayingPattern.diagonal => 0,
      };

  bool get isAngled => this == FloorLayingPattern.diagonal;

  static FloorLayingPattern parse(String? raw) {
    // Legacy patterns removed from UI — treat as straight.
    if (raw == 'herringbone' || raw == 'chevron') {
      return FloorLayingPattern.straight;
    }
    for (final p in FloorLayingPattern.values) {
      if (p.id == raw) return p;
    }
    return FloorLayingPattern.straight;
  }
}

/// Typical laminate board sizes (width × length cm).
const laminateBoardPresets = <(double, double)>[
  (19.2, 120),
  (19.2, 138),
  (20, 120),
  (24.3, 138),
  (33, 128.5),
];

/// Typical floor tile sizes (width × length cm).
const floorTilePresets = <(double, double)>[
  (60, 60),
  (30, 30),
  (120, 60),
  (90, 60),
  (40, 40),
];

/// Default screed thickness (cm).
const defaultScreedDepthCm = 5.0;

/// Screed volume in m³ from floor area (m²) and thickness (cm).
double screedVolumeM3(double floorM2, double depthCm) {
  if (floorM2 <= 0 || depthCm <= 0) return 0;
  return floorM2 * (depthCm / 100.0);
}

/// Catalog screed rates are ₽/м²; work in the app is priced ₽/м³.
double screedCatalogM2ToM3(double pricePerM2, double depthCm) {
  final d = depthCm <= 0 ? defaultScreedDepthCm : depthCm;
  final depthM = d / 100.0;
  if (depthM <= 0 || pricePerM2 <= 0) return 0;
  return pricePerM2 / depthM;
}
