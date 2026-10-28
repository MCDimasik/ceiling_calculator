import 'finish_model.dart';
import 'floor_covering.dart';
import 'models.dart';
import 'room_finish_areas.dart';
import 'surface_prep_layers.dart';
import 'work_rates_catalog.dart';
import 'work_rates_lookup.dart';

/// Prefer these catalog matchKeys / name fragments per wall layer kind.
/// Exact `xx_yy` keys are tried first; short prefixes (`pl_`) match by startsWith.
List<String> wallLayerCatalogHints(FinishLayerKind kind) => switch (kind) {
      FinishLayerKind.primer =>
        const ['pt_primer_w', 'грунтов', 'стен'],
      FinishLayerKind.plaster =>
        const ['pl_beacon_30', 'pl_beacon', 'штукатур', 'стен'],
      FinishLayerKind.putty =>
        const ['pt_putty_paint', 'pt_putty_wall', 'шпакл', 'шпаклев'],
      FinishLayerKind.paint =>
        const ['pt_paint_w', 'покраск', 'краск'],
      FinishLayerKind.tile =>
        const ['tl_wall', 'плитк', 'облицовка стен'],
      FinishLayerKind.demolition =>
        const ['dem_plaster', 'демонтаж', 'стен'],
    };

List<String> prepLayerCatalogHints({
  required bool floor,
  required String kindId,
}) {
  if (floor) {
    return switch (kindId) {
      'screed' => const ['sc_cps_50', 'sc_self', 'стяжк', 'пол'],
      'leveling' => const ['sc_self', 'наливн', 'самовыравн', 'стяжк'],
      'waterproof' => const ['гидроизол'],
      // Underlay itself is not a catalog work line; keep soft name hints only.
      'underlay' => const ['подлож', 'подклад'],
      'adhesive' => const ['клей', 'плитк'],
      _ => const ['пол', 'наполь'],
    };
  }
  return switch (kindId) {
    'insulation' => const ['утеплит', 'потол'],
    'vapor_barrier' => const ['пароизол'],
    'paint' => const ['pt_paint_c', 'покраск', 'потол'],
    'plaster' => const ['pl_ceil_30', 'pl_ceil', 'штукатур', 'потол'],
    'putty' => const ['pt_putty_ceil', 'шпакл', 'потол'],
    _ => const ['потол'],
  };
}

/// Map our floor covering kinds → catalog work rates (укладка).
List<String> floorCoveringCatalogHints({
  required FloorCoveringKind kind,
  FloorLayingPattern pattern = FloorLayingPattern.straight,
}) =>
    switch (kind) {
      FloorCoveringKind.laminate => pattern == FloorLayingPattern.diagonal
          ? const ['fl_lam_diag', 'fl_lam', 'ламинат']
          : const ['fl_lam', 'ламинат'],
      FloorCoveringKind.tile => pattern == FloorLayingPattern.diagonal
          ? const ['tl_floor_diag', 'tl_floor', 'плитк', 'пол']
          : const ['tl_floor', 'плитк', 'пол'],
      FloorCoveringKind.screed =>
        const ['sc_cps_50', 'sc_self', 'стяжк', 'пол'],
    };

/// Map our ceiling system names → catalog (Армстронг / Грильято / …).
List<String> ceilingSystemCatalogHints(String? materialsCeiling) {
  final s = (materialsCeiling ?? '').toLowerCase();
  if (s.contains('гриль') || s.contains('gril') || s == 'gl') {
    return const ['ceil_grilyato', 'грильято', 'потол'];
  }
  if (s.contains('рееч') || s.contains('rail')) {
    return const ['ceil_rail', 'рееч', 'потол'];
  }
  return const ['ceil_armstrong', 'армстронг', 'подвесн', 'потол'];
}

bool _looksLikeMatchKey(String h) =>
    h.contains('_') && RegExp(r'^[a-z0-9_]+$').hasMatch(h);

