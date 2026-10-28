import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../data/project_repository.dart';
import '../domain/act_export.dart';
import '../domain/as_built_export.dart';
import '../domain/dxf_export.dart';
import '../domain/documentation_export_policy.dart';
import '../domain/finish_model.dart';
import '../domain/floor_as_built_export.dart';
import '../domain/hidden_works_pdf.dart';
import '../domain/finish_vedomost.dart';
import '../domain/device_capabilities.dart';
import '../domain/documentation_photos.dart';
import '../domain/documentation_model.dart';
import '../domain/cost_calculator.dart';
import '../domain/material_catalog.dart';
import '../domain/material_certificates.dart';
import '../domain/models.dart';
import '../domain/official_form_export.dart';
import '../domain/partner_profile.dart';
import '../domain/project_doc_import.dart';
import '../domain/project_export.dart';
import '../domain/primary_supplier.dart';
import '../domain/room_documentation_status.dart';
import '../domain/scheme_png_export.dart';
import 'projects_screen.dart';
import 'geometry_capture_hub_screen.dart';
import '../domain/vedomost_export.dart';
import '../domain/document_template_loader.dart';
import '../domain/layout_layers.dart';
import '../domain/ks2_work_scope.dart';
import 'room_navigation.dart';
import 'finish_materials_screen.dart';
import 'documentation_project_prices_screen.dart';
import 'documentation_import_ui.dart';
import 'doc_step_navigation.dart';
import 'documentation_hidden_layers_screen.dart';
import 'contract_workspace_screen.dart';
import 'widgets/room_workflow_chip.dart';
import 'widgets/screen_scaffold.dart';
import '../domain/hidden_works_layers.dart';

/// Open documentation hub for a room from any module.
Future<void> openDocumentationRoom(
  BuildContext context, {
  required int projectId,
  required int roomId,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DocumentationRoomScreen(
        projectId: projectId,
        roomId: roomId,
      ),
    ),
  );
}

class DocumentationProjectsScreen extends StatelessWidget {
  const DocumentationProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProjectsScreen(module: AppModule.documentation);
  }
}

/// Room hub: checklist, as-built, vedomost, links to layout/materials.
class DocumentationRoomScreen extends StatefulWidget {
  const DocumentationRoomScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<DocumentationRoomScreen> createState() => _DocumentationRoomScreenState();
}

