import 'package:flutter/material.dart';

import 'mount_kits_screen.dart';
import 'suppliers_screen.dart';
import 'work_rates_screen.dart';
import 'widgets/screen_scaffold.dart';

/// Главное меню → Расценки: работы и материалы.
class PricingHubScreen extends StatelessWidget {
  const PricingHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      appBar: AppBar(title: const Text('Расценки')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        children: [
          Text(
            'Цены для смет, КС и КП',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Работы — услуги и м² отделки. Материалы — прайс поставщиков '
            '(плиты, профили, расходники).',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 28),
          _HubButton(
            icon: Icons.handyman_outlined,
            label: 'Работа',
            subtitle: 'Расценки услуг и отделки',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WorkRatesScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _HubButton(
            icon: Icons.inventory_2_outlined,
            label: 'Материалы',
            subtitle: 'Поставщики и цены закупки / клиент',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SuppliersScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _HubButton(
            icon: Icons.widgets_outlined,
            label: 'Комплекты',
            subtitle: 'Наборы материалов · привязка к типу слоя',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MountKitsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HubButton extends StatelessWidget {
  const _HubButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
            children: [
              Icon(icon, size: 32, color: scheme.onPrimaryContainer),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.85),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
