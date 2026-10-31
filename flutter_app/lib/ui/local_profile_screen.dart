import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/ceiling_sync_client.dart';
import '../domain/local_user_role.dart';
import 'widgets/screen_scaffold.dart';
import 'widgets/test_persona_switcher.dart';

/// Registration / sign-in / cloud session / role confirmation.
class LocalProfileScreen extends StatefulWidget {
  const LocalProfileScreen({super.key, this.initialTab = 0});

  /// 0 регистрация · 1 вход · 2 облако
  final int initialTab;

  @override
  State<LocalProfileScreen> createState() => _LocalProfileScreenState();
}

class _LocalProfileScreenState extends State<LocalProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _nameCtrl = TextEditingController();
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _signLoginCtrl = TextEditingController();
  final _signPassCtrl = TextEditingController();
  final _cloudLoginCtrl = TextEditingController();
  final _cloudPassCtrl = TextEditingController();
  AppUserRole _requested = AppUserRole.foreman;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initialTab.clamp(0, 2);
    _tabs = TabController(length: 3, vsync: this, initialIndex: i);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _loginCtrl.dispose();
    _passCtrl.dispose();
    _signLoginCtrl.dispose();
    _signPassCtrl.dispose();
    _cloudLoginCtrl.dispose();
    _cloudPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _cloudSignIn() async {
    setState(() => _busy = true);
    final scope = AppScope.of(context);
    final err = await scope.sync.signIn(
      login: _cloudLoginCtrl.text,
      password: _cloudPassCtrl.text,
    );
    if (!mounted) return;
    String? restoreNote;
    if (err == null) {
      restoreNote = await scope.accountCloud.syncNow();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final remote = AppScope.of(context).sync.remoteUser;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restoreNote != null
              ? 'Вход OK, синк: $restoreNote'
              : remote == null
              ? 'Облачный вход выполнен'
              : 'Облако · ${remote.fullName} · ${remote.effectiveRole.labelRu}',
        ),
      ),
    );
  }

  Future<void> _register() async {
    setState(() => _busy = true);
    final scope = AppScope.of(context);
    final err = await scope.user.register(
      fullName: _nameCtrl.text,
      login: _loginCtrl.text,
      password: _passCtrl.text,
      requestedRole: _requested,
    );
    if (!mounted) return;
    if (err == null) {
      await scope.projects.setActiveOwnerLogin(scope.user.profile?.login);
      // Mirror to Sync API when reachable (best-effort).
      var cloudErr = await scope.sync.registerCloud(
        fullName: _nameCtrl.text,
        login: _loginCtrl.text,
        password: _passCtrl.text,
        role: _requested,
      );
      if (cloudErr != null && cloudErr.contains('занят')) {
        cloudErr = await scope.sync.signIn(
          login: _loginCtrl.text,
          password: _passCtrl.text,
        );
      }
      if (!mounted) return;
      if (cloudErr != null) {
        // Local OK; cloud optional at this stage.
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final user = scope.user;
    final remote = scope.sync.remoteUser;
    final pendingCloud = remote != null && !remote.confirmed;
    final msg = user.isPending || pendingCloud
        ? 'Заявка сохранена · до подтверждения доступ как у монтажника'
        : 'Профиль активен · ${user.effectiveRole.labelRu}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.pop(context);
  }

  Future<void> _confirmCloud(SyncRemoteUser pending) async {
    final scope = AppScope.of(context);
    final err = await scope.sync.confirmCloudRole(pending.login);
    if (!mounted) return;
    if (err == null) {
      // Mirror onto local profiles with the same login, if any.
      await scope.user.markConfirmed(pending.login);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              'Облако: роль «${pending.requestedRole.labelRu}» '
              'для @${pending.login} подтверждена',
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    final scope = AppScope.of(context);
    final err = await scope.user.signIn(
      login: _signLoginCtrl.text,
      password: _signPassCtrl.text,
    );
    if (!mounted) return;
    if (err == null) {
      await scope.projects.setActiveOwnerLogin(scope.user.profile?.login);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _confirm(LocalUserProfile pending) async {
    final dirLogin = TextEditingController();
    final dirPass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Подтвердить · ${pending.fullName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Роль: ${pending.requestedRole.labelRu}'),
            const SizedBox(height: 12),
            TextField(
              controller: dirLogin,
              decoration: const InputDecoration(
                labelText: 'Логин директора',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: dirPass,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Пароль директора',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await AppScope.of(context).user.confirmRole(
      targetLogin: pending.login,
      directorLogin: dirLogin.text,
      directorPassword: dirPass.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Роль подтверждена')),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user;
    final sync = AppScope.of(context).sync;
    return ScreenScaffold(
      appBar: AppBar(
        title: const Text('Профиль и роли'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Регистрация'),
            Tab(text: 'Вход'),
            Tab(text: 'Облако'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([user, sync]),
        builder: (context, _) {
          final user = AppScope.of(context).user;
          final sync = AppScope.of(context).sync;
          return Column(
        children: [
          if (user.profile != null)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                title: Text(user.profile!.fullName),
                subtitle: Text(
                  user.isPending
                      ? 'Ожидает подтверждения · сейчас ${user.effectiveRole.labelRu}'
                      : '${user.accountRole.labelRu} · @${user.profile!.login}',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    await user.signOut();
                    await AppScope.of(context)
                        .projects
                        .setActiveOwnerLogin('__guest__');
                    if (mounted) setState(() {});
                  },
                  child: const Text('Выйти'),
                ),
              ),
            ),
          if (user.canUseTestPersonaLab)
            Material(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TestPersonaSwitcher(),
              ),
            ),
          if (sync.isSignedIn)
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.cloud_done_outlined),
                title: Text(
                  sync.remoteUser?.fullName ?? 'Облачный сеанс',
                ),
                subtitle: Text(
                  '${sync.remoteUser?.login ?? ""} · '
                  '${sync.remoteUser?.effectiveRole.labelRu ?? ""} · '
                  'входящих: ${sync.pendingTotal}',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    await sync.signOutCloud();
                    if (mounted) setState(() {});
                  },
                  child: const Text('Выйти'),
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'ФИО',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _loginCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Логин',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Пароль',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Запрашиваемая роль',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SegmentedButton<AppUserRole>(
                      showSelectedIcon: false,
                      segments: [
                        for (final r in [
                          AppUserRole.installer,
                          AppUserRole.foreman,
                          AppUserRole.director,
                        ])
                          ButtonSegment(
                            value: r,
                            label: Text(r.labelRu, textAlign: TextAlign.center),
                          ),
                      ],
                      selected: {_requested},
                      onSelectionChanged: (s) =>
                          setState(() => _requested = s.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _requested.hintRu,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _register,
                      child: const Text('Зарегистрироваться'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Без регистрации устройство работает как монтажник. '
                      'Бригадир/директор — после подтверждения директором '
                      '(первый директор на устройстве и в API подтверждается сразу). '
                      'При доступном API заявка уходит и в облако.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (user.accountRole.canConfirmRoles &&
                        user.pendingProfiles.isNotEmpty) ...[
                      const Divider(height: 32),
                      Text(
                        'Локально ждут подтверждения',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final p in user.pendingProfiles)
                        ListTile(
                          title: Text(p.fullName),
                          subtitle:
                              Text('${p.requestedRole.labelRu} · ${p.login}'),
                          trailing: TextButton(
                            onPressed: () => _confirm(p),
                            child: const Text('ОК'),
                          ),
                        ),
                    ],
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _signLoginCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Логин',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _signPassCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Пароль',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: const Text('Войти'),
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Облако — Sync API (${sync.client.baseUrl}): входящие, '
                      'рассылка объектов/расценок/комплектов и подтверждение ролей.',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Доступы модулей на главной — от локального профиля. '
                      'Свитчер персон переключает и локальный, и облачный аккаунт.\n\n'
                      'Демо: admin / director / brigadir / monter / novichok · '
                      'пароль demo1234 (novichok ждёт подтверждения).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      sync.statusHintRu,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _cloudLoginCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Логин API',
                        hintText: 'director / novichok / …',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cloudPassCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Пароль API',
                        hintText: 'demo1234',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy || sync.isSignedIn ? null : _cloudSignIn,
                      child: Text(
                        sync.isSignedIn ? 'Уже в облаке' : 'Войти в облако',
                      ),
                    ),
                    if (sync.isSignedIn) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () async {
                          await sync.signOutCloud();
                          if (mounted) setState(() {});
                        },
                        child: const Text('Выйти из облака'),
                      ),
                      if (sync.remoteUser != null &&
                          !sync.remoteUser!.confirmed) ...[
                        const SizedBox(height: 16),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.hourglass_top_outlined),
                            title: const Text('Ожидает подтверждения роли'),
                            subtitle: Text(
                              'Запрошено: ${sync.remoteUser!.requestedRole.labelRu}. '
                              'Пока эффективная роль — '
                              '${sync.remoteUser!.effectiveRole.labelRu}.',
                            ),
                          ),
                        ),
                      ],
                      if (sync.canConfirmCloudRoles) ...[
                        const Divider(height: 32),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Заявки в облаке',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Обновить',
                              onPressed: () async {
                                await sync.refreshPendingRoles();
                                if (mounted) setState(() {});
                              },
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        if (sync.pendingRoleUsers.isEmpty)
                          const ListTile(
                            leading: Icon(Icons.check_circle_outline),
                            title: Text('Нет ожидающих заявок'),
                          )
                        else
                          for (final p in sync.pendingRoleUsers)
                            Card(
                              child: ListTile(
                                title: Text(p.fullName),
                                subtitle: Text(
                                  '${p.requestedRole.labelRu} · @${p.login}',
                                ),
                                trailing: FilledButton(
                                  onPressed: () => _confirmCloud(p),
                                  child: const Text('Подтвердить'),
                                ),
                              ),
                            ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
          );
        },
      ),
    );
  }
}
