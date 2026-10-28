import 'package:flutter/material.dart';

import '../domain/finish_material_links.dart';
import 'widgets/layer_price_fields.dart' show showSupplierMaterialPicker;
import 'widgets/numeric_input.dart';
import 'widgets/screen_scaffold.dart';

/// Расценки → Материалы → комплекты (привязка к типу слоя).
class MountKitsScreen extends StatefulWidget {
  const MountKitsScreen({super.key});

  @override
  State<MountKitsScreen> createState() => _MountKitsScreenState();
}

class _MountKitsScreenState extends State<MountKitsScreen> {
  List<FinishMountKit> _kits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final list = await loadMountKits();
    if (!mounted) return;
    setState(() {
      _kits = list;
      _loading = false;
    });
  }

  Future<void> _edit({FinishMountKit? existing}) async {
    final result = await showDialog<FinishMountKit>(
      context: context,
      builder: (ctx) => _MountKitEditorDialog(existing: existing),
    );
    if (result == null) return;
    await upsertMountKit(result);
    await _reload();
  }

  Future<void> _delete(FinishMountKit kit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить комплект?'),
        content: Text('«${kit.name}» будет удалён.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await deleteMountKit(kit.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      appBar: AppBar(title: const Text('Комплекты материалов')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Комплект'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _kits.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Создайте комплект и привяжите к типу слоя '
                      '(краска, стяжка…). В диалоге слоя комплекты появятся первыми.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: _kits.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final k = _kits[i];
                    final layer = mountKitLayerKindLabel(k.section, k.layerKind);
                    return Card(
                      child: ListTile(
                        title: Text(k.name),
                        subtitle: Text(
                          '${mountKitSectionLabel(k.section)} · $layer · '
                          '${k.items.length} поз.',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _edit(existing: k);
                            if (v == 'delete') _delete(k);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Изменить')),
                            PopupMenuItem(value: 'delete', child: Text('Удалить')),
                          ],
                        ),
                        onTap: () => _edit(existing: k),
                      ),
                    );
                  },
                ),
    );
  }
}

class _MountKitEditorDialog extends StatefulWidget {
  const _MountKitEditorDialog({this.existing});

  final FinishMountKit? existing;

  @override
  State<_MountKitEditorDialog> createState() => _MountKitEditorDialogState();
}

class _MountKitEditorDialogState extends State<_MountKitEditorDialog> {
  late final TextEditingController _nameCtrl;
  late String _section;
  late String _layerKind;
  late List<FinishMaterialLink> _items;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _section = e?.section ?? 'walls';
    if (_section != 'walls' &&
        _section != 'floor' &&
        _section != 'ceiling' &&
        _section != 'any') {
      _section = 'walls';
    }
    _layerKind = (e?.layerKind.trim().isNotEmpty == true) ? e!.layerKind : 'any';
    _items = [for (final m in e?.items ?? const <FinishMaterialLink>[]) m.copy()];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final picked = await showSupplierMaterialPicker(context);
    if (picked == null) return;
    setState(() {
      _items.add(FinishMaterialLink(
        itemKey: picked.itemKey,
        productName: picked.productName,
        qtyPerUnit: 1,
        unit: 'м²',
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final layerOpts = mountKitLayerKindOptions(_section);
    final layerValue =
        layerOpts.any((o) => o.id == _layerKind) ? _layerKind : 'any';
    return AlertDialog(
      title: Text(widget.existing == null ? 'Новый комплект' : 'Комплект'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _section,
                decoration: const InputDecoration(
                  labelText: 'Раздел',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'walls', child: Text('Стены')),
                  DropdownMenuItem(value: 'floor', child: Text('Пол')),
                  DropdownMenuItem(value: 'ceiling', child: Text('Потолок')),
                  DropdownMenuItem(value: 'any', child: Text('Любой')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _section = v;
                    _layerKind = 'any';
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: layerValue,
                decoration: const InputDecoration(
                  labelText: 'Тип слоя',
                  border: OutlineInputBorder(),
                  isDense: true,
                  helperText: 'В диалоге этого слоя комплект будет первым',
                ),
                items: [
                  for (final o in layerOpts)
                    DropdownMenuItem(value: o.id, child: Text(o.label)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _layerKind = v);
                },
              ),
              const SizedBox(height: 12),
              Text('Позиции', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (var i = 0; i < _items.length; i++)
                _KitItemRow(
                  link: _items[i],
                  onChanged: (u) => setState(() => _items[i] = u),
                  onRemove: () => setState(() => _items.removeAt(i)),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Материал из прайса'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Укажите название')),
              );
              return;
            }
            if (_items.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Добавьте хотя бы один материал')),
              );
              return;
            }
            final kind =
                layerOpts.any((o) => o.id == _layerKind) ? _layerKind : 'any';
            Navigator.pop(
              context,
              FinishMountKit(
                id: widget.existing?.id ?? newMountKitId(),
                name: name,
                section: _section,
                layerKind: kind == 'any' ? '' : kind,
                items: [for (final m in _items) m.copy()],
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _KitItemRow extends StatelessWidget {
  const _KitItemRow({
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
              // ignore: deprecated_member_use
              value: _units.contains(link.unit) ? link.unit : 'м²',
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
