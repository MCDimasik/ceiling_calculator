import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/cost_calculator.dart';
import '../domain/material_catalog.dart';
import '../domain/money_format.dart';
import '../domain/user_product_aliases.dart';
import 'widgets/numeric_input.dart';

class SupplierEditScreen extends StatefulWidget {
  const SupplierEditScreen({
    super.key,
    required this.supplierId,
    required this.name,
  });

  final int supplierId;
  final String name;

  @override
  State<SupplierEditScreen> createState() => _SupplierEditScreenState();
}

class _SupplierEditScreenState extends State<SupplierEditScreen> {
  late TextEditingController _nameCtrl;
  late String _savedName;
  List<SupplierPrice> _prices = [];
  bool _loading = true;
  String _query = '';
  bool _selectMode = false;
  final Set<String> _selectedKeys = {};

  @override
  void initState() {
    super.initState();
    _savedName = widget.name;
    _nameCtrl = TextEditingController(text: widget.name);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await AppScope.of(context).suppliers.listPrices(widget.supplierId);
    if (!mounted) return;
    setState(() {
      _prices = list;
      _loading = false;
    });
  }

  Future<void> _saveName() async {
    final n = _nameCtrl.text.trim();
    if (n.isEmpty) return;
    await AppScope.of(context).suppliers.renameSupplier(widget.supplierId, n);
    if (!mounted) return;
    setState(() => _savedName = n);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
  }

  bool get _nameDirty => _nameCtrl.text.trim() != _savedName;

