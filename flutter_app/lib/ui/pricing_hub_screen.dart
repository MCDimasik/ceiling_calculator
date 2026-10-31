import 'package:flutter/material.dart';

import 'adaptive_layout.dart';
import 'desktop_cascade.dart';
import 'mount_kits_screen.dart';
import 'suppliers_screen.dart';
import 'work_rates_screen.dart';
import 'widgets/cascade_pane_toolbar.dart';
import 'widgets/screen_scaffold.dart';

/// Главное меню → Расценки: работы и материалы.
class PricingHubScreen extends StatelessWidget {
  const PricingHubScreen({
    super.key,
    this.cascadeMode = false,
  });

  final bool cascadeMode;

  void _open(
    BuildContext context, {
    required Widget page,
    required String title,
    required String detailId,
  }) {
    final cascade = cascadeMode ? DesktopCascadeHost.maybeOf(context) : null;
    if (cascade != null) {
      cascade.openDetail(page, title: title, detailId: detailId);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final desktop = DesktopMetrics.of(context);
    final items = [
      (
        Icons.handyman_outlined,
        'Работа',
        'Расценки услуг и отделки',
        () => _open(
              context,
              page: const WorkRatesScreen(),
              title: 'Работа',
              detailId: 'pricing:work',
            ),
      ),
      (
        Icons.inventory_2_outlined,
        'Материалы',
        'Поставщики и цены закупки / клиент',
        () => _open(
              context,
              page: const SuppliersScreen(),
              title: 'Материалы',
              detailId: 'pricing:mat',
            ),
      ),
      (
        Icons.widgets_outlined,
        'Комплекты',
        'Наборы материалов · привязка к типу слоя',
        () => _open(
              context,
              page: const MountKitsScreen(),
              title: 'Комплекты',
              detailId: 'pricing:kits',
            ),
      ),
    ];

    final body = ListView(
      padding: EdgeInsets.fromLTRB(
        cascadeMode ? 12 : (desktop ? 8 : 24),
        cascadeMode ? 12 : (desktop ? 20 : 24),
        cascadeMode ? 12 : (desktop ? 8 : 24),
        32,
      ),
      children: [
        if (!cascadeMode) ...[
          Text(
            'Цены для смет, КС и КП',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'Работы — услуги и м² отделки. Материалы — прайс поставщиков '
            '(плиты, профили, расходники).',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 28),
        ],
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: cascadeMode ? 8 : 14),
          _HubButton(
            icon: items[i].$1,
            label: items[i].$2,
            subtitle: items[i].$3,
            compact: cascadeMode,
            selected: cascadeMode &&
                DesktopCascadeHost.maybeOf(context)?.detailId ==
                    'pricing:${i == 0 ? 'work' : i == 1 ? 'mat' : 'kits'}',
            onTap: items[i].$4,
          ),
        ],
      ],
    );

    return ScreenScaffold(
      appBar: cascadeMode
          ? const CascadePaneToolbar(
              title: 'Расценки',
              subtitle: 'Работы · материалы · комплекты',
            )
          : AppBar(title: const Text('Расценки')),
      embeddedMaxWidth: cascadeMode
          ? AdaptiveBreakpoints.paneReadableMax
          : AdaptiveBreakpoints.paneReadableWide,
      body: body,
    );
  }
}

class _HubButton extends StatelessWidget {
  const _HubButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.compact = false,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool compact;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (compact) {
      return Card(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.85)
            : null,
        child: ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Icon(icon, size: 22),
          ),
          title: Text(label, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(subtitle, maxLines: 2),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
    }
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Row(
            children: [
              Icon(icon, size: 40, color: scheme.onPrimaryContainer),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 24,
                            color: scheme.onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.85),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 28,
                color: scheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
