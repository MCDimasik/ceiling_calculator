import 'ceiling_grid.dart';
import 'surface_prep_layers.dart';
import 'finish_extra_works.dart';
import 'finish_material_links.dart';
import 'finish_model.dart';
import 'finish_quantities.dart';
import 'floor_covering.dart';
import 'materials_calculator.dart';
import 'models.dart';
import 'project_materials.dart';
import 'room_finish_areas.dart';
import 'special_space.dart';

export 'finish_quantities.dart' show floorBoardCountForRoom;

/// One line in the finish vedomost (walls / floor / areas).
class FinishVedomostLine {
  const FinishVedomostLine({
    required this.section,
    required this.name,
    required this.quantity,
    required this.unit,
    this.linkedItemKey,
  });

  final String section;
  final String name;
  final String quantity;
  final String unit;

  /// When set, this is an optional purchase link from a layer — must not get
  /// section work rates (`finish_wall` / …) in KS-2 / priced vedomost.
  final String? linkedItemKey;

  bool get isLinkedMaterial =>
      linkedItemKey != null && linkedItemKey!.isNotEmpty;
}

void _appendMaterialLinks(
  List<FinishVedomostLine> lines, {
  required String section,
  required String layerLabel,
  required List<FinishMaterialLink> links,
  required double areaM2,
}) {
  if (links.isEmpty || areaM2 <= 0) return;
  for (final m in links) {
    final name = m.productName.trim().isEmpty ? m.itemKey : m.productName.trim();
    if (name.isEmpty) continue;
    final qty = areaM2 * (m.qtyPerUnit <= 0 ? 1 : m.qtyPerUnit);
    lines.add(FinishVedomostLine(
      section: section,
      name: '$layerLabel · $name',
      quantity: qty.toStringAsFixed(qty >= 10 ? 1 : 2),
      unit: m.unit,
      linkedItemKey: m.itemKey.isEmpty ? null : m.itemKey,
    ));
  }
}

/// Tab-driven filter for the finish materials screen.
///
/// Overview → [all]; other tabs → matching section only.
enum FinishVedomostScope {
  all,
  walls,
  floor,
  ceiling,
  extraWorks,
}

extension FinishVedomostScopeX on FinishVedomostScope {
  String? get labelRu => switch (this) {
        FinishVedomostScope.all => null,
        FinishVedomostScope.walls => 'Стены',
        FinishVedomostScope.floor => 'Пол',
        FinishVedomostScope.ceiling => 'Потолок',
        FinishVedomostScope.extraWorks => 'Другие работы',
      };

  /// Sections to keep; `null` means no filter.
  Set<String>? get sectionNames => switch (this) {
        FinishVedomostScope.all => null,
        FinishVedomostScope.walls => const {'Стены'},
        FinishVedomostScope.floor => const {'Пол'},
        FinishVedomostScope.ceiling => const {'Потолок'},
        FinishVedomostScope.extraWorks => const {'Другие работы'},
      };

  /// Room editor tabs: 0 Обзор · 1 Стены · 2 Пол · 3 Потолок.
  static FinishVedomostScope fromRoomTab(int index) => switch (index) {
        1 => FinishVedomostScope.walls,
        2 => FinishVedomostScope.floor,
        3 => FinishVedomostScope.ceiling,
        _ => FinishVedomostScope.all,
      };

  /// Project summary tabs: 0 Обзор · 1 Стены · 2 Пол · 3 Потолок · 4 Другие работы.
  static FinishVedomostScope fromProjectTab(int index) => switch (index) {
        1 => FinishVedomostScope.walls,
        2 => FinishVedomostScope.floor,
        3 => FinishVedomostScope.ceiling,
        4 => FinishVedomostScope.extraWorks,
        _ => FinishVedomostScope.all,
      };
}

List<FinishVedomostLine> filterFinishVedomostLines(
  List<FinishVedomostLine> lines,
  FinishVedomostScope scope,
) {
  final names = scope.sectionNames;
  if (names == null) return lines;
  return lines.where((l) => names.contains(l.section)).toList();
}

