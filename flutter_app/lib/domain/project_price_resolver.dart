import 'cost_calculator.dart';
import 'documentation_model.dart';
import 'work_rates_catalog.dart';
import 'work_rates_lookup.dart';

/// Standard finish section keys used in KS-2 pricing.
String? ks2SectionPriceKey(String section) => switch (section) {
      'Пол' => 'finish_floor',
      'Стены' => 'finish_wall',
      'Потолок' => 'finish_ceiling',
      _ => null,
    };

Map<String, ProjectPriceLine> projectPricesByKey(List<ProjectPriceLine> lines) {
  final map = <String, ProjectPriceLine>{};
  for (final line in lines) {
    if (line.matchKey.isEmpty || line.unitPrice <= 0) continue;
    map.putIfAbsent(line.matchKey, () => line);
  }
  return map;
}

double? _projectPriceForLine({
  required String name,
  required String section,
  required Map<String, ProjectPriceLine> byKey,
}) {
  final sectionKey = ks2SectionPriceKey(section);
  if (sectionKey != null) {
    final p = byKey[sectionKey];
    if (p != null && p.unitPrice > 0) return p.unitPrice;
  }
  if (name.contains('закупка')) {
    final p = byKey['purchase'];
    if (p != null && p.unitPrice > 0) return p.unitPrice;
  }
  final nameLow = name.toLowerCase();
  for (final e in byKey.entries) {
    final keyLow = e.key.toLowerCase();
    final labelLow = e.value.name.toLowerCase();
    if (keyLow.isNotEmpty &&
        (nameLow.contains(keyLow) || keyLow.contains(nameLow))) {
      return e.value.unitPrice;
    }
    if (labelLow.isNotEmpty &&
        (nameLow.contains(labelLow) || labelLow.contains(nameLow))) {
      return e.value.unitPrice;
    }
  }
  return null;
}

double? _supplierPriceForLine({
  required String name,
  required String section,
  Map<String, SupplierPrice>? prices,
}) {
  if (prices == null || prices.isEmpty) return null;
  final nameLow = name.toLowerCase();
  for (final e in prices.entries) {
    final keyLow = e.key.toLowerCase();
    if (nameLow.contains(keyLow) || keyLow.contains(nameLow)) {
      final p = e.value.unitPriceClient;
      return p > 0 ? p : null;
    }
  }
  final sectionKey = ks2SectionPriceKey(section);
  if (sectionKey != null && prices.containsKey(sectionKey)) {
    final p = prices[sectionKey]!.unitPriceClient;
    return p > 0 ? p : null;
  }
  if (name.contains('закупка') && prices.containsKey('purchase')) {
    final p = prices['purchase']!.unitPriceClient;
    return p > 0 ? p : null;
  }
  return null;
}

/// Resolve unit price for a KS-2 line:
/// project rates → work-rates catalog → supplier catalog.
///
/// [linkedItemKey]: optional purchase material from a finish layer — never use
/// section work rates (`finish_wall` / …); only the supplier row for that key.
double? resolveKs2UnitPrice({
  required String name,
  required String section,
  List<ProjectPriceLine>? projectPrices,
  Map<String, SupplierPrice>? supplierPrices,
  bool projectPricesOnly = false,
  List<WorkRateCategory>? workRatesCatalog,
  String? linkedItemKey,
}) {
  final link = linkedItemKey?.trim();
  if (link != null && link.isNotEmpty) {
    if (supplierPrices == null || supplierPrices.isEmpty) return null;
    final p = supplierPrices[link];
    final client = p?.unitPriceClient ?? 0;
    return client > 0 ? client : null;
  }

  final byKey = projectPricesByKey(projectPrices ?? []);
  if (byKey.isNotEmpty) {
    final p = _projectPriceForLine(name: name, section: section, byKey: byKey);
    if (p != null) return p;
    if (projectPricesOnly) return null;
  } else if (projectPricesOnly) {
    return null;
  }

  final cats = workRatesCatalog ?? WorkRatesCatalogStore.peek();
  if (cats.isNotEmpty) {
    final fromCatalog = catalogUnitPriceForLine(
      name: name,
      section: section,
      categories: cats,
    );
    if (fromCatalog != null && fromCatalog > 0) return fromCatalog;
  }

  return _supplierPriceForLine(name: name, section: section, prices: supplierPrices);
}

/// Resolve supplier price/SKU for finish sections (`finish_floor` / `finish_wall` / `finish_ceiling`).
/// Direct key first, then fuzzy match on catalog calc keys / product names.
SupplierPrice? resolveFinishSupplierPrice({
  required String sectionKey,
  Map<String, SupplierPrice>? prices,
}) {
  if (prices == null || prices.isEmpty) return null;
  final direct = prices[sectionKey];
  if (direct != null) return direct;

  final needles = switch (sectionKey) {
    'finish_floor' => const [
        'пол',
        'плитк',
        'ламинат',
        'стяжк',
        'floor',
        'tile',
        'screed',
        'паркет',
      ],
    'finish_wall' => const ['стен', 'wall', 'краск', 'штукатур', 'обои', 'шпакл'],
    'finish_ceiling' => const [
        'потол',
        'ceiling',
        'армстронг',
        'грильято',
        'плиты/кассеты',
      ],
    _ => const <String>[],
  };
  if (needles.isEmpty) return null;

  for (final e in prices.entries) {
    final hay = '${e.key} ${e.value.productName}'.toLowerCase();
    if (needles.any(hay.contains)) return e.value;
  }
  return null;
}

String resolveFinishSku({
  required String sectionKey,
  Map<String, SupplierPrice>? prices,
}) =>
    resolveFinishSupplierPrice(sectionKey: sectionKey, prices: prices)?.supplierSku.trim() ?? '';

