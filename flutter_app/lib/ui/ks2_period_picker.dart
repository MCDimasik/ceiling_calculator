import 'package:flutter/material.dart';

Future<(DateTime from, DateTime to)?> pickKs3PeriodRange(
  BuildContext context, {
  DateTime? initialFrom,
  DateTime? initialTo,
}) async {
  var from = initialFrom ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
  var to = initialTo ?? DateTime.now();

  return showDialog<(DateTime, DateTime)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Период КС-3'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('С'),
              subtitle: Text(_fmt(from)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: from,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setLocal(() => from = d);
              },
            ),
            ListTile(
              title: const Text('По'),
              subtitle: Text(_fmt(to)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: to.isBefore(from) ? from : to,
                  firstDate: from,
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setLocal(() => to = d);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              (
                DateTime(from.year, from.month, from.day),
                DateTime(to.year, to.month, to.day),
              ),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
