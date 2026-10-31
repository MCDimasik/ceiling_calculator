import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../domain/ceiling_sync_client.dart';
import '../../domain/local_user_role.dart';

/// Full local+cloud account switch for seeded test personas.
class TestPersonaSwitcher extends StatefulWidget {
  const TestPersonaSwitcher({super.key});

  @override
  State<TestPersonaSwitcher> createState() => _TestPersonaSwitcherState();
}

class _TestPersonaSwitcherState extends State<TestPersonaSwitcher> {
  bool _busy = false;

  Future<void> _switchTo(AppUserRole role) async {
    if (_busy) return;
    setState(() => _busy = true);
    final scope = AppScope.of(context);
    final err = await switchTestPersonaSession(
      user: scope.user,
      sync: scope.sync,
      role: role,
      onLocalAccountChanged: (login) =>
          scope.projects.setActiveOwnerLogin(login).then((_) async {
            final off = scope.offlineSync;
            if (!scope.user.effectiveRole.canOfflineDeviceSync &&
                off.enabled) {
              await off.setEnabled(false);
            }
          }),
    );
    if (!mounted) return;
    if (err == null && scope.sync.isSignedIn) {
      await scope.accountCloud.syncNow();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final login = testPersonaLogin(role);
    final cloudOk = scope.sync.isSignedIn &&
        scope.sync.remoteUser?.login.toLowerCase() == login;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err == null
              ? 'Аккаунт · @$login · ${role.labelRu}'
                  '${cloudOk ? " · облако OK" : ""}'
              : err,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user;
    final sync = AppScope.of(context).sync;
    if (!user.canUseTestPersonaLab) return const SizedBox.shrink();

    final selected = user.profile?.login.toLowerCase() == 'admin'
        ? AppUserRole.superAdmin
        : user.effectiveRole;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Тест: сменить аккаунт'),
          subtitle: Text(
            'Полный вход: локально + облако (@login / $kLocalDemoPassword). '
            'Сейчас: ${user.profile?.login ?? 'гость'}'
            '${sync.isSignedIn ? ' · облако ${sync.remoteUser?.login}' : ''}',
          ),
          isThreeLine: true,
        ),
        SegmentedButton<AppUserRole>(
          showSelectedIcon: false,
          segments: [
            for (final r in [
              AppUserRole.superAdmin,
              AppUserRole.director,
              AppUserRole.foreman,
              AppUserRole.installer,
            ])
              ButtonSegment(
                value: r,
                label: Text(
                  r == AppUserRole.superAdmin ? 'Админ' : r.labelRu,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
                enabled: !_busy,
              ),
          ],
          selected: {selected},
          onSelectionChanged: _busy
              ? null
              : (s) {
                  if (s.isEmpty) return;
                  _switchTo(s.first);
                },
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}