WorkRateItem? _matchByHints({
  required String displayName,
  required String section,
  required List<String> hints,
  required List<WorkRateCategory> categories,
}) {
  final flat = flattenWorkRates(categories);
  // 1) Exact matchKey
  for (final hint in hints) {
    final h = hint.toLowerCase();
    if (!_looksLikeMatchKey(h)) continue;
    for (final hit in flat) {
      if (hit.item.matchKey.toLowerCase() == h && hit.item.unitPrice > 0) {
        return hit.item;
      }
    }
  }
  // 2) Prefix matchKey (e.g. pl_beacon → pl_beacon_30)
  for (final hint in hints) {
    final h = hint.toLowerCase();
    if (!_looksLikeMatchKey(h) || h.length < 3) continue;
    for (final hit in flat) {
      final key = hit.item.matchKey.toLowerCase();
      if (key.startsWith(h) && hit.item.unitPrice > 0) {
        return hit.item;
      }
    }
  }
  // 3) Fuzzy name match in section
  final fuzzy = matchWorkRateItem(
    name: displayName,
    section: section,
    categories: categories,
  );
  if (fuzzy != null && fuzzy.unitPrice > 0) return fuzzy;

  // 4) Soft fallback: section-relevant item containing a hint word
  final ranked = rankWorkRatesForSection(categories, section: section);
  for (final hit in ranked) {
    if (!hit.sectionRelevant || hit.item.unitPrice <= 0) continue;
    final hay = '${hit.item.name} ${hit.item.matchKey}'.toLowerCase();
    if (hints.any((h) => h.length >= 3 && hay.contains(h.toLowerCase()))) {
      return hit.item;
    }
  }
  return null;
}

/// Auto-fill missing layer prices from the work-rates catalog.
/// Returns how many layers received a new price.
int autofillWallLayerPrices(
  List<FinishLayer> layers,
  List<WorkRateCategory> catalog, {
  bool onlyEmpty = true,
}) {
  var n = 0;
  for (final layer in layers) {
    if (onlyEmpty && layer.unitPrice != null && layer.unitPrice! > 0) continue;
    final hit = _matchByHints(
      displayName: layer.displayLabel,
      section: 'walls',
      hints: wallLayerCatalogHints(layer.kind),
      categories: catalog,
    );
    if (hit == null || hit.unitPrice <= 0) continue;
    layer.unitPrice = hit.unitPrice;
    layer.rateMatchKey = hit.matchKey;
    layer.rateName = hit.name;
    n++;
  }
  return n;
}

int autofillPrepLayerPrices(
  List<SurfacePrepLayer> layers,
  List<WorkRateCategory> catalog, {
  required bool floor,
  bool onlyEmpty = true,
}) {
  final section = floor ? 'floor' : 'ceiling';
  var n = 0;
  for (final layer in layers) {
    if (onlyEmpty && layer.unitPrice != null && layer.unitPrice! > 0) continue;
    final hit = _matchByHints(
      displayName: layer.displayName(floor: floor),
      section: section,
      hints: prepLayerCatalogHints(floor: floor, kindId: layer.kindId),
      categories: catalog,
    );
    if (hit == null || hit.unitPrice <= 0) continue;
    var price = hit.unitPrice;
    // Catalog screed/insulation rates are often ₽/м² → store ₽/м³.
    if (layer.usesThickness &&
        (hit.unit == 'м²' || hit.unit == 'м2' || hit.unit.isEmpty)) {
      final d = layer.thicknessCm <= 0 ? defaultScreedDepthCm : layer.thicknessCm;
      price = screedCatalogM2ToM3(price, d);
    }
    layer.unitPrice = price;
    layer.rateMatchKey = hit.matchKey;
    layer.rateName = hit.name;
    n++;
  }
  return n;
}

/// Propagate [unitPrice] to every layer sharing [groupId].
void syncWallLayerGroupPrice(
  List<FinishLayer> layers, {
  required String groupId,
  required double unitPrice,
  String? rateMatchKey,
  String? rateName,
}) {
  if (groupId.isEmpty) return;
  for (final l in layers) {
    if (l.priceGroupId != groupId) continue;
    l.unitPrice = unitPrice;
    if (rateMatchKey != null) l.rateMatchKey = rateMatchKey;
    if (rateName != null) l.rateName = rateName;
  }
}

void syncPrepLayerGroupPrice(
  List<SurfacePrepLayer> layers, {
  required String groupId,
  required double unitPrice,
  String? rateMatchKey,
  String? rateName,
}) {
  if (groupId.isEmpty) return;
  for (final l in layers) {
    if (l.priceGroupId != groupId) continue;
    l.unitPrice = unitPrice;
    if (rateMatchKey != null) l.rateMatchKey = rateMatchKey;
    if (rateName != null) l.rateName = rateName;
  }
}

