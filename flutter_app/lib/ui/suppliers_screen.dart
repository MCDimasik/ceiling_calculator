import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/cost_calculator.dart';
import 'receipt_import_screen.dart';
import 'supplier_edit_screen.dart';
import 'widgets/numeric_input.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<Supplier> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!AppScope.of(context).admin.unlocked) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Только для администратора')),
        );
        return;
      }
      _reload();
    });
  }

  Future<void> _reload() async {
    final list = await AppScope.of(context).suppliers.listSuppliers();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
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

  @override
  Widget build(BuildContext context) {
    if (!AppScope.of(context).admin.unlocked) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Поставщики'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceiptImportScreen()),
              );
            },
            child: const Text('Импорт чека'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Поставщик'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Нет поставщиков'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = _items[i];
                    return Card(
                      child: ListTile(
                        title: Text(s.name),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'rename') {
                              final n = await _ask('Переименовать', initial: s.name);
                              if (n != null && n.isNotEmpty) {
                                await AppScope.of(context).suppliers.renameSupplier(s.id!, n);
                                await _reload();
                              }
                            } else if (v == 'delete') {
                              await AppScope.of(context).suppliers.deleteSupplier(s.id!);
                              await _reload();
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                            PopupMenuItem(value: 'delete', child: Text('Удалить')),
                          ],
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SupplierEditScreen(supplierId: s.id!, name: s.name),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
