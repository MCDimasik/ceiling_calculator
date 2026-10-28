import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'finish_model.dart';
import 'floor_covering.dart';
import 'surface_prep_layers.dart';

/// Optional purchase line tied to a finish / prep layer (or floor covering).
class FinishMaterialLink {
  FinishMaterialLink({
    required this.itemKey,
    required this.productName,
    this.qtyPerUnit = 1,
    this.unit = 'м²',
  });

  /// Supplier / catalog key (`guide_3600`, `rx_…`).
  String itemKey;
  String productName;

  /// Consumption per 1 м² (or 1 м³ when [unit] is м³) of the work surface.
  double qtyPerUnit;
  String unit;

  Map<String, dynamic> toJson() => {
        'item_key': itemKey,
        'product_name': productName,
        'qty_per_unit': qtyPerUnit,
        'unit': unit,
      };

  static FinishMaterialLink fromJson(Map<String, dynamic> j) =>
      FinishMaterialLink(
        itemKey: j['item_key'] as String? ?? '',
        productName: j['product_name'] as String? ?? '',
        qtyPerUnit: (j['qty_per_unit'] as num?)?.toDouble() ?? 1,
        unit: j['unit'] as String? ?? 'м²',
      );

  FinishMaterialLink copy() => FinishMaterialLink(
        itemKey: itemKey,
        productName: productName,
        qtyPerUnit: qtyPerUnit,
        unit: unit,
      );
}

List<FinishMaterialLink> decodeMaterialLinks(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is Map)
        FinishMaterialLink.fromJson(Map<String, dynamic>.from(e)),
  ].where((l) => l.itemKey.isNotEmpty || l.productName.isNotEmpty).toList();
}

List<Map<String, dynamic>> encodeMaterialLinks(List<FinishMaterialLink> links) =>
    [for (final l in links) l.toJson()];

/// Named kit of materials the user can reuse on layers.
class FinishMountKit {
  FinishMountKit({
    required this.id,
    required this.name,
    required this.section,
    required this.items,
    this.layerKind = '',
  });

  final String id;
  final String name;

  /// `walls` | `floor` | `ceiling` | `any`
  final String section;

  /// Optional layer / covering kind id (`paint`, `screed`, `tile`, …).
  /// Empty or `any` = any layer in [section].
  final String layerKind;

  final List<FinishMaterialLink> items;

  bool get hasLayerKind {
    final k = layerKind.trim();
    return k.isNotEmpty && k != 'any';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'section': section,
        if (hasLayerKind) 'layer_kind': layerKind.trim(),
        'items': encodeMaterialLinks(items),
      };

  static FinishMountKit fromJson(Map<String, dynamic> j) => FinishMountKit(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Комплект',
        section: j['section'] as String? ?? 'any',
        layerKind: j['layer_kind'] as String? ?? '',
        items: decodeMaterialLinks(j['items']),
      );

  FinishMountKit copyWith({
    String? id,
    String? name,
    String? section,
    String? layerKind,
    List<FinishMaterialLink>? items,
  }) =>
      FinishMountKit(
        id: id ?? this.id,
        name: name ?? this.name,
        section: section ?? this.section,
        layerKind: layerKind ?? this.layerKind,
        items: items ?? [for (final i in this.items) i.copy()],
      );
}

const _prefKits = 'finish_mount_kits_v1';

Future<List<FinishMountKit>> loadMountKits() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_prefKits);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map)
          FinishMountKit.fromJson(Map<String, dynamic>.from(e)),
    ].where((k) => k.id.isNotEmpty && k.items.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}

Future<void> saveMountKits(List<FinishMountKit> kits) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _prefKits,
    jsonEncode([for (final k in kits) k.toJson()]),
  );
}

Future<List<FinishMountKit>> upsertMountKit(FinishMountKit kit) async {
  final list = await loadMountKits();
  final i = list.indexWhere((k) => k.id == kit.id);
  if (i >= 0) {
    list[i] = kit;
  } else {
    list.add(kit);
  }
  await saveMountKits(list);
  return list;
}

Future<List<FinishMountKit>> deleteMountKit(String id) async {
  final list = await loadMountKits();
  list.removeWhere((k) => k.id == id);
  await saveMountKits(list);
  return list;
}

String newMountKitId() => 'kit_${DateTime.now().millisecondsSinceEpoch}';

String mountKitSectionLabel(String section) => switch (section) {
      'walls' => 'Стены',
      'floor' => 'Пол',
      'ceiling' => 'Потолок',
      _ => 'Любой раздел',
    };

/// Human label for kit → layer binding.
String mountKitLayerKindLabel(String section, String layerKind) {
  final k = layerKind.trim();
  if (k.isEmpty || k == 'any') return 'Любой слой';
  final wall = FinishLayerKindX.tryParse(k);
  if (wall != null) return wall.labelRu;
  if (section == 'floor' || section == 'any') {
    for (final f in FloorPrepKind.values) {
      if (f.id == k) return 'Подготовка · ${f.labelRu}';
    }
    for (final f in FloorCoveringKind.values) {
      if (f.id == k) return 'Покрытие · ${f.labelRu}';
    }
  }
  if (section == 'ceiling' || section == 'any') {
    for (final c in CeilingPrepKind.values) {
      if (c.id == k) return 'Подготовка · ${c.labelRu}';
    }
    if (k == 'system') return 'Система потолка';
  }
  return k;
}

/// Layer-kind options for the kits editor, given [section].
List<({String id, String label})> mountKitLayerKindOptions(String section) {
  final any = (id: 'any', label: 'Любой слой');
  switch (section) {
    case 'walls':
      return [
        any,
        for (final k in FinishLayerKind.values) (id: k.id, label: k.labelRu),
      ];
    case 'floor':
      return [
        any,
        for (final k in FloorPrepKind.values)
          (id: k.id, label: 'Подготовка · ${k.labelRu}'),
        for (final k in FloorCoveringKind.values)
          (id: k.id, label: 'Покрытие · ${k.labelRu}'),
      ];
    case 'ceiling':
      return [
        any,
        for (final k in CeilingPrepKind.values)
          (id: k.id, label: 'Подготовка · ${k.labelRu}'),
        (id: 'system', label: 'Система потолка'),
      ];
    default:
      return [
        any,
        for (final k in FinishLayerKind.values)
          (id: k.id, label: 'Стены · ${k.labelRu}'),
        for (final k in FloorCoveringKind.values)
          (id: k.id, label: 'Пол · ${k.labelRu}'),
        (id: 'system', label: 'Потолок · система'),
      ];
  }
}

/// Kits for a layer dialog: exact layer matches first, then section-wide, then any.
List<FinishMountKit> kitsForLayer({
  required List<FinishMountKit> all,
  required String section,
  String? layerKindId,
}) {
  final kind = (layerKindId ?? '').trim();
  final exact = <FinishMountKit>[];
  final sectionWide = <FinishMountKit>[];
  final anySec = <FinishMountKit>[];
  for (final k in all) {
    final secOk = k.section == section || k.section == 'any';
    if (!secOk) continue;
    if (k.hasLayerKind) {
      if (kind.isNotEmpty && k.layerKind.trim() == kind) {
        exact.add(k);
      }
      continue;
    }
    if (k.section == section) {
      sectionWide.add(k);
    } else {
      anySec.add(k);
    }
  }
  return [...exact, ...sectionWide, ...anySec];
}