class _DocumentationRoomScreenState extends State<DocumentationRoomScreen> {
  Project? _project;
  Room? _room;
  ProjectDocumentation _doc = ProjectDocumentation();
  RoomDocumentationChecklist _checklist = RoomDocumentationChecklist();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cached = AppScope.of(context).projects.peekCachedProject(widget.projectId);
      if (cached != null && mounted) {
        Room? room;
        for (final r in cached.rooms) {
          if (r.id == widget.roomId) room = r;
        }
        setState(() {
          _project = cached;
          _room = room;
          _doc = ProjectDocumentation.fromJson(cached.documentationJson);
          _checklist =
              RoomDocumentationChecklist.fromJson(room?.documentationChecklistJson);
          _loading = false;
        });
      }
      _load();
    });
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    Room? room;
    if (project != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    if (!mounted) return;
    final doc = ProjectDocumentation.fromJson(project?.documentationJson);
    normalizeStampCustomerAddress(doc.stamp);
    normalizeContractCustomerAddress(doc.contract);
    if (!mounted) return;
    setState(() {
      _project = project;
      _room = room;
      _doc = doc;
      _checklist = RoomDocumentationChecklist.fromJson(room?.documentationChecklistJson);
      _loading = false;
    });
  }

  Future<void> _saveChecklist() async {
    final room = _room;
    if (room?.id == null) return;
    final json = roomChecklistJsonForSave(_checklist, room!.documentationChecklistJson);
    await AppScope.of(context).projects.updateRoomChecklist(
          room.id!,
          checklistJson: json,
        );
    room.documentationChecklistJson = json;
  }

  String _roomTemplateSubtitle() {
    final room = _room;
    if (room == null) return 'Как у проекта';
    final t = RoomExportTemplates.fromChecklistJson(room.documentationChecklistJson);
    if (!t.hasAnyOverride) return 'Как у проекта';
    final parts = <String>[];
    if (t.ks2TemplatePath != null) parts.add('КС-2');
    if (t.actHiddenTemplatePath != null) parts.add('акт');
    if (t.vedomostTemplatePath != null) parts.add('ведомость');
    return 'Свои: ${parts.join(', ')}';
  }

  Future<bool> _ensureExportAllowed({bool forKs2 = false}) async {
    final project = _project;
    final room = _room;
    if (project == null || room == null) return false;
    final prices = await _supplierPrices();
    final report = checkExportReadiness(
      project: project,
      room: room,
      doc: _doc,
      checklist: _checklist,
      supplierPrices: prices,
      forKs2: forKs2,
    );
    if (report.blockers.isNotEmpty) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Экспорт недоступен'),
          content: Text(report.blockers.join('\n')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return false;
    }
    if (report.warnings.isNotEmpty) {
      if (!mounted) return false;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Проверьте перед экспортом'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: report.warnings.map((w) => Text('• $w')).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Экспорт')),
          ],
        ),
      );
      return proceed == true;
    }
    return true;
  }

  Future<Map<String, SupplierPrice>?> _supplierPrices() async {
    return loadPrimarySupplierPrices(
      repo: AppScope.of(context).suppliers,
      doc: _doc,
    );
  }

  Future<void> _persistActNumberAfterShare(int actNumber) async {
    // Commit the peeked number only after a successful share.
    if (_doc.nextActNumber <= actNumber) {
      _doc.nextActNumber = actNumber + 1;
    }
    final project = _project;
    if (project?.id == null) return;
    project!.documentationJson = _doc.toJson();
    await AppScope.of(context).projects.updateProjectDocumentation(
          project.id!,
          documentationJson: project.documentationJson,
        );
  }

  Future<void> _exportHiddenWorksPdf() async {
    if (!await _ensureExportAllowed()) return;
    final project = _project;
    final room = _room;
    if (project == null || room == null) return;
    final stamp = _doc.stamp.withDefaults(projectName: project.name, roomName: room.name);
    final bytes = await buildHiddenWorksPdf(
      project: project,
      room: room,
      stamp: stamp,
      checklist: _checklist,
    );
    final base = safeExportBasename('${project.name}_${room.name}_hidden_works');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '$base.pdf'));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'Скрытые работы · ${room.name}'),
    );
  }

  Future<void> _exportHiddenWorksAct({required bool pdf}) async {
    if (!await _ensureExportAllowed()) return;
    final project = _project;
    final room = _room;
    if (project == null || room == null) return;
    // Peek — burn number only after share succeeds.
    final actNumber = _doc.nextActNumber;
    final stamp = _doc.stamp.withDefaults(projectName: project.name, roomName: room.name);
    final base = safeExportBasename('${project.name}_${room.name}_act_hidden');
    final dir = await getTemporaryDirectory();
    try {
      if (pdf) {
        final bytes = await buildHiddenWorksActPdf(
          project: project,
          room: room,
          stamp: stamp,
          checklist: _checklist,
          actNumber: actNumber,
          templateJson: await loadActHiddenTemplateJson(_doc, room: room),
        );
        final file = File(p.join(dir.path, '$base.pdf'));
        await file.writeAsBytes(bytes);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: 'Акт скрытых работ · ${room.name}',
          ),
        );
      } else {
        final text = buildHiddenWorksActText(
          project: project,
          room: room,
          stamp: stamp,
          checklist: _checklist,
          actNumber: actNumber,
        );
        await Clipboard.setData(ClipboardData(text: text));
        await SharePlus.instance.share(
          ShareParams(text: text, subject: 'Акт скрытых работ · ${room.name}'),
        );
      }
      await _persistActNumberAfterShare(actNumber);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выдать акт: $e')),
      );
    }
  }

  Future<void> _exportRoomCommercialProposal() async {
    final project = _project;
    final room = _room;
    if (project == null || room == null) return;
    if (!room.hasLayout) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет чертежа — сначала замкните контур')),
      );
      return;
    }
    normalizeStampCustomerAddress(_doc.stamp);
    normalizeContractCustomerAddress(_doc.contract);
    final stamp = _doc.stamp.withDefaults(projectName: project.name, roomName: room.name);
    final bytes = buildCommercialProposalXlsx(
      project: project,
      doc: _doc,
      stamp: stamp,
      rooms: [room],
    );
    final base = safeExportBasename('${project.name}_${room.name}_kp');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '$base.xlsx'));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'КП · ${room.name}'),
    );
  }

  Future<void> _exportKs2({required bool pdf}) async {
    if (!await _ensureExportAllowed(forKs2: true)) return;
    final project = _project;
    final room = _room;
    if (project == null || room == null) return;
    final stamp = _doc.stamp.withDefaults(projectName: project.name, roomName: room.name);
    final prices = await _supplierPrices();
    final base = safeExportBasename('${project.name}_${room.name}_ks2');
    final dir = await getTemporaryDirectory();
    final ks2Template = await loadKs2TemplateJson(_doc, room: room);
    if (pdf) {
      final bytes = await buildKs2MaterialsPdf(
        project: project,
        room: room,
        stamp: stamp,
        prices: prices,
        templateJson: ks2Template,
      );
      final file = File(p.join(dir.path, '$base.pdf'));
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'КС-2 · ${room.name}'),
      );
    } else {
      final text = buildKs2FromTemplate(
        templateJson: ks2Template,
        project: project,
        room: room,
        stamp: stamp,
        prices: prices,
      );
      await Clipboard.setData(ClipboardData(text: text));
      await SharePlus.instance.share(
        ShareParams(text: text, subject: 'КС-2 · ${room.name}'),
      );
    }
  }

  Future<void> _exportKs2Xlsx() async {
    if (!await _ensureExportAllowed(forKs2: true)) return;
    final project = _project;
    final room = _room;
    if (project == null || room == null) return;
    final stamp = _doc.stamp.withDefaults(projectName: project.name, roomName: room.name);
    final prices = await _supplierPrices();
    final bytes = buildKs2Xlsx(project: project, room: room, stamp: stamp, prices: prices);
    final base = safeExportBasename('${project.name}_${room.name}_ks2');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '$base.xlsx'));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'КС-2 Excel · ${room.name}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final project = _project;
    final room = _room;
    if (project == null || room == null) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Документация')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }

    final (hwDone, hwTotal) = hiddenLayersProgress(room, _checklist);
    final summary = roomDocumentationSummary(room, project, checklist: _checklist);
    final workflow = roomWorkflowStatus(
      room,
      summary,
      checklist: _checklist,
      project: project,
      documentation: _doc,
    );

    return ScreenScaffold(
      appBar: AppBar(
        title: Text('${room.name}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: RoomWorkflowChip(status: workflow)),
          ),
          IconButton(
            tooltip: 'Реквизиты объекта',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentationProjectSettingsScreen(
                    projectId: widget.projectId,
                  ),
                ),
              );
              await _load();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DocTile(
            icon: Icons.receipt_long_outlined,
            title: 'КП и акты',
            subtitle: 'Смета · выдать КС-2 · реестр',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ContractWorkspaceScreen(
                    projectId: widget.projectId,
                    initialTab: 1,
                    focusRoomId: widget.roomId,
                  ),
                ),
              );
              await _load();
            },
          ),
          _DocTile(
            icon: Icons.request_quote_outlined,
            title: 'КП · ${room.name}',
            subtitle: 'Коммерческое предложение только по этому помещению',
            onTap: () => _exportRoomCommercialProposal(),
          ),
          _DocTile(
            icon: Icons.table_chart_outlined,
            title: 'Ведомость · ${room.name}',
            subtitle: 'Потолок → стены → пол',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentationVedomostScreen(
                    projectId: widget.projectId,
                    roomId: widget.roomId,
                  ),
                ),
              );
            },
          ),
          _DocTile(
            icon: Icons.map_outlined,
            title: 'Исполнительные схемы',
            subtitle: 'PNG / PDF · штамп объекта',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentationAsBuiltScreen(
                    projectId: widget.projectId,
                    roomId: widget.roomId,
                  ),
                ),
              );
            },
          ),
          _DocTile(
            icon: Icons.photo_library_outlined,
            title: 'Скрытые работы (опционально)',
            subtitle: hwTotal == 0
                ? 'Слои из отделки · не обязательны для КС'
                : 'Фото $hwDone/$hwTotal · не обязательны для КС',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentationHiddenLayersScreen(
                    projectId: widget.projectId,
                    roomId: widget.roomId,
                  ),
                ),
              );
              await _load();
            },
          ),
          _DocTile(
            icon: Icons.assignment_outlined,
            title: 'Собрать акт скрытых работ',
            subtitle: 'PDF · долгий тап — текст',
            onTap: () => _exportHiddenWorksAct(pdf: true),
            onLongPress: () => _exportHiddenWorksAct(pdf: false),
          ),
          SwitchListTile(
            title: const Text('Готово к акту'),
            subtitle: const Text('Помещение можно закрывать в КС'),
            value: _checklist.acceptedForHandover,
            onChanged: (v) async {
              setState(() => _checklist.acceptedForHandover = v);
              await _saveChecklist();
            },
          ),
        ],
      ),
    );
  }
}

class _MissingItemsCard extends StatelessWidget {
  const _MissingItemsCard({
    required this.items,
    required this.actions,
    required this.projectId,
    required this.roomId,
    this.onAfterStep,
  });

  final List<String> items;
  final List<({String stepId, String title})> actions;
  final int projectId;
  final int roomId;
  final Future<void> Function()? onAfterStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Не закрыто', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            for (var i = 0; i < actions.length && i < 6; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('• ${actions[i].title}', style: theme.textTheme.bodySmall),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  await openMissingDocumentationStep(
                    context,
                    projectId: projectId,
                    roomId: roomId,
                    stepId: actions[i].stepId,
                  );
                  await onAfterStep?.call();
                },
              ),
            if (items.length > 6)
              Text(
                '… и ещё ${items.length - 6}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class DocumentationChecklistScreen extends StatefulWidget {
  const DocumentationChecklistScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<DocumentationChecklistScreen> createState() =>
      _DocumentationChecklistScreenState();
}

