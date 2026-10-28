import 'documentation_model.dart';
import 'project_price_resolver.dart';
import 'work_rates_catalog.dart';

/// Flat catalog item with its category for pickers / matching.
class WorkRateHit {
  const WorkRateHit({
    required this.category,
    required this.item,
    this.sectionRelevant = true,
    this.rankScore = 0,
  });

  final WorkRateCategory category;
  final WorkRateItem item;
  final bool sectionRelevant;
  final int rankScore;
}

/// Normalize section / domain hint to `finish_floor` / `finish_wall` / `finish_ceiling`.
String normalizeWorkRateSection(String section) {
  final s = section.trim().toLowerCase();
  if (s.isEmpty) return '';
  if (s == 'floor' || s == 'пол' || s.contains('floor') || s == 'finish_floor') {
    return 'finish_floor';
  }
  if (s == 'walls' ||
      s == 'wall' ||
      s == 'стен' ||
      s.contains('wall') ||
      s == 'finish_wall') {
    return 'finish_wall';
  }
  if (s == 'ceiling' ||
      s == 'потол' ||
      s.contains('ceiling') ||
      s == 'finish_ceiling') {
    return 'finish_ceiling';
  }
  return ks2SectionPriceKey(section) ?? '';
}

List<String> workRateSectionNeedles(String section) {
  return switch (normalizeWorkRateSection(section)) {
    'finish_floor' => const [
        'пол',
        'стяжк',
        'плитк',
        'ламинат',
        'паркет',
        'линолеум',
        'наполь',
        'screed',
        'floor',
      ],
    'finish_wall' => const [
        'стен',
        'штукатур',
        'шпакл',
        'обои',
        'краск',
        'маляр',
        'грунт',
        'wall',
        'plaster',
        'paint',
      ],
    'finish_ceiling' => const [
        'потол',
        'армстронг',
        'грильято',
        'реечн',
        'натяж',
        'ceiling',
      ],
    _ => const <String>[],
  };
}

bool workRateHitMatchesSection(WorkRateHit hit, String section) {
  final needles = workRateSectionNeedles(section);
  if (needles.isEmpty) return true;
  final hay =
      '${hit.item.name} ${hit.item.matchKey} ${hit.category.name}'.toLowerCase();
  return needles.any(hay.contains);
}

/// Ranked flat list for pickers: section-relevant first.
List<WorkRateHit> rankWorkRatesForSection(
  List<WorkRateCategory> categories, {
  String section = '',
}) {
  final needles = workRateSectionNeedles(section);
  final out = <WorkRateHit>[];
  for (final c in categories) {
    for (final item in c.items) {
      if (item.unitPrice <= 0 && item.name.trim().isEmpty) continue;
      final hay = '${item.name} ${item.matchKey} ${c.name}'.toLowerCase();
      final relevant =
          needles.isEmpty || needles.any(hay.contains);
      var score = relevant ? 100 : 0;
      if (relevant) score += item.name.length.clamp(0, 40);
      out.add(
        WorkRateHit(
          category: c,
          item: item,
          sectionRelevant: relevant || needles.isEmpty,
          rankScore: score,
        ),
      );
    }
  }
  out.sort((a, b) {
    final byRel = (b.sectionRelevant ? 1 : 0) - (a.sectionRelevant ? 1 : 0);
    if (byRel != 0) return byRel;
    return b.rankScore.compareTo(a.rankScore);
  });
  return out;
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// All priced items across categories.
List<WorkRateHit> flattenWorkRates(List<WorkRateCategory> categories) {
  final out = <WorkRateHit>[];
  for (final c in categories) {
    for (final item in c.items) {
      if (item.unitPrice > 0 || item.name.trim().isNotEmpty) {
        out.add(WorkRateHit(category: c, item: item));
      }
    }
  }
  return out;
}

/// Best catalog match for a estimate/vedomost line. Returns null if nothing useful.
/// Prefer longer / more specific name overlaps; our display name stays external.
WorkRateItem? matchWorkRateItem({
  required String name,
  String section = '',
  required List<WorkRateCategory> categories,
}) {
  final nameLow = _norm(name);
  if (nameLow.isEmpty) return null;

  final sectionNeedles = workRateSectionNeedles(section);

  WorkRateItem? best;
  var bestScore = 0;

  for (final hit in flattenWorkRates(categories)) {
    final item = hit.item;
    if (item.unitPrice <= 0) continue;
    final itemLow = _norm(item.name);
    final keyLow = _norm(item.matchKey);
    var score = 0;

    if (itemLow.isNotEmpty) {
      if (nameLow == itemLow) {
        score = 1000 + itemLow.length;
      } else if (nameLow.contains(itemLow) || itemLow.contains(nameLow)) {
        score = 100 + itemLow.length.clamp(0, 80);
      }
    }
    if (keyLow.isNotEmpty &&
        (nameLow.contains(keyLow) || keyLow.contains(nameLow))) {
      score = score < 50 ? 50 + keyLow.length : score;
    }
    if (sectionNeedles.isNotEmpty) {
      final hay = '$itemLow ${hit.category.name}'.toLowerCase();
      if (sectionNeedles.any(hay.contains)) {
        score += 15;
      }
    }
    if (score > bestScore) {
      bestScore = score;
      best = item;
    }
  }

  return bestScore >= 50 ? best : null;
}

double? catalogUnitPriceForLine({
  required String name,
  String section = '',
  required List<WorkRateCategory> categories,
}) =>
    matchWorkRateItem(name: name, section: section, categories: categories)
        ?.unitPrice;

/// Apply catalog prices onto project lines without renaming our labels/keys.
int applyCatalogPricesToProjectLines(
  List<ProjectPriceLine> lines,
  List<WorkRateCategory> categories, {
  bool onlyEmpty = true,
}) {
  var n = 0;
  for (final line in lines) {
    if (onlyEmpty && line.unitPrice > 0) continue;
    final hit = matchWorkRateItem(
      name: line.name.isNotEmpty ? line.name : line.matchKey,
      categories: categories,
    );
    if (hit == null || hit.unitPrice <= 0) continue;
    line.unitPrice = hit.unitPrice;
    if (line.unit.trim().isEmpty) line.unit = hit.unit;
    n++;
  }
  return n;
}

/// Build a project price line keeping our key/name; price from catalog item.
ProjectPriceLine projectLineFromCatalog({
  required String matchKey,
  required String name,
  required WorkRateItem catalogItem,
  String? unit,
}) {
  return ProjectPriceLine(
    matchKey: matchKey,
    name: name.isNotEmpty ? name : catalogItem.name,
    unit: (unit != null && unit.trim().isNotEmpty)
        ? unit
        : (catalogItem.unit.isNotEmpty ? catalogItem.unit : 'м²'),
    unitPrice: catalogItem.unitPrice,
  );
}
