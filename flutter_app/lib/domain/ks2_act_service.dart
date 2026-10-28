import 'act_export.dart';
import 'cost_calculator.dart';
import 'documentation_model.dart';
import 'ks2_work_scope.dart';
import 'models.dart';
import 'room_finish_areas.dart';

List<Ks2ActRecord> activeKs2Acts(List<Ks2ActRecord> acts) =>
    acts.where((a) => a.status != Ks2ActStatus.cancelled).toList();

/// Rooms eligible for a scoped KS-2: hidden work done, not yet closed for this scope.
List<Room> roomsReadyForScopedKs2({
  required Project project,
  required ProjectDocumentation doc,
  required WorkScope scope,
  required List<Ks2ActRecord> acts,
}) {
  if (!projectEnabledWorkScopes(doc).contains(scope)) return const [];
  final active = activeKs2Acts(acts);
  final closedRoomIds = closedRoomIdsForScope(active, scope);
  final out = <Room>[];
  for (final room in project.rooms) {
    if (room.id == null || !roomHasFinishGeometry(room)) continue;
    if (closedRoomIds.contains(room.id)) continue;
    final cl = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
    if (isRoomScopeReady(room, project, scope, cl)) out.add(room);
  }
  return out;
}

/// Rooms ready for a combined scope set (e.g. floor + walls).
List<Room> roomsReadyForMultiScopeKs2({
  required Project project,
  required ProjectDocumentation doc,
  required List<WorkScope> scopes,
  required List<Ks2ActRecord> acts,
}) {
  if (scopes.isEmpty) return const [];
  final active = activeKs2Acts(acts);
  final out = <Room>[];
  for (final room in project.rooms) {
    if (room.id == null || !roomHasFinishGeometry(room)) continue;
    final cl = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
    if (!isRoomMultiScopeReady(room, project, scopes, cl)) continue;
    var blocked = false;
    for (final scope in scopes) {
      if (closedRoomIdsForScope(active, scope).contains(room.id)) {
        blocked = true;
        break;
      }
    }
    if (!blocked) out.add(room);
  }
  return out;
}

Set<int> closedRoomIdsForScope(List<Ks2ActRecord> acts, WorkScope scope) {
  final out = <int>{};
  for (final act in activeKs2Acts(acts)) {
    if (!actScopeCovers(act.scope, scope)) continue;
    out.addAll(act.roomIds);
  }
  return out;
}

bool isRoomScopeClosed({
  required int roomId,
  required WorkScope scope,
  required List<Ks2ActRecord> acts,
}) =>
    closedRoomIdsForScope(acts, scope).contains(roomId);

WorkScope? suggestScopeAfterStep({
  required Project project,
  required ProjectDocumentation doc,
  required Room room,
  required String stepId,
  required List<Ks2ActRecord> acts,
}) {
  final scope = WorkScope.forHiddenStepId(stepId);
  if (scope == null || room.id == null) return null;
  if (!projectEnabledWorkScopes(doc).contains(scope)) return null;
  if (isRoomScopeClosed(roomId: room.id!, scope: scope, acts: acts)) return null;
  final cl = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
  if (!isRoomScopeReady(room, project, scope, cl)) return null;
  return scope;
}

Map<String, double> computeScopeBreakdown({
  required Project project,
  required List<Room> rooms,
  required List<WorkScope> scopes,
  Map<String, SupplierPrice>? prices,
}) {
  final map = <String, double>{};
  for (final scope in scopes) {
    final sum = ks2ProjectScopedTotal(
      project: project,
      rooms: rooms,
      scopes: [scope],
      prices: prices,
    );
    if (sum > 0) map[scope.name] = sum;
  }
  return map;
}

