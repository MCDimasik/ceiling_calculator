import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../domain/cost_calculator.dart';
import '../../domain/finish_material_links.dart';
import '../../domain/money_format.dart';
import '../../domain/work_rates_catalog.dart';
import '../../domain/work_rates_lookup.dart';
import 'numeric_input.dart';
import 'work_rate_catalog_picker.dart';

/// Compact price + catalog picker for finish / prep layer dialogs.
///
/// When [onMaterialsChanged] is set, shows optional material rows under the
/// work price (same place everywhere we set a rate on a layer / covering).
class LayerPriceFields extends StatelessWidget {
  const LayerPriceFields({
    super.key,
    required this.priceCtrl,
    required this.section,
    required this.suggestName,
    this.onChanged,
    this.priceUnitLabel = '₽/м²',
    this.catalogToStoredPrice,
    this.materials = const [],
    this.onMaterialsChanged,
    this.layerKindId,
  });

  final TextEditingController priceCtrl;
  final String section;
  final String suggestName;
  final VoidCallback? onChanged;

  /// e.g. `₽/м²` or `₽/м³` for volumetric screed.
  final String priceUnitLabel;

  /// Optional: convert catalog unit price before writing into [priceCtrl]
  /// (catalog screed is often ₽/м² while the field stores ₽/м³).
  final double Function(double catalogPrice)? catalogToStoredPrice;

  final List<FinishMaterialLink> materials;
  final ValueChanged<List<FinishMaterialLink>>? onMaterialsChanged;

  /// Finish / prep / covering kind id — used to surface matching mount kits first.
  final String? layerKindId;

  Future<void> _pick(BuildContext context) async {
    final picked = await showWorkRateCatalogPicker(context, section: section);
    if (picked == null) return;
    if (picked.unitPrice > 0) {
      final raw = catalogToStoredPrice?.call(picked.unitPrice) ?? picked.unitPrice;
      priceCtrl.text = raw.toStringAsFixed(0);
    }
    onChanged?.call();
  }

