import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI scope for construction site roles (local device, not cloud RBAC).
enum FieldRole {
  full('Полный доступ', 'Все модули и настройки'),
  manager('Руководитель', 'Сводки, документация, экспорт по объекту'),
  foreman('Бригадир', 'Раскладки, чеклисты, назначения, фото'),
  worker('Монтажник', 'Только скрытые работы: фото и отметки');

  const FieldRole(this.labelRu, this.hintRu);

  final String labelRu;
  final String hintRu;

  bool get canDeleteProjects => this == FieldRole.full;
  bool get canEditLayout => this != FieldRole.worker;
  bool get canSeePricing => this == FieldRole.full || this == FieldRole.manager;
  bool get prefersDashboard => this == FieldRole.manager || this == FieldRole.foreman;
  bool get workerOnlyChecklist => this == FieldRole.worker;
  bool get canCloseActs => this != FieldRole.worker;
  bool get canImportContract => this == FieldRole.full || this == FieldRole.manager;
  bool get canExportPack => this != FieldRole.worker;
  bool get canRebaseline => this != FieldRole.worker;
  bool get canEditProjectDocs => this != FieldRole.worker;

  static FieldRole parse(String? raw) => FieldRole.values.firstWhere(
        (r) => r.name == raw,
        orElse: () => FieldRole.full,
      );
}

class FieldRoleController extends ChangeNotifier {
  FieldRole _role = FieldRole.full;

  /// ARCHIVED: site roles temporarily disabled — always [FieldRole.full].
  /// Prefs still store the last choice for restore; see `_archived/README.md`.
  static const bool rolesUiArchived = true;

  FieldRole get role => rolesUiArchived ? FieldRole.full : _role;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _role = FieldRole.parse(prefs.getString('field_role'));
    _workerName = prefs.getString('field_worker_name') ?? '';
    notifyListeners();
  }

  String _workerName = '';
  String get workerName => _workerName;

  Future<void> setWorkerName(String name) async {
    _workerName = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('field_worker_name', _workerName);
    notifyListeners();
  }

  Future<void> setRole(FieldRole role) async {
    _role = role;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('field_role', role.name);
    notifyListeners();
  }
}
