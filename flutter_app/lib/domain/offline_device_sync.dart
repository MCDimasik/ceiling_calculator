import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/project_repository.dart';
import '../data/supplier_repository.dart';
import 'finish_material_links.dart';
import 'local_user_role.dart';
import 'prices_share.dart';
import 'sync_revisions.dart';
import 'temp_cleanup.dart';
import 'transfer_activity.dart';
import 'work_rates_catalog.dart';

const _prefsEnabled = 'offline_device_sync_enabled_v1';
const _prefsDeviceId = 'offline_device_sync_device_id_v1';
const _prefsDeviceName = 'offline_device_sync_device_name_v1';
const _prefsPairCode = 'offline_device_sync_pair_code_v1';
const _prefsLastSync = 'offline_device_sync_last_at_v1';
const _prefsLastPeer = 'offline_device_sync_last_peer_v1';

/// TCP port for peer HTTP API (same Wi‑Fi / hotspot).
const kOfflineSyncHttpPort = 18765;

/// UDP port for LAN discovery beacons.
const kOfflineSyncUdpPort = 18766;

class OfflinePeerInfo {
  OfflinePeerInfo({
    required this.host,
    required this.port,
    required this.deviceName,
    required this.ownerLogin,
    required this.deviceId,
  });

  final String host;
  final int port;
  final String deviceName;
  final String ownerLogin;
  final String deviceId;

  String get endpoint => 'http://$host:$port';
}

/// Director/admin-only offline sync between PC and phone (same account).
///
/// Transport v1: HTTP on LAN/hotspot + 6-digit pair code.
/// Discovery: UDP broadcast beacon while hosting.
class OfflineDeviceSyncController extends ChangeNotifier {
  OfflineDeviceSyncController({
    required this.projects,
    required this.suppliers,
    required this.user,
    this.transfers,
  });

  final ProjectRepository projects;
  final SupplierRepository suppliers;
  final LocalUserController user;
  final TransferActivityController? transfers;

  bool enabled = false;
  bool hosting = false;
  String deviceId = '';
  String deviceName = '';
  String pairCode = '';
  String? lastPeerName;
  DateTime? lastSyncAt;
  String? lastError;
  String? lastStatusRu;
  List<String> localIps = const [];
  List<OfflinePeerInfo> discovered = const [];

  HttpServer? _server;
  RawDatagramSocket? _beacon;
  Timer? _beaconTimer;
  Timer? _discoverTimer;
  RawDatagramSocket? _discoverSock;
  String? _sessionToken;
  final _rng = Random.secure();

  bool get canUse => user.effectiveRole.canOfflineDeviceSync;

