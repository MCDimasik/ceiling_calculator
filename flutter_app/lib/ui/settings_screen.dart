import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'widgets/screen_scaffold.dart';
import '../domain/theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppScope.of(context).theme;
    return ScreenScaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListenableBuilder(
        listenable: theme,
        builder: (context, _) {
          return ListView(
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
              const ListTile(
                title: Text('Ceiling Calculator'),
                subtitle: Text('Flutter · отделка · документация'),
              ),
            ],
          );
        },
      ),
    );
  }
}
