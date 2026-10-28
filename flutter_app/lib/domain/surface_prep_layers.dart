import 'dart:convert';

import 'finish_material_links.dart';

/// Optional preparatory layers under the main floor covering / ceiling finish.
/// The main covering (laminate/tile/Armstrong…) stays in existing room fields;
/// these layers are extra quantity lines when the user enables «Доп. слои».

enum FloorPrepKind {
  screed('screed', 'Стяжка'),
  leveling('leveling', 'Финишная стяжка'),
  waterproof('waterproof', 'Гидроизоляция'),
  underlay('underlay', 'Подложка'),
  adhesive('adhesive', 'Клей'),
  other('other', 'Другое');

  const FloorPrepKind(this.id, this.labelRu);
  final String id;
  final String labelRu;

  static FloorPrepKind parse(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    for (final k in FloorPrepKind.values) {
      if (k.id == s) return k;
    }
    return FloorPrepKind.other;
  }
}

enum CeilingPrepKind {
  insulation('insulation', 'Утеплитель'),
  vaporBarrier('vapor_barrier', 'Пароизоляция'),
  paint('paint', 'Покраска'),
  plaster('plaster', 'Штукатурка'),
  putty('putty', 'Шпаклёвка'),
  other('other', 'Другое');

  const CeilingPrepKind(this.id, this.labelRu);
  final String id;
  final String labelRu;

  static CeilingPrepKind parse(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    for (final k in CeilingPrepKind.values) {
      if (k.id == s) return k;
    }
    return CeilingPrepKind.other;
  }
}

class SurfacePrepLayer {
  SurfacePrepLayer({
    required this.kindId,
    this.label,
    this.enabled = true,
    this.thicknessCm = 0,
    this.unitPrice,
    this.rateMatchKey,
    this.rateName,
    this.priceGroupId,
    List<FinishMaterialLink>? materialLinks,
  }) : materialLinks = materialLinks ?? [];

  String kindId;
  String? label;
  bool enabled;

  /// Used for screed / insulation volume ≈ area × thickness.
  double thicknessCm;

  /// Work rate: ₽/м³ when [usesThickness], otherwise ₽/м² (feeds КП/КС).
  double? unitPrice;
  String? rateMatchKey;
  String? rateName;

  /// Shared price group («одна итерация» с общей ценой).
  String? priceGroupId;

  /// Optional materials for this prep layer.
  List<FinishMaterialLink> materialLinks;

  String displayName({required bool floor}) {
    final custom = label?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    if (floor) return FloorPrepKind.parse(kindId).labelRu;
    return CeilingPrepKind.parse(kindId).labelRu;
  }

  bool get usesThickness {
    final f = FloorPrepKind.parse(kindId);
    final c = CeilingPrepKind.parse(kindId);
    return f == FloorPrepKind.screed ||
        f == FloorPrepKind.leveling ||
        c == CeilingPrepKind.insulation;
  }

  /// Rough purchase line for materials / vedomost: `(quantity, unit)`.
  (String quantity, String unit) materialQty(
    double areaM2, {
    required bool floor,
  }) {
    final a = areaM2 < 0 ? 0.0 : areaM2;
    final areaStr = a.toStringAsFixed(2);
    if (usesThickness && thicknessCm > 0) {
      final vol = a * (thicknessCm / 100.0);
      return (vol.toStringAsFixed(3), 'м³');
    }
    if (floor) {
      return switch (FloorPrepKind.parse(kindId)) {
        FloorPrepKind.adhesive => ((a * 0.35).toStringAsFixed(1), 'кг'),
        _ => (areaStr, 'м²'),
      };
    }
    return switch (CeilingPrepKind.parse(kindId)) {
      CeilingPrepKind.paint => ((a * 0.12).toStringAsFixed(1), 'л'),
      CeilingPrepKind.plaster => ((a * 0.9).toStringAsFixed(1), 'кг'),
      CeilingPrepKind.putty => ((a * 0.5).toStringAsFixed(1), 'кг'),
      _ => (areaStr, 'м²'),
    };
  }

  Map<String, dynamic> toJson() => {
        'kind': kindId,
        'label': label,
        'enabled': enabled,
        'thickness_cm': thicknessCm,
        if (unitPrice != null) 'unit_price': unitPrice,
        if (rateMatchKey != null && rateMatchKey!.isNotEmpty)
          'rate_match_key': rateMatchKey,
        if (rateName != null && rateName!.isNotEmpty) 'rate_name': rateName,
        if (priceGroupId != null && priceGroupId!.isNotEmpty)
          'price_group_id': priceGroupId,
        if (materialLinks.isNotEmpty)
          'materials': encodeMaterialLinks(materialLinks),
      };

  static SurfacePrepLayer fromJson(Map<String, dynamic> j) => SurfacePrepLayer(
        kindId: j['kind'] as String? ?? 'other',
        label: j['label'] as String?,
        enabled: j['enabled'] as bool? ?? true,
        thicknessCm: (j['thickness_cm'] as num?)?.toDouble() ?? 0,
        unitPrice: (j['unit_price'] as num?)?.toDouble(),
        rateMatchKey: j['rate_match_key'] as String?,
        rateName: j['rate_name'] as String?,
        priceGroupId: j['price_group_id'] as String?,
        materialLinks: decodeMaterialLinks(j['materials']),
      );
}

/// Sum of enabled prep-layer unit prices as effective ₽/м² of [areaM2].
/// Volumetric layers (стяжка / утеплитель) use ₽/м³ × объём → ÷ площадь.
/// Same [SurfacePrepLayer.priceGroupId] counts once.
double? sumPrepLayerUnitPrices(
  Iterable<SurfacePrepLayer> layers, {
  double areaM2 = 1,
}) {
  final money = sumPrepLayerWorkTotal(layers, areaM2: areaM2);
  if (money == null || areaM2 <= 0) return money;
  return money / areaM2;
}

/// Absolute work total (₽) for enabled prep layers on [areaM2].
double? sumPrepLayerWorkTotal(
  Iterable<SurfacePrepLayer> layers, {
  required double areaM2,
}) {
  final a = areaM2 < 0 ? 0.0 : areaM2;
  final seenGroups = <String>{};
  var sum = 0.0;
  var any = false;
  for (final l in layers) {
    if (!l.enabled) continue;
    final p = l.unitPrice;
    if (p == null || p <= 0) continue;
    final g = l.priceGroupId;
    if (g != null && g.isNotEmpty) {
      if (seenGroups.contains(g)) continue;
      seenGroups.add(g);
    }
    if (l.usesThickness && l.thicknessCm > 0) {
      sum += a * (l.thicknessCm / 100.0) * p;
    } else {
      sum += a * p;
    }
    any = true;
  }
  return any ? sum : null;
}

List<SurfacePrepLayer> decodePrepLayers(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return [];
    return [
      for (final e in list)
        if (e is Map)
          SurfacePrepLayer.fromJson(Map<String, dynamic>.from(e)),
    ];
  } catch (_) {
    return [];
  }
}

String encodePrepLayers(List<SurfacePrepLayer> layers) =>
    jsonEncode([for (final l in layers) l.toJson()]);