class _DocumentationChecklistScreenState extends State<DocumentationChecklistScreen>
    with WidgetsBindingObserver {
  Project? _project;
  Room? _room;
  RoomDocumentationChecklist _checklist = RoomDocumentationChecklist();
  final _notesCtrl = TextEditingController();
  Timer? _notesSaveTimer;
  bool _loading = true;
  /// Captured for best-effort flush in [dispose] (context may be unmounted).
  ProjectRepository? _projects;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // ignore: discarded_futures
      _flushNotesSave();
    }
  }

  Future<void> _load() async {
    final projects = AppScope.of(context).projects;
    _projects = projects;
    final project = await projects.getProject(widget.projectId);
    Room? room;
    if (project != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    if (!mounted) return;
    setState(() {
      _project = project;
      _room = room;
      _checklist = RoomDocumentationChecklist.fromJson(room?.documentationChecklistJson);
      _notesCtrl.text = _checklist.notes;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final room = _room;
    if (room?.id == null) return;
    final json = roomChecklistJsonForSave(_checklist, room!.documentationChecklistJson);
    final projects = _projects ?? (mounted ? AppScope.of(context).projects : null);
    if (projects == null) return;
    await projects.updateRoomChecklist(
      room.id!,
      checklistJson: json,
    );
    room.documentationChecklistJson = json;
  }

  Future<void> _addPhoto(String stepId) async {
    final room = _room;
    if (room?.id == null) return;
    final path = await pickAndStoreDocumentationPhoto(
      projectId: widget.projectId,
      roomId: room!.id!,
      stepId: stepId,
    );
    if (path == null || !mounted) return;
    setState(() {
      final list = List<String>.from(_checklist.stepPhotos[stepId] ?? []);
      list.add(path);
      _checklist.stepPhotos[stepId] = list;
    });
    await _save();
  }

  Future<void> _toggleHiddenConfirm(String stepId, bool? v) async {
    setState(() {
      _checklist.hiddenWorksConfirmed[stepId] = v ?? false;
    });
    await _save();
  }

  Future<void> _removePhoto(String stepId, String path) async {
    await removeDocumentationPhoto(path);
    if (!mounted) return;
    setState(() {
      final list = List<String>.from(_checklist.stepPhotos[stepId] ?? [])
        ..remove(path);
      if (list.isEmpty) {
        _checklist.stepPhotos.remove(stepId);
      } else {
        _checklist.stepPhotos[stepId] = list;
      }
    });
    await _save();
  }

  void _scheduleNotesSave() {
    _notesSaveTimer?.cancel();
    _notesSaveTimer = Timer(const Duration(milliseconds: 700), () async {
      _checklist.notes = _notesCtrl.text;
      await _save();
    });
  }

  Future<void> _flushNotesSave() async {
    _notesSaveTimer?.cancel();
    _notesSaveTimer = null;
    _checklist.notes = _notesCtrl.text;
    await _save();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final pending = _notesSaveTimer != null;
    _notesSaveTimer?.cancel();
    _notesSaveTimer = null;
    if (pending) {
      _checklist.notes = _notesCtrl.text;
      final room = _room;
      final projects = _projects;
      if (room?.id != null && projects != null) {
        final json = roomChecklistJsonForSave(
          _checklist,
          room!.documentationChecklistJson,
        );
        // ignore: discarded_futures
        projects.updateRoomChecklist(room.id!, checklistJson: json);
      }
    }
    _notesCtrl.dispose();
    super.dispose();
  }

  void _viewPhoto(String path, String title) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(title, style: Theme.of(ctx).textTheme.titleSmall),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Закрыть'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    final project = _project;
    final room = _room;
    if (project == null || room == null) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Статус отделки')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }
    final summary = roomDocumentationSummary(room, project, checklist: _checklist);

    Widget section(String title, DocumentationPhase phase, int done, int total) {
      final items = summary.steps.where((s) => s.step.phase == phase).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleSmall),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('$done / $total'),
                ),
              ],
            ),
          ),
          for (final st in items)
            _ChecklistStepTile(
              status: st,
              onAcceptedToggle: st.step.id == DocumentationStep.accepted.id
                  ? (v) async {
                      setState(() => _checklist.acceptedForHandover = v ?? false);
                      await _save();
                    }
                  : null,
              onHiddenConfirm: st.step.kind == DocumentationStepKind.hiddenWork && st.applies
                  ? (v) => _toggleHiddenConfirm(st.step.id, v)
                  : null,
              hiddenConfirmed: _checklist.hiddenWorksConfirmed[st.step.id] ?? false,
              onAddPhoto: st.step.kind == DocumentationStepKind.hiddenWork && st.applies
                  ? () => _addPhoto(st.step.id)
                  : null,
              onDeletePhoto: st.step.kind == DocumentationStepKind.hiddenWork && st.applies
                  ? (path) => _removePhoto(st.step.id, path)
                  : null,
              onViewPhoto: (path) => _viewPhoto(path, st.step.title),
              photoPaths: _checklist.photosFor(st.step.id),
              stepNote: _checklist.stepNotes[st.step.id] ?? '',
              onStepNoteChanged: (v) {
                if (v.trim().isEmpty) {
                  _checklist.stepNotes.remove(st.step.id);
                } else {
                  _checklist.stepNotes[st.step.id] = v;
                }
                _scheduleNotesSave();
              },
            ),
        ],
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _flushNotesSave();
        if (mounted) Navigator.of(context).pop();
      },
      child: ScreenScaffold(
        appBar: AppBar(
          title: Text('Отделка · ${room.name}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _flushNotesSave();
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            section(
              'Проектирование и раскладки',
              DocumentationPhase.design,
              summary.designDone,
              summary.designTotal,
            ),
            section(
              'Скрытые работы (фото)',
              DocumentationPhase.hiddenWorks,
              summary.hiddenWorksDone,
              summary.hiddenWorksTotal,
            ),
            section('Сдача', DocumentationPhase.acceptance, summary.readyForHandover ? 1 : 0, 1),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Срок скрытых работ'),
              subtitle: Text(
                _checklist.dueDate == null
                    ? 'Не задан'
                    : '${_checklist.dueDate!.day.toString().padLeft(2, '0')}.'
                        '${_checklist.dueDate!.month.toString().padLeft(2, '0')}.'
                        '${_checklist.dueDate!.year}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.event),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _checklist.dueDate ?? now,
                    firstDate: now.subtract(const Duration(days: 30)),
                    lastDate: now.add(const Duration(days: 730)),
                  );
                  if (picked == null) return;
                  setState(() => _checklist.dueDate = picked);
                  await _save();
                },
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Примечания к акту',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              controller: _notesCtrl,
              onChanged: (v) {
                _checklist.notes = v;
                _scheduleNotesSave();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistStepTile extends StatelessWidget {
  const _ChecklistStepTile({
    required this.status,
    this.onAcceptedToggle,
    this.onHiddenConfirm,
    this.onAddPhoto,
    this.onDeletePhoto,
    this.onViewPhoto,
    this.hiddenConfirmed = false,
    this.photoPaths = const [],
    this.stepNote = '',
    this.onStepNoteChanged,
  });

  final StepStatus status;
  final ValueChanged<bool?>? onAcceptedToggle;
  final ValueChanged<bool?>? onHiddenConfirm;
  final VoidCallback? onAddPhoto;
  final ValueChanged<String>? onDeletePhoto;
  final ValueChanged<String>? onViewPhoto;
  final bool hiddenConfirmed;
  final List<String> photoPaths;
  final String stepNote;
  final ValueChanged<String>? onStepNoteChanged;

  @override
  Widget build(BuildContext context) {
    final st = status;
    final theme = Theme.of(context);
    final isHidden = st.step.kind == DocumentationStepKind.hiddenWork;
    final isAcceptance = st.step.id == DocumentationStep.accepted.id;
    final na = isHidden && !st.applies;

    final cardColor = na
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : null;

    Widget leadingIcon() {
      if (na) {
        return Icon(Icons.remove_circle_outline, color: theme.disabledColor);
      }
      if (st.done) {
        return Icon(Icons.check_circle, color: theme.colorScheme.primary);
      }
      return Icon(Icons.radio_button_unchecked, color: theme.disabledColor);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAcceptance && onAcceptedToggle != null)
              CheckboxListTile(
                value: st.done,
                onChanged: onAcceptedToggle,
                title: Text(st.step.title),
                subtitle: Text(st.hint),
                secondary: leadingIcon(),
              )
            else
              ListTile(
                leading: leadingIcon(),
                title: Text(
                  st.step.title,
                  style: na ? TextStyle(color: theme.disabledColor) : null,
                ),
                subtitle: Text(
                  na ? 'Не требуется · ${st.hint}' : st.hint,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (isHidden && st.applies) ...[
              if (onStepNoteChanged != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.note_alt_outlined, size: 18),
                    label: Text(stepNote.isEmpty ? 'Комментарий к этапу' : stepNote),
                    onPressed: () async {
                      final ctrl = TextEditingController(text: stepNote);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(st.step.title),
                          content: TextField(
                            controller: ctrl,
                            maxLines: 3,
                            decoration: const InputDecoration(hintText: 'Комментарий'),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
                          ],
                        ),
                      );
                      if (ok == true) onStepNoteChanged!(ctrl.text);
                    },
                  ),
                ),
              if (photoPaths.isNotEmpty)
                _PhotoThumbnailStrip(
                  paths: photoPaths,
                  onTap: onViewPhoto,
                  onDelete: onDeletePhoto,
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (onAddPhoto != null)
                      OutlinedButton.icon(
                        onPressed: onAddPhoto,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: const Text('Фото'),
                      ),
                    if (onHiddenConfirm != null)
                      FilterChip(
                        label: const Text('Без фото'),
                        selected: hiddenConfirmed,
                        onSelected: (v) => onHiddenConfirm!(v),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoThumbnailStrip extends StatelessWidget {
  const _PhotoThumbnailStrip({
    required this.paths,
    this.onTap,
    this.onDelete,
  });

  final List<String> paths;
  final ValueChanged<String>? onTap;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final path = paths[i];
          final file = File(path);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                onTap: onTap == null ? null : () => onTap!(path),
                borderRadius: BorderRadius.circular(6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: file.existsSync()
                      ? Image.file(file, width: 64, height: 64, fit: BoxFit.cover)
                      : Container(
                          width: 64,
                          height: 64,
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                ),
              ),
              if (onDelete != null)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onDelete!(path),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.close, size: 16),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class DocumentationAsBuiltScreen extends StatefulWidget {
  const DocumentationAsBuiltScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<DocumentationAsBuiltScreen> createState() => _DocumentationAsBuiltScreenState();
}

class _DocumentationAsBuiltScreenState extends State<DocumentationAsBuiltScreen> {
  Project? _project;
  Room? _room;
  ProjectDocumentation _doc = ProjectDocumentation();
  Uint8List? _preview;
  AsBuiltSchemeKind _scheme = AsBuiltSchemeKind.ceiling;
  AsBuiltExportOptions _exportOptions = const AsBuiltExportOptions();
  bool _loading = true;
  bool _exporting = false;
  bool _layersSeeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    Room? room;
    if (project != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    Uint8List? png;
    AsBuiltExportOptions exportOptions = _exportOptions;
    if (room != null && room.hasLayout) {
      final layersRaw = room.layoutViewJson?['layers'];
      if (layersRaw is Map && !_layersSeeded) {
        exportOptions = AsBuiltExportOptions.fromLayoutLayers(
          LayoutLayerVisibility.fromJson(Map<String, dynamic>.from(layersRaw)),
        ).copyWith(
          // Keep session-only presentation toggles; dims come from layout layers.
          showTiles: _exportOptions.showTiles,
          showGridStep: _exportOptions.showGridStep,
          showLightCallouts: _exportOptions.showLightCallouts,
        );
        _layersSeeded = true;
      }
      final stamp = ProjectDocumentation.fromJson(project?.documentationJson)
          .stamp
          .withDefaults(projectName: project?.name ?? '', roomName: room.name);
      png = await renderStampedSchemePng(
        room: room,
        stamp: stamp,
        scheme: _scheme,
        options: exportOptions,
      );
    }
    if (!mounted) return;
    setState(() {
      _project = project;
      _room = room;
      _doc = ProjectDocumentation.fromJson(project?.documentationJson);
      _exportOptions = exportOptions;
      _preview = png;
      _loading = false;
    });
  }

  Future<void> _setScheme(AsBuiltSchemeKind kind) async {
    setState(() {
      _scheme = kind;
      _loading = true;
    });
    await _load();
  }

  Future<void> _toggleLayer(AsBuiltExportOptions Function(AsBuiltExportOptions) fn) async {
    setState(() {
      _exportOptions = fn(_exportOptions);
      _loading = true;
    });
    await _load();
  }

  Future<File> _writeTemp(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _exportDxf() async {
    final room = _room;
    final project = _project;
    if (room == null || project == null || !room.hasLayout) return;
    setState(() => _exporting = true);
    try {
      final grid = gridForDxfExport(room, project);
      final isFloor = _scheme == AsBuiltSchemeKind.floor;
      final isWalls = _scheme == AsBuiltSchemeKind.walls;
      // Walls scheme: plan contour only (no elevation DXF yet).
      final bytes = buildLayoutDxf(
        room: room,
        grid: grid,
        includeGrid: isFloor || isWalls ? false : _exportOptions.showGrid,
        includeWalls: _exportOptions.showWalls,
        includeGuides: isFloor || isWalls ? false : _exportOptions.showGuides,
        includeLights: isFloor || isWalls ? false : _exportOptions.showLights,
        includeFloor: isFloor || (!isWalls && _exportOptions.showFloor),
        includeNotes: !isWalls && _exportOptions.showNotes,
        includeDimensions: _exportOptions.showWallDims || _exportOptions.showTileDims,
      );
      final file = await _writeTemp(
        safeExportBasename('${project.name}_${room.name}_layout') + '.dxf',
        bytes,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: isWalls ? 'DXF · контур стен · ${room.name}' : 'DXF · ${room.name}',
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    final room = _room;
    final project = _project;
    if (room == null || project == null || !room.hasLayout) return;
    setState(() => _exporting = true);
    try {
      final stamp = _doc.stamp.withDefaults(
        projectName: project.name,
        roomName: room.name,
      );
      final pdf = await buildSchemePdf(
        project: project,
        room: room,
        stamp: stamp,
        scheme: _scheme,
        options: _exportOptions,
      );
      if (pdf.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF пуст — включите слои схемы')),
          );
        }
        return;
      }
      final base = safeExportBasename('${project.name}_${room.name}_scheme');
      final file = await _writeTemp('$base.pdf', pdf);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: stamp.sheetTitle),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPng() async {
    final room = _room;
    final project = _project;
    if (room == null || project == null || !room.hasLayout) return;
    setState(() => _exporting = true);
    try {
      final stamp = _doc.stamp.withDefaults(
        projectName: project.name,
        roomName: room.name,
      );
      final png = await renderStampedSchemePng(
        room: room,
        stamp: stamp,
        scheme: _scheme,
        options: _exportOptions,
      );
      if (png.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PNG пуст — включите слои схемы')),
          );
        }
        return;
      }
      final base = safeExportBasename('${project.name}_${room.name}_${_scheme.name}');
      final file = await _writeTemp('$base.png', png);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Исполнительная схема'),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = _room;
    return ScreenScaffold(
      appBar: AppBar(
        title: Text('Схема · ${room?.name ?? ''}'),
      ),
      body: room == null || !room.hasLayout
          ? const Center(child: Text('Сначала нарисуйте контур помещения'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AsBuiltSchemeKind>(
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        ),
                        textStyle: WidgetStatePropertyAll(
                          Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      segments: AsBuiltSchemeKind.values
                          .map(
                            (k) => ButtonSegment(
                              value: k,
                              label: Text(
                                k.labelRu,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      selected: {_scheme},
                      onSelectionChanged: (s) => _setScheme(s.first),
                    ),
                  ),
                ),
                if (_scheme != AsBuiltSchemeKind.walls) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (_scheme == AsBuiltSchemeKind.ceiling ||
                            _scheme == AsBuiltSchemeKind.combined) ...[
                          FilterChip(
                            label: const Text('Плитки'),
                            selected: _exportOptions.showTiles,
                            onSelected: (v) => _toggleLayer((o) => o.copyWith(showTiles: v)),
                          ),
                          FilterChip(
                            label: const Text('Сетка'),
                            selected: _exportOptions.showGrid,
                            onSelected: (v) => _toggleLayer((o) => o.copyWith(showGrid: v)),
                          ),
                          FilterChip(
                            label: const Text('Направл.'),
                            selected: _exportOptions.showGuides,
                            onSelected: (v) => _toggleLayer((o) => o.copyWith(showGuides: v)),
                          ),
                          FilterChip(
                            label: const Text('Свет'),
                            selected: _exportOptions.showLights,
                            onSelected: (v) => _toggleLayer((o) => o.copyWith(showLights: v)),
                          ),
                          FilterChip(
                            label: const Text('Резы плит'),
                            selected: _exportOptions.showTileDims,
                            onSelected: (v) => _toggleLayer((o) => o.copyWith(showTileDims: v)),
                          ),
                          FilterChip(
                            label: const Text('Шаг сетки'),
                            selected: _exportOptions.showGridStep,
                            onSelected: (v) => _toggleLayer((o) => o.copyWith(showGridStep: v)),
                          ),
                          FilterChip(
                            label: const Text('Свет №'),
                            selected: _exportOptions.showLightCallouts,
                            onSelected: (v) => _toggleLayer((o) => o.copyWith(showLightCallouts: v)),
                          ),
                        ],
                        FilterChip(
                          label: const Text('Размеры стен'),
                          selected: _exportOptions.showWallDims,
                          onSelected: (v) => _toggleLayer((o) => o.copyWith(showWallDims: v)),
                        ),
                        // Ceiling/combined: walls & notes affect PNG. Floor PNG only has wall dims.
                        if (_scheme != AsBuiltSchemeKind.floor) ...[
                          FilterChip(
                            label: const Text('Стены'),
                            selected: _exportOptions.showWalls,
                            onSelected: (v) => _toggleLayer((o) => o.copyWith(showWalls: v)),
                          ),
                          if (_scheme == AsBuiltSchemeKind.combined)
                            FilterChip(
                              label: const Text('Пол'),
                              selected: _exportOptions.showFloor,
                              onSelected: (v) => _toggleLayer((o) => o.copyWith(showFloor: v)),
                            ),
                          if (_scheme == AsBuiltSchemeKind.ceiling)
                            FilterChip(
                              label: const Text('Пол'),
                              selected: _exportOptions.showFloor,
                              onSelected: (v) => _toggleLayer((o) => o.copyWith(showFloor: v)),
                            ),
                          FilterChip(
                            label: const Text('Заметки'),
                            selected: _exportOptions.showNotes,
                            onSelected: (v) => _toggleLayer((o) => o.copyWith(showNotes: v)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                Expanded(
                  child: _preview == null
                      ? const Center(child: CircularProgressIndicator())
                      : InteractiveViewer(
                          child: Center(
                            child: Image.memory(_preview!, fit: BoxFit.contain),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exporting ? null : _exportDxf,
                          icon: const Icon(Icons.architecture_outlined),
                          label: Text(
                            _scheme == AsBuiltSchemeKind.walls ? 'DXF контур' : 'DXF',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _exporting ? null : _exportPng,
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('PNG'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _exporting ? null : _exportPdf,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('PDF'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class DocumentationVedomostScreen extends StatefulWidget {
  const DocumentationVedomostScreen({
    super.key,
    required this.projectId,
    this.roomId,
  });

  final int projectId;

  /// When null, show project-wide vedomost (all rooms).
  final int? roomId;

  bool get projectWide => roomId == null;

  @override
  State<DocumentationVedomostScreen> createState() => _DocumentationVedomostScreenState();
}

class _DocumentationVedomostScreenState extends State<DocumentationVedomostScreen> {
  Project? _project;
  Room? _room;
  ProjectDocumentation _doc = ProjectDocumentation();
  String _preview = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    Room? room;
    if (project != null && widget.roomId != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    final doc = ProjectDocumentation.fromJson(project?.documentationJson);
    var preview = '';
    if (project != null) {
      if (widget.projectWide) {
        final stamp = doc.stamp.withDefaults(projectName: project.name, roomName: '');
        preview = buildProjectVedomostText(project: project, stamp: stamp);
      } else if (room != null) {
        final stamp = doc.stamp.withDefaults(
          projectName: project.name,
          roomName: room.name,
        );
        final templateJson = await loadVedomostTemplateJson(doc, room: room);
        if (templateJson != null) {
          preview = buildVedomostFromTemplate(
            templateJson: templateJson,
            project: project,
            room: room,
            stamp: stamp,
          );
        } else {
          preview = buildVedomostText(project: project, room: room, stamp: stamp);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _project = project;
      _room = room;
      _doc = doc;
      _preview = preview;
      _loading = false;
    });
  }

  Future<Map<String, SupplierPrice>?> _supplierPrices() async {
    return loadPrimarySupplierPrices(
      repo: AppScope.of(context).suppliers,
      doc: _doc,
    );
  }

  Future<void> _share({required bool csv, bool pdf = false}) async {
    final project = _project;
    if (project == null) return;
    if (widget.projectWide) {
      final stamp = _doc.stamp.withDefaults(projectName: project.name, roomName: '');
      final text = csv
          ? '\uFEFF${buildProjectVedomostCsv(project: project, stamp: stamp)}'
          : buildProjectVedomostText(project: project, stamp: stamp);
      if (pdf) {
        final bytes = await buildProjectVedomostPdf(project: project, stamp: stamp);
        final base = safeExportBasename('${project.name}_vedomost_object');
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path, '$base.pdf'));
        await file.writeAsBytes(bytes);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], subject: 'Ведомость объекта'),
        );
        return;
      }
      if (csv) {
        final base = safeExportBasename('${project.name}_vedomost_object');
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path, '$base.csv'));
        await file.writeAsString(text, encoding: utf8);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], subject: 'Ведомость объекта'),
        );
      } else {
        await Clipboard.setData(ClipboardData(text: text));
        await SharePlus.instance.share(
          ShareParams(text: text, subject: 'Ведомость объекта'),
        );
      }
      return;
    }

    final room = _room;
    if (room == null) return;
    if (!room.hasLayout) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет закрытого чертежа — ведомость недоступна')),
      );
      return;
    }
    final stamp = _doc.stamp.withDefaults(
      projectName: project.name,
      roomName: room.name,
    );
    final prices = await _supplierPrices();
    if (pdf) {
      final templateJson = await loadVedomostTemplateJson(_doc, room: room);
      final bytes = await buildVedomostPdf(
        project: project,
        room: room,
        stamp: stamp,
        templateJson: templateJson,
        prices: prices,
      );
      final base = safeExportBasename('${project.name}_${room.name}_vedomost');
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, '$base.pdf'));
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Ведомость · ${room.name}'),
      );
      return;
    }
    final text = csv
        ? buildVedomostExcelCsv(project: project, room: room, stamp: stamp, prices: prices)
        : buildVedomostTextWithPricing(
            project: project,
            room: room,
            stamp: stamp,
            prices: prices,
          );
    if (csv) {
      final base = safeExportBasename('${project.name}_${room.name}_vedomost');
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, '$base.csv'));
      await file.writeAsString(text, encoding: utf8);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Ведомость · ${room.name}'),
      );
    } else {
      await Clipboard.setData(ClipboardData(text: text));
      await SharePlus.instance.share(
        ShareParams(text: text, subject: 'Ведомость · ${room.name}'),
      );
    }
  }

  Future<void> _shareXlsx() async {
    final project = _project;
    if (project == null) return;
    if (widget.projectWide) {
      final stamp = _doc.stamp.withDefaults(projectName: project.name, roomName: '');
      final bytes = buildProjectVedomostXlsx(project: project, stamp: stamp);
      final base = safeExportBasename('${project.name}_vedomost_object');
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, '$base.xlsx'));
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Ведомость объекта'),
      );
      return;
    }
    final room = _room;
    if (room == null) return;
    if (!room.hasLayout) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет закрытого чертежа — ведомость недоступна')),
      );
      return;
    }
    final stamp = _doc.stamp.withDefaults(projectName: project.name, roomName: room.name);
    final prices = await _supplierPrices();
    final bytes = buildVedomostXlsx(
      project: project,
      room: room,
      stamp: stamp,
      prices: prices,
    );
    final base = safeExportBasename('${project.name}_${room.name}_vedomost');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '$base.xlsx'));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'Ведомость · ${room.name}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    final title = widget.projectWide
        ? 'Ведомость объекта'
        : 'Ведомость · ${_room?.name ?? ''}';
    return ScreenScaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'PDF',
            onPressed: () => _share(csv: false, pdf: true),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'XLSX',
            onPressed: _shareXlsx,
            icon: const Icon(Icons.grid_on),
          ),
          IconButton(
            tooltip: 'CSV',
            onPressed: () => _share(csv: true),
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: 'Поделиться',
            onPressed: () => _share(csv: false),
            icon: const Icon(Icons.share),
          ),
        ],
      ),
      body: _preview.isEmpty
          ? const Center(child: Text('Нет данных для ведомости'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_preview, style: const TextStyle(fontFamily: 'monospace')),
            ),
    );
  }
}