List<FinishVedomostLine> buildFinishVedomostLines(
  Room room, {
  Project? project,
}) {
  final areas = finishAreasForRoom(room, project: project);
  if (areas == null) return [];
  final fromSpecial = room.specialSpace != null;

  final lines = <FinishVedomostLine>[];
  final includeFloor = room.finishIncludeFloor;
  final includeWalls = room.finishIncludeWalls;
  final includeCeiling = room.finishIncludeCeiling;

  if (includeFloor) {
    lines.add(FinishVedomostLine(
      section: 'Пол',
      name: 'Площадь',
      quantity: areas.floorM2.toStringAsFixed(2),
      unit: 'м²',
    ));
  }
  if (includeCeiling) {
    lines.add(FinishVedomostLine(
      section: 'Потолок',
      name: 'Площадь',
      quantity: areas.ceilingM2.toStringAsFixed(2),
      unit: 'м²',
    ));
  }
  if (includeWalls) {
    lines.add(FinishVedomostLine(
      section: 'Стены',
      name: 'Площадь',
      quantity: areas.wallsNetM2.toStringAsFixed(2),
      unit: 'м²',
    ));
  }
  if (includeWalls && !fromSpecial) {
    lines.add(FinishVedomostLine(
      section: 'Стены',
      name: 'Проёмы',
      quantity: areas.openingsM2.toStringAsFixed(2),
      unit: 'м²',
    ));
  }

  final floorKind = FloorCoveringKindX.parse(room.floorCoveringKind);
  final pattern = FloorLayingPatternX.parse(room.floorLayingPattern);

  // Prep layers first (against slab → under covering), then main covering.
  if (includeFloor) {
    for (final raw in room.floorPrepLayers) {
      final layer = SurfacePrepLayer.fromJson(raw);
      if (!layer.enabled) continue;
      final name = layer.displayName(floor: true);
      final (qty, unit) = layer.materialQty(areas.floorM2, floor: true);
      if (layer.usesThickness && unit == 'м³') {
        lines.add(FinishVedomostLine(
          section: 'Пол',
          name: 'Подготовка · $name',
          quantity: qty,
          unit: 'м³',
        ));
      } else {
        lines.add(FinishVedomostLine(
          section: 'Пол',
          name: 'Подготовка · $name',
          quantity: areas.floorM2.toStringAsFixed(2),
          unit: 'м²',
        ));
        if (unit != 'м²') {
          lines.add(FinishVedomostLine(
            section: 'Пол',
            name: '$name · материал',
            quantity: qty,
            unit: unit,
          ));
        }
      }
      _appendMaterialLinks(
        lines,
        section: 'Пол',
        layerLabel: name,
        links: layer.materialLinks,
        areaM2: areas.floorM2,
      );
    }

    if (floorKind == FloorCoveringKind.screed) {
      final depth = room.floorScreedDepthCm <= 0
          ? defaultScreedDepthCm
          : room.floorScreedDepthCm;
      final volume = screedVolumeM3(areas.floorM2, depth);
      final depthLabel =
          depth.toStringAsFixed(depth == depth.roundToDouble() ? 0 : 1);
      lines.add(FinishVedomostLine(
        section: 'Пол',
        name: 'Стяжка (покрытие) · $depthLabel см',
        quantity: volume.toStringAsFixed(2),
        unit: 'м³',
      ));
    } else if ((!fromSpecial && areas.floorM2 > 0) ||
        (fromSpecial && areas.floorM2 > 0)) {
      final coveringTitle = floorKind == FloorCoveringKind.laminate
          ? '${floorKind.labelRu} · ${pattern.labelRu}'
          : floorKind.labelRu;
      if (fromSpecial) {
        lines.add(FinishVedomostLine(
          section: 'Пол',
          name: coveringTitle,
          quantity: areas.floorM2.toStringAsFixed(2),
          unit: 'м²',
        ));
      } else {
        final floorBoards = floorBoardCountForRoom(room);
        lines.add(FinishVedomostLine(
          section: 'Пол',
          name: coveringTitle,
          quantity: '$floorBoards',
          unit: 'шт (на плане)',
        ));
        final sizeName = floorKind == FloorCoveringKind.laminate
            ? 'Размер доски'
            : 'Размер плитки';
        lines.add(FinishVedomostLine(
          section: 'Пол',
          name: sizeName,
          quantity:
              '${room.finishTileWidthCm.round()} × ${room.finishTileHeightCm.round()}',
          unit: 'см',
        ));
      }
    }
    _appendMaterialLinks(
      lines,
      section: 'Пол',
      layerLabel: floorKind.labelRu,
      links: decodeMaterialLinks(room.floorCoveringMaterials),
      areaM2: areas.floorM2,
    );
  }

  if (includeCeiling) {
    for (final raw in room.ceilingPrepLayers) {
      final layer = SurfacePrepLayer.fromJson(raw);
      if (!layer.enabled) continue;
      final name = layer.displayName(floor: false);
      final (qty, unit) = layer.materialQty(areas.ceilingM2, floor: false);
      if (layer.usesThickness && unit == 'м³') {
        lines.add(FinishVedomostLine(
          section: 'Потолок',
          name: 'Подготовка · $name',
          quantity: qty,
          unit: 'м³',
        ));
      } else {
        lines.add(FinishVedomostLine(
          section: 'Потолок',
          name: 'Подготовка · $name',
          quantity: areas.ceilingM2.toStringAsFixed(2),
          unit: 'м²',
        ));
        if (unit != 'м²') {
          lines.add(FinishVedomostLine(
            section: 'Потолок',
            name: '$name · материал',
            quantity: qty,
            unit: unit,
          ));
        }
      }
      _appendMaterialLinks(
        lines,
        section: 'Потолок',
        layerLabel: name,
        links: layer.materialLinks,
        areaM2: areas.ceilingM2,
      );
    }
    lines.addAll(_ceilingSummaryLines(room, project));
    _appendMaterialLinks(
      lines,
      section: 'Потолок',
      layerLabel: 'Система',
      links: decodeMaterialLinks(room.ceilingSystemMaterials),
      areaM2: areas.ceilingM2,
    );
  }

  if (includeWalls) {
    for (final q in areas.wallLayers) {
      final layer = q.layer;
      final name = layer.displayLabel;
      var qty = q.areaM2.toStringAsFixed(2);
      var unit = 'м²';
      if (layer.kind == FinishLayerKind.tile) {
        qty = '${q.areaM2.toStringAsFixed(2)} / ${q.tilesEstimate}';
        unit = 'м² / шт (раскладка)';
      }
      lines.add(FinishVedomostLine(
        section: 'Стены',
        name: name,
        quantity: qty,
        unit: unit,
      ));
      _appendMaterialLinks(
        lines,
        section: 'Стены',
        layerLabel: name,
        links: layer.materialLinks,
        areaM2: q.areaM2,
      );
    }
    // Do not emit «Слои не заданы» here — ЛК/пустые комнаты засоряли сводку
    // объекта прочерком даже когда у обычных помещений слои уже заданы.
    // Coverage is shown in FinishProjectScreen section tabs instead.
  }

  final skirting = includeFloor ? skirtingLengthM(room) : 0.0;
  if (skirting > 0) {
    lines.add(FinishVedomostLine(
      section: 'Пол',
      name: 'Плинтус напольный',
      quantity: skirting.toStringAsFixed(1),
      unit: 'п.м.',
    ));
  }

  if (includeFloor) {
    final floorBoards = floorKind == FloorCoveringKind.screed
        ? 0
        : floorBoardCountForRoom(room);
    final floorWaste = withWastePercent(floorBoards, 0.05);
    if (floorBoards > 0) {
      lines.add(FinishVedomostLine(
        section: 'Пол',
        name: 'Закупка с запасом 5%',
        quantity: '$floorWaste',
        unit: 'шт',
      ));
    }
  }

  // Floor-related consumables live under «Пол» (no duplicate «Расходники»).
  final consumables =
      includeFloor ? finishConsumablesEstimate(room) : <String, String>{};
  if (consumables.containsKey('Подложка') &&
      !lines.any((l) => l.section == 'Пол' && l.name == 'Подложка')) {
    final raw = consumables['Подложка']!;
    final match = RegExp(r'^([\d.,]+)\s*(.*)$').firstMatch(raw.trim());
    lines.add(FinishVedomostLine(
      section: 'Пол',
      name: 'Подложка',
      quantity: match?.group(1) ?? raw,
      unit: match?.group(2) ?? '',
    ));
  }
  for (final e in consumables.entries) {
    if (e.key.startsWith('Пол · ') || e.key.startsWith('Потолок · ')) continue;
    if (e.key == 'Плинтус напольный' ||
        e.key == 'Подложка' ||
        e.key == 'Стяжка' ||
        e.key == 'Пол · запас 5%') {
      continue;
    }
    final match = RegExp(r'^([\d.,]+)\s*(.*)$').firstMatch(e.value.trim());
    lines.add(FinishVedomostLine(
      section: 'Расходники',
      name: e.key,
      quantity: match?.group(1) ?? e.value,
      unit: match?.group(2) ?? '',
    ));
  }

  return lines.where((l) => room.includesFinishSection(l.section)).toList();
}

