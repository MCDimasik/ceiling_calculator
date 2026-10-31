import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// UTC revision clocks for last-write-wins sync (device ↔ device / future cloud).
///
/// Clocks are always stored in UTC so timezone differences don't matter —
/// devices don't need the same local timezone, only roughly correct wall clocks.
class SyncRevisions {
  SyncRevisions._();

  static const _prefsKey = 'sync_entity_revisions_utc_v1';

  /// Fired after a local entity clock bump (for debounced cloud push).
  static void Function(String key)? onEntityTouched;

  static String projectKey(String name) =>
      'project:${name.trim().toLowerCase()}';
  static String workRatesKey() => 'work_rates';
  static String kitKey(String idOrName) =>
      'kit:${idOrName.trim().toLowerCase()}';
  static String supplierKey(String name) =>
      'supplier:${name.trim().toLowerCase()}';
  static String archiveKey() => 'director_archive';
  static String accountSnapshotKey() => 'account_snapshot';

  static Future<Map<String, DateTime>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return {};
      final out = <String, DateTime>{};
      for (final e in j.entries) {
        final dt = DateTime.tryParse('${e.value}');
        if (dt != null) out['${e.key}'] = dt.toUtc();
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveMap(Map<String, DateTime> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        for (final e in map.entries) e.key: e.value.toUtc().toIso8601String(),
      }),
    );
  }

  static Future<DateTime?> get(String key) async {
    final map = await _loadMap();
    return map[key];
  }

  /// Bump revision to now (UTC), or [at] if provided.
  static Future<DateTime> touch(String key, {DateTime? at}) async {
    final map = await _loadMap();
    final next = (at ?? DateTime.now()).toUtc();
    final prev = map[key];
    late final DateTime stored;
    if (prev != null && !next.isAfter(prev)) {
      // Ensure monotonic bump on rapid edits.
      stored = prev.add(const Duration(milliseconds: 1));
      map[key] = stored;
      await _saveMap(map);
    } else {
      stored = next;
      map[key] = next;
      await _saveMap(map);
    }
    try {
      onEntityTouched?.call(key);
    } catch (_) {}
    return stored;
  }

  /// Set clock exactly (e.g. after accepting a newer remote).
  static Future<void> set(String key, DateTime at) async {
    final map = await _loadMap();
    map[key] = at.toUtc();
    await _saveMap(map);
  }

  /// true if [remote] should replace local (remote ≥ local UTC, or no local).
  /// Equal clocks re-apply (idempotent merge / same-device round-trip).
  static bool remoteWins(DateTime? local, DateTime? remote) {
    if (remote == null) return false;
    if (local == null) return true;
    return !remote.toUtc().isBefore(local.toUtc());
  }

  static DateTime? parse(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toUtc();
  }
}
