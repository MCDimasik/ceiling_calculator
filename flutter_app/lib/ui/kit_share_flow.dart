import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/ceiling_sync_client.dart';
import '../domain/finish_material_links.dart';
import '../domain/local_user_role.dart';
import 'widgets/share_destination_sheet.dart';

/// Long-press / menu: file vs in-app, then recipients.
Future<void> shareMountKit(BuildContext context, FinishMountKit kit) async {
  final headline = 'Комплект «${kit.name}»';
  final detail =
      '${mountKitSectionLabel(kit.section)} · ${kit.items.length} поз.';
  final dest = await showShareDestinationSheet(
    context,
    headline: headline,
    detail: detail,
  );
  if (dest == null || !context.mounted) return;

  final scope = AppScope.of(context);
  final payload = buildMountKitSharePayload(
    kit,
    fromOwner: scope.projects.activeOwnerLogin,
  );

  if (dest == ShareDestination.file) {
    final dir = await getTemporaryDirectory();
    final safe = kit.name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final file = File(p.join(dir.path, 'visota_${safe}_kit.json'));
    await file.writeAsString(jsonEncode(payload), encoding: utf8);
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: headline),
      );
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    return;
  }

  await showInAppKitShareDialog(context, kit: kit);
}

Future<void> showInAppKitShareDialog(
  BuildContext context, {
  required FinishMountKit kit,
}) async {
  final scope = AppScope.of(context);
  final sync = scope.sync;
  if (!sync.isSignedIn) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Войдите свитчером теста / облаком, чтобы отправить внутри приложения',
        ),
      ),
    );
    return;
  }
  final role =
      scope.user.profile?.effectiveRole ?? AppUserRole.installer;
  if (!role.canPricing) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Отправлять комплекты могут бригадир, директор и админ'),
      ),
    );
    return;
  }

  List<SyncRemoteUser> people = const [];
  try {
    people = await sync.client.directory();
  } catch (_) {
    final me = sync.remoteUser?.login.toLowerCase();
    people = [
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
  if (!context.mounted) return;
  final roster = [
    for (final p in people)
      if (p.effectiveRole.canPricing) p,
  ];
  if (roster.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет получателей с правом на расценки')),
    );
    return;
  }

  final selectedLogins = <String>{};
  var sendAll = false;
  var contactsExpanded = true;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final recipientsLabel = sendAll
            ? 'Всем (${roster.length})'
            : (selectedLogins.isEmpty
                ? 'Никого не выбрано'
                : 'Выбрано: ${selectedLogins.length}');
        return AlertDialog(
          title: const Text('Отправить в приложении'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Комплект «${kit.name}»',
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${mountKitSectionLabel(kit.section)} · '
                    '${kit.items.length} поз.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ExpansionTile(
                      initiallyExpanded: contactsExpanded,
                      onExpansionChanged: (v) => contactsExpanded = v,
                      title: Text('Кому · $recipientsLabel'),
                      children: [
                        CheckboxListTile(
                          value: sendAll,
                          title: const Text('Отправить всем'),
                          subtitle: Text(
                            'Бригадир / директор / админ (${roster.length})',
                          ),
                          onChanged: (v) => setLocal(() {
                            sendAll = v == true;
                            if (sendAll) {
                              selectedLogins
                                ..clear()
                                ..addAll(roster.map((p) => p.login));
                            } else {
                              selectedLogins.clear();
                            }
                          }),
                        ),
                        const Divider(height: 1),
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
                final recipients = sendAll
                    ? roster.map((p) => p.login).toSet()
                    : selectedLogins;
                if (recipients.isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Отправить'),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;

  final recipients = sendAll
      ? roster.map((p) => p.login).toList()
      : selectedLogins.toList();
  final err = await sendMountKitOffers(
    context,
    kit: kit,
    toLogins: recipients,
  );
  if (!context.mounted) return;
  final names = [
    for (final p in roster)
      if (recipients.contains(p.login)) p.fullName,
  ];
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        err ?? 'Отправлено (${recipients.length}): ${names.join(', ')}',
      ),
    ),
  );
}

/// Send one kit to recipients (or all pricing-capable users).
Future<String?> sendMountKitOffers(
  BuildContext context, {
  required FinishMountKit kit,
  List<String>? toLogins,
  bool sendAllPricing = false,
}) async {
  final scope = AppScope.of(context);
  final sync = scope.sync;
  if (!sync.isSignedIn) {
    return 'Войдите свитчером теста / облаком';
  }

  List<SyncRemoteUser> people = const [];
  try {
    people = await sync.client.directory();
  } catch (_) {
    final me = sync.remoteUser?.login.toLowerCase();
    people = [
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

  final roster = [
    for (final p in people)
      if (p.effectiveRole.canPricing) p,
  ];
  final recipients = sendAllPricing
      ? roster.map((p) => p.login).toList()
      : (toLogins ?? const <String>[]);
  if (recipients.isEmpty) {
    return 'Нет получателей (нужны бригадир / директор / админ)';
  }

  final payload = buildMountKitSharePayload(
    kit,
    fromOwner: scope.projects.activeOwnerLogin,
  );
  final title = 'Комплект «${kit.name}»';
  final errors = <String>[];
  var sent = 0;
  for (final login in recipients) {
    final err = await sync.sendOffer(
      kind: 'kit',
      title: title,
      toLogin: login,
      payloadJson: jsonEncode(payload),
    );
    if (err == null) {
      sent++;
    } else {
      errors.add('@$login: $err');
    }
  }
  if (errors.isEmpty) {
    return null; // success — caller shows snackbar with count
  }
  return 'Отправлено $sent из ${recipients.length}. ${errors.first}';
}

/// Pending kit offers sheet (from «+ Комплект» badge).
Future<void> showPendingKitsInboxSheet(BuildContext context) async {
  final sync = AppScope.of(context).sync;
  if (!sync.isSignedIn) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нужен вход в облако / свитчер теста')),
    );
    return;
  }
  await sync.refreshInbox();
  if (!context.mounted) return;
  List<SyncInboxItem> kits;
  try {
    final all = await sync.fetchInbox();
    kits = [for (final i in all) if (i.kind == 'kit') i];
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Не удалось загрузить: $e')),
    );
    return;
  }
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Входящие комплекты',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Сохранить себе или отклонить',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (kits.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Нет ожидающих комплектов', textAlign: TextAlign.center),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: kits.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final item = kits[i];
                      final p = item.payload;
                      final name = p['kit_name'] as String? ?? item.title;
                      final section = p['section'] as String? ?? 'any';
                      final count = (p['item_count'] as num?)?.toInt() ?? 0;
                      return Card(
                        child: ListTile(
                          title: Text(name),
                          subtitle: Text(
                            '${mountKitSectionLabel(section)} · $count поз. · '
                            'от @${item.fromLogin}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Отклонить',
                                onPressed: () async {
                                  await sync.decideOffer(
                                    itemId: item.id,
                                    accept: false,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                                icon: const Icon(Icons.close),
                              ),
                              FilledButton(
                                onPressed: () async {
                                  try {
                                    await applyMountKitSharePayload(p);
                                    await sync.decideOffer(
                                      itemId: item.id,
                                      accept: true,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Комплект «$name» сохранён',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                    }
                                    return;
                                  }
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                                child: const Text('Сохранить'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