(String ceiling, String susp, String cell) _ceilingConfig(
  Room room,
  Project? project,
) {
  if (project != null) return roomEffectiveConfig(room, project);
  return (
    room.materialsCeiling ?? 'Армстронг',
    room.materialsSusp ?? 'Подвес 0,5',
    room.materialsCell ?? '50x50',
  );
}

/// Summary lines for ceiling adapted to Armstrong / Грильято / GL.
List<FinishVedomostLine> _ceilingSummaryLines(Room room, Project? project) {
  final (ceiling, susp, cell) = _ceilingConfig(room, project);
  final out = <FinishVedomostLine>[
    FinishVedomostLine(
      section: 'Потолок',
      name: 'Тип потолка',
      quantity: ceiling,
      unit: '',
    ),
  ];

  if (ceiling == 'Армстронг') {
    final purchase = ceilingPurchaseCount(room);
    if (purchase > 0) {
      out.add(FinishVedomostLine(
        section: 'Потолок',
        name: 'Плиты/кассеты (закупка)',
        quantity: '$purchase',
        unit: 'шт',
      ));
    }
    out.add(FinishVedomostLine(
      section: 'Потолок',
      name: 'Подвес',
      quantity: susp,
      unit: '',
    ));
  } else {
    // Грильято / GL — профильная система, без кассет Armstrong.
    out.add(FinishVedomostLine(
      section: 'Потолок',
      name: 'Ячейка',
      quantity: cell,
      unit: '',
    ));
    out.add(FinishVedomostLine(
      section: 'Потолок',
      name: 'Подвес',
      quantity: susp,
      unit: '',
    ));
    final layout = ceilingLayoutTileCountForRoom(room);
    if (layout > 0) {
      out.add(FinishVedomostLine(
        section: 'Потолок',
        name: '$ceiling · модули 600×600 (раскладка)',
        quantity: '$layout',
        unit: 'шт',
      ));
    }
  }

  final lights = room.lightFixtures.length;
  if (lights > 0) {
    out.add(FinishVedomostLine(
      section: 'Потолок',
      name: 'Светильники',
      quantity: '$lights',
      unit: 'шт',
    ));
  }
  return out;
}

