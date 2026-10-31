import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'finish_model.dart';

/// Local device roles (no server). Guest without registration = installer.
enum AppUserRole {
  installer,
  foreman,
  director,
  superAdmin;

  String get labelRu => switch (this) {
        AppUserRole.installer => 'Монтажник',
        AppUserRole.foreman => 'Бригадир',
        AppUserRole.director => 'Директор',
        AppUserRole.superAdmin => 'Супер-админ',
      };

  String get hintRu => switch (this) {
        AppUserRole.installer =>
          'Раскладка, материалы потолка, импорт потолка, настройки',
        AppUserRole.foreman =>
          'Отделка без документов (+ведомость), импорт отделки, расценки',
        AppUserRole.director => 'Полный доступ + архив',
        AppUserRole.superAdmin =>
          'Полный доступ + переключение роли для теста UI',
      };

  static AppUserRole parse(String? raw) => AppUserRole.values.firstWhere(
        (r) => r.name == raw,
        orElse: () => AppUserRole.installer,
      );
}

class LocalUserProfile {
  LocalUserProfile({
    required this.fullName,
    required this.login,
    required this.passwordHash,
    required this.requestedRole,
    required this.confirmed,
  });

  final String fullName;
  final String login;
  final String passwordHash;
  final AppUserRole requestedRole;
  final bool confirmed;

  AppUserRole get effectiveRole =>
      confirmed ? requestedRole : AppUserRole.installer;

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'login': login,
        'passwordHash': passwordHash,
        'requestedRole': requestedRole.name,
        'confirmed': confirmed,
      };

  factory LocalUserProfile.fromJson(Map<String, dynamic> j) => LocalUserProfile(
        fullName: (j['fullName'] as String?)?.trim() ?? '',
        login: (j['login'] as String?)?.trim() ?? '',
        passwordHash: (j['passwordHash'] as String?) ?? '',
        requestedRole: AppUserRole.parse(j['requestedRole'] as String?),
        confirmed: j['confirmed'] == true,
      );

  LocalUserProfile copyWith({
    String? fullName,
    String? login,
    String? passwordHash,
    AppUserRole? requestedRole,
    bool? confirmed,
  }) =>
      LocalUserProfile(
        fullName: fullName ?? this.fullName,
        login: login ?? this.login,
        passwordHash: passwordHash ?? this.passwordHash,
        requestedRole: requestedRole ?? this.requestedRole,
        confirmed: confirmed ?? this.confirmed,
      );
}

String hashLocalPassword(String password) =>
    sha256.convert(utf8.encode(password.trim())).toString();

/// Gates home modules / actions by effective role.
extension AppUserRoleAccess on AppUserRole {
  bool get canCeilingLayout => true;
  bool get canCeilingMaterials => true;
  bool get canCeilingImport => true;
  bool get canSettings => true;

  bool get canFinish =>
      this == AppUserRole.foreman ||
      this == AppUserRole.director ||
      this == AppUserRole.superAdmin;

  /// Finish docs / КП / КС — director+.
  bool get canDocumentation =>
      this == AppUserRole.director || this == AppUserRole.superAdmin;

  /// Ведомость without full docs pack — foreman+.
  bool get canFinishVedomost => canFinish;

  bool get canPricing =>
      this == AppUserRole.foreman ||
      this == AppUserRole.director ||
      this == AppUserRole.superAdmin;

  bool get canArchive =>
      this == AppUserRole.director || this == AppUserRole.superAdmin;

  bool get canConfirmRoles =>
      this == AppUserRole.director || this == AppUserRole.superAdmin;

  /// Offline PC ↔ phone mesh for the same director/admin account.
  bool get canOfflineDeviceSync =>
      this == AppUserRole.director || this == AppUserRole.superAdmin;

  /// Configure OTA manifest URL / manual check UI (silent auto for everyone else).
  bool get canManageAppUpdates => this == AppUserRole.superAdmin;

  bool get canManageProfiles => this == AppUserRole.superAdmin;

