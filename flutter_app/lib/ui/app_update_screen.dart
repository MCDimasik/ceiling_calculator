import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/local_user_role.dart';
import 'widgets/screen_scaffold.dart';

/// Admin-only: configure manifest URL and manual check / install.
class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key});

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  final _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final u = AppScope.of(context).appUpdate;
      await u.load();
      if (!mounted) return;
      _urlCtrl.text = u.manifestUrl;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLocalManifest() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked.isEmpty) return;
    final path = picked.first.path;
    if (path == null) return;
    _urlCtrl.text = path;
    await AppScope.of(context).appUpdate.setManifestUrl(path);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _check() async {
    final u = AppScope.of(context).appUpdate;
    await u.setManifestUrl(_urlCtrl.text);
    final r = await u.checkForUpdate();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.error ??
              (r.hasUpdate
                  ? 'Есть обновление ${r.remote!.versionName}'
                  : 'Актуально: ${r.currentName}'),
        ),
      ),
    );
  }

  Future<void> _downloadAndInstall() async {
    final u = AppScope.of(context).appUpdate;
    final remote = u.lastCheck?.remote;
    if (remote == null || u.lastCheck?.hasUpdate != true) return;
    try {
      await u.downloadUpdate(remote);
      if (!mounted) return;
      await u.openPendingInstaller();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Обновление: $e')),
      );
    }
  }

  Future<void> _installPending() async {
    final u = AppScope.of(context).appUpdate;
    try {
      await u.openPendingInstaller();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Установка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = AppScope.of(context).user.effectiveRole;
    final u = AppScope.of(context).appUpdate;
    if (!role.canManageAppUpdates) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Обновления')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Настройка обновлений доступна только админу.\n'
              'У остальных приложение проверяет манифест само '
              'при появлении сети.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return ScreenScaffold(
      appBar: AppBar(title: const Text('Обновления (админ)')),
      body: ListenableBuilder(
        listenable: u,
        builder: (context, _) {
          final check = u.lastCheck;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                'Сейчас: ${u.currentVersionName ?? '…'} '
                '(build ${u.currentVersionCode ?? '…'})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Манифест — JSON с полями version_name, version_code, '
                'apk_url / windows_url, notes. Положите на облачный диск '
                'или HTTP. Пользователи получают обновление молча; '
                'этот экран — только для настройки канала.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Автопроверка при запуске'),
                subtitle: const Text(
                  'Все роли: раз в 6 ч при сети скачать APK/EXE и '
                  'предложить установку (данные приложения сохраняются)',
                ),
                value: u.autoEnabled,
                onChanged: (v) => u.setAutoEnabled(v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL или путь к манифесту',
                  hintText: 'https://…/update.json  или  C:\\…\\update.json',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _pickLocalManifest,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Файл…'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: u.checking ? null : _check,
                    icon: u.checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update_alt),
                    label: const Text('Проверить'),
                  ),
                ],
              ),
              if (u.lastStatusRu != null) ...[
                const SizedBox(height: 12),
                Text(u.lastStatusRu!),
              ],
              if (u.pendingInstallerPath != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    title: Text(
                      'Скачано: ${u.pendingVersionName ?? 'обновление'}',
                    ),
                    subtitle: Text(u.pendingInstallerPath!),
                    trailing: FilledButton(
                      onPressed: _installPending,
                      child: const Text('Установить'),
                    ),
                  ),
                ),
              ],
              if (check?.remote != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: Text(
                      'В манифесте: ${check!.remote!.versionName} '
                      '(+${check.remote!.versionCode})',
                    ),
                    subtitle: Text(
                      check.hasUpdate
                          ? (check.remote!.notes.isEmpty
                              ? 'Доступно обновление'
                              : check.remote!.notes)
                          : 'Не новее установленной',
                    ),
                    isThreeLine: check.remote!.notes.isNotEmpty,
                  ),
                ),
                if (check.hasUpdate) ...[
                  const SizedBox(height: 8),
                  if (u.downloading && u.downloadProgress != null)
                    LinearProgressIndicator(value: u.downloadProgress),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: u.downloading ? null : _downloadAndInstall,
                    icon: const Icon(Icons.download),
                    label: Text(
                      u.downloading
                          ? 'Скачивание…'
                          : 'Скачать и установить',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              Text(
                'Пример update.json',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              const SelectableText(
                '{\n'
                '  "version_name": "3.0.1",\n'
                '  "version_code": 102120513,\n'
                '  "apk_url": "https://example.com/CeilingCalculator.apk",\n'
                '  "windows_url": "https://example.com/CeilingCalculator.exe",\n'
                '  "notes": "Офлайн-синк и исправления"\n'
                '}',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}
