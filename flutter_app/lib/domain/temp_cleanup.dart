import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Prefixes / patterns of app-owned temp & cache files safe to delete.
bool _isVisotaTempName(String name) {
  final n = name.toLowerCase();
  return n.startsWith('visota_') ||
      n.startsWith('ceilingcalculator-') ||
      n.endsWith('_kit.json') ||
      n.endsWith('_prices.json') ||
      (n.contains('offline_') && n.endsWith('.json')) ||
      n.startsWith('ks2_') ||
      n.startsWith('ks3_') ||
      n.startsWith('vedomost_') ||
      n.startsWith('smeta_') ||
      n.startsWith('act_');
}

/// Delete one file if it exists; ignore errors.
Future<bool> deleteFileQuiet(String? path) async {
  if (path == null || path.isEmpty) return false;
  try {
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
      return true;
    }
  } catch (_) {}
  return false;
}

/// Purge app temp exports (share JSON, offline bundles, doc exports).
///
/// [olderThan]: only remove files older than this (Duration.zero = all matching).
/// [keepPaths]: absolute paths that must stay (e.g. pending OTA).
Future<int> purgeVisotaTempFiles({
  Duration olderThan = Duration.zero,
  Set<String> keepPaths = const {},
}) async {
  var deleted = 0;
  final keep = {
    for (final k in keepPaths) p.normalize(k).toLowerCase(),
  };
  final cutoff = DateTime.now().subtract(olderThan);

  Future<void> scan(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is! File) continue;
      final name = p.basename(ent.path);
      if (!_isVisotaTempName(name)) continue;
      final norm = p.normalize(ent.path).toLowerCase();
      if (keep.contains(norm)) continue;
      try {
        if (olderThan > Duration.zero) {
          final stat = await ent.stat();
          if (stat.modified.isAfter(cutoff)) continue;
        }
        await ent.delete();
        deleted++;
      } catch (_) {}
    }
  }

  try {
    await scan(await getTemporaryDirectory());
  } catch (_) {}
  try {
    // Some share_plus / exports land under cache.
    final support = await getApplicationSupportDirectory();
    await scan(Directory(p.join(support.path, 'cache')));
  } catch (_) {}
  return deleted;
}

/// Keep only [keepPath] inside app-support/updates; delete older APK/EXE.
Future<int> purgeOldUpdatePackages({String? keepPath}) async {
  var deleted = 0;
  try {
    final support = await getApplicationSupportDirectory();
    final updates = Directory(p.join(support.path, 'updates'));
    if (!await updates.exists()) return 0;
    final keep = keepPath == null ? null : p.normalize(keepPath).toLowerCase();
    await for (final ent in updates.list(followLinks: false)) {
      if (ent is! File) continue;
      final name = p.basename(ent.path).toLowerCase();
      if (!(name.endsWith('.apk') || name.endsWith('.exe'))) continue;
      final norm = p.normalize(ent.path).toLowerCase();
      if (keep != null && norm == keep) continue;
      try {
        await ent.delete();
        deleted++;
      } catch (_) {}
    }
  } catch (_) {}
  return deleted;
}

/// After replacing an archive/local blob: drop sibling files for same id
/// with a different extension, and orphaned files not listed in [keepRelative].
Future<int> purgeOrphanArchiveFiles({
  required String categoryId,
  required Set<String> keepRelativePaths,
}) async {
  var deleted = 0;
  try {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'director_archive', categoryId));
    if (!await dir.exists()) return 0;
    final keep = {
      for (final r in keepRelativePaths)
        p.normalize(p.join(root.path, r)).toLowerCase(),
    };
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is! File) continue;
      final norm = p.normalize(ent.path).toLowerCase();
      if (keep.contains(norm)) continue;
      try {
        await ent.delete();
        deleted++;
      } catch (_) {}
    }
  } catch (_) {}
  return deleted;
}

/// Run after a successful sync / share / OTA download.
Future<int> cleanupAfterTransfer({
  String? keepUpdatePath,
  bool purgeTemp = true,
  bool purgeUpdates = true,
}) async {
  var n = 0;
  if (purgeTemp) {
    n += await purgeVisotaTempFiles(
      keepPaths: {
        if (keepUpdatePath != null) keepUpdatePath,
      },
    );
  }
  if (purgeUpdates) {
    n += await purgeOldUpdatePackages(keepPath: keepUpdatePath);
  }
  return n;
}
