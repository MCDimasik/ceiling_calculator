import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_stub.dart';
import 'local_user_role.dart';

const _prefsTokenKey = 'ceiling_sync_token';

/// Base URL for Ceiling Sync API.
/// Override: `--dart-define=API_BASE=https://calc.example.com`
String ceilingSyncApiBase() {
  const raw = String.fromEnvironment('API_BASE', defaultValue: '');
  if (raw.trim().isNotEmpty) return raw.trim().replaceAll(RegExp(r'/$'), '');
  return 'http://127.0.0.1:8010';
}

class SyncInboxItem {
  SyncInboxItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.fromLogin,
    required this.status,
    required this.createdAt,
    this.payloadJson = '{}',
  });

  final int id;
  final String kind; // project | prices | kit
  final String title;
  final String fromLogin;
  final String status;
  final DateTime createdAt;
  final String payloadJson;

  Map<String, dynamic> get payload {
    try {
      final j = jsonDecode(payloadJson);
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return const {};
  }

  factory SyncInboxItem.fromJson(Map<String, dynamic> j) => SyncInboxItem(
        id: j['id'] as int,
        kind: j['kind'] as String? ?? 'project',
        title: j['title'] as String? ?? '',
        fromLogin: j['from_login'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.now(),
        payloadJson: j['payload_json'] as String? ?? '{}',
      );
}

class SyncInboxCounts {
  const SyncInboxCounts({
    this.project = 0,
    this.prices = 0,
    this.kit = 0,
    this.total = 0,
  });

  final int project;
  final int prices;
  final int kit;
  final int total;

  factory SyncInboxCounts.fromJson(Map<String, dynamic> j) => SyncInboxCounts(
        project: (j['project'] as num?)?.toInt() ?? 0,
        prices: (j['prices'] as num?)?.toInt() ?? 0,
        kit: (j['kit'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
}

class SyncRemoteUser {
  SyncRemoteUser({
    required this.fullName,
    required this.login,
    required this.requestedRole,
    required this.confirmed,
    required this.effectiveRole,
  });

  final String fullName;
  final String login;
  final AppUserRole requestedRole;
  final bool confirmed;
  final AppUserRole effectiveRole;

  factory SyncRemoteUser.fromJson(Map<String, dynamic> j) {
    AppUserRole parseRole(String? raw) {
      final n = (raw ?? 'installer').replaceAll('super_admin', 'superAdmin');
      return AppUserRole.parse(n);
    }

    return SyncRemoteUser(
      fullName: j['full_name'] as String? ?? '',
      login: j['login'] as String? ?? '',
      requestedRole: parseRole(j['requested_role'] as String?),
      confirmed: j['confirmed'] == true,
      effectiveRole: parseRole(j['effective_role'] as String?),
    );
  }
}

class CeilingSyncException implements Exception {
  CeilingSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CeilingSyncClient {
  CeilingSyncClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? ceilingSyncApiBase();

  final http.Client _http;
  final String baseUrl;
  String? accessToken;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessToken != null && accessToken!.isNotEmpty)
          'Authorization': 'Bearer $accessToken',
      };

  Future<bool> health() async {
    try {
      final r =
          await _http.get(_u('/health')).timeout(const Duration(seconds: 3));
      if (r.statusCode != 200) return false;
      final j = jsonDecode(r.body);
      return j is Map && j['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String> login({required String login, required String password}) async {
    final r = await _http.post(
      _u('/auth/login'),
      headers: _headers,
      body: jsonEncode({'login': login, 'password': password}),
    );
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    accessToken = j['access_token'] as String?;
    if (accessToken == null || accessToken!.isEmpty) {
      throw CeilingSyncException('Нет токена');
    }
    return accessToken!;
  }

  Future<String> register({
    required String fullName,
    required String login,
    required String password,
    required AppUserRole role,
  }) async {
    final roleApi = role == AppUserRole.superAdmin ? 'super_admin' : role.name;
    final r = await _http.post(
      _u('/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'full_name': fullName,
        'login': login,
        'password': password,
        'requested_role': roleApi,
      }),
    );
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    accessToken = j['access_token'] as String?;
    if (accessToken == null) throw CeilingSyncException('Нет токена');
    return accessToken!;
  }

  Future<SyncRemoteUser> me() async {
    final r = await _http.get(_u('/auth/me'), headers: _headers);
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    return SyncRemoteUser.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Confirmed API users for recipient picker (excludes self).
  Future<List<SyncRemoteUser>> directory() async {
    final r = await _http.get(_u('/auth/directory'), headers: _headers);
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    final list = jsonDecode(r.body) as List<dynamic>;
    return [
      for (final e in list)
        if (e is Map) SyncRemoteUser.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  /// Users awaiting role confirmation (director+).
  Future<List<SyncRemoteUser>> pendingUsers() async {
    final r = await _http.get(_u('/auth/pending'), headers: _headers);
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    final list = jsonDecode(r.body) as List<dynamic>;
    return [
      for (final e in list)
        if (e is Map) SyncRemoteUser.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<SyncRemoteUser> confirmRole(String targetLogin) async {
    final r = await _http.post(
      _u('/auth/confirm'),
      headers: _headers,
      body: jsonEncode({'target_login': targetLogin.trim().toLowerCase()}),
    );
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    return SyncRemoteUser.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<SyncInboxCounts> inboxCounts() async {
    final r = await _http.get(_u('/inbox/counts'), headers: _headers);
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    return SyncInboxCounts.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<SyncInboxItem>> listInbox() async {
    final r = await _http.get(_u('/inbox'), headers: _headers);
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    final list = jsonDecode(r.body) as List<dynamic>;
    return [
      for (final e in list)
        if (e is Map) SyncInboxItem.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<SyncInboxItem> createOffer({
    required String kind,
    required String title,
    required String toLogin,
    String payloadJson = '{}',
  }) async {
    final r = await _http.post(
      _u('/inbox'),
      headers: _headers,
      body: jsonEncode({
        'kind': kind,
        'title': title,
        'to_login': toLogin,
        'payload_json': payloadJson,
      }),
    );
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    return SyncInboxItem.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<SyncInboxItem> decide({
    required int itemId,
    required bool accept,
    String? targetProjectId,
  }) async {
    final r = await _http.post(
      _u('/inbox/$itemId/decide'),
      headers: _headers,
      body: jsonEncode({
        'accept': accept,
        if (targetProjectId != null) 'target_project_id': targetProjectId,
      }),
    );
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    return SyncInboxItem.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Seamless account backup. Returns null if server has no snapshot yet.
  Future<Map<String, dynamic>?> getAccountSnapshot() async {
    final r = await _http.get(_u('/account/snapshot'), headers: _headers);
    if (r.statusCode == 204 ||
        r.statusCode == 404 ||
        r.body.trim().isEmpty ||
        r.body.trim() == 'null') {
      return null;
    }
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    final j = jsonDecode(r.body);
    if (j == null) return null;
    if (j is! Map) throw CeilingSyncException('Неверный снимок');
    return Map<String, dynamic>.from(j);
  }

  Future<Map<String, dynamic>> putAccountSnapshot({
    required String payloadJson,
    DateTime? updatedAt,
  }) async {
    final r = await _http.put(
      _u('/account/snapshot'),
      headers: _headers,
      body: jsonEncode({
        'payload_json': payloadJson,
        if (updatedAt != null)
          'updated_at': updatedAt.toUtc().toIso8601String(),
      }),
    );
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
  }

  Future<List<Map<String, dynamic>>> listArchiveFiles() async {
    final r = await _http.get(_u('/archive/files'), headers: _headers);
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    final list = jsonDecode(r.body) as List<dynamic>;
    return [
      for (final e in list)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  Future<Map<String, dynamic>> uploadArchiveFile({
    required String categoryClientId,
    required String clientId,
    required String displayName,
    required List<int> bytes,
    String filename = 'file.bin',
  }) async {
    final uri = _u('/archive/files');
    final req = http.MultipartRequest('POST', uri);
    if (accessToken != null && accessToken!.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    req.fields['category_client_id'] = categoryClientId;
    req.fields['client_id'] = clientId;
    req.fields['display_name'] = displayName;
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed =
        await _http.send(req).timeout(const Duration(minutes: 3));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw CeilingSyncException('Загрузка файла: HTTP ${streamed.statusCode}');
    }
    return Map<String, dynamic>.from(jsonDecode(body) as Map);
  }

  Future<List<int>> downloadArchiveFile(int serverId) async {
    final r = await _http.get(
      _u('/archive/files/$serverId/download'),
      headers: {
        if (accessToken != null && accessToken!.isNotEmpty)
          'Authorization': 'Bearer $accessToken',
      },
    );
    if (r.statusCode != 200) throw CeilingSyncException(_err(r));
    return r.bodyBytes;
  }

  String _err(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return 'Ошибка API ${r.statusCode}';
  }
}

/// App-wide sync state (API session + inbox badges).
class CeilingSyncController extends ChangeNotifier {
  CeilingSyncController({CeilingSyncClient? client})
      : client = client ?? CeilingSyncClient();

  final CeilingSyncClient client;
  final AppSurface surface = AppSurface.fromEnvironment();

  CloudSyncStatus status = CloudSyncStatus.awaitingServerApproval;
  SyncRemoteUser? remoteUser;
  SyncInboxCounts counts = const SyncInboxCounts();
  List<SyncRemoteUser> pendingRoleUsers = const [];
  String? lastError;

  bool get isSignedIn =>
      client.accessToken != null && client.accessToken!.isNotEmpty;

  bool get canConfirmCloudRoles {
    final r = remoteUser?.effectiveRole;
    return r == AppUserRole.director || r == AppUserRole.superAdmin;
  }

  int get pendingTotal => counts.total;
  int get pendingProjectOffers => counts.project;
  int get pendingPricePushes => counts.prices;
  int get pendingKitOffers => counts.kit;
  int get pendingRoleConfirmations => pendingRoleUsers.length;

  String get statusHintRu {
    if (status == CloudSyncStatus.offlineLocal) {
      return 'API недоступен · ${client.baseUrl}';
    }
    if (lastError != null && !isSignedIn) return lastError!;
    if (status == CloudSyncStatus.ready && isSignedIn) {
      return 'Синк · ${remoteUser?.login ?? "онлайн"} · входящих: $pendingTotal';
    }
    if (status == CloudSyncStatus.ready) {
      return 'API доступен · войдите в профиле (облако)';
    }
    return 'Ожидание API (${client.baseUrl})';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsTokenKey);
    if (saved != null && saved.isNotEmpty) client.accessToken = saved;

    final ok = await client.health();
    if (!ok) {
      status = CloudSyncStatus.offlineLocal;
      lastError = null;
      notifyListeners();
      return;
    }
    status = CloudSyncStatus.ready;
    lastError = null;
    if (isSignedIn) {
      try {
        remoteUser = await client.me();
        counts = await client.inboxCounts();
        await _refreshPendingRolesQuiet();
      } catch (e) {
        client.accessToken = null;
        remoteUser = null;
        pendingRoleUsers = const [];
        await prefs.remove(_prefsTokenKey);
        lastError = e.toString();
      }
    }
    notifyListeners();
  }

  Future<String?> signIn({
    required String login,
    required String password,
  }) async {
    try {
      await client.login(login: login, password: password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsTokenKey, client.accessToken!);
      remoteUser = await client.me();
      counts = await client.inboxCounts();
      await _refreshPendingRolesQuiet();
      status = CloudSyncStatus.ready;
      lastError = null;
      notifyListeners();
      return null;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return lastError;
    }
  }

  /// Register on Sync API (and keep session). Returns error or null.
  Future<String?> registerCloud({
    required String fullName,
    required String login,
    required String password,
    required AppUserRole role,
  }) async {
    try {
      await client.register(
        fullName: fullName,
        login: login,
        password: password,
        role: role,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsTokenKey, client.accessToken!);
      remoteUser = await client.me();
      counts = await client.inboxCounts();
      await _refreshPendingRolesQuiet();
      status = CloudSyncStatus.ready;
      lastError = null;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> signOutCloud() async {
    client.accessToken = null;
    remoteUser = null;
    counts = const SyncInboxCounts();
    pendingRoleUsers = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsTokenKey);
    notifyListeners();
  }

  Future<void> _refreshPendingRolesQuiet() async {
    if (!isSignedIn || !canConfirmCloudRoles) {
      pendingRoleUsers = const [];
      return;
    }
    try {
      pendingRoleUsers = await client.pendingUsers();
    } catch (_) {
      pendingRoleUsers = const [];
    }
  }

  Future<void> refreshPendingRoles() async {
    if (!isSignedIn) return;
    try {
      remoteUser = await client.me();
      await _refreshPendingRolesQuiet();
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    }
    notifyListeners();
  }

  Future<String?> confirmCloudRole(String targetLogin) async {
    if (!isSignedIn) return 'Сначала войдите в облако';
    if (!canConfirmCloudRoles) {
      return 'Подтверждать роли может директор / супер-админ';
    }
    try {
      await client.confirmRole(targetLogin);
      await _refreshPendingRolesQuiet();
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> refreshInbox() async {
    if (!isSignedIn) return;
    try {
      counts = await client.inboxCounts();
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    }
    notifyListeners();
  }

  Future<List<SyncInboxItem>> fetchInbox() =>
      isSignedIn ? client.listInbox() : Future.value(const []);

  Future<String?> sendOffer({
    required String kind,
    required String title,
    required String toLogin,
    String payloadJson = '{}',
  }) async {
    if (!isSignedIn) return 'Сначала войдите в облако (Профиль)';
    try {
      await client.createOffer(
        kind: kind,
        title: title,
        toLogin: toLogin,
        payloadJson: payloadJson,
      );
      await refreshInbox();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> decideOffer({
    required int itemId,
    required bool accept,
  }) async {
    try {
      await client.decide(itemId: itemId, accept: accept);
      await refreshInbox();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}

/// Switch local profile + cloud API session to a seeded test persona.
Future<String?> switchTestPersonaSession({
  required LocalUserController user,
  required CeilingSyncController sync,
  required AppUserRole role,
  Future<void> Function(String login)? onLocalAccountChanged,
}) async {
  final localErr = await user.switchTestPersona(role);
  if (localErr != null) return localErr;
  final login = testPersonaLogin(role);
  if (onLocalAccountChanged != null) {
    await onLocalAccountChanged(login);
  }
  final cloudErr = await sync.signIn(
    login: login,
    password: kLocalDemoPassword,
  );
  if (cloudErr != null) {
    return 'Локально: @$login · облако: $cloudErr';
  }
  return null;
}