  bool canOpenModule(AppModule module) => switch (module) {
        AppModule.ceilingLayout => canCeilingLayout,
        AppModule.materials => canCeilingMaterials,
        AppModule.finish => canFinish,
        AppModule.documentation => canDocumentation,
      };
}

const _prefsActiveLogin = 'local_user_active_login';
const _prefsProfiles = 'local_user_profiles_v1';

/// Shared password for local + API demo accounts.
const kLocalDemoPassword = 'demo1234';

/// Login used by the on-device persona switcher for [role].
String testPersonaLogin(AppUserRole role) => switch (role) {
      AppUserRole.superAdmin => 'admin',
      AppUserRole.director => 'director',
      AppUserRole.foreman => 'brigadir',
      AppUserRole.installer => 'monter',
    };

class LocalUserController extends ChangeNotifier {
  LocalUserProfile? _profile;
  List<LocalUserProfile> _all = [];

  LocalUserProfile? get profile => _profile;
  List<LocalUserProfile> get allProfiles => List.unmodifiable(_all);

  AppUserRole get accountRole =>
      _profile?.effectiveRole ?? AppUserRole.installer;

  bool get isSuperAdminAccount => accountRole == AppUserRole.superAdmin;

  /// Role used for UI gates (= signed-in account).
  AppUserRole get effectiveRole => accountRole;

  bool get isRegistered => _profile != null;
  bool get isPending => _profile != null && !_profile!.confirmed;

