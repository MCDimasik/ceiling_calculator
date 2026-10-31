import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/ceiling_sync_client.dart';
import '../domain/local_user_role.dart';
import '../domain/models.dart';
import '../domain/project_transfer.dart';
import 'widgets/share_destination_sheet.dart';

/// Share project / rooms: choose file vs in-app, then run that path.
Future<void> shareProjectOrRooms(
  BuildContext context, {
  required Project project,
  List<Room>? rooms,
}) async {
  final roomList = rooms;
  final headline = roomList == null || roomList.isEmpty
      ? 'Объект «${project.name}»'
      : (roomList.length == 1
          ? '«${roomList.first.name}» · ${project.name}'
          : '${roomList.length} помещений · ${project.name}');
  final detail = roomList == null || roomList.isEmpty
      ? 'Все помещения объекта'
      : roomList.map((r) => r.name).join(', ');

  final dest = await showShareDestinationSheet(
    context,
    headline: headline,
    detail: detail,
  );
  if (dest == null || !context.mounted) return;

  if (dest == ShareDestination.file) {
    await shareProject(project, rooms: roomList);
    return;
  }

  await showInAppProjectShareDialog(
    context,
    project: project,
    roomIds: [
      for (final r in roomList ?? project.rooms)
        if (r.id != null) r.id!,
    ],
  );
}

/// Prefills object + rooms; user only picks recipients.
Future<void> showInAppProjectShareDialog(
  BuildContext context, {
  required Project project,
  required List<int> roomIds,
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
  if (project.id == null) return;
  final ids = roomIds.where((e) => e > 0).toList();
  if (ids.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет помещений для отправки')),
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
  if (people.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет получателей в справочнике')),
    );
    return;
  }

  final selectedLogins = <String>{};
  var sendAll = false;
  var contactsExpanded = true;
  final roomNames = [
    for (final r in project.rooms)
      if (r.id != null && ids.contains(r.id)) r.name,
  ];

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final recipientsLabel = sendAll
            ? 'Всем (${people.length})'
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
                    'Объект «${project.name}»',
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ids.length == project.rooms.length
                        ? 'Все помещения (${ids.length})'
                        : 'Помещения (${ids.length}): ${roomNames.join(', ')}',
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
                            'Всем из справочника (${people.length})',
                          ),
                          onChanged: (v) => setLocal(() {
                            sendAll = v == true;
                            if (sendAll) {
                              selectedLogins
                                ..clear()
                                ..addAll(people.map((p) => p.login));
                            } else {
                              selectedLogins.clear();
                            }
                          }),
                        ),
                        const Divider(height: 1),
                        for (final p in people)
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
                    ? people.map((p) => p.login).toSet()
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
      ? people.map((p) => p.login).toList()
      : selectedLogins.toList();
  if (recipients.isEmpty) return;

  late final Map<String, dynamic> payload;
  try {
    payload = await scope.projects.buildProjectSharePayload(
      project.id!,
      roomIds: ids,
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Не удалось собрать объект: $e')),
    );
    return;
  }

  final sendTitle = ids.length == project.rooms.length
      ? 'Проект «${project.name}»'
      : 'Помещения из «${project.name}» (${ids.length})';

  final errors = <String>[];
  var sent = 0;
  for (final login in recipients) {
    final err = await sync.sendOffer(
      kind: 'project',
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
    for (final p in people)
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
