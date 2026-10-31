import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/cost_calculator.dart';
import '../domain/documentation_model.dart';
import '../domain/finish_model.dart';
import '../domain/models.dart';
import '../domain/project_stage.dart';
import '../domain/special_space.dart';
import '../domain/typical_floor_diff.dart';
import '../domain/project_export.dart';
import '../domain/act_export.dart';
import '../domain/project_batch_export.dart';
import '../domain/project_summary_export.dart';
import '../domain/primary_supplier.dart';
import '../domain/document_template_loader.dart';
import '../domain/project_dashboard.dart';
import '../domain/project_floors.dart';
import '../domain/room_documentation_status.dart';
import 'documentation_flow_screens.dart';
import 'documentation_import_ui.dart';
import 'ks2_period_picker.dart';
import 'documentation_hidden_layers_screen.dart';
import 'geometry_capture_hub_screen.dart';
import 'project_documents_hub_screen.dart';
import 'widgets/expand_section_header.dart';
import 'widgets/room_workflow_chip.dart';
import 'widgets/screen_scaffold.dart';

/// Manager / foreman overview for one project.
class ProjectDashboardScreen extends StatefulWidget {
  const ProjectDashboardScreen({
    super.key,
    required this.projectId,
    this.module = AppModule.documentation,
    this.focusFloorId,
  });

  final int projectId;
  final AppModule module;

  /// Floor to expand first (e.g. the floor page user came from).
  final int? focusFloorId;

  @override
  State<ProjectDashboardScreen> createState() => _ProjectDashboardScreenState();
}

