import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/documentation_model.dart';
import '../domain/ks2_act_service.dart';
import '../domain/local_user_role.dart';
import '../domain/models.dart';
import '../domain/money_format.dart';
import '../domain/project_documents_vault.dart';
import 'contract_workspace_screen.dart';
import 'documentation_flow_screens.dart';
import 'documentation_import_ui.dart';
import 'widgets/screen_scaffold.dart';

/// Unified documents hub + per-project vault feed.
class ProjectDocumentsHubScreen extends StatefulWidget {
  const ProjectDocumentsHubScreen({super.key, required this.projectId});

  final int projectId;

  @override
  State<ProjectDocumentsHubScreen> createState() =>
      _ProjectDocumentsHubScreenState();
}

class _ProjectDocumentsHubScreenState extends State<ProjectDocumentsHubScreen> {
  Project? _project;
  bool _loading = true;
  DocumentVaultCategory? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cached =
          AppScope.of(context).projects.peekCachedProject(widget.projectId);
      if (cached != null && mounted) {
        setState(() {
          _project = cached;
          _loading = false;
        });
      }
      _load();
    });
  }

  Future<void> _load() async {
    final project =
        await AppScope.of(context).projects.getProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _project = project;
      _loading = false;
    });
  }

  Future<void> _openWorkspace({int initialTab = 0}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContractWorkspaceScreen(
          projectId: widget.projectId,
          initialTab: initialTab,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentationProjectSettingsScreen(
          projectId: widget.projectId,
        ),
      ),
    );
    await _load();
  }

  Future<void> _importDocument() async {
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

  Future<void> _attachFile() async {
    final project = _project;
    if (project?.id == null) return;
    final scope = AppScope.of(context);
    final role = scope.user.effectiveRole;
    if (!role.canDocumentation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вложения — только директору')),
      );
      return;
    }
    final projects = scope.projects;
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null || path.isEmpty) return;
    final name = files.first.name;
    final doc = ProjectDocumentation.fromJson(project!.documentationJson);
    await appendVaultFile(
      doc: doc,
      projectId: project.id!,
      category: DocumentVaultCategory.other,
      displayName: name,
      sourcePath: path,
      source: DocumentVaultSource.attachment,
    );
    project.documentationJson = doc.toJson();
    await projects.updateProjectDocumentation(
      project.id!,
      documentationJson: doc.toJson(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('В хранилище: $name')),
    );
    await _load();
  }

  Future<void> _openEntry(ProjectVaultEntry entry) async {
    try {
      final abs = await resolveVaultAbsolutePath(entry);
      final file = File(abs);
      if (!file.existsSync()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл не найден на диске')),
        );
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [XFile(abs)], subject: entry.name),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть: $e')),
      );
    }
  }

  IconData _catIcon(DocumentVaultCategory c) => switch (c) {
        DocumentVaultCategory.kp => Icons.request_quote_outlined,
        DocumentVaultCategory.smeta => Icons.table_chart_outlined,
        DocumentVaultCategory.ks2 => Icons.assignment_outlined,
        DocumentVaultCategory.ks3 => Icons.assignment_turned_in_outlined,
        DocumentVaultCategory.act => Icons.gavel_outlined,
        DocumentVaultCategory.scheme => Icons.grid_on_outlined,
        DocumentVaultCategory.certificate => Icons.verified_outlined,
        DocumentVaultCategory.other => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final project = _project;
    if (project == null) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Документы')),
        body: const Center(child: Text('Проект не найден')),
      );
    }

    final doc = ProjectDocumentation.fromJson(project.documentationJson);
    final role = AppScope.of(context).user.effectiveRole;
    final feed = buildVaultFeed(doc, role);
    final filtered = _filter == null
        ? feed
        : feed.where((e) => e.category == _filter).toList();
    final ks2Alerts = ks2ClosureAlerts(project);
    final actBits = <String>[];
    if (doc.ks2Acts.isNotEmpty) {
      actBits.add('актов: ${doc.ks2Acts.length}');
      actBits.add(formatRub(ledgerContractTotal(doc.ks2Acts)));
    }
    if (ks2Alerts.isNotEmpty) {
      actBits.add(ks2Alerts.map((e) => '${e.$1.labelRu}: ${e.$2}').join(' · '));
    }
    final workspaceSubtitle = actBits.isEmpty
        ? 'Смета → выдать акт → реестр · в одном экране'
        : actBits.join(' · ');
    final visibleCats = DocumentVaultCategory.values
        .where((c) => c.visibleFor(role))
        .toList();

    return ScreenScaffold(
      appBar: AppBar(
        title: Text('Документы · ${project.name}'),
        actions: [
          if (role.canDocumentation)
            IconButton(
              tooltip: 'Прикрепить файл',
              icon: const Icon(Icons.attach_file),
              onPressed: _attachFile,
            ),
          IconButton(
            tooltip: 'Реквизиты объекта',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (role.canDocumentation) ...[
            Text(
              'Рабочий стол',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Собрать КП/КС, закрыть помещения актом и смотреть реестр.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _DocListTile(
              icon: Icons.description_outlined,
              title: 'КП и акты',
              subtitle: workspaceSubtitle,
              highlighted: true,
              onTap: () => _openWorkspace(),
            ),
            _DocListTile(
              icon: Icons.upload_file,
              title: 'Загрузить договор / расценки',
              subtitle: doc.ks2Prices.isEmpty
                  ? 'Excel, Word, PDF — опционально'
                  : 'Расценок: ${doc.ks2Prices.length}',
              onTap: _importDocument,
            ),
            _DocListTile(
              icon: Icons.badge_outlined,
              title: 'Штамп и реквизиты',
              subtitle: 'Заказчик, исполнитель, цены объекта',
              onTap: _openSettings,
            ),
            const Divider(height: 28),
          ] else ...[
            Text(
              'Хранилище объекта',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Ведомости и схемы по роли бригадира (полный док-пак — у директора).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Хранилище · ${feed.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('Все'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final c in visibleCats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(c.labelRu),
                      selected: _filter == c,
                      onSelected: (_) => setState(() => _filter = c),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.folder_open_outlined),
                title: Text('Пока пусто'),
                subtitle: Text(
                  'Экспорты КП/КС/схем попадут сюда автоматически',
                ),
              ),
            )
          else
            for (final e in filtered)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(_catIcon(e.category)),
                  title: Text(e.name),
                  subtitle: Text(
                    '${e.category.labelRu} · ${e.source.labelRu} · '
                    '${e.createdAt.day.toString().padLeft(2, '0')}.'
                    '${e.createdAt.month.toString().padLeft(2, '0')}.'
                    '${e.createdAt.year}',
                  ),
                  trailing: const Icon(Icons.ios_share_outlined),
                  onTap: () => _openEntry(e),
                ),
              ),
        ],
      ),
    );
  }
}

class _DocListTile extends StatelessWidget {
  const _DocListTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color:
          highlighted ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
