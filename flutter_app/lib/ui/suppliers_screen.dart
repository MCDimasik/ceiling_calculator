import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/cost_calculator.dart';
import '../domain/local_user_role.dart';
import '../domain/prices_share.dart';
import 'adaptive_layout.dart';
import 'mount_kits_screen.dart';
import 'prices_share_flow.dart';
import 'receipt_import_screen.dart';
import 'supplier_edit_screen.dart';
import 'widgets/long_press_action_tile.dart';
import 'widgets/numeric_input.dart';
import 'widgets/screen_scaffold.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<Supplier> _items = [];
  bool _loading = true;
  final Set<int> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reload();
    });
  }

  Future<void> _reload() async {
    final list = await AppScope.of(context).suppliers.listSuppliers();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
      _selectedIds.removeWhere((id) => !_items.any((s) => s.id == id));
    });
  }

  Future<void> _create() async {
    final name = await _ask('Новый поставщик');
    if (name == null || name.isEmpty) return;
    await AppScope.of(context).suppliers.createSupplier(name);
    await _reload();
  }

  Future<String?> _ask(String title, {String initial = ''}) async {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: NumericInput.textKeyboard,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  void _toggleSelected(int? id) {
    if (id == null) return;
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  Future<void> _shareSupplier(Supplier s) {
    return shareSupplierMaterials(context, supplier: s);
  }

  Future<void> _shareSelected() async {
    final chosen = [
      for (final s in _items)
        if (s.id != null && _selectedIds.contains(s.id)) s,
    ];
    if (chosen.isEmpty) return;
    if (chosen.length == 1) {
      await _shareSupplier(chosen.first);
      return;
    }
    final ids = [for (final s in chosen) s.id!];
    await sharePricesSelection(
      context,
      headline: '${chosen.length} поставщиков',
      detail: chosen.map((s) => s.name).join(', '),
      buildPayload: () => PricesShare.buildPayload(
        suppliers: AppScope.of(context).suppliers,
        fromOwner: AppScope.of(context).projects.activeOwnerLogin,
        includeWorkRates: false,
        supplierIds: ids,
      ),
    );
  }

  Future<void> _shareAll() async {
    if (_items.isEmpty) return;
    await sharePricesSelection(
      context,
      headline: 'Все поставщики (${_items.length})',
      detail: _items.map((s) => s.name).join(', '),
      buildPayload: () => PricesShare.buildPayload(
        suppliers: AppScope.of(context).suppliers,
        fromOwner: AppScope.of(context).projects.activeOwnerLogin,
        includeWorkRates: false,
      ),
    );
  }

  Future<void> _open(Supplier s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupplierEditScreen(supplierId: s.id!, name: s.name),
      ),
    );
    await _reload();
  }

  Future<void> _rename(Supplier s) async {
    final n = await _ask('Переименовать', initial: s.name);
    if (n == null || n.isEmpty) return;
    await AppScope.of(context).suppliers.renameSupplier(s.id!, n);
    await _reload();
  }

  Future<void> _delete(Supplier s) async {
    await AppScope.of(context).suppliers.deleteSupplier(s.id!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final canShare = (AppScope.of(context).user.profile?.effectiveRole ??
            AppUserRole.installer)
        .canPricing;
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _clearSelection();
      },
      child: ScreenScaffold(
        appBar: AppBar(
          leading: _selectionMode
              ? IconButton(
                  tooltip: 'Снять выбор',
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.close),
                )
              : null,
          title: Text(
            _selectionMode
                ? 'Выбрано: ${_selectedIds.length}'
                : 'Поставщики',
          ),
          actions: [
            if (!_selectionMode) ...[
              if (canShare && _items.isNotEmpty)
                IconButton(
                  tooltip: 'Поделиться всеми',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: _shareAll,
                ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MountKitsScreen()),
                  );
                },
                child: const Text('Комплекты'),
              ),
              TextButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ReceiptImportScreen(),
                    ),
                  );
                  await _reload();
                },
                child: const Text('Импорт чека'),
              ),
            ],
          ],
        ),
        floatingActionButton: _selectionMode
            ? null
            : FloatingActionButton.extended(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('Поставщик'),
              ),
        bottomNavigationBar: _selectionMode
            ? SafeArea(
                child: Material(
                  elevation: 8,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: canShare ? _shareSelected : null,
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Поделиться'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? const DesktopEmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'Нет поставщиков',
                    subtitle: 'Добавьте поставщика кнопкой ниже',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final s = _items[i];
                      final selected =
                          s.id != null && _selectedIds.contains(s.id);
                      return LongPressActionTile(
                        title: s.name,
                        leading: const Icon(Icons.storefront_outlined),
                        selected: selected,
                        selectionMode: _selectionMode,
                        onToggleSelect: () => _toggleSelected(s.id),
                        onOpen: () => _open(s),
                        onRename: () => _rename(s),
                        onShare: () => _shareSupplier(s),
                        onDelete: () => _delete(s),
                      );
                    },
                  ),
      ),
    );
  }
}
