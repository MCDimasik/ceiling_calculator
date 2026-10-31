import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'temp_cleanup.dart';
import 'transfer_activity.dart';

const _prefsManifestUrl = 'app_update_manifest_url_v1';
const _prefsAutoEnabled = 'app_update_auto_enabled_v1';
const _prefsLastAutoCheckMs = 'app_update_last_auto_check_ms_v1';
const _prefsPendingInstaller = 'app_update_pending_installer_v1';
const _prefsPendingVersion = 'app_update_pending_version_v1';

/// Built-in fallback when admin has not set a per-device URL yet.
/// Replace with your cloud-disk / CDN `update.json` when publishing a build.
const kDefaultAppUpdateManifestUrl = '';

const _autoCheckMinInterval = Duration(hours: 6);

const _installChannel = MethodChannel('org.ceiling/app_update');

/// Remote / local update manifest for OTA (APK or Windows installer).
class AppUpdateManifest {
  AppUpdateManifest({
    required this.versionName,
    required this.versionCode,
    this.apkUrl,
    this.windowsUrl,
    this.notes = '',
  });

  final String versionName;
  final int versionCode;
  final String? apkUrl;
  final String? windowsUrl;
  final String notes;

  factory AppUpdateManifest.fromJson(Map<String, dynamic> j) =>
      AppUpdateManifest(
        versionName: (j['version_name'] as String?)?.trim() ??
            (j['versionName'] as String?)?.trim() ??
            '',
        versionCode: (j['version_code'] as num?)?.toInt() ??
            (j['versionCode'] as num?)?.toInt() ??
            0,
        apkUrl: (j['apk_url'] as String?) ?? (j['apkUrl'] as String?),
        windowsUrl:
            (j['windows_url'] as String?) ?? (j['windowsUrl'] as String?),
        notes: (j['notes'] as String?)?.trim() ?? '',
      );

  String? downloadUrlForPlatform() {
    if (Platform.isAndroid) {
      final u = apkUrl?.trim();
      return (u == null || u.isEmpty) ? null : u;
    }
    if (Platform.isWindows) {
      final u = windowsUrl?.trim();
      return (u == null || u.isEmpty) ? null : u;
    }
    return apkUrl?.trim().isNotEmpty == true ? apkUrl : windowsUrl;
  }
}

class AppUpdateCheckResult {
  AppUpdateCheckResult({
    required this.currentName,
    required this.currentCode,
    this.remote,
    this.error,
  });

  final String currentName;
  final int currentCode;
  final AppUpdateManifest? remote;
  final String? error;

  bool get hasUpdate {
    final r = remote;
    if (r == null) return false;
    return r.versionCode > currentCode;
  }
}

/// Outcome of a silent background cycle (no admin UI).
enum AppUpdateSilentOutcome {
  skippedNoUrl,
  skippedRecent,
  skippedUpToDate,
  downloaded,
  alreadyPending,
  error,
}

class AppUpdateSilentResult {
  AppUpdateSilentResult(this.outcome, {this.message, this.installerPath});

  final AppUpdateSilentOutcome outcome;
  final String? message;
  final String? installerPath;

  bool get shouldPromptInstall =>
      outcome == AppUpdateSilentOutcome.downloaded ||
      outcome == AppUpdateSilentOutcome.alreadyPending;
}

/// OTA: check manifest URL (or local JSON), download, prompt install.
///
/// Same `applicationId` + signing key ⇒ Android keeps SQLite / prefs.
/// Windows side-by-side install should keep the app data directory.
class AppUpdateController extends ChangeNotifier {
  AppUpdateController({this.transfers});

  final TransferActivityController? transfers;

