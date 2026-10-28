import 'dart:convert';

import 'package:flutter/services.dart';

import 'documentation_model.dart';
import 'material_catalog.dart';
import 'product_aliases.dart';

double? _parsePriceTokenLocal(String s) {
  final cleaned = s.replaceAll(' ', '').replaceAll(',', '.');
  final m = RegExp(r'(\d+(?:\.\d{1,2})?)').firstMatch(cleaned);
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

class DocImportFormatProfile {
  DocImportFormatProfile(this.data);

  final Map<String, dynamic> data;

  String get id => data['id'] as String? ?? '';
  String get name => data['name'] as String? ?? id;

  Map<String, dynamic> get detect =>
      (data['detect'] as Map?)?.cast<String, dynamic>() ?? {};

  Map<String, List<String>> get columnHints {
    final raw = (data['columns'] as Map?)?.cast<String, dynamic>() ?? {};
    return raw.map(
      (k, v) => MapEntry(
        k,
        (v as List? ?? []).map((e) => e.toString().toLowerCase()).toList(),
      ),
    );
  }
}

List<DocImportFormatProfile>? _profileCache;

Future<List<DocImportFormatProfile>> loadDocImportFormatProfiles({bool force = false}) async {
  if (_profileCache != null && !force) return _profileCache!;
  final out = <DocImportFormatProfile>[];
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final paths = manifest
      .listAssets()
      .where((k) =>
          k.startsWith('assets/doc_import_templates/') &&
          k.endsWith('.json'))
      .toList()
    ..sort();
  for (final path in paths) {
    try {
      final raw = await rootBundle.loadString(path);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['id'] != null) out.add(DocImportFormatProfile(data));
    } catch (_) {}
  }
  _profileCache = out;
  return out;
}

int scoreDocFormatProfile({
  required String text,
  required List<List<String>> rows,
  required DocImportFormatProfile profile,
}) {
  final detect = profile.detect;
  var score = 0;
  final textLow = text.toLowerCase();

  for (final phrase in (detect['any_contains'] as List? ?? [])) {
    if (textLow.contains(phrase.toString().toLowerCase())) {
      score += (detect['weight_contains'] as num?)?.toInt() ?? 2;
    }
  }

  for (final phrase in (detect['all_contains'] as List? ?? [])) {
    if (textLow.contains(phrase.toString().toLowerCase())) {
      score += (detect['weight_all'] as num?)?.toInt() ?? 3;
    } else {
      return 0;
    }
  }

  if (rows.isNotEmpty) {
    final headerJoined = rows.take(5).map((r) => r.join(' ').toLowerCase()).join(' ');
    for (final phrase in (detect['any_contains'] as List? ?? [])) {
      if (headerJoined.contains(phrase.toString().toLowerCase())) {
        score += 1;
      }
    }
  }

  return score;
}

(DocImportFormatProfile? profile, int score) detectBestDocFormatProfile({
  required String text,
  required List<List<String>> rows,
  required List<DocImportFormatProfile> profiles,
}) {
  DocImportFormatProfile? best;
  var bestScore = 0;
  for (final p in profiles) {
    final s = scoreDocFormatProfile(text: text, rows: rows, profile: p);
    final minScore = (p.detect['min_score'] as num?)?.toInt() ?? 2;
    if (s >= minScore && s > bestScore) {
      bestScore = s;
      best = p;
    }
  }
  return (best, bestScore);
}

/// Detected column layout in a spreadsheet.
class DetectedColumnMap {
  DetectedColumnMap({
    required this.headerRowIndex,
    this.colKey,
    this.colCode,
    this.colName,
    this.colUnit,
    this.colPrice,
    this.colSection,
    this.confidence = 0,
  });

  final int headerRowIndex;
  final int? colKey;
  final int? colCode;
  final int? colName;
  final int? colUnit;
  final int? colPrice;
  final int? colSection;
  final double confidence;
}

int? _matchColumnIndex(List<String> header, List<String> hints) {
  for (var i = 0; i < header.length; i++) {
    final h = header[i].toLowerCase();
    for (final hint in hints) {
      if (h.contains(hint) || hint.contains(h)) return i;
    }
  }
  return null;
}

DetectedColumnMap detectColumnMap(
  List<List<String>> rows, {
  DocImportFormatProfile? profile,
}) {
  if (rows.isEmpty) {
    return DetectedColumnMap(headerRowIndex: -1);
  }

  DetectedColumnMap? best;
  var bestScore = 0.0;

  final hints = profile?.columnHints ?? const {
    'key': ['match_key', 'key', 'ключ'],
    'code': ['обосн', 'шифр', 'код', 'артикул'],
    'name': ['наимен', 'name', 'работ', 'номенклатур'],
    'unit': ['ед', 'unit', 'единица'],
    'price': ['расцен', 'цена за ед', 'price', 'цен'],
    'section': ['раздел', 'section', 'вид работ'],
  };

  for (var r = 0; r < rows.length && r < 45; r++) {
    final header = rows[r].map((c) => c.toLowerCase().trim()).toList();
    if (header.every((c) => c.isEmpty)) continue;

    final nameCol = _matchColumnIndex(header, hints['name'] ?? []);
    final priceCol = _matchColumnIndex(header, hints['price'] ?? []);
    if (nameCol == null || priceCol == null) continue;

    var score = 2.0;
    final unitCol = _matchColumnIndex(header, hints['unit'] ?? []);
    final codeCol = _matchColumnIndex(header, hints['code'] ?? []);
    final keyCol = _matchColumnIndex(header, hints['key'] ?? []);
    final sectionCol = _matchColumnIndex(header, hints['section'] ?? []);
    if (unitCol != null) score += 1;
    if (codeCol != null) score += 0.5;
    if (keyCol != null) score += 0.5;
    if (sectionCol != null) score += 0.5;

    // Penalize "сумма" mistaken as price column
    final priceHeader = header[priceCol];
    if (priceHeader.contains('сумм') || priceHeader.contains('стоим')) score -= 1.5;

    if (score > bestScore) {
      bestScore = score;
      best = DetectedColumnMap(
        headerRowIndex: r,
        colKey: keyCol,
        colCode: codeCol,
        colName: nameCol,
        colUnit: unitCol,
        colPrice: priceCol,
        colSection: sectionCol,
        confidence: score,
      );
    }
  }

  return best ?? DetectedColumnMap(headerRowIndex: -1);
}

