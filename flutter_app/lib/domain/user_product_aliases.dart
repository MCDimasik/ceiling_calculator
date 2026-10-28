import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'material_catalog.dart';
import 'product_aliases.dart';

const _prefAliases = 'user_product_aliases_v1';
const _prefHiddenPrefix = 'supplier_hidden_item_keys_v1_';

String normalizeProductLabel(String s) {
  return s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll('×', 'x')
      .replaceAll('х', 'x')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Stable custom key for unmatched receipt rows.
String customItemKeyForLabel(String rawName) {
  final n = normalizeProductLabel(rawName);
  var h = 0;
  for (final c in n.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return 'rx_$h';
}

class UserProductAliasStore {
  UserProductAliasStore._(this._map);
  final Map<String, String> _map; // normalized label → itemKey

  static Future<UserProductAliasStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefAliases);
    final map = <String, String>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            final k = normalizeProductLabel('${e.key}');
            final v = '${e.value}'.trim();
            if (k.isNotEmpty && v.isNotEmpty) map[k] = v;
          }
        }
      } catch (_) {}
    }
    return UserProductAliasStore._(map);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAliases, jsonEncode(_map));
  }

  String? itemKeyForLabel(String rawName) {
    final k = normalizeProductLabel(rawName);
    if (k.isEmpty) return null;
    return _map[k];
  }

  AliasHit? match(String rawName) {
    final key = itemKeyForLabel(rawName);
    if (key == null) return null;
    final entry = catalogByItemKey(key);
    return AliasHit(
      itemKey: key,
      productName: entry?.displayName,
      receiptUnit: entry == null ? null : defaultReceiptUnit(key),
      unitsPerPack: entry == null ? null : defaultUnitsPerPack(key).toDouble(),
    );
  }

  /// Point [labels] at [itemKey] (overwrites previous mapping for those labels).
  Future<void> bindLabels(Iterable<String> labels, String itemKey) async {
    for (final label in labels) {
      final k = normalizeProductLabel(label);
      if (k.isEmpty) continue;
      _map[k] = itemKey;
    }
    await save();
  }

  Map<String, String> get snapshot => Map.unmodifiable(_map);
}

Future<Set<String>> loadHiddenItemKeys(int supplierId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getStringList('$_prefHiddenPrefix$supplierId') ?? const [];
  return raw.toSet();
}

Future<void> hideItemKeys(int supplierId, Iterable<String> keys) async {
  final prefs = await SharedPreferences.getInstance();
  final set = await loadHiddenItemKeys(supplierId);
  set.addAll(keys.where((k) => k.trim().isNotEmpty));
  await prefs.setStringList('$_prefHiddenPrefix$supplierId', set.toList()..sort());
}

Future<void> unhideItemKey(int supplierId, String key) async {
  final prefs = await SharedPreferences.getInstance();
  final set = await loadHiddenItemKeys(supplierId)..remove(key);
  await prefs.setStringList('$_prefHiddenPrefix$supplierId', set.toList()..sort());
}
