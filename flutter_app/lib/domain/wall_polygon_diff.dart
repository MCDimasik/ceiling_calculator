import 'ceiling_guides.dart';
import 'geometry_polygon.dart';
import 'materials_calculator.dart';

/// Comparison of project (design) vs fact wall footprints.
class WallPolygonDiff {
  const WallPolygonDiff({
    required this.hasDesignBaseline,
    required this.designAreaM2,
    required this.factAreaM2,
    required this.areaDeltaM2,
    required this.designPerimeterM,
    required this.factPerimeterM,
    required this.perimeterDeltaM,
    required this.centroidShiftCmX,
    required this.centroidShiftCmY,
  });

  final bool hasDesignBaseline;
  final double designAreaM2;
  final double factAreaM2;
  final double areaDeltaM2;
  final double designPerimeterM;
  final double factPerimeterM;
  final double perimeterDeltaM;
  final double centroidShiftCmX;
  final double centroidShiftCmY;

  bool get hasSignificantDiff =>
      hasDesignBaseline &&
      (areaDeltaM2.abs() > 0.05 ||
          perimeterDeltaM.abs() > 0.1 ||
          centroidShiftCmX.abs() > 2 ||
          centroidShiftCmY.abs() > 2);
}

WallPolygonDiff compareWallPolygons(
  List<List<double>>? designWalls,
  List<List<double>> factWalls,
) {
  final factFp = footprintFromWalls(factWalls);
  if (designWalls == null || designWalls.length < 3) {
    return WallPolygonDiff(
      hasDesignBaseline: false,
      designAreaM2: 0,
      factAreaM2: factFp.areaM2,
      areaDeltaM2: 0,
      designPerimeterM: 0,
      factPerimeterM: factFp.perimeterM,
      perimeterDeltaM: 0,
      centroidShiftCmX: 0,
      centroidShiftCmY: 0,
    );
  }
  final designFp = footprintFromWalls(designWalls);
  final (dcx, dcy) = roomCentroidCm(designWalls);
  final (fcx, fcy) = roomCentroidCm(factWalls);
  return WallPolygonDiff(
    hasDesignBaseline: true,
    designAreaM2: designFp.areaM2,
    factAreaM2: factFp.areaM2,
    areaDeltaM2: factFp.areaM2 - designFp.areaM2,
    designPerimeterM: designFp.perimeterM,
    factPerimeterM: factFp.perimeterM,
    perimeterDeltaM: factFp.perimeterM - designFp.perimeterM,
    centroidShiftCmX: fcx - dcx,
    centroidShiftCmY: fcy - dcy,
  );
}

String formatWallPolygonDiffSummary(WallPolygonDiff diff) {
  if (!diff.hasDesignBaseline) {
    return 'Базовый контур проекта не сохранён — будет создан после применения.';
  }
  final area = diff.areaDeltaM2;
  final areaSign = area >= 0 ? '+' : '';
  final shift = diff.centroidShiftCmX.round().abs() + diff.centroidShiftCmY.round().abs();
  if (!diff.hasSignificantDiff) {
    return 'Контур совпадает с проектом (Δ площади ${areaSign}${area.toStringAsFixed(2)} м²).';
  }
  return 'Проект ${diff.designAreaM2.toStringAsFixed(2)} м² → '
      'факт ${diff.factAreaM2.toStringAsFixed(2)} м² '
      '(Δ ${areaSign}${area.toStringAsFixed(2)} м²)\n'
      'Смещение центра: ${diff.centroidShiftCmX.round()}×${diff.centroidShiftCmY.round()} см'
      '${shift > 0 ? '' : ''}';
}

/// Shift confirmed grid offset so lights/guides stay aligned after fact capture.
(int dx, int dy) gridRealignDeltaFromDiff(WallPolygonDiff diff) => (
      diff.centroidShiftCmX.round(),
      diff.centroidShiftCmY.round(),
    );

double designAreaM2(List<List<double>> walls) => MaterialsCalculator.roomAreaM2(walls);