List<ProjectPriceLine> parsePriceRowsWithColumnMap(
  List<List<String>> rows,
  DetectedColumnMap map,
) {
  if (map.headerRowIndex < 0 || map.colName == null || map.colPrice == null) {
    return [];
  }

  final out = <ProjectPriceLine>[];
  for (final row in rows.skip(map.headerRowIndex + 1)) {
    if (row.isEmpty) continue;
    final name = map.colName! < row.length ? row[map.colName!].trim() : '';
    if (name.length < 2) continue;
    final low = name.toLowerCase();
    if (['итого', 'всего', 'ндс', 'раздел', 'итог'].any(low.startsWith)) continue;

    final priceRaw = map.colPrice! < row.length ? row[map.colPrice!] : '';
    final price = _parsePriceTokenLocal(priceRaw);
    if (price == null || price <= 0) continue;

    var key = map.colKey != null && map.colKey! < row.length ? row[map.colKey!].trim() : '';
    if (key.isEmpty && map.colCode != null && map.colCode! < row.length) {
      key = row[map.colCode!].trim();
    }
    key = key.isEmpty
        ? guessMatchKeyForImport(
            name,
            section: map.colSection != null && map.colSection! < row.length
                ? row[map.colSection!].trim()
                : '',
          )
        : key;

    final unit = map.colUnit != null &&
            map.colUnit! < row.length &&
            row[map.colUnit!].trim().isNotEmpty
        ? row[map.colUnit!].trim()
        : 'шт';

    out.add(ProjectPriceLine(matchKey: key, name: name, unit: unit, unitPrice: price));
  }
  return out;
}

String guessMatchKeyForImport(String name, {String section = ''}) {
  final sec = section.toLowerCase();
  if (sec.contains('пол')) return 'finish_floor';
  if (sec.contains('стен')) return 'finish_wall';
  if (sec.contains('потол')) return 'finish_ceiling';
  final alias = matchProductAlias(name);
  if (alias != null) {
    return catalogByItemKey(alias.itemKey)?.calcMatchKey ?? alias.itemKey;
  }
  final low = name.toLowerCase();
  if (low.contains('пол') && (low.contains('м²') || low.contains('отдел'))) {
    return 'finish_floor';
  }
  if (low.contains('стен') && (low.contains('м²') || low.contains('отдел'))) {
    return 'finish_wall';
  }
  if (low.contains('потол') && (low.contains('м²') || low.contains('отдел'))) {
    return 'finish_ceiling';
  }
  if (low.contains('закуп') || low.contains('плит') || low.contains('кассет')) {
    return 'purchase';
  }
  for (final e in catalogEntries) {
    final dn = e.displayName.toLowerCase();
    final ck = e.calcMatchKey.toLowerCase();
    if (low.contains(dn) || low.contains(ck) || dn.contains(low)) {
      return e.calcMatchKey;
    }
  }
  return name;
}

class AdaptiveParseMeta {
  const AdaptiveParseMeta({
    this.formatId = '',
    this.formatName = '',
    this.formatScore = 0,
    this.unmatchedRows = const [],
  });

  final String formatId;
  final String formatName;
  final int formatScore;
  final List<String> unmatchedRows;
}

/// Adaptive price extraction with format detection metadata.
Future<(List<ProjectPriceLine> prices, AdaptiveParseMeta meta)> extractAdaptivePrices({
  required String text,
  required List<List<String>> tableRows,
}) async {
  if (tableRows.isEmpty) {
    return (<ProjectPriceLine>[], const AdaptiveParseMeta());
  }

  final profiles = await loadDocImportFormatProfiles();
  final (profile, score) = detectBestDocFormatProfile(
    text: text,
    rows: tableRows,
    profiles: profiles,
  );

  final columnMap = detectColumnMap(tableRows, profile: profile);
  var prices = parsePriceRowsWithColumnMap(tableRows, columnMap);
  final unmatched = <String>[];

  if (columnMap.headerRowIndex >= 0) {
    for (final row in tableRows.skip(columnMap.headerRowIndex + 1)) {
      if (row.isEmpty) continue;
      final name = columnMap.colName != null && columnMap.colName! < row.length
          ? row[columnMap.colName!].trim()
          : '';
      if (name.length < 2) continue;
      final priceRaw = columnMap.colPrice != null && columnMap.colPrice! < row.length
          ? row[columnMap.colPrice!]
          : '';
      final price = _parsePriceTokenLocal(priceRaw);
      if (price == null || price <= 0) {
        if (name.isNotEmpty && !['итого', 'всего'].any(name.toLowerCase().startsWith)) {
          unmatched.add(name);
        }
      } else if (!prices.any((p) => p.name == name)) {
        unmatched.add(name);
      }
    }
  }

  final meta = AdaptiveParseMeta(
    formatId: profile?.id ?? 'auto',
    formatName: profile?.name ?? 'Автоопределение',
    formatScore: score,
    unmatchedRows: unmatched.take(20).toList(),
  );

  return (prices, meta);
}
