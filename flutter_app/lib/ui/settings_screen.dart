import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'receipt_import_screen.dart';
import 'widgets/screen_scaffold.dart';
import '../domain/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  DateTime? _pressStarted;

  Future<void> _tryAdminUnlock() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Режим администратора'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Пароль'),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final unlocked = await AppScope.of(context).admin.tryUnlock(controller.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(unlocked ? 'Админ-режим включён' : 'Неверный пароль')),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final admin = scope.admin;
    final theme = scope.theme;
    return ScreenScaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Тема'),
            subtitle: Text(switch (theme.mode) {
              ThemeMode.light => 'Светлая',
              ThemeMode.dark => 'Тёмная',
              _ => 'Как в системе',
            }),
            trailing: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
              ],
              selected: {theme.mode},
              onSelectionChanged: (s) async {
                await theme.setMode(s.first);
                setState(() {});
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Видеофон'),
            subtitle: Text(
              videoBgUnsupported
                  ? 'На Windows/Linux отключён (крашит video_player). На телефоне можно включить.'
                  : 'Только на главной: mp4 поверх фото-фона',
            ),
            value: theme.useVideoBg && !videoBgUnsupported,
            onChanged: videoBgUnsupported
                ? null
                : (v) async {
                    await theme.setUseVideoBg(v);
                    setState(() {});
                  },
          ),
          const Divider(),
          Listener(
            onPointerDown: (_) => _pressStarted = DateTime.now(),
            onPointerUp: (_) {
              final started = _pressStarted;
              _pressStarted = null;
              if (started == null) return;
              if (DateTime.now().difference(started) >= const Duration(seconds: 1)) {
                _tryAdminUnlock();
              }
            },
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Админ-режим'),
              subtitle: Text(
                admin.unlocked
                    ? 'Активен — удержите 1 сек для повторного ввода'
                    : 'Удержите 1 секунду и введите пароль',
              ),
            ),
          ),
          if (admin.unlocked) ...[
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Импорт чека'),
              subtitle: const Text('Текст чека → цены поставщика'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReceiptImportScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Выйти из админ-режима'),
              onTap: () async {
                await admin.lock();
                setState(() {});
              },
            ),
          ],
          const Divider(),
          const ListTile(
            title: Text('Ceiling Calculator'),
            subtitle: Text('Flutter-порт · версия 2.2'),
          ),
        ],
      ),
    );
  }
}