/// Individual edit broke the shared price — clear the group for everyone.
void dissolveWallPriceGroup(List<FinishLayer> layers, String? groupId) {
  if (groupId == null || groupId.isEmpty) return;
  for (final l in layers) {
    if (l.priceGroupId == groupId) l.priceGroupId = null;
  }
}

void dissolvePrepPriceGroup(List<SurfacePrepLayer> layers, String? groupId) {
  if (groupId == null || groupId.isEmpty) return;
  for (final l in layers) {
    if (l.priceGroupId == groupId) l.priceGroupId = null;
  }
}

/// New shared-price group id, scoped to [roomId] so bulk-copy never
/// paints the same accent across unrelated rooms.
String newPriceGroupId({int? roomId}) {
  final r = roomId ?? 0;
  final t = DateTime.now().microsecondsSinceEpoch;
  return 'g_${r}_$t';
}

bool _sameUnitPrice(double? a, double? b) {
  final aa = a ?? 0;
  final bb = b ?? 0;
  return (aa - bb).abs() < 0.005;
}

/// Drop invalid shared-price marks:
/// - fewer than 2 members
/// - members with different unit prices (group was copied, then prices diverged)
/// - foreign ids from another room → remint only when prices still match
void sanitizeWallPriceGroups(List<FinishLayer> layers, {int? roomId}) {
  final byGroup = <String, List<FinishLayer>>{};
  for (final l in layers) {
    final g = l.priceGroupId;
    if (g == null || g.isEmpty) continue;
    byGroup.putIfAbsent(g, () => []).add(l);
  }
  for (final e in byGroup.entries) {
    final members = e.value;
    if (members.length < 2) {
      for (final l in members) {
        l.priceGroupId = null;
      }
      continue;
    }
    final p0 = members.first.unitPrice;
    final samePrice = members.every((l) => _sameUnitPrice(l.unitPrice, p0));
    if (!samePrice) {
      for (final l in members) {
        l.priceGroupId = null;
      }
      continue;
    }
    if (roomId != null && !e.key.contains('_${roomId}_')) {
      final nid = newPriceGroupId(roomId: roomId);
      for (final l in members) {
        l.priceGroupId = nid;
      }
    }
  }
}

void sanitizePrepPriceGroups(List<SurfacePrepLayer> layers, {int? roomId}) {
  final byGroup = <String, List<SurfacePrepLayer>>{};
  for (final l in layers) {
    final g = l.priceGroupId;
    if (g == null || g.isEmpty) continue;
    byGroup.putIfAbsent(g, () => []).add(l);
  }
  for (final e in byGroup.entries) {
    final members = e.value;
    if (members.length < 2) {
      for (final l in members) {
        l.priceGroupId = null;
      }
      continue;
    }
    final p0 = members.first.unitPrice;
    final samePrice = members.every((l) => _sameUnitPrice(l.unitPrice, p0));
    if (!samePrice) {
      for (final l in members) {
        l.priceGroupId = null;
      }
      continue;
    }
    if (roomId != null && !e.key.contains('_${roomId}_')) {
      final nid = newPriceGroupId(roomId: roomId);
      for (final l in members) {
        l.priceGroupId = nid;
      }
    }
  }
}

/// Heal shared-price marks on every room (call when opening finish hub / room).
/// Returns how many rooms were rewritten.
Future<int> sanitizeProjectPriceGroups(
  Iterable<Room> rooms, {
  required Future<void> Function(Room room) persist,
}) async {
  var n = 0;
  for (final room in rooms) {
    if (room.id == null) continue;
    final wallsBefore = room.wallFinishLayers
        .map((e) => '${e['price_group_id']}|${e['unit_price']}')
        .join(';');
    final floorBefore = room.floorPrepLayers
        .map((e) => '${e['price_group_id']}|${e['unit_price']}')
        .join(';');
    final ceilBefore = room.ceilingPrepLayers
        .map((e) => '${e['price_group_id']}|${e['unit_price']}')
        .join(';');

    final walls = room.wallFinishLayers.map(FinishLayer.fromJson).toList();
    sanitizeWallPriceGroups(walls, roomId: room.id);
    room.wallFinishLayers = walls.map((l) => l.toJson()).toList();

    final floorPrep =
        room.floorPrepLayers.map(SurfacePrepLayer.fromJson).toList();
    sanitizePrepPriceGroups(floorPrep, roomId: room.id);
    room.floorPrepLayers = floorPrep.map((l) => l.toJson()).toList();

    final ceilPrep =
        room.ceilingPrepLayers.map(SurfacePrepLayer.fromJson).toList();
    sanitizePrepPriceGroups(ceilPrep, roomId: room.id);
    room.ceilingPrepLayers = ceilPrep.map((l) => l.toJson()).toList();

    final wallsAfter = room.wallFinishLayers
        .map((e) => '${e['price_group_id']}|${e['unit_price']}')
        .join(';');
    final floorAfter = room.floorPrepLayers
        .map((e) => '${e['price_group_id']}|${e['unit_price']}')
        .join(';');
    final ceilAfter = room.ceilingPrepLayers
        .map((e) => '${e['price_group_id']}|${e['unit_price']}')
        .join(';');
    if (wallsBefore != wallsAfter ||
        floorBefore != floorAfter ||
        ceilBefore != ceilAfter) {
      await persist(room);
      n++;
    }
  }
  return n;
}