Ks2ActRecord registerKs2Act({
  required ProjectDocumentation doc,
  required List<WorkScope> scopes,
  required List<Room> rooms,
  required double totalAmount,
  Map<String, double>? scopeBreakdown,
  String? exportPath,
  String? amendedFromId,
  String notes = '',
}) {
  final actNumber = doc.allocateActNumber();
  final scopeKey = WorkScope.encodeKey(scopes);
  final record = Ks2ActRecord(
    id: '${DateTime.now().millisecondsSinceEpoch}_$actNumber',
    actNumber: actNumber,
    scope: scopeKey,
    roomIds: rooms.map((r) => r.id!).where((id) => id > 0).toList(),
    roomNames: rooms.map((r) => r.name).toList(),
    totalAmount: totalAmount,
    createdAt: DateTime.now(),
    exportPath: exportPath,
    amendedFromId: amendedFromId,
    notes: notes,
    scopeBreakdown: scopeBreakdown ?? {},
  );
  doc.ks2Acts.add(record);
  return record;
}

void cancelKs2Act(ProjectDocumentation doc, String actId, {String reason = ''}) {
  final idx = doc.ks2Acts.indexWhere((a) => a.id == actId);
  if (idx < 0) return;
  final act = doc.ks2Acts[idx];
  doc.ks2Acts[idx] = Ks2ActRecord(
    id: act.id,
    actNumber: act.actNumber,
    scope: act.scope,
    roomIds: act.roomIds,
    roomNames: act.roomNames,
    totalAmount: act.totalAmount,
    createdAt: act.createdAt,
    status: Ks2ActStatus.cancelled,
    exportPath: act.exportPath,
    notes: reason.isEmpty ? act.notes : reason,
    amendedFromId: act.amendedFromId,
    scopeBreakdown: act.scopeBreakdown,
  );
}

/// Permanently removes an act from the registry (rooms can be closed again).
bool deleteKs2Act(ProjectDocumentation doc, String actId) {
  final before = doc.ks2Acts.length;
  doc.ks2Acts.removeWhere((a) => a.id == actId);
  return doc.ks2Acts.length < before;
}

Ks2ActRecord amendKs2ActAmount({
  required ProjectDocumentation doc,
  required String actId,
  required double newAmount,
  String note = '',
}) {
  final idx = doc.ks2Acts.indexWhere((a) => a.id == actId);
  if (idx < 0) throw StateError('act not found');
  final act = doc.ks2Acts[idx];
  var maxN = 0;
  for (final a in doc.ks2Acts) {
    if (a.actNumber > maxN) maxN = a.actNumber;
  }
  if (doc.nextActNumber <= maxN) doc.nextActNumber = maxN + 1;
  final newNumber = doc.allocateActNumber();
  cancelKs2Act(
    doc,
    actId,
    reason: 'Заменён актом № $newNumber. Было ${act.totalAmount.toStringAsFixed(2)} ₽'
        '${note.isNotEmpty ? '. $note' : ''}',
  );
  var breakdown = Map<String, double>.from(act.scopeBreakdown);
  if (act.totalAmount > 0 && breakdown.isNotEmpty && newAmount != act.totalAmount) {
    final k = newAmount / act.totalAmount;
    breakdown = breakdown.map((key, v) => MapEntry(key, v * k));
  }
  final replacement = Ks2ActRecord(
    id: '${DateTime.now().millisecondsSinceEpoch}_$newNumber',
    actNumber: newNumber,
    scope: act.scope,
    roomIds: act.roomIds,
    roomNames: act.roomNames,
    totalAmount: newAmount,
    createdAt: DateTime.now(),
    status: Ks2ActStatus.issued,
    notes: note,
    amendedFromId: act.id,
    scopeBreakdown: breakdown,
  );
  doc.ks2Acts.add(replacement);
  return replacement;
}

class Ks3LedgerRow {
  const Ks3LedgerRow({
    required this.scopeKey,
    required this.scopeLabel,
    required this.cumulativeSum,
    required this.previousSum,
    required this.periodSum,
    required this.roomNames,
  });

  final String scopeKey;
  final String scopeLabel;
  final double cumulativeSum;
  final double previousSum;
  final double periodSum;
  final List<String> roomNames;
}

