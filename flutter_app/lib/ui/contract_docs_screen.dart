import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'widgets/screen_scaffold.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/contract_document_model.dart';
import '../domain/cost_calculator.dart';
import '../domain/documentation_model.dart';
import '../domain/ks2_act_service.dart';
import '../domain/ks2_work_scope.dart';
import '../domain/materials_calculator.dart';
import '../domain/models.dart';
import '../domain/money_format.dart';
import '../domain/official_form_export.dart';
import '../domain/primary_supplier.dart';
import '../domain/project_export.dart';
import '../domain/room_finish_areas.dart';
import '../domain/work_rates_catalog.dart';
import 'ks2_period_picker.dart';
import 'widgets/expand_section_header.dart';
import 'widgets/numeric_input.dart';
import 'widgets/work_rate_catalog_picker.dart';

/// КП, КС-2, КС-3 и простой акт — по объекту или выбранным помещениям.
///
/// [embedded] — без своего AppBar (вкладка «Смета» в [ContractWorkspaceScreen]).
class ContractDocsScreen extends StatefulWidget {
  const ContractDocsScreen({
    super.key,
    required this.projectId,
    this.embedded = false,
    this.scrollHint,
  });

  final int projectId;
  final bool embedded;

  /// Shown at the top of the scrollable body (scrolls away with content).
  final String? scrollHint;

  @override
  State<ContractDocsScreen> createState() => ContractDocsScreenState();
}

class ContractDocsScreenState extends State<ContractDocsScreen> {
  Future<void> save() => _saveDoc();
  Project? _project;
  ProjectDocumentation _doc = ProjectDocumentation();
  bool _loading = true;
  bool _scopeAllRooms = true;
  int? _scopedRoomId;
  List<WorkRateCategory> _catalog = const [];
  Map<String, SupplierPrice>? _supplierPrices;
  final Set<String> _selectedLineKeys = {};
  bool _linesExpanded = true;
  bool _selectingLines = false;

  late TextEditingController _workTitleCtrl;
  late TextEditingController _scopeNoteCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _customerCtrl;
  late TextEditingController _buildSiteCtrl;
  late TextEditingController _contractNumCtrl;

  @override
  void initState() {
    super.initState();
    _workTitleCtrl = TextEditingController();
    _scopeNoteCtrl = TextEditingController();
    _priceCtrl = TextEditingController();
    _customerCtrl = TextEditingController();
    _buildSiteCtrl = TextEditingController();
    _contractNumCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _workTitleCtrl.dispose();
    _scopeNoteCtrl.dispose();
    _priceCtrl.dispose();
    _customerCtrl.dispose();
    _buildSiteCtrl.dispose();
    _contractNumCtrl.dispose();
    super.dispose();
  }

