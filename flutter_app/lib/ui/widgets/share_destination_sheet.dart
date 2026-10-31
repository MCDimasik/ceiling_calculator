import 'package:flutter/material.dart';

/// Where to send a project / rooms export.
enum ShareDestination { file, inApp }

/// Aesthetic chooser: system file share vs in-app inbox sync.
Future<ShareDestination?> showShareDestinationSheet(
  BuildContext context, {
  required String headline,
  String? detail,
}) {
  return showModalBottomSheet<ShareDestination>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Поделиться',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              headline,
              style: Theme.of(ctx).textTheme.titleSmall,
            ),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                detail,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            _ShareOptionCard(
              icon: Icons.ios_share_outlined,
              title: 'Файлом',
              subtitle: 'Мессенджер, почта, диск и другие приложения',
              accent: scheme.secondaryContainer,
              accentFg: scheme.onSecondaryContainer,
              onTap: () => Navigator.pop(ctx, ShareDestination.file),
            ),
            const SizedBox(height: 10),
            _ShareOptionCard(
              icon: Icons.mark_email_unread_outlined,
              title: 'В приложении',
              subtitle: 'Коллегам во «Входящие» через синхронизацию',
              accent: scheme.primaryContainer,
              accentFg: scheme.onPrimaryContainer,
              onTap: () => Navigator.pop(ctx, ShareDestination.inApp),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
          ],
        ),
      );
    },
  );
}

class _ShareOptionCard extends StatelessWidget {
  const _ShareOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.accentFg,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color accentFg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: accent,
                foregroundColor: accentFg,
                child: Icon(icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
