import 'package:flutter/material.dart';

import '../../domain/money_format.dart';
import '../../domain/work_rates_catalog.dart';
import '../../domain/work_rates_lookup.dart';

/// Bottom sheet: pick a work rate from the global catalog (search + categories).
///
/// [section] filters/sorts by domain (`floor` / `walls` / `ceiling` / finish_* keys).
Future<WorkRateItem?> showWorkRateCatalogPicker(
  BuildContext context, {
  String section = '',
}) async {
  final categories = await WorkRatesCatalogStore.ensureLoaded();
  if (!context.mounted) return null;
  return showModalBottomSheet<WorkRateItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _WorkRateCatalogPickerSheet(
      categories: categories,
      section: section,
    ),
  );
}

class _WorkRateCatalogPickerSheet extends StatefulWidget {
  const _WorkRateCatalogPickerSheet({
    required this.categories,
    this.section = '',
  });

  final List<WorkRateCategory> categories;
  final String section;

  @override
  State<_WorkRateCatalogPickerSheet> createState() =>
      _WorkRateCatalogPickerSheetState();
}

class _WorkRateCatalogPickerSheetState extends State<_WorkRateCatalogPickerSheet> {
  String _query = '';
  bool _showAll = false;

  List<WorkRateHit> get _hits {
    final ranked = rankWorkRatesForSection(
      widget.categories,
      section: widget.section,
    );
    final q = _query.trim().toLowerCase();
    var list = ranked;
    if (!_showAll && widget.section.trim().isNotEmpty) {
      final relevant = list.where((h) => h.sectionRelevant).toList();
      if (relevant.isNotEmpty) list = relevant;
    }
    if (q.isEmpty) return list;
    return list
        .where(
          (h) =>
              h.item.name.toLowerCase().contains(q) ||
              h.category.name.toLowerCase().contains(q) ||
              h.item.matchKey.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final hasSection = widget.section.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Каталог работ',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Поиск',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (hasSection)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(_showAll ? 'Только подходящие' : 'Показать все'),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: hits.isEmpty
                  ? const Center(child: Text('Ничего не найдено'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      itemCount: hits.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final h = hits[i];
                        final price = h.item.unitPrice;
                        return ListTile(
                          title: Text(h.item.name, maxLines: 3),
                          subtitle: Text(
                            h.sectionRelevant || !hasSection
                                ? h.category.name
                                : '${h.category.name} · другая категория',
                          ),
                          trailing: Text(
                            price > 0
                                ? '${formatMoney(price)} ₽/${h.item.unit}'
                                : '—',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () => Navigator.pop(context, h.item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
