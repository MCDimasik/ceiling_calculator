import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/act_export.dart';
import '../domain/contract_document_model.dart';
import '../domain/cost_calculator.dart';
import '../domain/documentation_export_policy.dart';
import '../domain/documentation_model.dart';
import '../domain/document_template_loader.dart';
import '../domain/hidden_works_pdf.dart';
import '../domain/ks2_act_service.dart';
import '../domain/ks2_work_scope.dart';
import '../domain/models.dart';
import '../domain/money_format.dart';
import '../domain/primary_supplier.dart';
import '../domain/official_form_export.dart';
import '../domain/project_documents_vault.dart';
import '../domain/project_export.dart';
import '../domain/project_floors.dart';
import '../domain/vedomost_export.dart';
import '../domain/work_rates_catalog.dart';
import 'documentation_hidden_layers_screen.dart';
import 'ks2_period_picker.dart';
import 'widgets/expand_section_header.dart';
import 'widgets/screen_scaffold.dart';

/// Which panel to show when embedded in [ContractWorkspaceScreen].
enum Ks2ClosurePanel {
  /// Internal tabs: issue + registry (standalone screen).
  both,

  /// Only «выдать акт».
  issue,

  /// Only act registry.
  registry,
}

/// Project-level intermediate KS-2 closure + act registry + KS-3.
class Ks2ClosureScreen extends StatefulWidget {
  const Ks2ClosureScreen({
    super.key,
    required this.projectId,
    this.initialScope,
    this.initialScopes,
    this.focusRoomId,
    this.embedded = false,
    this.panel = Ks2ClosurePanel.both,
    this.onActsChanged,
    this.scrollHint,
  });

  final int projectId;
  final WorkScope? initialScope;
  final List<WorkScope>? initialScopes;
  final int? focusRoomId;
  final bool embedded;
  final Ks2ClosurePanel panel;
  final VoidCallback? onActsChanged;

  /// Shown at the top of the scrollable panel (scrolls away with content).
  final String? scrollHint;

  @override
  State<Ks2ClosureScreen> createState() => Ks2ClosureScreenState();
}

