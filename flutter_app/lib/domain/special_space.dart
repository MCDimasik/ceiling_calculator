import 'dart:convert';
import 'dart:math' as math;

import 'finish_model.dart';
import 'models.dart';

/// Room without a drawn floor plan: manual volumes and/or stairwell params.
enum SpecialSpaceKind {
  /// User enters ready m² (walls / floor / ceiling).
  volume,

  /// Parametric stairwell (подъездная клетка).
  stairwell,
}

enum StairPlanKind {
  /// П-образная с площадкой (default for подъезды).
  uLanding,

  /// Прямой марш.
  straight,
}

/// How the user prefers to feed dimensions — other fields derive from this.
enum StairInputFocus {
  /// Already know wall finish m² (optionally split by floors in UI).
  knownWallsM2,

  /// Box Ш×Д and floor-to-floor height В.
  boxAndStoreyHeight,

  /// Total shaft height (all storeys) + Ш×Д.
  totalHeightAndBox,
}

extension StairPlanKindX on StairPlanKind {
  String get id => switch (this) {
        StairPlanKind.uLanding => 'u_landing',
        StairPlanKind.straight => 'straight',
      };

  String get labelRu => switch (this) {
        StairPlanKind.uLanding => 'П-образная с площадкой',
        StairPlanKind.straight => 'Прямая',
      };

  static StairPlanKind parse(String? raw) => switch (raw) {
        'straight' => StairPlanKind.straight,
        _ => StairPlanKind.uLanding,
      };
}

extension StairInputFocusX on StairInputFocus {
  String get id => switch (this) {
        StairInputFocus.knownWallsM2 => 'walls_m2',
        StairInputFocus.boxAndStoreyHeight => 'box_h',
        StairInputFocus.totalHeightAndBox => 'total_h',
      };

  String get labelRu => switch (this) {
        StairInputFocus.knownWallsM2 => 'Знаю м² стен',
        StairInputFocus.boxAndStoreyHeight => 'Высота этажа (пол→пол)',
        StairInputFocus.totalHeightAndBox => 'Высота всей клетки',
      };

  /// Short hint under the mode chips.
  String get hintRu => switch (this) {
        StairInputFocus.knownWallsM2 =>
          'Вводите уже посчитанную площадь стен. Габариты Ш×Д не нужны.',
        StairInputFocus.boxAndStoreyHeight =>
          'Ш и Д клетки + высота одного этажа (от пола до пола). '
          'Стены = периметр × высота этажа × число этажей.',
        StairInputFocus.totalHeightAndBox =>
          'Ш и Д клетки + высота всего пролёта целиком. '
          'Высота одного этажа = В всего ÷ число этажей.',
      };

  static StairInputFocus parse(String? raw) => switch (raw) {
        'box_h' => StairInputFocus.boxAndStoreyHeight,
        'total_h' => StairInputFocus.totalHeightAndBox,
        _ => StairInputFocus.knownWallsM2,
      };
}

/// Typical ЖБ stair slab / tread (cm) — used when user does not override.
const kStairLandingSlabCm = 16.0;
const kStairTreadSlabCm = 5.0;