/// Deep-copy wall layers for another room with fresh per-room group ids.
List<Map<String, dynamic>> cloneWallLayersForRoom(
  List<FinishLayer> source, {
  required int? roomId,
}) {
  final layers = source
      .map((l) => FinishLayer.fromJson(Map<String, dynamic>.from(l.toJson())))
      .toList();
  final remap = <String, String>{};
  for (final l in layers) {
    final g = l.priceGroupId;
    if (g == null || g.isEmpty) continue;
    remap.putIfAbsent(g, () => newPriceGroupId(roomId: roomId));
  }
  for (final l in layers) {
    final g = l.priceGroupId;
    if (g != null && remap.containsKey(g)) l.priceGroupId = remap[g];
  }
  sanitizeWallPriceGroups(layers, roomId: roomId);
  return layers.map((l) => l.toJson()).toList();
}

List<Map<String, dynamic>> clonePrepLayersForRoom(
  List<SurfacePrepLayer> source, {
  required int? roomId,
}) {
  final layers = source
      .map(
        (l) => SurfacePrepLayer.fromJson(Map<String, dynamic>.from(l.toJson())),
      )
      .toList();
  final remap = <String, String>{};
  for (final l in layers) {
    final g = l.priceGroupId;
    if (g == null || g.isEmpty) continue;
    remap.putIfAbsent(g, () => newPriceGroupId(roomId: roomId));
  }
  for (final l in layers) {
    final g = l.priceGroupId;
    if (g != null && remap.containsKey(g)) l.priceGroupId = remap[g];
  }
  sanitizePrepPriceGroups(layers, roomId: roomId);
  return layers.map((l) => l.toJson()).toList();
}

/// True when [groupId] is shared by ≥2 layers with the same unit price.
bool priceGroupIsActive(
  Iterable<String?> groupIds,
  String? groupId, {
  Iterable<double?>? unitPrices,
}) {
  if (groupId == null || groupId.isEmpty) return false;
  final ids = groupIds.toList();
  final prices = unitPrices?.toList();
  var n = 0;
  double? firstPrice;
  var sawPrice = false;
  for (var i = 0; i < ids.length; i++) {
    if (ids[i] != groupId) continue;
    n++;
    if (prices != null && i < prices.length) {
      final p = prices[i];
      if (!sawPrice) {
        firstPrice = p;
        sawPrice = true;
      } else if (!_sameUnitPrice(p, firstPrice)) {
        return false;
      }
    }
  }
  return n >= 2;
}

/// Apply one shared price to selected wall layers and bind them with [groupId].
void bindWallLayersSharedPrice(
  List<FinishLayer> layers,
  Set<int> indices, {
  required double unitPrice,
  required String groupId,
  String? rateMatchKey,
  String? rateName,
}) {
  for (final i in indices) {
    if (i < 0 || i >= layers.length) continue;
    layers[i].unitPrice = unitPrice;
    layers[i].priceGroupId = groupId.isEmpty ? null : groupId;
    if (rateMatchKey != null) layers[i].rateMatchKey = rateMatchKey;
    if (rateName != null) layers[i].rateName = rateName;
  }
}

