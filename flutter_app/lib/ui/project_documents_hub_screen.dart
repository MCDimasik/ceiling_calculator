import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/documentation_model.dart';
import '../domain/ks2_act_service.dart';
import '../domain/models.dart';
import '../domain/money_format.dart';
import 'contract_workspace_screen.dart';
import 'documentation_flow_screens.dart';
import 'documentation_import_ui.dart';
import 'widgets/screen_scaffold.dart';

/// Lean documents hub: единый вход в КП/акты + реквизиты.
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

    return ScreenScaffold(
      appBar: AppBar(
        title: Text('Документы · ${project.name}'),
        actions: [
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
          Text(
            'Документы объекта',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Один рабочий стол: собрать КП/КС, закрыть часть помещений '
            'актом и смотреть реестр выданных КС-2.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _DocListTile(
            icon: Icons.description_outlined,
            title: 'КП и акты',
            subtitle: workspaceSubtitle,
            highlighted: true,
            onTap: () => _openWorkspace(),
          ),
          const Divider(height: 28),
          Text('Реквизиты', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
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
