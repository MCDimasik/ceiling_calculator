import 'ceiling_grid.dart';
import 'ceiling_guides.dart';
import 'materials_calculator.dart';
import 'models.dart';

const typeMap = {
  'Армстронг': CeilingType.armstrong,
  'Грильято': CeilingType.grilyatoClassic,
  'GL': CeilingType.grilyatoGl,
};

(String ceiling, String susp, String cell) roomEffectiveConfig(Room room, Project project) {
  final pCeiling = project.materialsCeiling ?? 'Армстронг';
  final pSusp = project.materialsSusp ?? 'Подвес 0,5';
  final pCell = project.materialsCell ?? '50x50';
  if (room.materialsOverride) {
    return (
      room.materialsCeiling ?? pCeiling,
      room.materialsSusp ?? pSusp,
      room.materialsCell ?? pCell,
    );
  }
  return (pCeiling, pSusp, pCell);
}

(String key, int qty) normalizeResultKey(
  String name,
  int value,
  String ceiling,
  String susp,
  String cell,
) {
  var key = name;
  if (name == 'Подвес') {
    final sizeTxt = susp.replaceFirst('Подвес', '').trim();
    key = 'Подвес ($sizeTxt)';
  } else if (name == 'Профиль Папа' || name == 'Профиль Мама' || name == 'Заглушки') {
    key = '$name ($cell)';
  } else if (name == 'Плиты/кассеты') {
    key = '$name ($ceiling)';
  } else if (name == 'Светильники') {
    key = 'Светильники';
  }
  return (key, value);
}

List<(double, double)> pointsFromWalls(List<List<double>> walls) {
  return MaterialsCalculator.orderedPointsFromWalls(walls);
}

/// Layout-driven materials for one room.
Map<String, int> calculateRoomMaterials(Room room, Project project) {
  if (room.walls.length < 3) return {};
  final (ceiling, susp, cell) = roomEffectiveConfig(room, project);
  final type = typeMap[ceiling] ?? CeilingType.armstrong;

  final grid = CeilingGrid(
    offsetXCm: room.gridOffsetX.toDouble(),
    offsetYCm: room.gridOffsetY.toDouble(),
  );
  final lights = <String>{};
  for (final f in room.lightFixtures) {
    if (f.length >= 2) lights.add('${f[0]}:${f[1]}');
  }
  grid.rebuild(
    roomPoints: pointsFromWalls(room.walls),
    walls: room.walls,
    lightIds: lights,
  );
  grid.pruneLights();

  final layoutTiles = grid.cells
      .where((c) => c.kind == CellKind.full || c.kind == CellKind.cut)
      .map(
        (c) => (
          isFull: c.kind == CellKind.full,
          cutXCm: c.cutXCm,
          cutYCm: c.cutYCm,
        ),
      );
  final cassette = MaterialsCalculator.estimatePurchaseCassettes(
    walls: room.walls,
    layoutTiles: layoutTiles,
    cellCm: grid.cellSizeCm,
  );
  final lightCount = room.lightFixtures.length;
  final raw = MaterialsCalculator.calculate(
    type: type,
    walls: room.walls,
    cassetteCount: cassette,
    cellSize: cell,
    lightCount: lightCount,
  );

  final guideMarks = parseCeilingGuidesWithLegacyAnchor(
    room.ceilingGuides,
    room.walls,
    offsetX: room.gridOffsetX.toDouble(),
    offsetY: room.gridOffsetY.toDouble(),
    cellSize: grid.cellSizeCm,
  );
  final guideCounts = countGuidesFromMarks(
    guideMarks,
    room.walls,
    offsetX: room.gridOffsetX.toDouble(),
    offsetY: room.gridOffsetY.toDouble(),
    cellSize: grid.cellSizeCm,
  );
  final adjusted = applyGuideOverrides(raw, guideCounts, type: type);

  final out = <String, int>{};
  for (final e in adjusted.entries) {
    final (key, qty) = normalizeResultKey(e.key, e.value, ceiling, susp, cell);
    out[key] = (out[key] ?? 0) + qty;
  }
  return out;
}

(Map<String, int> totals, double areaM2, double perimeterM) aggregateProjectTotals(Project project) {
  final totals = <String, int>{};
  var area = 0.0;
  var peri = 0.0;
  for (final room in project.rooms) {
    if (room.walls.length < 3) continue;
    area += MaterialsCalculator.roomAreaM2(room.walls);
    peri += MaterialsCalculator.roomPerimeterCm(room.walls) / 100.0;
    final part = calculateRoomMaterials(room, project);
    for (final e in part.entries) {
      totals[e.key] = (totals[e.key] ?? 0) + e.value;
    }
  }
  return (totals, area, peri);
}