class DocumentationProjectSettingsScreen extends StatefulWidget {
  const DocumentationProjectSettingsScreen({super.key, required this.projectId});

  final int projectId;

  @override
  State<DocumentationProjectSettingsScreen> createState() =>
      _DocumentationProjectSettingsScreenState();
}

class _DocumentationProjectSettingsScreenState
    extends State<DocumentationProjectSettingsScreen> {
  Project? _project;
  ProjectDocumentation _doc = ProjectDocumentation();
  bool _loading = true;
  late final Map<String, TextEditingController> _fields;
  late final Map<String, TextEditingController> _contractFields;

  @override
  void initState() {
    super.initState();
    _fields = {};
    _contractFields = {};
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final c in _contractFields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    final doc = ProjectDocumentation.fromJson(project?.documentationJson);
    normalizeStampCustomerAddress(doc.stamp);
    normalizeContractCustomerAddress(doc.contract);
    if (!mounted) return;
    setState(() {
      _project = project;
      _doc = doc;
      _loading = false;
    });
    _bindFields(doc.stamp, project?.name ?? '');
    _bindContractFields(doc.contract);
  }

  void _bindContractFields(ProjectContractInfo contract) {
    for (final c in _contractFields.values) {
      c.dispose();
    }
    _contractFields.clear();
    void add(String key, String value) {
      _contractFields[key] = TextEditingController(text: value);
    }

    add('contract_number', contract.contractNumber);
    add('estimate_number', contract.estimateNumber);
    add('customer_inn', contract.customerInn);
    add('customer_name', contract.customerName);
    add('customer_okpo', contract.customerOkpo);
    add('build_site', contract.buildSite);
    add('vat_rate', contract.vatRatePercent > 0 ? contract.vatRatePercent.toStringAsFixed(0) : '20');
  }

  void _bindFields(DocumentationStamp stamp, String projectName) {
    for (final c in _fields.values) {
      c.dispose();
    }
    _fields.clear();
    void add(String key, String value) {
      _fields[key] = TextEditingController(text: value);
    }

    add('object', stamp.objectName.isEmpty ? projectName : stamp.objectName);
    add('customer', stamp.customer);
    add('address', stamp.address);
    add('executor', stamp.executor);
    add('designer', stamp.designer);
    add('document_number', stamp.documentNumber);
    add('sheet_title', stamp.sheetTitle);
    add('scale_note', stamp.scaleNote);
  }

  Future<void> _save() async {
    final project = _project;
    if (project?.id == null) return;
    _doc.stamp = DocumentationStamp(
      objectName: _fields['object']!.text.trim(),
      customer: _fields['customer']!.text.trim(),
      address: _fields['address']!.text.trim(),
      executor: _fields['executor']!.text.trim(),
      designer: _fields['designer']!.text.trim(),
      documentNumber: _fields['document_number']!.text.trim(),
      sheetTitle: _fields['sheet_title']!.text.trim(),
      scaleNote: _fields['scale_note']!.text.trim(),
      issueDate: _doc.stamp.issueDate,
    );
    _doc.contract = ProjectContractInfo(
      contractNumber: _contractFields['contract_number']!.text.trim(),
      estimateNumber: _contractFields['estimate_number']!.text.trim(),
      customerInn: _contractFields['customer_inn']!.text.trim(),
      customerName: _contractFields['customer_name']!.text.trim(),
      customerOkpo: _contractFields['customer_okpo']!.text.trim(),
      buildSite: _contractFields['build_site']!.text.trim(),
      contractDate: _doc.contract.contractDate,
      investorOkpo: _doc.contract.investorOkpo,
      vatRatePercent:
          double.tryParse(_contractFields['vat_rate']!.text.replaceAll(',', '.')) ?? 20,
      vatExempt: _doc.contract.vatExempt,
    );
    project!.documentationJson = _doc.toJson();
    await AppScope.of(context).projects.updateProjectDocumentation(
          project.id!,
          documentationJson: _doc.toJson(),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено')),
      );
    }
  }

  bool get _isDirty {
    if (_loading || _fields.isEmpty || _contractFields.isEmpty) return false;
    final stamp = _doc.stamp;
    if (_fields['object']!.text.trim() != stamp.objectName) return true;
    if (_fields['customer']!.text.trim() != stamp.customer) return true;
    if (_fields['address']!.text.trim() != stamp.address) return true;
    if (_fields['executor']!.text.trim() != stamp.executor) return true;
    if (_fields['designer']!.text.trim() != stamp.designer) return true;
    if (_fields['document_number']!.text.trim() != stamp.documentNumber) return true;
    if (_fields['sheet_title']!.text.trim() != stamp.sheetTitle) return true;
    if (_fields['scale_note']!.text.trim() != stamp.scaleNote) return true;
    final contract = _doc.contract;
    if (_contractFields['contract_number']!.text.trim() != contract.contractNumber) return true;
    if (_contractFields['estimate_number']!.text.trim() != contract.estimateNumber) return true;
    if (_contractFields['customer_inn']!.text.trim() != contract.customerInn) return true;
    final vat =
        double.tryParse(_contractFields['vat_rate']!.text.replaceAll(',', '.')) ??
            contract.vatRatePercent;
    if ((vat - contract.vatRatePercent).abs() > 0.01) return true;
    return false;
  }

  Future<bool> _leaveSettings() async {
    if (!_isDirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сохранить настройки?'),
        content: const Text('Есть несохранённые изменения штампа или договора.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Остаться')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Не сохранять')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Сохранить')),
        ],
      ),
    );
    if (choice == null || choice == 'cancel' || !mounted) return false;
    if (choice == 'save') await _save();
    return true;
  }

  Future<void> _pickTemplate(void Function(String path) onPicked) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
    );
    if (files.isEmpty || files.first.path == null) return;
    final src = File(files.first.path!);
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory(p.join(dir.path, 'doc_templates'));
    await destDir.create(recursive: true);
    final dest = File(p.join(destDir.path, p.basename(src.path)));
    await src.copy(dest.path);
    onPicked(dest.path);
    await _save();
  }

  Future<void> _useBundledTemplates() async {
    setState(() {
      _doc.vedomostTemplatePath = null;
      _doc.ks2TemplatePath = null;
      _doc.ks3TemplatePath = null;
      _doc.actHiddenTemplatePath = null;
    });
    await _save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Используются встроенные шаблоны')),
      );
    }
  }

  Future<void> _importProjectDocument() async {
    await runProjectDocumentImportFlow(
      context,
      doc: _doc,
      onSave: (updated) async {
        setState(() {
          _doc = updated;
          _bindFields(updated.stamp, _project?.name ?? '');
          _bindContractFields(updated.contract);
        });
        final project = _project;
        if (project?.id != null) {
          project!.documentationJson = _doc.toJson();
          await AppScope.of(context).projects.updateProjectDocumentation(
                project.id!,
                documentationJson: _doc.toJson(),
              );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _leaveSettings() && mounted) Navigator.pop(context);
      },
      child: ScreenScaffold(
      appBar: AppBar(
        title: const Text('Настройки документации'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (await _leaveSettings() && mounted) Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Штамп (исполнительная схема)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final entry in [
            ('object', 'Объект'),
            ('customer', 'Заказчик'),
            ('address', 'Адрес'),
            ('executor', 'Исполнитель'),
            ('designer', 'Проектировщик'),
            ('document_number', '№ документа'),
            ('sheet_title', 'Наименование документа'),
            ('scale_note', 'Масштаб / примечание'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _fields[entry.$1],
                decoration: InputDecoration(
                  labelText: entry.$2,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () async {
                  setState(() => _doc = applyPartnerDefaults(_doc));
                  _bindFields(_doc.stamp, _project?.name ?? '');
                  await _save();
                },
                child: const Text('ИП Гусев · исполнитель'),
              ),
              OutlinedButton(
                onPressed: () async {
                  setState(
                    () => _doc = applyPartnerDefaults(_doc, fillAvangardCustomer: true),
                  );
                  _bindFields(_doc.stamp, _project?.name ?? '');
                  _bindContractFields(_doc.contract);
                  await _save();
                },
                child: const Text('+ заказчик Авангард'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 24),
          Text('Договор / смета', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final entry in [
            ('contract_number', '№ договора'),
            ('estimate_number', '№ сметы'),
            ('customer_name', 'Заказчик (полное наименование)'),
            ('customer_okpo', 'ОКПО заказчика'),
            ('build_site', 'Стройка / адрес'),
            ('customer_inn', 'ИНН заказчика'),
            ('vat_rate', 'НДС, %'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _contractFields[entry.$1],
                decoration: InputDecoration(
                  labelText: entry.$2,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          const Divider(height: 24),
          Text('Прайс поставщика', style: Theme.of(context).textTheme.titleMedium),
          Text(
            'Используется для ведомости, КС-2 и ZIP, если нет только проектных расценок.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Supplier>>(
            future: AppScope.of(context).suppliers.listSuppliers(),
            builder: (context, snap) {
              final list = snap.data ?? const <Supplier>[];
              return DropdownButtonFormField<int?>(
                value: _doc.primarySupplierId,
                decoration: const InputDecoration(
                  labelText: 'Основной поставщик',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Первый в списке')),
                  for (final s in list)
                    if (s.id != null)
                      DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (id) async {
                  setState(() => _doc.primarySupplierId = id);
                  await _save();
                },
              );
            },
          ),
          const Divider(height: 24),
          Text('Состав работ по договору', style: Theme.of(context).textTheme.titleMedium),
          Text(
            'Отметьте, что входит в объект: только стены, пол+стены без потолка и т.д.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final scope in WorkScope.values)
                FilterChip(
                  label: Text(scope.labelRu),
                  selected: _doc.enabledWorkScopes.contains(scope.name),
                  onSelected: (on) async {
                    setState(() {
                      if (on) {
                        if (!_doc.enabledWorkScopes.contains(scope.name)) {
                          _doc.enabledWorkScopes.add(scope.name);
                        }
                      } else {
                        _doc.enabledWorkScopes.remove(scope.name);
                        if (_doc.enabledWorkScopes.isEmpty) {
                          _doc.enabledWorkScopes.add(scope.name);
                        }
                      }
                    });
                    await _save();
                  },
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final project = _project;
                if (project == null) return;
                setState(() {
                  _doc.enabledWorkScopes = WorkScope.names(inferWorkScopesFromProject(project));
                });
                await _save();
              },
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Определить по комнатам'),
            ),
          ),
          const Divider(height: 24),
          Text('КС-2 / КС-3', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Загрузить документ'),
            subtitle: const Text(
              'Excel, Word, PDF, TXT, CSV — заказчик, договор, расценки',
            ),
            onTap: _importProjectDocument,
          ),
          ListTile(
            leading: const Icon(Icons.price_change_outlined),
            title: const Text('Расценки объекта'),
            subtitle: Text(
              _doc.ks2Prices.isEmpty
                  ? 'Не заданы — используется прайс поставщика'
                  : '${_doc.ks2Prices.length} позиций',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentationProjectPricesScreen(projectId: widget.projectId),
                ),
              );
              await _load();
            },
          ),
          SwitchListTile(
            title: const Text('Только расценки объекта'),
            subtitle: const Text('Не подставлять прайс поставщика в КС-2/КС-3'),
            value: _doc.useProjectPricesOnly,
            onChanged: (v) async {
              setState(() => _doc.useProjectPricesOnly = v);
              await _save();
            },
          ),
          SwitchListTile(
            title: const Text('Строгий режим КС-2'),
            subtitle: const Text('Блокировать экспорт, если не хватает расценок'),
            value: _doc.requireFullKs2Pricing,
            onChanged: (v) async {
              setState(() => _doc.requireFullKs2Pricing = v);
              await _save();
            },
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('КП и акты'),
            subtitle: Text(
              _doc.ks2Acts.isEmpty
                  ? 'Смета · выдача · реестр'
                  : 'Актов: ${_doc.ks2Acts.length}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ContractWorkspaceScreen(
                    projectId: widget.projectId,
                    initialTab: 1,
                  ),
                ),
              );
              await _load();
            },
          ),
          const Divider(height: 24),
          Text('Шаблоны документов', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            title: const Text('Ведомость (JSON)'),
            subtitle: Text(_doc.vedomostTemplatePath ?? 'Встроенный / текстовый'),
            trailing: const Icon(Icons.upload_file),
            onTap: () => _pickTemplate((p) => _doc.vedomostTemplatePath = p),
          ),
          ListTile(
            title: const Text('КС-2 (JSON)'),
            subtitle: Text(_doc.ks2TemplatePath ?? 'Встроенный _example.ks2'),
            trailing: const Icon(Icons.upload_file),
            onTap: () => _pickTemplate((p) => _doc.ks2TemplatePath = p),
          ),
          ListTile(
            title: const Text('КС-3 (JSON)'),
            subtitle: Text(_doc.ks3TemplatePath ?? 'Встроенный _example.ks3'),
            trailing: const Icon(Icons.upload_file),
            onTap: () => _pickTemplate((p) => _doc.ks3TemplatePath = p),
          ),
          ListTile(
            title: const Text('Акт скрытых работ (JSON)'),
            subtitle: Text(_doc.actHiddenTemplatePath ?? 'Встроенный _example.act_hidden'),
            trailing: const Icon(Icons.upload_file),
            onTap: () => _pickTemplate((p) => _doc.actHiddenTemplatePath = p),
          ),
          TextButton.icon(
            onPressed: _useBundledTemplates,
            icon: const Icon(Icons.restore),
            label: const Text('Сбросить на встроенные шаблоны'),
          ),
        ],
      ),
      ),
    );
  }
}

class DocumentationRoomExportTemplatesScreen extends StatefulWidget {
  const DocumentationRoomExportTemplatesScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<DocumentationRoomExportTemplatesScreen> createState() =>
      _DocumentationRoomExportTemplatesScreenState();
}

class _DocumentationRoomExportTemplatesScreenState
    extends State<DocumentationRoomExportTemplatesScreen> {
  Room? _room;
  ProjectDocumentation _doc = ProjectDocumentation();
  RoomExportTemplates _templates = RoomExportTemplates();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    Room? room;
    if (project != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    if (!mounted) return;
    setState(() {
      _room = room;
      _doc = ProjectDocumentation.fromJson(project?.documentationJson);
      _templates = RoomExportTemplates.fromChecklistJson(room?.documentationChecklistJson);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final room = _room;
    if (room?.id == null) return;
    final checklist = RoomDocumentationChecklist.fromJson(room!.documentationChecklistJson);
    final json = RoomExportTemplates.mergeIntoChecklist(
      checklist.toJson(),
      _templates,
    );
    await AppScope.of(context).projects.updateRoomChecklist(
          room.id!,
          checklistJson: json,
        );
    room.documentationChecklistJson = json;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено')),
      );
    }
  }

  Future<void> _pickTemplate(void Function(String path) onPicked) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
    );
    if (files.isEmpty || files.first.path == null) return;
    final src = File(files.first.path!);
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory(p.join(dir.path, 'doc_templates', 'rooms'));
    await destDir.create(recursive: true);
    final dest = File(p.join(destDir.path, p.basename(src.path)));
    await src.copy(dest.path);
    onPicked(dest.path);
    await _save();
  }

  Future<void> _clearOverrides() async {
    setState(() {
      _templates = RoomExportTemplates();
    });
    await _save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Используются шаблоны проекта')),
      );
    }
  }

  String _label(String? path, String projectFallback) {
    if (path != null && path.isNotEmpty) return p.basename(path);
    return 'Как у проекта ($projectFallback)';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = _room;
    if (room == null) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Шаблоны комнаты')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }
    return ScreenScaffold(
      appBar: AppBar(title: Text('${room.name} · шаблоны')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Переопределение шаблонов только для этой комнаты. '
            'Если не задано — используются шаблоны проекта или встроенные.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Ведомость (JSON)'),
            subtitle: Text(_label(
              _templates.vedomostTemplatePath,
              _doc.vedomostTemplatePath == null ? 'текстовый' : p.basename(_doc.vedomostTemplatePath!),
            )),
            trailing: const Icon(Icons.upload_file),
            onTap: () => _pickTemplate((path) => _templates.vedomostTemplatePath = path),
          ),
          ListTile(
            title: const Text('КС-2 (JSON)'),
            subtitle: Text(_label(
              _templates.ks2TemplatePath,
              _doc.ks2TemplatePath == null ? '_example.ks2' : p.basename(_doc.ks2TemplatePath!),
            )),
            trailing: const Icon(Icons.upload_file),
            onTap: () => _pickTemplate((path) => _templates.ks2TemplatePath = path),
          ),
          ListTile(
            title: const Text('Акт скрытых работ (JSON)'),
            subtitle: Text(_label(
              _templates.actHiddenTemplatePath,
              _doc.actHiddenTemplatePath == null
                  ? '_example.act_hidden'
                  : p.basename(_doc.actHiddenTemplatePath!),
            )),
            trailing: const Icon(Icons.upload_file),
            onTap: () => _pickTemplate((path) => _templates.actHiddenTemplatePath = path),
          ),
          TextButton.icon(
            onPressed: _clearOverrides,
            icon: const Icon(Icons.restore),
            label: const Text('Сбросить — как у проекта'),
          ),
        ],
      ),
    );
  }
}

