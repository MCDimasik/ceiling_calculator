import 'package:flutter/material.dart';

import '../domain/documentation_model.dart';
import '../domain/project_doc_import.dart';

/// Human-readable before/after for import confirmation.
String formatProjectDocumentImportDiff({
  required ProjectDocumentation before,
  required ParsedProjectDocument parsed,
}) {
  final buf = StringBuffer();
  void line(String label, String oldV, String newV) {
    if (newV.isEmpty) return;
    if (oldV == newV) {
      buf.writeln('• $label: $newV');
    } else {
      buf.writeln('• $label: ${oldV.isEmpty ? '—' : oldV} → $newV');
    }
  }

  line('Заказчик', before.stamp.customer, parsed.customer);
  line('Исполнитель', before.stamp.executor, parsed.executor);
  line('Объект', before.stamp.objectName, parsed.objectName);
  line('Договор', before.contract.contractNumber, parsed.contractNumber);
  line('Смета', before.contract.estimateNumber, parsed.estimateNumber);
  if (parsed.hasPrices) {
    buf.writeln(
      '• Расценок: было ${before.ks2Prices.length} → станет ${parsed.prices.length}',
    );
  }
  return buf.toString().trim();
}

/// Pick file, preview adaptive parse result, apply to project documentation.
Future<bool> runProjectDocumentImportFlow(
  BuildContext context, {
  required ProjectDocumentation doc,
  required Future<void> Function(ProjectDocumentation updated) onSave,
}) async {
  final result = await parsePickedProjectDocument();
  final parsed = result.parsed;
  final filename = result.filename;
  if (filename == null) return false;

  if (parsed.warning.isNotEmpty) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(parsed.warning)),
    );
    return false;
  }

  if (!parsed.hasStampFields && !parsed.hasPrices) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Не удалось извлечь данные. Попробуйте Excel, Word, CSV или PDF.',
        ),
      ),
    );
    return false;
  }

  if (!context.mounted) return false;
  final diff = formatProjectDocumentImportDiff(before: doc, parsed: parsed);
  final apply = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Импорт · $filename'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (result.meta.formatName.isNotEmpty)
                Text(
                  'Формат: ${result.meta.formatName}'
                  '${result.meta.formatScore > 0 ? ' (${result.meta.formatScore})' : ''}',
                  style: Theme.of(ctx).textTheme.labelLarge,
                ),
              if (diff.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Изменения', style: Theme.of(ctx).textTheme.titleSmall),
                Text(diff, style: Theme.of(ctx).textTheme.bodySmall),
              ],
              if (result.meta.unmatchedRows.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Без цены / без ключа (${result.meta.unmatchedRows.length}):',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in result.meta.unmatchedRows)
                        Text('• $u', style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(
                  'Строки без цены не попадут в расценки — поправьте Excel или добавьте вручную.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Применить')),
      ],
    ),
  );
  if (apply != true) return false;

  final updated = applyParsedProjectDocument(doc, parsed);
  await onSave(updated);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Данные объекта обновлены')),
    );
  }
  return true;
}
