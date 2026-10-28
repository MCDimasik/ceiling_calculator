import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/documentation_model.dart';
import '../domain/material_catalog.dart';
import '../domain/models.dart';
import '../domain/money_format.dart';
import '../domain/office_doc_reader.dart';
import '../domain/project_doc_import.dart';
import '../domain/project_price_resolver.dart';
import '../domain/work_rates_catalog.dart';
import '../domain/work_rates_lookup.dart';
import 'widgets/numeric_input.dart';
import 'widgets/screen_scaffold.dart';
import 'widgets/work_rate_catalog_picker.dart';

/// Edit per-project KS-2/KS-3 unit rates.
class DocumentationProjectPricesScreen extends StatefulWidget {
  const DocumentationProjectPricesScreen({super.key, required this.projectId});

  final int projectId;

  @override
  State<DocumentationProjectPricesScreen> createState() =>
      _DocumentationProjectPricesScreenState();
}

class _DocumentationProjectPricesScreenState
    extends State<DocumentationProjectPricesScreen> {
  Project? _project;
  ProjectDocumentation _doc = ProjectDocumentation();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    if (!mounted) return;
    await WorkRatesCatalogStore.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _project = project;
      _doc = ProjectDocumentation.fromJson(project?.documentationJson);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final project = _project;
    if (project?.id == null) return;
    project!.documentationJson = _doc.toJson();
    await AppScope.of(context).projects.updateProjectDocumentation(
          project.id!,
          documentationJson: _doc.toJson(),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Расценки сохранены')),
      );
    }
  }

  void _addDefaultRates() {
    setState(() {
      final byKey = projectPricesByKey(_doc.ks2Prices);
      void put(String key, String name, String unit) {
        byKey.putIfAbsent(
          key,
          () => ProjectPriceLine(matchKey: key, name: name, unit: unit),
        );
      }

      put('finish_floor', 'Отделка пола', 'м²');
      put('finish_wall', 'Отделка стен', 'м²');
      put('finish_ceiling', 'Отделка потолка', 'м²');
      put('purchase', 'Плиты/кассеты (закупка)', 'шт');
      for (final g in catalogProductGroups()) {
        byKey.putIfAbsent(
          g.calcMatchKey,
          () => ProjectPriceLine(
            matchKey: g.calcMatchKey,
            name: g.title,
            unit: 'шт',
          ),
        );
      }
      _doc.ks2Prices = byKey.values.toList()
        ..sort((a, b) => a.matchKey.compareTo(b.matchKey));
    });
  }

  Future<void> _pullFromCatalog({bool onlyEmpty = true}) async {
    final cats = await WorkRatesCatalogStore.ensureLoaded();
    if (!mounted) return;
    if (_doc.ks2Prices.isEmpty) _addDefaultRates();
    final n = applyCatalogPricesToProjectLines(
      _doc.ks2Prices,
      cats,
      onlyEmpty: onlyEmpty,
    );
    setState(() {});
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == 0
              ? 'Совпадений в каталоге не найдено'
              : 'Подставлено цен из каталога: $n (названия сохранены)',
        ),
      ),
    );
  }

  Future<void> _importCsv() async {
    final result = await parsePickedProjectDocument();
    final parsed = result.parsed;
    final filename = result.filename;
    if (filename == null) return;
    if (parsed.warning.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(parsed.warning)),
      );
      return;
    }
    if (!parsed.hasPrices) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В файле не найдены строки с ценами')),
      );
      return;
    }
    setState(() {
      _doc = applyParsedProjectDocument(_doc, parsed);
    });
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Импортировано позиций: ${parsed.prices.length}')),
    );
  }

  Future<void> _shareExcelTemplate() async {
    final bytes = buildProjectPriceImportTemplateXlsx();
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'project_prices_template.xlsx'));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'Шаблон расценок'),
    );
  }

  Future<void> _editLine(int index) async {
    final line = _doc.ks2Prices[index];
    final keyCtrl = TextEditingController(text: line.matchKey);
    final nameCtrl = TextEditingController(text: line.name);
    final unitCtrl = TextEditingController(text: line.unit);
    final priceCtrl = TextEditingController(
      text: line.unitPrice > 0 ? line.unitPrice.toStringAsFixed(2) : '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Расценка'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: keyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ключ (finish_floor, purchase, …)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Наименование (наше)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: unitCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ед. изм.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: NumericInput.decimalKeyboard,
                      decoration: const InputDecoration(
                        labelText: 'Цена, руб.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showWorkRateCatalogPicker(ctx);
                        if (picked == null) return;
                        setLocal(() {
                          priceCtrl.text = picked.unitPrice > 0
                              ? picked.unitPrice.toStringAsFixed(0)
                              : '';
                          if (unitCtrl.text.trim().isEmpty) {
                            unitCtrl.text = picked.unit;
                          }
                          // Keep our name unless empty.
                          if (nameCtrl.text.trim().isEmpty) {
                            nameCtrl.text = picked.name;
                          }
                        });
                      },
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Из каталога работ'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    setState(() {
      _doc.ks2Prices[index] = ProjectPriceLine(
        matchKey: keyCtrl.text.trim(),
        name: nameCtrl.text.trim(),
        unit: unitCtrl.text.trim().isEmpty ? 'шт' : unitCtrl.text.trim(),
        unitPrice: double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0,
      );
    });
    await _save();
  }

  Future<void> _deleteLine(int index) async {
    final p = _doc.ks2Prices[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить расценку?'),
        content: Text(p.name.isEmpty ? p.matchKey : p.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _doc.ks2Prices.removeAt(index));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ScreenScaffold(
      appBar: AppBar(
        title: const Text('Расценки объекта · КС-2 / КС-3'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Только расценки объекта'),
            subtitle: const Text(
              'Не подставлять цены из каталога работ и прайса поставщика',
            ),
            value: _doc.useProjectPricesOnly,
            onChanged: (v) async {
              setState(() => _doc.useProjectPricesOnly = v);
              await _save();
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _addDefaultRates,
                icon: const Icon(Icons.playlist_add),
                label: const Text('Типовые позиции'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _pullFromCatalog(onlyEmpty: true),
                icon: const Icon(Icons.sync_alt),
                label: const Text('Подтянуть из каталога'),
              ),
              OutlinedButton.icon(
                onPressed: _importCsv,
                icon: const Icon(Icons.upload_file),
                label: const Text('Импорт файла'),
              ),
              OutlinedButton.icon(
                onPressed: _shareExcelTemplate,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Шаблон Excel'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_doc.ks2Prices.isEmpty)
            Text(
              'Нет расценок. Добавьте типовые позиции, строку вручную '
              'или выберите цену из каталога работ.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ...List.generate(_doc.ks2Prices.length, (i) {
              final priceLine = _doc.ks2Prices[i];
              return Card(
                child: ListTile(
                  title: Text(
                    priceLine.name.isEmpty ? priceLine.matchKey : priceLine.name,
                  ),
                  subtitle: Text('${priceLine.matchKey} · ${priceLine.unit}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        priceLine.unitPrice > 0
                            ? formatRub(priceLine.unitPrice)
                            : '—',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        tooltip: 'Изменить',
                        onPressed: () => _editLine(i),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Удалить',
                        onPressed: () => _deleteLine(i),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  onTap: () => _editLine(i),
                ),
              );
            }),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          setState(() {
            _doc.ks2Prices.add(
              ProjectPriceLine(matchKey: '', name: 'Новая позиция'),
            );
          });
          await _editLine(_doc.ks2Prices.length - 1);
        },
        icon: const Icon(Icons.add),
        label: const Text('Позиция'),
      ),
    );
  }
}