class DocumentationCertificatesScreen extends StatefulWidget {
  const DocumentationCertificatesScreen({super.key, required this.projectId});

  final int projectId;

  @override
  State<DocumentationCertificatesScreen> createState() =>
      _DocumentationCertificatesScreenState();
}

class _DocumentationCertificatesScreenState extends State<DocumentationCertificatesScreen> {
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
  }

  Future<void> _addCertificate() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
    );
    if (files.isEmpty || files.first.path == null) return;
    if (!mounted) return;
    final picked = files.first;
    final labelCtrl = TextEditingController(text: picked.name);
    var materialKey = 'all';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сертификат'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: materialKey,
              decoration: const InputDecoration(labelText: 'Тип материала'),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('Все материалы')),
                const DropdownMenuItem(value: 'finish_floor', child: Text('Отделка пола')),
                const DropdownMenuItem(value: 'finish_wall', child: Text('Отделка стен')),
                const DropdownMenuItem(value: 'finish_ceiling', child: Text('Отделка потолка')),
                ...catalogEntries.map(
                  (e) => DropdownMenuItem(value: e.itemKey, child: Text(e.displayName)),
                ),
              ],
              onChanged: (v) => materialKey = v ?? 'all',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Добавить')),
        ],
      ),
    );
    if (ok != true) return;

    final src = File(picked.path!);
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory(p.join(dir.path, 'certs', '${widget.projectId}'));
    await destDir.create(recursive: true);
    final dest = File(p.join(destDir.path, p.basename(src.path)));
    await src.copy(dest.path);

    setState(() {
      _doc.certificates.add(
        MaterialCertificate(
          materialKey: materialKey,
          label: labelCtrl.text.trim(),
          localPath: dest.path,
          uploadedAt: DateTime.now(),
        ),
      );
    });
    await _save();
  }

  Future<void> _shareCert(MaterialCertificate cert) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(cert.localPath)], subject: cert.label),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ScreenScaffold(
      appBar: AppBar(title: const Text('Сертификаты')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCertificate,
        icon: const Icon(Icons.add),
        label: const Text('Файл'),
      ),
      body: _doc.certificates.isEmpty
          ? const Center(child: Text('Прикрепите PDF или фото сертификата'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _doc.certificates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = _doc.certificates[i];
                return ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(c.label),
                  subtitle: Text(c.materialKey),
                  trailing: IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () => _shareCert(c),
                  ),
                );
              },
            ),
    );
  }
}