double _clampD(double v, double a, double b) {
  final lo = math.min(a, b);
  final hi = math.max(a, b);
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

int _clampI(int v, int a, int b) {
  final lo = math.min(a, b);
  final hi = math.max(a, b);
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

/// Opening on a stairwell wall (deducted from finish area).
class StairwellOpening {
  StairwellOpening({
    this.kind = 'door',
    this.wallIndex = 0,
    this.widthCm = 90,
    this.heightCm = 210,
    this.sillCm = 0,
    this.offsetAlongWallCm = 40,
  });

  /// `door` or `window`.
  String kind;

  /// 0 торец промежут. · 1 длинная прав. · 2 торец нижней · 3 длинная лев.
  int wallIndex;
  double widthCm;
  double heightCm;
  double sillCm;
  double offsetAlongWallCm;

  double get areaM2 =>
      (widthCm < 0 || heightCm < 0) ? 0 : (widthCm * heightCm) / 10000.0;

  String get kindLabelRu => kind == 'window' ? 'Окно' : 'Дверь';

  /// Short labels for lists / dropdowns (avoid overflow).
  String get wallLabelRu => switch (_clampI(wallIndex, 0, 3)) {
        0 => 'Тор. П',
        1 => 'Прав.',
        2 => 'Тор. Н',
        _ => 'Лев.',
      };

  String get wallLabelLongRu => switch (_clampI(wallIndex, 0, 3)) {
        0 => 'Торец промежут. площадки',
        1 => 'Длинная стена (прав.)',
        2 => 'Торец нижней площадки',
        _ => 'Длинная стена (лев.)',
      };

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'wall_index': wallIndex,
        'width_cm': widthCm,
        'height_cm': heightCm,
        'sill_cm': sillCm,
        'offset_cm': offsetAlongWallCm,
      };

  static StairwellOpening fromJson(Map<String, dynamic> j) => StairwellOpening(
        kind: (j['kind'] as String?) == 'window' ? 'window' : 'door',
        wallIndex: (j['wall_index'] as num?)?.toInt() ?? 0,
        widthCm: (j['width_cm'] as num?)?.toDouble() ?? 90,
        heightCm: (j['height_cm'] as num?)?.toDouble() ?? 210,
        sillCm: (j['sill_cm'] as num?)?.toDouble() ?? 0,
        offsetAlongWallCm: (j['offset_cm'] as num?)?.toDouble() ?? 40,
      );
}

class StairwellParams {
  StairwellParams({
    this.plan = StairPlanKind.uLanding,
    this.inputFocus = StairInputFocus.boxAndStoreyHeight,
    this.floorsFrom = 1,
    this.floorsTo = 5,
    this.storeyHeightM = 3.0,
    this.totalHeightM = 0,
    this.widthM = 2.4,
    this.depthM = 5.0,
    this.finishSides = 3,
    this.doorsM2 = 0,
    this.knownWallsM2 = 0,
    this.landingSlabCm = kStairLandingSlabCm,
    this.treadSlabCm = kStairTreadSlabCm,
    this.landingsSameSize = true,
    this.midLandingDepthM,
    this.bottomLandingDepthM,
    List<StairwellOpening>? openings,
  }) : openings = openings ?? [];

  StairPlanKind plan;
  StairInputFocus inputFocus;
  int floorsFrom;
  int floorsTo;

  /// Floor → floor above (includes slab + finishes).
  double storeyHeightM;

  /// Entire shaft height when focusing [StairInputFocus.totalHeightAndBox].
  double totalHeightM;

  /// Ширина клетки Ш (м) — поперёк маршей (два марша + зазор / проём).
  double widthM;

  /// Длина клетки Д (м) — вдоль маршей: нижняя площадка + марш + промежуточная.
  double depthM;

  /// 2 / 3 / 4 walls to finish.
  int finishSides;

  /// Extra manual deduction (m²), plus [openings].
  double doorsM2;

  /// Direct wall area when [inputFocus] is knownWallsM2.
  double knownWallsM2;

  /// Thickness of landing slab (cm), default [kStairLandingSlabCm].
  double landingSlabCm;

  /// Thickness of tread slab (cm), default [kStairTreadSlabCm].
  double treadSlabCm;

  /// True → one depth for both landings; false → [midLandingDepthM] / [bottomLandingDepthM].
  bool landingsSameSize;

  /// Intermediate landing depth (m). Null → auto ≈ 18% of Д.
  double? midLandingDepthM;

  /// Bottom landing depth (m). Null → auto (or same as mid when [landingsSameSize]).
  double? bottomLandingDepthM;

  List<StairwellOpening> openings;

  int get storeyCount {
    final a = floorsFrom;
    final b = floorsTo;
    final n = (b >= a ? b - a : a - b) + 1;
    return n < 1 ? 1 : n;
  }

  /// Perimeter of finished walls for a rectangular shaft (m).
  ///
  /// [depthM] (Д) already includes flight run + landing; we do not split them.
  double finishPerimeterM() {
    final sh = widthM < 0 ? 0.0 : widthM; // Ш
    final d = depthM < 0 ? 0.0 : depthM; // Д
    final sides = _clampI(finishSides, 2, 4);
    return switch (sides) {
      2 => plan == StairPlanKind.straight ? 2 * d : 2 * (d > sh ? d : sh),
      3 => sh + 2 * d, // typical U: two long walls (Д) + one short (Ш)
      _ => 2 * (sh + d),
    };
  }

  /// Effective floor-to-floor height from current focus.
  double effectiveStoreyHeightM() {
    switch (inputFocus) {
      case StairInputFocus.totalHeightAndBox:
        final n = storeyCount;
        if (totalHeightM > 0 && n > 0) return totalHeightM / n;
        return storeyHeightM > 0 ? storeyHeightM : 3.0;
      case StairInputFocus.boxAndStoreyHeight:
      case StairInputFocus.knownWallsM2:
        return storeyHeightM > 0 ? storeyHeightM : 3.0;
    }
  }

  double openingsAreaM2() {
    var a = doorsM2 < 0 ? 0.0 : doorsM2;
    for (final o in openings) {
      a += o.areaM2;
    }
    return a;
  }

  /// Computed wall finish area (m²).
  double computeWallsM2() {
    if (inputFocus == StairInputFocus.knownWallsM2 && knownWallsM2 > 0) {
      return knownWallsM2;
    }
    final h = effectiveStoreyHeightM();
    final perim = finishPerimeterM();
    final n = storeyCount;
    // One schematic edit × N storeys: walls and matching openings on each floor.
    final gross = perim * h * n;
    final net = gross - openingsAreaM2() * n;
    return net < 0 ? 0 : net;
  }

  /// Sill height (cm) so a door sits on the landing slab at [wallIndex].
  /// Long walls: use landing under the opening mid-point along Д.
  static double suggestedSillCmForWall({
    required StairSchematicGeometry g,
    required int wallIndex,
    required double offsetAlongCm,
    required double widthCm,
  }) {
    final wi = wallIndex < 0 ? 0 : (wallIndex > 3 ? 3 : wallIndex);
    final mid = offsetAlongCm + widthCm / 2;
    if (wi == 0) {
      // Торец промежуточной площадки (y≈0)
      for (final L in g.landings) {
        if (math.min(L.y0, L.y1) <= 1) return L.zTop;
      }
      return 0;
    }
    if (wi == 2) {
      // Торец нижней площадки (y≈Д)
      for (final L in g.landings) {
        if (math.max(L.y0, L.y1) >= g.depthCm - 1) return L.zTop;
      }
      return 0;
    }
    // Long walls 1/3: along = Y — sill = top of landing under door
    for (final L in g.landings) {
      final y0 = math.min(L.y0, L.y1);
      final y1 = math.max(L.y0, L.y1);
      if (mid >= y0 - 1 && mid <= y1 + 1) {
        return L.zTop;
      }
    }
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'plan': plan.id,
        'input_focus': inputFocus.id,
        'floors_from': floorsFrom,
        'floors_to': floorsTo,
        'storey_height_m': storeyHeightM,
        'total_height_m': totalHeightM,
        'width_m': widthM,
        'depth_m': depthM,
        'finish_sides': finishSides,
        'doors_m2': doorsM2,
        'known_walls_m2': knownWallsM2,
        'landing_slab_cm': landingSlabCm,
        'tread_slab_cm': treadSlabCm,
        'landings_same': landingsSameSize,
        'mid_landing_m': midLandingDepthM,
        'bottom_landing_m': bottomLandingDepthM,
        'openings': openings.map((o) => o.toJson()).toList(),
      };

  static StairwellParams fromJson(Map<String, dynamic>? j) {
    if (j == null || j.isEmpty) return StairwellParams();
    final rawOpen = j['openings'];
    final openings = <StairwellOpening>[];
    if (rawOpen is List) {
      for (final e in rawOpen) {
        if (e is Map) {
          openings.add(
            StairwellOpening.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return StairwellParams(
      plan: StairPlanKindX.parse(j['plan'] as String?),
      inputFocus: StairInputFocusX.parse(j['input_focus'] as String?),
      floorsFrom: (j['floors_from'] as num?)?.toInt() ?? 1,
      floorsTo: (j['floors_to'] as num?)?.toInt() ?? 5,
      storeyHeightM: (j['storey_height_m'] as num?)?.toDouble() ?? 3.0,
      totalHeightM: (j['total_height_m'] as num?)?.toDouble() ?? 0,
      widthM: (j['width_m'] as num?)?.toDouble() ?? 2.4,
      depthM: (j['depth_m'] as num?)?.toDouble() ?? 5.0,
      finishSides: (j['finish_sides'] as num?)?.toInt() ?? 3,
      doorsM2: (j['doors_m2'] as num?)?.toDouble() ?? 0,
      knownWallsM2: (j['known_walls_m2'] as num?)?.toDouble() ?? 0,
      landingSlabCm:
          (j['landing_slab_cm'] as num?)?.toDouble() ?? kStairLandingSlabCm,
      treadSlabCm:
          (j['tread_slab_cm'] as num?)?.toDouble() ?? kStairTreadSlabCm,
      landingsSameSize: (j['landings_same'] as bool?) ?? true,
      midLandingDepthM: (j['mid_landing_m'] as num?)?.toDouble(),
      bottomLandingDepthM: (j['bottom_landing_m'] as num?)?.toDouble(),
      openings: openings,
    );
  }

  /// Live schematic for 2D/3D preview (one storey slice). Null if Ш/Д missing.
  StairSchematicGeometry? buildSchematic() {
    final wM = widthM;
    final dM = depthM;
    if (wM <= 0 || dM <= 0) return null;
    final hM = effectiveStoreyHeightM();
    if (hM <= 0) return null;
    return StairSchematicGeometry.fromParams(
      plan: plan,
      widthCm: wM * 100,
      depthCm: dM * 100,
      heightCm: hM * 100,
      storeyCount: storeyCount,
      landingSlabCm: landingSlabCm > 0 ? landingSlabCm : kStairLandingSlabCm,
      treadSlabCm: treadSlabCm > 0 ? treadSlabCm : kStairTreadSlabCm,
      midLandingCm: midLandingDepthM == null || midLandingDepthM! <= 0
          ? null
          : midLandingDepthM! * 100,
      bottomLandingCm: () {
        if (landingsSameSize) {
          if (midLandingDepthM != null && midLandingDepthM! > 0) {
            return midLandingDepthM! * 100;
          }
          return null;
        }
        if (bottomLandingDepthM == null || bottomLandingDepthM! <= 0) {
          return null;
        }
        return bottomLandingDepthM! * 100;
      }(),
      openings: openings,
    );
  }
}

/// Closed polygon zone inside the stair shaft (flight / landing), cm.
class StairSchematicZone {
  const StairSchematicZone({
    required this.kind,
    required this.pointsCm,
    required this.labelRu,
  });

  /// `flight`, `landing`, or `void`.
  final String kind;

  /// Closed ring [[x, y], …] in cm (X = Ш, Y = Д).
  final List<List<double>> pointsCm;
  final String labelRu;
}

/// One tread in 3D (cm): top at [zTop], thickness [slabCm].
class StairTread3D {
  const StairTread3D({
    required this.x0,
    required this.x1,
    required this.y0,
    required this.y1,
    required this.zTop,
    required this.riserCm,
    required this.slabCm,
  });

  final double x0;
  final double x1;
  final double y0;
  final double y1;
  final double zTop;
  final double riserCm;
  final double slabCm;

  double get zBottom => _clampD(zTop - riserCm, 0.0, zTop);
  double get zUnder => _clampD(zTop - slabCm, 0.0, zTop);
}

/// Landing slab with volume (cm).
class StairLanding3D {
  const StairLanding3D({
    required this.x0,
    required this.x1,
    required this.y0,
    required this.y1,
    required this.zTop,
    required this.slabCm,
    required this.labelRu,
  });

  final double x0;
  final double x1;
  final double y0;
  final double y1;
  final double zTop;
  final double slabCm;
  final String labelRu;

  double get zUnder => _clampD(zTop - slabCm, 0.0, zTop);
  double get depthCm => (y1 - y0).abs();
}

/// Generated stair cell drawing from Ш×Д×В (not stored on the room).
class StairSchematicGeometry {
  StairSchematicGeometry({
    required this.widthCm,
    required this.depthCm,
    required this.heightCm,
    required this.plan,
    required this.storeyCount,
    required this.walls,
    required this.zones,
    required this.midLandingDepthCm,
    required this.bottomLandingDepthCm,
    required this.flightRunCm,
    required this.riserCm,
    required this.treadCm,
    required this.landingSlabCm,
    required this.treadSlabCm,
    required this.stepsPerHalf,
    required this.treads,
    required this.landings,
    required this.elevationLower,
    required this.elevationUpper,
    required this.openings,
  });

  final double widthCm;
  final double depthCm;
  final double heightCm;
  final StairPlanKind plan;
  final int storeyCount;

  final List<List<double>> walls;
  final List<StairSchematicZone> zones;

  /// Intermediate landing (перемычка) depth along Д.
  final double midLandingDepthCm;

  /// Lower (floor) landing depth along Д.
  final double bottomLandingDepthCm;

  final double flightRunCm;
  final double riserCm;
  final double treadCm;
  final double landingSlabCm;
  final double treadSlabCm;
  final int stepsPerHalf;

  final List<StairTread3D> treads;
  final List<StairLanding3D> landings;

  /// Side elevation step profiles [yCm, zCm] within Д × В.
  final List<List<double>> elevationLower;
  final List<List<double>> elevationUpper;
  final List<StairwellOpening> openings;

  /// Back-compat alias for mid landing depth.
  double get landingDepthCm => midLandingDepthCm;

  static StairSchematicGeometry fromParams({
    required StairPlanKind plan,
    required double widthCm,
    required double depthCm,
    required double heightCm,
    required int storeyCount,
    double landingSlabCm = kStairLandingSlabCm,
    double treadSlabCm = kStairTreadSlabCm,
    double? midLandingCm,
    double? bottomLandingCm,
    List<StairwellOpening> openings = const [],
  }) {
    final w = widthCm;
    final d = depthCm;
    final h = heightCm;
    final walls = <List<double>>[
      [0, 0, w, 0],
      [w, 0, w, d],
      [w, d, 0, d],
      [0, d, 0, 0],
    ];

    // Two landings along Д: intermediate (y≈0) + bottom (y≈d). Upper = next floor.
    // Default auto ≈ 18% of Д each; optional overrides from user.
    const minFlight = 80.0;
    var midLanding = midLandingCm ?? d * 0.18;
    var botLanding = bottomLandingCm ?? midLandingCm ?? d * 0.18;
    if (midLanding + botLanding + minFlight > d) {
      final room = math.max(d - minFlight, d * 0.2);
      final sum = midLanding + botLanding;
      if (sum > 0) {
        midLanding = room * (midLanding / sum);
        botLanding = room * (botLanding / sum);
      } else {
        midLanding = room / 2;
        botLanding = room / 2;
      }
    }
    midLanding = _clampD(midLanding, 1.0, d * 0.45);
    botLanding = _clampD(botLanding, 1.0, d - midLanding - 1.0);
    final flightRun = math.max(1.0, d - midLanding - botLanding);

    final yMid0 = 0.0;
    final yMid1 = midLanding;
    final yBot0 = d - botLanding;
    final yBot1 = d;
    final yFlight0 = midLanding;
    final yFlight1 = yBot0;

    final zones = <StairSchematicZone>[];
    final gap = _clampD(w * 0.12, math.min(40.0, w * 0.05), w * 0.28);
    final flightW = plan == StairPlanKind.straight ? w : (w - gap) / 2;

    zones.add(StairSchematicZone(
      kind: 'landing',
      labelRu: 'Промежут.',
      pointsCm: [
        [0, yMid0],
        [w, yMid0],
        [w, yMid1],
        [0, yMid1],
      ],
    ));
    zones.add(StairSchematicZone(
      kind: 'landing',
      labelRu: 'Нижняя',
      pointsCm: [
        [0, yBot0],
        [w, yBot0],
        [w, yBot1],
        [0, yBot1],
      ],
    ));

    if (plan == StairPlanKind.straight) {
      zones.add(StairSchematicZone(
        kind: 'flight',
        labelRu: 'Марш',
        pointsCm: [
          [0, yFlight0],
          [w, yFlight0],
          [w, yFlight1],
          [0, yFlight1],
        ],
      ));
    } else if (flightW > 1 && flightRun > 1) {
      zones.add(StairSchematicZone(
        kind: 'flight',
        labelRu: 'Марш 1',
        pointsCm: [
          [0, yFlight0],
          [flightW, yFlight0],
          [flightW, yFlight1],
          [0, yFlight1],
        ],
      ));
      zones.add(StairSchematicZone(
        kind: 'flight',
        labelRu: 'Марш 2',
        pointsCm: [
          [w - flightW, yFlight0],
          [w, yFlight0],
          [w, yFlight1],
          [w - flightW, yFlight1],
        ],
      ));
      zones.add(StairSchematicZone(
        kind: 'void',
        labelRu: 'Проём',
        pointsCm: [
          [flightW, yFlight0],
          [w - flightW, yFlight0],
          [w - flightW, yFlight1],
          [flightW, yFlight1],
        ],
      ));
    }

    final halfRise = plan == StairPlanKind.uLanding ? h / 2 : h;
    var steps = _clampI((halfRise / 16.0).round(), 3, 24);
    var riser = halfRise / steps;
    if (riser > 19) {
      steps = _clampI((halfRise / 17.0).ceil(), 3, 28);
      riser = halfRise / steps;
    }
    final tread = flightRun / math.max(steps, 1);
    final slabL = landingSlabCm;
    final slabT = treadSlabCm;

    final treads = <StairTread3D>[];
    final landings = <StairLanding3D>[];
    final elevLower = <List<double>>[];
    final elevUpper = <List<double>>[];

    // Bottom landing at floor (z = slab)
    landings.add(StairLanding3D(
      x0: 0,
      x1: w,
      y0: yBot0,
      y1: yBot1,
      zTop: slabL,
      slabCm: slabL,
      labelRu: 'Нижняя площадка',
    ));

    if (plan == StairPlanKind.uLanding) {
      // Lower flight: bottom landing → mid landing, z 0 → H/2
      elevLower.add([yBot0, 0]);
      for (var i = 1; i <= steps; i++) {
        final z = riser * i;
        final y1 = yBot0 - tread * (i - 1);
        final y0 = yBot0 - tread * i;
        elevLower.add([y1, z]);
        elevLower.add([y0, z]);
        treads.add(StairTread3D(
          x0: 0,
          x1: flightW,
          y0: math.min(y0, y1),
          y1: math.max(y0, y1),
          zTop: z,
          riserCm: riser,
          slabCm: slabT,
        ));
      }
      // Mid landing
      landings.add(StairLanding3D(
        x0: 0,
        x1: w,
        y0: yMid0,
        y1: yMid1,
        zTop: halfRise,
        slabCm: slabL,
        labelRu: 'Промежуточная',
      ));
      elevLower.add([yMid1, halfRise]);
      elevLower.add([yMid0, halfRise]);

      // Upper flight: mid → bottom Y (same end as floor landing), z H/2 → H
      // Top of upper flight arrives at next floor — no top landing drawn.
      elevUpper.add([yMid1, halfRise]);
      for (var i = 1; i <= steps; i++) {
        final z = halfRise + riser * i;
        final y0 = yMid1 + tread * (i - 1);
        final y1 = yMid1 + tread * i;
        elevUpper.add([y0, z]);
        elevUpper.add([y1, z]);
        treads.add(StairTread3D(
          x0: w - flightW,
          x1: w,
          y0: y0,
          y1: y1,
          zTop: _clampD(z, 0, h),
          riserCm: riser,
          slabCm: slabT,
        ));
      }
    } else {
      elevLower.add([yBot0, 0]);
      for (var i = 1; i <= steps; i++) {
        final z = riser * i;
        final y1 = yBot0 - tread * (i - 1);
        final y0 = yBot0 - tread * i;
        elevLower.add([y1, z]);
        elevLower.add([y0, z]);
        treads.add(StairTread3D(
          x0: 0,
          x1: w,
          y0: math.min(y0, y1),
          y1: math.max(y0, y1),
          zTop: z,
          riserCm: riser,
          slabCm: slabT,
        ));
      }
      landings.add(StairLanding3D(
        x0: 0,
        x1: w,
        y0: yMid0,
        y1: yMid1,
        zTop: h,
        slabCm: slabL,
        labelRu: 'Верхняя (= нижняя след. эт.)',
      ));
      elevLower.add([yMid1, h]);
      elevLower.add([yMid0, h]);
    }

    final nStoreys = storeyCount < 1 ? 1 : storeyCount;

    return StairSchematicGeometry(
      widthCm: w,
      depthCm: d,
      heightCm: h,
      plan: plan,
      storeyCount: nStoreys,
      walls: walls,
      zones: zones,
      midLandingDepthCm: midLanding,
      bottomLandingDepthCm: botLanding,
      flightRunCm: flightRun,
      riserCm: riser,
      treadCm: tread,
      landingSlabCm: slabL,
      treadSlabCm: slabT,
      stepsPerHalf: steps,
      treads: treads,
      landings: landings,
      elevationLower: elevLower,
      elevationUpper: elevUpper,
      openings: List.of(openings),
    );
  }
}

class SpecialSpace {
  SpecialSpace({
    required this.kind,
    this.wallsM2 = 0,
    this.floorM2 = 0,
    this.ceilingM2 = 0,
    this.stair,
  });

  SpecialSpaceKind kind;
  double wallsM2;
  double floorM2;
  double ceilingM2;
  StairwellParams? stair;

  bool get hasAnyArea => wallsM2 > 0 || floorM2 > 0 || ceilingM2 > 0;

  String get kindLabelRu => switch (kind) {
        SpecialSpaceKind.volume => 'Объём без чертежа',
        SpecialSpaceKind.stairwell => 'Лестничная клетка',
      };

  /// Sync [wallsM2] from stair params when kind is stairwell.
  void recomputeFromStair() {
    if (kind != SpecialSpaceKind.stairwell) return;
    final s = stair ??= StairwellParams();
    wallsM2 = s.computeWallsM2();
  }

  Map<String, dynamic> toJson() => {
        'kind': kind == SpecialSpaceKind.stairwell ? 'stairwell' : 'volume',
        'walls_m2': wallsM2,
        'floor_m2': floorM2,
        'ceiling_m2': ceilingM2,
        if (stair != null) 'stair': stair!.toJson(),
      };

  String encode() => jsonEncode(toJson());

  static SpecialSpace? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      return fromJson(Map<String, dynamic>.from(j));
    } catch (_) {
      return null;
    }
  }

  static SpecialSpace fromJson(Map<String, dynamic> j) {
    final kindRaw = j['kind'] as String? ?? 'volume';
    final kind = kindRaw == 'stairwell'
        ? SpecialSpaceKind.stairwell
        : SpecialSpaceKind.volume;
    final stairRaw = j['stair'];
    return SpecialSpace(
      kind: kind,
      wallsM2: (j['walls_m2'] as num?)?.toDouble() ?? 0,
      floorM2: (j['floor_m2'] as num?)?.toDouble() ?? 0,
      ceilingM2: (j['ceiling_m2'] as num?)?.toDouble() ?? 0,
      stair: stairRaw is Map
          ? StairwellParams.fromJson(Map<String, dynamic>.from(stairRaw))
          : (kind == SpecialSpaceKind.stairwell ? StairwellParams() : null),
    );
  }
}

extension RoomSpecialSpaceX on Room {
  SpecialSpace? get specialSpace => SpecialSpace.tryParse(specialSpaceJson);

  set specialSpace(SpecialSpace? value) {
    specialSpaceJson = value?.encode();
  }

  bool get isSpecialSpace => specialSpace != null;
}

/// Footprint walls (cm) for master plan when the room has no drawn contour.
///
/// Stairwell: rectangle Ш×Д. Volume: square ≈ √floor when floor > 0.
List<List<double>>? specialSpaceFootprintWallsCm(Room room) {
  final s = room.specialSpace;
  if (s == null) return null;
  if (s.kind == SpecialSpaceKind.stairwell) {
    final st = s.stair;
    if (st == null) return null;
    final w = st.widthM * 100;
    final d = st.depthM * 100;
    if (w < 1 || d < 1) return null;
    return [
      [0, 0, w, 0],
      [w, 0, w, d],
      [w, d, 0, d],
      [0, d, 0, 0],
    ];
  }
  final floor = s.floorM2;
  if (floor <= 0) return null;
  final a = (math.sqrt(floor) * 100).clamp(50.0, 5000.0);
  return [
    [0, 0, a, 0],
    [a, 0, a, a],
    [a, a, 0, a],
    [0, a, 0, 0],
  ];
}

/// Contour for plan drawing: real walls, else special footprint.
List<List<double>>? roomPlanWalls(Room room) {
  if (room.hasLayout && room.walls.length >= 3) return room.walls;
  return specialSpaceFootprintWallsCm(room);
}

/// Openings for plan / door-snap: stairwell nested openings, else [Room.openings].
///
/// Maps [StairwellOpening] onto the same wall indices as [roomPlanWalls].
List<RoomOpening> roomPlanOpenings(Room room) {
  final space = room.specialSpace;
  final stair = space?.stair;
  if (space?.kind == SpecialSpaceKind.stairwell &&
      stair != null &&
      stair.openings.isNotEmpty) {
    return [
      for (final o in stair.openings)
        RoomOpening(
          kind: o.kind,
          widthCm: o.widthCm,
          heightCm: o.heightCm,
          wallIndex: o.wallIndex,
          offsetAlongWallCm: o.offsetAlongWallCm,
          sillHeightCm: o.sillCm,
        ),
    ];
  }
  return [for (final raw in room.openings) RoomOpening.fromJson(raw)];
}
