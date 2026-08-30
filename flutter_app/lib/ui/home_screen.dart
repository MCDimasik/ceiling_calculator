import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_model.dart';
import '../domain/project_transfer.dart';
import 'materials_flow_screens.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';
import 'suppliers_screen.dart';
import 'widgets/app_background.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _adminDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Режим администратора\n(цены и поставщики)'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Пароль'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Войти')),
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
    final admin = AppScope.of(context).admin.unlocked;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        dim: true,
        allowVideo: true,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              Image.asset(
                'assets/media/logo-visota.PNG',
                height: 72,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              Text(
                'Ceiling Calculator',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              _MainButton(
                label: 'Расчет раскладки потолка',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProjectsScreen(module: AppModule.ceilingLayout),
                  ),
                ),
              ),
              _MainButton(
                label: 'Расчет материалов',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MaterialsProjectsScreen()),
                ),
              ),
              _MainButton(
                label: 'Расчет отделки',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProjectsScreen(module: AppModule.finish),
                  ),
                ),
              ),
              _MainButton(
                label: 'Импорт проекта',
                onTap: () async {
                  try {
                    final p = await importProjectFile(AppScope.of(context).projects);
                    if (!mounted) return;
                    if (p == null) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        p.rooms.isEmpty
                            ? 'Импортирован «${p.name}»'
                            : 'Импортирован «${p.name}» · комнат: ${p.rooms.length}',
                      ),
                    ),
                  );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                  }
                },
              ),
              if (admin)
                _MainButton(
                  label: 'Поставщики',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SuppliersScreen()),
                    );
                    if (mounted) setState(() {});
                  },
                ),
              Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
                        .then((_) {
                      if (mounted) setState(() {});
                    });
                  },
                  onLongPress: _adminDialog,
                  child: const SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: Center(child: Text('Настройки')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainButton extends StatelessWidget {
  const _MainButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: FilledButton.tonal(
          onPressed: onTap,
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
