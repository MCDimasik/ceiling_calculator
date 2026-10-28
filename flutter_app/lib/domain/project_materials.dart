import 'ceiling_grid.dart';
import 'ceiling_guides.dart';
import 'finish_quantities.dart';
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

/// Main ceiling layout tile — always 600×600 mm (60 cm), Armstrong and Grilyato alike.
const double layoutTileCm = 60;

/// Inner Grilyato cell size in mm from materials label (50×50, 75×75, 100×100).
int grilyatoInnerCellMm(String cellLabel) {
  return switch (cellLabel) {
    '50x50' => 50,
    '75x75' => 75,
    '100x100' => 100,
    _ => 100,
  };
}

/// How many inner cells fit along one 600 mm cassette edge (for subdivision lines).
int grilyatoSubdivisionsPerTile(String cellLabel) {
  final innerMm = grilyatoInnerCellMm(cellLabel);
  return (600 / innerMm).round();
}

/// Grid cell side in cm for finish area estimates (always 600×600 mm cassette).
double ceilingCellCm(String ceilingType, String cell) => layoutTileCm;

bool isSuspensionKey(String key) =>
    key == 'Подвес' || key.startsWith('Подвес (');

String materialsBaseName(String name) {
  if (isSuspensionKey(name)) return 'Подвес';
  if (name.startsWith('Профиль Папа')) return 'Профиль Папа';
  if (name.startsWith('Профиль Мама')) return 'Профиль Мама';
  if (name.startsWith('Заглушки')) return 'Заглушки';
  if (name.startsWith('Плиты/кассеты')) return 'Плиты/кассеты';
  return name;
}

(String key, int qty) normalizeResultKey(
  String name,
  int value,
  String ceiling,
  String susp,
  String cell,
) {
  final base = materialsBaseName(name);
  var key = base;
  if (base == 'Подвес') {
    final sizeTxt = susp.replaceFirst('Подвес', '').trim();
    key = 'Подвес ($sizeTxt)';
  } else if (base == 'Профиль Папа' || base == 'Профиль Мама' || base == 'Заглушки') {
    key = '$base ($cell)';
  } else if (base == 'Плиты/кассеты') {
    key = '$base ($ceiling)';
  } else if (base == 'Светильники') {
    key = 'Светильники';
  }
  return (key, value);
}

List<(double, double)> pointsFromWalls(List<List<double>> walls) {
  return MaterialsCalculator.orderedPointsFromWalls(walls);
}

/// Project-level UI selection applied to rooms without per-room override.
class MaterialsUiConfig {
  const MaterialsUiConfig({
    required this.ceiling,
    required this.susp,
    required this.cell,
  });

  final String ceiling;
  final String susp;
  final String cell;
}

(String ceiling, String susp, String cell) resolveMaterialsConfig(
  Room room,
  Project project, {
  MaterialsUiConfig? ui,
  bool ignoreRoomOverride = false,
}) {
  if (!ignoreRoomOverride && room.materialsOverride) {
    return roomEffectiveConfig(room, project);
  }
  if (ui != null) {
    return (ui.ceiling, ui.susp, ui.cell);
  }
  return roomEffectiveConfig(room, project);
}

Map<String, int> buildNormalizedMaterialsMap(
  Map<String, int> raw,
  String ceiling,
  String susp,
  String cell,
) {
  final out = <String, int>{};
  var suspTotal = 0;
  var hasSusp = false;
  for (final e in raw.entries) {
    if (isSuspensionKey(e.key)) {
      suspTotal += e.value;
      hasSusp = true;
      continue;
    }
    final (key, qty) = normalizeResultKey(e.key, e.value, ceiling, susp, cell);
    out[key] = (out[key] ?? 0) + qty;
  }
  out.removeWhere((k, _) => isSuspensionKey(k));
  if (hasSusp) {
    final (key, _) = normalizeResultKey('Подвес', suspTotal, ceiling, susp, cell);
    out[key] = suspTotal;
  }
  return out;
}

Map<String, int> finalizeMaterialsTotals(
  Map<String, int> totals,
  MaterialsUiConfig ui,
) {
  final normalized = buildNormalizedMaterialsMap(
    totals,
    ui.ceiling,
    ui.susp,
    ui.cell,
  );
  final type = typeMap[ui.ceiling] ?? CeilingType.armstrong;
  stripExtraneousForCeilingType(normalized, type);
  return normalized;
}

