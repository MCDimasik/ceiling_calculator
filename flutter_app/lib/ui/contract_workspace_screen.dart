import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/documentation_model.dart';
import '../domain/ks2_act_service.dart';
import '../domain/ks2_work_scope.dart';
import '../domain/models.dart';
import 'contract_docs_screen.dart';
import 'ks2_closure_screen.dart';
import 'widgets/screen_scaffold.dart';

/// Единое место для сметы (КП/КС), частичного закрытия и реестра актов.
///
/// Пользовательская история:
/// 1. **Смета** — настроить строки/цены/форму и выгрузить КП или полный КС.
/// 2. **Выдать** — выбрать помещения × пол/стены/потолок и записать акт в реестр.
/// 3. **Реестр** — что уже выдано, статусы, КС-3 нарастающим итогом.
class ContractWorkspaceScreen extends StatefulWidget {
  const ContractWorkspaceScreen({
    super.key,
    required this.projectId,
    this.initialTab = 0,
    this.initialScope,
    this.initialScopes,
    this.focusRoomId,
  });

  final int projectId;

  /// 0 = смета, 1 = выдать акт, 2 = реестр.
  final int initialTab;
  final WorkScope? initialScope;
  final List<WorkScope>? initialScopes;
  final int? focusRoomId;

  @override
  State<ContractWorkspaceScreen> createState() =>
      _ContractWorkspaceScreenState();
}

class _ContractWorkspaceScreenState extends State<ContractWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _estimateKey = GlobalKey<ContractDocsScreenState>();
  final _issueKey = GlobalKey<Ks2ClosureScreenState>();
  final _registryKey = GlobalKey<Ks2ClosureScreenState>();
  Project? _project;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final i = widget.initialTab.clamp(0, 2);
    _tabs = TabController(length: 3, vsync: this, initialIndex: i);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      setState(() {});
      // После выдачи акта реестр мог устареть — подтянуть при открытии.
      if (_tabs.index == 2) {
        _registryKey.currentState?.reload();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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

  Future<void> _leave() async {
    try {
      await _estimateKey.currentState?.save();
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  Future<void> _onActIssued() async {
    await _registryKey.currentState?.reload();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final name = _project?.name ?? '';
    const canClose = true;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leave();
      },
      child: ScreenScaffold(
        appBar: AppBar(
          title: Text(name.isEmpty ? 'КП и акты' : 'КП и акты · $name'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leave,
          ),
          actions: [
            if (_tabs.index == 0)
              IconButton(
                tooltip: 'Сохранить смету',
                icon: const Icon(Icons.save_outlined),
                onPressed: () async {
                  await _estimateKey.currentState?.save();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Смета сохранена')),
                  );
                },
              ),
            if (_tabs.index == 2 && canClose)
              IconButton(
                tooltip: 'КС-3 нарастающая',
                icon: const Icon(Icons.receipt_long_outlined),
                onPressed: () => _registryKey.currentState?.exportKs3(),
              ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Смета'),
              Tab(text: 'Выдать'),
              Tab(text: 'Реестр'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            ContractDocsScreen(
              key: _estimateKey,
              projectId: widget.projectId,
              embedded: true,
              scrollHint:
                  'Соберите смету: помещения, строки, цены → выгрузка КП / полного КС.',
            ),
            Ks2ClosureScreen(
              key: _issueKey,
              projectId: widget.projectId,
              embedded: true,
              panel: Ks2ClosurePanel.issue,
              initialScope: widget.initialScope,
              initialScopes: widget.initialScopes,
              focusRoomId: widget.focusRoomId,
              onActsChanged: _onActIssued,
              scrollHint:
                  'Закройте часть объекта: комнаты и вид работ → акт попадёт в реестр.',
            ),
            Ks2ClosureScreen(
              key: _registryKey,
              projectId: widget.projectId,
              embedded: true,
              panel: Ks2ClosurePanel.registry,
              onActsChanged: _onActIssued,
              scrollHint:
                  'Уже выданные КС-2, статусы оплаты и КС-3 нарастающим итогом.',
            ),
          ],
        ),
      ),
    );
  }
}

/// After hidden-works step: offer to open workspace on «Выдать» for that room/scope.
Future<void> maybePromptScopedKs2(
  BuildContext context, {
  required int projectId,
  required int roomId,
  required String stepId,
}) async {
  final project = await AppScope.of(context).projects.getProject(projectId);
  if (project == null || !context.mounted) return;
  Room? room;
  for (final r in project.rooms) {
    if (r.id == roomId) room = r;
  }
  if (room == null) return;
  final r = room;
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  final scope = suggestScopeAfterStep(
    project: project,
    doc: doc,
    room: r,
    stepId: stepId,
    acts: doc.ks2Acts,
  );
  if (scope == null || !context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Закрыть «${scope.labelRu}»?'),
      content: Text(
        'Скрытые работы по «${scope.labelRu}» в «${r.name}» выполнены.\n'
        'Сформировать промежуточный КС-2 на объект?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Позже'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('КС-2'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContractWorkspaceScreen(
          projectId: projectId,
          initialTab: 1,
          initialScope: scope,
          focusRoomId: roomId,
        ),
      ),
    );
  }
}