class _ProjectDashboardScreenState extends State<ProjectDashboardScreen> {
  Project? _project;
  ProjectDashboardSummary? _dash;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cached = AppScope.of(context).projects.peekCachedProject(widget.projectId);
      if (cached != null && mounted) {
        setState(() {
          _project = cached;
          _dash = buildProjectDashboard(cached);
          _loading = false;
        });
      }
      _load();
    });
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _project = project;
      _dash = project == null ? null : buildProjectDashboard(project);
      _loading = false;
    });
  }

  Future<void> _exportSummary({required bool pdf}) async {
    final dash = _dash;
    if (dash == null) return;
    final base = safeExportBasename('${dash.project.name}_svodka');
    if (pdf) {
      final bytes = await buildProjectSummaryPdf(dash);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, '$base.pdf'));
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Сводка · ${dash.project.name}'),
      );
    } else {
      final text = buildProjectSummaryText(dash);
      await Clipboard.setData(ClipboardData(text: text));
      await SharePlus.instance.share(
        ShareParams(text: text, subject: 'Сводка · ${dash.project.name}'),
      );
    }
  }

  Future<void> _bulkTypicalFloor(Room template) async {
    final countCtrl = TextEditingController(text: '5');
    final prefixCtrl = TextEditingController(text: '${template.name} ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Типовой этаж'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Шаблон: «${template.name}» — геометрия и отделка без документов.'),
            const SizedBox(height: 12),
            TextField(
              controller: prefixCtrl,
              decoration: const InputDecoration(labelText: 'Префикс имён'),
            ),
            TextField(
              controller: countCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Количество копий'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final count = int.tryParse(countCtrl.text.trim()) ?? 0;
    if (count < 1 || count > 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите от 1 до 50 комнат')),
      );
      return;
    }
    final prefix = prefixCtrl.text.trim();
    final names = List.generate(count, (i) => '$prefix${i + 1}');
    await AppScope.of(context).projects.duplicateRoomBulk(widget.projectId, template, names);
    if (!mounted) return;
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    if (project != null && mounted) {
      final copies = project.rooms.where((r) => names.contains(r.name)).toList();
      if (copies.isNotEmpty) {
        final diff = compareTypicalFloor(template: template, project: project, copies: copies);
        final geo = formatTypicalFloorGeometryDiff(template: template, copies: copies);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Сравнение типового этажа'),
            content: SingleChildScrollView(
              child: Text('${formatTypicalFloorDiffText(diff)}\n$geo'),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Создано $count комнат')),
      );
      await _load();
    }
  }

  Future<void> _exportDocumentationPack() async {
    final project = _project;
    if (project == null) return;
    final layoutRooms = project.rooms.where((r) => r.hasLayout).length;
    if (layoutRooms == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет комнат с чертежом для экспорта')),
      );
      return;
    }
    final doc = ProjectDocumentation.fromJson(project.documentationJson);
    Map<String, SupplierPrice>? prices;
    try {
      prices = await loadPrimarySupplierPrices(
        repo: AppScope.of(context).suppliers,
        doc: doc,
      );
    } catch (_) {}
    try {
      final ks2Template = await loadKs2TemplateJson(doc);
      final actTemplate = await loadActHiddenTemplateJson(doc);
      final ks3Template = await loadKs3TemplateJson(doc);
      final now = DateTime.now();
      DateTime periodFrom = DateTime(now.year, now.month, 1);
      DateTime periodTo = now;
      if (doc.ks2Acts.isNotEmpty) {
        if (!mounted) return;
        final period = await pickKs3PeriodRange(
          context,
          initialFrom: periodFrom,
          initialTo: periodTo,
        );
        if (period == null) return;
        periodFrom = period.$1;
        periodTo = period.$2;
      }
      final result = await exportProjectDocumentationPack(
        project: project,
        doc: doc,
        supplierPrices: prices,
        ks2TemplateJson: ks2Template,
        actHiddenTemplateJson: actTemplate,
        ks3TemplateJson: ks3Template,
        periodFrom: periodFrom,
        periodTo: periodTo,
      );
      if (result.nextActNumber != null && project.id != null) {
        doc.nextActNumber = result.nextActNumber!;
        project.documentationJson = doc.toJson();
        await AppScope.of(context).projects.updateProjectDocumentation(
              project.id!,
              documentationJson: doc.toJson(),
            );
      }
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.file.path)],
          subject: 'Документация · ${project.name}',
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.warnings.isEmpty
                ? 'ZIP: ${result.fileCount} файлов · $layoutRooms комнат'
                : 'ZIP: ${result.fileCount} файлов · предупреждений: ${result.warnings.length}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка экспорта: $e')),
      );
    }
  }

  Future<void> _importProjectDocument() async {
    final project = _project;
    if (project?.id == null) return;
    var doc = ProjectDocumentation.fromJson(project!.documentationJson);
    await runProjectDocumentImportFlow(
      context,
      doc: doc,
      onSave: (updated) async {
        doc = updated;
        project.documentationJson = doc.toJson();
        await AppScope.of(context).projects.updateProjectDocumentation(
              project.id!,
              documentationJson: doc.toJson(),
            );
      },
    );
    await _load();
  }

  Future<Map<String, SupplierPrice>?> _supplierPrices() async {
    try {
      final project = _project;
      if (project == null) return null;
      final doc = ProjectDocumentation.fromJson(project.documentationJson);
      return await loadPrimarySupplierPrices(
        repo: AppScope.of(context).suppliers,
        doc: doc,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _exportKs3({required bool pdf}) async {
    final project = _project;
    if (project == null) return;
    final doc = ProjectDocumentation.fromJson(project.documentationJson);
    final layoutRooms = project.rooms.where((r) => r.hasLayout).length;
    if (layoutRooms == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет комнат с чертежом для КС-3')),
      );
      return;
    }
    final now = DateTime.now();
    if (!mounted) return;
    final period = await pickKs3PeriodRange(
      context,
      initialFrom: DateTime(now.year, now.month, 1),
      initialTo: now,
    );
    if (period == null) return;
    final (periodFrom, periodTo) = period;
    final stamp = doc.stamp.withDefaults(projectName: project.name, roomName: '');
    final prices = await _supplierPrices();
    final ks3Template = await loadKs3TemplateJson(doc);
    final base = safeExportBasename('${project.name}_ks3');
    final dir = await getTemporaryDirectory();
    if (pdf) {
      final bytes = await buildKs3MaterialsPdf(
        project: project,
        stamp: stamp,
        periodFrom: periodFrom,
        periodTo: periodTo,
        templateJson: ks3Template,
        prices: prices,
      );
      final file = File(p.join(dir.path, '$base.pdf'));
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'КС-3 · ${project.name}'),
      );
    } else {
      final text = buildKs3FromTemplate(
        templateJson: ks3Template,
        project: project,
        stamp: stamp,
        periodFrom: periodFrom,
        periodTo: periodTo,
        prices: prices,
      );
      await Clipboard.setData(ClipboardData(text: text));
      await SharePlus.instance.share(
        ShareParams(text: text, subject: 'КС-3 · ${project.name}'),
      );
    }
  }

  Future<void> _setStage(ProjectStage stage) async {
    final project = _project;
    if (project?.id == null) return;
    final doc = ProjectDocumentation.fromJson(project!.documentationJson);
    doc.stage = stage;
    project.documentationJson = doc.toJson();
    await AppScope.of(context).projects.updateProjectDocumentation(
          project.id!,
          documentationJson: doc.toJson(),
        );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    final dash = _dash;
    if (dash == null) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Сводка объекта')),
        body: const Center(child: Text('Проект не найден')),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;

    return ScreenScaffold(
      appBar: AppBar(
        title: Text('Сводка · ${dash.project.name}'),
        actions: [
          IconButton(
            tooltip: 'Настройки документации',
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
      body: wide ? _buildWide(dash) : _buildNarrow(dash),
    );
  }

  List<Widget> _projectActionCards(ProjectDashboardSummary dash) {
    final doc = ProjectDocumentation.fromJson(dash.project.documentationJson);
    final actCount = doc.ks2Acts.length;
    return [
      Card(
        color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.35),
        child: ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Документы'),
          subtitle: Text(
            actCount == 0
                ? 'КП · КС-2 / КС-3 · реквизиты'
                : 'КП · КС · актов: $actCount',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProjectDocumentsHubScreen(projectId: widget.projectId),
              ),
            );
            await _load();
          },
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('Ведомость объекта'),
          subtitle: const Text('Сумма по всем помещениям · PDF / Excel'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DocumentationVedomostScreen(
                  projectId: widget.projectId,
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildNarrow(ProjectDashboardSummary dash) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._projectActionCards(dash),
        const SizedBox(height: 12),
        ..._roomTilesGrouped(dash),
      ],
    );
  }

  List<Widget> _roomTilesGrouped(ProjectDashboardSummary dash) {
    final floors = dash.project.floors;
    if (!projectHasExplicitFloors(floors)) {
      return [
        for (final item in dash.rooms)
          _RoomDashTile(
            item: item,
            projectId: widget.projectId,
            project: dash.project,
            onChanged: _load,
          ),
      ];
    }
    final pages = floorsForPager(floors);
    final out = <Widget>[];
    for (final floor in pages) {
      final items = <RoomAttentionItem>[];
      final spanningGuestIds = <int>{};
      for (final item in dash.rooms) {
        if (item.room.floorId == floor.id) {
          items.add(item);
          continue;
        }
        // Same ЛК on every overlapping floor page — display only; totals stay 1×.
        if (stairwellSpansFloorPage(item.room, floor)) {
          items.add(item);
          if (item.room.id != null) spanningGuestIds.add(item.room.id!);
        }
      }
      if (items.isEmpty) continue;
      final nativeN = items.length - spanningGuestIds.length;
      out.add(
        SoftExpansionTile(
          initiallyExpanded: pages.length == 1 ||
              (widget.focusFloorId != null
                  ? floor.id == widget.focusFloorId
                  : floor.floorNumber == 1),
          leading: const Icon(Icons.layers_outlined),
          title: Text(floor.pagerLabel),
          subtitle: Text(
            spanningGuestIds.isEmpty
                ? '$nativeN помещ.'
                : '$nativeN помещ. · +ЛК сквозная',
          ),
          children: [
            for (final item in items)
              _RoomDashTile(
                item: item,
                projectId: widget.projectId,
                project: dash.project,
                onChanged: _load,
                spanningGuest: spanningGuestIds.contains(item.room.id),
              ),
          ],
        ),
      );
    }
    // Orphans without floor
    final known = pages.map((f) => f.id).toSet();
    final orphans = dash.rooms
        .where((i) => i.room.floorId != null && !known.contains(i.room.floorId))
        .toList();
    for (final item in orphans) {
      out.add(
        _RoomDashTile(
          item: item,
          projectId: widget.projectId,
          project: dash.project,
          onChanged: _load,
        ),
      );
    }
    return out;
  }

  Widget _buildWide(ProjectDashboardSummary dash) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 320,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ..._projectActionCards(dash),
              const SizedBox(height: 12),
              Text(
                'ПК-режим: список слева, детали справа. На телефоне — компактный список.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: _roomTilesGrouped(dash),
          ),
        ),
      ],
    );
  }

  Future<void> _compareTypicalFloor(ProjectDashboardSummary dash) async {
    final withLayout = dash.rooms.where((r) => r.hasLayout).toList();
    if (withLayout.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет комнат с чертежом')),
      );
      return;
    }
    final template = await showModalBottomSheet<Room>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Шаблон для сравнения')),
            for (final item in withLayout)
              ListTile(
                title: Text(
                  roomNameWithFloor(
                    room: item.room,
                    floors: dash.project.floors,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, item.room),
              ),
          ],
        ),
      ),
    );
    if (template == null || !mounted) return;
    final prefixCtrl = TextEditingController(text: '${template.name} ');
    final prefixOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Префикс копий'),
        content: TextField(
          controller: prefixCtrl,
          decoration: const InputDecoration(
            labelText: 'Имена копий начинаются с…',
            helperText: 'Например: «101 » для 101 1, 101 2…',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сравнить')),
        ],
      ),
    );
    if (prefixOk != true || !mounted) return;
    final copies = findTypicalFloorCopies(
      dash.project,
      template,
      prefix: prefixCtrl.text,
    );
    if (copies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Копии с таким префиксом не найдены')),
      );
      return;
    }
    final diff = compareTypicalFloor(
      template: template,
      project: dash.project,
      copies: copies,
    );
    final geo = formatTypicalFloorGeometryDiff(template: template, copies: copies);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сравнение типового этажа'),
        content: SingleChildScrollView(
          child: Text('${formatTypicalFloorDiffText(diff)}\n$geo'),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _pickTemplateRoom(ProjectDashboardSummary dash) async {
    final withLayout = dash.rooms.where((r) => r.hasLayout).toList();
    if (withLayout.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет комнат с чертежом для шаблона')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Room>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Выберите типовую комнату')),
            for (final item in withLayout)
              ListTile(
                title: Text(
                  roomNameWithFloor(
                    room: item.room,
                    floors: dash.project.floors,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, item.room),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _bulkTypicalFloor(picked);
  }
}

class _TypicalFloorCard extends StatelessWidget {
  const _TypicalFloorCard({required this.onPick, required this.onCompare});

  final VoidCallback onPick;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Типовой этаж'),
            subtitle: const Text('Скопировать комнату в N однотипных'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onPick,
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.compare_arrows, size: 20),
            title: const Text('Сравнить шаблон с копиями'),
            onTap: onCompare,
          ),
        ],
      ),
    );
  }
}