/// Full ceiling frame/BOM lines for expand detail (one room).
List<FinishVedomostLine> buildCeilingComponentLines(
  Room room,
  Project project,
) {
  if (!room.hasLayout) return [];
  final mat = calculateRoomMaterials(room, project);
  final keys = mat.keys.toList()..sort(compareMaterialLineKeys);
  return [
    for (final k in keys)
      FinishVedomostLine(
        section: 'Потолок',
        name: k,
        quantity: '${mat[k]}',
        unit: 'шт',
      ),
  ];
}

/// Aggregated ceiling BOM across rooms (respects mixed types).
List<FinishVedomostLine> aggregateCeilingComponentLines(
  Project project, {
  Iterable<int>? roomIds,
}) {
  final (totals, _, _) = aggregateCeilingTotals(project, roomIds: roomIds);
  if (totals.isEmpty) return [];
  final keys = totals.keys.toList()..sort();
  return [
    for (final k in keys)
      FinishVedomostLine(
        section: 'Потолок',
        name: k,
        quantity: '${totals[k]}',
        unit: 'шт',
      ),
  ];
}

/// Short chip for section header (e.g. «141 м² · Армстронг»).
String finishSectionSummaryChip(
  String section,
  List<FinishVedomostLine> lines,
) {
  String? area;
  String? type;
  String? extra;
  for (final l in lines) {
    if (l.name == 'Площадь') {
      area = '${l.quantity} ${l.unit}'.trim();
    } else if (l.name == 'Тип потолка') {
      type = l.quantity;
    } else if (section == 'Пол' &&
        (l.name.startsWith('Плитка') || l.name.startsWith('Ламинат'))) {
      extra = l.name;
    } else if (section == 'Стены' && l.name == 'Проёмы') {
      final n = double.tryParse(l.quantity.replaceAll(',', '.'));
      if (n != null && n > 0.005) extra = 'проёмы ${l.quantity} ${l.unit}'.trim();
    }
  }
  final parts = <String>[
    if (area != null) area,
    if (type != null) type,
    if (extra != null) extra,
  ];
  if (parts.isEmpty && lines.isNotEmpty) {
    return '${lines.length} поз.';
  }
  return parts.join(' · ');
}

