import 'package:flutter/material.dart';

/// Non-standard finish spaces (no floor plan).
enum AddSpaceChoice {
  volume,
  stairwell,
}

/// Bottom sheet: объём без чертежа · лестничная клетка.
Future<AddSpaceChoice?> showAddSpaceSheet(BuildContext context) {
  return showModalBottomSheet<AddSpaceChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Нестандартное помещение', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Без чертежа — вводите то, что уже есть на объекте или в смете.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.square_foot_outlined),
                title: const Text('Объём без чертежа'),
                subtitle: const Text('Уже знаете м² стен / пола / потолка'),
                onTap: () => Navigator.pop(ctx, AddSpaceChoice.volume),
              ),
              ListTile(
                leading: const Icon(Icons.stairs_outlined),
                title: const Text('Лестничная клетка'),
                subtitle: const Text('П-образная или прямая · Ш×Д · В'),
                onTap: () => Navigator.pop(ctx, AddSpaceChoice.stairwell),
              ),
            ],
          ),
        ),
      );
    },
  );
}
