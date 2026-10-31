import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_revisions.dart';
import 'temp_cleanup.dart';

const _prefsKey = 'director_archive_local_v2';

/// Allowed office / document extensions for director archive.
const kDirectorArchiveAllowedExt = {
  '.pdf',
  '.doc',
  '.docx',
  '.xls',
  '.xlsx',
  '.odt',
  '.ods',
  '.rtf',
  '.txt',
  '.csv',
};

class DirectorArchiveFile {
  DirectorArchiveFile({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.relativePath,
    required this.updatedAt,
    this.serverId,
    this.contentType,
    this.sizeBytes = 0,
  });

  final String id;
  final String categoryId;
  String name;
  String relativePath;
  DateTime updatedAt;
  int? serverId;
  String? contentType;
  int sizeBytes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category_id': categoryId,
        'name': name,
        'relative_path': relativePath,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        if (serverId != null) 'server_id': serverId,
        if (contentType != null) 'content_type': contentType,
        'size_bytes': sizeBytes,
      };

  factory DirectorArchiveFile.fromJson(Map<String, dynamic> j) =>
      DirectorArchiveFile(
        id: (j['id'] as String?)?.trim() ?? _newId(),
        categoryId: (j['category_id'] as String?)?.trim() ?? '',
        name: (j['name'] as String?)?.trim() ?? 'file',
        relativePath: (j['relative_path'] as String?)?.trim() ?? '',
        updatedAt: DateTime.tryParse('${j['updated_at']}')?.toUtc() ??
            DateTime.now().toUtc(),
        serverId: (j['server_id'] as num?)?.toInt(),
        contentType: j['content_type'] as String?,
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
      );
}

class DirectorArchiveCategory {
  DirectorArchiveCategory({
    required this.id,
    required this.title,
    this.note = '',
    DateTime? updatedAt,
    List<DirectorArchiveFile>? files,
  })  : updatedAt = (updatedAt ?? DateTime.now()).toUtc(),
        files = files ?? [];