void bindPrepLayersSharedPrice(
  List<SurfacePrepLayer> layers,
  Set<int> indices, {
  required double unitPrice,
  required String groupId,
  String? rateMatchKey,
  String? rateName,
}) {
  for (final i in indices) {
    if (i < 0 || i >= layers.length) continue;
    layers[i].unitPrice = unitPrice;
    layers[i].priceGroupId = groupId.isEmpty ? null : groupId;
    if (rateMatchKey != null) layers[i].rateMatchKey = rateMatchKey;
    if (rateName != null) layers[i].rateName = rateName;
  }
}

/// Unit price for main floor covering as stored on room.
/// Screed: ₽/м³; laminate/tile: ₽/м².
double? floorCoveringUnitPriceOf(Room room) {
  final p = room.floorCoveringUnitPrice;
  if (p == null || p <= 0) return null;
  return p;
}

/// ₽/м² for main ceiling system (stored on room).
double? ceilingSystemUnitPriceOf(Room room) {
  final p = room.ceilingSystemUnitPrice;
  if (p == null || p <= 0) return null;
  return p;
}

double _roomFloorAreaM2(Room room) => resolveRoomFinishAreas(room).floorM2;

double _roomCeilingAreaM2(Room room) =>
    resolveRoomFinishAreas(room).ceilingM2;

/// Absolute floor-scope work total (₽) including prep + covering.
double? floorScopeWorkTotal(Room room, {double? floorM2}) {
  final area = floorM2 ?? _roomFloorAreaM2(room);
  if (area <= 0) return null;
  var total = 0.0;
  var any = false;
  final prep = sumPrepLayerWorkTotal(
    room.floorPrepLayers.map(SurfacePrepLayer.fromJson),
    areaM2: area,
  );
  if (prep != null) {
    total += prep;
    any = true;
  }
  final cover = floorCoveringUnitPriceOf(room);
  if (cover != null) {
    if (FloorCoveringKindX.parse(room.floorCoveringKind) ==
        FloorCoveringKind.screed) {
      final d = room.floorScreedDepthCm <= 0
          ? defaultScreedDepthCm
          : room.floorScreedDepthCm;
      total += screedVolumeM3(area, d) * cover;
    } else {
      total += area * cover;
    }
    any = true;
  }
  return any ? total : null;
}

/// Effective ₽/м² for floor scope (КП/КС line = area × this).
double? floorScopeUnitPrice(Room room, {double? floorM2}) {
  final area = floorM2 ?? _roomFloorAreaM2(room);
  final money = floorScopeWorkTotal(room, floorM2: area);
  if (money == null || area <= 0) return null;
  return money / area;
}

/// Absolute ceiling-scope work total (₽).
double? ceilingScopeWorkTotal(Room room, {double? ceilingM2}) {
  final area = ceilingM2 ?? _roomCeilingAreaM2(room);
  if (area <= 0) return null;
  var total = 0.0;
  var any = false;
  final prep = sumPrepLayerWorkTotal(
    room.ceilingPrepLayers.map(SurfacePrepLayer.fromJson),
    areaM2: area,
  );
  if (prep != null) {
    total += prep;
    any = true;
  }
  final system = ceilingSystemUnitPriceOf(room);
  if (system != null) {
    total += area * system;
    any = true;
  }
  return any ? total : null;
}

/// Effective ₽/м² for ceiling scope.
double? ceilingScopeUnitPrice(Room room, {double? ceilingM2}) {
  final area = ceilingM2 ?? _roomCeilingAreaM2(room);
  final money = ceilingScopeWorkTotal(room, ceilingM2: area);
  if (money == null || area <= 0) return null;
  return money / area;
}

WorkRateItem? matchFloorCoveringRate(
  Room room,
  List<WorkRateCategory> catalog,
) {
  final kind = FloorCoveringKindX.parse(room.floorCoveringKind);
  final pattern = FloorLayingPatternX.parse(room.floorLayingPattern);
  return _matchByHints(
    displayName: kind.labelRu,
    section: 'floor',
    hints: floorCoveringCatalogHints(kind: kind, pattern: pattern),
    categories: catalog,
  );
}

WorkRateItem? matchCeilingSystemRate(
  Room room,
  List<WorkRateCategory> catalog,
) {
  final label = room.materialsCeiling ?? 'Армстронг';
  return _matchByHints(
    displayName: label,
    section: 'ceiling',
    hints: ceilingSystemCatalogHints(label),
    categories: catalog,
  );
}

