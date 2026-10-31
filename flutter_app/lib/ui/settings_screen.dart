import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/local_user_role.dart';
import '../domain/theme_controller.dart';
import 'adaptive_layout.dart';
import 'app_update_screen.dart';
import 'local_profile_screen.dart';
import 'offline_device_sync_screen.dart';
import 'widgets/screen_scaffold.dart';
import 'widgets/test_persona_switcher.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppScope.of(context).theme;
    final user = AppScope.of(context).user;
    final sync = AppScope.of(context).sync;
    final offlineSync = AppScope.of(context).offlineSync;
    final accountCloud = AppScope.of(context).accountCloud;
    return ScreenScaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(
          [theme, user, sync, offlineSync, accountCloud],
        ),
        builder: (context, _) {
          final profile = user.profile;
          final role = user.effectiveRole;
          final desktop = DesktopMetrics.of(context);
          final themeControl = SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('Авто'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode),
                label: Text('Светлая'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('Тёмная'),
              ),
            ],
            selected: {theme.mode},
            onSelectionChanged: (s) => theme.setMode(s.first),
          );
          return ListView(
            padding: EdgeInsets.symmetric(
              vertical: desktop ? 8 : 0,
            ),
            children: [
              ListTile(
                leading: Icon(
                  Icons.badge_outlined,
                  size: desktop ? 28 : 24,
                ),
                title: const Text('Профиль и роли'),
                subtitle: Text(
                  profile == null
                      ? 'Гость · ${role.labelRu} · регистрация на устройстве'
                      : (user.isPending
                          ? '${profile.fullName} · ожидает · ${role.labelRu}'
                          : '${profile.fullName} · ${role.labelRu} · @${profile.login}'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LocalProfileScreen(),
                    ),
                  );
                },
              ),
              if (user.canUseTestPersonaLab)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TestPersonaSwitcher(),
                ),
              const Divider(),
              if (desktop)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Тема',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            switch (theme.mode) {
                              ThemeMode.light => 'Светлая',
                              ThemeMode.dark => 'Тёмная',
                              _ => 'Как в системе',
                            },
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 14),
                          themeControl,
                        ],
                      ),
                    ),
                  ),
                )
              else
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
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                      ),
                    ],
                    selected: {theme.mode},
                    onSelectionChanged: (s) => theme.setMode(s.first),
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
                    : (v) => theme.setUseVideoBg(v),
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  sync.isSignedIn
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_outlined,
                ),
                title: const Text('Облако и синк'),
                subtitle: Text(
                  '${sync.statusHintRu}\n'
                  'Свитчер теста выше входит и локально, и в API.\n'
                  'API: ${sync.client.baseUrl}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LocalProfileScreen(
                        initialTab: 2,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  sync.isSignedIn
                      ? Icons.cloud_sync_outlined
                      : Icons.cloud_off_outlined,
                ),
                title: const Text('Синхронизация аккаунта'),
                subtitle: Text(AppScope.of(context).accountCloud.statusHintRu),
                trailing: AppScope.of(context).accountCloud.busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                onTap: () async {
                  final cloud = AppScope.of(context).accountCloud;
                  final err = await cloud.syncNow();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(err ?? cloud.lastStatusRu ?? 'Готово'),
                    ),
                  );
                },
              ),
              if (role.canOfflineDeviceSync) ...[
                ListTile(
                  leading: Icon(
                    offlineSync.enabled
                        ? Icons.phonelink_outlined
                        : Icons.phonelink_off_outlined,
                  ),
                  title: const Text('Офлайн-синк ПК ↔ телефон'),
                  subtitle: Text(offlineSync.statusHintRu),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OfflineDeviceSyncScreen(),
                      ),
                    );
                  },
                ),
              ],
              if (role.canManageAppUpdates)
                ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: const Text('Обновления (админ)'),
                  subtitle: Text(
                    AppScope.of(context).appUpdate.currentVersionName == null
                        ? 'Манифест OTA · авто у всех ролей'
                        : 'Сейчас ${AppScope.of(context).appUpdate.currentVersionName}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AppUpdateScreen(),
                      ),
                    );
                  },
                ),
              const Divider(),
              const ListTile(
                title: Text('Высота Калькулятор'),
                subtitle: Text(
                  'Flutter · локальные роли · отделка · документация',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