  String manifestUrl = '';
  bool autoEnabled = true;
  String? currentVersionName;
  int? currentVersionCode;
  AppUpdateCheckResult? lastCheck;
  String? lastStatusRu;
  bool checking = false;
  bool downloading = false;
  double? downloadProgress;
  String? pendingInstallerPath;
  String? pendingVersionName;
  bool silentRunning = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsManifestUrl) ?? '';
    manifestUrl =
        stored.isNotEmpty ? stored : kDefaultAppUpdateManifestUrl;
    autoEnabled = prefs.getBool(_prefsAutoEnabled) ?? true;
    pendingInstallerPath = prefs.getString(_prefsPendingInstaller);
    pendingVersionName = prefs.getString(_prefsPendingVersion);
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersionName = info.version;
      currentVersionCode = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      currentVersionName = '—';
      currentVersionCode = 0;
    }
    // If we already run a newer/equal build, drop leftover installer files.
    if (pendingInstallerPath != null) {
      final f = File(pendingInstallerPath!);
      final pendingStillUseful = await f.exists() &&
          !_pendingLooksInstalled(pendingVersionName, currentVersionName);
      if (!pendingStillUseful) {
        await deleteFileQuiet(pendingInstallerPath);
        pendingInstallerPath = null;
        pendingVersionName = null;
        await prefs.remove(_prefsPendingInstaller);
        await prefs.remove(_prefsPendingVersion);
        await purgeOldUpdatePackages();
      } else {
        await purgeOldUpdatePackages(keepPath: pendingInstallerPath);
      }
    } else {
      await purgeOldUpdatePackages();
    }
    notifyListeners();
  }

  /// Heuristic: pending version name already matches running app → installed.
  bool _pendingLooksInstalled(String? pendingName, String? currentName) {
    if (pendingName == null || currentName == null) return false;
    final a = pendingName.trim().toLowerCase();
    final b = currentName.trim().toLowerCase();
    if (a.isEmpty || b.isEmpty) return false;
    return a == b || b.startsWith(a) || a.startsWith(b);
  }

  Future<void> setManifestUrl(String url) async {
    manifestUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsManifestUrl, manifestUrl);
    notifyListeners();
  }

  Future<void> setAutoEnabled(bool enabled) async {
    autoEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoEnabled, enabled);
    notifyListeners();
  }

  Future<AppUpdateCheckResult> checkForUpdate() async {
    checking = true;
    lastStatusRu = 'Проверка…';
    notifyListeners();
    try {
      final info = await PackageInfo.fromPlatform();
      final curName = info.version;
      final curCode = int.tryParse(info.buildNumber) ?? 0;
      currentVersionName = curName;
      currentVersionCode = curCode;

      final source = manifestUrl.trim().isNotEmpty
          ? manifestUrl.trim()
          : kDefaultAppUpdateManifestUrl;
      if (source.isEmpty) {
        final r = AppUpdateCheckResult(
          currentName: curName,
          currentCode: curCode,
          error: 'Укажите URL манифеста (JSON) или выберите локальный файл',
        );
        lastCheck = r;
        lastStatusRu = r.error;
        return r;
      }

      final remote = await _loadManifest(source);
      final r = AppUpdateCheckResult(
        currentName: curName,
        currentCode: curCode,
        remote: remote,
      );
      lastCheck = r;
      lastStatusRu = r.hasUpdate
          ? 'Доступна ${remote.versionName} (+${remote.versionCode})'
          : 'У вас актуальная версия ($curName)';
      return r;
    } catch (e) {
      final info = await PackageInfo.fromPlatform();
      final r = AppUpdateCheckResult(
        currentName: info.version,
        currentCode: int.tryParse(info.buildNumber) ?? 0,
        error: e.toString(),
      );
      lastCheck = r;
      lastStatusRu = 'Ошибка проверки: $e';
      return r;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<AppUpdateManifest> _loadManifest(String source) async {
    if (source.startsWith('http://') || source.startsWith('https://')) {
      final resp = await http
          .get(Uri.parse(source))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw StateError('HTTP ${resp.statusCode}');
      }
      final j = jsonDecode(resp.body);
      if (j is! Map) throw StateError('Манифест не JSON-объект');
      return AppUpdateManifest.fromJson(Map<String, dynamic>.from(j));
    }
    final file = File(source);
    if (!await file.exists()) {
      throw StateError('Файл манифеста не найден');
    }
    final j = jsonDecode(await file.readAsString());
    if (j is! Map) throw StateError('Манифест не JSON-объект');
    return AppUpdateManifest.fromJson(Map<String, dynamic>.from(j));
  }

  /// Download update package to app-support (survives temp cleanup).
  Future<File> downloadUpdate(AppUpdateManifest manifest) async {
    final url = manifest.downloadUrlForPlatform();
    if (url == null || url.isEmpty) {
      throw StateError(
        Platform.isAndroid
            ? 'В манифесте нет apk_url'
            : 'В манифесте нет windows_url',
      );
    }
    downloading = true;
    downloadProgress = 0;
    lastStatusRu = 'Скачивание…';
    final token = transfers?.begin(
      direction: TransferDirection.downloading,
      titleRu: 'Обновление ${manifest.versionName}',
      detailRu: 'Скачивание пакета…',
      progress: 0,
    );
    notifyListeners();
    try {
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      final streamed =
          await client.send(req).timeout(const Duration(minutes: 5));
      if (streamed.statusCode != 200) {
        throw StateError('Скачивание: HTTP ${streamed.statusCode}');
      }
      final total = streamed.contentLength ?? 0;
      final bytes = <int>[];
      var got = 0;
      await for (final chunk in streamed.stream) {
        bytes.addAll(chunk);
        got += chunk.length;
        if (total > 0) {
          downloadProgress = got / total;
          transfers?.setProgress(downloadProgress, token: token);
          notifyListeners();
        }
      }
      client.close();

      final dir = await getApplicationSupportDirectory();
      final updatesDir = Directory(p.join(dir.path, 'updates'));
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }
      final ext = Platform.isAndroid ? 'apk' : 'exe';
      final name = 'CeilingCalculator-${manifest.versionName}.$ext';
      final file = File(p.join(updatesDir.path, name));
      await file.writeAsBytes(bytes, flush: true);
      downloadProgress = 1;
      lastStatusRu = 'Скачано: ${file.path}';
      await _setPending(file.path, manifest.versionName);
      // Keep only this installer; purge older APK/EXE and share temps.
      await cleanupAfterTransfer(keepUpdatePath: file.path);
      return file;
    } finally {
      downloading = false;
      transfers?.end(token: token);
      notifyListeners();
    }
  }

  Future<void> _setPending(String path, String versionName) async {
    pendingInstallerPath = path;
    pendingVersionName = versionName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPendingInstaller, path);
    await prefs.setString(_prefsPendingVersion, versionName);
    notifyListeners();
  }

  Future<void> clearPending({bool deleteFile = true}) async {
    final path = pendingInstallerPath;
    pendingInstallerPath = null;
    pendingVersionName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsPendingInstaller);
    await prefs.remove(_prefsPendingVersion);
    if (deleteFile) {
      await deleteFileQuiet(path);
      await purgeOldUpdatePackages();
    }
    notifyListeners();
  }

  /// Open system installer. Does not wipe app data (same package / signing).
  Future<void> openInstaller(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Файл обновления не найден');
    }
    if (Platform.isAndroid) {
      await _installChannel.invokeMethod<void>('installApk', {'path': path});
      return;
    }
    if (Platform.isWindows) {
      await Process.start(
        path,
        const [],
        mode: ProcessStartMode.detached,
      );
      return;
    }
    throw StateError('Установка OTA на этой платформе не поддерживается');
  }

  Future<void> openPendingInstaller() async {
    final path = pendingInstallerPath;
    if (path == null) throw StateError('Нет скачанного обновления');
    await openInstaller(path);
  }

  /// Background: check → download if newer. Call once after UI is up.
  Future<AppUpdateSilentResult> runSilentCycle({
    bool force = false,
  }) async {
    if (silentRunning) {
      return AppUpdateSilentResult(
        AppUpdateSilentOutcome.skippedRecent,
        message: 'Уже проверяем',
      );
    }
    if (!autoEnabled && !force) {
      return AppUpdateSilentResult(
        AppUpdateSilentOutcome.skippedRecent,
        message: 'Автообновление выключено',
      );
    }
    silentRunning = true;
    notifyListeners();
    try {
      final source = manifestUrl.trim().isNotEmpty
          ? manifestUrl.trim()
          : kDefaultAppUpdateManifestUrl;
      if (source.isEmpty) {
        return AppUpdateSilentResult(AppUpdateSilentOutcome.skippedNoUrl);
      }

      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_prefsLastAutoCheckMs) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!force &&
          lastMs > 0 &&
          now - lastMs < _autoCheckMinInterval.inMilliseconds) {
        if (pendingInstallerPath != null) {
          return AppUpdateSilentResult(
            AppUpdateSilentOutcome.alreadyPending,
            installerPath: pendingInstallerPath,
            message: pendingVersionName,
          );
        }
        return AppUpdateSilentResult(AppUpdateSilentOutcome.skippedRecent);
      }

      if (pendingInstallerPath != null) {
        final f = File(pendingInstallerPath!);
        if (await f.exists()) {
          return AppUpdateSilentResult(
            AppUpdateSilentOutcome.alreadyPending,
            installerPath: pendingInstallerPath,
            message: pendingVersionName,
          );
        }
        await clearPending();
      }

      final check = await checkForUpdate();
      await prefs.setInt(_prefsLastAutoCheckMs, now);
      if (check.error != null) {
        return AppUpdateSilentResult(
          AppUpdateSilentOutcome.error,
          message: check.error,
        );
      }
      if (!check.hasUpdate || check.remote == null) {
        return AppUpdateSilentResult(AppUpdateSilentOutcome.skippedUpToDate);
      }

      final file = await downloadUpdate(check.remote!);
      return AppUpdateSilentResult(
        AppUpdateSilentOutcome.downloaded,
        installerPath: file.path,
        message: check.remote!.versionName,
      );
    } catch (e) {
      return AppUpdateSilentResult(
        AppUpdateSilentOutcome.error,
        message: e.toString(),
      );
    } finally {
      silentRunning = false;
      notifyListeners();
    }
  }
}