  Future<void> _suggest(BuildContext context) async {
    final cats = await WorkRatesCatalogStore.ensureLoaded();
    final hit = matchWorkRateItem(
      name: suggestName,
      section: section,
      categories: cats,
    );
    if (hit == null || hit.unitPrice <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('В каталоге нет подходящей позиции')),
        );
      }
      return;
    }
    final raw = catalogToStoredPrice?.call(hit.unitPrice) ?? hit.unitPrice;
    priceCtrl.text = raw.toStringAsFixed(0);
    onChanged?.call();
  }

  void _emitMaterials(List<FinishMaterialLink> next) {
    onMaterialsChanged?.call(next);
    onChanged?.call();
  }

  Future<void> _addMaterial(BuildContext context) async {
    final picked = await showSupplierMaterialPicker(context);
    if (picked == null) return;
    final next = [
      ...materials,
      FinishMaterialLink(
        itemKey: picked.itemKey,
        productName: picked.productName,
        qtyPerUnit: 1,
        unit: 'м²',
      ),
    ];
    _emitMaterials(next);
  }

  void _applyKitItems(FinishMountKit kit) {
    final next = [
      ...materials,
      for (final i in kit.items) i.copy(),
    ];
    _emitMaterials(next);
  }

  Future<void> _applyKit(BuildContext context) async {
    final kits = kitsForLayer(
      all: await loadMountKits(),
      section: section,
      layerKindId: layerKindId,
    );
    if (kits.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет сохранённых комплектов')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final chosen = await showModalBottomSheet<FinishMountKit>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Комплект материалов'),
              subtitle: Text('Сначала — для этого слоя, затем общие'),
            ),
            for (final k in kits)
              ListTile(
                title: Text(k.name),
                subtitle: Text(
                  '${k.items.length} поз. · '
                  '${mountKitLayerKindLabel(k.section, k.layerKind)}',
                ),
                onTap: () => Navigator.pop(ctx, k),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    _applyKitItems(chosen);
  }

  Future<void> _saveKit(BuildContext context) async {
    if (materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала добавьте материалы')),
      );
      return;
    }
    final nameCtrl = TextEditingController(text: suggestName);
    var bindLayer = (layerKindId ?? '').trim().isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Сохранить комплект'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  border: OutlineInputBorder(),
                ),
              ),
              if ((layerKindId ?? '').trim().isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Привязать к этому типу слоя'),
                  subtitle: Text(
                    mountKitLayerKindLabel(section, layerKindId ?? ''),
                  ),
                  value: bindLayer,
                  onChanged: (v) => setLocal(() => bindLayer = v),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || name.isEmpty) return;
    final kind = bindLayer ? (layerKindId ?? '').trim() : '';
    await upsertMountKit(FinishMountKit(
      id: newMountKitId(),
      name: name,
      section: section,
      layerKind: kind,
      items: [for (final m in materials) m.copy()],
    ));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Комплект «$name» сохранён')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showMats = onMaterialsChanged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        TextField(
          controller: priceCtrl,
          keyboardType: NumericInput.decimalKeyboard,
          decoration: InputDecoration(
            labelText: 'Цена работ, $priceUnitLabel',
            isDense: true,
            border: const OutlineInputBorder(),
            helperText: priceCtrl.text.trim().isEmpty
                ? 'Необязательно · из каталога или вручную'
                : null,
            suffixIcon: IconButton(
              tooltip: 'Из каталога',
              onPressed: () => _pick(context),
              icon: const Icon(Icons.menu_book_outlined),
            ),
          ),
          onChanged: (_) => onChanged?.call(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => _suggest(context),
            child: const Text('Подставить из каталога'),
          ),
        ),
        if (showMats) ...[
          const SizedBox(height: 4),
          Text(
            'Материалы (опционально)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Сначала комплекты для слоя, иначе свой набор · расход на 1 м²',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<FinishMountKit>>(
            future: loadMountKits(),
            builder: (context, snap) {
              final preferred = kitsForLayer(
                all: snap.data ?? const [],
                section: section,
                layerKindId: layerKindId,
              ).where((k) => k.hasLayerKind).take(6).toList();
              if (preferred.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in preferred)
                      ActionChip(
                        avatar: const Icon(Icons.widgets_outlined, size: 16),
                        label: Text(k.name),
                        onPressed: () => _applyKitItems(k),
                      ),
                  ],
                ),
              );
            },
          ),
          for (var i = 0; i < materials.length; i++)
            _MaterialLinkRow(
              link: materials[i],
              onChanged: (updated) {
                final next = [...materials];
                next[i] = updated;
                _emitMaterials(next);
              },
              onRemove: () {
                final next = [...materials]..removeAt(i);
                _emitMaterials(next);
              },
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _addMaterial(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Свой материал'),
              ),
              TextButton(
                onPressed: () => _applyKit(context),
                child: const Text('Все комплекты'),
              ),
              if (materials.isNotEmpty)
                TextButton(
                  onPressed: () => _saveKit(context),
                  child: const Text('Сохранить комплект'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MaterialLinkRow extends StatelessWidget {
  const _MaterialLinkRow({
    required this.link,
    required this.onChanged,
    required this.onRemove,
  });

  final FinishMaterialLink link;
  final ValueChanged<FinishMaterialLink> onChanged;
  final VoidCallback onRemove;

  static const _units = ['м²', 'кг', 'л', 'шт', 'п.м.', 'м³'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Материал',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              child: Text(
                link.productName.isEmpty ? link.itemKey : link.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: TextFormField(
              initialValue: link.qtyPerUnit == link.qtyPerUnit.roundToDouble()
                  ? link.qtyPerUnit.round().toString()
                  : link.qtyPerUnit.toStringAsFixed(2),
              keyboardType: NumericInput.decimalKeyboard,
              inputFormatters: NumericInput.decimalFormatters,
              decoration: const InputDecoration(
                labelText: 'Расход',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                final q = double.tryParse(v.replaceAll(',', '.')) ?? 1;
                onChanged(FinishMaterialLink(
                  itemKey: link.itemKey,
                  productName: link.productName,
                  qtyPerUnit: q <= 0 ? 1 : q,
                  unit: link.unit,
                ));
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: DropdownButtonFormField<String>(
              initialValue: _units.contains(link.unit) ? link.unit : 'м²',
              decoration: const InputDecoration(
                labelText: 'Ед.',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final u in _units)
                  DropdownMenuItem(value: u, child: Text(u)),
              ],
              onChanged: (u) {
                if (u == null) return;
                onChanged(FinishMaterialLink(
                  itemKey: link.itemKey,
                  productName: link.productName,
                  qtyPerUnit: link.qtyPerUnit,
                  unit: u,
                ));
              },
            ),
          ),
          IconButton(
            tooltip: 'Убрать',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Pick a material from supplier price lists (deduped by itemKey).
Future<({String itemKey, String productName})?> showSupplierMaterialPicker(
  BuildContext context,
) async {
  final scope = AppScope.of(context);
  final suppliers = await scope.suppliers.listSuppliers();
  final byKey = <String, SupplierPrice>{};
  for (final s in suppliers) {
    if (s.id == null) continue;
    final prices = await scope.suppliers.listPrices(s.id!);
    for (final p in prices) {
      if (p.itemKey.isEmpty) continue;
      byKey.putIfAbsent(p.itemKey, () => p);
    }
  }
  final all = byKey.values.toList()
    ..sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));

  if (!context.mounted) return null;

  if (all.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет позиций в прайсах поставщиков')),
    );
    return null;
  }

  var query = '';
  return showModalBottomSheet<({String itemKey, String productName})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? all
              : all
                  .where(
                    (p) =>
                        p.productName.toLowerCase().contains(q) ||
                        p.itemKey.toLowerCase().contains(q),
                  )
                  .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Поиск материала',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setLocal(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        return ListTile(
                          title: Text(p.productName),
                          subtitle: Text(p.itemKey),
                          onTap: () => Navigator.pop(ctx, (
                            itemKey: p.itemKey,
                            productName: p.productName,
                          )),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Dialog: set one unit price on many layers (all or selected).
Future<double?> showBulkLayerPriceDialog(
  BuildContext context, {
  required String title,
  required String section,
  String priceUnitLabel = '₽/м²',
  double Function(double catalogPrice)? catalogToStoredPrice,
}) async {
  final priceCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceCtrl,
              keyboardType: NumericInput.decimalKeyboard,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Цена, $priceUnitLabel',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final picked =
                    await showWorkRateCatalogPicker(ctx, section: section);
                if (picked == null) return;
                setLocal(() {
                  if (picked.unitPrice > 0) {
                    final raw = catalogToStoredPrice?.call(picked.unitPrice) ??
                        picked.unitPrice;
                    priceCtrl.text = raw.toStringAsFixed(0);
                  }
                });
              },
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Из каталога'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    ),
  );
  final v = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
  priceCtrl.dispose();
  if (ok != true || v == null || v < 0) return null;
  return v;
}

String layerPriceSubtitle(double? unitPrice) {
  if (unitPrice == null || unitPrice <= 0) return '';
  return formatRub(unitPrice);
}
