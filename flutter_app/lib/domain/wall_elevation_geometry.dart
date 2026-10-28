import 'dart:math' as math;

import 'finish_model.dart';

/// Gap between repeated openings along one wall (matches isometric preview).
const openingGapAlongWallCm = 30.0;

double wallSegmentLengthCm(List<double> wall) =>
    math.sqrt(math.pow(wall[2] - wall[0], 2) + math.pow(wall[3] - wall[1], 2));

List<List<double>> wallElevationPolygon(double lengthCm, double heightCm) => [
      [0, 0, lengthCm, 0],
      [lengthCm, 0, lengthCm, heightCm],
      [lengthCm, heightCm, 0, heightCm],
      [0, heightCm, 0, 0],
    ];

/// Opening rectangle on a wall elevation (x along wall, y from floor up).
class WallOpeningRect {
  const WallOpeningRect({
    required this.leftCm,
    required this.bottomCm,
    required this.widthCm,
    required this.heightCm,
    this.label,
    this.kind,
  });

  final double leftCm;
  final double bottomCm;
  final double widthCm;
  final double heightCm;
  final String? label;
  final String? kind;
}

List<WallOpeningRect> openingRectsOnWall({
  required int wallIndex,
  required double wallLengthCm,
  required double roomHeightCm,
  required List<RoomOpening> openings,
}) {
  final out = <WallOpeningRect>[];
  for (final o in openings) {
    if (o.wallIndex != wallIndex) continue;
    final count = math.max(1, o.quantity);
    for (var q = 0; q < count; q++) {
      final start = o.offsetAlongWallCm + q * (o.widthCm + openingGapAlongWallCm);
      if (start >= wallLengthCm) break;
      final w = math.min(o.widthCm, wallLengthCm - start);
      if (w < 1) continue;
      final z0 = o.sillHeightCm.clamp(0.0, roomHeightCm);
      final z1 = (o.sillHeightCm + o.heightCm).clamp(0.0, roomHeightCm);
      if (z1 - z0 < 1) continue;
      out.add(
        WallOpeningRect(
          leftCm: start,
          bottomCm: z0,
          widthCm: w,
          heightCm: z1 - z0,
          label: o.label,
          kind: o.kind,
        ),
      );
    }
  }
  return out;
}
