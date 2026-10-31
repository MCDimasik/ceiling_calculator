import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/director_archive_store.dart';
import '../domain/local_user_role.dart';
import 'adaptive_layout.dart';
import 'desktop_cascade.dart';
import 'widgets/cascade_pane_toolbar.dart';
import 'widgets/screen_scaffold.dart';

/// Director archive: categories + PDF/Word/Excel; syncs with server when online.
class DirectorArchiveScreen extends StatefulWidget {
  const DirectorArchiveScreen({
    super.key,
    this.cascadeMode = false,
  });

  final bool cascadeMode;

  @override
  State<DirectorArchiveScreen> createState() => _DirectorArchiveScreenState();
}

class _DirectorArchiveScreenState extends State<DirectorArchiveScreen> {
  var _loading = true;
  var _busy = false;
  List<DirectorArchiveCategory> _cats = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final cats = await DirectorArchiveStore.load();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _loading = false;
    });
  }

  Future<void> _addCategory() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая категория'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final title = ctrl.text.trim();
    if (title.isEmpty) return;
    await DirectorArchiveStore.addCategory(title);
    await _reload();
  }

  Future<void> _editNote(DirectorArchiveCategory cat) async {
    final ctrl = TextEditingController(text: cat.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cat.title),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Заметка',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    cat.note = ctrl.text.trim();
    await DirectorArchiveStore.updateCategory(cat);
    await _reload();
  }

  Future<void> _attachFile(DirectorArchiveCategory cat) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'odt',
        'ods',
        'rtf',
        'txt',
        'csv',
      ],
    );
    if (picked.isEmpty) return;
    final path = picked.first.path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      await DirectorArchiveStore.addFileFromPath(
        categoryId: cat.id,
        sourcePath: path,
        displayName: picked.first.name,
      );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Файл добавлен в архив')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncCloud() async {
    final scope = AppScope.of(context);
    setState(() => _busy = true);
    final err = await scope.accountCloud.syncNow();
    if (!mounted) return;
    setState(() => _busy = false);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ?? (scope.accountCloud.lastStatusRu ?? 'Синхронизировано'),
        ),
      ),
    );
  }

  Future<void> _openCategory(DirectorArchiveCategory cat) async {
    final page = _ArchiveCategoryScreen(
      categoryId: cat.id,
      onChanged: _reload,
    );
    final cascade = widget.cascadeMode
        ? DesktopCascadeHost.maybeOf(context)
        : null;
    if (cascade != null) {
      cascade.openDetail(
        page,
        title: cat.title,
        detailId: 'archive:${cat.id}',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final role = AppScope.of(context).user.effectiveRole;
    final cloud = AppScope.of(context).accountCloud;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final actions = <Widget>[
      if (role.canArchive)
        IconButton(
          tooltip: 'Синхронизировать с сервером',
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : _syncCloud,
          icon: cloud.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_sync_outlined),
        ),
      IconButton(
        tooltip: 'Категория',
        visualDensity: VisualDensity.compact,
        onPressed: _busy ? null : _addCategory,
        icon: const Icon(Icons.create_new_folder_outlined),
      ),
    ];
    return ScreenScaffold(
      appBar: widget.cascadeMode
          ? CascadePaneToolbar(
              title: 'Архив',
              subtitle: '${_cats.length} категорий',
              actions: actions,
            )
          : AppBar(
              title: const Text('Архив'),
              actions: actions,
            ),
      embeddedMaxWidth: widget.cascadeMode
          ? AdaptiveBreakpoints.paneReadableMax
          : AdaptiveBreakpoints.paneReadableWide,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = DesktopMetrics.of(context);
          final grid = desktop && constraints.maxWidth >= 640;
          final catCards = [
            for (final cat in _cats)
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  minTileHeight: DesktopMetrics.listTileMinHeight(context),
                  leading: CircleAvatar(
                    radius: DesktopMetrics.leadingRadius(context),
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.folder_outlined),
                  ),
                  title: Text(
                    cat.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    cat.files.isEmpty
                        ? (cat.note.isEmpty
                            ? 'Нет файлов · откройте, чтобы добавить'
                            : cat.note)
                        : '${cat.files.length} файл(ов)'
                            '${cat.note.isEmpty ? '' : ' · ${cat.note}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Прикрепить файл',
                    onPressed: _busy ? null : () => _attachFile(cat),
                    icon: const Icon(Icons.attach_file),
                  ),
                  onTap: () => _openCategory(cat),
                  onLongPress: () async {
                    final action = await showModalBottomSheet<String>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.notes),
                              title: const Text('Заметка'),
                              onTap: () => Navigator.pop(ctx, 'note'),
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete_outline),
                              title: const Text('Удалить категорию'),
                              onTap: () => Navigator.pop(ctx, 'del'),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (!mounted) return;
                    if (action == 'note') {
                      await _editNote(cat);
                    } else if (action == 'del') {
                      final del = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Удалить категорию?'),
                          content: Text(cat.title),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Отмена'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Удалить'),
                            ),
                          ],
                        ),
                      );
                      if (del == true) {
                        await DirectorArchiveStore.deleteCategory(cat.id);
                        await _reload();
                      }
                    }
                  },
                ),
              ),
          ];
          return ListView(
            padding: EdgeInsets.all(desktop ? 12 : 16),
            children: [
              Card(
                child: ListTile(
                  minTileHeight: DesktopMetrics.listTileMinHeightTall(context),
                  leading: Icon(
                    AppScope.of(context).sync.isSignedIn
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_outlined,
                    size: desktop ? 28 : 24,
                  ),
                  title: Text(
                    'Архив директора',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  subtitle: Text(
                    '${cloud.statusHintRu}\n'
                    'PDF, Word, Excel — локально и на сервер при синке. '
                    'Позже — точка стыка с CRM.',
                  ),
                  isThreeLine: true,
                ),
              ),
              const SizedBox(height: 16),
              if (grid)
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.6,
                  children: catCards,
                )
              else
                ...[
                  for (final c in catCards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: c,
                    ),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _ArchiveCategoryScreen extends StatefulWidget {
  const _ArchiveCategoryScreen({
    required this.categoryId,
    required this.onChanged,
  });

  final String categoryId;
  final Future<void> Function() onChanged;

  @override
  State<_ArchiveCategoryScreen> createState() => _ArchiveCategoryScreenState();
}

class _ArchiveCategoryScreenState extends State<_ArchiveCategoryScreen> {
  DirectorArchiveCategory? _cat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final cats = await DirectorArchiveStore.load();
    DirectorArchiveCategory? found;
    for (final c in cats) {
      if (c.id == widget.categoryId) {
        found = c;
        break;
      }
    }
    if (!mounted) return;
    setState(() => _cat = found);
  }

  Future<void> _attach() async {
    final cat = _cat;
    if (cat == null) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'odt',
        'ods',
        'rtf',
        'txt',
        'csv',
      ],
    );
    if (picked.isEmpty) return;
    final path = picked.first.path;
    if (path == null) return;
    await DirectorArchiveStore.addFileFromPath(
      categoryId: cat.id,
      sourcePath: path,
      displayName: picked.first.name,
    );
    await _load();
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    return ScreenScaffold(
      appBar: AppBar(
        title: Text(cat?.title ?? 'Категория'),
        actions: [
          IconButton(
            tooltip: 'Прикрепить',
            onPressed: cat == null ? null : _attach,
            icon: const Icon(Icons.attach_file),
          ),
        ],
      ),
      body: cat == null
          ? const Center(child: Text('Категория не найдена'))
          : cat.files.isEmpty
              ? Center(
                  child: Text(
                    'Нет файлов.\nНажмите «скрепку», чтобы добавить PDF / Word / Excel.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: cat.files.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final f = cat.files[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(f.name),
                        subtitle: Text(
                          '${(f.sizeBytes / 1024).toStringAsFixed(1)} КБ'
                          '${f.serverId != null ? ' · на сервере' : ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await DirectorArchiveStore.deleteFile(
                              cat.id,
                              f.id,
                            );
                            await _load();
                            await widget.onChanged();
                          },
                        ),
                        onTap: () async {
                          final path =
                              await DirectorArchiveStore.absolutePath(f);
                          if (!File(path).existsSync()) return;
                          await SharePlus.instance.share(
                            ShareParams(
                              files: [XFile(path)],
                              subject: f.name,
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
