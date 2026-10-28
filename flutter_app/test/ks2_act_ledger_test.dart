import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/ks2_act_service.dart';
import 'package:ceiling_calculator/domain/ks2_room_closure_status.dart';
import 'package:ceiling_calculator/domain/ks2_work_scope.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/project_doc_format_detector.dart';

void main() {
  test('Ks2ActRecord serializes', () {
    final act = Ks2ActRecord(
      id: 'a1',
      actNumber: 3,
      scope: WorkScope.floor.name,
      roomIds: [1, 2],
      roomNames: ['101', '102'],
      totalAmount: 150000,
      createdAt: DateTime(2026, 3, 15),
      status: Ks2ActStatus.issued,
    );
    final back = Ks2ActRecord.fromJson(act.toJson());
    expect(back.actNumber, 3);
    expect(back.scope, 'floor');
    expect(back.roomNames, ['101', '102']);
    expect(back.totalAmount, 150000);
  });

  test('ProjectDocumentation stores ks2Acts', () {
    final doc = ProjectDocumentation(
      ks2Acts: [
        Ks2ActRecord(
          id: 'x',
          actNumber: 1,
          scope: 'walls',
          roomIds: [5],
          roomNames: ['Hall'],
          totalAmount: 50000,
          createdAt: DateTime(2026, 1, 10),
        ),
      ],
      requireFullKs2Pricing: true,
    );
    final raw = doc.toJson();
    final back = ProjectDocumentation.fromJson(raw);
    expect(back.ks2Acts.length, 1);
    expect(back.ks2Acts.first.scope, 'walls');
    expect(back.requireFullKs2Pricing, true);
  });

  test('buildKs3LedgerRows cumulative', () {
    final acts = [
      Ks2ActRecord(
        id: '1',
        actNumber: 1,
        scope: 'floor',
        roomIds: [1],
        roomNames: ['101'],
        totalAmount: 100000,
        createdAt: DateTime(2026, 2, 1),
      ),
      Ks2ActRecord(
        id: '2',
        actNumber: 2,
        scope: 'walls',
        roomIds: [1],
        roomNames: ['101'],
        totalAmount: 200000,
        createdAt: DateTime(2026, 2, 20),
      ),
    ];
    final rows = buildKs3LedgerRows(
      acts: acts,
      periodFrom: DateTime(2026, 2, 1),
      periodTo: DateTime(2026, 2, 28),
    );
    expect(rows.length, 2);
    expect(rows[0].scopeLabel, 'Пол');
    expect(rows[0].periodSum, 100000);
    expect(rows[0].cumulativeSum, 100000);
    expect(rows[1].scopeLabel, 'Стены');
    expect(rows[1].periodSum, 200000);
    expect(rows[1].cumulativeSum, 200000);
    expect(ledgerContractTotal(acts), 300000);
  });

  test('ProjectDocumentation stores enabledWorkScopes', () {
    final doc = ProjectDocumentation(enabledWorkScopes: ['walls', 'floor']);
    final back = ProjectDocumentation.fromJson(doc.toJson());
    expect(back.enabledWorkScopes, ['walls', 'floor']);
  });

  test('ks2RowMatchesScope filters sections', () {
    expect(
      ks2RowMatchesScope(
        {'name': 'Площадь пола', 'section': 'Помещение'},
        WorkScope.floor,
      ),
      true,
    );
    expect(
      ks2RowMatchesScope(
        {'name': 'Плиты', 'section': 'Потолок'},
        WorkScope.floor,
      ),
      false,
    );
    expect(
      ks2RowMatchesScope({'name': 'Обои', 'section': 'Стены'}, WorkScope.walls),
      true,
    );
  });

  test('guessMatchKeyForImport uses section column', () {
    expect(guessMatchKeyForImport('Устройство покрытия', section: 'Пол'), 'finish_floor');
    expect(guessMatchKeyForImport('Штукатурка', section: 'Стены'), 'finish_wall');
    expect(guessMatchKeyForImport('Монтаж каркаса', section: 'Потолок'), 'finish_ceiling');
  });

  test('WorkScope.encodeKey multi-scope', () {
    expect(
      WorkScope.encodeKey([WorkScope.walls, WorkScope.floor]),
      'floor+walls',
    );
  });

  test('activeKs2Acts excludes cancelled', () {
    final acts = [
      Ks2ActRecord(
        id: '1',
        actNumber: 1,
        scope: 'floor',
        roomIds: [1],
        roomNames: ['101'],
        totalAmount: 100,
        createdAt: DateTime(2026, 1, 1),
      ),
      Ks2ActRecord(
        id: '2',
        actNumber: 2,
        scope: 'walls',
        roomIds: [1],
        roomNames: ['101'],
        totalAmount: 200,
        createdAt: DateTime(2026, 1, 2),
        status: Ks2ActStatus.cancelled,
      ),
    ];
    expect(activeKs2Acts(acts).length, 1);
    expect(ledgerContractTotal(acts), 100);
  });

  test('cancel act reopens room for scoped KS-2', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final room = Room(
      id: 1,
      name: '101',
      walls: walls,
      documentationChecklistJson: RoomDocumentationChecklist(
        hiddenWorksConfirmed: {'hw_floor': true},
      ).toJson(),
    );
    final project = Project(id: 1, name: 'Obj', rooms: [room]);
    final doc = ProjectDocumentation(enabledWorkScopes: ['floor']);
    registerKs2Act(
      doc: doc,
      scopes: [WorkScope.floor],
      rooms: [room],
      totalAmount: 1000,
    );
    expect(isRoomScopeClosed(roomId: 1, scope: WorkScope.floor, acts: doc.ks2Acts), isTrue);
    expect(
      roomsReadyForScopedKs2(
        project: project,
        doc: doc,
        scope: WorkScope.floor,
        acts: doc.ks2Acts,
      ),
      isEmpty,
    );
    cancelKs2Act(doc, doc.ks2Acts.first.id, reason: 'ошибка');
    expect(isRoomScopeClosed(roomId: 1, scope: WorkScope.floor, acts: doc.ks2Acts), isFalse);
    expect(
      roomsReadyForScopedKs2(
        project: project,
        doc: doc,
        scope: WorkScope.floor,
        acts: doc.ks2Acts,
      ).map((r) => r.id),
      [1],
    );
  });

  test('amendKs2ActAmount replaces act and keeps trail', () {
    final room = Room(id: 1, name: '101', walls: [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ]);
    final doc = ProjectDocumentation();
    final original = registerKs2Act(
      doc: doc,
      scopes: [WorkScope.floor],
      rooms: [room],
      totalAmount: 100,
      scopeBreakdown: {'floor': 100},
    );
    final replacement = amendKs2ActAmount(
      doc: doc,
      actId: original.id,
      newAmount: 80,
      note: 'пересчёт',
    );
    expect(doc.ks2Acts.length, 2);
    expect(
      doc.ks2Acts.firstWhere((a) => a.id == original.id).status,
      Ks2ActStatus.cancelled,
    );
    expect(replacement.amendedFromId, original.id);
    expect(replacement.totalAmount, 80);
    expect(activeKs2Acts(doc.ks2Acts).length, 1);
    expect(ledgerContractTotal(doc.ks2Acts), 80);
  });

  test('roomClosureStatusSummary compactLabel for ready floor', () {
    final room = Room(
      id: 1,
      name: '101',
      walls: [
        [0.0, 0.0, 400.0, 0.0],
        [400.0, 0.0, 400.0, 300.0],
        [400.0, 300.0, 0.0, 300.0],
        [0.0, 300.0, 0.0, 0.0],
      ],
      documentationChecklistJson: RoomDocumentationChecklist(
        hiddenWorksConfirmed: {'hw_floor': true},
      ).toJson(),
    );
    final project = Project(id: 1, name: 'Obj', rooms: [room]);
    final doc = ProjectDocumentation(enabledWorkScopes: ['floor']);
    final summary = roomClosureStatusSummary(project: project, room: room, doc: doc);
    expect(summary.compactLabel, contains('Пол !'));
    expect(roomClosureStatusLegend(), contains('готово'));
  });

  test('initialSelectedRoomIds selects all ready rooms by default', () {
    expect(initialSelectedRoomIds(readyIds: {1, 2, 3}, focusRoomId: 9), {1, 2, 3});
    expect(initialSelectedRoomIds(readyIds: {1, 2, 3}, focusRoomId: 2), {1, 2, 3});
    expect(initialSelectedRoomIds(readyIds: {1, 2, 3}), {1, 2, 3});
  });

  test('KS-3 same-scope previous period and cumulative to periodTo', () {
    final acts = [
      Ks2ActRecord(
        id: '1',
        actNumber: 1,
        scope: 'floor',
        roomIds: [1],
        roomNames: ['101'],
        totalAmount: 100000,
        createdAt: DateTime(2026, 1, 15),
      ),
      Ks2ActRecord(
        id: '2',
        actNumber: 2,
        scope: 'floor',
        roomIds: [2],
        roomNames: ['102'],
        totalAmount: 50000,
        createdAt: DateTime(2026, 2, 10),
      ),
      Ks2ActRecord(
        id: '3',
        actNumber: 3,
        scope: 'walls',
        roomIds: [1],
        roomNames: ['101'],
        totalAmount: 200000,
        createdAt: DateTime(2026, 3, 5),
      ),
    ];
    final feb = buildKs3LedgerRows(
      acts: acts,
      periodFrom: DateTime(2026, 2, 1),
      periodTo: DateTime(2026, 2, 28),
    );
    expect(feb.length, 1);
    expect(feb[0].scopeKey, 'floor');
    expect(feb[0].previousSum, 100000);
    expect(feb[0].periodSum, 50000);
    expect(feb[0].cumulativeSum, 150000);

    final jan = buildKs3LedgerRows(
      acts: acts,
      periodFrom: DateTime(2026, 1, 1),
      periodTo: DateTime(2026, 1, 31),
    );
    expect(jan.single.periodSum, 100000);
    expect(jan.single.previousSum, 0);
    expect(jan.single.cumulativeSum, 100000);
  });
}