  final String id;
  String title;
  String note;
  DateTime updatedAt;
  final List<DirectorArchiveFile> files;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'files': [for (final f in files) f.toJson()],
      };

  factory DirectorArchiveCategory.fromJson(Map<String, dynamic> j) {
    final filesRaw = j['files'];
    return DirectorArchiveCategory(
      id: (j['id'] as String?)?.trim() ?? _newId(),
      title: (j['title'] as String?)?.trim() ?? 'Категория',
      note: (j['note'] as String?)?.trim() ?? '',
      updatedAt: DateTime.tryParse('${j['updated_at']}')?.toUtc(),
      files: [
        if (filesRaw is List)
          for (final e in filesRaw)
            if (e is Map)
              DirectorArchiveFile.fromJson(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

String _newId() {
  final r = Random();
  return 'a_${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(1 << 20)}';
}

Future<Directory> _archiveRoot() async {
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(root.path, 'director_archive'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Local director archive (categories + PDF/Office files) with UTC clocks.
class DirectorArchiveStore {
  DirectorArchiveStore._();

  static List<DirectorArchiveCategory>? _cache;

  static Future<List<DirectorArchiveCategory>> load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final cats = <DirectorArchiveCategory>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final e in list) {
          if (e is! Map) continue;
          cats.add(
            DirectorArchiveCategory.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      } catch (_) {}
    }
    // Migrate v1 prefs (categories without files).
    if (cats.isEmpty) {
      final legacy = prefs.getString('director_archive_local_v1');
      if (legacy != null && legacy.isNotEmpty) {
        try {
          final list = jsonDecode(legacy) as List<dynamic>;
          for (final e in list) {
            if (e is! Map) continue;
            final m = Map<String, dynamic>.from(e);
            cats.add(
              DirectorArchiveCategory(
                id: (m['id'] as String?) ?? _newId(),
                title: (m['title'] as String?) ?? 'Категория',
                note: (m['note'] as String?) ?? '',
              ),
            );
          }
        } catch (_) {}
      }
    }
    cats.removeWhere(
      (c) =>
          c.id == 'certs' ||
          c.id == 'schemes' ||
          c.title == 'Сертификаты' ||
          c.title == 'Схемы',
    );
    if (cats.isEmpty) {
      cats.addAll([
        DirectorArchiveCategory(id: 'ks', title: 'КС-2 / КС-3'),
        DirectorArchiveCategory(id: 'acts', title: 'Акты'),
      ]);
    }
    _cache = cats;
    await _persist();
    return cats;
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final cats = _cache ?? [];
    await prefs.setString(
      _prefsKey,
      jsonEncode([for (final c in cats) c.toJson()]),
    );
    await SyncRevisions.touch(SyncRevisions.archiveKey());
  }

  static Future<DirectorArchiveCategory> addCategory(String title) async {
    final cats = await load();
    final cat = DirectorArchiveCategory(id: _newId(), title: title.trim());
    cats.add(cat);
    await _persist();
    return cat;
  }

  static Future<void> updateCategory(DirectorArchiveCategory cat) async {
    await load();
    cat.updatedAt = DateTime.now().toUtc();
    await _persist();
  }

  static Future<void> deleteCategory(String id) async {
    final cats = await load();
    final idx = cats.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    final cat = cats.removeAt(idx);
    for (final f in cat.files) {
      await _deleteLocalFile(f);
    }
    await _persist();
  }

  static Future<DirectorArchiveFile?> addFileFromPath({
    required String categoryId,
    required String sourcePath,
    String? displayName,
  }) async {
    final cats = await load();
    DirectorArchiveCategory? cat;
    for (final c in cats) {
      if (c.id == categoryId) {
        cat = c;
        break;
      }
    }
    if (cat == null) return null;
    final ext = p.extension(sourcePath).toLowerCase();
    if (!kDirectorArchiveAllowedExt.contains(ext)) {
      throw StateError(
        'Допустимы: ${kDirectorArchiveAllowedExt.join(", ")}',
      );
    }
    final root = await _archiveRoot();
    final catDir = Directory(p.join(root.path, categoryId));
    if (!await catDir.exists()) await catDir.create(recursive: true);
    final id = _newId();
    final name = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : p.basename(sourcePath);
    final destName = '$id$ext';
    final dest = File(p.join(catDir.path, destName));
    await File(sourcePath).copy(dest.path);
    final rel = p.join('director_archive', categoryId, destName);
    final entry = DirectorArchiveFile(
      id: id,
      categoryId: categoryId,
      name: name,
      relativePath: rel.replaceAll('\\', '/'),
      updatedAt: DateTime.now().toUtc(),
      sizeBytes: await dest.length(),
      contentType: _guessContentType(ext),
    );
    cat.files.add(entry);
    cat.updatedAt = entry.updatedAt;
    await _persist();
    await purgeOrphanArchiveFiles(
      categoryId: categoryId,
      keepRelativePaths: {for (final f in cat.files) f.relativePath},
    );
    return entry;
  }

  static Future<String> absolutePath(DirectorArchiveFile file) async {
    if (p.isAbsolute(file.relativePath) &&
        File(file.relativePath).existsSync()) {
      return file.relativePath;
    }
    final root = await getApplicationDocumentsDirectory();
    return p.join(root.path, file.relativePath);
  }

  static Future<void> deleteFile(String categoryId, String fileId) async {
    final cats = await load();
    DirectorArchiveCategory? cat;
    for (final c in cats) {
      if (c.id == categoryId) {
        cat = c;
        break;
      }
    }
    if (cat == null) return;
    final idx = cat.files.indexWhere((f) => f.id == fileId);
    if (idx < 0) return;
    final f = cat.files.removeAt(idx);
    await _deleteLocalFile(f);
    cat.updatedAt = DateTime.now().toUtc();
    await _persist();
  }

  static Future<void> _deleteLocalFile(DirectorArchiveFile f) async {
    try {
      final path = await absolutePath(f);
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static String _guessContentType(String ext) => switch (ext) {
        '.pdf' => 'application/pdf',
        '.doc' => 'application/msword',
        '.docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        '.xls' => 'application/vnd.ms-excel',
        '.xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        '.csv' => 'text/csv',
        '.txt' => 'text/plain',
        _ => 'application/octet-stream',
      };

  /// Meta for account snapshot (without binary bytes).
  static Future<List<Map<String, dynamic>>> categoriesMeta() async {
    final cats = await load();
    return [
      for (final c in cats)
        {
          'id': c.id,
          'title': c.title,
          'note': c.note,
          'updated_at': c.updatedAt.toUtc().toIso8601String(),
          'files': [
            for (final f in c.files)
              {
                'id': f.id,
                'name': f.name,
                'updated_at': f.updatedAt.toUtc().toIso8601String(),
                'size_bytes': f.sizeBytes,
                'content_type': f.contentType,
              },
          ],
        },
    ];
  }

  static Future<void> mergeCategoriesMeta(List<dynamic> remote) async {
    final cats = await load();
    final byId = {for (final c in cats) c.id: c};
    for (final raw in remote) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final id = (m['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) continue;
      final remoteAt = SyncRevisions.parse(m['updated_at']);
      final existing = byId[id];
      if (existing == null) {
        // Meta only — binary files arrive via /archive/files sync.
        final created = DirectorArchiveCategory(
          id: id,
          title: (m['title'] as String?) ?? 'Категория',
          note: (m['note'] as String?) ?? '',
          updatedAt: remoteAt,
        );
        byId[id] = created;
        cats.add(created);
        continue;
      }
      if (SyncRevisions.remoteWins(existing.updatedAt, remoteAt)) {
        existing.title = (m['title'] as String?)?.trim() ?? existing.title;
        existing.note = (m['note'] as String?)?.trim() ?? existing.note;
        if (remoteAt != null) existing.updatedAt = remoteAt;
      }
    }
    _cache = cats;
    await _persist();
  }

  static void clearCache() => _cache = null;

  /// Replace entire local catalog (after cloud pull merge).
  static Future<void> replaceAll(List<DirectorArchiveCategory> cats) async {
    _cache = cats;
    await _persist();
  }
}