class GeometryCaptureInfoScreen extends StatefulWidget {
  const GeometryCaptureInfoScreen({super.key});

  @override
  State<GeometryCaptureInfoScreen> createState() => _GeometryCaptureInfoScreenState();
}

class _GeometryCaptureInfoScreenState extends State<GeometryCaptureInfoScreen> {
  List<FeatureCapability>? _caps;

  @override
  void initState() {
    super.initState();
    DeviceCapabilities.geometryCaptureReport().then((v) {
      if (mounted) setState(() => _caps = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final caps = _caps;
    return ScreenScaffold(
      appBar: AppBar(title: const Text('Захват помещения')),
      body: caps == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Хаб «Захват помещения»: фото/PDF, RoomPlan, ARCore — '
                  'контур для всего комплекса отделки (пол, потолок, стены, проёмы).',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ниже — проверка готовности этого устройства.',
                ),
                const SizedBox(height: 16),
                for (final c in caps) ...[
                  ListTile(
                    leading: Icon(_iconFor(c.level)),
                    title: Text(c.title),
                    subtitle: Text(c.message),
                  ),
                  if (c.installUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: c.installUrl!));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Ссылка скопирована: ${c.installUrl}')),
                            );
                          }
                        },
                        icon: const Icon(Icons.link),
                        label: const Text('Скопировать ссылку на установку'),
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  IconData _iconFor(CapabilityLevel level) => switch (level) {
        CapabilityLevel.supported => Icons.check_circle_outline,
        CapabilityLevel.needsInstall => Icons.download_outlined,
        CapabilityLevel.unsupported => Icons.block,
        CapabilityLevel.wrongPlatform => Icons.phone_android,
      };
}
