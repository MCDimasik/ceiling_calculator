import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/project_repository.dart';
import '../data/supplier_repository.dart';
import 'ceiling_sync_client.dart';
import 'director_archive_store.dart';
import 'offline_device_sync.dart';
import 'sync_revisions.dart';
import 'temp_cleanup.dart';
import 'transfer_activity.dart';

/// Seamless account backup ↔ server (not inbox offers).
///
/// After login / reinstall: pull snapshot → LWW merge → push.
/// Local edits schedule a debounced push; orphan temps are purged after sync.
class AccountCloudSyncController extends ChangeNotifier {
  AccountCloudSyncController({
    required this.projects,
    required this.suppliers,
    required this.sync,
    required this.offlineSync,
    this.transfers,
  });

  final ProjectRepository projects;
  final SupplierRepository suppliers;
  final CeilingSyncController sync;
  final OfflineDeviceSyncController offlineSync;
  final TransferActivityController? transfers;

  static const debounceDelay = Duration(seconds: 45);
  static const periodicInterval = Duration(minutes: 15);

  bool busy = false;
  String? lastStatusRu;
  String? lastError;
  DateTime? lastSyncAt;
  Timer? _debounce;
  Timer? _periodic;
  var _hookBound = false;

  String get statusHintRu {
    if (!sync.isSignedIn) {
      return 'Войдите в облако — тогда данные поедут на сервер';
    }
    if (busy) return lastStatusRu ?? 'Синхронизация…';
    if (lastError != null) return lastError!;
    if (lastSyncAt != null) {
      final t = lastSyncAt!.toLocal();
      return 'Аккаунт синхронизирован '
          '${t.day.toString().padLeft(2, '0')}.'
          '${t.month.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    }
    return 'Готов к бесшовной синхронизации с сервером';
  }

  /// Wire revision bumps → debounced sync + periodic timer.
  void startAutoSync() {
    if (!_hookBound) {
      _hookBound = true;
      SyncRevisions.onEntityTouched = _onEntityTouched;
    }
    _periodic?.cancel();
    _periodic = Timer.periodic(periodicInterval, (_) {
      if (sync.isSignedIn && !busy) {
        unawaited(syncNow());
      }
    });
  }

  void disposeAutoSync() {
    _debounce?.cancel();
    _periodic?.cancel();
    if (_hookBound && SyncRevisions.onEntityTouched == _onEntityTouched) {
      SyncRevisions.onEntityTouched = null;
      _hookBound = false;
    }
  }

  void _onEntityTouched(String key) {
    if (key == SyncRevisions.accountSnapshotKey()) return;
    if (!sync.isSignedIn || busy) return;
    scheduleDebouncedSync();
  }

  /// After local edits: wait [debounceDelay], then pull+push.
  void scheduleDebouncedSync() {
    if (!sync.isSignedIn) return;
    _debounce?.cancel();
    lastStatusRu = 'Изменения… синк через ${debounceDelay.inSeconds} с';
    notifyListeners();
    _debounce = Timer(debounceDelay, () {
      unawaited(syncNow());
    });
  }

  /// Pull remote → LWW apply → push local (and archive files).
  Future<String?> syncNow({bool pullFirst = true}) async {
    if (!sync.isSignedIn) {
      return 'Сначала войдите в облако (Профиль)';
    }
    if (busy) return 'Уже выполняется';
    busy = true;
    lastError = null;
    lastStatusRu = 'Синхронизация аккаунта…';
    final token = transfers?.begin(
      direction: pullFirst
          ? TransferDirection.bidirectional
          : TransferDirection.uploading,
      titleRu: 'Синхронизация аккаунта',
      detailRu: pullFirst ? 'Сверка с сервером…' : 'Отправка…',
    );
    notifyListeners();
    try {
      if (pullFirst) {
        lastStatusRu = 'Загрузка с сервера…';
        transfers?.update(
          token: token,
          direction: TransferDirection.downloading,
          detailRu: 'Входящие данные…',
        );
        notifyListeners();
        await _pullSnapshot();
        await _pullArchiveFiles();
      }

      lastStatusRu = 'Отправка на сервер…';
      transfers?.update(
        token: token,
        direction: TransferDirection.uploading,
        detailRu: 'Исходящие данные…',
        progress: pullFirst ? 0.55 : 0.2,
      );
      notifyListeners();
      await _pushSnapshot();
      transfers?.setProgress(0.8, token: token);
      await _pushArchiveFiles();
      await _purgeArchiveOrphans();

      // Drop share/export temps left after transfer.
      await cleanupAfterTransfer(purgeUpdates: false);

      lastSyncAt = DateTime.now().toUtc();
      lastStatusRu = 'Готово';
      transfers?.update(
        token: token,
        detailRu: 'Готово',
        progress: 1,
      );
      await SyncRevisions.touch(SyncRevisions.accountSnapshotKey());
      notifyListeners();
      return null;
    } catch (e) {
      lastError = e.toString();
      lastStatusRu = 'Ошибка';
      transfers?.update(token: token, detailRu: 'Ошибка: $e');
      notifyListeners();
      return lastError;
    } finally {
      busy = false;
      notifyListeners();
      // Brief "готово" before the airy card fades (unless already dismissed).
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        transfers?.end(token: token);
      });
    }
  }

  Future<void> _pullSnapshot() async {
    final remote = await sync.client.getAccountSnapshot();
    if (remote == null) return;
    final raw = remote['payload_json'] as String? ?? '{}';
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    final bundle = Map<String, dynamic>.from(decoded);
    if (bundle['projects'] is! List) return;
    bundle['kind'] = 'offline_device_bundle';
    final note = await offlineSync.applyBundle(bundle);
    final arch = bundle['archive_categories'];
    if (arch is List) {
      await DirectorArchiveStore.mergeCategoriesMeta(arch);
    }
    lastStatusRu = 'С сервера: $note';
  }

  Future<void> _pushSnapshot() async {
    final bundle = await offlineSync.buildBundle();
    bundle['kind'] = 'account_snapshot';
    bundle['archive_categories'] =
        await DirectorArchiveStore.categoriesMeta();
    final stamp = DateTime.now().toUtc();
    bundle['cloud_updated_at'] = stamp.toIso8601String();
    await sync.client.putAccountSnapshot(
      payloadJson: jsonEncode(bundle),
      updatedAt: stamp,
    );
  }

  Future<void> _pushArchiveFiles() async {
    final cats = await DirectorArchiveStore.load();
    var changed = false;
    for (final cat in cats) {
      for (final f in cat.files) {
        final path = await DirectorArchiveStore.absolutePath(f);
        final file = File(path);
        if (!await file.exists()) continue;
        try {
          final bytes = await file.readAsBytes();
          final out = await sync.client.uploadArchiveFile(
            categoryClientId: cat.id,
            clientId: f.id,
            displayName: f.name,
            bytes: bytes,
            filename: p.basename(path),
          );
          final sid = (out['id'] as num?)?.toInt();
          if (sid != null && f.serverId != sid) {
            f.serverId = sid;
            changed = true;
          }
        } catch (_) {}
      }
    }
    if (changed) await DirectorArchiveStore.replaceAll(cats);
  }

  Future<void> _purgeArchiveOrphans() async {
    final cats = await DirectorArchiveStore.load();
    for (final cat in cats) {
      await purgeOrphanArchiveFiles(
        categoryId: cat.id,
        keepRelativePaths: {
          for (final f in cat.files) f.relativePath,
        },
      );
    }
  }

  Future<void> _pullArchiveFiles() async {
    List<Map<String, dynamic>> remote;
    try {
      remote = await sync.client.listArchiveFiles();
    } catch (_) {
      return;
    }
    final cats = await DirectorArchiveStore.load();
    final byFileId = <String, DirectorArchiveFile>{
      for (final c in cats)
        for (final f in c.files) f.id: f,
    };
    final root = await getApplicationDocumentsDirectory();
    var changed = false;

    for (final m in remote) {
      final clientId = (m['client_id'] as String?)?.trim() ?? '';
      final catId = (m['category_client_id'] as String?)?.trim() ?? '';
      final serverId = (m['id'] as num?)?.toInt();
      final name = (m['display_name'] as String?)?.trim() ?? 'file';
      if (clientId.isEmpty || catId.isEmpty || serverId == null) continue;

      DirectorArchiveCategory? cat;
      for (final c in cats) {
        if (c.id == catId) {
          cat = c;
          break;
        }
      }
      if (cat == null) {
        cat = DirectorArchiveCategory(id: catId, title: 'Архив');
        cats.add(cat);
        changed = true;
      }

      final existing = byFileId[clientId];
      final remoteAt = SyncRevisions.parse(m['updated_at']);
      if (existing != null) {
        final localPath = await DirectorArchiveStore.absolutePath(existing);
        if (File(localPath).existsSync() &&
            !SyncRevisions.remoteWins(existing.updatedAt, remoteAt)) {
          continue;
        }
      }

      try {
        // Drop previous local blob for this id (other extension / stale path).
        if (existing != null) {
          final oldPath = await DirectorArchiveStore.absolutePath(existing);
          if (File(oldPath).existsSync()) {
            await deleteFileQuiet(oldPath);
          }
        }
        final bytes = await sync.client.downloadArchiveFile(serverId);
        final ext = p.extension(name).isEmpty ? '.bin' : p.extension(name);
        final dir = Directory(p.join(root.path, 'director_archive', catId));
        if (!await dir.exists()) await dir.create(recursive: true);
        final destName = '$clientId$ext';
        final dest = File(p.join(dir.path, destName));
        await dest.writeAsBytes(bytes, flush: true);
        final rel =
            p.join('director_archive', catId, destName).replaceAll('\\', '/');
        if (existing != null) {
          existing.name = name;
          existing.relativePath = rel;
          existing.serverId = serverId;
          existing.sizeBytes = bytes.length;
          if (remoteAt != null) existing.updatedAt = remoteAt;
        } else {
          final entry = DirectorArchiveFile(
            id: clientId,
            categoryId: catId,
            name: name,
            relativePath: rel,
            updatedAt: remoteAt ?? DateTime.now().toUtc(),
            serverId: serverId,
            sizeBytes: bytes.length,
          );
          cat.files.add(entry);
          byFileId[clientId] = entry;
        }
        changed = true;
      } catch (_) {}
    }
    if (changed) await DirectorArchiveStore.replaceAll(cats);
  }
}