  String get statusHintRu {
    if (!canUse) {
      return 'Доступно директору и админу';
    }
    if (!enabled) return 'Выключено';
    if (hosting) {
      final ips = localIps.isEmpty ? '…' : localIps.join(', ');
      return 'Раздаю · $ips:$kOfflineSyncHttpPort · код $pairCode';
    }
    if (lastSyncAt != null) {
      final t = lastSyncAt!.toLocal();
      final stamp =
          '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      return 'Последний обмен: $stamp'
          '${lastPeerName != null ? ' · $lastPeerName' : ''}';
    }
    return 'Включено · запустите «Раздавать» на одном устройстве';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_prefsEnabled) ?? false;
    deviceId = prefs.getString(_prefsDeviceId) ?? '';
    if (deviceId.isEmpty) {
      deviceId = _newId('dev');
      await prefs.setString(_prefsDeviceId, deviceId);
    }
    deviceName = prefs.getString(_prefsDeviceName) ?? '';
    if (deviceName.isEmpty) {
      deviceName = _defaultDeviceName();
      await prefs.setString(_prefsDeviceName, deviceName);
    }
    pairCode = prefs.getString(_prefsPairCode) ?? '';
    if (pairCode.length != 6) {
      pairCode = _newPairCode();
      await prefs.setString(_prefsPairCode, pairCode);
    }
    final rawAt = prefs.getString(_prefsLastSync);
    if (rawAt != null) {
      lastSyncAt = DateTime.tryParse(rawAt);
    }
    lastPeerName = prefs.getString(_prefsLastPeer);
    localIps = await _listLocalIpv4();
    if (enabled && canUse) {
      await startHosting();
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (value && !canUse) {
      lastError = 'Офлайн-синк только для директора / админа';
      notifyListeners();
      return;
    }
    enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabled, value);
    if (value) {
      await startHosting();
    } else {
      await stopHosting();
    }
    notifyListeners();
  }

  Future<void> setDeviceName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    deviceName = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDeviceName, n);
    notifyListeners();
  }

  Future<void> regeneratePairCode() async {
    pairCode = _newPairCode();
    _sessionToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPairCode, pairCode);
    notifyListeners();
  }

  Future<void> refreshAddresses() async {
    localIps = await _listLocalIpv4();
    notifyListeners();
  }

  Future<void> startHosting() async {
    if (!canUse || !enabled) return;
    if (hosting && _server != null) return;
    lastError = null;
    try {
      localIps = await _listLocalIpv4();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, kOfflineSyncHttpPort);
      hosting = true;
      _server!.listen(_handleRequest, onError: (e) {
        lastError = e.toString();
        notifyListeners();
      });
      await _startBeacon();
      await startDiscovery();
      lastStatusRu = 'Хост запущен';
      notifyListeners();
    } catch (e) {
      hosting = false;
      lastError = 'Не удалось открыть порт $kOfflineSyncHttpPort: $e';
      notifyListeners();
    }
  }

  Future<void> stopHosting() async {
    await _stopBeacon();
    await stopDiscovery();
    await _server?.close(force: true);
    _server = null;
    hosting = false;
    _sessionToken = null;
    notifyListeners();
  }

  Future<void> startDiscovery() async {
    await stopDiscovery();
    try {
      try {
        _discoverSock = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          kOfflineSyncUdpPort,
          reuseAddress: true,
        );
      } catch (_) {
        _discoverSock = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
        );
      }
      _discoverSock!.broadcastEnabled = true;
      _discoverSock!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _discoverSock!.receive();
        if (dg == null) return;
        _onBeacon(dg);
      });
      _discoverTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        // Drop stale peers older than keep via rebuild from recent map — simple clear.
        if (discovered.isNotEmpty) {
          // keep list; UI can refresh manually
        }
      });
    } catch (e) {
      // Discovery is best-effort.
      if (kDebugMode) {
        debugPrint('offline discover: $e');
      }
    }
  }

  Future<void> stopDiscovery() async {
    _discoverTimer?.cancel();
    _discoverTimer = null;
    _discoverSock?.close();
    _discoverSock = null;
  }

  void _onBeacon(Datagram dg) {
    try {
      final j = jsonDecode(utf8.decode(dg.data));
      if (j is! Map) return;
      final id = j['device_id'] as String? ?? '';
      if (id.isEmpty || id == deviceId) return;
      final host = dg.address.address;
      final port = (j['port'] as num?)?.toInt() ?? kOfflineSyncHttpPort;
      final info = OfflinePeerInfo(
        host: host,
        port: port,
        deviceName: j['device_name'] as String? ?? host,
        ownerLogin: j['owner_login'] as String? ?? '',
        deviceId: id,
      );
      final next = [
        for (final p in discovered)
          if (p.deviceId != id) p,
        info,
      ];
      discovered = next;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _startBeacon() async {
    await _stopBeacon();
    try {
      _beacon = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _beacon!.broadcastEnabled = true;
      void send() {
        final payload = utf8.encode(jsonEncode({
          'v': 1,
          'port': kOfflineSyncHttpPort,
          'device_id': deviceId,
          'device_name': deviceName,
          'owner_login': projects.activeOwnerLogin,
        }));
        try {
          _beacon?.send(
            payload,
            InternetAddress('255.255.255.255'),
            kOfflineSyncUdpPort,
          );
        } catch (_) {}
      }

      send();
      _beaconTimer = Timer.periodic(const Duration(seconds: 2), (_) => send());
    } catch (_) {}
  }

  Future<void> _stopBeacon() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _beacon?.close();
    _beacon = null;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/offline/hello') {
        await _json(req, {
          'ok': true,
          'device_id': deviceId,
          'device_name': deviceName,
          'owner_login': projects.activeOwnerLogin,
          'port': kOfflineSyncHttpPort,
        });
        return;
      }
      if (req.method == 'POST' && path == '/offline/pair') {
        final body = await utf8.decoder.bind(req).join();
        final j = jsonDecode(body);
        final code = j is Map ? (j['code'] as String? ?? '') : '';
        if (code != pairCode) {
          await _json(req, {'ok': false, 'error': 'Неверный код'}, status: 403);
          return;
        }
        _sessionToken = _newId('tok');
        await _json(req, {
          'ok': true,
          'token': _sessionToken,
          'device_name': deviceName,
          'owner_login': projects.activeOwnerLogin,
        });
        return;
      }
      if (!_authorized(req)) {
        await _json(req, {'ok': false, 'error': 'Нужна пара'}, status: 401);
        return;
      }
      if (req.method == 'GET' && path == '/offline/pull') {
        final bundle = await buildBundle();
        await _json(req, bundle);
        return;
      }
      if (req.method == 'POST' && path == '/offline/push') {
        final body = await utf8.decoder.bind(req).join();
        final j = jsonDecode(body);
        if (j is! Map) {
          await _json(req, {'ok': false, 'error': 'Плохой JSON'}, status: 400);
          return;
        }
        final note = await applyBundle(Map<String, dynamic>.from(j));
        await _markSynced(j['device_name'] as String?);
        await _json(req, {'ok': true, 'applied': note});
        return;
      }
      await _json(req, {'ok': false, 'error': 'Not found'}, status: 404);
    } catch (e) {
      try {
        await _json(req, {'ok': false, 'error': '$e'}, status: 500);
      } catch (_) {}
    }
  }

  bool _authorized(HttpRequest req) {
    final h = req.headers.value('authorization') ?? '';
    if (!h.startsWith('Bearer ')) return false;
    final tok = h.substring(7).trim();
    return tok.isNotEmpty && tok == _sessionToken;
  }

  Future<void> _json(
    HttpRequest req,
    Map<String, dynamic> body, {
    int status = 200,
  }) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  /// Connect to peer host, exchange bundles both ways.
  Future<String?> syncWithPeer({
    required String host,
    required String code,
    int port = kOfflineSyncHttpPort,
  }) async {
    if (!canUse) return 'Только директор / админ';
    lastError = null;
    lastStatusRu = 'Подключение…';
    final xfer = transfers?.begin(
      direction: TransferDirection.bidirectional,
      titleRu: 'Офлайн-синк',
      detailRu: 'Подключение к $host…',
    );
    notifyListeners();
    final base = 'http://$host:$port';
    try {
      final hello = await http
          .get(Uri.parse('$base/offline/hello'))
          .timeout(const Duration(seconds: 5));
      if (hello.statusCode != 200) {
        return 'Пир недоступен (${hello.statusCode})';
      }
      final helloJ = jsonDecode(hello.body);
      final peerLogin = helloJ is Map
          ? (helloJ['owner_login'] as String? ?? '')
          : '';
      final myLogin = projects.activeOwnerLogin;
      if (peerLogin.isNotEmpty &&
          myLogin.isNotEmpty &&
          peerLogin.toLowerCase() != myLogin.toLowerCase()) {
        return 'Разные аккаунты: у вас @$myLogin, у пира @$peerLogin. '
            'Офлайн-синк — только между своими устройствами.';
      }

      final pair = await http
          .post(
            Uri.parse('$base/offline/pair'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code.trim()}),
          )
          .timeout(const Duration(seconds: 5));
      final pairJ = jsonDecode(pair.body);
      if (pair.statusCode != 200 ||
          pairJ is! Map ||
          pairJ['ok'] != true ||
          pairJ['token'] == null) {
        return pairJ is Map
            ? (pairJ['error'] as String? ?? 'Не удалось спарить')
            : 'Не удалось спарить';
      }
      final token = pairJ['token'] as String;
      final peerName = pairJ['device_name'] as String? ?? host;
      final auth = {'Authorization': 'Bearer $token'};

      lastStatusRu = 'Загрузка с пира…';
      transfers?.update(
        token: xfer,
        direction: TransferDirection.downloading,
        detailRu: 'Входящие с $peerName…',
        progress: 0.25,
      );
      notifyListeners();
      final pull = await http
          .get(Uri.parse('$base/offline/pull'), headers: auth)
          .timeout(const Duration(seconds: 60));
      if (pull.statusCode != 200) {
        return 'Не удалось получить данные (${pull.statusCode})';
      }
      final remote = jsonDecode(pull.body);
      if (remote is! Map) return 'Плохой снимок с пира';
      final applied = await applyBundle(Map<String, dynamic>.from(remote));

      lastStatusRu = 'Отправка на пир…';
      transfers?.update(
        token: xfer,
        direction: TransferDirection.uploading,
        detailRu: 'Исходящие на $peerName…',
        progress: 0.65,
      );
      notifyListeners();
      final local = await buildBundle();
      final push = await http
          .post(
            Uri.parse('$base/offline/push'),
            headers: {
              ...auth,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(local),
          )
          .timeout(const Duration(seconds: 60));
      if (push.statusCode != 200) {
        return 'Пир принял данные частично; отправка не удалась '
            '(${push.statusCode}). Уже применено: $applied';
      }

      await _markSynced(peerName);
      lastStatusRu = 'Готово · $applied';
      transfers?.update(token: xfer, detailRu: 'Готово', progress: 1);
      notifyListeners();
      return null;
    } catch (e) {
      lastError = e.toString();
      lastStatusRu = 'Ошибка';
      transfers?.update(token: xfer, detailRu: 'Ошибка');
      notifyListeners();
      return lastError;
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        transfers?.end(token: xfer);
      });
    }
  }

  Future<Map<String, dynamic>> buildBundle() async {
    final projectList = await projects.listProjects();
    final projectPayloads = <Map<String, dynamic>>[];
    for (final p in projectList) {
      if (p.id == null) continue;
      try {
        projectPayloads.add(
          await projects.buildProjectSharePayload(p.id!),
        );
      } catch (_) {}
    }

    final work = await WorkRatesCatalogStore.buildSharePayload(
      fromOwner: projects.activeOwnerLogin,
    );
    final workSnap = Map<String, dynamic>.from(work['snapshot'] as Map? ?? {});
    workSnap['work_rates_mode'] = 'merge';
    work['work_rates_mode'] = 'merge';
    work['snapshot'] = workSnap;
    final workAt =
        await SyncRevisions.get(SyncRevisions.workRatesKey());
    if (workAt != null) {
      work['updated_at'] = workAt.toIso8601String();
    }

    final kits = await loadMountKits();
    final kitPayloads = <Map<String, dynamic>>[];
    for (final k in kits) {
      final j = k.toJson();
      final at = await SyncRevisions.get(SyncRevisions.kitKey(k.id)) ??
          await SyncRevisions.get(SyncRevisions.kitKey(k.name));
      if (at != null) j['updated_at'] = at.toIso8601String();
      kitPayloads.add(j);
    }

    final suppliersPart = await PricesShare.buildPayload(
      suppliers: suppliers,
      fromOwner: projects.activeOwnerLogin,
      includeWorkRates: false,
      supplierIds: null,
    );
    final supList = <Map<String, dynamic>>[];
    final rawSup = suppliersPart['snapshot'] is Map
        ? (suppliersPart['snapshot'] as Map)['suppliers']
        : null;
    if (rawSup is List) {
      for (final s in rawSup) {
        if (s is! Map) continue;
        final m = Map<String, dynamic>.from(s);
        final name = m['name'] as String? ?? '';
        final at = await SyncRevisions.get(SyncRevisions.supplierKey(name));
        if (at != null) m['updated_at'] = at.toIso8601String();
        supList.add(m);
      }
    }

    return {
      'kind': 'offline_device_bundle',
      'version': 2,
      'lww': true,
      'device_id': deviceId,
      'device_name': deviceName,
      'owner_login': projects.activeOwnerLogin,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'projects': projectPayloads,
      'work_rates': work,
      'kits': kitPayloads,
      'suppliers': supList,
    };
  }

  /// Apply remote bundle with last-write-wins per entity (UTC clocks).
  Future<String> applyBundle(Map<String, dynamic> bundle) async {
    if (bundle['kind'] != 'offline_device_bundle') {
      throw StateError('Это не снимок офлайн-синка');
    }
    final notes = <String>[];

    final projectsRaw = bundle['projects'];
    if (projectsRaw is List) {
      var n = 0;
      var skipped = 0;
      final existing = await projects.listProjects();
      final byName = <String, int>{
        for (final p in existing)
          if (p.id != null) p.name.trim().toLowerCase(): p.id!,
      };
      for (final raw in projectsRaw) {
        if (raw is! Map) continue;
        final payload = Map<String, dynamic>.from(raw);
        final name =
            (payload['project_name'] as String? ?? '').trim().toLowerCase();
        if (name.isEmpty) continue;
        final remoteAt = SyncRevisions.parse(payload['updated_at']);
        final localAt =
            await SyncRevisions.get(SyncRevisions.projectKey(name));
        if (!SyncRevisions.remoteWins(localAt, remoteAt) &&
            localAt != null) {
          skipped++;
          continue;
        }
        // No remote clock + local exists → still merge (legacy bundles).
        if (remoteAt == null && localAt != null && byName.containsKey(name)) {
          // Prefer not to overwrite without clock; skip.
          skipped++;
          continue;
        }
        final into = byName[name];
        try {
          final id = await projects.applyProjectSharePayload(
            payload,
            intoProjectId: into,
          );
          if (into == null) {
            final created = await projects.getProject(id);
            if (created != null && created.id != null) {
              byName[created.name.trim().toLowerCase()] = created.id!;
            }
          }
          if (remoteAt != null) {
            await SyncRevisions.set(SyncRevisions.projectKey(name), remoteAt);
          }
          n++;
        } catch (_) {}
      }
      if (n > 0) notes.add('объекты: $n');
      if (skipped > 0) notes.add('объекты пропуск (новее локально): $skipped');
    }

    final work = bundle['work_rates'];
    if (work is Map) {
      try {
        final remoteAt = SyncRevisions.parse(work['updated_at']);
        final localAt =
            await SyncRevisions.get(SyncRevisions.workRatesKey());
        final snap = work['snapshot'];
        if (snap is Map &&
            snap['categories'] is List &&
            (snap['categories'] as List).isNotEmpty) {
          if (SyncRevisions.remoteWins(localAt, remoteAt) ||
              (remoteAt == null && localAt == null)) {
            final c = await WorkRatesCatalogStore.mergeShareCategories(
              snap['categories'] as List,
            );
            if (remoteAt != null) {
              await SyncRevisions.set(SyncRevisions.workRatesKey(), remoteAt);
            }
            notes.add('работы: +$c');
          } else {
            notes.add('работы: пропуск (локально новее)');
          }
        }
      } catch (_) {}
    }

    final kitsRaw = bundle['kits'];
    if (kitsRaw is List && kitsRaw.isNotEmpty) {
      var kn = 0;
      var skipped = 0;
      final local = await loadMountKits();
      final byName = {
        for (final k in local) k.name.trim().toLowerCase(): k,
      };
      for (final raw in kitsRaw) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final kit = FinishMountKit.fromJson(map);
        if (kit.items.isEmpty) continue;
        final key = kit.name.trim().toLowerCase();
        final remoteAt = SyncRevisions.parse(map['updated_at']);
        final localAt = await SyncRevisions.get(SyncRevisions.kitKey(kit.id)) ??
            await SyncRevisions.get(SyncRevisions.kitKey(kit.name));
        final existing = byName[key];
        if (existing != null &&
            !SyncRevisions.remoteWins(localAt, remoteAt) &&
            localAt != null) {
          skipped++;
          continue;
        }
        if (existing != null) {
          await upsertMountKit(kit.copyWith(id: existing.id));
        } else {
          await upsertMountKit(kit.copyWith(id: newMountKitId()));
        }
        if (remoteAt != null) {
          await SyncRevisions.set(SyncRevisions.kitKey(kit.name), remoteAt);
          await SyncRevisions.set(SyncRevisions.kitKey(kit.id), remoteAt);
        }
        kn++;
      }
      if (kn > 0) notes.add('комплекты: $kn');
      if (skipped > 0) notes.add('комплекты пропуск: $skipped');
    }

    final supRaw = bundle['suppliers'];
    if (supRaw is List && supRaw.isNotEmpty) {
      var applied = 0;
      var skipped = 0;
      final filtered = <Map<String, dynamic>>[];
      final clocks = <String, DateTime>{};
      for (final raw in supRaw) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final name = (m['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final remoteAt = SyncRevisions.parse(m['updated_at']);
        final localAt =
            await SyncRevisions.get(SyncRevisions.supplierKey(name));
        if (!SyncRevisions.remoteWins(localAt, remoteAt) && localAt != null) {
          skipped++;
          continue;
        }
        filtered.add(m);
        if (remoteAt != null) clocks[name] = remoteAt;
        applied++;
      }
      if (filtered.isNotEmpty) {
        await suppliers.applySuppliersShareSnapshot(filtered);
        for (final e in clocks.entries) {
          await SyncRevisions.set(SyncRevisions.supplierKey(e.key), e.value);
        }
      }
      if (applied > 0) notes.add('материалы: $applied пост.');
      if (skipped > 0) notes.add('материалы пропуск: $skipped');
    }

    return notes.isEmpty ? 'нечего применять (всё уже актуально)' : notes.join(' · ');
  }

  /// Export full offline bundle to a temp JSON file (USB / мессенджер / диск).
  Future<File> exportBundleFile() async {
    final bundle = await buildBundle();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(
      p.join(dir.path, 'visota_offline_${projects.activeOwnerLogin}_$stamp.json'),
    );
    await file.writeAsString(jsonEncode(bundle), encoding: utf8);
    return file;
  }

  /// Import bundle from a JSON file (merge into this device).
  Future<String> importBundleFile(File file) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('Файл не похож на снимок офлайн-синка');
    }
    final note = await applyBundle(Map<String, dynamic>.from(decoded));
    await _markSynced(decoded['device_name'] as String? ?? file.uri.pathSegments.last);
    lastStatusRu = 'Импорт из файла · $note';
    notifyListeners();
    return note;
  }

  Future<void> _markSynced(String? peerName) async {
    lastSyncAt = DateTime.now();
    lastPeerName = peerName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLastSync, lastSyncAt!.toIso8601String());
    if (peerName != null) {
      await prefs.setString(_prefsLastPeer, peerName);
    }
    // Offline JSON exports / stale share temps no longer needed.
    await cleanupAfterTransfer(purgeUpdates: false);
    notifyListeners();
  }

  String _newPairCode() =>
      List.generate(6, (_) => _rng.nextInt(10)).join();

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_rng.nextInt(1 << 20).toRadixString(16)}';

  String _defaultDeviceName() {
    if (Platform.isAndroid) return 'Телефон';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isWindows) return 'ПК Windows';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isLinux) return 'ПК Linux';
    return 'Устройство';
  }

  Future<List<String>> _listLocalIpv4() async {
    try {
      final list = <String>[];
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          list.add(addr.address);
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    unawaited(stopHosting());
    super.dispose();
  }
}