DateTime ks3PeriodStart(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime ks3PeriodEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

bool actFallsInKs3Period(DateTime created, DateTime periodFrom, DateTime periodTo) =>
    !created.isBefore(ks3PeriodStart(periodFrom)) && !created.isAfter(ks3PeriodEnd(periodTo));

/// Rooms pre-checked on the close tab.
/// Default: all ready. Optional [focusRoomId] only highlights; still selects all.
Set<int> initialSelectedRoomIds({
  required Iterable<int> readyIds,
  int? focusRoomId,
}) {
  final ready = readyIds.toSet();
  if (focusRoomId != null && !ready.contains(focusRoomId)) {
    // Focus room not closable yet — still offer the rest of the object.
    return ready;
  }
  return ready;
}

List<Ks3LedgerRow> buildKs3LedgerRows({
  required List<Ks2ActRecord> acts,
  required DateTime periodFrom,
  required DateTime periodTo,
}) {
  final sorted = activeKs2Acts(acts)..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final from = ks3PeriodStart(periodFrom);
  final to = ks3PeriodEnd(periodTo);

  final cumulativeByKey = <String, double>{};
  final previousByKey = <String, double>{};
  final periodByKey = <String, double>{};
  final roomsByKey = <String, Set<String>>{};
  final labelByKey = <String, String>{};

  for (final act in sorted) {
    if (act.createdAt.isAfter(to)) continue;
    final inPeriod = actFallsInKs3Period(act.createdAt, periodFrom, periodTo);

    void addAmount(String key, String label, double amount) {
      cumulativeByKey[key] = (cumulativeByKey[key] ?? 0) + amount;
      labelByKey[key] = label;
      if (inPeriod) {
        periodByKey[key] = (periodByKey[key] ?? 0) + amount;
        roomsByKey.putIfAbsent(key, () => {}).addAll(act.roomNames);
      } else if (act.createdAt.isBefore(from)) {
        previousByKey[key] = (previousByKey[key] ?? 0) + amount;
      }
    }

    if (act.scopeBreakdown.isNotEmpty) {
      for (final e in act.scopeBreakdown.entries) {
        addAmount(e.key, WorkScope.parse(e.key)?.labelRu ?? e.key, e.value);
      }
    } else {
      final scopes = parseScopeKey(act.scope);
      if (scopes.length == 1) {
        addAmount(scopes.first.name, scopes.first.labelRu, act.totalAmount);
      } else if (scopes.isNotEmpty) {
        addAmount(act.scope, scopeKeyLabel(act.scope), act.totalAmount);
      }
    }
  }

  final keys = cumulativeByKey.keys.toList()
    ..sort((a, b) {
      int order(String k) {
        final scopes = parseScopeKey(k);
        if (scopes.isEmpty) return 99;
        return scopes.first.index;
      }

      final o = order(a).compareTo(order(b));
      if (o != 0) return o;
      return a.compareTo(b);
    });

  final rows = <Ks3LedgerRow>[];
  for (final key in keys) {
    final cumulative = cumulativeByKey[key] ?? 0;
    if (cumulative <= 0) continue;
    rows.add(Ks3LedgerRow(
      scopeKey: key,
      scopeLabel: labelByKey[key] ?? scopeKeyLabel(key),
      cumulativeSum: cumulative,
      previousSum: previousByKey[key] ?? 0,
      periodSum: periodByKey[key] ?? 0,
      roomNames: (roomsByKey[key] ?? {}).toList()..sort(),
    ));
  }
  return rows;
}

double ledgerContractTotal(List<Ks2ActRecord> acts) {
  var total = 0.0;
  for (final act in activeKs2Acts(acts)) {
    total += act.totalAmount;
  }
  return total;
}

Map<WorkScope, int> countRoomsReadyToCloseMap({
  required Project project,
  required ProjectDocumentation doc,
}) {
  final acts = activeKs2Acts(doc.ks2Acts);
  final out = <WorkScope, int>{};
  for (final scope in projectActiveWorkScopes(project: project, doc: doc)) {
    out[scope] = roomsReadyForScopedKs2(
      project: project,
      doc: doc,
      scope: scope,
      acts: acts,
    ).length;
  }
  return out;
}

List<(WorkScope, int)> ks2ClosureAlerts(Project project) {
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  return countRoomsReadyToCloseMap(project: project, doc: doc)
      .entries
      .where((e) => e.value > 0)
      .map((e) => (e.key, e.value))
      .toList();
}
