import 'documentation_model.dart';
import 'ks2_act_service.dart';
import 'ks2_work_scope.dart';
import 'models.dart';
import 'room_documentation_status.dart';
import 'room_finish_areas.dart';

enum RoomScopeClosureState {
  notInContract,
  notApplicable,
  inProgress,
  ready,
  closed,
  paid,
}

extension RoomScopeClosureStateX on RoomScopeClosureState {
  String get shortGlyph => switch (this) {
        RoomScopeClosureState.notInContract => '—',
        RoomScopeClosureState.notApplicable => '·',
        RoomScopeClosureState.inProgress => '…',
        RoomScopeClosureState.ready => '!',
        RoomScopeClosureState.closed => '✓',
        RoomScopeClosureState.paid => '₽',
      };

  String get legendHint => switch (this) {
        RoomScopeClosureState.notInContract => 'нет в договоре',
        RoomScopeClosureState.notApplicable => 'не применяется',
        RoomScopeClosureState.inProgress => 'в работе',
        RoomScopeClosureState.ready => 'готово к закрытию',
        RoomScopeClosureState.closed => 'закрыто КС-2',
        RoomScopeClosureState.paid => 'оплачено',
      };
}

String roomClosureStatusLegend() =>
    '… в работе · ! готово · ✓ закрыто · ₽ оплачено';

/// True when every applicable contract scope for this room is closed or paid in KS-2.
bool isRoomHandedOverByClosingDocs({
  required Project project,
  required Room room,
  required ProjectDocumentation doc,
}) {
  if (room.id == null || !roomHasFinishGeometry(room)) return false;
  final summary = roomClosureStatusSummary(project: project, room: room, doc: doc);
  final applicable = summary.byScope.entries.where(
    (e) =>
        e.value != RoomScopeClosureState.notInContract &&
        e.value != RoomScopeClosureState.notApplicable,
  );
  if (applicable.isEmpty) return false;
  return applicable.every(
    (e) =>
        e.value == RoomScopeClosureState.closed ||
        e.value == RoomScopeClosureState.paid,
  );
}

/// Per-room closure summary for dashboard chips.
class RoomClosureStatusSummary {
  const RoomClosureStatusSummary({
    required this.byScope,
    required this.compactLabel,
  });

  final Map<WorkScope, RoomScopeClosureState> byScope;
  final String compactLabel;
}

RoomClosureStatusSummary roomClosureStatusSummary({
  required Project project,
  required Room room,
  required ProjectDocumentation doc,
}) {
  final cl = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
  final acts = activeKs2Acts(doc.ks2Acts);
  final enabled = projectEnabledWorkScopes(doc);
  final byScope = <WorkScope, RoomScopeClosureState>{};

  for (final scope in WorkScope.values) {
    if (!enabled.contains(scope)) {
      byScope[scope] = RoomScopeClosureState.notInContract;
      continue;
    }
    if (!isScopeApplicableToRoom(room, project, scope)) {
      byScope[scope] = RoomScopeClosureState.notApplicable;
      continue;
    }
    final paid = acts.any(
      (a) =>
          a.status == Ks2ActStatus.paid &&
          actScopeCovers(a.scope, scope) &&
          a.roomIds.contains(room.id),
    );
    if (paid) {
      byScope[scope] = RoomScopeClosureState.paid;
      continue;
    }
    if (isRoomScopeClosed(roomId: room.id!, scope: scope, acts: acts)) {
      byScope[scope] = RoomScopeClosureState.closed;
      continue;
    }
    if (isRoomScopeReady(room, project, scope, cl)) {
      byScope[scope] = RoomScopeClosureState.ready;
      continue;
    }
    byScope[scope] = RoomScopeClosureState.inProgress;
  }

  final parts = <String>[];
  for (final scope in enabled) {
    final st = byScope[scope];
    if (st == null ||
        st == RoomScopeClosureState.notApplicable ||
        st == RoomScopeClosureState.notInContract) {
      continue;
    }
    parts.add('${scope.labelRu} ${st.shortGlyph}');
  }
  return RoomClosureStatusSummary(
    byScope: byScope,
    compactLabel: parts.isEmpty ? 'закрытие не настроено' : parts.join(' · '),
  );
}

/// Project-level: how many rooms are ready to close per scope.
Map<WorkScope, int> countRoomsReadyToClose({
  required Project project,
  required ProjectDocumentation doc,
}) =>
    countRoomsReadyToCloseMap(project: project, doc: doc);
