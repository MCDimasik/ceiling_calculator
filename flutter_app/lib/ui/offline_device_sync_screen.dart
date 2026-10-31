import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/local_user_role.dart';
import '../domain/offline_device_sync.dart';
import '../domain/temp_cleanup.dart';
import 'widgets/screen_scaffold.dart';

/// Director/admin: manage offline PC ↔ phone sync (LAN / hotspot / file).
class OfflineDeviceSyncScreen extends StatefulWidget {
  const OfflineDeviceSyncScreen({super.key});

  @override
  State<OfflineDeviceSyncScreen> createState() =>
      _OfflineDeviceSyncScreenState();
}

class _OfflineDeviceSyncScreenState extends State<OfflineDeviceSyncScreen> {
  final _hostCtrl = TextEditingController();
  final _peerCodeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final off = AppScope.of(context).offlineSync;
      _nameCtrl.text = off.deviceName;
      // Peer code stays empty — must enter the HOST's code.
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _peerCodeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSync() async {
    final off = AppScope.of(context).offlineSync;
    final host = _hostCtrl.text.trim();
    final code = _peerCodeCtrl.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите IP устройства-хоста')),
      );
      return;
    }
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите 6-значный код с хоста')),
      );
      return;
    }
    setState(() => _busy = true);
    final err = await off.syncWithPeer(host: host, code: code);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? (off.lastStatusRu ?? 'Синхронизация завершена')),
      ),
    );
  }

  Future<void> _exportFile() async {
    final off = AppScope.of(context).offlineSync;
    setState(() => _busy = true);
    String? exportPath;
    try {
      final file = await off.exportBundleFile();
      exportPath = file.path;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Офлайн-снимок Высота',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выгрузить: $e')),
      );
    } finally {
      await deleteFileQuiet(exportPath);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    final off = AppScope.of(context).offlineSync;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked.isEmpty) return;
    final path = picked.first.path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      final note = await off.importBundleFile(File(path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импортировано · $note')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось импортировать: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final off = scope.offlineSync;
    final can = scope.user.effectiveRole.canOfflineDeviceSync;
    final scheme = Theme.of(context).colorScheme;

    return ScreenScaffold(
      appBar: AppBar(
        title: const Text('Офлайн-синк'),
        actions: [
          IconButton(
            tooltip: 'Обновить адреса',
            onPressed: () => off.refreshAddresses(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: off,
        builder: (context, _) {
          if (!can) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Офлайн-синхронизация ПК ↔ телефон доступна '
                  'только директору и админу.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Card(
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Как это работает',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '• Один и тот же аккаунт (директор/админ) на ПК и телефоне.\n'
                        '• Одна Wi‑Fi или раздача с телефона на ПК (hotspot) — '
                        'обмен в обе стороны: объекты, работы, материалы, комплекты.\n'
                        '• Приоритет по времени правки (UTC): на каждое устройство '
                        'уезжает только то, что новее локальной копии; устаревшее '
                        'не затирает свежее. Часовые пояса не важны — важны '
                        'синхронизированные часы устройств.\n'
                        '• Одно устройство «раздаёт» (хост), второе подключается '
                        'по IP + коду. После связи данные уезжают туда и обратно.\n'
                        '• Без интернета и без API. Когда сеть появится — '
                        'облачный синк как раньше.\n'
                        '• Запасной путь: выгрузить/принять JSON-файл '
                        '(кабель, диск, мессенджер).',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Включить офлайн-синк'),
                subtitle: Text(
                  off.enabled
                      ? (off.hosting
                          ? 'Хост активен · ${off.statusHintRu}'
                          : off.statusHintRu)
                      : 'Выключено — раздача и поиск пиров остановлены',
                ),
                value: off.enabled,
                onChanged: _busy
                    ? null
                    : (v) async {
                        await off.setEnabled(v);
                      },
              ),
              const Divider(height: 28),
              Text(
                '1. Это устройство (хост)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Включите синк здесь, покажите IP и код второму устройству. '
                'При раздаче Wi‑Fi с телефона удобно сделать хостом телефон: '
                'ПК подключится к его IP в сети 192.168.x.x.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Имя устройства',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) => off.setDeviceName(v),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => off.setDeviceName(_nameCtrl.text),
                  child: const Text('Сохранить имя'),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ваш код пары (для второго устройства)'),
                subtitle: Text(
                  off.pairCode,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        letterSpacing: 4,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Копировать',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: off.pairCode),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Код скопирован')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                    IconButton(
                      tooltip: 'Новый код',
                      onPressed: () => off.regeneratePairCode(),
                      icon: const Icon(Icons.casino_outlined),
                    ),
                  ],
                ),
              ),
              if (off.localIps.isEmpty)
                Text(
                  'IP пока не видны. Включите Wi‑Fi/раздачу и нажмите обновить.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                )
              else ...[
                Text(
                  'IP этого устройства:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                for (final ip in off.localIps)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(ip),
                    subtitle: Text('порт $kOfflineSyncHttpPort'),
                    trailing: IconButton(
                      tooltip: 'Копировать',
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: ip));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Скопировано: $ip')),
                        );
                      },
                    ),
                  ),
              ],
              if (off.hosting)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.wifi_tethering, color: scheme.primary),
                    title: const Text('Раздача (хост) активна'),
                    subtitle: Text(
                      'На втором устройстве: IP одного из адресов выше + '
                      'код ${off.pairCode} → «Синхронизировать». '
                      'Данные уйдут в обе стороны.',
                    ),
                    isThreeLine: true,
                  ),
                ),
              if (Platform.isWindows)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Windows: при первом запуске разрешите доступ '
                    'приложения к сети (порт $kOfflineSyncHttpPort) в брандмауэре.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const Divider(height: 28),
              Text(
                '2. Подключиться к хосту',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'На хосте уже включён офлайн-синк. Здесь — его IP и его код '
                '(не ваш). После обмена оба устройства получат объединение данных.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (off.discovered.isNotEmpty) ...[
                Text(
                  'Найдено в сети',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                for (final peer in off.discovered)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.devices_other),
                    title: Text(peer.deviceName),
                    subtitle: Text('${peer.host} · @${peer.ownerLogin}'),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              _hostCtrl.text = peer.host;
                              setState(() {});
                            },
                      child: const Text('IP'),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _hostCtrl,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'IP хоста',
                  hintText: '192.168.x.x',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _peerCodeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Код пары хоста',
                  border: OutlineInputBorder(),
                  isDense: true,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: (!off.enabled || _busy) ? null : _runSync,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  _busy ? 'Обмен в обе стороны…' : 'Синхронизировать',
                ),
              ),
              const Divider(height: 28),
              Text(
                '3. Файлом (без сети)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Выгрузите снимок на одном устройстве и примите на другом '
                '(кабель, диск, чат). Тот же merge, что и по сети.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _exportFile,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Выгрузить'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _importFile,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Принять'),
                    ),
                  ),
                ],
              ),
              if (off.lastError != null) ...[
                const SizedBox(height: 12),
                Text(
                  off.lastError!,
                  style: TextStyle(color: scheme.error),
                ),
              ],
              if (off.lastStatusRu != null) ...[
                const SizedBox(height: 8),
                Text(
                  off.lastStatusRu!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