  Future<bool> _leaveEditor() async {
    if (!_nameDirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сохранить имя?'),
        content: const Text('Имя поставщика изменено.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Остаться')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Не сохранять')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Сохранить')),
        ],
      ),
    );
    if (choice == null || choice == 'cancel' || !mounted) return false;
    if (choice == 'save') await _saveName();
    return true;
  }

  Future<void> _addPosition() async {
    final existing = _prices.map((p) => p.itemKey).toSet();
    final groups = catalogProductGroups();
    final missingCatalog = <CatalogEntry>[
      for (final g in groups)
        for (final v in g.variants)
          if (!existing.contains(v.itemKey)) v,
    ];

    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (_, controller) {
            return ListView(
              controller: controller,
              children: [
                const ListTile(title: Text('Добавить позицию')),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Своё название…'),
                  subtitle: const Text('Материал из чека / вне каталога'),
                  onTap: () => Navigator.pop(ctx, 'custom'),
                ),
                if (missingCatalog.isEmpty)
                  const ListTile(
                    title: Text('Все позиции каталога уже в списке'),
                    subtitle: Text('Можно добавить своё название или объединить дубли'),
                  )
                else
                  for (final v in missingCatalog)
                    ListTile(
                      title: Text(v.displayName),
                      subtitle: Text(v.calcMatchKey),
                      onTap: () => Navigator.pop(ctx, v),
                    ),
              ],
            );
          },
        );
      },
    );
    if (choice == null || !mounted) return;

    if (choice == 'custom') {
      final nameCtrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Новая позиция'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Название материала',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Добавить'),
            ),
          ],
        ),
      );
      final name = nameCtrl.text.trim();
      if (ok != true || name.isEmpty || !mounted) return;
      final key = customItemKeyForLabel(name);
      await AppScope.of(context).suppliers.upsertPrice(
            widget.supplierId,
            SupplierPrice(itemKey: key, productName: name),
          );
      final aliases = await UserProductAliasStore.load();
      await aliases.bindLabels([name], key);
      await _reload();
      return;
    }

    if (choice is CatalogEntry) {
      await unhideItemKey(widget.supplierId, choice.itemKey);
      await AppScope.of(context).suppliers.upsertPrice(
            widget.supplierId,
            SupplierPrice(
              itemKey: choice.itemKey,
              productName: choice.displayName,
              unitsPerPack: defaultUnitsPerPack(choice.itemKey).toDouble(),
            ),
          );
      await _reload();
    }
  }

  Future<void> _edit(SupplierPrice p) async {
    final costCtrl = TextEditingController(text: p.unitPriceCost > 0 ? p.unitPriceCost.toString() : '');
    final clientCtrl = TextEditingController(text: p.unitPriceClient > 0 ? p.unitPriceClient.toString() : '');
    final packCtrl = TextEditingController(text: p.unitsPerPack.toString());
    final nameCtrl = TextEditingController(text: p.productName);
    final skuCtrl = TextEditingController(text: p.supplierSku);
    var receiptUnit = p.receiptUnit;
    final ok = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(p.itemKey),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  keyboardType: NumericInput.textKeyboard,
                  decoration: const InputDecoration(labelText: 'Имя:'),
                ),
                TextField(
                  controller: skuCtrl,
                  keyboardType: NumericInput.textKeyboard,
                  decoration: const InputDecoration(labelText: 'SKU / артикул'),
                ),
                TextField(
                  controller: costCtrl,
                  decoration: InputDecoration(
                    labelText:
                        receiptUnit == 'pack' ? 'Закуп, ₽/уп' : 'Закуп, ₽/шт',
                    helperText: () {
                      final v =
                          double.tryParse(costCtrl.text.replaceAll(',', '.'));
                      if (v == null || v <= 0) return null;
                      return formatRub(v);
                    }(),
                  ),
                  keyboardType: NumericInput.decimalKeyboard,
                  inputFormatters: NumericInput.decimalFormatters,
                  onChanged: (_) => setLocal(() {}),
                ),
                TextField(
                  controller: clientCtrl,
                  decoration: InputDecoration(
                    labelText: receiptUnit == 'pack'
                        ? 'Клиент, ₽/уп'
                        : 'Клиент, ₽/шт',
                    helperText: () {
                      final v =
                          double.tryParse(clientCtrl.text.replaceAll(',', '.'));
                      if (v == null || v <= 0) return null;
                      return formatRub(v);
                    }(),
                  ),
                  keyboardType: NumericInput.decimalKeyboard,
                  inputFormatters: NumericInput.decimalFormatters,
                  onChanged: (_) => setLocal(() {}),
                ),
                TextField(
                  controller: packCtrl,
                  decoration: const InputDecoration(labelText: 'Штук в упаковке'),
                  keyboardType: NumericInput.integerKeyboard,
                  inputFormatters: NumericInput.integerFormatters,
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'piece', label: Text('за шт')),
                    ButtonSegment(value: 'pack', label: Text('за уп')),
                  ],
                  selected: {receiptUnit == 'pack' ? 'pack' : 'piece'},
                  onSelectionChanged: (s) => setLocal(() => receiptUnit = s.first),
                ),
                TextButton(
                  onPressed: () {
                    final c = double.tryParse(costCtrl.text.replaceAll(',', '.')) ?? 0;
                    if (c > 0) {
                      clientCtrl.text = (c * 1.1).toStringAsFixed(2);
                      setLocal(() {});
                    }
                  },
                  child: const Text('+10% к закупке → клиент'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Удалить')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (ok == 'delete') {
      await AppScope.of(context).suppliers.deletePrice(widget.supplierId, p.itemKey);
      await _reload();
      return;
    }
    if (ok != 'save') return;
    var cost = double.tryParse(costCtrl.text.replaceAll(',', '.')) ?? 0;
    var client = double.tryParse(clientCtrl.text.replaceAll(',', '.')) ?? 0;
    final upp = double.tryParse(packCtrl.text.replaceAll(',', '.')) ?? 1;
    if (receiptUnit == 'pack' && upp > 1) {
      if (cost > 0) cost = double.parse((cost / upp).toStringAsFixed(4));
      if (client > 0) client = double.parse((client / upp).toStringAsFixed(4));
    }
    p.productName = nameCtrl.text.trim().isEmpty ? p.productName : nameCtrl.text.trim();
    p.supplierSku = skuCtrl.text.trim();
    p.unitPriceCost = cost;
    p.unitPriceClient = client <= 0 && cost > 0 ? double.parse((cost * 1.1).toStringAsFixed(2)) : client;
    p.unitsPerPack = upp;
    p.receiptUnit = receiptUnit;
    await AppScope.of(context).suppliers.upsertPrice(widget.supplierId, p);
    await _reload();
  }

  List<SupplierPrice> get _visiblePrices {
    return _prices.where((p) {
      if (_query.isEmpty) return true;
      final hay = '${p.productName} ${p.itemKey} ${p.supplierSku}'.toLowerCase();
      return hay.contains(_query);
    }).toList();
  }

  void _toggleSelect(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  Future<void> _mergeSelected() async {
    final selected = _prices.where((p) => _selectedKeys.contains(p.itemKey)).toList();
    if (selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите минимум 2 позиции')),
      );
      return;
    }

    var keeperKey = selected.first.itemKey;
    var nameChoice = selected.first.productName;
    final customCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Объединить позиции'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Оставить как основную (цены и каталог):',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final p in selected)
                  RadioListTile<String>(
                    dense: true,
                    title: Text(p.productName),
                    subtitle: Text(p.itemKey),
                    value: p.itemKey,
                    groupValue: keeperKey,
                    onChanged: (v) {
                      if (v == null) return;
                      setLocal(() {
                        keeperKey = v;
                        if (customCtrl.text.trim().isEmpty) {
                          nameChoice = selected
                              .firstWhere((e) => e.itemKey == v)
                              .productName;
                        }
                      });
                    },
                  ),
                const Divider(),
                Text(
                  'Имя объединённой позиции:',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                for (final p in selected)
                  RadioListTile<String>(
                    dense: true,
                    title: Text(p.productName),
                    value: p.productName,
                    groupValue: customCtrl.text.trim().isEmpty ? nameChoice : null,
                    onChanged: (v) {
                      if (v == null) return;
                      setLocal(() {
                        nameChoice = v;
                        customCtrl.clear();
                      });
                    },
                  ),
                TextField(
                  controller: customCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Своё название',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'Старые названия из чеков запомнятся и будут '
                  'попадать в эту позицию при следующих импортах.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Объединить')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final displayName =
        customCtrl.text.trim().isNotEmpty ? customCtrl.text.trim() : nameChoice;
    final absorb = selected.map((p) => p.itemKey).toList();
    final labels = <String>[
      for (final p in selected) p.productName,
      displayName,
    ];

    try {
      await AppScope.of(context).suppliers.mergePrices(
        supplierId: widget.supplierId,
        keeperItemKey: keeperKey,
        absorbItemKeys: absorb,
        displayName: displayName,
        aliasLabels: labels,
      );
      if (!mounted) return;
      setState(() {
        _selectMode = false;
        _selectedKeys.clear();
      });
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Объединено в «$displayName»')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось объединить: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePrices;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_selectMode) {
          setState(() {
            _selectMode = false;
            _selectedKeys.clear();
          });
          return;
        }
        if (await _leaveEditor() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectMode
              ? 'Выбрано: ${_selectedKeys.length}'
              : 'Поставщик'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (_selectMode) {
                setState(() {
                  _selectMode = false;
                  _selectedKeys.clear();
                });
                return;
              }
              if (await _leaveEditor() && mounted) Navigator.pop(context);
            },
          ),
          actions: [
            if (_selectMode) ...[
              TextButton(
                onPressed: _selectedKeys.length >= 2 ? _mergeSelected : null,
                child: const Text('Объединить'),
              ),
            ] else ...[
              IconButton(
                tooltip: 'Выбрать для объединения',
                onPressed: () => setState(() {
                  _selectMode = true;
                  _selectedKeys.clear();
                }),
                icon: const Icon(Icons.merge_type),
              ),
              TextButton(onPressed: _saveName, child: const Text('Сохранить')),
            ],
          ],
        ),
        floatingActionButton: _selectMode
            ? null
            : FloatingActionButton.extended(
                onPressed: _addPosition,
                icon: const Icon(Icons.add),
                label: const Text('Добавить позицию'),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                children: [
                  if (!_selectMode) ...[
                    TextField(
                      controller: _nameCtrl,
                      keyboardType: NumericInput.textKeyboard,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Имя:',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Поиск позиции',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectMode
                        ? 'Отметьте дубли одного материала, затем «Объединить».'
                        : 'Цены закупки и клиента. Иконка объединения — слить дубли '
                            'из разных чеков (алиасы запоминаются).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  for (final p in visible)
                    Card(
                      color: _selectedKeys.contains(p.itemKey)
                          ? Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.55)
                          : null,
                      child: ListTile(
                        leading: _selectMode
                            ? Checkbox(
                                value: _selectedKeys.contains(p.itemKey),
                                onChanged: (_) => _toggleSelect(p.itemKey),
                              )
                            : null,
                        title: Text(p.productName),
                        subtitle: Text([
                          if (p.itemKey.startsWith('rx_')) 'из чека',
                          if (p.supplierSku.isNotEmpty) 'SKU ${p.supplierSku}',
                          if (p.unitPriceCost > 0)
                            'закуп ${formatRub(p.unitPriceCost)}',
                          if (p.unitPriceClient > 0)
                            'клиент ${formatRub(p.unitPriceClient)}',
                          if (p.unitsPerPack > 1)
                            'уп×${p.unitsPerPack.round()}',
                          p.receiptUnit == 'pack' ? 'за уп' : 'за шт',
                        ].join(' · ')),
                        trailing: (!_selectMode && p.unitPriceClient > 0)
                            ? Text(
                                formatRub(p.unitPriceClient),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                        onTap: () {
                          if (_selectMode) {
                            _toggleSelect(p.itemKey);
                          } else {
                            _edit(p);
                          }
                        },
                        onLongPress: () {
                          setState(() {
                            _selectMode = true;
                            _selectedKeys.add(p.itemKey);
                          });
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
