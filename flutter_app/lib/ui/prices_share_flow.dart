import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/ceiling_sync_client.dart';
import '../domain/cost_calculator.dart';
import '../domain/local_user_role.dart';
import '../domain/prices_share.dart';
import '../domain/work_rates_catalog.dart';
import 'widgets/share_destination_sheet.dart';

/// Share work rates / materials: file vs in-app, with recipient picker.
Future<void> sharePricesSelection(
  BuildContext context, {
  required String headline,
  String? detail,
  required Future<Map<String, dynamic>> Function() buildPayload,
}) async {
  final dest = await showShareDestinationSheet(
    context,
    headline: headline,
    detail: detail,
  );
  if (dest == null || !context.mounted) return;

  late final Map<String, dynamic> payload;
  try {
    payload = await buildPayload();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Не удалось собрать снимок: $e')),
    );
    return;
  }

  if (dest == ShareDestination.file) {
    await _sharePricesFile(payload, subject: headline);
    return;
  }

  await showInAppPricesShareDialog(
    context,
    payload: payload,
    headline: headline,
    detail: detail,
  );
}

Future<void> shareWorkCategory(
  BuildContext context, {
  required WorkRateCategory category,
  Iterable<String>? itemMatchKeys,
}) {
  final keys = itemMatchKeys?.toList();
  final headline = keys == null
      ? 'Категория «${category.name}»'
      : (keys.length == 1
          ? 'Работа · ${category.name}'
          : '${keys.length} работ · ${category.name}');
  final detail = keys == null
      ? '${category.items.length} позиций'
      : [
          for (final i in category.items)
            if (keys.contains(i.matchKey)) i.name,
        ].join(', ');
  return sharePricesSelection(
    context,
    headline: headline,
    detail: detail,
    buildPayload: () => PricesShare.buildWorkCategoryPayload(
      category: category,
      fromOwner: AppScope.of(context).projects.activeOwnerLogin,
      itemMatchKeys: keys,
    ),
  );
}

Future<void> shareSupplierMaterials(
  BuildContext context, {
  required Supplier supplier,
  Iterable<String>? itemKeys,
  List<SupplierPrice>? selectedPrices,
}) {
  final id = supplier.id;
  if (id == null) {
    return Future.value();
  }
  final keys = itemKeys?.toList() ??
      selectedPrices?.map((p) => p.itemKey).toList();
  final headline = keys == null
      ? 'Поставщик «${supplier.name}»'
      : (keys.length == 1
          ? (selectedPrices?.first.productName ?? 'Материал')
          : '${keys.length} материалов · ${supplier.name}');
  final detail = keys == null
      ? 'Все позиции с ценами'
      : (selectedPrices?.map((p) => p.productName).join(', ') ??
          '${keys.length} поз.');
  return sharePricesSelection(
    context,
    headline: headline,
    detail: detail,
    buildPayload: () => PricesShare.buildSupplierMaterialsPayload(
      suppliers: AppScope.of(context).suppliers,
      supplierId: id,
      fromOwner: AppScope.of(context).projects.activeOwnerLogin,
      itemKeys: keys,
    ),
  );
}

Future<void> _sharePricesFile(
  Map<String, dynamic> payload, {
  required String subject,
}) async {
  final dir = await getTemporaryDirectory();
  final safe = subject
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .trim();
  final base = safe.isEmpty ? 'prices' : safe;
  final file = File(p.join(dir.path, 'visota_${base}_prices.json'));
  await file.writeAsString(jsonEncode(payload), encoding: utf8);
  try {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
  } finally {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Prefills payload; user only picks recipients (pricing roles).
Future<void> showInAppPricesShareDialog(
  BuildContext context, {
  required Map<String, dynamic> payload,
  required String headline,
  String? detail,
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
        content: Text('Отправлять расценки могут бригадир, директор и админ'),
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
                  Text(headline, style: Theme.of(ctx).textTheme.titleSmall),
                  if (detail != null && detail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(detail, style: Theme.of(ctx).textTheme.bodySmall),
                  ],
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
  if (recipients.isEmpty) return;

  final sendTitle = PricesShare.titleForPayload(payload);
  final errors = <String>[];
  var sent = 0;
  for (final login in recipients) {
    final err = await sync.sendOffer(
      kind: 'prices',
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
  if (!context.mounted) return;
  final names = [
    for (final p in roster)
      if (recipients.contains(p.login)) p.fullName,
  ];
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        errors.isEmpty
            ? 'Отправлено ($sent): ${names.join(', ')}'
            : 'Отправлено $sent из ${recipients.length}. ${errors.first}',
      ),
    ),
  );
}

/// Send to all pricing users (toolbar / «для всех»).
Future<String?> sendPricesOffers(
  BuildContext context, {
  bool includeWorkRates = true,
  Iterable<int>? supplierIds,
  Map<int, Iterable<String>>? supplierItemKeys,
  List<String>? toLogins,
  bool sendAllPricing = false,
}) async {
  final scope = AppScope.of(context);
  late final Map<String, dynamic> payload;
  try {
    payload = await PricesShare.buildPayload(
      suppliers: scope.suppliers,
      fromOwner: scope.projects.activeOwnerLogin,
      includeWorkRates: includeWorkRates,
      supplierIds: supplierIds,
      supplierItemKeys: supplierItemKeys,
    );
  } catch (e) {
    return 'Не удалось собрать снимок: $e';
  }

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
  final title = PricesShare.titleForPayload(payload);
  final errors = <String>[];
  var sent = 0;
  for (final login in recipients) {
    final err = await sync.sendOffer(
      kind: 'prices',
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
  if (errors.isEmpty) return null;
  return 'Отправлено $sent из ${recipients.length}. ${errors.first}';
}