  Future<void> _leaveAndSave() async {
    if (!_loading && _project?.id != null) {
      try {
        await _saveDoc();
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    if (!mounted) return;
    final catalog = await WorkRatesCatalogStore.ensureLoaded();
    if (!mounted) return;
    final doc = ProjectDocumentation.fromJson(project?.documentationJson);
    Map<String, SupplierPrice>? prices;
    try {
      prices = await loadPrimarySupplierPrices(
        repo: AppScope.of(context).suppliers,
        doc: doc,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _project = project;
      _doc = doc;
      _catalog = catalog;
      _supplierPrices = prices;
      _loading = false;
    });
    _syncControllers();
  }

  Future<void> _pickUnifiedPriceFromCatalog() async {
    final item = await showWorkRateCatalogPicker(context);
    if (item == null || !mounted) return;
    setState(() {
      _priceCtrl.text = item.unitPrice > 0
          ? item.unitPrice.toStringAsFixed(0)
          : _priceCtrl.text;
      _doc.contractDocs.unifiedPricePerM2 =
          double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ??
              _doc.contractDocs.unifiedPricePerM2;
    });
  }

  Future<void> _editByRoomLinePrice(ContractWorkLine line) async {
    if (line.lineKey.isEmpty) return;
    if (line.lineKey.startsWith('merge:')) {
      await _editMergedLine(line);
      return;
    }
    final nameCtrl = TextEditingController(text: line.name);
    final priceCtrl = TextEditingController(
      text: line.unitPrice > 0 ? line.unitPrice.toStringAsFixed(0) : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Строка КП / КС'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Наименование',
                    border: OutlineInputBorder(),
                    helperText: 'Помещение · этаж · вид отделки',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: NumericInput.decimalKeyboard,
                  decoration: const InputDecoration(
                    labelText: 'Цена, ₽/м²',
                    border: OutlineInputBorder(),
                    helperText:
                        'Ручная цена перекрывает авторасчёт. Очистите поле — вернётся авто.',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showWorkRateCatalogPicker(
                      ctx,
                      section: line.section,
                    );
                    if (picked == null) return;
                    setLocal(() {
                      if (picked.unitPrice > 0) {
                        priceCtrl.text = picked.unitPrice.toStringAsFixed(0);
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
            TextButton(
              onPressed: () {
                priceCtrl.clear();
                Navigator.pop(ctx, true);
              },
              child: const Text('Авто'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;
    final name = nameCtrl.text.trim();
    setState(() {
      if (price > 0) {
        _doc.contractDocs.linePriceOverrides[line.lineKey] = price;
      } else {
        _doc.contractDocs.linePriceOverrides.remove(line.lineKey);
      }
      if (name.isNotEmpty) {
        _doc.contractDocs.lineNameOverrides[line.lineKey] = name;
      } else {
        _doc.contractDocs.lineNameOverrides.remove(line.lineKey);
      }
    });
    await _saveDoc();
  }

  void _enterLineSelection(ContractWorkLine line) {
    setState(() {
      _selectingLines = true;
      if (line.lineKey.isNotEmpty && !line.lineKey.startsWith('merge:')) {
        _selectedLineKeys.add(line.lineKey);
      }
    });
  }

  void _exitLineSelection() {
    setState(() {
      _selectingLines = false;
      _selectedLineKeys.clear();
    });
  }

  Future<void> _pickLineSort() async {
    final chosen = await showDialog<ContractLineSort>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Порядок строк'),
        children: [
          for (final s in ContractLineSort.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Row(
                children: [
                  Expanded(child: Text(s.labelRu)),
                  if (s == _doc.contractDocs.lineSort)
                    const Icon(Icons.check, size: 20),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    setState(() => _doc.contractDocs.lineSort = chosen);
  }

  Future<void> _mergeSelectedLines(List<ContractWorkLine> preview) async {
    final selected = preview
        .where(
          (l) =>
              _selectedLineKeys.contains(l.lineKey) &&
              l.lineKey.isNotEmpty &&
              !l.lineKey.startsWith('merge:'),
        )
        .toList();
    if (selected.length < 2) {
      _snack('Выберите не меньше двух строк');
      return;
    }
    final qty = selected.fold<double>(0, (s, l) => s + l.quantity);
    final suggestedPrice = qty > 0
        ? selected.fold<double>(0, (s, l) => s + l.lineSum) / qty
        : 0.0;
    // Prefer «Room · Floor · отделка (пол+стены)» style over «A + B + C».
    String defaultMergeName() {
      final rooms = <String>{};
      final floors = <String>{};
      final finishes = <String>[];
      for (final l in selected) {
        final parts = l.name.split(' · ');
        if (parts.isNotEmpty) rooms.add(parts.first.trim());
        if (parts.length >= 3) {
          floors.add(parts[1].trim());
          finishes.add(parts.last.split('.').first.trim());
        } else if (parts.length == 2) {
          finishes.add(parts.last.split('.').first.trim());
        } else {
          finishes.add(l.name);
        }
      }
      final finShort = finishes
          .map((f) => f
              .replaceFirst('Отделка пола', 'пол')
              .replaceFirst('Отделка стен', 'стены')
              .replaceFirst('Отделка потолка', 'потолок'))
          .toSet()
          .join('+');
      final head = [
        if (rooms.length == 1) rooms.first,
        if (floors.length == 1) floors.first,
      ].join(' · ');
      if (head.isEmpty) return 'Отделка ($finShort)';
      return '$head · отделка ($finShort)';
    }

    final nameCtrl = TextEditingController(text: defaultMergeName());
    final priceCtrl = TextEditingController(
      text: suggestedPrice > 0 ? suggestedPrice.toStringAsFixed(0) : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Объединить строки'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Количество: ${qty.toStringAsFixed(1)} м² · ${selected.length} строк',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Цена по умолчанию — средневзвешенная: сумма строк ÷ объём '
                  '(${formatRub(suggestedPrice)}/м²).',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Наименование',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  keyboardType: NumericInput.decimalKeyboard,
                  decoration: const InputDecoration(
                    labelText: 'Цена, ₽/м²',
                    border: OutlineInputBorder(),
                    helperText: 'Можно изменить вручную или взять из каталога',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showWorkRateCatalogPicker(ctx);
                    if (picked == null) return;
                    setLocal(() {
                      if (picked.unitPrice > 0) {
                        priceCtrl.text = picked.unitPrice.toStringAsFixed(0);
                      }
                      if (nameCtrl.text.trim().isEmpty) {
                        nameCtrl.text = picked.name;
                      }
                    });
                  },
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Из каталога'),
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
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;
    if (name.isEmpty) {
      _snack('Укажите название');
      return;
    }
    setState(() {
      _doc.contractDocs.mergedLines = [
        ..._doc.contractDocs.mergedLines,
        ContractMergedLine(
          id: 'm_${DateTime.now().millisecondsSinceEpoch}',
          sourceKeys: [for (final l in selected) l.lineKey],
          name: name,
          unitPrice: price,
        ),
      ];
      _selectingLines = false;
      _selectedLineKeys.clear();
    });
  }

  Future<void> _editMergedLine(ContractWorkLine line) async {
    final id = line.lineKey.replaceFirst('merge:', '');
    final merge = _doc.contractDocs.mergedLines
        .cast<ContractMergedLine?>()
        .firstWhere((m) => m?.id == id, orElse: () => null);
    if (merge == null) return;
    final nameCtrl = TextEditingController(text: merge.name);
    final priceCtrl = TextEditingController(
      text: merge.unitPrice > 0 ? merge.unitPrice.toStringAsFixed(0) : '',
    );
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Объединённая строка'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Наименование',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: NumericInput.decimalKeyboard,
              decoration: const InputDecoration(
                labelText: 'Цена, ₽/м²',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'split'),
            child: const Text('Разъединить'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('OK')),
        ],
      ),
    );
    if (action == 'split') {
      setState(() {
        _doc.contractDocs.mergedLines =
            _doc.contractDocs.mergedLines.where((m) => m.id != id).toList();
      });
      await _saveDoc();
      return;
    }
    if (action != 'save') return;
    setState(() {
      merge.name = nameCtrl.text.trim().isEmpty ? merge.name : nameCtrl.text.trim();
      merge.unitPrice =
          double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? merge.unitPrice;
    });
    await _saveDoc();
  }

  Future<void> _editCustomLine(int index) async {
    final lines = List<ContractWorkLine>.from(_doc.contractDocs.customLines);
    final line = index >= 0 && index < lines.length
        ? lines[index]
        : const ContractWorkLine(
            name: 'Работа',
            unit: 'м2',
            quantity: 0,
            unitPrice: 0,
          );
    final nameCtrl = TextEditingController(text: line.name);
    final unitCtrl = TextEditingController(text: line.unit);
    final qtyCtrl = TextEditingController(
      text: line.quantity > 0 ? line.quantity.toStringAsFixed(1) : '',
    );
    final priceCtrl = TextEditingController(
      text: line.unitPrice > 0 ? line.unitPrice.toStringAsFixed(0) : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(index < 0 ? 'Новая строка' : 'Строка КП / КС'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Наименование',
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
                  controller: qtyCtrl,
                  keyboardType: NumericInput.decimalKeyboard,
                  decoration: const InputDecoration(
                    labelText: 'Количество',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  keyboardType: NumericInput.decimalKeyboard,
                  decoration: const InputDecoration(
                    labelText: 'Цена, ₽',
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
                          : priceCtrl.text;
                      if (unitCtrl.text.trim().isEmpty) {
                        unitCtrl.text = picked.unit;
                      }
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
        ),
      ),
    );
    if (ok != true) return;
    final updated = ContractWorkLine(
      name: nameCtrl.text.trim().isEmpty ? line.name : nameCtrl.text.trim(),
      unit: unitCtrl.text.trim().isEmpty ? 'м2' : unitCtrl.text.trim(),
      quantity: double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0,
      unitPrice: double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0,
      estimatePos: line.estimatePos.isNotEmpty
          ? line.estimatePos
          : '${(index < 0 ? lines.length : index) + 1}',
    );
    setState(() {
      if (index < 0) {
        lines.add(updated);
      } else {
        lines[index] = updated;
      }
      _doc.contractDocs.customLines = lines;
    });
    await _saveDoc();
  }

  Future<void> _deleteCustomLine(int index) async {
    setState(() {
      final lines = List<ContractWorkLine>.from(_doc.contractDocs.customLines)
        ..removeAt(index);
      _doc.contractDocs.customLines = lines;
    });
    await _saveDoc();
  }

  Future<void> _seedCustomFromRooms() async {
    if (_doc.contractDocs.customLines.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Заполнить из помещений?'),
          content: const Text(
            'Текущие свои строки будут заменены строками '
            '«помещение · этаж · отделка» с ценами из слоёв.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Заменить'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final seeded = seedCustomLinesFromRooms(
      settings: _doc.contractDocs.copyWith(
        workTitle: _workTitleCtrl.text,
        scopeNote: _scopeNoteCtrl.text,
        unifiedPricePerM2:
            double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ??
                _doc.contractDocs.unifiedPricePerM2,
      ),
      rooms: _selectedRooms,
      floors: _project?.floors ?? const [],
      catalog: _catalog,
    );
    setState(() {
      _doc.contractDocs.customLines = seeded;
      _doc.contractDocs.lineMode = ProposalLineMode.custom;
    });
    await _saveDoc();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Добавлено строк: ${seeded.length}')),
    );
  }

  void _syncControllers() {
    final cfg = _doc.contractDocs;
    _workTitleCtrl.text = cfg.workTitle;
    _scopeNoteCtrl.text = cfg.scopeNote;
    _customerCtrl.text = _doc.contract.customerName.isNotEmpty
        ? _doc.contract.customerName
        : _doc.stamp.customer;
    _buildSiteCtrl.text = _doc.contract.buildSite.isNotEmpty
        ? _doc.contract.buildSite
        : _doc.stamp.address;
    _contractNumCtrl.text = _doc.contract.contractNumber;
    // Single-line: seed primary ₽/м² from weighted average when unset / default.
    if (cfg.lineMode == ProposalLineMode.single) {
      _seedSingleLinePriceIfNeeded();
    } else {
      _priceCtrl.text = cfg.unifiedPricePerM2 > 0
          ? cfg.unifiedPricePerM2.toStringAsFixed(0)
          : '';
    }
  }

  /// Fill the single-line price field with the room-weighted average.
  void _seedSingleLinePriceIfNeeded({bool force = false}) {
    final avg = weightedAverageUnitPrice(
      settings: _doc.contractDocs,
      rooms: _selectedRooms,
      floors: _project?.floors ?? const [],
      catalog: _catalog,
    );
    final current = double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0;
    final stored = _doc.contractDocs.unifiedPricePerM2;
    final shouldSeed = force ||
        current <= 0 ||
        stored <= 0 ||
        stored == 700; // legacy default placeholder
    if (avg != null && avg > 0 && shouldSeed) {
      _priceCtrl.text = avg.round().toString();
      _doc.contractDocs.unifiedPricePerM2 = avg;
    } else if (stored > 0) {
      _priceCtrl.text = stored.toStringAsFixed(0);
    }
  }

  void _applyAverageAsSinglePrice() {
    final avg = weightedAverageUnitPrice(
      settings: _doc.contractDocs,
      rooms: _selectedRooms,
      floors: _project?.floors ?? const [],
      catalog: _catalog,
    );
    if (avg == null || avg <= 0) return;
    setState(() {
      _priceCtrl.text = avg.round().toString();
      _doc.contractDocs.unifiedPricePerM2 = avg;
    });
  }

  void _applySettingsFromControllers() {
    _doc.contractDocs.workTitle = _workTitleCtrl.text.trim();
    _doc.contractDocs.scopeNote = _scopeNoteCtrl.text.trim();
    _doc.contractDocs.unifiedPricePerM2 =
        double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0;
    _doc.stamp.customer = _customerCtrl.text.trim();
    _doc.contract.customerName = _customerCtrl.text.trim();
    _doc.contract.buildSite = _buildSiteCtrl.text.trim();
    _doc.stamp.address = _buildSiteCtrl.text.trim();
    _doc.contract.contractNumber = _contractNumCtrl.text.trim();
  }

  Future<void> _saveDoc() async {
    final project = _project;
    if (project?.id == null) return;
    _applySettingsFromControllers();
    project!.documentationJson = _doc.toJson();
    await AppScope.of(context).projects.updateProjectDocumentation(
          project.id!,
          documentationJson: project.documentationJson,
        );
  }

  Iterable<Room> get _roomsWithLayout =>
      _project?.rooms.where((r) => r.id != null && roomHasFinishGeometry(r)) ??
          const [];

  List<Room> get _selectedRooms {
    if (_scopeAllRooms) return _roomsWithLayout.toList();
    final id = _scopedRoomId;
    if (id == null) return [];
    return _roomsWithLayout.where((r) => r.id == id).toList();
  }

  String get _scopeLabel {
    if (_scopeAllRooms) return 'Все помещения (${_roomsWithLayout.length})';
    for (final r in _roomsWithLayout) {
      if (r.id == _scopedRoomId) {
        return roomLabelForDocs(r, _project?.floors ?? const []);
      }
    }
    return 'Помещение';
  }

  double get _previewArea {
    var a = 0.0;
    for (final r in _selectedRooms) {
      a += MaterialsCalculator.roomAreaM2(r.walls);
    }
    return a;
  }

  double get _previewTotal {
    final lines = buildWorkLines(
      settings: _doc.contractDocs.copyWith(
        workTitle: _workTitleCtrl.text,
        scopeNote: _scopeNoteCtrl.text,
        unifiedPricePerM2:
            double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0,
      ),
      rooms: _selectedRooms,
      floors: _project?.floors ?? const [],
      catalog: _catalog,
      supplierPrices: _supplierPrices,
    );
    return linesTotal(lines);
  }

  Future<void> _shareBytes(Uint8List bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: filename),
    );
  }

  Future<void> _shareText(String text, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsString(text);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: filename),
    );
  }

  Future<void> _exportProposal() async {
    await _saveDoc();
    final project = _project;
    if (project == null || _selectedRooms.isEmpty) {
      _snack('Выберите помещения с чертежом');
      return;
    }
    final bytes = buildCommercialProposalXlsx(
      project: project,
      doc: _doc,
      stamp: _doc.stamp.withDefaults(projectName: project.name, roomName: ''),
      rooms: _selectedRooms,
      catalog: _catalog,
      supplierPrices: _supplierPrices,
    );
    final base = safeExportBasename('${project.name}_kp');
    await _shareBytes(bytes, '$base.xlsx');
  }

  Future<void> _exportOfficialKs2() async {
    await _saveDoc();
    final project = _project;
    if (project == null || _selectedRooms.isEmpty) {
      _snack('Выберите помещения с чертежом');
      return;
    }
    try {
      final now = DateTime.now();
      // Peek number for the file; registerKs2Act allocates the same via nextActNumber.
      final actNum = _doc.nextActNumber;
      final stamp =
          _doc.stamp.withDefaults(projectName: project.name, roomName: '');
      late final Uint8List bytes;
      if (_doc.contractDocs.formStyle == ContractFormStyle.simpleTable) {
        bytes = buildSimpleKs2WorkLinesXlsx(
          project: project,
          doc: _doc,
          stamp: stamp,
          rooms: _selectedRooms,
          actNumber: actNum,
          catalog: _catalog,
          supplierPrices: _supplierPrices,
        );
      } else {
        bytes = await buildOfficialKs2Xlsx(
          project: project,
          doc: _doc,
          stamp: stamp,
          rooms: _selectedRooms,
          actNumber: actNum,
          issueDate: now,
          periodFrom: now.subtract(const Duration(days: 7)),
          periodTo: now,
          supplierPrices: _supplierPrices,
        );
      }
      final scopes = projectActiveWorkScopes(project: project, doc: _doc);
      final effectiveScopes =
          scopes.isEmpty ? WorkScope.values.toList() : scopes;
      final breakdown = computeScopeBreakdown(
        project: project,
        rooms: _selectedRooms,
        scopes: effectiveScopes,
        prices: _supplierPrices,
      );
      final total = breakdown.values.fold<double>(0, (a, b) => a + b);
      final base = safeExportBasename('${project.name}_ks2_$actNum');
      // Share first — burn registry number only if share succeeds.
      await _shareBytes(bytes, '$base.xlsx');
      registerKs2Act(
        doc: _doc,
        scopes: effectiveScopes,
        rooms: _selectedRooms,
        totalAmount: total,
        scopeBreakdown: breakdown,
        notes: 'Экспорт из Смета',
      );
      project.documentationJson = _doc.toJson();
      if (!mounted) return;
      await AppScope.of(context).projects.updateProjectDocumentation(
            project.id!,
            documentationJson: project.documentationJson,
          );
      _snack('КС-2 № $actNum записан в реестр');
    } catch (e) {
      _snack('Не удалось выдать КС-2: $e');
    }
  }

  Future<void> _exportOfficialKs3() async {
    await _saveDoc();
    final project = _project;
    if (project == null || !mounted) return;
    final period = await pickKs3PeriodRange(context);
    if (period == null || !mounted) return;
    final bytes = await buildOfficialKs3Xlsx(
      project: project,
      doc: _doc,
      stamp: _doc.stamp.withDefaults(projectName: project.name, roomName: ''),
      documentNumber: _doc.ks2Acts.length + 1,
      issueDate: DateTime.now(),
      periodFrom: period.$1,
      periodTo: period.$2,
      acts: _doc.ks2Acts,
    );
    final base = safeExportBasename('${project.name}_ks3');
    await _shareBytes(bytes, '$base.xlsx');
  }

  Future<void> _exportSimpleAct() async {
    await _saveDoc();
    final project = _project;
    if (project == null || _selectedRooms.isEmpty) {
      _snack('Выберите помещения с чертежом');
      return;
    }
    final actNum = _doc.nextActNumber;
    final text = buildSimpleActText(
      project: project,
      doc: _doc,
      stamp: _doc.stamp.withDefaults(projectName: project.name, roomName: ''),
      rooms: _selectedRooms,
      actNumber: actNum,
    );
    final base = safeExportBasename('${project.name}_act_$actNum');
    await _shareText(text, '$base.txt');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _applyPartnerCard({required bool avangard}) async {
    setState(() {
      _doc = applyPartnerDefaults(_doc, fillAvangardCustomer: avangard);
      if (avangard && _doc.contract.contractNumber.isEmpty) {
        _doc.contract.contractNumber = '08/04-2025';
        _doc.contract.contractDate = DateTime(2025, 4, 8);
        _doc.contract.buildSite = 'улица Пархоменко, 1, Волгоград, 400087';
      }
    });
    _syncControllers();
    await _saveDoc();
    _snack('Реквизиты ИП Гусев подставлены');
  }

  Future<void> _openRoomScopePicker() async {
    final rooms = _roomsWithLayout.toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, scrollController) => ListView(
            controller: scrollController,
            children: [
              ListTile(
                title: const Text('Все помещения'),
                trailing: _scopeAllRooms ? const Icon(Icons.check_circle) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _scopeAllRooms = true;
                    _scopedRoomId = null;
                  });
                },
              ),
              const Divider(height: 1),
              for (final room in rooms)
                ListTile(
                  title: Text(
                    roomLabelForDocs(room, _project?.floors ?? const []),
                  ),
                  subtitle: Text(
                    'S=${MaterialsCalculator.roomAreaM2(room.walls).toStringAsFixed(1)} м²',
                  ),
                  trailing: !_scopeAllRooms && _scopedRoomId == room.id
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _scopeAllRooms = false;
                      _scopedRoomId = room.id;
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      const loading = Center(child: CircularProgressIndicator());
      if (widget.embedded) return loading;
      return const ScreenScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final project = _project;
    final previewLines = buildWorkLines(
      settings: _doc.contractDocs.copyWith(
        workTitle: _workTitleCtrl.text,
        scopeNote: _scopeNoteCtrl.text,
        unifiedPricePerM2:
            double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0,
        lineMode: _doc.contractDocs.lineMode,
        linePriceOverrides: _doc.contractDocs.linePriceOverrides,
      ),
      rooms: _selectedRooms,
      floors: _project?.floors ?? const [],
      catalog: _catalog,
      supplierPrices: _supplierPrices,
    );

    final hint = widget.scrollHint?.trim();
    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (hint != null && hint.isNotEmpty) ...[
            Material(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton(
            onPressed: _openRoomScopePicker,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Выбор помещений · $_scopeLabel'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'S ≈ ${_previewArea.toStringAsFixed(1)} м² · '
            '≈ ${formatRub(_previewTotal)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Форма документа', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ContractFormStyle>(
            segments: ContractFormStyle.values
                .map(
                  (s) => ButtonSegment(
                    value: s,
                    label: Text(
                      s == ContractFormStyle.avangardKs ? 'Бланк Авангард' : 'Таблица',
                    ),
                  ),
                )
                .toList(),
            selected: {_doc.contractDocs.formStyle},
            onSelectionChanged: (s) => setState(() {
              _doc.contractDocs.formStyle = s.first;
            }),
          ),
          const SizedBox(height: 4),
          Text(
            _doc.contractDocs.formStyle == ContractFormStyle.avangardKs
                ? 'КС-2/КС-3 заполняются в бланк Авангард (Excel).'
                : 'КС-2 — упрощённая таблица строк работ (Excel).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text('Реквизиты', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _applyPartnerCard(avangard: false),
                child: const Text('ИП Гусев · исполнитель'),
              ),
              OutlinedButton(
                onPressed: () => _applyPartnerCard(avangard: true),
                child: const Text('+ заказчик Авангард'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customerCtrl,
            decoration: const InputDecoration(
              labelText: 'Заказчик',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _applySettingsFromControllers(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _buildSiteCtrl,
            decoration: const InputDecoration(
              labelText: 'Стройка / адрес объекта',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _applySettingsFromControllers(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contractNumCtrl,
            decoration: const InputDecoration(
              labelText: '№ договора',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _applySettingsFromControllers(),
          ),
          const SizedBox(height: 16),
          Text('Работы и цена', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ProposalLineMode>(
            segments: ProposalLineMode.values
                .map((m) => ButtonSegment(value: m, label: Text(m.labelRu)))
                .toList(),
            selected: {_doc.contractDocs.lineMode},
            onSelectionChanged: (s) => setState(() {
              _doc.contractDocs.lineMode = s.first;
              if (s.first == ProposalLineMode.single) {
                _seedSingleLinePriceIfNeeded(force: true);
              }
            }),
          ),
          const SizedBox(height: 12),
          Text('Состав цены', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ContractPriceComposition>(
            segments: ContractPriceComposition.values
                .map(
                  (m) => ButtonSegment(
                    value: m,
                    label: Text(m.labelRu),
                  ),
                )
                .toList(),
            selected: {_doc.contractDocs.priceComposition},
            onSelectionChanged: (s) => setState(() {
              _doc.contractDocs.priceComposition = s.first;
            }),
          ),
          const SizedBox(height: 4),
          Text(
            _doc.contractDocs.priceComposition.helperRu,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_doc.contractDocs.lineMode == ProposalLineMode.single) ...[
            TextField(
              controller: _workTitleCtrl,
              decoration: const InputDecoration(
                labelText: 'Наименование работ',
                border: OutlineInputBorder(),
                helperText: 'Одна строка в КП / КС',
              ),
              onChanged: (_) => _applySettingsFromControllers(),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _scopeNoteCtrl,
            decoration: const InputDecoration(
              labelText: 'Уточнение (дом, секция, этажи)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _applySettingsFromControllers(),
          ),
          const SizedBox(height: 8),
          if (_doc.contractDocs.lineMode == ProposalLineMode.single) ...[
            Text(
              'Одна строка на весь объём. Цена ниже попадает в КП / КС как есть. '
              'По умолчанию — средневзвешенная по помещениям из расчёта отделки.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrl,
              keyboardType: NumericInput.decimalKeyboard,
              decoration: InputDecoration(
                labelText: 'Цена за м², ₽',
                border: const OutlineInputBorder(),
                helperText: previewLines.isEmpty
                    ? null
                    : 'В документе: ${previewLines.first.quantity.toStringAsFixed(1)} м² · '
                        '${formatRub(previewLines.first.lineSum)}',
                suffixIcon: IconButton(
                  tooltip: 'Из каталога работ',
                  onPressed: _pickUnifiedPriceFromCatalog,
                  icon: const Icon(Icons.menu_book_outlined),
                ),
              ),
              onChanged: (_) {
                _applySettingsFromControllers();
                setState(() {});
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _applyAverageAsSinglePrice,
                icon: const Icon(Icons.functions, size: 18),
                label: const Text('Подставить среднюю по помещениям'),
              ),
            ),
          ],
          if (_doc.contractDocs.lineMode == ProposalLineMode.byRoom) ...[
            Text(
              'Цены берутся из расчёта отделки (слои + покрытие/система). '
              'Правка строки в документе — только если в отделке цены ещё нет. '
              'Имена: помещение · этаж · вид отделки. '
              'Удерживайте строку, чтобы объединить.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_doc.contractDocs.linePriceOverrides.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(
                    () => _doc.contractDocs.linePriceOverrides.clear(),
                  ),
                  child: const Text('Сбросить правки цен в документе'),
                ),
              ),
          ],
          if (_doc.contractDocs.lineMode == ProposalLineMode.custom) ...[
            Text(
              'Свои строки: имя, количество и цена редактируются. '
              'Можно заполнить из помещений или добавить вручную.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _seedCustomFromRooms,
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Из помещений'),
                ),
                TextButton.icon(
                  onPressed: () => _editCustomLine(-1),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить строку'),
                ),
              ],
            ),
            if (_doc.contractDocs.customLines.isEmpty)
              Text(
                'Пока пусто — «Из помещений» или «Добавить строку». '
                'В КП / КС уйдут только эти строки.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else ...[
              Text(
                'В документе: ${_doc.contractDocs.customLines.length} · '
                '${formatRub(_previewTotal)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _doc.contractDocs.customLines.length; i++)
                Card(
                  child: ListTile(
                    title: Text(_doc.contractDocs.customLines[i].name),
                    subtitle: Text(
                      '${_doc.contractDocs.customLines[i].quantity.toStringAsFixed(1)} '
                      '${_doc.contractDocs.customLines[i].unit} · '
                      '${formatRub(_doc.contractDocs.customLines[i].unitPrice)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatRub(_doc.contractDocs.customLines[i].lineSum),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          onPressed: () => _editCustomLine(i),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: () => _deleteCustomLine(i),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    onTap: () => _editCustomLine(i),
                  ),
                ),
            ],
          ],
          // In «свои строки» the cards above are the document lines — no ghost preview.
          if (_doc.contractDocs.lineMode != ProposalLineMode.custom) ...[
          const SizedBox(height: 16),
          if (previewLines.isEmpty)
            Text(
              _doc.contractDocs.lineMode == ProposalLineMode.byRoom
                  ? 'Строки и цены — нет помещений с чертежом'
                  : 'Предпросмотр — нет помещений с чертежом',
            )
          else ...[
            ExpandSectionHeader(
              title: _doc.contractDocs.lineMode == ProposalLineMode.byRoom
                  ? 'Строки и цены'
                  : 'Предпросмотр строк',
              subtitle: '${previewLines.length} · ${formatRub(_previewTotal)}',
              expanded: _linesExpanded,
              onTap: () => setState(() => _linesExpanded = !_linesExpanded),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: !_linesExpanded
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_doc.contractDocs.lineMode ==
                            ProposalLineMode.byRoom) ...[
                          const SizedBox(height: 8),
                          if (_selectingLines)
                            Row(
                              children: [
                                Flexible(
                                  child: OutlinedButton.icon(
                                    onPressed: _selectedLineKeys.length >= 2
                                        ? () =>
                                            _mergeSelectedLines(previewLines)
                                        : null,
                                    icon:
                                        const Icon(Icons.merge_type, size: 18),
                                    label: Text(
                                      _selectedLineKeys.length >= 2
                                          ? 'Объединить (${_selectedLineKeys.length})'
                                          : 'Объединить',
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _exitLineSelection,
                                  child: const Text('Снять выделенное'),
                                ),
                                IconButton(
                                  tooltip: 'Порядок строк',
                                  onPressed: _pickLineSort,
                                  icon: const Icon(Icons.filter_list),
                                ),
                              ],
                            )
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Удерживайте строку, чтобы объединить. '
                                    'Короткое нажатие — имя и цена.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Порядок строк',
                                  onPressed: _pickLineSort,
                                  icon: const Icon(Icons.filter_list),
                                ),
                              ],
                            ),
                        ],
                        for (final line in previewLines)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: _doc.contractDocs.lineMode ==
                                        ProposalLineMode.byRoom &&
                                    _selectingLines &&
                                    line.lineKey.isNotEmpty &&
                                    !line.lineKey.startsWith('merge:')
                                ? Checkbox(
                                    value: _selectedLineKeys
                                        .contains(line.lineKey),
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selectedLineKeys.add(line.lineKey);
                                      } else {
                                        _selectedLineKeys.remove(line.lineKey);
                                      }
                                    }),
                                  )
                                : line.lineKey.startsWith('merge:')
                                    ? const Icon(Icons.merge_type, size: 20)
                                    : null,
                            title: Text(
                              line.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${line.quantity.toStringAsFixed(1)} ${line.unit} · '
                              '${formatRub(line.unitPrice)}/${line.unit}'
                              '${line.lineKey.startsWith('merge:') ? ' · объединено' : ''}',
                            ),
                            trailing: Text(
                              formatRub(line.lineSum),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            onTap: () {
                              final mode = _doc.contractDocs.lineMode;
                              if (mode == ProposalLineMode.custom) {
                                final idx = _doc.contractDocs.customLines
                                    .indexWhere((l) =>
                                        l.name == line.name &&
                                        l.quantity == line.quantity &&
                                        l.unitPrice == line.unitPrice);
                                if (idx >= 0) _editCustomLine(idx);
                                return;
                              }
                              if (mode != ProposalLineMode.byRoom) return;
                              if (line.lineKey.isEmpty) return;
                              if (_selectingLines) {
                                if (line.lineKey.startsWith('merge:')) return;
                                setState(() {
                                  if (_selectedLineKeys.contains(line.lineKey)) {
                                    _selectedLineKeys.remove(line.lineKey);
                                  } else {
                                    _selectedLineKeys.add(line.lineKey);
                                  }
                                });
                              } else {
                                _editByRoomLinePrice(line);
                              }
                            },
                            onLongPress: _doc.contractDocs.lineMode ==
                                        ProposalLineMode.byRoom &&
                                    line.lineKey.isNotEmpty &&
                                    !line.lineKey.startsWith('merge:')
                                ? () => _enterLineSelection(line)
                                : null,
                          ),
                      ],
                    ),
            ),
          ],
          ],
          const SizedBox(height: 16),
          Text('Экспорт', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _exportProposal,
            icon: const Icon(Icons.request_quote_outlined),
            label: const Text('Коммерческое предложение · Excel'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _exportOfficialKs2,
            icon: const Icon(Icons.description_outlined),
            label: Text(
              _doc.contractDocs.formStyle == ContractFormStyle.avangardKs
                  ? 'КС-2 · бланк Авангард · Excel'
                  : 'КС-2 · таблица · Excel',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _exportOfficialKs3,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('КС-3 · бланк Авангард · Excel'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _exportSimpleAct,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Простой акт · текст'),
          ),
        ],
      );

    if (widget.embedded) return body;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leaveAndSave();
      },
      child: ScreenScaffold(
        appBar: AppBar(
          title: Text(project?.name ?? 'Документы'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leaveAndSave,
          ),
          actions: [
            IconButton(
              tooltip: 'Сохранить',
              onPressed: () async {
                await _saveDoc();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Сохранено')),
                );
              },
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: body,
      ),
    );
  }
}