double? _parseLeadingNumber(String quantity) {
  final normalized = quantity.replaceAll(',', '.');
  final match = RegExp(r'^([\d.]+)').firstMatch(normalized.trim());
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

String _formatAggregatedQuantity(double value, FinishVedomostLine sample) {
  final unit = sample.unit.trim();
  if (unit.contains('м²')) {
    return value.toStringAsFixed(2);
  }
  if (value == value.roundToDouble()) {
    return '${value.round()}';
  }
  return value.toStringAsFixed(1);
}

/// How many layout rooms (not ЛК/объём) have enabled wall finish layers.
({int ready, int total}) wallLayersCoverage(Iterable<Room> rooms) {
  var ready = 0;
  var total = 0;
  for (final room in rooms) {
    if (!roomHasFinishGeometry(room)) continue;
    if (room.isSpecialSpace) continue;
    total++;
    final has = room.wallFinishLayers
        .map(FinishLayer.fromJson)
        .any((l) => l.enabled);
    if (has) ready++;
  }
  return (ready: ready, total: total);
}

/// Floor prep layers coverage (ordinary rooms; covering kind is always present).
({int ready, int total}) floorPrepCoverage(Iterable<Room> rooms) {
  var ready = 0;
  var total = 0;
  for (final room in rooms) {
    if (!roomHasFinishGeometry(room)) continue;
    if (room.isSpecialSpace) continue;
    total++;
    final prepOn = room.floorPrepLayers
        .map(SurfacePrepLayer.fromJson)
        .any((l) => l.enabled);
    if (prepOn) ready++;
  }
  return (ready: ready, total: total);
}

/// Ceiling prep layers coverage (ordinary rooms).
({int ready, int total}) ceilingPrepCoverage(Iterable<Room> rooms) {
  var ready = 0;
  var total = 0;
  for (final room in rooms) {
    if (!roomHasFinishGeometry(room)) continue;
    if (room.isSpecialSpace) continue;
    total++;
    final prepOn = room.ceilingPrepLayers
        .map(SurfacePrepLayer.fromJson)
        .any((l) => l.enabled);
    if (prepOn) ready++;
  }
  return (ready: ready, total: total);
}

/// Merges finish vedomost lines across rooms (sums numeric quantities).
///
/// When [includeExtraWorks] is true, project-level (and optional room-scoped)
/// [FinishExtraWork] lines are appended under section «Другие работы».
List<FinishVedomostLine> aggregateFinishVedomostLines(
  Project project, {
  Iterable<int>? roomIds,
  bool includeExtraWorks = true,
}) {
  final idSet = roomIds?.toSet();
  final buckets = <String, List<FinishVedomostLine>>{};

  for (final room in project.rooms) {
    if (room.id != null && idSet != null && !idSet.contains(room.id)) continue;
    if (!roomHasFinishGeometry(room)) continue;
    for (final line in buildFinishVedomostLines(room, project: project)) {
      // Legacy placeholder from older builds — never aggregate.
      if (line.name == 'Слои не заданы') continue;
      final linkKey = line.linkedItemKey ?? '';
      buckets
          .putIfAbsent('${line.section}||${line.name}||$linkKey', () => [])
          .add(line);
    }
  }

  final out = <FinishVedomostLine>[];
  for (final group in buckets.values) {
    final sample = group.first;
    if (group.length == 1) {
      out.add(sample);
      continue;
    }
    final slashParts = sample.quantity.split(' / ');
    if (slashParts.length == 2) {
      var left = 0.0;
      var right = 0.0;
      var ok = true;
      for (final line in group) {
        final parts = line.quantity.split(' / ');
        if (parts.length != 2) {
          ok = false;
          break;
        }
        final l = _parseLeadingNumber(parts[0]);
        final r = _parseLeadingNumber(parts[1]);
        if (l == null || r == null) {
          ok = false;
          break;
        }
        left += l;
        right += r;
      }
      if (ok) {
        out.add(FinishVedomostLine(
          section: sample.section,
          name: sample.name,
          quantity:
              '${left.toStringAsFixed(2)} / ${right.round()}',
          unit: sample.unit,
          linkedItemKey: sample.linkedItemKey,
        ));
        continue;
      }
    }

    // Thickness / size: do not sum across rooms.
    final unit = sample.unit.trim();
    if (unit == 'см' || sample.name.contains('толщина') || sample.name.contains('Размер')) {
      final values = group.map((l) => l.quantity).toSet();
      if (values.length == 1) {
        out.add(sample);
      } else {
        out.add(FinishVedomostLine(
          section: sample.section,
          name: sample.name,
          quantity: 'разная',
          unit: unit,
          linkedItemKey: sample.linkedItemKey,
        ));
      }
      continue;
    }

    final nums = group.map((l) => _parseLeadingNumber(l.quantity)).toList();
    if (nums.every((n) => n != null)) {
      final sum = nums.fold<double>(0, (a, b) => a + b!);
      out.add(FinishVedomostLine(
        section: sample.section,
        name: sample.name,
        quantity: _formatAggregatedQuantity(sum, sample),
        unit: sample.unit,
        linkedItemKey: sample.linkedItemKey,
      ));
      continue;
    }

    final values = group.map((l) => l.quantity).toSet();
    if (values.length == 1) {
      out.add(sample);
      continue;
    }

    out.add(FinishVedomostLine(
      section: sample.section,
      name: sample.name,
      quantity: '${group.length} помещ.',
      unit: '',
      linkedItemKey: sample.linkedItemKey,
    ));
  }

  if (includeExtraWorks) {
    // Only append when there are actual extra-work lines (empty → omitted).
    out.addAll(finishExtraWorkVedomostLines(project, roomIds: roomIds));
  }

  const sectionOrder = [
    'Потолок',
    'Стены',
    'Пол',
    'Расходники',
    'Другие работы',
  ];
  out.sort((a, b) {
    final ai = sectionOrder.indexOf(a.section);
    final bi = sectionOrder.indexOf(b.section);
    final ao = ai < 0 ? sectionOrder.length : ai;
    final bo = bi < 0 ? sectionOrder.length : bi;
    if (ao != bo) return ao.compareTo(bo);
    return a.name.compareTo(b.name);
  });
  return out;
}

/// Vedomost lines from [FinishExtraWorksState] on the project.
List<FinishVedomostLine> finishExtraWorkVedomostLines(
  Project project, {
  Iterable<int>? roomIds,
}) {
  final state = FinishExtraWorksState.fromJson(project.finishExtraWorksJson);
  final idSet = roomIds?.toSet();
  final out = <FinishVedomostLine>[];
  for (final w in state.works) {
    if (w.roomId != null) {
      if (idSet != null && !idSet.contains(w.roomId)) continue;
    }
    if (w.title.trim().isEmpty) continue;
    final qty = w.quantityWithWaste;
    if (qty <= 0) continue;
    final label = w.materialLabel?.trim().isNotEmpty == true
        ? '${w.title} · ${w.materialLabel}'
        : w.title;
    out.add(FinishVedomostLine(
      section: 'Другие работы',
      name: w.category.trim().isEmpty ? label : '${w.category}: $label',
      quantity: formatFinishWorkQty(qty, w.unit),
      unit: w.unit.labelRu,
    ));
  }
  return out;
}

/// Combined ceiling purchase + finish quantities for documentation.
Map<String, String> buildCombinedMaterialsSummary(Room room, Project project) {
  final finish = buildFinishVedomostLines(room, project: project);
  final out = <String, String>{};

  if (room.finishIncludeCeiling) {
    final ceiling = calculateRoomMaterials(room, project);
    for (final e in ceiling.entries) {
      out['Потолок · ${e.key}'] = '${e.value} шт';
    }
  }
  for (final f in finish) {
    out['${f.section} · ${f.name}'] = '${f.quantity} ${f.unit}'.trim();
  }
  for (final f in finishExtraWorkVedomostLines(
    project,
    roomIds: room.id == null ? null : [room.id!],
  )) {
    out['${f.section} · ${f.name}'] = '${f.quantity} ${f.unit}'.trim();
  }
  return out;
}

int ceilingPurchaseCount(Room room) {
  if (!room.hasLayout) return 0;
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
  final layoutTiles = grid.cells
      .where((c) => c.kind == CellKind.full || c.kind == CellKind.cut)
      .map((c) => (isFull: c.kind == CellKind.full, cutXCm: c.cutXCm, cutYCm: c.cutYCm));
  return MaterialsCalculator.estimatePurchaseCassettes(
    walls: room.walls,
    layoutTiles: layoutTiles,
    cellCm: grid.cellSizeCm,
  );
}
