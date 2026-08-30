import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/cost_calculator.dart';
import '../domain/material_catalog.dart';
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
  List<SupplierPrice> _prices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
  }

  Future<void> _addPosition() async {
    final existing = _prices.map((p) => p.itemKey).toSet();
    final groups = catalogProductGroups();
    final choice = await showModalBottomSheet<CatalogEntry>(
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
                for (final g in groups) ...[
                  for (final v in g.variants)
                    if (!existing.contains(v.itemKey))
                      ListTile(
                        title: Text(v.displayName),
                        subtitle: Text(g.calcMatchKey),
                        onTap: () => Navigator.pop(ctx, v),
                      ),
                ],
              ],
            );
          },
        );
      },
    );
    if (choice == null) return;
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

  Future<void> _edit(SupplierPrice p) async {
    final costCtrl = TextEditingController(text: p.unitPriceCost > 0 ? p.unitPriceCost.toString() : '');
    final clientCtrl = TextEditingController(text: p.unitPriceClient > 0 ? p.unitPriceClient.toString() : '');
    final packCtrl = TextEditingController(text: p.unitsPerPack.toString());
    final nameCtrl = TextEditingController(text: p.productName);
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
                  controller: costCtrl,
                  decoration: InputDecoration(
                    labelText: receiptUnit == 'pack' ? 'Закуп, ₽/уп' : 'Закуп, ₽/шт',
                  ),
                  keyboardType: NumericInput.decimalKeyboard,
                  inputFormatters: NumericInput.decimalFormatters,
                ),
                TextField(
                  controller: clientCtrl,
                  decoration: InputDecoration(
                    labelText: receiptUnit == 'pack' ? 'Клиент, ₽/уп' : 'Клиент, ₽/шт',
                  ),
                  keyboardType: NumericInput.decimalKeyboard,
                  inputFormatters: NumericInput.decimalFormatters,
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
    p.unitPriceCost = cost;
    p.unitPriceClient = client <= 0 && cost > 0 ? double.parse((cost * 1.1).toStringAsFixed(2)) : client;
    p.unitsPerPack = upp;
    p.receiptUnit = receiptUnit;
    await AppScope.of(context).suppliers.upsertPrice(widget.supplierId, p);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Поставщик'),
        actions: [
          TextButton(onPressed: _saveName, child: const Text('Сохранить')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPosition,
        icon: const Icon(Icons.add),
        label: const Text('Добавить позицию'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              children: [
                TextField(
                  controller: _nameCtrl,
                  keyboardType: NumericInput.textKeyboard,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Имя:', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                for (final p in _prices)
                  Card(
                    child: ListTile(
                      title: Text(p.productName),
                      subtitle: Text([
                        if (p.unitPriceCost > 0) 'закуп ${p.unitPriceCost}',
                        if (p.unitPriceClient > 0) 'клиент ${p.unitPriceClient}',
                        if (p.unitsPerPack > 1) 'уп×${p.unitsPerPack.round()}',
                        p.receiptUnit == 'pack' ? 'за уп' : 'за шт',
                      ].join(' · ')),
                      onTap: () => _edit(p),
                    ),
                  ),
              ],
            ),
    );
  }
}