class Ks2ClosureScreenState extends State<Ks2ClosureScreen>
    with SingleTickerProviderStateMixin {
  Future<void> reload() => _load();

  Future<void> exportKs3() => _exportKs3();
  Project? _project;
  ProjectDocumentation _doc = ProjectDocumentation();
  Map<String, SupplierPrice>? _prices;
  bool _loading = true;
  WorkScope _scope = WorkScope.floor;
  final Set<WorkScope> _selectedScopes = {};
  late TabController _tabs;
  final Set<int> _selectedRoomIds = {};
  bool _appliedFocus = false;
  bool _includeVedomost = false;
  bool _roomsListExpanded = false;
  bool _includeHiddenWorks = false;
  int _registryFilter = 0; // 0 all, 1 active, 2 cancelled
  /// Per-room KS totals for the rooms list (avoid recomputing on every rebuild).
  Map<int, double> _roomTotalCache = {};
  String _roomTotalCacheKey = '';

  List<WorkScope> get _activeScopes {
    final project = _project;
    if (project == null) return const [];
    return projectActiveWorkScopes(project: project, doc: _doc);
  }

  List<WorkScope> get _scopeList {
    if (_selectedScopes.isNotEmpty) {
      return _selectedScopes.toList()..sort((a, b) => a.index.compareTo(b.index));
    }
    return [_scope];
  }

  List<Room> get _readyRooms {
    final project = _project;
    if (project == null) return const [];
    final scopes = _scopeList;
    if (scopes.length == 1) {
      return roomsReadyForScopedKs2(
        project: project,
        doc: _doc,
        scope: scopes.first,
        acts: _doc.ks2Acts,
      );
    }
    return roomsReadyForMultiScopeKs2(
      project: project,
      doc: _doc,
      scopes: scopes,
      acts: _doc.ks2Acts,
    );
  }

  List<Room> get _selectedRooms =>
      _readyRooms.where((r) => r.id != null && _selectedRoomIds.contains(r.id)).toList();

  void _syncScopeAndSelection() {
    final active = _activeScopes;
    // Default: all active scopes (finishInclude + contract). Explicit
    // initialScope(s) from caller stay as provided.
    if (_selectedScopes.isEmpty) {
      _selectedScopes.addAll(active);
      if (_selectedScopes.isNotEmpty) _scope = _selectedScopes.first;
    }
    _selectedScopes.removeWhere((s) => !active.contains(s));
    if (_selectedScopes.isEmpty && active.isNotEmpty) {
      _selectedScopes.addAll(active);
      _scope = _selectedScopes.first;
    }
    final readyIds = _readyRooms.map((r) => r.id).whereType<int>().toSet();
    _selectedRoomIds.removeWhere((id) => !readyIds.contains(id));
    final focusId = widget.focusRoomId;
    if (focusId != null && !_appliedFocus) {
      _appliedFocus = true;
      // From a room screen: only that room is selected (others unchecked).
      _selectedRoomIds
        ..clear()
        ..addAll(readyIds.contains(focusId) ? [focusId] : const <int>[]);
    } else if (_selectedRoomIds.isEmpty) {
      _selectedRoomIds.addAll(readyIds);
    }
  }

  double get _previewTotal {
    final project = _project;
    if (project == null) return 0;
    _ensureRoomTotalCache();
    var sum = 0.0;
    for (final r in _selectedRooms) {
      final id = r.id;
      if (id == null) continue;
      sum += _roomTotalCache[id] ?? 0;
    }
    return sum;
  }

  void _ensureRoomTotalCache() {
    final project = _project;
    if (project == null) return;
    final scopes = _scopeList;
    final key =
        '${scopes.map((s) => s.name).join('+')}|${_prices?.length ?? 0}|${project.rooms.length}';
    if (key == _roomTotalCacheKey && _roomTotalCache.isNotEmpty) return;
    final next = <int, double>{};
    for (final r in _readyRooms) {
      final id = r.id;
      if (id == null) continue;
      next[id] = ks2ProjectScopedTotal(
        project: project,
        rooms: [r],
        scopes: scopes,
        prices: _prices,
      );
    }
    _roomTotalCache = next;
    _roomTotalCacheKey = key;
  }

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope ?? WorkScope.floor;
    if (widget.initialScopes != null && widget.initialScopes!.isNotEmpty) {
      _selectedScopes.addAll(widget.initialScopes!);
      _scope = _selectedScopes.first;
    } else if (widget.initialScope != null) {
      _selectedScopes.add(widget.initialScope!);
    }
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cached = AppScope.of(context).projects.peekCachedProject(widget.projectId);
      if (cached != null && mounted) {
        setState(() {
          _project = cached;
          _doc = ProjectDocumentation.fromJson(cached.documentationJson);
          _loading = false;
          _syncScopeAndSelection();
        });
      }
      _load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<Map<String, SupplierPrice>?> _supplierPrices(ProjectDocumentation doc) async {
    try {
      return await loadPrimarySupplierPrices(
        repo: AppScope.of(context).suppliers,
        doc: doc,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    final doc = ProjectDocumentation.fromJson(project?.documentationJson);
    final prices = await _supplierPrices(doc);
    if (!mounted) return;
    setState(() {
      _project = project;
      _roomTotalCache = {};
      _roomTotalCacheKey = '';
      _doc = doc;
      _prices = prices;
      _loading = false;
      _syncScopeAndSelection();
    });
  }

  Future<void> _saveDoc() async {
    if (_project?.id == null) return;
    await AppScope.of(context).projects.updateProjectDocumentation(
          _project!.id!,
          documentationJson: _doc.toJson(),
        );
    _project!.documentationJson = _doc.toJson();
  }

  Future<void> _formKs2() async {
    final project = _project;
    if (project == null) return;
    final rooms = _selectedRooms;
    if (rooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет помещений, готовых к закрытию по этому виду работ')),
      );
      return;
    }

    final allBlockers = <String>{};
    final allWarnings = <String>{};
    for (final room in rooms) {
      final cl =
          RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
      final report = checkExportReadiness(
        project: project,
        room: room,
        doc: _doc,
        checklist: cl,
        supplierPrices: _prices,
        forKs2: true,
        scopes: _scopeList,
      );
      allBlockers.addAll(report.blockers);
      for (final w in report.warnings) {
        allWarnings.add('${room.name}: $w');
      }
    }
    if (allBlockers.isNotEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Нельзя сформировать КС-2'),
          content: Text(allBlockers.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (allWarnings.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Предупреждения'),
          content: SingleChildScrollView(
            child: Text(allWarnings.join('\n')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Продолжить'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    final actNumber = _doc.nextActNumber;
    final total = _previewTotal;
    final ks2Template = await loadKs2TemplateJson(_doc);
    final scopeLabel = _scopeList.map((s) => s.labelRu).join(' + ');
    final want = <String>{
      for (final s in _scopeList)
        switch (s) {
          WorkScope.floor => 'floor',
          WorkScope.walls => 'walls',
          WorkScope.ceiling => 'ceiling',
        },
    };
    final previewLines = buildScopedContractWorkLines(
      settings: _doc.contractDocs,
      rooms: rooms,
      floors: project.floors,
      scopeIds: want,
      catalog: WorkRatesCatalogStore.peek(),
      supplierPrices: _prices,
    );

    if (!mounted) return;
    final previewOk = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final width = MediaQuery.sizeOf(ctx).width;
        return AlertDialog(
          title: Text('КС-2 № $actNumber'),
          content: SizedBox(
            width: width < 420 ? width * 0.92 : 420,
            height: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '$scopeLabel · ${rooms.length} помещ.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  total > 0
                      ? 'Итого: ${formatRub(total, fractionDigits: 2)}'
                      : 'Итого: —',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const Divider(height: 16),
                Expanded(
                  child: previewLines.isEmpty
                      ? const Center(
                          child: Text('Нет строк работ для выбранных видов'),
                        )
                      : ListView.separated(
                          itemCount: previewLines.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final line = previewLines[i];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                line.name,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${line.quantity.toStringAsFixed(1)} ${line.unit} · '
                                '${formatRub(line.unitPrice)}/${line.unit}',
                              ),
                              trailing: Text(
                                formatRub(line.lineSum),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Далее'),
            ),
          ],
        );
      },
    );
    if (previewOk != true) return;

    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Экспорт КС-2 № $actNumber'),
              subtitle: Text(
                'Одни и те же строки работ · '
                '${rooms.length} помещ. · '
                '${total > 0 ? formatRub(total, fractionDigits: 2) : 'сумма —'}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF'),
              subtitle: const Text('Файл + запись в реестр'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Excel'),
              subtitle: const Text('Файл + запись в реестр'),
              onTap: () => Navigator.pop(ctx, 'xlsx'),
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Текст'),
              subtitle: const Text('Файл + запись в реестр'),
              onTap: () => Navigator.pop(ctx, 'text'),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Формат только меняет файл. Содержание — строки сметы (работы). '
                'Бланк Авангард целиком — во вкладке «Смета».',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;

    try {
    final shareFiles = <XFile>[];
    String? exportPath;
    if (action == 'pdf') {
      final bytes = await buildProjectKs2MaterialsPdf(
        project: project,
        rooms: rooms,
        scopes: _scopeList,
        stamp: _doc.stamp,
        actNumber: actNumber,
        prices: _prices,
        templateJson: ks2Template,
        projectId: project.id,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(dir.path, '${safeExportBasename(project.name)}_ks2_${WorkScope.encodeKey(_scopeList)}_$actNumber.pdf'),
      );
      await file.writeAsBytes(bytes);
      exportPath = file.path;
      shareFiles.add(XFile(file.path));
    } else if (action == 'xlsx') {
      final bytes = buildProjectKs2Xlsx(
        project: project,
        rooms: rooms,
        scopes: _scopeList,
        stamp: _doc.stamp,
        actNumber: actNumber,
        prices: _prices,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(dir.path, '${safeExportBasename(project.name)}_ks2_$actNumber.xlsx'),
      );
      await file.writeAsBytes(bytes);
      exportPath = file.path;
      shareFiles.add(XFile(file.path));
    } else {
      final text = buildProjectKs2FromTemplate(
        templateJson: ks2Template,
        project: project,
        rooms: rooms,
        scopes: _scopeList,
        stamp: _doc.stamp,
        actNumber: actNumber,
        prices: _prices,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(dir.path, '${safeExportBasename(project.name)}_ks2_$actNumber.txt'),
      );
      await file.writeAsString(text);
      exportPath = file.path;
      shareFiles.add(XFile(file.path));
    }

    final extras = await _writeExtrasZip(project: project, rooms: rooms);
    if (extras != null) shareFiles.add(XFile(extras.path));

    if (shareFiles.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          files: shareFiles,
          subject: 'КС-2 № $actNumber · $scopeLabel',
        ),
      );
    }

    registerKs2Act(
      doc: _doc,
      scopes: _scopeList,
      rooms: rooms,
      totalAmount: total,
      scopeBreakdown: computeScopeBreakdown(
        project: project,
        rooms: rooms,
        scopes: _scopeList,
        prices: _prices,
      ),
      exportPath: exportPath,
    );
    await _saveDoc();
    if (exportPath != null) {
      await registerExportInVault(
        projects: AppScope.of(context).projects,
        project: project,
        category: DocumentVaultCategory.ks2,
        displayName: 'КС-2 № $actNumber · $scopeLabel',
        sourcePath: exportPath,
      );
      _doc.vault =
          ProjectDocumentation.fromJson(project.documentationJson).vault;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('КС-2 № $actNumber записан в реестр')),
    );
    setState(() {});
    widget.onActsChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сформировать КС-2: $e')),
      );
    }
  }

  Future<File?> _writeExtrasZip({
    required Project project,
    required List<Room> rooms,
  }) async {
    if (!_includeVedomost && !_includeHiddenWorks) return null;
    final archive = Archive();
    if (_includeVedomost) {
      for (final room in rooms) {
        final stamp = _doc.stamp.withDefaults(projectName: project.name, roomName: room.name);
        final text = _prices != null && _prices!.isNotEmpty
            ? buildVedomostTextWithPricing(
                project: project,
                room: room,
                stamp: stamp,
                prices: _prices!,
              )
            : buildVedomostText(project: project, room: room, stamp: stamp);
        final bytes = utf8.encode(text);
        archive.addFile(
          ArchiveFile(
            'vedomost_${safeExportBasename(room.name)}.txt',
            bytes.length,
            bytes,
          ),
        );
      }
    }
    if (_includeHiddenWorks) {
      for (final room in rooms) {
        final cl = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
        final pdf = await buildHiddenWorksPdf(
          project: project,
          room: room,
          stamp: _doc.stamp,
          checklist: cl,
          projectDoc: _doc,
        );
        archive.addFile(
          ArchiveFile(
            'hidden_${safeExportBasename(room.name)}.pdf',
            pdf.length,
            pdf,
          ),
        );
      }
    }
    if (archive.files.isEmpty) return null;
    final encoded = ZipEncoder().encode(archive);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${safeExportBasename(project.name)}_ks2_extras.zip'));
    await file.writeAsBytes(encoded);
    return file;
  }

  Future<void> _exportKs3() async {
    final project = _project;
    if (project == null || _doc.ks2Acts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала закройте хотя бы один вид работ через КС-2')),
      );
      return;
    }
    final period = await pickKs3PeriodRange(context);
    if (period == null) return;
    final (from, to) = period;
    final tpl = await loadKs3TemplateJson(_doc);
    final text = buildKs3FromTemplate(
      templateJson: tpl,
      project: project,
      stamp: _doc.stamp,
      periodFrom: from,
      periodTo: to,
      prices: _prices,
    );
    final pdf = await buildKs3MaterialsPdf(
      project: project,
      stamp: _doc.stamp,
      periodFrom: from,
      periodTo: to,
      templateJson: tpl,
      prices: _prices,
    );
    final dir = await getTemporaryDirectory();
    final pdfFile = File(p.join(dir.path, '${safeExportBasename(project.name)}_ks3.pdf'));
    await pdfFile.writeAsBytes(pdf);
    final ks3Xlsx = await buildOfficialKs3Xlsx(
      project: project,
      doc: _doc,
      stamp: _doc.stamp.withDefaults(projectName: project.name, roomName: ''),
      documentNumber: _doc.ks2Acts.length,
      issueDate: DateTime.now(),
      periodFrom: from,
      periodTo: to,
      acts: _doc.ks2Acts,
    );
    final xlsxFile = File(p.join(dir.path, '${safeExportBasename(project.name)}_ks3_avangard.xlsx'));
    await xlsxFile.writeAsBytes(ks3Xlsx);
    await Share.shareXFiles(
      [XFile(pdfFile.path), XFile(xlsxFile.path)],
      subject: 'КС-3 · ${project.name}',
      text: text,
    );
    if (project.id != null) {
      await registerExportInVault(
        projects: AppScope.of(context).projects,
        project: project,
        category: DocumentVaultCategory.ks3,
        displayName: 'КС-3 · ${project.name}',
        sourcePath: pdfFile.path,
      );
      _doc.vault =
          ProjectDocumentation.fromJson(project.documentationJson).vault;
    }
  }

  Future<void> _cancelAct(Ks2ActRecord act) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text('Отменить КС-2 № ${act.actNumber}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Помещения из акта снова можно будет закрыть. '
                'Отменённый акт останется в реестре, но не попадёт в КС-3.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                decoration: const InputDecoration(labelText: 'Причина (опционально)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Нет')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Отменить акт')),
          ],
        );
      },
    );
    if (reason == null) return;
    cancelKs2Act(_doc, act.id, reason: reason);
    await _saveDoc();
    setState(() {});
  }

  Future<void> _deleteAct(Ks2ActRecord act) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить КС-2 № ${act.actNumber}?'),
        content: Text(
          'Акт будет убран из реестра без следа. '
          'Помещения (${act.roomNames.join(', ')}) снова можно закрыть. '
          'Отмена — если нужна история; удаление — если ошиблись и переделываете.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!deleteKs2Act(_doc, act.id)) return;
    await _saveDoc();
    if (!mounted) return;
    _syncScopeAndSelection();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('КС-2 № ${act.actNumber} удалён из реестра')),
    );
  }

  Future<void> _amendAct(Ks2ActRecord act) async {
    final ctrl = TextEditingController(text: act.totalAmount.toStringAsFixed(2));
    final noteCtrl = TextEditingController(text: act.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Исправить КС-2 № ${act.actNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Будет создан новый акт. КС-2 № ${act.actNumber} '
              '(${formatRub(act.totalAmount, fractionDigits: 2)}) останется в реестре как отменённый.',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Сумма, ₽'),
            ),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Комментарий'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? act.totalAmount;
    amendKs2ActAmount(doc: _doc, actId: act.id, newAmount: amount, note: noteCtrl.text);
    await _saveDoc();
    setState(() {});
  }

  Future<void> _togglePaid(Ks2ActRecord act) async {
    final idx = _doc.ks2Acts.indexWhere((a) => a.id == act.id);
    if (idx < 0) return;
    final next = Ks2ActRecord(
      id: act.id,
      actNumber: act.actNumber,
      scope: act.scope,
      roomIds: act.roomIds,
      roomNames: act.roomNames,
      totalAmount: act.totalAmount,
      createdAt: act.createdAt,
      status: act.status == Ks2ActStatus.paid ? Ks2ActStatus.issued : Ks2ActStatus.paid,
      exportPath: act.exportPath,
      notes: act.notes,
      amendedFromId: act.amendedFromId,
      scopeBreakdown: act.scopeBreakdown,
    );
    _doc.ks2Acts[idx] = next;
    await _saveDoc();
    setState(() {});
  }

  Room? get _focusRoom {
    final id = widget.focusRoomId;
    if (id == null) return null;
    for (final r in _project?.rooms ?? const <Room>[]) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<Ks2ActRecord> get _filteredActs {
    final list = _doc.ks2Acts.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_registryFilter == 1) return list.where((a) => a.status != Ks2ActStatus.cancelled).toList();
    if (_registryFilter == 2) return list.where((a) => a.status == Ks2ActStatus.cancelled).toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      const loading = Center(child: CircularProgressIndicator());
      if (widget.embedded) return loading;
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Журнал актов')),
        body: loading,
      );
    }
    final project = _project;
    final ready = _readyRooms;
    final selected = _selectedRooms;
    final total = _previewTotal;
    final contractTotal = ledgerContractTotal(_doc.ks2Acts);
    final activeScopes = _activeScopes;
    final enabledScopes = projectEnabledWorkScopes(_doc);
    const canClose = true;
    final focus = _focusRoom;
    final focusReady = focus != null && ready.any((r) => r.id == focus.id);

    final hint = widget.scrollHint?.trim();
    Widget hintBanner() {
      if (hint == null || hint.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
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
      );
    }

    final issuePanel = ListView(
            padding: const EdgeInsets.all(16),
            children: [
              hintBanner(),
              Text('Вид работ', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (focus != null) ...[
                Builder(builder: (context) {
                  final floorTag = roomFloorLabel(
                    room: focus,
                    floors: project?.floors ?? const [],
                  );
                  final title = floorTag == null
                      ? 'Помещение «${focus.name}»'
                      : 'Помещение «${focus.name}» · $floorTag';
                  final scheme = Theme.of(context).colorScheme;
                  return Material(
                    color: focusReady
                        ? scheme.primaryContainer.withValues(alpha: 0.72)
                        : scheme.errorContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    elevation: 0,
                    child: ListTile(
                      leading: Icon(
                        focusReady ? Icons.star : Icons.info_outline,
                        color: focusReady
                            ? scheme.onPrimaryContainer
                            : scheme.onErrorContainer,
                      ),
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: focusReady
                              ? scheme.onPrimaryContainer
                              : scheme.onErrorContainer,
                        ),
                      ),
                      subtitle: Text(
                        focusReady
                            ? 'Это помещение сверху в списке и уже отмечено.'
                            : 'Нужен чертёж и включённый вид работ в отделке, либо вид уже закрыт в реестре.',
                        style: TextStyle(
                          color: (focusReady
                                  ? scheme.onPrimaryContainer
                                  : scheme.onErrorContainer)
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],
              if (activeScopes.isEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.warning_amber_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Нет видов работ для закрытия'),
                  subtitle: const Text(
                    'Проверьте состав договора в настройках объекта или отметку отделки в комнатах',
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final s in activeScopes)
                      FilterChip(
                        label: Text(s.labelRu),
                        selected: _selectedScopes.contains(s),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _selectedScopes.add(s);
                          } else if (_selectedScopes.length > 1) {
                            _selectedScopes.remove(s);
                          }
                          _scope = _selectedScopes.first;
                          _syncScopeAndSelection();
                        }),
                      ),
                  ],
                ),
              if (enabledScopes.length < WorkScope.values.length) ...[
                const SizedBox(height: 8),
                Text(
                  'По договору: ${enabledScopes.map((s) => s.labelRu).join(' · ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Text('Выбрано: ${selected.length} из ${ready.length} помещ.'),
              if (total > 0)
                Text(
                  'Сумма: ${formatRub(total, fractionDigits: 2)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (contractTotal > 0)
                Text('Уже в реестре: ${formatRub(contractTotal, fractionDigits: 2)}'),
              const SizedBox(height: 4),
              Text(
                'Часть помещений сейчас — остальные позже.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (ready.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _selectedRoomIds.addAll(
                            ready.map((r) => r.id).whereType<int>(),
                          )),
                      child: const Text('Все'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selectedRoomIds.clear()),
                      child: const Text('Снять'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              if (ready.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Нет готовых помещений'),
                  subtitle: Text(
                    'Нужен чертёж и включённый вид работ в составе отделки',
                  ),
                )
              else ...[
                Builder(builder: (context) {
                  final floors = project?.floors ?? const [];
                  final collapse = ready.length > 5 ||
                      projectHasExplicitFloors(floors);
                  final showList = !collapse || _roomsListExpanded;
                  return Column(
                    children: [
                      if (collapse)
                        ExpandSectionHeader(
                          expanded: _roomsListExpanded,
                          emphasized: focus != null,
                          title: _roomsListExpanded
                              ? 'Скрыть список помещений'
                              : 'Помещения (${selected.length} из ${ready.length})',
                          subtitle: focus != null
                              ? 'Выбрано: ${focus.name}'
                              : 'Нажмите, чтобы отметить галочки',
                          onTap: () => setState(
                            () => _roomsListExpanded = !_roomsListExpanded,
                          ),
                        ),
                      if (showList) ...[
                        Builder(builder: (context) {
                          _ensureRoomTotalCache();
                          final ordered = List<Room>.from(ready);
                          final focusId = widget.focusRoomId;
                          if (focusId != null) {
                            ordered.sort((a, b) {
                              final af = a.id == focusId ? 0 : 1;
                              final bf = b.id == focusId ? 0 : 1;
                              return af.compareTo(bf);
                            });
                          }
                          // Cap initial paint: virtualize via Column of tiles
                          // but use cached totals (was N× full KS calc per frame).
                          return Column(
                            children: [
                              for (final r in ordered)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _Ks2RoomPickTile(
                                    room: r,
                                    floors: floors,
                                    checked: _selectedRoomIds.contains(r.id),
                                    isFocus: widget.focusRoomId == r.id,
                                    totalRub: _roomTotalCache[r.id!] ?? 0,
                                    onChanged: (v) => setState(() {
                                      final id = r.id!;
                                      if (v == true) {
                                        _selectedRoomIds.add(id);
                                      } else {
                                        _selectedRoomIds.remove(id);
                                      }
                                    }),
                                  ),
                                ),
                            ],
                          );
                        }),
                      ],
                    ],
                  );
                }),
              ],
              const SizedBox(height: 8),
              Material(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Ведомость выбранных помещений'),
                      subtitle: const Text('В одном ZIP вместе с КС-2'),
                      value: _includeVedomost,
                      onChanged: (v) => setState(() => _includeVedomost = v),
                    ),
                    SwitchListTile(
                      title: const Text('Включить скрытые работы'),
                      subtitle: const Text(
                        'Опционально: фото слоёв → PDF в ZIP с КС-2',
                      ),
                      value: _includeHiddenWorks,
                      onChanged: (v) => setState(() => _includeHiddenWorks = v),
                    ),
                    if (_includeHiddenWorks)
                      ListTile(
                        leading: const Icon(Icons.photo_library_outlined),
                        title: const Text('Заполнить скрытые'),
                        subtitle: Text(
                          selected.isEmpty
                              ? 'Сначала выберите помещения'
                              : 'Слои → фото · ${selected.length} пом.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        enabled: selected.isNotEmpty,
                        onTap: selected.isEmpty
                            ? null
                            : () async {
                                final room = selected.first;
                                if (room.id == null) return;
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DocumentationHiddenLayersScreen(
                                      projectId: widget.projectId,
                                      roomId: room.id!,
                                    ),
                                  ),
                                );
                                await _load();
                              },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: !canClose || selected.isEmpty ? null : _formKs2,
                icon: const Icon(Icons.description_outlined),
                label: Text(
                  canClose
                      ? 'Сформировать КС-2 · ${_scopeList.map((s) => s.labelRu).join(' + ')}'
                      : 'Закрытие недоступно монтажнику',
                ),
              ),
            ],
          );

    final Widget registryPanel = _doc.ks2Acts.isEmpty
        ? ListView(
            padding: const EdgeInsets.all(16),
            children: [
              hintBanner(),
              const SizedBox(height: 48),
              const Center(child: Text('Реестр пуст — сформируйте первый КС-2')),
            ],
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              hintBanner(),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Все')),
                  ButtonSegment(value: 1, label: Text('Действующие')),
                  ButtonSegment(value: 2, label: Text('Отменённые')),
                ],
                selected: {_registryFilter},
                onSelectionChanged: (s) =>
                    setState(() => _registryFilter = s.first),
              ),
              const SizedBox(height: 12),
              for (final act in _filteredActs)
                Card(
                  color: act.status == Ks2ActStatus.cancelled
                      ? Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.25)
                      : act.status == Ks2ActStatus.paid
                          ? Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.35)
                          : null,
                  child: ListTile(
                    leading: Icon(
                      act.status == Ks2ActStatus.cancelled
                          ? Icons.block
                          : act.status == Ks2ActStatus.paid
                              ? Icons.payments
                              : Icons.description_outlined,
                    ),
                    title: Text(
                      'КС-2 № ${act.actNumber} · ${scopeKeyLabel(act.scope)}',
                      style: act.status == Ks2ActStatus.cancelled
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough)
                          : null,
                    ),
                    subtitle: Text(
                      '${act.roomNames.join(', ')}\n'
                      '${formatRub(act.totalAmount, fractionDigits: 2)} · ${act.status.labelRu} · '
                      '${act.createdAt.day.toString().padLeft(2, '0')}.'
                      '${act.createdAt.month.toString().padLeft(2, '0')}.${act.createdAt.year}'
                      '${act.amendedFromId != null ? '\nЗамена предыдущего акта' : ''}'
                      '${act.notes.isNotEmpty ? '\n${act.notes}' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: !canClose
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'paid') await _togglePaid(act);
                              if (v == 'cancel') await _cancelAct(act);
                              if (v == 'amend') await _amendAct(act);
                              if (v == 'delete') await _deleteAct(act);
                              widget.onActsChanged?.call();
                            },
                            itemBuilder: (_) {
                              if (act.status == Ks2ActStatus.cancelled) {
                                return const [
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Удалить из реестра'),
                                  ),
                                ];
                              }
                              return [
                                PopupMenuItem(
                                  value: 'paid',
                                  child: Text(
                                    act.status == Ks2ActStatus.paid
                                        ? 'Снять оплату'
                                        : 'Оплачен',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'amend',
                                  child: Text('Исправить сумму'),
                                ),
                                const PopupMenuItem(
                                  value: 'cancel',
                                  child: Text('Отменить акт'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Удалить из реестра'),
                                ),
                              ];
                            },
                          ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Итого по активным актам: ${formatRub(contractTotal, fractionDigits: 2)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          );

    switch (widget.panel) {
      case Ks2ClosurePanel.issue:
        return issuePanel;
      case Ks2ClosurePanel.registry:
        return registryPanel;
      case Ks2ClosurePanel.both:
        break;
    }

    return ScreenScaffold(
      appBar: AppBar(
        title: Text('Журнал · ${project?.name ?? ''}'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Закрыть (${selected.length}/${ready.length})'),
            Tab(text: 'Акты (${_doc.ks2Acts.length})'),
          ],
        ),
        actions: [
          if (canClose)
            IconButton(
              tooltip: 'КС-3 нарастающая',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: _exportKs3,
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [issuePanel, registryPanel],
      ),
    );
  }
}

class _Ks2RoomPickTile extends StatelessWidget {
  const _Ks2RoomPickTile({
    required this.room,
    required this.floors,
    required this.checked,
    required this.isFocus,
    required this.totalRub,
    required this.onChanged,
  });

  final Room room;
  final List<ProjectFloor> floors;
  final bool checked;
  final bool isFocus;
  final double totalRub;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final floorTag = roomFloorLabel(room: room, floors: floors);
    final name = floorTag == null ? room.name : '${room.name} · $floorTag';
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isFocus
          ? scheme.primaryContainer.withValues(alpha: 0.72)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: CheckboxListTile(
        value: checked,
        onChanged: onChanged,
        secondary: Icon(
          isFocus ? Icons.star : Icons.meeting_room_outlined,
        ),
        title: Text(
          isFocus ? '$name · это помещение' : name,
          style: isFocus
              ? const TextStyle(fontWeight: FontWeight.w700)
              : null,
        ),
        subtitle: Text(formatRub(totalRub)),
      ),
    );
  }
}