/// One-shot: catalog-sourced screed prices were stored as ₽/м²; convert to ₽/м³.
/// Only touches rows that still look like area rates (< 8 000) and have a catalog key.
int migrateScreedPricesToM3(Room room) {
  var n = 0;
  if (FloorCoveringKindX.parse(room.floorCoveringKind) ==
      FloorCoveringKind.screed) {
    final p = room.floorCoveringUnitPrice;
    final key = room.floorCoveringRateMatchKey;
    if (p != null &&
        p > 0 &&
        p < 8000 &&
        key != null &&
        key.isNotEmpty) {
      final d = room.floorScreedDepthCm <= 0
          ? defaultScreedDepthCm
          : room.floorScreedDepthCm;
      room.floorCoveringUnitPrice = screedCatalogM2ToM3(p, d);
      n++;
    }
  }
  for (final floor in [true, false]) {
    final raw = floor ? room.floorPrepLayers : room.ceilingPrepLayers;
    final layers = raw.map(SurfacePrepLayer.fromJson).toList();
    var changed = false;
    for (final l in layers) {
      if (!l.usesThickness) continue;
      final p = l.unitPrice;
      final key = l.rateMatchKey;
      if (p == null || p <= 0 || p >= 8000) continue;
      if (key == null || key.isEmpty) continue;
      final d = l.thicknessCm <= 0 ? defaultScreedDepthCm : l.thicknessCm;
      l.unitPrice = screedCatalogM2ToM3(p, d);
      changed = true;
      n++;
    }
    if (changed) {
      final encoded = layers.map((e) => e.toJson()).toList();
      if (floor) {
        room.floorPrepLayers = encoded;
      } else {
        room.ceilingPrepLayers = encoded;
      }
    }
  }
  return n;
}

/// Autofill main covering / system prices from the work-rates catalog.
/// Returns how many fields received a new price.
int autofillCoveringPrices(
  Iterable<Room> rooms,
  List<WorkRateCategory> catalog, {
  bool onlyEmpty = true,
}) {
  var n = 0;
  for (final room in rooms) {
    final floorEmpty =
        room.floorCoveringUnitPrice == null || room.floorCoveringUnitPrice! <= 0;
    if (!onlyEmpty || floorEmpty) {
      final hit = matchFloorCoveringRate(room, catalog);
      if (hit != null && hit.unitPrice > 0) {
        var price = hit.unitPrice;
        // Catalog screed rates are ₽/м² → store ₽/м³ for volume pricing.
        if (FloorCoveringKindX.parse(room.floorCoveringKind) ==
            FloorCoveringKind.screed) {
          final d = room.floorScreedDepthCm <= 0
              ? defaultScreedDepthCm
              : room.floorScreedDepthCm;
          price = screedCatalogM2ToM3(price, d);
        }
        room.floorCoveringUnitPrice = price;
        room.floorCoveringRateMatchKey = hit.matchKey;
        room.floorCoveringRateName = hit.name;
        n++;
      }
    }
    final ceilEmpty =
        room.ceilingSystemUnitPrice == null || room.ceilingSystemUnitPrice! <= 0;
    if (!onlyEmpty || ceilEmpty) {
      final hit = matchCeilingSystemRate(room, catalog);
      if (hit != null && hit.unitPrice > 0) {
        room.ceilingSystemUnitPrice = hit.unitPrice;
        room.ceilingSystemRateMatchKey = hit.matchKey;
        room.ceilingSystemRateName = hit.name;
        n++;
      }
    }
  }
  return n;
}

/// Project-level finish work totals (₽).
({double floor, double walls, double ceiling}) finishScopePriceTotals(
  Iterable<Room> rooms,
) {
  var floor = 0.0;
  var walls = 0.0;
  var ceiling = 0.0;
  for (final room in rooms) {
    if (!roomHasFinishGeometry(room)) continue;
    final areas = resolveRoomFinishAreas(room);
    final wallLayers = room.wallFinishLayers.map(FinishLayer.fromJson).toList();
    final wallPrice = sumLayerUnitPrices(wallLayers) ?? 0;
    if (room.finishIncludeFloor) {
      floor += floorScopeWorkTotal(room, floorM2: areas.floorM2) ?? 0;
    }
    if (room.finishIncludeWalls) walls += areas.wallsM2 * wallPrice;
    if (room.finishIncludeCeiling) {
      ceiling +=
          ceilingScopeWorkTotal(room, ceilingM2: areas.ceilingM2) ?? 0;
    }
  }
  return (floor: floor, walls: walls, ceiling: ceiling);
}
