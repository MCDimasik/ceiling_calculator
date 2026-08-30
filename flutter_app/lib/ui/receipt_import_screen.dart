import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../domain/receipt_import.dart';
import 'supplier_edit_screen.dart';

class ReceiptImportScreen extends StatefulWidget {
  const ReceiptImportScreen({super.key});

  @override
  State<ReceiptImportScreen> createState() => _ReceiptImportScreenState();
}

class _ReceiptImportScreenState extends State<ReceiptImportScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _merge = true;
  String? _report;
  int? _supplierId;
  String? _supplierName;

  Future<void> _pickFile() async {
    setState(() => _busy = true);
    try {
      final text = await pickReceiptText();
      if (text == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось извлечь текст (попробуйте вставить вручную)')),
          );
        }
        return;
      }
      setState(() => _controller.text = text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _report = null;
    });
    try {
      final (parsed, meta) = await parseReceiptTextSmart(text);
      if (parsed.items.isEmpty) {
        setState(() => _report = 'Не удалось найти позиции с ценами.');
        return;
      }
      final result = await applyParsedReceipt(
        AppScope.of(context).suppliers,
        parsed,
        merge: _merge,
      );
      _supplierId = result.supplierId;
      _supplierName = result.supplierName;
      final tpl = meta == null ? '' : '\nШаблон: ${meta['template_name']} (score ${meta['score']})';
      setState(() {
        _report =
            'Поставщик: ${result.supplierName}$tpl\n'
            'Сопоставлено: ${result.matched.length}\n'
            'Без совпадения: ${result.unmatched.length}'
            '${result.unmatched.isEmpty ? '' : '\n\nНе найдено:\n${result.unmatched.map((e) => '• ${e.rawName}').join('\n')}'}';
      });
    } catch (e) {
      setState(() => _report = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AppScope.of(context).admin.unlocked) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт чека')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Выбрать PDF / TXT'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Объединить с существующими ценами'),
            value: _merge,
            onChanged: (v) => setState(() => _merge = v),
          ),
          TextField(
            controller: _controller,
            maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Или вставьте текст чека…',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _apply,
            child: const Text('Импортировать цены'),
          ),
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) setState(() => _controller.text = data!.text!);
            },
            child: const Text('Вставить из буфера'),
          ),
          if (_report != null) ...[
            const SizedBox(height: 16),
            SelectableText(_report!),
            if (_supplierId != null)
              FilledButton.tonal(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SupplierEditScreen(
                        supplierId: _supplierId!,
                        name: _supplierName ?? 'Поставщик',
                      ),
                    ),
                  );
                },
                child: const Text('Открыть поставщика'),
              ),
          ],
        ],
      ),
    );
  }
}
