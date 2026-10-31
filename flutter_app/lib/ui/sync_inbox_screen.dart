import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/ceiling_sync_client.dart';
import '../domain/cloud_sync_stub.dart';
import '../domain/local_user_role.dart';
import '../domain/models.dart';
import '../domain/finish_material_links.dart';
import '../domain/prices_share.dart';
import 'adaptive_layout.dart';
import 'local_profile_screen.dart';
import 'widgets/screen_scaffold.dart';

/// Live inbox against Ceiling Sync API (`/inbox`).
class SyncInboxScreen extends StatefulWidget {
  const SyncInboxScreen({super.key});

  @override
  State<SyncInboxScreen> createState() => _SyncInboxScreenState();
}

class _SyncInboxScreenState extends State<SyncInboxScreen> {
  List<SyncInboxItem>? _items;
  String? _loadError;
  bool _loading = true;

  /// null = all; else project | prices | kit (matched first in list).
  String? _filterKind;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final sync = AppScope.of(context).sync;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    await sync.refreshInbox();
    if (!sync.isSignedIn) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
      return;
    }
    try {
      final list = await sync.fetchInbox();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  List<SyncInboxItem> get _sortedItems {
    final all = _items ?? const <SyncInboxItem>[];
    final f = _filterKind;
    if (f == null) return all;
    final matched = all.where((e) => e.kind == f).toList();
    final rest = all.where((e) => e.kind != f).toList();
    return [...matched, ...rest];
  }

  List<Map<String, dynamic>> _roomsPreview(Map<String, dynamic> payload) {
    final raw = payload['rooms_preview'];
    if (raw is List) {
      return [
        for (final e in raw)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    }
    final snap = payload['snapshot'];
    if (snap is Map) {
      final rooms = snap['rooms'];
      if (rooms is List) {
        return [
          for (final e in rooms)
            if (e is Map)
              {
                'name': e['name'] ?? 'Помещение',
                if (e['floor_name'] != null) 'floor': e['floor_name'],
              },
        ];
      }
    }
    return const [];
  }

  Future<_AcceptDestination?> _askAcceptDestination({
    required String suggestedName,
  }) async {
    final projects = await AppScope.of(context).projects.listProjects(force: true);
    if (!mounted) return null;

    var mode = projects.any((p) => p.name == suggestedName)
        ? _AcceptMode.merge
        : _AcceptMode.create;
    Project? into = projects.cast<Project?>().firstWhere(
          (p) => p!.name == suggestedName,
          orElse: () => projects.isEmpty ? null : projects.first,
        );
    var newName = suggestedName;

    return showDialog<_AcceptDestination>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Куда сохранить'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Если объекта ещё нет — создайте новый. '
                      'Если он уже есть, но называется иначе — выберите его вручную.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<_AcceptMode>(
                      segments: [
                        const ButtonSegment(
                          value: _AcceptMode.create,
                          label: Text('Новый'),
                        ),
                        ButtonSegment(
                          value: _AcceptMode.merge,
                          label: const Text('В существующий'),
                          enabled: projects.isNotEmpty,
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) =>
                          setLocal(() => mode = s.first),
                    ),
                    const SizedBox(height: 12),
                    if (mode == _AcceptMode.create)
                      TextFormField(
                        initialValue: newName,
                        decoration: const InputDecoration(
                          labelText: 'Название объекта',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => newName = v,
                      )
                    else if (projects.isNotEmpty)
                      DropdownButtonFormField<Project>(
                        initialValue: into,
                        decoration: const InputDecoration(
                          labelText: 'Ваш объект',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final p in projects)
                            DropdownMenuItem(
                              value: p,
                              child: Text(p.name),
                            ),
                        ],
                        onChanged: (p) => setLocal(() => into = p),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  if (mode == _AcceptMode.create) {
                    final n = newName.trim();
                    if (n.isEmpty) return;
                    Navigator.pop(
                      ctx,
                      _AcceptDestination.create(n),
                    );
                  } else if (into?.id != null) {
                    Navigator.pop(
                      ctx,
                      _AcceptDestination.merge(into!.id!),
                    );
                  }
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _decide(SyncInboxItem item, bool accept) async {
    final scope = AppScope.of(context);
    String? applyNote;

    if (accept && item.kind == 'project') {
      final payload = item.payload;
      final suggested = (payload['project_name'] as String?)?.trim().isNotEmpty ==
              true
          ? payload['project_name'] as String
          : item.title;
      final dest = await _askAcceptDestination(suggestedName: suggested);
      if (dest == null) return;

      try {
        final newId = await scope.projects.applyProjectSharePayload(
          payload,
          intoProjectId: dest.intoProjectId,
          createAsName: dest.createAsName,
        );
        final name = dest.createAsName ??
            payload['project_name'] as String? ??
            item.title;
        final rooms = payload['room_count'] ?? _roomsPreview(payload).length;
        applyNote = dest.intoProjectId != null
            ? 'Помещения ($rooms) добавлены в выбранный объект'
            : 'Объект «$name» добавлен · помещений: $rooms · id $newId';
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить: $e')),
        );
        return;
      }
    } else if (accept && item.kind == 'prices') {
      final payload = item.payload;
      final snap = payload['snapshot'];
      final hasWork = snap is Map &&
          snap['categories'] is List &&
          (snap['categories'] as List).isNotEmpty;
      final hasSup = snap is Map &&
          snap['suppliers'] is List &&
          (snap['suppliers'] as List).isNotEmpty;
      final cats = (payload['category_count'] as num?)?.toInt() ??
          ((payload['categories_preview'] as List?)?.length ?? 0);
      final items = (payload['item_count'] as num?)?.toInt();
      final supCount = (payload['supplier_count'] as num?)?.toInt() ??
          ((payload['suppliers_preview'] as List?)?.length ?? 0);
      final priceLines = (payload['supplier_price_count'] as num?)?.toInt();
      final workMode = (payload['work_rates_mode'] as String?) ??
          ((payload['snapshot'] is Map
                  ? (payload['snapshot'] as Map)['work_rates_mode']
                  : null) as String?) ??
          'replace';
      final mergeWork = workMode == 'merge';
      final lines = <String>[];
      if (hasWork) {
        if (mergeWork) {
          lines.add(
            'Работы будут добавлены/обновлены в вашем каталоге'
            '${cats > 0 ? ' ($cats катег.' : ''}'
            '${items != null ? ', $items позиций' : ''}'
            '${cats > 0 ? ')' : ''}. '
            'Остальные ваши позиции не затронутся.',
          );
        } else {
          lines.add(
            'Каталог работ будет заменён'
            '${cats > 0 ? ' ($cats катег.' : ''}'
            '${items != null ? ', $items позиций' : ''}'
            '${cats > 0 ? ')' : ''}. '
            'Правки цен работ на этом устройстве пропадут.',
          );
        }
      }
      if (hasSup) {
        lines.add(
          'Цены материалов поставщиков сольются по имени'
          '${supCount > 0 ? ' ($supCount пост.' : ''}'
          '${priceLines != null ? ', $priceLines строк' : ''}'
          '${supCount > 0 ? ')' : ''}.',
        );
      }
      if (lines.isEmpty) {
        lines.add('В сообщении нет снимка расценок или материалов.');
      }
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Применить расценки?'),
          content: Text(lines.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                hasWork && !mergeWork ? 'Заменить' : 'Применить',
              ),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        final note = await PricesShare.applyPayload(
          payload,
          suppliers: scope.suppliers,
        );
        applyNote = 'Расценки обновлены · $note';
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось применить расценки: $e')),
        );
        return;
      }
    } else if (accept && item.kind == 'kit') {
      final payload = item.payload;
      final name = payload['kit_name'] as String? ?? item.title;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Сохранить комплект?'),
          content: Text(
            '«$name» будет добавлен в ваши комплекты материалов '
            '(${(payload['item_count'] as num?)?.toInt() ?? '—'} поз.).',
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
      if (confirm != true) return;
      try {
        final saved = await applyMountKitSharePayload(payload);
        applyNote = 'Комплект «${saved.name}» сохранён';
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить комплект: $e')),
        );
        return;
      }
    }

    final err = await scope.sync.decideOffer(
      itemId: item.id,
      accept: accept,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              (accept
                  ? (applyNote ?? 'Принято · ${item.title}')
                  : 'Отклонено · ${item.title}'),
        ),
      ),
    );
    await _reload();
  }

  Future<void> _showMessageDetail(SyncInboxItem item) async {
    final payload = item.payload;
    final projectName = payload['project_name'] as String?;
    final roomCount = payload['room_count'] as num?;
    final preview = _roomsPreview(payload);
    final hasSnapshot = payload['snapshot'] is Map;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 16 + bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: Icon(_kindIcon(item.kind)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          Text(
                            '${_kindLabel(item.kind)} · от @${item.fromLogin}',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (item.kind == 'project') ...[
                          Text(
                            projectName == null
                                ? 'Объект'
                                : 'Объект «$projectName»',
                            style: Theme.of(ctx).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Помещений: ${roomCount?.toInt() ?? preview.length}'
                            '${hasSnapshot ? '' : ' · без снимка (старое сообщение)'}',
                            style: Theme.of(ctx).textTheme.bodyMedium,
                          ),
                          if (preview.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Список помещений',
                              style: Theme.of(ctx).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            for (final r in preview)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.meeting_room_outlined),
                                title: Text('${r['name'] ?? 'Помещение'}'),
                                subtitle: r['floor'] != null
                                    ? Text('Этаж: ${r['floor']}')
                                    : null,
                                trailing: r['area_m2'] != null
                                    ? Text('${r['area_m2']} м²')
                                    : null,
                              ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'При принятии выберите: создать новый объект '
                            'или добавить помещения в уже существующий '
                            '(если он у вас называется иначе).',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ] else if (item.kind == 'prices') ...[
                          Text(
                            'Расценки и материалы',
                            style: Theme.of(ctx).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            () {
                              final has = payload['snapshot'] is Map;
                              if (!has) {
                                return 'Старое сообщение без снимка — '
                                    'принять не получится, попросите '
                                    'отправить ещё раз.';
                              }
                              final parts = <String>[];
                              final cats =
                                  (payload['category_count'] as num?)?.toInt();
                              final items =
                                  (payload['item_count'] as num?)?.toInt();
                              if (cats != null || items != null) {
                                parts.add(
                                  'Работы: ${cats ?? '—'} катег., '
                                  '${items ?? '—'} поз.',
                                );
                              }
                              final sc =
                                  (payload['supplier_count'] as num?)?.toInt();
                              final sp = (payload['supplier_price_count']
                                      as num?)
                                  ?.toInt();
                              if (sc != null || sp != null) {
                                parts.add(
                                  'Материалы: ${sc ?? '—'} пост., '
                                  '${sp ?? '—'} строк',
                                );
                              }
                              return parts.isEmpty
                                  ? 'Снимок без данных'
                                  : parts.join('\n');
                            }(),
                            style: Theme.of(ctx).textTheme.bodyMedium,
                          ),
                          if (payload['categories_preview'] is List) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Категории работ',
                              style: Theme.of(ctx).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            for (final raw
                                in payload['categories_preview'] as List)
                              if (raw is Map)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.payments_outlined),
                                  title: Text('${raw['name'] ?? 'Категория'}'),
                                  trailing: Text(
                                    '${raw['items'] ?? 0} поз.',
                                  ),
                                ),
                          ],
                          if (payload['suppliers_preview'] is List) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Поставщики',
                              style: Theme.of(ctx).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            for (final raw
                                in payload['suppliers_preview'] as List)
                              if (raw is Map)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.storefront_outlined),
                                  title: Text('${raw['name'] ?? 'Поставщик'}'),
                                  trailing: Text(
                                    '${raw['prices'] ?? 0} стр.',
                                  ),
                                ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            () {
                              final snap = payload['snapshot'];
                              final hasWork = snap is Map &&
                                  snap['categories'] is List &&
                                  (snap['categories'] as List).isNotEmpty;
                              final hasSup = snap is Map &&
                                  snap['suppliers'] is List &&
                                  (snap['suppliers'] as List).isNotEmpty;
                              final mode = (payload['work_rates_mode']
                                      as String?) ??
                                  (snap is Map
                                      ? snap['work_rates_mode'] as String?
                                      : null) ??
                                  'replace';
                              final merge = mode == 'merge';
                              if (hasWork && hasSup) {
                                return merge
                                    ? 'Работы — слияние; материалы — '
                                        'слияние по имени поставщика.'
                                    : 'Работы — замена каталога; '
                                        'материалы — слияние по имени.';
                              }
                              if (hasWork) {
                                return merge
                                    ? 'При принятии позиции добавятся/обновятся '
                                        'в вашем каталоге «Работа».'
                                    : 'При принятии локальный каталог «Работа» '
                                        'будет заменён этим снимком.';
                              }
                              if (hasSup) {
                                return 'При принятии цены материалов сольются '
                                    'с вашими поставщиками по имени.';
                              }
                              return '';
                            }(),
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ] else if (item.kind == 'kit') ...[
                          Text(
                            'Комплект материалов',
                            style: Theme.of(ctx).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            () {
                              final name =
                                  payload['kit_name'] as String? ?? item.title;
                              final section =
                                  payload['section'] as String? ?? 'any';
                              final items =
                                  (payload['item_count'] as num?)?.toInt();
                              final has = payload['snapshot'] is Map;
                              if (!has) {
                                return 'Старое сообщение без снимка — '
                                    'попросите отправить комплект ещё раз.';
                              }
                              return '«$name» · ${mountKitSectionLabel(section)}'
                                  ' · позиций: ${items ?? '—'}';
                            }(),
                            style: Theme.of(ctx).textTheme.bodyMedium,
                          ),
                          if (payload['items_preview'] is List) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Позиции',
                              style: Theme.of(ctx).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            for (final raw in payload['items_preview'] as List)
                              if (raw is Map)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.inventory_2_outlined),
                                  title: Text('${raw['name'] ?? 'Материал'}'),
                                  trailing: Text(
                                    '${raw['qty'] ?? ''} ${raw['unit'] ?? ''}'
                                        .trim(),
                                  ),
                                ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'При принятии комплект добавится в '
                            '«Расценки → Комплекты».',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ] else ...[
                          const Text('Сообщение'),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _decide(item, false);
                        },
                        child: const Text('Отклонить'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _decide(item, true);
                        },
                        child: const Text('Принять'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<SyncRemoteUser>> _loadDirectory(CeilingSyncController sync) async {
    try {
      return await sync.client.directory();
    } catch (_) {
      final me = sync.remoteUser?.login.toLowerCase();
      return [
        for (final r in [
          AppUserRole.superAdmin,
          AppUserRole.director,
          AppUserRole.foreman,
          AppUserRole.installer,
        ])
          if (testPersonaLogin(r) != me)
            SyncRemoteUser(
              fullName: r.labelRu,
              login: testPersonaLogin(r),
              requestedRole: r,
              confirmed: true,
              effectiveRole: r,
            ),
      ];
    }
  }

  Future<void> _composeMessage() async {
    final sync = AppScope.of(context).sync;
    if (!sync.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала войдите свитчером теста / облаком'),
        ),
      );
      return;
    }
    final projectsRepo = AppScope.of(context).projects;
    final userRole =
        AppScope.of(context).user.profile?.effectiveRole ??
            AppUserRole.installer;
    final canSendPricing = userRole.canPricing;
    final people = await _loadDirectory(sync);
    if (people.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет получателей в справочнике API')),
      );
      return;
    }

    final projects = await projectsRepo.listProjects();
    final availableKits = await loadMountKits();
    if (!mounted) return;

    var kind = 'project';
    final selectedLogins = <String>{};
    var sendAll = false;
    var contactsExpanded = false;
    var roomsExpanded = true;
    Project? project;
    Project? fullProject;
    final selectedRoomIds = <int>{};
    FinishMountKit? selectedKit;
    var title = '';
    Map<String, dynamic>? pricesPreview;
    Map<String, dynamic>? kitPreview;
    var includeWorkRates = true;
    var includeSuppliers = true;
    var pricesPreviewBusy = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          String pricesTitleFrom(Map<String, dynamic> p) {
            final hasWork = p['category_count'] != null;
            final hasSup = p['supplier_count'] != null;
            if (hasWork && hasSup) {
              return 'Расценки и материалы '
                  '(${p['category_count']} катег. · '
                  '${p['supplier_count']} пост.)';
            }
            if (hasSup) {
              return 'Цены материалов '
                  '(${p['supplier_count']} пост., '
                  '${p['supplier_price_count']} стр.)';
            }
            return 'Расценки работ '
                '(${p['category_count']} катег., '
                '${p['item_count']} поз.)';
          }

          String autoTitle() {
            if (kind == 'project' && project != null) {
              final n = selectedRoomIds.isEmpty ||
                      (fullProject != null &&
                          selectedRoomIds.length == fullProject!.rooms.length)
                  ? 'Проект «${project!.name}»'
                  : 'Помещения из «${project!.name}» '
                      '(${selectedRoomIds.length})';
              return n;
            }
            if (kind == 'prices' && pricesPreview != null) {
              return pricesTitleFrom(pricesPreview!);
            }
            if (kind == 'prices') return 'Расценки и материалы';
            if (kind == 'kit' && selectedKit != null) {
              return 'Комплект «${selectedKit!.name}»';
            }
            if (kind == 'kit') return 'Комплект материалов';
            return 'Сообщение';
          }

          List<SyncRemoteUser> visiblePeople() {
            if (kind == 'prices' || kind == 'kit') {
              return [
                for (final p in people)
                  if (p.effectiveRole.canPricing) p,
              ];
            }
            return people;
          }

          /// Recipients stay collapsed until content is chosen.
          final contentReady = kind == 'project'
              ? project != null && selectedRoomIds.isNotEmpty
              : kind == 'prices'
                  ? pricesPreview != null
                  : kind == 'kit'
                      ? kitPreview != null
                      : true;

          Future<void> refreshPricesPreview() async {
            if (!includeWorkRates && !includeSuppliers) {
              pricesPreview = null;
              contactsExpanded = false;
              setLocal(() {});
              return;
            }
            pricesPreviewBusy = true;
            setLocal(() {});
            try {
              pricesPreview = await PricesShare.buildPayload(
                suppliers: AppScope.of(context).suppliers,
                fromOwner: projectsRepo.activeOwnerLogin,
                includeWorkRates: includeWorkRates,
                supplierIds: includeSuppliers ? null : const <int>[],
              );
              contactsExpanded = true;
            } catch (_) {
              pricesPreview = null;
              contactsExpanded = false;
            }
            pricesPreviewBusy = false;
            if (ctx.mounted) setLocal(() {});
          }

          void pickKit(FinishMountKit? k) {
            selectedKit = k;
            title = '';
            if (k == null) {
              kitPreview = null;
              contactsExpanded = false;
            } else {
              kitPreview = buildMountKitSharePayload(
                k,
                fromOwner: projectsRepo.activeOwnerLogin,
              );
              contactsExpanded = true;
            }
            setLocal(() {});
          }

          Future<void> pickProject(Project? p) async {
            project = p;
            fullProject = null;
            selectedRoomIds.clear();
            contactsExpanded = false;
            title = '';
            setLocal(() {});
            if (p?.id == null) return;
            final loaded = await projectsRepo.getProject(p!.id!);
            if (!ctx.mounted) return;
            fullProject = loaded;
            selectedRoomIds
              ..clear()
              ..addAll([
                for (final r in loaded?.rooms ?? const <Room>[])
                  if (r.id != null) r.id!,
              ]);
            // Rooms auto-selected → open recipients.
            contactsExpanded = selectedRoomIds.isNotEmpty;
            setLocal(() {});
          }

          final roster = visiblePeople();
          final recipientsLabel = sendAll
              ? 'Всем (${roster.length})'
              : (selectedLogins.isEmpty
                  ? 'Никого не выбрано'
                  : 'Выбрано: ${selectedLogins.length}');

          return AlertDialog(
            title: const Text('Новое сообщение'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Что отправить',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        const ButtonSegment(
                          value: 'project',
                          label: Text('Проект'),
                        ),
                        ButtonSegment(
                          value: 'prices',
                          label: const Text('Расценки'),
                          enabled: canSendPricing,
                        ),
                        ButtonSegment(
                          value: 'kit',
                          label: const Text('Комплект'),
                          enabled: canSendPricing,
                        ),
                      ],
                      selected: {kind},
                      onSelectionChanged: (s) {
                        final next = s.first;
                        setLocal(() {
                          kind = next;
                          title = '';
                          selectedLogins.clear();
                          sendAll = false;
                          contactsExpanded = false;
                          if (next != 'prices') pricesPreview = null;
                          if (next != 'kit') {
                            selectedKit = null;
                            kitPreview = null;
                          }
                        });
                        if (next == 'prices') {
                          refreshPricesPreview();
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kind == 'project'
                          ? 'Можно отправить весь объект или отдельные '
                              'помещения. Получатель выберет: новый объект '
                              'или добавить в свой (даже с другим именем).'
                          : kind == 'prices'
                              ? (!canSendPricing
                                  ? 'Расценки могут отправлять бригадир, '
                                      'директор и админ.'
                                  : 'Отметьте, что включить: каталог работ '
                                      'и/или цены поставщиков. Работы у '
                                      'получателя заменятся; материалы '
                                      'сольются по имени.')
                              : (!canSendPricing
                                  ? 'Комплекты могут отправлять бригадир, '
                                      'директор и админ.'
                                  : 'Выберите комплект — у получателя он '
                                      'появится во входящих и в разделе '
                                      '«Комплекты» после принятия.'),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    if (kind == 'prices' && canSendPricing) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: includeWorkRates,
                        title: const Text('Каталог работ'),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) {
                          includeWorkRates = v ?? true;
                          pricesPreview = null;
                          refreshPricesPreview();
                        },
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: includeSuppliers,
                        title: const Text('Цены поставщиков'),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) {
                          includeSuppliers = v ?? true;
                          pricesPreview = null;
                          refreshPricesPreview();
                        },
                      ),
                      if (pricesPreviewBusy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(),
                        )
                      else if (pricesPreview != null)
                        Text(
                          () {
                            final p = pricesPreview!;
                            final parts = <String>[];
                            if (p['category_count'] != null) {
                              parts.add(
                                'работы: ${p['category_count']} катег., '
                                '${p['item_count']} поз.',
                              );
                            }
                            if (p['supplier_count'] != null) {
                              parts.add(
                                'материалы: ${p['supplier_count']} пост., '
                                '${p['supplier_price_count']} строк',
                              );
                            }
                            return parts.isEmpty
                                ? 'Нечего отправлять'
                                : 'Снимок: ${parts.join(' · ')}';
                          }(),
                          style: Theme.of(ctx).textTheme.bodySmall,
                        )
                      else if (!includeWorkRates && !includeSuppliers)
                        Text(
                          'Выберите хотя бы один блок.',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Theme.of(ctx).colorScheme.error,
                              ),
                        ),
                    ],
                    if (kind == 'kit') ...[
                      const SizedBox(height: 12),
                      if (availableKits.isEmpty)
                        const Text(
                          'Нет комплектов — создайте в «Расценки → Комплекты».',
                        )
                      else
                        DropdownButtonFormField<FinishMountKit>(
                          initialValue: selectedKit,
                          decoration: const InputDecoration(
                            labelText: 'Комплект',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final k in availableKits)
                              DropdownMenuItem(
                                value: k,
                                child: Text(
                                  '${k.name} · ${k.items.length} поз.',
                                ),
                              ),
                          ],
                          onChanged: pickKit,
                        ),
                    ],
                    if (kind == 'project') ...[
                      const SizedBox(height: 12),
                      if (projects.isEmpty)
                        const Text('Нет проектов — создайте объект.')
                      else
                        DropdownButtonFormField<Project>(
                          initialValue: project,
                          decoration: const InputDecoration(
                            labelText: 'Объект',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final p in projects)
                              DropdownMenuItem(
                                value: p,
                                child: Text(p.name),
                              ),
                          ],
                          onChanged: (p) => pickProject(p),
                        ),
                      if (fullProject != null &&
                          fullProject!.rooms.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Card(
                          child: ExpansionTile(
                            initiallyExpanded: roomsExpanded,
                            onExpansionChanged: (v) =>
                                roomsExpanded = v,
                            title: Text(
                              'Помещения '
                              '(${selectedRoomIds.length}/'
                              '${fullProject!.rooms.length})',
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => setLocal(() {
                                        selectedRoomIds
                                          ..clear()
                                          ..addAll([
                                            for (final r
                                                in fullProject!.rooms)
                                              if (r.id != null) r.id!,
                                          ]);
                                        contactsExpanded =
                                            selectedRoomIds.isNotEmpty;
                                      }),
                                      child: const Text('Все'),
                                    ),
                                    TextButton(
                                      onPressed: () => setLocal(() {
                                        selectedRoomIds.clear();
                                        contactsExpanded = false;
                                      }),
                                      child: const Text('Сбросить'),
                                    ),
                                  ],
                                ),
                              ),
                              for (final r in fullProject!.rooms)
                                if (r.id != null)
                                  CheckboxListTile(
                                    dense: true,
                                    value: selectedRoomIds.contains(r.id),
                                    title: Text(r.name),
                                    subtitle: () {
                                      String? floor;
                                      for (final f in fullProject!.floors) {
                                        if (f.id == r.floorId) {
                                          floor = f.name;
                                          break;
                                        }
                                      }
                                      return floor == null
                                          ? null
                                          : Text('Этаж: $floor');
                                    }(),
                                    onChanged: (v) => setLocal(() {
                                      if (v == true) {
                                        selectedRoomIds.add(r.id!);
                                      } else {
                                        selectedRoomIds.remove(r.id);
                                      }
                                      contactsExpanded =
                                          selectedRoomIds.isNotEmpty;
                                      title = '';
                                    }),
                                  ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    if (!contentReady)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.people_outline),
                          title: const Text('Кому'),
                          subtitle: Text(
                            kind == 'project'
                                ? 'Сначала выберите объект и помещения'
                                : kind == 'prices'
                                    ? 'Сначала дождитесь снимка каталога'
                                    : kind == 'kit'
                                        ? 'Сначала выберите комплект'
                                        : 'Сначала выберите тип сообщения',
                          ),
                        ),
                      )
                    else
                      Card(
                        child: ExpansionTile(
                          key: ValueKey(
                            'contacts-open-$contactsExpanded-'
                            '${selectedRoomIds.length}-$kind-'
                            '${roster.length}',
                          ),
                          initiallyExpanded: contactsExpanded,
                          onExpansionChanged: (v) =>
                              contactsExpanded = v,
                          title: Text('Кому · $recipientsLabel'),
                          children: [
                            CheckboxListTile(
                              value: sendAll,
                              title: const Text('Отправить всем'),
                              subtitle: Text(
                                kind == 'prices' || kind == 'kit'
                                    ? 'Бригадир+ из справочника (${roster.length})'
                                    : 'Всем из справочника (${roster.length})',
                              ),
                              onChanged: roster.isEmpty
                                  ? null
                                  : (v) => setLocal(() {
                                        sendAll = v == true;
                                        if (sendAll) {
                                          selectedLogins
                                            ..clear()
                                            ..addAll(
                                              roster.map((p) => p.login),
                                            );
                                        } else {
                                          selectedLogins.clear();
                                        }
                                      }),
                            ),
                            const Divider(height: 1),
                            if (roster.isEmpty)
                              const ListTile(
                                dense: true,
                                title: Text('Нет подходящих получателей'),
                              )
                            else
                              for (final p in roster)
                                CheckboxListTile(
                                  dense: true,
                                  value: selectedLogins.contains(p.login),
                                  title: Text(p.fullName),
                                  subtitle: Text(
                                    '@${p.login} · ${p.effectiveRole.labelRu}',
                                  ),
                                  onChanged: sendAll
                                      ? null
                                      : (v) => setLocal(() {
                                            if (v == true) {
                                              selectedLogins.add(p.login);
                                            } else {
                                              selectedLogins.remove(p.login);
                                            }
                                          }),
                                ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: title.isEmpty ? autoTitle() : title,
                      key: ValueKey(
                        '$kind-${project?.id}-'
                        '${selectedRoomIds.length}-'
                        '${selectedLogins.length}-$sendAll',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Заголовок',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => title = v,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  final rosterNow = visiblePeople();
                  final recipients = sendAll
                      ? rosterNow.map((p) => p.login).toSet()
                      : selectedLogins;
                  if (recipients.isEmpty) return;
                  if (kind == 'project' &&
                      (project == null || selectedRoomIds.isEmpty)) {
                    return;
                  }
                  if (kind == 'prices' && pricesPreview == null) return;
                  if (kind == 'kit' && kitPreview == null) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Отправить'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || !mounted) return;
    final rosterForSend = (kind == 'prices' || kind == 'kit')
        ? [
            for (final p in people)
              if (p.effectiveRole.canPricing) p,
          ]
        : people;
    final recipients = sendAll
        ? rosterForSend.map((p) => p.login).toList()
        : selectedLogins.toList();
    if (recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите получателей')),
      );
      return;
    }
    if (kind == 'project' &&
        (project?.id == null || selectedRoomIds.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите объект и помещения')),
      );
      return;
    }
    if (kind == 'kit' && selectedKit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите комплект')),
      );
      return;
    }

    Map<String, dynamic> payload;
    if (kind == 'project') {
      try {
        payload = await projectsRepo.buildProjectSharePayload(
          project!.id!,
          roomIds: selectedRoomIds,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось собрать объект: $e')),
        );
        return;
      }
    } else if (kind == 'prices') {
      try {
        payload = pricesPreview ??
            await PricesShare.buildPayload(
              suppliers: AppScope.of(context).suppliers,
              fromOwner: projectsRepo.activeOwnerLogin,
              includeWorkRates: includeWorkRates,
              supplierIds: includeSuppliers ? null : const <int>[],
            );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось собрать расценки: $e')),
        );
        return;
      }
    } else if (kind == 'kit') {
      payload = kitPreview ??
          buildMountKitSharePayload(
            selectedKit!,
            fromOwner: projectsRepo.activeOwnerLogin,
          );
    } else {
      payload = {
        'stub': true,
        'kind': kind,
      };
    }

    final sendTitle = title.trim().isEmpty
        ? (kind == 'project'
            ? (selectedRoomIds.length == (fullProject?.rooms.length ?? 0)
                ? 'Проект «${project!.name}»'
                : 'Помещения из «${project!.name}» (${selectedRoomIds.length})')
            : (kind == 'prices'
                ? () {
                    final hasWork = payload['category_count'] != null;
                    final hasSup = payload['supplier_count'] != null;
                    if (hasWork && hasSup) {
                      return 'Расценки и материалы '
                          '(${payload['category_count']} катег. · '
                          '${payload['supplier_count']} пост.)';
                    }
                    if (hasSup) {
                      return 'Цены материалов '
                          '(${payload['supplier_count']} пост.)';
                    }
                    return 'Расценки работ '
                        '(${payload['category_count']} катег., '
                        '${payload['item_count']} поз.)';
                  }()
                : 'Комплект «${selectedKit!.name}»'))
        : title.trim();

    final errors = <String>[];
    var sent = 0;
    for (final login in recipients) {
      final err = await sync.sendOffer(
        kind: kind,
        title: sendTitle,
        toLogin: login,
        payloadJson: jsonEncode(payload),
      );
      if (err == null) {
        sent++;
      } else {
        errors.add('@$login: $err');
      }
    }
    if (!mounted) return;
    final names = [
      for (final p in rosterForSend)
        if (recipients.contains(p.login)) p.fullName,
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errors.isEmpty
              ? 'Отправлено ($sent): ${names.join(', ')}'
              : 'Отправлено $sent из ${recipients.length}. '
                  '${errors.first}',
        ),
      ),
    );
    await _reload();
  }

  IconData _kindIcon(String kind) => switch (kind) {
        'prices' => Icons.payments_outlined,
        'kit' => Icons.inventory_2_outlined,
        _ => Icons.apartment_outlined,
      };

  String _kindLabel(String kind) => switch (kind) {
        'prices' => 'Расценки',
        'kit' => 'Комплект',
        _ => 'Проект',
      };

  @override
  Widget build(BuildContext context) {
    final sync = AppScope.of(context).sync;
    final scheme = Theme.of(context).colorScheme;
    final sorted = _sortedItems;

    return ScreenScaffold(
      embeddedMaxWidth: AdaptiveBreakpoints.paneReadableWide,
      appBar: AppBar(
        title: const Text('Входящие'),
        actions: [
          IconButton(
            tooltip: 'Новое сообщение',
            icon: const Icon(Icons.send_outlined),
            onPressed: _composeMessage,
          ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: EdgeInsets.all(
            DesktopMetrics.of(context) ? 12 : 16,
          ),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  sync.status == CloudSyncStatus.offlineLocal
                      ? Icons.cloud_off_outlined
                      : (sync.isSignedIn
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_outlined),
                ),
                title: Text(sync.statusHintRu),
                subtitle: Text(
                  sync.isSignedIn
                      ? 'Сервер ${sync.client.baseUrl} · сообщения идут '
                          'через API; объекты копируются из снимка в вашу БД.'
                      : 'Войдите свитчером теста · ${sync.client.baseUrl}',
                ),
                isThreeLine: true,
                trailing: sync.isSignedIn
                    ? null
                    : TextButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LocalProfileScreen(),
                            ),
                          );
                          await _reload();
                        },
                        child: const Text('Войти'),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _filterTile(
              context,
              kind: 'project',
              icon: Icons.apartment_outlined,
              title: 'Проекты и комнаты',
              count: sync.pendingProjectOffers,
            ),
            _filterTile(
              context,
              kind: 'prices',
              icon: Icons.payments_outlined,
              title: 'Расценки и материалы',
              count: sync.pendingPricePushes,
            ),
            _filterTile(
              context,
              kind: 'kit',
              icon: Icons.inventory_2_outlined,
              title: 'Комплекты',
              count: sync.pendingKitOffers,
            ),
            const Divider(height: 28),
            Text(
              _filterKind == null
                  ? 'Все сообщения'
                  : 'Сначала: ${_kindLabel(_filterKind!)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              Card(
                child: ListTile(
                  leading: Icon(Icons.error_outline, color: scheme.error),
                  title: const Text('Не удалось загрузить'),
                  subtitle: Text(_loadError!),
                  trailing: TextButton(
                    onPressed: _reload,
                    child: const Text('Повторить'),
                  ),
                ),
              )
            else if (!sync.isSignedIn)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Нужен облачный вход'),
                  subtitle: Text('Локальный профиль работает без синка'),
                ),
              )
            else if (sorted.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.inbox_outlined),
                  title: Text('Пусто'),
                  subtitle: Text('Нет ожидающих сообщений'),
                ),
              )
            else
              for (var i = 0; i < sorted.length; i++) ...[
                if (_filterKind != null &&
                    i > 0 &&
                    sorted[i - 1].kind == _filterKind &&
                    sorted[i].kind != _filterKind)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(
                      'Остальные',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    color: _filterKind != null && sorted[i].kind == _filterKind
                        ? scheme.primaryContainer.withValues(alpha: 0.35)
                        : null,
                    child: ListTile(
                      minTileHeight: 72,
                      leading: CircleAvatar(
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        child: Icon(_kindIcon(sorted[i].kind)),
                      ),
                      title: Text(sorted[i].title),
                      subtitle: Text(
                        '${_kindLabel(sorted[i].kind)} · от @${sorted[i].fromLogin}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showMessageDetail(sorted[i]),
                    ),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _filterTile(
    BuildContext context, {
    required String kind,
    required IconData icon,
    required String title,
    required int count,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _filterKind == kind;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: selected ? scheme.secondaryContainer : null,
        child: ListTile(
          minTileHeight: 64,
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Icon(icon),
              ),
              if (count > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: scheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(title),
          subtitle: Text(
            selected
                ? (count == 0 ? 'Фильтр · пусто' : 'Фильтр · новых: $count')
                : (count == 0 ? 'Нет входящих' : 'Новых: $count'),
          ),
          trailing: Icon(
            selected ? Icons.filter_alt : Icons.filter_alt_outlined,
          ),
          onTap: () => setState(() {
            _filterKind = selected ? null : kind;
          }),
        ),
      ),
    );
  }
}

enum _AcceptMode { create, merge }

class _AcceptDestination {
  const _AcceptDestination._({this.intoProjectId, this.createAsName});
  factory _AcceptDestination.create(String name) =>
      _AcceptDestination._(createAsName: name);
  factory _AcceptDestination.merge(int projectId) =>
      _AcceptDestination._(intoProjectId: projectId);

  final int? intoProjectId;
  final String? createAsName;
}