/// Layout-driven materials for one room.
Map<String, int> calculateRoomMaterials(
  Room room,
  Project project, {
  MaterialsUiConfig? ui,
  bool ignoreRoomOverride = false,
}) {
  if (!room.hasLayout) return {};
  final (ceiling, susp, cell) = resolveMaterialsConfig(
    room,
    project,
    ui: ui,
    ignoreRoomOverride: ignoreRoomOverride,
  );
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

  final guideMarksParsed = filterGuideMarksForCeilingType(
    parseCeilingGuidesWithLegacyAnchor(
      room.ceilingGuides,
      room.walls,
      offsetX: room.gridOffsetX.toDouble(),
      offsetY: room.gridOffsetY.toDouble(),
      cellSize: grid.cellSizeCm,
    ),
    type,
  );
  // No marks → auto frame (same as leaving layout without placing guides).
  // Do not fall back to area formulas for carriers.
  final guideMarks = guideMarksParsed.isNotEmpty
      ? guideMarksParsed
      : filterGuideMarksForCeilingType(
          autoGuideMarksForRoom(
            walls: room.walls,
            offsetX: room.gridOffsetX.toDouble(),
            offsetY: room.gridOffsetY.toDouble(),
            cellSize: grid.cellSizeCm,
            ceilingLabel: ceiling,
            cellSizeLabel: cell,
          ),
          type,
        );
  final guideCounts = countGuidesFromMarks(
    guideMarks,
    room.walls,
    offsetX: room.gridOffsetX.toDouble(),
    offsetY: room.gridOffsetY.toDouble(),
    cellSize: grid.cellSizeCm,
  );
  final adjusted = applyGuideOverrides(raw, guideCounts, type: type);

  return buildNormalizedMaterialsMap(adjusted, ceiling, susp, cell);
}

/// Finish purchase quantities aggregated for project cost (floor boards, wall tiles).
Map<String, int> aggregateFinishMaterialTotals(
  Project project, {
  Iterable<int>? roomIds,
}) {
  final totals = <String, int>{};
  final idSet = roomIds?.toSet();
  for (final room in project.rooms) {
    if (room.id != null && idSet != null && !idSet.contains(room.id)) continue;
    if (!room.hasLayout) continue;
    if (room.finishIncludeFloor) {
      final floorBoards = withWastePercent(floorBoardCountForRoom(room), 0.05);
      if (floorBoards > 0) {
        totals['Отделка · пол (с запасом)'] =
            (totals['Отделка · пол (с запасом)'] ?? 0) + floorBoards;
      }
    }
    if (room.finishIncludeWalls) {
      final wallTiles = withWastePercent(wallTileLayoutCountForRoom(room), 0.07);
      if (wallTiles > 0) {
        totals['Отделка · плитка стен'] =
            (totals['Отделка · плитка стен'] ?? 0) + wallTiles;
      }
    }
  }
  return totals;
}

(Map<String, int> totals, double areaM2, double perimeterM) aggregateCeilingTotals(
  Project project, {
  Iterable<int>? roomIds,
  MaterialsUiConfig? ui,
}) {
  final totals = <String, int>{};
  var area = 0.0;
  var peri = 0.0;
  final idSet = roomIds?.toSet();
  for (final room in project.rooms) {
    if (room.id != null && idSet != null && !idSet.contains(room.id)) continue;
    if (!room.hasLayout) continue;
    if (!room.finishIncludeCeiling) continue;
    area += MaterialsCalculator.roomAreaM2(room.walls);
    peri += MaterialsCalculator.roomPerimeterCm(room.walls) / 100.0;
    // Respect per-room overrides; non-override rooms use [ui] when provided.
    // Do not strip by project ceiling type — mixed Armstrong/Grilyato must sum.
    final part = calculateRoomMaterials(
      room,
      project,
      ui: ui,
      ignoreRoomOverride: false,
    );
    for (final e in part.entries) {
      totals[e.key] = (totals[e.key] ?? 0) + e.value;
    }
  }
  return (totals, area, peri);
}

(Map<String, int> totals, double areaM2, double perimeterM) aggregateProjectTotals(
  Project project, {
  Iterable<int>? roomIds,
  MaterialsUiConfig? ui,
}) {
  final (ceiling, area, peri) = aggregateCeilingTotals(
    project,
    roomIds: roomIds,
    ui: ui,
  );
  final totals = Map<String, int>.from(ceiling);
  for (final e in aggregateFinishMaterialTotals(project, roomIds: roomIds).entries) {
    totals[e.key] = (totals[e.key] ?? 0) + e.value;
  }
  return (totals, area, peri);
}

/// Sort material lines for display: guides longest→shortest (3600…600), else A–Z.
int compareMaterialLineKeys(String a, String b) {
  int? guideMm(String key) {
    final m = RegExp(r'Направляющая\s+(\d+)').firstMatch(key);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  final ga = guideMm(a);
  final gb = guideMm(b);
  if (ga != null && gb != null) return gb.compareTo(ga);
  if (ga != null) return -1;
  if (gb != null) return 1;
  return a.compareTo(b);
}

List<MapEntry<String, int>> sortedMaterialEntries(Map<String, int> raw) {
  final list = raw.entries.toList()
    ..sort((a, b) => compareMaterialLineKeys(a.key, b.key));
  return list;
}