class _RoomDashTile extends StatelessWidget {
  const _RoomDashTile({
    required this.item,
    required this.projectId,
    required this.project,
    required this.onChanged,
    this.spanningGuest = false,
  });

  final RoomAttentionItem item;
  final int projectId;
  final Project project;
  final Future<void> Function() onChanged;

  /// Shown under a non-anchor floor page — same room id, not a second BOM row.
  final bool spanningGuest;

  @override
  Widget build(BuildContext context) {
    final room = item.room;
    final cl = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
    final scheme = Theme.of(context).colorScheme;
    final isStair = room.specialSpace?.kind == SpecialSpaceKind.stairwell;
    final stair = room.specialSpace?.stair;
    final spanLabel = () {
      if (stair == null) return '';
      final lo = stair.floorsFrom <= stair.floorsTo
          ? stair.floorsFrom
          : stair.floorsTo;
      final hi = stair.floorsFrom <= stair.floorsTo
          ? stair.floorsTo
          : stair.floorsFrom;
      return lo == hi ? 'эт. $lo' : 'эт. $lo–$hi';
    }();

    final doc = ProjectDocumentation.fromJson(project.documentationJson);
    final workflow = roomWorkflowStatus(
      room,
      item.summary,
      checklist: cl,
      project: project,
      documentation: doc,
    );

    String subtitle;
    if (isStair) {
      final bits = <String>[
        if (spanningGuest) 'Сквозная ЛК',
        if (spanLabel.isNotEmpty) spanLabel,
        'схема · документы',
      ];
      subtitle = bits.join(' · ');
    } else if (item.hasLayout || room.isSpecialSpace) {
      subtitle = room.isSpecialSpace ? 'Схема · документы' : 'Документы';
    } else {
      subtitle = 'Нет чертежа';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isStair
          ? scheme.secondaryContainer.withValues(alpha: 0.55)
          : null,
      shape: isStair
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: scheme.secondary.withValues(alpha: 0.55),
                width: spanningGuest ? 1.5 : 1,
              ),
            )
          : null,
      child: ListTile(
        leading: Icon(
          isStair
              ? Icons.stairs_outlined
              : (item.isReady
                  ? Icons.verified
                  : Icons.meeting_room_outlined),
          color: isStair
              ? scheme.secondary
              : (item.isReady ? scheme.primary : null),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                isStair
                    ? '${room.name} · ЛК'
                    : roomNameWithFloor(
                        room: room,
                        floors: project.floors,
                      ),
              ),
            ),
            RoomWorkflowChip(status: workflow),
          ],
        ),
        subtitle: Text(subtitle),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'doc':
                await openDocumentationRoom(
                  context,
                  projectId: projectId,
                  roomId: room.id!,
                );
              case 'field':
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DocumentationHiddenLayersScreen(
                      projectId: projectId,
                      roomId: room.id!,
                    ),
                  ),
                );
              case 'photo':
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GeometryCaptureHubScreen(
                      projectId: projectId,
                      roomId: room.id!,
                    ),
                  ),
                );
            }
            await onChanged();
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(value: 'doc', child: Text('Документация')),
            PopupMenuItem(value: 'field', child: Text('Скрытые работы')),
            PopupMenuItem(value: 'photo', child: Text('Чертёж с фото-плана')),
          ],
        ),
        onTap: () async {
          if (room.id == null) return;
          await openDocumentationRoom(
            context,
            projectId: projectId,
            roomId: room.id!,
          );
          await onChanged();
        },
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.stage, required this.onChanged});

  final ProjectStage stage;
  final ValueChanged<ProjectStage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Этап объекта', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: stage.progress),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: ProjectStage.values.map((s) {
                return ChoiceChip(
                  label: Text(s.labelRu),
                  selected: stage == s,
                  onSelected: (_) => onChanged(s),
                );
              }).toList(),
            ),
            Text(stage.hintRu, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
