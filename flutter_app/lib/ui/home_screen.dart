import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_model.dart';
import '../domain/project_transfer.dart';
import 'documentation_flow_screens.dart';
import 'materials_flow_screens.dart';
import 'pricing_hub_screen.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';
import 'widgets/app_background.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
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
                label: 'Расчет материалов потолка',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProjectsScreen(
                      materialsCalcMode: MaterialsCalcMode.ceiling,
                    ),
                  ),
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
                label: 'Документация · отделка',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DocumentationProjectsScreen(),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
                  }
                },
              ),
              _MainButton(
                label: 'Расценки',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PricingHubScreen(),
                    ),
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
