import 'package:flutter/material.dart';

import '../domain/money_format.dart';
import '../domain/work_rates_catalog.dart';
import 'widgets/expand_section_header.dart';
import 'widgets/long_press_action_barrier.dart';
import 'widgets/numeric_input.dart';
import 'widgets/screen_scaffold.dart';

/// Global work rates by category (Расценки → Работа).
class WorkRatesScreen extends StatefulWidget {
  const WorkRatesScreen({super.key});

  @override
  State<WorkRatesScreen> createState() => _WorkRatesScreenState();
}

class _WorkRatesScreenState extends State<WorkRatesScreen> {
  List<WorkRateCategory> _categories = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reload();
    });
  }

  Future<void> _reload() async {
    final cats = await WorkRatesCatalogStore.load();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _loading = false;
    });
  }

  Future<void> _persist({bool snack = true}) async {
    await WorkRatesCatalogStore.save(_categories);
    if (!mounted || !snack) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Расценки работ сохранены')),
    );
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить каталог?'),
        content: const Text(
          'Вернутся цены из загруженных скриншотов «Строительные расценки». '
          'Ваши правки будут потеряны.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сбросить')),
        ],
      ),
    );
    if (ok != true) return;
    await WorkRatesCatalogStore.resetToSeed();
    await _reload();
  }

  WorkRateCategory? _liveCategory(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _openCategory(WorkRateCategory cat) async {
    final live = _liveCategory(cat.id) ?? cat;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WorkRateCategoryScreen(
          category: live,
          onChanged: () async {
            await _persist(snack: false);
            setState(() {});
          },
          onRenameCategory: (name) async {
            live.name = name;
            await _persist(snack: false);
            setState(() {});
          },
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _addCategory() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая категория'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Добавить')),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    if (ok != true || name.isEmpty) return;
    final id = 'cat_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _categories.add(WorkRateCategory(id: id, name: name));
    });
    await _persist();
  }

  Future<void> _renameCategory(WorkRateCategory cat) async {
    final live = _liveCategory(cat.id) ?? cat;
    final nameCtrl = TextEditingController(text: live.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать категорию'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    if (ok != true || name.isEmpty) return;
    setState(() => live.name = name);
    await _persist();
  }

  Future<void> _deleteCategory(WorkRateCategory cat) async {
    final live = _liveCategory(cat.id);
    if (live == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить категорию?'),
        content: Text(
          live.items.isEmpty
              ? '«${live.name}»'
              : '«${live.name}» и ${live.items.length} позиций внутри.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _categories.removeWhere((c) => c.id == live.id));
    await _persist();
  }

  Future<void> _addWorkToCategory(WorkRateCategory cat) async {
    final live = _liveCategory(cat.id) ?? cat;
    final draft = WorkRateItem(
      matchKey: '${live.id}_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Новая работа',
      unit: 'м²',
    );
    final edited = await editWorkRateItemDialog(context, draft);
    if (edited == null) return;
    setState(() => live.items.add(edited));
    await _persist();
  }

  Future<void> _addWorkAnywhere() async {
    if (_categories.isEmpty) {
      await _addCategory();
      if (_categories.isEmpty || !mounted) return;
    }
    final chosen = await showDialog<Object>(
      context: context,
      builder: (ctx) {
        final titleStyle = Theme.of(ctx).textTheme.titleLarge;
        final itemStyle = Theme.of(ctx).textTheme.titleMedium;
        return SimpleDialog(
          title: Text('Куда добавить работу?', style: titleStyle),
          children: [
            for (final c in _categories)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: Text(c.name, style: itemStyle),
              ),
            const Divider(height: 20),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'new_category'),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.create_new_folder_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Добавить свою категорию',
                      style: itemStyle?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (chosen == 'new_category') {
      await _addCategory();
      if (!mounted || _categories.isEmpty) return;
      await _addWorkToCategory(_categories.last);
      return;
    }
    if (chosen is WorkRateCategory) {
      await _addWorkToCategory(chosen);
    }
  }

  void _reorderCategories(int oldIndex, int newIndex) {
    setState(() {
      // onReorderItem already adjusts newIndex for the removed item.
      final item = _categories.removeAt(oldIndex);
      _categories.insert(newIndex.clamp(0, _categories.length), item);
    });
    _persist(snack: false);
  }

  Widget _buildCategoryCard(WorkRateCategory c, {int? reorderIndex}) {
    final live = _liveCategory(c.id) ?? c;
    final n = c.items.length;
    return Padding(
      key: ValueKey(live.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: _WorkRateCategoryCard(
        category: live,
        itemCount: n,
        initiallyExpanded: _query.isNotEmpty && n > 0,
        reorderIndex: reorderIndex,
        onOpen: () => _openCategory(live),
        onRename: () => _renameCategory(live),
        onDelete: () => _deleteCategory(live),
        onAddWork: () => _addWorkToCategory(live),
        filteredItems: c.items,
        onEditItem: (item) async {
          final liveItemIndex = live.items.indexWhere(
            (x) => x.matchKey == item.matchKey,
          );
          if (liveItemIndex < 0) return;
          final edited = await editWorkRateItemDialog(
            context,
            live.items[liveItemIndex],
          );
          if (edited == null) return;
          setState(() => live.items[liveItemIndex] = edited);
          await _persist(snack: false);
        },
        onDeleteItem: (item) async {
          final liveItemIndex = live.items.indexWhere(
            (x) => x.matchKey == item.matchKey,
          );
          if (liveItemIndex < 0) return;
          final del = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Удалить?'),
              content: Text(item.name),
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
          if (del != true) return;
          setState(() => live.items.removeAt(liveItemIndex));
          await _persist(snack: false);
        },
      ),
    );
  }

  List<WorkRateCategory> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _categories;
    return _categories
        .map((c) {
          final items = c.items.where((i) => i.name.toLowerCase().contains(q)).toList();
          if (c.name.toLowerCase().contains(q) || items.isNotEmpty) {
            return WorkRateCategory(
              id: c.id,
              name: c.name,
              items: items.isEmpty ? c.items : items,
            );
          }
          return null;
        })
        .whereType<WorkRateCategory>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return ScreenScaffold(
      appBar: AppBar(
        title: const Text('Работа · расценки'),
        actions: [
          IconButton(
            tooltip: 'Новая категория',
            onPressed: _addCategory,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: 'Сбросить из скриншотов',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: 'Сохранить',
            onPressed: _persist,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addWorkAnywhere,
        icon: const Icon(Icons.add),
        label: const Text('Работа'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Поиск по работам',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('Нет категорий — добавьте первую'))
                      : _query.trim().isEmpty
                          ? ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                              itemCount: list.length,
                              onReorderItem: _reorderCategories,
                              proxyDecorator: (child, index, animation) =>
                                  Material(
                                elevation: 2,
                                borderRadius: BorderRadius.circular(14),
                                child: child,
                              ),
                              itemBuilder: (context, i) =>
                                  _buildCategoryCard(list[i], reorderIndex: i),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                              itemCount: list.length,
                              itemBuilder: (context, i) =>
                                  _buildCategoryCard(list[i]),
                            ),
                ),
              ],
            ),
    );
  }
}

/// Category row: expand on tap; long-press opens action icons (as rooms/projects).
class _WorkRateCategoryCard extends StatefulWidget {
  const _WorkRateCategoryCard({
    required this.category,
    required this.itemCount,
    required this.initiallyExpanded,
    this.reorderIndex,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onAddWork,
    required this.filteredItems,
    required this.onEditItem,
    required this.onDeleteItem,
  });

  final WorkRateCategory category;
  final int itemCount;
  final bool initiallyExpanded;
  final int? reorderIndex;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onAddWork;
  final List<WorkRateItem> filteredItems;
  final Future<void> Function(WorkRateItem item) onEditItem;
  final Future<void> Function(WorkRateItem item) onDeleteItem;

  @override
  State<_WorkRateCategoryCard> createState() => _WorkRateCategoryCardState();
}

class _WorkRateCategoryCardState extends State<_WorkRateCategoryCard> {
  bool _actions = false;
  final _token = Object();

  @override
  void initState() {
    super.initState();
    LongPressActionBarrier.instance.bindClose(_token, _hideActions);
  }

  @override
  void dispose() {
    LongPressActionBarrier.instance.unbindClose(_token);
    super.dispose();
  }

  void _showActions() {
    setState(() => _actions = true);
    LongPressActionBarrier.instance.registerOpen(_token);
  }

  void _hideActions() {
    if (!_actions) return;
    setState(() => _actions = false);
    LongPressActionBarrier.instance.registerClosed(_token);
  }

  Widget _actionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor ?? scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 22, color: foregroundColor ?? scheme.onSurface),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = widget.itemCount;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _actions
          ? Card(
              key: const ValueKey('actions'),
              child: SizedBox(
                height: 88,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      _actionIcon(
                        icon: Icons.open_in_new,
                        tooltip: 'Открыть',
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        onPressed: () {
                          _hideActions();
                          widget.onOpen();
                        },
                      ),
                      const SizedBox(width: 6),
                      _actionIcon(
                        icon: Icons.drive_file_rename_outline,
                        tooltip: 'Имя',
                        onPressed: () {
                          _hideActions();
                          widget.onRename();
                        },
                      ),
                      const SizedBox(width: 6),
                      _actionIcon(
                        icon: Icons.delete_outline,
                        tooltip: 'Удалить',
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                        onPressed: () {
                          _hideActions();
                          widget.onDelete();
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: _hideActions,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : GestureDetector(
              key: const ValueKey('tile'),
              onLongPress: _showActions,
              child: SoftExpansionTile(
                leading: widget.reorderIndex != null
                    ? ReorderableDragStartListener(
                        index: widget.reorderIndex!,
                        child: const Icon(Icons.drag_handle),
                      )
                    : const Icon(Icons.handyman_outlined),
                title: Text(widget.category.name),
                subtitle: Text(
                  n == 0
                      ? 'Пока пусто · удерживайте для меню'
                      : '$n позиций · тяните ☰ для порядка',
                ),
                initiallyExpanded: widget.initiallyExpanded,
                children: [
                  if (n == 0)
                    const ListTile(dense: true, title: Text('Нет позиций'))
                  else
                    for (final item in widget.filteredItems)
                      _WorkRateItemTile(
                        item: item,
                        onEdit: () => widget.onEditItem(item),
                        onDelete: () => widget.onDeleteItem(item),
                      ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: widget.onAddWork,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Работа'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _WorkRateItemTile extends StatelessWidget {
  const _WorkRateItemTile({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final WorkRateItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(item.name, maxLines: 2),
      subtitle: Text(item.unit),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.unitPrice > 0 ? formatRub(item.unitPrice) : '—',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          IconButton(
            tooltip: 'Изменить',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Удалить',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
      onTap: onEdit,
    );
  }
}

Future<WorkRateItem?> editWorkRateItemDialog(
  BuildContext context,
  WorkRateItem line,
) async {
  final nameCtrl = TextEditingController(text: line.name);
  final unitCtrl = TextEditingController(text: line.unit);
  final priceCtrl = TextEditingController(
    text: line.unitPrice > 0 ? line.unitPrice.toStringAsFixed(0) : '',
  );
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Расценка'),
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
              labelText: 'Цена, ₽',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
      ],
    ),
  );
  if (ok != true) return null;
  return WorkRateItem(
    matchKey: line.matchKey,
    name: nameCtrl.text.trim().isEmpty ? line.name : nameCtrl.text.trim(),
    unit: unitCtrl.text.trim().isEmpty ? line.unit : unitCtrl.text.trim(),
    unitPrice: double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0,
  );
}

class _WorkRateCategoryScreen extends StatefulWidget {
  const _WorkRateCategoryScreen({
    required this.category,
    required this.onChanged,
    this.onRenameCategory,
  });

  final WorkRateCategory category;
  final VoidCallback onChanged;
  final Future<void> Function(String name)? onRenameCategory;

  @override
  State<_WorkRateCategoryScreen> createState() => _WorkRateCategoryScreenState();
}

class _WorkRateCategoryScreenState extends State<_WorkRateCategoryScreen> {
  Future<void> _edit(int index) async {
    final edited = await editWorkRateItemDialog(context, widget.category.items[index]);
    if (edited == null) return;
    setState(() => widget.category.items[index] = edited);
    widget.onChanged();
  }

  Future<void> _add() async {
    final draft = WorkRateItem(
      matchKey: '${widget.category.id}_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Новая работа',
      unit: 'м²',
    );
    final edited = await editWorkRateItemDialog(context, draft);
    if (edited == null) return;
    setState(() => widget.category.items.add(edited));
    widget.onChanged();
  }

  Future<void> _delete(int index) async {
    final item = widget.category.items[index];
    final del = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить?'),
        content: Text(item.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (del != true) return;
    setState(() => widget.category.items.removeAt(index));
    widget.onChanged();
  }

  Future<void> _rename() async {
    final rename = widget.onRenameCategory;
    if (rename == null) return;
    final nameCtrl = TextEditingController(text: widget.category.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Категория',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    if (ok != true || name.isEmpty) return;
    await rename(name);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.category.items;
    return ScreenScaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
        actions: [
          IconButton(
            tooltip: 'Переименовать',
            onPressed: _rename,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Работа'),
      ),
      body: items.isEmpty
          ? const Center(child: Text('Нет позиций — нажмите «Работа»'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final item = items[i];
                return Card(
                  child: _WorkRateItemTile(
                    item: item,
                    onEdit: () => _edit(i),
                    onDelete: () => _delete(i),
                  ),
                );
              },
            ),
    );
  }
}