  /// Show full-account test switcher when demo personas are seeded.
  bool get canUseTestPersonaLab =>
      _find('admin') != null &&
      _find('director') != null &&
      _find('brigadir') != null &&
      _find('monter') != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsProfiles);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _all = [
          for (final e in list)
            if (e is Map)
              LocalUserProfile.fromJson(Map<String, dynamic>.from(e)),
        ];
      } catch (_) {
        _all = [];
      }
    }
    final login = prefs.getString(_prefsActiveLogin);
    if (login != null && login.isNotEmpty) {
      _profile = _find(login);
    } else {
      _profile = null;
    }
    await ensureDevTestProfiles();
    notifyListeners();
  }

  /// Promote `admin` → superAdmin; seed monter/brigadir/director for multi-device tests.
  Future<void> ensureDevTestProfiles() async {
    var changed = false;

    final admin = _find('admin');
    if (admin != null) {
      if (admin.requestedRole != AppUserRole.superAdmin || !admin.confirmed) {
        final next = admin.copyWith(
          requestedRole: AppUserRole.superAdmin,
          confirmed: true,
        );
        _all = [
          for (final p in _all)
            if (p.login.toLowerCase() == 'admin') next else p,
        ];
        if (_profile?.login.toLowerCase() == 'admin') _profile = next;
        changed = true;
      }
    } else {
      _all = [
        ..._all,
        LocalUserProfile(
          fullName: 'Супер-админ',
          login: 'admin',
          passwordHash: hashLocalPassword(kLocalDemoPassword),
          requestedRole: AppUserRole.superAdmin,
          confirmed: true,
        ),
      ];
      changed = true;
    }

    const seeds = <(String, String, AppUserRole)>[
      ('Тест Монтажник', 'monter', AppUserRole.installer),
      ('Тест Бригадир', 'brigadir', AppUserRole.foreman),
      ('Тест Директор', 'director', AppUserRole.director),
    ];
    for (final (name, login, role) in seeds) {
      if (_find(login) != null) continue;
      _all = [
        ..._all,
        LocalUserProfile(
          fullName: name,
          login: login,
          passwordHash: hashLocalPassword(kLocalDemoPassword),
          requestedRole: role,
          confirmed: true,
        ),
      ];
      changed = true;
    }

    if (changed) await _persist();
  }

  /// Instant local switch to a seeded test persona (no password prompt).
  Future<String?> switchTestPersona(AppUserRole role) async {
    await ensureDevTestProfiles();
    final login = testPersonaLogin(role);
    final p = _find(login);
    if (p == null) return 'Нет тестового профиля @$login';
    if (!p.confirmed) {
      final fixed = p.copyWith(confirmed: true);
      _all = [
        for (final e in _all)
          if (e.login.toLowerCase() == login) fixed else e,
      ];
      _profile = fixed;
    } else {
      _profile = p;
    }
    await _persist();
    notifyListeners();
    return null;
  }

  LocalUserProfile? _find(String login) {
    final key = login.trim().toLowerCase();
    for (final p in _all) {
      if (p.login.toLowerCase() == key) return p;
    }
    return null;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsProfiles,
      jsonEncode([for (final p in _all) p.toJson()]),
    );
    final active = _profile?.login;
    if (active == null || active.isEmpty) {
      await prefs.remove(_prefsActiveLogin);
    } else {
      await prefs.setString(_prefsActiveLogin, active);
    }
  }

  /// Register or update local profile. First director on device auto-confirms.
  Future<String?> register({
    required String fullName,
    required String login,
    required String password,
    required AppUserRole requestedRole,
  }) async {
    final name = fullName.trim();
    final log = login.trim();
    if (name.isEmpty) return 'Укажите ФИО';
    if (log.isEmpty) return 'Укажите логин';
    if (password.trim().length < 4) return 'Пароль не короче 4 символов';
    if (requestedRole == AppUserRole.superAdmin) {
      return 'Супер-админ пока недоступен';
    }

    final existing = _find(log);
    final hasConfirmedDirector = _all.any(
      (p) =>
          p.confirmed &&
          (p.requestedRole == AppUserRole.director ||
              p.requestedRole == AppUserRole.superAdmin),
    );
    final autoConfirm = requestedRole == AppUserRole.director &&
        !hasConfirmedDirector;

    final hash = hashLocalPassword(password);
    final next = LocalUserProfile(
      fullName: name,
      login: log,
      passwordHash: hash,
      requestedRole: requestedRole,
      confirmed: autoConfirm || requestedRole == AppUserRole.installer,
    );

    if (existing != null) {
      _all = [
        for (final p in _all)
          if (p.login.toLowerCase() == log.toLowerCase()) next else p,
      ];
    } else {
      _all = [..._all, next];
    }
    _profile = next;
    await _persist();
    notifyListeners();
    return null;
  }

  Future<String?> signIn({
    required String login,
    required String password,
  }) async {
    final p = _find(login);
    if (p == null) return 'Пользователь не найден';
    if (p.passwordHash != hashLocalPassword(password)) {
      return 'Неверный пароль';
    }
    _profile = p;
    await _persist();
    notifyListeners();
    return null;
  }

  Future<void> signOut() async {
    _profile = null;
    await _persist();
    notifyListeners();
  }

  /// Confirm a pending profile (director password required).
  Future<String?> confirmRole({
    required String targetLogin,
    required String directorLogin,
    required String directorPassword,
  }) async {
    final director = _find(directorLogin);
    if (director == null ||
        !director.confirmed ||
        !director.effectiveRole.canConfirmRoles) {
      return 'Нужен подтверждённый директор';
    }
    if (director.passwordHash != hashLocalPassword(directorPassword)) {
      return 'Неверный пароль директора';
    }
    return markConfirmed(targetLogin);
  }

  /// Mark local profile confirmed (e.g. after cloud confirm).
  Future<String?> markConfirmed(String targetLogin) async {
    final target = _find(targetLogin);
    if (target == null) return 'Профиль не найден';
    if (target.confirmed) return null;
    final confirmed = target.copyWith(confirmed: true);
    _all = [
      for (final p in _all)
        if (p.login.toLowerCase() == targetLogin.trim().toLowerCase())
          confirmed
        else
          p,
    ];
    if (_profile?.login.toLowerCase() == target.login.toLowerCase()) {
      _profile = confirmed;
    }
    await _persist();
    notifyListeners();
    return null;
  }

  List<LocalUserProfile> get pendingProfiles =>
      _all.where((p) => !p.confirmed).toList();
}
